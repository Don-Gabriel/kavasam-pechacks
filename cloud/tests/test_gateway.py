import json
from uuid import uuid4

import pytest
from pydantic import ValidationError
from fastapi.testclient import TestClient

from app.analyzer import fallback_analysis
from app.main import app
from app.schemas import SafetyAnalysisRequest


def valid_event() -> dict:
    return {
        "schemaVersion": 1,
        "sessionId": str(uuid4()),
        "localRisk": 42,
        "vectorSimilarity": 0.71,
        "signals": ["otp_pin", "secrecy_urgency"],
        "callerContext": {
            "savedContact": False,
            "locallyReported": True,
            "carrierVerificationFailed": False,
        },
        "locale": "en-IN",
    }


@pytest.mark.parametrize("forbidden", ["phoneNumber", "contactName", "audio", "transcript", "callHistory"])
def test_schema_rejects_pii_and_call_content(forbidden: str) -> None:
    payload = valid_event()
    payload[forbidden] = "must not leave the device"
    with pytest.raises(ValidationError):
        SafetyAnalysisRequest.model_validate(payload)


def test_schema_rejects_unknown_signal() -> None:
    payload = valid_event()
    payload["signals"] = ["made_up_signal"]
    with pytest.raises(ValidationError):
        SafetyAnalysisRequest.model_validate(payload)


def test_fallback_is_explainable_and_bounded() -> None:
    event = SafetyAnalysisRequest.model_validate_json(json.dumps(valid_event()))
    result = fallback_analysis(event)
    assert 0 <= result.risk <= 100
    assert result.level in {"low", "medium", "high", "critical"}
    assert result.reasons
    assert result.recommendedActions
    assert result.source == "rules-fallback"


def test_api_accepts_redacted_json_and_never_caches() -> None:
    response = TestClient(app).post("/v1/safety/analyze", json=valid_event())
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.json()["source"] in {"gemini", "rules-fallback"}


def test_api_rejects_phone_number() -> None:
    payload = valid_event()
    payload["phoneNumber"] = "+919999999999"
    response = TestClient(app).post("/v1/safety/analyze", json=payload)
    assert response.status_code == 422
