from __future__ import annotations

from dataclasses import dataclass

import httpx


@dataclass(frozen=True, slots=True)
class ElevenLabsVoiceClient:
    api_key: str
    voice_id: str
    model: str = "eleven_multilingual_v2"
    timeout_seconds: float = 15.0

    async def synthesize(self, text: str) -> bytes | None:
        endpoint = f"https://api.elevenlabs.io/v1/text-to-speech/{self.voice_id}"
        try:
            async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                response = await client.post(
                    endpoint,
                    params={"output_format": "mp3_44100_128"},
                    headers={
                        "xi-api-key": self.api_key,
                        "Content-Type": "application/json",
                        "Accept": "audio/mpeg",
                    },
                    json={
                        "text": text,
                        "model_id": self.model,
                        "voice_settings": {
                            "stability": 0.72,
                            "similarity_boost": 0.75,
                            "style": 0.1,
                            "use_speaker_boost": True,
                        },
                    },
                )
                response.raise_for_status()
            return response.content
        except httpx.HTTPError:
            return None
