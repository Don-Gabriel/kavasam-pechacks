from fastapi.testclient import TestClient


def test_suspicious_payment_and_report_flow(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    payment = client.post(
        "/payment/check",
        headers=auth_headers,
        json={
            "upi_id": "bad upi",
            "merchant_name": "Local Store",
            "amount": 50_000,
            "context": "Pay urgent verification fee for cashback",
        },
    )
    assert payment.status_code == 200
    assert payment.json()["status"] == "WARNING"

    report = client.post(
        "/report/generate",
        headers=auth_headers,
        json={
            "event_id": payment.json()["event_id"],
            "incident_notes": "The receiver contacted me by phone.",
        },
    )
    assert report.status_code == 200
    assert report.json()["status"] == "DRAFT"
    assert "1930" in " ".join(report.json()["recommended_complaint_details"])


def test_guardian_link_starts_pending_and_alert_is_recorded(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    guardian = client.post(
        "/guardian/add",
        headers=auth_headers,
        json={"guardian_phone": "+919812345678", "guardian_name": "Anjali"},
    )
    assert guardian.status_code == 200
    assert guardian.json()["status"] == "PENDING_APPROVAL"

    event = client.post(
        "/fraud/analyze-message",
        headers=auth_headers,
        json={"text": "Send money immediately and do not tell anyone", "language": "English"},
    ).json()
    alert = client.post(
        "/guardian/alert",
        headers=auth_headers,
        json={"event_id": event["event_id"], "message": "Possible fraud detected"},
    )
    assert alert.status_code == 200
    assert alert.json()["status"] == "QUEUED"
    assert alert.json()["recipients"] == 1


def test_upi_qr_without_fixed_amount_can_still_be_checked(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    response = client.post(
        "/payment/check",
        headers=auth_headers,
        json={
            "upi_id": "merchant@okaxis",
            "merchant_name": "Local Store",
            "amount": 0,
            "context": "",
        },
    )
    assert response.status_code == 200
    assert response.json()["status"] in {"SAFE", "VERIFY", "WARNING"}
