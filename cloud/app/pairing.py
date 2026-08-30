"""Device-to-device guardian pairing backed by MongoDB.

The protected (elderly) phone shows a short alphanumeric code. A guardian phone
enters that code to link the two devices. MongoDB enforces exclusivity: a code
binds to exactly one guardian device, and danger reports are scoped to the pair,
so one guardian can never read another pair's reports.

When a danger report arrives, an n8n webhook is fired so the guardian gets a
real-time alert through whatever channel their workflow uses (no SMS/DLT needed).
"""

from __future__ import annotations

import hashlib
import hmac
import os
import secrets
import threading
from datetime import UTC, datetime, timedelta

import httpx

try:
    from pymongo import ASCENDING, MongoClient
    from pymongo.errors import PyMongoError
except ImportError:  # pragma: no cover - driver always present in the container
    MongoClient = None  # type: ignore
    PyMongoError = Exception  # type: ignore

# Unambiguous code alphabet (no O/0/I/1) for phone-to-phone reading.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 6
PAIRING_TTL_DAYS = 30
SESSION_TTL_DAYS = 30
REPORT_TTL_DAYS = 7


def _now() -> datetime:
    return datetime.now(UTC)


def _code() -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))


class PairingError(Exception):
    """Raised for expected pairing failures (bad/used code, no pairing)."""


class GuardianAlertGateway:
    """Fires an n8n webhook so the guardian is alerted. Fail-open."""

    def __init__(self) -> None:
        self.url = os.getenv("N8N_WEBHOOK_URL", "").strip()
        self.secret = os.getenv("N8N_WEBHOOK_SECRET", "").strip()

    @property
    def configured(self) -> bool:
        return bool(self.url and self.secret)

    def notify(self, payload: dict[str, object]) -> str:
        if not self.configured:
            return "skipped"
        try:
            with httpx.Client(timeout=10.0) as client:
                response = client.post(
                    self.url,
                    json=payload,
                    headers={"X-Kavasam-Webhook-Secret": self.secret},
                )
                response.raise_for_status()
            return "delivered"
        except httpx.HTTPError:
            return "pending"


class PairingStore:
    def __init__(
        self,
        uri: str | None = None,
        database: str | None = None,
        token_secret: str | None = None,
        gateway: GuardianAlertGateway | None = None,
    ) -> None:
        self._uri = uri if uri is not None else os.getenv("MONGODB_URI", "").strip()
        self._db_name = database or os.getenv("MONGODB_DATABASE", "kavasam")
        self._secret = (
            token_secret or os.getenv("NUMBER_HMAC_SECRET", "development-only-secret")
        ).encode()
        self._gateway = gateway or GuardianAlertGateway()
        self._lock = threading.RLock()
        self._client = None
        self._ready = False
        if self._uri and MongoClient is not None:
            try:
                # tz_aware so stored datetimes come back as UTC-aware and
                # compare cleanly with datetime.now(UTC).
                self._client = MongoClient(
                    self._uri, serverSelectionTimeoutMS=8000, tz_aware=True
                )
                self._pairings.create_index([("code", ASCENDING)], unique=True)
                self._pairings.create_index([("elderlyDeviceId", ASCENDING)], unique=True)
                self._pairings.create_index([("sessionTokenHash", ASCENDING)])
                self._events.create_index([("pairingId", ASCENDING), ("occurredAt", ASCENDING)])
                self._ready = True
            except PyMongoError:
                self._ready = False

    @property
    def configured(self) -> bool:
        return self._ready

    @property
    def _db(self):
        return self._client[self._db_name]

    @property
    def _pairings(self):
        return self._db["guardian_pairings"]

    @property
    def _events(self):
        return self._db["guardian_pair_events"]

    def _require(self) -> None:
        if not self._ready:
            raise PairingError("Guardian pairing storage is not available.")

    def _hash(self, value: str) -> str:
        return hmac.new(self._secret, value.encode(), hashlib.sha256).hexdigest()

    @staticmethod
    def _protected_view(pairing: dict[str, object]) -> dict[str, object]:
        status = str(pairing.get("status", "open"))
        return {
            "status": status,
            "code": str(pairing.get("code", "")),
            "guardianAlias": str(pairing.get("guardianAlias") or ""),
        }

    # -- Protected (elderly) side ------------------------------------------

    def code_for(self, elderly_device_id: str, alias: str) -> dict[str, object]:
        """Returns the device's active pairing code, creating one if needed."""
        self._require()
        now = _now()
        with self._lock:
            existing = self._pairings.find_one({"elderlyDeviceId": elderly_device_id})
            if existing and existing["expiresAt"] > now:
                self._pairings.update_one(
                    {"_id": existing["_id"]},
                    {"$set": {"alias": alias or existing.get("alias", "Protected user")}},
                )
                return self._protected_view(self._pairings.find_one({"_id": existing["_id"]}))
            if existing:
                self._events.delete_many({"pairingId": str(existing["_id"])})
                self._pairings.delete_one({"_id": existing["_id"]})
            code = _code()
            while self._pairings.find_one({"code": code}):
                code = _code()
            document = {
                "code": code,
                "elderlyDeviceId": elderly_device_id,
                "alias": alias or "Protected user",
                "guardianDeviceId": None,
                "guardianAlias": None,
                "alertHandle": None,
                "sessionTokenHash": None,
                "status": "open",
                "createdAt": now,
                "expiresAt": now + timedelta(days=PAIRING_TTL_DAYS),
            }
            result = self._pairings.insert_one(document)
            document["_id"] = result.inserted_id
            return self._protected_view(document)

    def status_for(self, elderly_device_id: str) -> dict[str, object]:
        self._require()
        pairing = self._pairings.find_one({"elderlyDeviceId": elderly_device_id})
        if pairing is None:
            return {"status": "none", "code": "", "guardianAlias": ""}
        return self._protected_view(pairing)

    def unpair(self, elderly_device_id: str) -> dict[str, object]:
        self._require()
        with self._lock:
            pairing = self._pairings.find_one({"elderlyDeviceId": elderly_device_id})
            if pairing is not None:
                self._events.delete_many({"pairingId": str(pairing["_id"])})
                self._pairings.delete_one({"_id": pairing["_id"]})
        return {"status": "none", "code": "", "guardianAlias": ""}

    # -- Guardian side ------------------------------------------------------

    def claim(
        self,
        code: str,
        guardian_device_id: str,
        guardian_alias: str,
        alert_handle: str,
    ) -> dict[str, object]:
        self._require()
        now = _now()
        normalized = code.strip().upper()
        with self._lock:
            pairing = self._pairings.find_one({"code": normalized})
            if pairing is None or pairing["expiresAt"] <= now:
                raise PairingError("That code is invalid or has expired.")
            linked = pairing.get("guardianDeviceId")
            if linked and linked != guardian_device_id:
                raise PairingError("That code is already linked to another guardian.")
            raw_token = secrets.token_urlsafe(36)
            self._pairings.update_one(
                {"_id": pairing["_id"]},
                {
                    "$set": {
                        "guardianDeviceId": guardian_device_id,
                        "guardianAlias": guardian_alias or "Guardian",
                        "alertHandle": alert_handle.strip(),
                        "sessionTokenHash": self._hash(raw_token),
                        "status": "linked",
                        "linkedAt": now,
                        "sessionExpiresAt": now + timedelta(days=SESSION_TTL_DAYS),
                    }
                },
            )
            return {
                "pairingId": str(pairing["_id"]),
                "sessionToken": raw_token,
                "elderlyAlias": pairing.get("alias", "Protected user"),
                "expiresAt": now + timedelta(days=SESSION_TTL_DAYS),
            }

    def reports_for(self, session_token: str) -> dict[str, object]:
        self._require()
        now = _now()
        pairing = self._pairings.find_one({"sessionTokenHash": self._hash(session_token)})
        if pairing is None or pairing.get("sessionExpiresAt", now) <= now:
            raise PairingError("Guardian session is invalid or expired.")
        cutoff = now - timedelta(days=REPORT_TTL_DAYS)
        self._events.delete_many({"occurredAt": {"$lt": cutoff}})
        rows = (
            self._events.find({"pairingId": str(pairing["_id"])})
            .sort("occurredAt", -1)
            .limit(100)
        )
        reports = [
            {
                "reportId": row["reportId"],
                "primaryAlias": pairing.get("alias", "Protected user"),
                "callerLast4": row.get("callerLast4", ""),
                "occurredAt": row["occurredAt"],
                "risk": row["risk"],
                "riskLabel": row.get("riskLabel", "Dangerous"),
                "summary": row.get("summary", ""),
                "signals": row.get("signals", []),
            }
            for row in rows
        ]
        return {"elderlyAlias": pairing.get("alias", "Protected user"), "reports": reports}

    # -- Danger report ingestion -------------------------------------------

    def submit_report(self, elderly_device_id: str, report: dict[str, object]) -> str:
        self._require()
        now = _now()
        with self._lock:
            pairing = self._pairings.find_one({"elderlyDeviceId": elderly_device_id})
            if pairing is None:
                raise PairingError("This phone has not generated a guardian code yet.")
            report_id = str(report["reportId"])
            if self._events.find_one({"pairingId": str(pairing["_id"]), "reportId": report_id}):
                return "duplicate"
            self._events.insert_one(
                {
                    "pairingId": str(pairing["_id"]),
                    "reportId": report_id,
                    "callerLast4": str(report.get("callerLast4", ""))[:4],
                    "risk": int(report.get("risk", 0)),
                    "riskLabel": str(report.get("riskLabel", "Dangerous"))[:40],
                    "summary": str(report.get("summary", ""))[:360],
                    "signals": list(report.get("signals", []))[:6],
                    "occurredAt": now,
                }
            )
        if not pairing.get("guardianDeviceId"):
            return "stored"
        delivery = self._gateway.notify(
            {
                "event": "guardian_alert",
                "to": pairing.get("alertHandle") or "",
                "reference": report_id,
                "guardianAlias": pairing.get("guardianAlias") or "Guardian",
                "message": (
                    f"Kavasam danger alert for {pairing.get('alias', 'your family member')}: "
                    f"a call ending {str(report.get('callerLast4', '')) or '----'} scored "
                    f"{int(report.get('risk', 0))}/100. Open the Kavasam Guardian tab."
                ),
            }
        )
        return delivery


def protected_status_message(status: str) -> str:
    return {
        "none": "No guardian code has been generated yet.",
        "open": "Share this code with your guardian to link their phone.",
        "linked": "A guardian is linked and will receive danger alerts.",
    }.get(status, "")
