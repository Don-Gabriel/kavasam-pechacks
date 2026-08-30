import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.main import app
from app.schemas import VoiceWarningRequest
from app.voice import VoiceWarningService


def test_request_rejects_unknown_language() -> None:
    with pytest.raises(ValidationError):
        VoiceWarningRequest.model_validate(
            {"text": "Do not share your OTP", "language": "fr"}
        )


def test_request_rejects_empty_text() -> None:
    with pytest.raises(ValidationError):
        VoiceWarningRequest.model_validate({"text": "", "language": "en"})


def test_service_unconfigured_reports_not_configured() -> None:
    service = VoiceWarningService()
    service.api_key = ""
    assert service.configured is False


def test_endpoint_returns_503_when_not_configured(monkeypatch) -> None:
    from app import main

    monkeypatch.setattr(main.voice, "api_key", "")
    response = TestClient(app).post(
        "/v1/voice/warning",
        json={"text": "Do not share your OTP", "language": "en"},
    )
    assert response.status_code == 503


def test_health_exposes_voice_flag() -> None:
    response = TestClient(app).get("/health")
    assert response.status_code == 200
    assert "voiceConfigured" in response.json()
