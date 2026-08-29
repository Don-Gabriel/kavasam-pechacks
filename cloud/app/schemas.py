from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


SafetySignal = Literal[
    "otp_pin",
    "payment_transfer",
    "remote_access",
    "impersonation",
    "secrecy_urgency",
    "threats",
]


class CallerContext(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    savedContact: bool
    locallyReported: bool
    carrierVerificationFailed: bool


class SafetyAnalysisRequest(BaseModel):
    """The complete allowlist of data accepted from a phone."""

    model_config = ConfigDict(extra="forbid", strict=True)

    schemaVersion: Literal[1]
    sessionId: UUID = Field(strict=False)
    localRisk: int = Field(ge=0, le=100)
    vectorSimilarity: float = Field(ge=0.0, le=1.0)
    signals: list[SafetySignal] = Field(max_length=6)
    callerContext: CallerContext
    locale: str = Field(pattern=r"^[a-z]{2,3}(?:-[A-Z]{2})?$", max_length=12)


class VectorPatternMatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    category: str = Field(max_length=64)
    label: str = Field(max_length=120)
    similarity: float = Field(ge=0.0, le=1.0)
    riskFloor: int = Field(ge=0, le=100)


class SafetyAnalysisResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    risk: int = Field(ge=0, le=100)
    level: Literal["low", "medium", "high", "critical"]
    reasons: list[str] = Field(max_length=4)
    recommendedActions: list[str] = Field(max_length=4)
    warningText: str = Field(max_length=320)
    source: Literal["gemini", "rules-fallback"]
    vectorDatabase: Literal[
        "actian-vectorai", "actian-unavailable", "local-fallback"
    ] = "local-fallback"
    vectorMatch: VectorPatternMatch | None = None


class HealthResponse(BaseModel):
    status: Literal["ok"] = "ok"
    geminiConfigured: bool
    guardianConfigured: bool = False
    actianConfigured: bool = False
    actianStatus: Literal[
        "not-configured", "not-checked", "ready", "unavailable"
    ] = "not-configured"
    actianCollection: str = "kavasam_scam_patterns"
    rawRequestRetention: Literal["none"] = "none"
    communityReputation: Literal["ready"] = "ready"


SpamCategory = Literal[
    "telemarketing",
    "financial_fraud",
    "impersonation",
    "robocall",
    "harassment",
    "delivery_scam",
    "other",
]


class ReputationLookupRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    phoneNumber: str = Field(pattern=r"^\+?[0-9]{7,18}$", max_length=18)


class ReputationReportRequest(ReputationLookupRequest):
    reporterId: UUID = Field(strict=False)
    category: SpamCategory


class CommunityReputationResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    found: bool
    category: str
    risk: int = Field(ge=0, le=100)
    riskLabel: str
    reportCount: int = Field(ge=0)
    confidence: float = Field(ge=0.0, le=1.0)
    reasons: list[str] = Field(max_length=4)
    source: Literal["community", "none"]


GuardianState = Literal["pending", "verified", "approved", "rejected", "expired"]


class GuardianEnrollmentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    deviceId: UUID = Field(strict=False)
    guardianPhone: str = Field(pattern=r"^\+?[0-9]{7,18}$", max_length=18)
    primaryAlias: str = Field(min_length=1, max_length=48)
    locale: str = Field(pattern=r"^[a-z]{2,3}(?:-[A-Z]{2})?$", max_length=12)


class GuardianEnrollmentResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    enrollmentId: UUID
    status: Literal["pending", "verified", "expired"]
    expiresAt: datetime
    delivery: Literal["n8n"]
    message: str = Field(max_length=240)


class GuardianApprovalRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    deviceId: UUID = Field(strict=False)
    guardianId: UUID = Field(strict=False)
    guardianPhone: str = Field(pattern=r"^\+?[0-9]{7,18}$", max_length=18)
    callSessionId: UUID = Field(strict=False)
    primaryAlias: str = Field(min_length=1, max_length=48)
    callerLast4: str = Field(pattern=r"^[0-9]{0,4}$", max_length=4)
    risk: int = Field(ge=0, le=100)
    riskLabel: str = Field(min_length=1, max_length=40)
    signals: list[SafetySignal] = Field(max_length=6)


class GuardianApprovalResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    requestId: UUID
    refCode: str = Field(pattern=r"^[0-9]{4}$")
    status: Literal["pending", "approved", "rejected", "expired"]
    expiresAt: datetime
    message: str = Field(max_length=240)


class GuardianReplyRequest(BaseModel):
    """Allowlisted payload sent only by the authenticated n8n workflow."""

    model_config = ConfigDict(extra="forbid", strict=True)

    senderPhone: str = Field(pattern=r"^\+?[0-9]{7,18}$", max_length=18)
    message: str = Field(min_length=1, max_length=80)


class GuardianReplyResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    matched: bool
    status: Literal["verified", "approved", "rejected", "unrecognized", "not_found"]
    message: str = Field(max_length=240)
