from fastapi.testclient import TestClient


def test_login_and_verify_issue_access_token(client: TestClient) -> None:
    login = client.post("/auth/login", json={"phone_number": "+919876543210"})
    assert login.status_code == 200
    assert login.json()["dev_otp"] == "246810"

    verify = client.post(
        "/auth/verify",
        json={"session_id": login.json()["session_id"], "otp": "246810"},
    )
    assert verify.status_code == 200
    assert verify.json()["token_type"] == "bearer"
    assert verify.json()["access_token"]


def test_protected_endpoint_rejects_missing_token(client: TestClient) -> None:
    response = client.post(
        "/fraud/analyze-message",
        json={"text": "Hello from your family", "language": "English"},
    )
    assert response.status_code == 401


def test_invalid_phone_is_rejected(client: TestClient) -> None:
    response = client.post("/auth/login", json={"phone_number": "123"})
    assert response.status_code == 422
