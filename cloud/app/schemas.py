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


class SafetyAnalysisResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    risk: int = Field(ge=0, le=100)
    level: Literal["low", "medium", "high", "critical"]
    reasons: list[str] = Field(max_length=4)
    recommendedActions: list[str] = Field(max_length=4)
    warningText: str = Field(max_length=320)
    source: Literal["gemini", "rules-fallback"]


class HealthResponse(BaseModel):
    status: Literal["ok"] = "ok"
    geminiConfigured: bool
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
