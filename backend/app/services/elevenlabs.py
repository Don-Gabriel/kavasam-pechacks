from __future__ import annotations

from dataclasses import dataclass, field

import httpx

_KEY_FALLBACK_STATUS_CODES = frozenset({401, 402, 403, 429})


@dataclass(slots=True)
class ElevenLabsVoiceClient:
    api_keys: tuple[str, ...]
    voice_id: str
    model: str = "eleven_multilingual_v2"
    timeout_seconds: float = 15.0
    _active_key_index: int = field(default=0, init=False, repr=False)

    async def synthesize(self, text: str) -> bytes | None:
        endpoint = f"https://api.elevenlabs.io/v1/text-to-speech/{self.voice_id}"
        for offset in range(len(self.api_keys)):
            key_index = (self._active_key_index + offset) % len(self.api_keys)
            try:
                async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                    response = await client.post(
                        endpoint,
                        params={"output_format": "mp3_44100_128"},
                        headers={
                            "xi-api-key": self.api_keys[key_index],
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
            except httpx.HTTPStatusError as error:
                if error.response.status_code in _KEY_FALLBACK_STATUS_CODES:
                    continue
                return None
            except httpx.HTTPError:
                return None

            self._active_key_index = key_index
            return response.content
        return None
