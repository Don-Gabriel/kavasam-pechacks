from __future__ import annotations

import asyncio
import json
from collections.abc import Callable

import httpx

from app.core.config import Settings
from app.services.elevenlabs import ElevenLabsVoiceClient
from app.services.gemini import GeminiFraudClient


def _response(status_code: int, *, json_body: object | None = None, content: bytes = b""):
    request = httpx.Request("POST", "https://provider.example/test")
    if json_body is not None:
        return httpx.Response(status_code, request=request, json=json_body)
    return httpx.Response(status_code, request=request, content=content)


def _fake_client_factory(
    responses: list[httpx.Response],
    observed_keys: list[str],
    header_name: str,
) -> Callable[..., object]:
    class FakeAsyncClient:
        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, traceback):
            return False

        async def post(self, endpoint, *, headers, **kwargs):
            observed_keys.append(headers[header_name])
            return responses.pop(0)

    return lambda **kwargs: FakeAsyncClient()


def _gemini_success_response() -> httpx.Response:
    assessment = {
        "risk_score": 91,
        "fraud_type": "impersonation",
        "confidence": 0.94,
        "evidence": ["Requests urgent payment"],
        "warning": "Do not transfer money.",
        "recommended_action": "Contact the organisation independently.",
    }
    return _response(
        200,
        json_body={
            "candidates": [
                {"content": {"parts": [{"text": json.dumps(assessment)}]}}
            ]
        },
    )


def test_settings_load_four_ordered_provider_keys(monkeypatch):
    for provider in ("GEMINI", "ELEVENLABS"):
        monkeypatch.delenv(f"{provider}_API_KEY", raising=False)
        for index in range(1, 5):
            monkeypatch.setenv(f"{provider}_API_KEY_{index}", f"{provider.lower()}-{index}")

    settings = Settings.from_env()

    assert settings.configured_gemini_api_keys == (
        "gemini-1",
        "gemini-2",
        "gemini-3",
        "gemini-4",
    )
    assert settings.configured_elevenlabs_api_keys == (
        "elevenlabs-1",
        "elevenlabs-2",
        "elevenlabs-3",
        "elevenlabs-4",
    )


def test_gemini_rolls_over_and_keeps_the_successful_key(monkeypatch):
    observed_keys: list[str] = []
    responses = [_response(429), _gemini_success_response(), _gemini_success_response()]
    monkeypatch.setattr(
        "app.services.gemini.httpx.AsyncClient",
        _fake_client_factory(responses, observed_keys, "x-goog-api-key"),
    )
    client = GeminiFraudClient(("gemini-1", "gemini-2", "gemini-3"), "test-model")

    first = asyncio.run(client.analyze_text("Transfer now", "English"))
    second = asyncio.run(client.analyze_text("Share your OTP", "English"))

    assert first is not None
    assert second is not None
    assert observed_keys == ["gemini-1", "gemini-2", "gemini-2"]


def test_gemini_does_not_rotate_for_bad_requests(monkeypatch):
    observed_keys: list[str] = []
    responses = [_response(400)]
    monkeypatch.setattr(
        "app.services.gemini.httpx.AsyncClient",
        _fake_client_factory(responses, observed_keys, "x-goog-api-key"),
    )
    client = GeminiFraudClient(("gemini-1", "gemini-2"), "test-model")

    result = asyncio.run(client.analyze_text("hello", "English"))

    assert result is None
    assert observed_keys == ["gemini-1"]


def test_elevenlabs_rolls_over_on_exhausted_key(monkeypatch):
    observed_keys: list[str] = []
    responses = [_response(401), _response(200, content=b"audio")]
    monkeypatch.setattr(
        "app.services.elevenlabs.httpx.AsyncClient",
        _fake_client_factory(responses, observed_keys, "xi-api-key"),
    )
    client = ElevenLabsVoiceClient(("voice-1", "voice-2"), "voice-id")

    result = asyncio.run(client.synthesize("This may be a scam."))

    assert result == b"audio"
    assert observed_keys == ["voice-1", "voice-2"]
