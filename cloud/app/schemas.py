from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


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
    # Optional consent-gated speech excerpt. The phone redacts digit runs
    # before upload, so OTPs and numbers never reach the gateway.
    transcriptExcerpt: str = Field(default="", max_length=2400)
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
    snowflakeConfigured: bool = False
    snowflakeStatus: Literal[
        "not-configured", "not-checked", "ready", "unavailable"
    ] = "not-configured"
    voiceConfigured: bool = False
    pairingConfigured: bool = False


ContentKind = Literal["message", "qr"]
FileContentKind = Literal["email_pdf", "screenshot"]


class ContentAnalysisRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schemaVersion: Literal[1]
    sessionId: UUID = Field(strict=False)
    kind: ContentKind
    text: str = Field(min_length=1, max_length=20_000)
    locale: str = Field(pattern=r"^[a-z]{2,3}(?:-[A-Z]{2})?$", max_length=12)


class FileAnalysisRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schemaVersion: Literal[1]
    sessionId: UUID = Field(strict=False)
    kind: FileContentKind
    fileName: str = Field(min_length=1, max_length=160)
    mimeType: Literal["application/pdf", "image/jpeg", "image/png", "image/webp"]
    dataBase64: str = Field(min_length=4, max_length=12_000_000)
    locale: str = Field(pattern=r"^[a-z]{2,3}(?:-[A-Z]{2})?$", max_length=12)

    @model_validator(mode="after")
    def validate_kind_and_mime(self) -> "FileAnalysisRequest":
        if self.kind == "email_pdf" and self.mimeType != "application/pdf":
            raise ValueError("Email analysis accepts PDF files only.")
        if self.kind == "screenshot" and not self.mimeType.startswith("image/"):
            raise ValueError("Screenshot analysis accepts image files only.")
        return self


class UrlAnalysisRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schemaVersion: Literal[1]
    sessionId: UUID = Field(strict=False)
    url: str = Field(min_length=4, max_length=2_048)
    locale: str = Field(pattern=r"^[a-z]{2,3}(?:-[A-Z]{2})?$", max_length=12)


class UrlAssessment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    originalHost: str = Field(max_length=253)
    finalHost: str = Field(max_length=253)
    redirectCount: int = Field(ge=0, le=5)
    redirectChain: list[str] = Field(max_length=6)
    usesShortener: bool
    hostChanged: bool
    reachable: bool


class ContentAnalysisResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    risk: int = Field(ge=0, le=100)
    level: Literal["low", "medium", "high", "critical"]
    category: str = Field(max_length=80)
    summary: str = Field(max_length=360)
    reasons: list[str] = Field(max_length=5)
    recommendedActions: list[str] = Field(max_length=5)
    indicators: list[str] = Field(max_length=10)
    source: Literal["gemini", "rules-fallback"]
    extractedTextPreview: str = Field(default="", max_length=500)
    urlAssessment: UrlAssessment | None = None


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


class VoiceWarningRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    text: str = Field(min_length=1, max_length=320)
    language: Literal["en", "ta"] = "en"


class VoiceWarningResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    audioBase64: str = Field(min_length=4)
    mimeType: Literal["audio/mpeg"] = "audio/mpeg"
    spokenText: str = Field(max_length=320)
    language: Literal["en", "ta"]
    source: Literal["elevenlabs"] = "elevenlabs"


class LinkRoomRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    deviceId: UUID = Field(strict=False)


class LinkRoomResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: str = Field(pattern=r"^[0-9]{6}$")
    expiresInSeconds: int = Field(ge=1)
    sampleRate: Literal[16000] = 16000


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


class GuardianClaimRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    guardianPhone: str = Field(pattern=r"^\+?[0-9]{7,18}$", max_length=18)
    referenceCode: str = Field(pattern=r"^[0-9]{4}$")
    guardianDeviceId: UUID = Field(strict=False)


class GuardianClaimResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    guardianId: UUID
    sessionToken: str = Field(min_length=32, max_length=128)
    primaryAlias: str = Field(min_length=1, max_length=48)
    expiresAt: datetime
    message: str = Field(max_length=240)


class GuardianReportRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    reportId: UUID = Field(strict=False)
    deviceId: UUID = Field(strict=False)
    guardianId: UUID = Field(strict=False)
    guardianPhone: str = Field(pattern=r"^\+?[0-9]{7,18}$", max_length=18)
    callSessionId: UUID = Field(strict=False)
    callerLast4: str = Field(pattern=r"^[0-9]{0,4}$", max_length=4)
    occurredAt: datetime
    risk: int = Field(gt=80, le=100)
    riskLabel: str = Field(min_length=1, max_length=40)
    summary: str = Field(min_length=1, max_length=360)
    signals: list[SafetySignal] = Field(max_length=6)


class GuardianReportResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reportId: UUID
    status: Literal["delivered", "stored"]
    message: str = Field(max_length=240)


class GuardianReportItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reportId: UUID
    primaryAlias: str
    callerLast4: str
    occurredAt: datetime
    risk: int = Field(gt=80, le=100)
    riskLabel: str
    summary: str
    signals: list[SafetySignal]


class GuardianReportList(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reports: list[GuardianReportItem] = Field(max_length=100)


class PairingCodeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    elderlyDeviceId: UUID = Field(strict=False)
    alias: str = Field(min_length=1, max_length=48)


class PairingStatusResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["none", "open", "linked"]
    code: str = Field(max_length=12)
    guardianAlias: str = Field(default="", max_length=48)
    message: str = Field(default="", max_length=160)


class PairingClaimRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    code: str = Field(min_length=4, max_length=12)
    guardianDeviceId: UUID = Field(strict=False)
    guardianAlias: str = Field(min_length=1, max_length=48)
    alertHandle: str = Field(default="", max_length=120)


class PairingClaimResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    pairingId: str = Field(max_length=64)
    sessionToken: str = Field(min_length=16, max_length=128)
    elderlyAlias: str = Field(max_length=48)
    expiresAt: datetime
    message: str = Field(max_length=160)


class PairingReportRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    elderlyDeviceId: UUID = Field(strict=False)
    reportId: UUID = Field(strict=False)
    callerLast4: str = Field(pattern=r"^[0-9]{0,4}$", max_length=4)
    risk: int = Field(gt=80, le=100)
    riskLabel: str = Field(min_length=1, max_length=40)
    summary: str = Field(min_length=1, max_length=360)
    signals: list[SafetySignal] = Field(max_length=6)


class PairingReportResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reportId: UUID
    status: Literal["delivered", "pending", "stored", "duplicate", "skipped"]


class PairingReportList(BaseModel):
    model_config = ConfigDict(extra="forbid")

    elderlyAlias: str = Field(default="", max_length=48)
    reports: list[GuardianReportItem] = Field(max_length=100)
