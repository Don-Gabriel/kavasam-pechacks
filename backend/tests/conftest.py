from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app


@pytest.fixture()
def client() -> TestClient:
    settings = Settings(
        environment="testing",
        secret_key="test-only-secret-that-is-long-enough-for-signing",
        expose_dev_otp=True,
        dev_otp="246810",
        rate_limit_per_minute=10_000,
    )
    with TestClient(create_app(settings)) as test_client:
        yield test_client


@pytest.fixture()
def auth_headers(client: TestClient) -> dict[str, str]:
    login = client.post("/auth/login", json={"phone_number": "+919876543210"})
    session_id = login.json()["session_id"]
    verify = client.post("/auth/verify", json={"session_id": session_id, "otp": "246810"})
    return {"Authorization": f"Bearer {verify.json()['access_token']}"}
