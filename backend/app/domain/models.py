from __future__ import annotations

from datetime import UTC, datetime
from enum import StrEnum

from pydantic import BaseModel, Field, field_validator


class RiskLevel(StrEnum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


class LoginRequest(BaseModel):
    phone_number: str = Field(pattern=r"^\+?[1-9]\d{9,14}$")


class LoginResponse(BaseModel):
    message: str
    session_id: str
    dev_otp: str | None = None


class VerifyRequest(BaseModel):
    session_id: str = Field(min_length=16, max_length=128)
    otp: str = Field(pattern=r"^\d{6}$")


class VerifyResponse(BaseModel):
    access_token: str
    user_id: str
    token_type: str = "bearer"


class MessageAnalysisRequest(BaseModel):
    text: str = Field(min_length=1, max_length=12_000)
    language: str = Field(default="English", min_length=2, max_length=40)

    @field_validator("text")
    @classmethod
    def reject_blank_text(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("text must not be blank")
        return value.strip()


class ImageAnalysisRequest(BaseModel):
    image_base64: str = Field(min_length=16, max_length=8_000_000)
    mime_type: str = Field(default="image/jpeg", pattern=r"^image/")
    context: str = Field(default="", max_length=2_000)
    language: str = Field(default="English", min_length=2, max_length=40)


class CallAnalysisRequest(BaseModel):
    audio_chunk: str | None = Field(default=None, max_length=8_000_000)
    transcript: str | None = Field(default=None, max_length=12_000)
    language: str = Field(default="English", min_length=2, max_length=40)

    @field_validator("transcript")
    @classmethod
    def normalize_transcript(cls, value: str | None) -> str | None:
        return value.strip() if value and value.strip() else None


class FraudAnalysisResponse(BaseModel):
    event_id: str
    risk_score: int = Field(ge=0, le=100)
    risk_level: RiskLevel
    fraud_type: str
    confidence: float = Field(ge=0, le=1)
    reasons: list[str]
    warning: str
    recommended_action: str
    analyzed_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    analysis_source: str = "rules"


class PaymentCheckRequest(BaseModel):
    upi_id: str = Field(min_length=3, max_length=120)
    merchant_name: str = Field(min_length=1, max_length=160)
    amount: float = Field(ge=0, le=10_000_000)
    context: str = Field(default="", max_length=2_000)


class PaymentCheckResponse(BaseModel):
    event_id: str
    risk_score: int = Field(ge=0, le=100)
    status: str
    reason: str
    reasons: list[str]
    recommended_action: str


class GuardianAddRequest(BaseModel):
    guardian_phone: str = Field(pattern=r"^\+?[1-9]\d{9,14}$")
    guardian_name: str = Field(min_length=1, max_length=100)


class GuardianLinkResponse(BaseModel):
    guardian_id: str
    guardian_name: str
    status: str


class GuardianAlertRequest(BaseModel):
    event_id: str = Field(min_length=8, max_length=128)
    message: str = Field(min_length=1, max_length=500)


class GuardianAlertResponse(BaseModel):
    alert_id: str
    status: str
    recipients: int


class ReportGenerateRequest(BaseModel):
    event_id: str = Field(min_length=8, max_length=128)
    incident_notes: str = Field(default="", max_length=4_000)


class ReportResponse(BaseModel):
    report_id: str
    incident_summary: str
    evidence_list: list[str]
    timeline: list[str]
    recommended_complaint_details: list[str]
    status: str = "DRAFT"


class FeedbackRequest(BaseModel):
    event_id: str = Field(min_length=8, max_length=128)
    user_verdict: str = Field(pattern=r"^(FRAUD|SAFE|UNSURE)$")


class FeedbackResponse(BaseModel):
    status: str


class VoiceWarningRequest(BaseModel):
    text: str = Field(min_length=2, max_length=500)
    language: str = Field(default="English", min_length=2, max_length=40)


class VoiceWarningResponse(BaseModel):
    audio_base64: str
    mime_type: str = "audio/mpeg"
    provider: str = "elevenlabs"
