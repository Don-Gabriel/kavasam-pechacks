import asyncio
from uuid import uuid4

import httpx

from app.actian_vector import ActianVectorStore, augment_with_actian, safety_vector
from app.analyzer import fallback_analysis
from app.schemas import SafetyAnalysisRequest


def event() -> SafetyAnalysisRequest:
    return SafetyAnalysisRequest.model_validate(
        {
            "schemaVersion": 1,
            "sessionId": str(uuid4()),
            "localRisk": 72,
            "vectorSimilarity": 0.84,
            "signals": ["otp_pin", "secrecy_urgency"],
            "callerContext": {
                "savedContact": False,
                "locallyReported": True,
                "carrierVerificationFailed": False,
            },
            "locale": "en-IN",
        }
    )


def test_safety_vector_is_fixed_size_and_contains_no_pii() -> None:
    vector = safety_vector(event())
    assert len(vector) == ActianVectorStore.dimension
    assert all(isinstance(value, float) for value in vector)
    assert all(0.0 <= value <= 1.0 for value in vector)


def test_actian_creates_seeds_and_searches_real_rest_endpoints() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.method == "POST":
            return httpx.Response(
                200,
                json={
                    "status": "ok",
                    "result": [
                        {
                            "id": 1,
                            "score": 0.93,
                            "payload": {
                                "category": "credential_theft",
                                "label": "OTP or PIN credential theft",
                                "risk_floor": 88,
                                "reason": "The signal pattern resembles an OTP/PIN theft attempt.",
                            },
                        }
                    ],
                },
            )
        return httpx.Response(200, json={"status": "ok", "result": True})

    store = ActianVectorStore(
        base_url="http://vectorai.test:6573",
        access_token="test-token",
        collection="kavasam_test_patterns",
        transport=httpx.MockTransport(handler),
    )
    match = asyncio.run(store.match(event()))

    assert match is not None
    assert match.category == "credential_theft"
    assert match.similarity == 0.93
    assert [request.method for request in requests] == ["PUT", "PUT", "POST"]
    assert requests[0].url.path == "/collections/kavasam_test_patterns"
    assert requests[1].url.path.endswith("/points")
    assert requests[2].url.path.endswith("/points/search")
    assert all(request.headers["authorization"] == "Bearer test-token" for request in requests)
    assert store.status == "ready"


def test_actian_failure_fails_open_to_local_advice() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503, json={"status": {"error": "offline"}})

    store = ActianVectorStore(
        base_url="http://vectorai.test:6573",
        transport=httpx.MockTransport(handler),
    )
    safety_event = event()
    match = asyncio.run(store.match(safety_event))
    result = augment_with_actian(fallback_analysis(safety_event), match, store)

    assert match is None
    assert store.status == "unavailable"
    assert result.vectorDatabase == "actian-unavailable"
    assert result.vectorMatch is None
    assert result.reasons


def test_actian_recreates_stale_collection_after_search_404() -> None:
    requests: list[httpx.Request] = []
    search_attempts = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal search_attempts
        requests.append(request)
        if request.method == "POST":
            search_attempts += 1
            if search_attempts == 1:
                return httpx.Response(
                    404,
                    json={"status": {"error": "Collection not found"}},
                )
            return httpx.Response(
                200,
                json={
                    "status": "ok",
                    "result": [
                        {
                            "id": 2,
                            "score": 0.91,
                            "payload": {
                                "category": "payment_fraud",
                                "label": "Urgent payment or transfer fraud",
                                "risk_floor": 90,
                                "reason": "The signal pattern resembles urgent payment fraud.",
                            },
                        }
                    ],
                },
            )
        return httpx.Response(200, json={"status": "ok", "result": True})

    store = ActianVectorStore(
        base_url="http://vectorai.test:6573",
        transport=httpx.MockTransport(handler),
    )
    match = asyncio.run(store.match(event()))

    assert match is not None
    assert match.category == "payment_fraud"
    assert [request.method for request in requests] == [
        "PUT",
        "PUT",
        "POST",
        "DELETE",
        "PUT",
        "PUT",
        "POST",
    ]
    assert store.status == "ready"


def test_actian_match_is_visible_and_can_raise_advisory_risk() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "POST":
            return httpx.Response(
                200,
                json={
                    "status": "ok",
                    "result": [
                        {
                            "id": 3,
                            "score": 0.96,
                            "payload": {
                                "category": "remote_access",
                                "label": "Remote-access takeover",
                                "risk_floor": 92,
                                "reason": "The signal pattern resembles a remote-access takeover scam.",
                            },
                        }
                    ],
                },
            )
        return httpx.Response(200, json={"status": "ok", "result": True})

    store = ActianVectorStore(
        base_url="http://vectorai.test:6573",
        transport=httpx.MockTransport(handler),
    )
    safety_event = event()
    match = asyncio.run(store.match(safety_event))
    result = augment_with_actian(fallback_analysis(safety_event), match, store)

    assert result.vectorDatabase == "actian-vectorai"
    assert result.vectorMatch is not None
    assert result.vectorMatch.label == "Remote-access takeover"
    assert result.risk >= 88
