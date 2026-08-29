from uuid import uuid4

from app.reputation import CommunityReputationStore
from app.schemas import ReputationReportRequest


def test_reports_are_deduplicated_and_raw_number_is_not_stored() -> None:
    store = CommunityReputationStore(":memory:", "test-secret-with-enough-entropy")
    number = "+919876543210"
    reporter = uuid4()
    event = ReputationReportRequest(
        phoneNumber=number,
        reporterId=reporter,
        category="financial_fraud",
    )
    first = store.report(event)
    second = store.report(event)
    assert first.reportCount == 1
    assert second.reportCount == 1
    dump = " ".join(store._connection.iterdump())
    assert number not in dump
    assert str(reporter) not in dump
    store.close()


def test_multiple_reporters_increase_confidence() -> None:
    store = CommunityReputationStore(":memory:", "test-secret-with-enough-entropy")
    number = "+919876543211"
    for _ in range(3):
        store.report(
            ReputationReportRequest(
                phoneNumber=number,
                reporterId=uuid4(),
                category="impersonation",
            )
        )
    result = store.lookup(number)
    assert result.found is True
    assert result.reportCount == 3
    assert result.risk >= 70
    assert result.confidence > 0.5
    store.close()


def test_unknown_number_has_neutral_reputation() -> None:
    store = CommunityReputationStore(":memory:", "test-secret-with-enough-entropy")
    result = store.lookup("+919876543212")
    assert result.found is False
    assert result.risk == 0
    assert result.source == "none"
    store.close()
