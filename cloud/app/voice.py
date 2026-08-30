"""ElevenLabs spoken scam warnings.

Turns a short English warning into speech. For Tamil, the warning is first
translated with Gemini, then voiced with the Tamil voice, so an elderly user
hears the alert in their own language. Only the warning text and language ever
leave the gateway - no caller identity, number, or audio.
"""

import base64
import json
import os
import re

import httpx

ELEVENLABS_TTS_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
ELEVENLABS_MODEL = "eleven_multilingual_v2"
MAX_WARNING_CHARS = 320


class VoiceWarningService:
    def __init__(self) -> None:
        self.api_key = os.getenv("ELEVENLABS_API_KEY", "").strip()
        self.voice_en = os.getenv("ELEVENLABS_VOICE_ID_EN", "").strip()
        self.voice_ta = os.getenv("ELEVENLABS_VOICE_ID_TA", "").strip()
        self._gemini_key = os.getenv("GEMINI_API_KEY", "").strip()
        model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash-lite").strip()
        self._gemini_model = (
            model if re.fullmatch(r"[A-Za-z0-9._-]+", model) else "gemini-3.5-flash-lite"
        )

    @property
    def configured(self) -> bool:
        return bool(self.api_key and (self.voice_en or self.voice_ta))

    def _voice_for(self, language: str) -> str:
        if language == "ta" and self.voice_ta:
            return self.voice_ta
        return self.voice_en or self.voice_ta

    async def synthesize(self, text: str, language: str) -> tuple[bytes, str]:
        """Returns (mp3_bytes, spoken_text). Raises RuntimeError when unavailable."""
        if not self.configured:
            raise RuntimeError("Voice warnings are not configured on the gateway.")
        spoken = text.strip()[:MAX_WARNING_CHARS]
        if language == "ta":
            spoken = await self._to_tamil(spoken)
        voice_id = self._voice_for(language)
        if not voice_id:
            raise RuntimeError("No ElevenLabs voice is configured for that language.")
        payload = {
            "text": spoken,
            "model_id": ELEVENLABS_MODEL,
            "voice_settings": {"stability": 0.5, "similarity_boost": 0.75},
        }
        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                response = await client.post(
                    ELEVENLABS_TTS_URL.format(voice_id=voice_id),
                    headers={
                        "xi-api-key": self.api_key,
                        "accept": "audio/mpeg",
                        "content-type": "application/json",
                    },
                    json=payload,
                )
                response.raise_for_status()
        except httpx.HTTPError as error:
            raise RuntimeError("ElevenLabs speech synthesis failed.") from error
        return response.content, spoken

    async def _to_tamil(self, text: str) -> str:
        if not self._gemini_key:
            return text
        prompt = (
            "Translate this phone-scam safety warning into natural spoken Tamil. "
            "Return only the Tamil translation with no notes.\n\n"
            f"Warning: {text}"
        )
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.0, "thinkingConfig": {"thinkingLevel": "LOW"}},
        }
        url = (
            "https://generativelanguage.googleapis.com/v1beta/models/"
            f"{self._gemini_model}:generateContent"
        )
        try:
            async with httpx.AsyncClient(timeout=12.0) as client:
                response = await client.post(
                    url, headers={"x-goog-api-key": self._gemini_key}, json=payload
                )
                response.raise_for_status()
            translated = response.json()["candidates"][0]["content"]["parts"][0]["text"]
            return translated.strip()[:MAX_WARNING_CHARS] or text
        except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError):
            return text


def encode_audio(audio: bytes) -> str:
    return base64.b64encode(audio).decode("ascii")
