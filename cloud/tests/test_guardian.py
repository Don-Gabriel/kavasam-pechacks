from datetime import datetime, timezone
from uuid import uuid4

from app.guardian import GuardianApprovalStore
from app.schemas import (
    GuardianApprovalRequest,
    GuardianClaimRequest,
    GuardianEnrollmentRequest,
    GuardianReportRequest,
)


class FakeGateway:
    configured = True

    def __init__(self) -> None:
        self.messages: list[dict[str, object]] = []

    def send(self, payload: dict[str, object]) -> None:
        self.messages.append(payload)


def _verified_guardian() -> tuple[GuardianApprovalStore, FakeGateway, object, object, str]:
    gateway = FakeGateway()
    store = GuardianApprovalStore(
        ":memory:", "test-secret-with-enough-entropy", gateway=gateway
    )
    device_id = uuid4()
    phone = "+919876543210"
    enrollment = store.enroll(
        GuardianEnrollmentRequest(
            deviceId=device_id,
            guardianPhone=phone,
            primaryAlias="Amma",
            locale="en-IN",
        )
    )
    reference = gateway.messages[-1]["reference"]
    reply = store.receive_reply(phone, f"JOIN #{reference}")
    assert reply.status == "verified"
    return store, gateway, device_id, enrollment.enrollmentId, phone


def test_guardian_phone_is_tokenized_and_requires_opt_in() -> None:
    store, gateway, device_id, guardian_id, phone = _verified_guardian()
    status = store.enrollment_status(guardian_id, device_id)
    assert status.status == "verified"
    dump = " ".join(store._connection.iterdump())
    assert phone not in dump
    assert gateway.messages[0]["event"] == "guardian_enrollment"
    store.close()


def test_approval_reply_resolves_pending_request() -> None:
    store, gateway, device_id, guardian_id, phone = _verified_guardian()
    call_session_id = uuid4()
    approval = store.request_approval(
        GuardianApprovalRequest(
            deviceId=device_id,
            guardianId=guardian_id,
            guardianPhone=phone,
            callSessionId=call_session_id,
            primaryAlias="Amma",
            callerLast4="3210",
            risk=82,
            riskLabel="High risk",
            signals=["otp_pin", "secrecy_urgency"],
        )
    )
    assert approval.status == "pending"
    reply = store.receive_reply(phone, f"ACCEPT #{approval.refCode}")
    assert reply.status == "approved"
    assert store.approval_status(approval.requestId, device_id).status == "approved"
    assert gateway.messages[-1]["event"] == "guardian_approval"
    store.close()


def test_unrecognized_reply_does_not_approve() -> None:
    store, _, device_id, guardian_id, phone = _verified_guardian()
    approval = store.request_approval(
        GuardianApprovalRequest(
            deviceId=device_id,
            guardianId=guardian_id,
            guardianPhone=phone,
            callSessionId=uuid4(),
            primaryAlias="Amma",
            callerLast4="",
            risk=55,
            riskLabel="Suspicious",
            signals=[],
        )
    )
    reply = store.receive_reply(phone, f"MAYBE #{approval.refCode}")
    assert reply.status == "unrecognized"
    assert store.approval_status(approval.requestId, device_id).status == "pending"
    store.close()


def test_guardian_can_claim_relationship_and_read_danger_reports() -> None:
    store, gateway, device_id, guardian_id, phone = _verified_guardian()
    reference = gateway.messages[0]["reference"]
    claim = store.claim_relationship(
        GuardianClaimRequest(
            guardianPhone=phone,
            referenceCode=reference,
            guardianDeviceId=uuid4(),
        )
    )
    assert claim.guardianId == guardian_id
    assert claim.primaryAlias == "Amma"

    report = store.submit_report(
        GuardianReportRequest(
            reportId=uuid4(),
            deviceId=device_id,
            guardianId=guardian_id,
            guardianPhone=phone,
            callSessionId=uuid4(),
            callerLast4="3210",
            occurredAt=datetime(2026, 8, 30, 10, tzinfo=timezone.utc),
            risk=91,
            riskLabel="Dangerous",
            summary="Caller requested an OTP and immediate bank transfer.",
            signals=["otp_pin", "payment_transfer"],
        )
    )
    assert report.status == "delivered"
    assert gateway.messages[-1]["event"] == "guardian_report"

    reports = store.reports(claim.sessionToken)
    assert len(reports.reports) == 1
    assert reports.reports[0].risk == 91
    assert reports.reports[0].callerLast4 == "3210"
    assert phone not in " ".join(store._connection.iterdump())
    store.close()


def test_danger_report_threshold_is_enforced_by_schema() -> None:
    try:
        GuardianReportRequest(
            reportId=uuid4(),
            deviceId=uuid4(),
            guardianId=uuid4(),
            guardianPhone="+919876543210",
            callSessionId=uuid4(),
            occurredAt=datetime(2026, 8, 30, 10, tzinfo=timezone.utc),
            risk=80,
            riskLabel="High",
            summary="Below the guardian reporting threshold.",
            signals=[],
        )
    except ValueError:
        return
    raise AssertionError("risk 80 must not be accepted as a dangerous report")
