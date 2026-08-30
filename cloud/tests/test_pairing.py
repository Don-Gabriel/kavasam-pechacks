from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app import main
from app.main import app
from app.pairing import PairingStore
from app.schemas import PairingClaimRequest, PairingReportRequest


def test_store_without_uri_is_unconfigured() -> None:
    store = PairingStore(uri="")
    assert store.configured is False


def test_claim_code_length_is_validated() -> None:
    with pytest.raises(ValidationError):
        PairingClaimRequest.model_validate(
            {"code": "A1", "guardianDeviceId": str(uuid4()), "guardianAlias": "Son"}
        )


def test_report_requires_high_risk() -> None:
    base = {
        "elderlyDeviceId": str(uuid4()),
        "reportId": str(uuid4()),
        "callerLast4": "4821",
        "riskLabel": "Dangerous",
        "summary": "OTP scam",
        "signals": ["otp_pin"],
    }
    PairingReportRequest.model_validate({**base, "risk": 92})
    with pytest.raises(ValidationError):
        PairingReportRequest.model_validate({**base, "risk": 50})


def test_code_endpoint_503_when_unconfigured(monkeypatch) -> None:
    monkeypatch.setattr(main, "pairing", PairingStore(uri=""))
    response = TestClient(app).post(
        "/v1/pair/code", json={"elderlyDeviceId": str(uuid4()), "alias": "Amma"}
    )
    assert response.status_code == 503


def test_reports_requires_bearer_token() -> None:
    response = TestClient(app).get("/v1/pair/reports")
    assert response.status_code == 401


def test_health_exposes_pairing_flag() -> None:
    response = TestClient(app).get("/health")
    assert response.status_code == 200
    assert "pairingConfigured" in response.json()
