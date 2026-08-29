import asyncio
import os
import re
from dataclasses import dataclass
from urllib.parse import quote

import httpx

from .schemas import SafetyAnalysisRequest, SafetyAnalysisResponse, VectorPatternMatch


SIGNAL_ORDER = (
    "otp_pin",
    "payment_transfer",
    "remote_access",
    "impersonation",
    "secrecy_urgency",
    "threats",
)

# These are transparent behavior prototypes, not voice embeddings. They are seeded
# into Actian so every online safety request can use real nearest-neighbor search.
SCAM_PATTERNS = (
    {
        "id": 1,
        "vector": [0.82, 0.88, 1.0, 0.15, 0.05, 0.75, 0.95, 0.10, 1.0, 0.45, 0.20, 0.50],
        "payload": {
            "category": "credential_theft",
            "label": "OTP or PIN credential theft",
            "risk_floor": 88,
            "reason": "The signal pattern resembles an OTP/PIN theft attempt.",
        },
    },
    {
        "id": 2,
        "vector": [0.86, 0.90, 0.15, 1.0, 0.10, 0.65, 0.90, 0.35, 1.0, 0.55, 0.25, 0.58],
        "payload": {
            "category": "payment_fraud",
            "label": "Urgent payment or transfer fraud",
            "risk_floor": 90,
            "reason": "The signal pattern resembles urgent payment fraud.",
        },
    },
    {
        "id": 3,
        "vector": [0.88, 0.92, 0.25, 0.35, 1.0, 0.70, 0.75, 0.15, 1.0, 0.45, 0.30, 0.60],
        "payload": {
            "category": "remote_access",
            "label": "Remote-access takeover",
            "risk_floor": 92,
            "reason": "The signal pattern resembles a remote-access takeover scam.",
        },
    },
    {
        "id": 4,
        "vector": [0.84, 0.86, 0.10, 0.45, 0.05, 1.0, 0.70, 0.85, 1.0, 0.45, 0.35, 0.58],
        "payload": {
            "category": "authority_impersonation",
            "label": "Authority impersonation and threats",
            "risk_floor": 89,
            "reason": "The signal pattern resembles authority impersonation with intimidation.",
        },
    },
)


@dataclass(frozen=True)
class ActianMatch:
    category: str
    label: str
    similarity: float
    risk_floor: int
    reason: str


def safety_vector(event: SafetyAnalysisRequest) -> list[float]:
    selected = set(event.signals)
    return [
        event.localRisk / 100.0,
        event.vectorSimilarity,
        *(1.0 if signal in selected else 0.0 for signal in SIGNAL_ORDER),
        0.0 if event.callerContext.savedContact else 1.0,
        1.0 if event.callerContext.locallyReported else 0.0,
        1.0 if event.callerContext.carrierVerificationFailed else 0.0,
        len(selected) / len(SIGNAL_ORDER),
    ]


class ActianVectorStore:
    """Fail-open Actian VectorAI DB adapter for advisory scam-pattern retrieval."""

    dimension = 12

    def __init__(
        self,
        base_url: str | None = None,
        access_token: str | None = None,
        collection: str | None = None,
        timeout_seconds: float | None = None,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.base_url = (base_url if base_url is not None else os.getenv("ACTIAN_VECTORAI_URL", "")).strip().rstrip("/")
        self.access_token = (
            access_token if access_token is not None else os.getenv("ACTIAN_VECTORAI_ACCESS_TOKEN", "")
        ).strip()
        requested_collection = (
            collection if collection is not None else os.getenv("ACTIAN_VECTORAI_COLLECTION", "kavasam_scam_patterns")
        ).strip()
        self.collection = (
            requested_collection
            if re.fullmatch(r"[A-Za-z0-9_-]{1,64}", requested_collection)
            else "kavasam_scam_patterns"
        )
        raw_timeout = os.getenv("ACTIAN_VECTORAI_TIMEOUT_SECONDS", "2.5")
        try:
            self.timeout_seconds = timeout_seconds if timeout_seconds is not None else float(raw_timeout)
        except ValueError:
            self.timeout_seconds = 2.5
        self._transport = transport
        self._ready = False
        self._status = "not-checked" if self.configured else "not-configured"
        self._initialization_lock = asyncio.Lock()

    @property
    def configured(self) -> bool:
        return bool(self.base_url)

    @property
    def status(self) -> str:
        return self._status

    @property
    def _headers(self) -> dict[str, str]:
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        if self.access_token:
            headers["Authorization"] = f"Bearer {self.access_token}"
        return headers

    async def match(self, event: SafetyAnalysisRequest) -> ActianMatch | None:
        if not self.configured:
            return None
        try:
            await self._ensure_collection()
            collection = quote(self.collection, safe="")
            body = await self._request(
                "POST",
                f"/collections/{collection}/points/search",
                json={
                    "vector": safety_vector(event),
                    "limit": 1,
                    "score_threshold": 0.58,
                    "with_payload": True,
                    "with_vector": False,
                },
            )
            results = body.get("result")
            if not isinstance(results, list) or not results:
                self._status = "ready"
                return None
            top = results[0]
            payload = top.get("payload") if isinstance(top, dict) else None
            if not isinstance(payload, dict):
                return None
            match = ActianMatch(
                category=str(payload["category"])[:64],
                label=str(payload["label"])[:120],
                similarity=max(0.0, min(1.0, float(top["score"]))),
                risk_floor=max(0, min(100, int(payload["risk_floor"]))),
                reason=str(payload["reason"])[:240],
            )
            self._status = "ready"
            return match
        except (httpx.HTTPError, KeyError, TypeError, ValueError):
            self._status = "unavailable"
            self._ready = False
            return None

    async def _ensure_collection(self) -> None:
        if self._ready:
            return
        async with self._initialization_lock:
            if self._ready:
                return
            collection = quote(self.collection, safe="")
            await self._request(
                "PUT",
                f"/collections/{collection}",
                json={"vectors": {"size": self.dimension, "distance": "Cosine"}},
                accepted_statuses={200, 409},
            )
            await self._request(
                "PUT",
                f"/collections/{collection}/points?wait=true",
                json={"points": list(SCAM_PATTERNS)},
            )
            self._ready = True
            self._status = "ready"

    async def _request(
        self,
        method: str,
        path: str,
        *,
        json: dict[str, object],
        accepted_statuses: set[int] | None = None,
    ) -> dict[str, object]:
        async with httpx.AsyncClient(
            base_url=self.base_url,
            headers=self._headers,
            timeout=self.timeout_seconds,
            transport=self._transport,
        ) as client:
            response = await client.request(method, path, json=json)
        allowed = accepted_statuses or {200}
        if response.status_code not in allowed:
            response.raise_for_status()
        if response.status_code == 409:
            return {"status": "ok"}
        body = response.json()
        if not isinstance(body, dict):
            raise ValueError("Actian returned a non-object response.")
        return body


def augment_with_actian(
    result: SafetyAnalysisResponse,
    match: ActianMatch | None,
    store: ActianVectorStore,
) -> SafetyAnalysisResponse:
    vector_database = (
        "actian-vectorai"
        if match is not None
        else "actian-unavailable"
        if store.configured and store.status == "unavailable"
        else "local-fallback"
    )
    if match is None:
        return result.model_copy(update={"vectorDatabase": vector_database, "vectorMatch": None})

    matched_floor = round(match.risk_floor * match.similarity)
    risk = max(result.risk, matched_floor)
    level = "critical" if risk >= 85 else "high" if risk >= 60 else "medium" if risk >= 30 else "low"
    reasons = [match.reason, *(reason for reason in result.reasons if reason != match.reason)][:4]
    return result.model_copy(
        update={
            "risk": risk,
            "level": level,
            "reasons": reasons,
            "vectorDatabase": vector_database,
            "vectorMatch": VectorPatternMatch(
                category=match.category,
                label=match.label,
                similarity=match.similarity,
                riskFloor=match.risk_floor,
            ),
        }
    )
