from fastapi.testclient import TestClient

from app.content_analysis import ContentAnalyzer
from app.elastic_search import ElasticScamStore
from app.main import app


def test_store_without_credentials_is_unconfigured() -> None:
    store = ElasticScamStore(url="", api_key="")
    assert store.configured is False
    assert store.status == "not-configured"
    assert store.match("anything") is None


def test_health_exposes_elastic_flags() -> None:
    body = TestClient(app).get("/health").json()
    assert "elasticConfigured" in body
    assert "elasticStatus" in body


class _StubRetriever:
    configured = True

    def match(self, text: str):
        return {
            "label": "Credential phishing (account verification)",
            "category": "credential_phishing",
            "score": 12.3,
        }


def test_email_pattern_used_when_retriever_configured() -> None:
    analyzer = ContentAnalyzer(email_retriever=_StubRetriever())
    match = analyzer._email_pattern("verify your account password and otp now")
    assert match is not None
    assert match["category"] == "credential_phishing"


def test_email_pattern_none_without_retriever() -> None:
    analyzer = ContentAnalyzer()  # no retriever configured
    assert analyzer._email_pattern("verify your account now") is None
