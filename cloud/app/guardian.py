from __future__ import annotations

import hashlib
import hmac
import os
import re
import secrets
import sqlite3
import threading
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import httpx

from .schemas import (
    GuardianApprovalRequest,
    GuardianApprovalResponse,
    GuardianClaimRequest,
    GuardianClaimResponse,
    GuardianEnrollmentRequest,
    GuardianEnrollmentResponse,
    GuardianReportItem,
    GuardianReportList,
    GuardianReportRequest,
    GuardianReportResponse,
    GuardianReplyResponse,
)


ACCEPT_WORDS = {"ACCEPT", "YES", "Y", "OK", "APPROVE"}
REJECT_WORDS = {"REJECT", "NO", "N", "DENY", "CANCEL"}


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _normalize_phone(value: str) -> str:
    prefix = "+" if value.strip().startswith("+") else ""
    return prefix + "".join(character for character in value if character.isdigit())


def _parse_reply(value: str) -> tuple[str | None, str | None]:
    words = re.findall(r"[A-Z]+|[0-9]{4}", value.upper())
    decision = next(
        (
            "approved" if word in ACCEPT_WORDS else "rejected"
            for word in words
            if word in ACCEPT_WORDS or word in REJECT_WORDS
        ),
        None,
    )
    ref_code = next((word for word in words if word.isdigit() and len(word) == 4), None)
    return decision, ref_code


class GuardianGateway:
    def __init__(self) -> None:
        self.url = os.getenv("N8N_WEBHOOK_URL", "").strip()
        self.secret = os.getenv("N8N_WEBHOOK_SECRET", "").strip()
        self.public_base_url = (
            os.getenv("PUBLIC_BASE_URL", "") or os.getenv("RENDER_EXTERNAL_URL", "")
        ).strip().rstrip("/")

    @property
    def configured(self) -> bool:
        return bool(self.url and self.secret and self.public_base_url.startswith("https://"))

    def send(self, payload: dict[str, object]) -> None:
        if not self.configured:
            raise RuntimeError(
                "Guardian SMS is not configured. Set N8N_WEBHOOK_URL, "
                "N8N_WEBHOOK_SECRET, and PUBLIC_BASE_URL."
            )
        with httpx.Client(timeout=10.0) as client:
            response = client.post(
                self.url,
                json=payload
                | {"replyWebhookUrl": f"{self.public_base_url}/v1/guardian/reply"},
                headers={"X-Kavasam-Webhook-Secret": self.secret},
            )
            response.raise_for_status()


class GuardianApprovalStore:
    def __init__(
        self,
        path: str | None = None,
        token_secret: str | None = None,
        gateway: GuardianGateway | None = None,
        approval_ttl_seconds: int = 300,
    ) -> None:
        database_path = path or os.getenv("KAVASAM_DB_PATH", "/tmp/kavasam.db")
        if database_path != ":memory:":
            Path(database_path).parent.mkdir(parents=True, exist_ok=True)
        self._connection = sqlite3.connect(database_path, check_same_thread=False)
        self._connection.row_factory = sqlite3.Row
        self._lock = threading.RLock()
        self._secret = (
            token_secret or os.getenv("NUMBER_HMAC_SECRET", "development-only-secret")
        ).encode()
        self._gateway = gateway or GuardianGateway()
        self._approval_ttl = timedelta(seconds=max(60, approval_ttl_seconds))
        self._enrollment_ttl = timedelta(hours=24)
        self._guardian_session_ttl = timedelta(days=30)
        self._create_schema()

    @property
    def configured(self) -> bool:
        return self._gateway.configured

    def close(self) -> None:
        self._connection.close()

    def _create_schema(self) -> None:
        with self._connection:
            self._connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS guardians (
                    id TEXT PRIMARY KEY,
                    device_id TEXT NOT NULL,
                    primary_alias TEXT NOT NULL DEFAULT 'Protected user',
                    phone_token TEXT NOT NULL,
                    ref_code TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    verified_at TEXT
                );
                CREATE INDEX IF NOT EXISTS guardians_phone_status
                    ON guardians(phone_token, status);
                CREATE TABLE IF NOT EXISTS guardian_approvals (
                    id TEXT PRIMARY KEY,
                    guardian_id TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    call_session_id TEXT NOT NULL,
                    ref_code TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    responded_at TEXT,
                    UNIQUE(device_id, call_session_id)
                );
                CREATE INDEX IF NOT EXISTS approvals_guardian_status
                    ON guardian_approvals(guardian_id, status);
                CREATE TABLE IF NOT EXISTS guardian_sessions (
                    token_hash TEXT PRIMARY KEY,
                    guardian_id TEXT NOT NULL,
                    guardian_device_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS guardian_sessions_guardian
                    ON guardian_sessions(guardian_id, expires_at);
                CREATE TABLE IF NOT EXISTS guardian_reports (
                    id TEXT PRIMARY KEY,
                    guardian_id TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    call_session_id TEXT NOT NULL,
                    caller_last4 TEXT NOT NULL,
                    occurred_at TEXT NOT NULL,
                    risk INTEGER NOT NULL,
                    risk_label TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    signals TEXT NOT NULL,
                    delivery_status TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS guardian_reports_guardian_time
                    ON guardian_reports(guardian_id, occurred_at DESC);
                """
            )
            columns = {
                row[1] for row in self._connection.execute("PRAGMA table_info(guardians)")
            }
            if "primary_alias" not in columns:
                self._connection.execute(
                    "ALTER TABLE guardians ADD COLUMN primary_alias TEXT NOT NULL "
                    "DEFAULT 'Protected user'"
                )

    def _token(self, phone: str) -> str:
        return hmac.new(
            self._secret,
            _normalize_phone(phone).encode(),
            hashlib.sha256,
        ).hexdigest()

    def _session_token(self, value: str) -> str:
        return hmac.new(
            self._secret,
            f"guardian-session:{value}".encode(),
            hashlib.sha256,
        ).hexdigest()

    @staticmethod
    def _ref_code() -> str:
        return f"{secrets.randbelow(10_000):04d}"

    def enroll(self, event: GuardianEnrollmentRequest) -> GuardianEnrollmentResponse:
        if not self.configured:
            raise RuntimeError("Guardian SMS gateway is not configured.")
        now = _utc_now()
        expires = now + self._enrollment_ttl
        enrollment_id = uuid4()
        ref_code = self._ref_code()
        with self._lock, self._connection:
            self._expire(now)
            self._connection.execute(
                "UPDATE guardians SET status = 'expired' "
                "WHERE device_id = ? AND status = 'pending'",
                (str(event.deviceId),),
            )
            self._connection.execute(
                """
                INSERT INTO guardians(
                    id, device_id, primary_alias, phone_token, ref_code, status,
                    created_at, expires_at, verified_at
                ) VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, NULL)
                """,
                (
                    str(enrollment_id),
                    str(event.deviceId),
                    event.primaryAlias,
                    self._token(event.guardianPhone),
                    ref_code,
                    now.isoformat(),
                    expires.isoformat(),
                ),
            )
        try:
            self._gateway.send(
                {
                    "event": "guardian_enrollment",
                    "to": _normalize_phone(event.guardianPhone),
                    "reference": ref_code,
                    "message": (
                        f"Kavasam: {event.primaryAlias} wants you as their call-safety guardian. "
                        f"Reply JOIN #{ref_code} or enter code {ref_code} in the Kavasam "
                        "Guardian tab to opt in. Expires in 24 hours."
                    ),
                }
            )
        except Exception:
            with self._lock, self._connection:
                self._connection.execute(
                    "UPDATE guardians SET status = 'expired' WHERE id = ?",
                    (str(enrollment_id),),
                )
            raise
        return GuardianEnrollmentResponse(
            enrollmentId=enrollment_id,
            status="pending",
            expiresAt=expires,
            delivery="n8n",
            message="Opt-in sent. Ask your guardian to reply JOIN with the reference code.",
        )

    def claim_relationship(self, event: GuardianClaimRequest) -> GuardianClaimResponse:
        now = _utc_now()
        expires = now + self._guardian_session_ttl
        phone_token = self._token(event.guardianPhone)
        raw_token = secrets.token_urlsafe(36)
        with self._lock, self._connection:
            self._expire(now)
            rows = self._connection.execute(
                """
                SELECT * FROM guardians
                WHERE phone_token = ? AND ref_code = ?
                  AND status IN ('pending', 'verified')
                ORDER BY created_at DESC
                """,
                (phone_token, event.referenceCode),
            ).fetchall()
            if len(rows) != 1:
                raise PermissionError("The guardian phone and reference code did not match.")
            guardian = rows[0]
            if guardian["status"] == "pending":
                self._connection.execute(
                    "UPDATE guardians SET status = 'verified', verified_at = ? WHERE id = ?",
                    (now.isoformat(), guardian["id"]),
                )
            self._connection.execute(
                "DELETE FROM guardian_sessions WHERE guardian_device_id = ?",
                (str(event.guardianDeviceId),),
            )
            self._connection.execute(
                "INSERT INTO guardian_sessions VALUES (?, ?, ?, ?, ?)",
                (
                    self._session_token(raw_token),
                    guardian["id"],
                    str(event.guardianDeviceId),
                    now.isoformat(),
                    expires.isoformat(),
                ),
            )
        return GuardianClaimResponse(
            guardianId=UUID(guardian["id"]),
            sessionToken=raw_token,
            primaryAlias=guardian["primary_alias"],
            expiresAt=expires,
            message=(
                f"Guardian relationship activated for {guardian['primary_alias']}. "
                "Dangerous-call reports will appear in this tab."
            ),
        )

    def submit_report(self, event: GuardianReportRequest) -> GuardianReportResponse:
        now = _utc_now()
        with self._lock, self._connection:
            guardian = self._connection.execute(
                """
                SELECT * FROM guardians
                WHERE id = ? AND device_id = ? AND status = 'verified'
                """,
                (str(event.guardianId), str(event.deviceId)),
            ).fetchone()
            if guardian is None or not hmac.compare_digest(
                guardian["phone_token"], self._token(event.guardianPhone)
            ):
                raise PermissionError("Guardian is not verified for this device.")
            existing = self._connection.execute(
                "SELECT delivery_status FROM guardian_reports WHERE id = ?",
                (str(event.reportId),),
            ).fetchone()
            if existing is None:
                self._connection.execute(
                    """
                    INSERT INTO guardian_reports VALUES (
                        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'stored', ?
                    )
                    """,
                    (
                        str(event.reportId),
                        str(event.guardianId),
                        str(event.deviceId),
                        str(event.callSessionId),
                        event.callerLast4,
                        event.occurredAt.isoformat(),
                        event.risk,
                        event.riskLabel,
                        event.summary,
                        ",".join(event.signals),
                        now.isoformat(),
                    ),
                )
            elif existing["delivery_status"] == "delivered":
                return GuardianReportResponse(
                    reportId=event.reportId,
                    status="delivered",
                    message="The dangerous-call report was already delivered.",
                )
        last_digits = f" ending {event.callerLast4}" if event.callerLast4 else ""
        try:
            self._gateway.send(
                {
                    "event": "guardian_report",
                    "to": _normalize_phone(event.guardianPhone),
                    "reference": str(event.reportId),
                    "message": (
                        f"Kavasam danger report for {guardian['primary_alias']}: a call"
                        f"{last_digits} scored {event.risk}/100 ({event.riskLabel}). "
                        "Open the Kavasam Guardian tab for the redacted analysis."
                    ),
                }
            )
        except Exception:
            return GuardianReportResponse(
                reportId=event.reportId,
                status="stored",
                message="Report stored for the guardian; SMS delivery will be retried later.",
            )
        with self._lock, self._connection:
            self._connection.execute(
                "UPDATE guardian_reports SET delivery_status = 'delivered' WHERE id = ?",
                (str(event.reportId),),
            )
        return GuardianReportResponse(
            reportId=event.reportId,
            status="delivered",
            message="Dangerous-call report stored and sent to the guardian by SMS.",
        )

    def reports(self, session_token: str) -> GuardianReportList:
        now = _utc_now()
        with self._lock, self._connection:
            self._expire(now)
            session = self._connection.execute(
                """
                SELECT * FROM guardian_sessions
                WHERE token_hash = ? AND expires_at > ?
                """,
                (self._session_token(session_token), now.isoformat()),
            ).fetchone()
            if session is None:
                raise PermissionError("Guardian session is invalid or expired.")
            rows = self._connection.execute(
                """
                SELECT r.*, g.primary_alias
                FROM guardian_reports r
                JOIN guardians g ON g.id = r.guardian_id
                WHERE r.guardian_id = ?
                ORDER BY r.occurred_at DESC
                LIMIT 100
                """,
                (session["guardian_id"],),
            ).fetchall()
        return GuardianReportList(
            reports=[
                GuardianReportItem(
                    reportId=UUID(row["id"]),
                    primaryAlias=row["primary_alias"],
                    callerLast4=row["caller_last4"],
                    occurredAt=datetime.fromisoformat(row["occurred_at"]),
                    risk=row["risk"],
                    riskLabel=row["risk_label"],
                    summary=row["summary"],
                    signals=[value for value in row["signals"].split(",") if value],
                )
                for row in rows
            ]
        )

    def enrollment_status(
        self, enrollment_id: UUID, device_id: UUID
    ) -> GuardianEnrollmentResponse:
        now = _utc_now()
        with self._lock, self._connection:
            self._expire(now)
            row = self._connection.execute(
                "SELECT * FROM guardians WHERE id = ? AND device_id = ?",
                (str(enrollment_id), str(device_id)),
            ).fetchone()
        if row is None:
            raise KeyError("Guardian enrollment was not found.")
        return GuardianEnrollmentResponse(
            enrollmentId=UUID(row["id"]),
            status=row["status"],
            expiresAt=datetime.fromisoformat(row["expires_at"]),
            delivery="n8n",
            message=(
                "Guardian verified. Suspicious-call approvals are ready."
                if row["status"] == "verified"
                else "Waiting for the guardian's opt-in reply."
                if row["status"] == "pending"
                else "Enrollment expired. Send a new invitation."
            ),
        )

    def request_approval(self, event: GuardianApprovalRequest) -> GuardianApprovalResponse:
        if not self.configured:
            raise RuntimeError("Guardian SMS gateway is not configured.")
        now = _utc_now()
        expires = now + self._approval_ttl
        request_id = uuid4()
        ref_code = self._ref_code()
        with self._lock, self._connection:
            self._expire(now)
            guardian = self._connection.execute(
                "SELECT * FROM guardians WHERE id = ? AND device_id = ? AND status = 'verified'",
                (str(event.guardianId), str(event.deviceId)),
            ).fetchone()
            if guardian is None or not hmac.compare_digest(
                guardian["phone_token"], self._token(event.guardianPhone)
            ):
                raise PermissionError("Guardian is not verified for this device.")
            existing = self._connection.execute(
                "SELECT * FROM guardian_approvals "
                "WHERE device_id = ? AND call_session_id = ?",
                (str(event.deviceId), str(event.callSessionId)),
            ).fetchone()
            if existing is not None:
                return self._approval_response(existing)
            another_pending = self._connection.execute(
                "SELECT id FROM guardian_approvals WHERE device_id = ? AND status = 'pending'",
                (str(event.deviceId),),
            ).fetchone()
            if another_pending is not None:
                raise ValueError("Another guardian approval is already pending.")
            self._connection.execute(
                "INSERT INTO guardian_approvals VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, NULL)",
                (
                    str(request_id),
                    str(event.guardianId),
                    str(event.deviceId),
                    str(event.callSessionId),
                    ref_code,
                    now.isoformat(),
                    expires.isoformat(),
                ),
            )
        last_digits = f" ending {event.callerLast4}" if event.callerLast4 else ""
        signal_text = ", ".join(signal.replace("_", " ") for signal in event.signals[:3])
        details = f" Signals: {signal_text}." if signal_text else ""
        try:
            self._gateway.send(
                {
                    "event": "guardian_approval",
                    "to": _normalize_phone(event.guardianPhone),
                    "reference": ref_code,
                    "expiresInSeconds": int(self._approval_ttl.total_seconds()),
                    "message": (
                        f"Kavasam alert: {event.primaryAlias} wants to continue a "
                        f"{event.riskLabel.lower()} call{last_digits} (risk {event.risk}/100)."
                        f"{details} Reply ACCEPT #{ref_code} or REJECT #{ref_code}. "
                        "No reply means reject."
                    ),
                }
            )
        except Exception:
            with self._lock, self._connection:
                self._connection.execute(
                    "UPDATE guardian_approvals SET status = 'rejected', responded_at = ? WHERE id = ?",
                    (now.isoformat(), str(request_id)),
                )
            raise
        return GuardianApprovalResponse(
            requestId=request_id,
            refCode=ref_code,
            status="pending",
            expiresAt=expires,
            message="Call paused while Kavasam waits for the guardian.",
        )

    def approval_status(
        self, request_id: UUID, device_id: UUID
    ) -> GuardianApprovalResponse:
        now = _utc_now()
        with self._lock, self._connection:
            self._expire(now)
            row = self._connection.execute(
                "SELECT * FROM guardian_approvals WHERE id = ? AND device_id = ?",
                (str(request_id), str(device_id)),
            ).fetchone()
        if row is None:
            raise KeyError("Guardian approval was not found.")
        return self._approval_response(row)

    def receive_reply(self, sender_phone: str, message: str) -> GuardianReplyResponse:
        phone_token = self._token(sender_phone)
        normalized = message.upper().strip()
        decision, ref_code = _parse_reply(normalized)
        now = _utc_now()
        with self._lock, self._connection:
            self._expire(now)
            if "JOIN" in re.findall(r"[A-Z]+", normalized):
                query = (
                    "SELECT * FROM guardians WHERE phone_token = ? AND status = 'pending' "
                    + ("AND ref_code = ? " if ref_code else "")
                    + "ORDER BY created_at DESC"
                )
                arguments = (phone_token, ref_code) if ref_code else (phone_token,)
                rows = self._connection.execute(query, arguments).fetchall()
                if len(rows) == 1:
                    self._connection.execute(
                        "UPDATE guardians SET status = 'verified', verified_at = ? WHERE id = ?",
                        (now.isoformat(), rows[0]["id"]),
                    )
                    return GuardianReplyResponse(
                        matched=True, status="verified", message="Guardian opt-in verified."
                    )
            guardians = self._connection.execute(
                "SELECT id FROM guardians WHERE phone_token = ? AND status = 'verified'",
                (phone_token,),
            ).fetchall()
            guardian_ids = [row["id"] for row in guardians]
            if not guardian_ids:
                return GuardianReplyResponse(
                    matched=False, status="not_found", message="No active guardian request matched."
                )
            placeholders = ",".join("?" for _ in guardian_ids)
            query = (
                f"SELECT * FROM guardian_approvals WHERE guardian_id IN ({placeholders}) "
                "AND status = 'pending' "
                + ("AND ref_code = ? " if ref_code else "")
                + "ORDER BY created_at DESC"
            )
            arguments: tuple[object, ...] = tuple(guardian_ids) + (
                (ref_code,) if ref_code else ()
            )
            rows = self._connection.execute(query, arguments).fetchall()
            if len(rows) != 1:
                return GuardianReplyResponse(
                    matched=False,
                    status="not_found",
                    message="Include the four-digit reference when more than one request is pending.",
                )
            if decision is None:
                return GuardianReplyResponse(
                    matched=True,
                    status="unrecognized",
                    message="Reply ACCEPT or REJECT followed by the four-digit reference.",
                )
            self._connection.execute(
                "UPDATE guardian_approvals SET status = ?, responded_at = ? WHERE id = ?",
                (decision, now.isoformat(), rows[0]["id"]),
            )
            return GuardianReplyResponse(
                matched=True, status=decision, message=f"Call continuation {decision}."
            )

    @staticmethod
    def _approval_response(row: sqlite3.Row) -> GuardianApprovalResponse:
        status = row["status"]
        return GuardianApprovalResponse(
            requestId=UUID(row["id"]),
            refCode=row["ref_code"],
            status=status,
            expiresAt=datetime.fromisoformat(row["expires_at"]),
            message={
                "pending": "Waiting for guardian approval. Keep the call paused.",
                "approved": "Guardian approved continuing the call.",
                "rejected": "Guardian rejected the call. End it and verify independently.",
                "expired": "No reply arrived in time. The request was rejected for safety.",
            }[status],
        )

    def _expire(self, now: datetime) -> None:
        stamp = now.isoformat()
        report_cutoff = (now - timedelta(days=7)).isoformat()
        self._connection.execute(
            "UPDATE guardians SET status = 'expired' WHERE status = 'pending' AND expires_at <= ?",
            (stamp,),
        )
        self._connection.execute(
            "UPDATE guardian_approvals SET status = 'expired' "
            "WHERE status = 'pending' AND expires_at <= ?",
            (stamp,),
        )
        self._connection.execute(
            "DELETE FROM guardian_sessions WHERE expires_at <= ?",
            (stamp,),
        )
        self._connection.execute(
            "DELETE FROM guardian_reports WHERE occurred_at < ?",
            (report_cutoff,),
        )
