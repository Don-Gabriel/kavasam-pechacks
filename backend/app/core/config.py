from __future__ import annotations

import os
import secrets
from dataclasses import dataclass, field

from dotenv import load_dotenv


def _load_api_keys(provider: str) -> tuple[str, ...]:
    candidates = [os.getenv(f"{provider}_API_KEY_{index}") for index in range(1, 5)]
    candidates.append(os.getenv(f"{provider}_API_KEY"))

    configured: list[str] = []
    for candidate in candidates:
        key = (candidate or "").strip()
        if key and key not in configured:
            configured.append(key)
    return tuple(configured)


@dataclass(frozen=True, slots=True)
class Settings:
    environment: str = "development"
    secret_key: str = field(default_factory=lambda: secrets.token_urlsafe(48))
    expose_dev_otp: bool = True
    dev_otp: str = field(default_factory=lambda: f"{secrets.randbelow(1_000_000):06d}")
    token_ttl_minutes: int = 60
    rate_limit_per_minute: int = 120
    cors_origins: tuple[str, ...] = ("http://localhost:3000", "http://localhost:5000")
    gemini_api_key: str | None = None
    gemini_api_keys: tuple[str, ...] = ()
    gemini_model: str = "gemini-3.7-flash"
    n8n_guardian_webhook_url: str | None = None
    n8n_signing_secret: str | None = None
    elevenlabs_api_key: str | None = None
    elevenlabs_api_keys: tuple[str, ...] = ()
    elevenlabs_voice_id: str = "JBFqnCBsd6RMkjVDRZzb"
    elevenlabs_model: str = "eleven_multilingual_v2"

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"

    @property
    def configured_gemini_api_keys(self) -> tuple[str, ...]:
        return self._merge_api_keys(self.gemini_api_keys, self.gemini_api_key)

    @property
    def configured_elevenlabs_api_keys(self) -> tuple[str, ...]:
        return self._merge_api_keys(self.elevenlabs_api_keys, self.elevenlabs_api_key)

    @staticmethod
    def _merge_api_keys(keys: tuple[str, ...], legacy_key: str | None) -> tuple[str, ...]:
        merged = [key.strip() for key in keys if key.strip()]
        if legacy_key and legacy_key.strip() not in merged:
            merged.append(legacy_key.strip())
        return tuple(merged)

    @classmethod
    def from_env(cls) -> Settings:
        load_dotenv()
        environment = os.getenv("KAVASAM_ENVIRONMENT", "development")
        configured_secret = os.getenv("KAVASAM_SECRET_KEY")
        origins = tuple(
            origin.strip()
            for origin in os.getenv(
                "KAVASAM_CORS_ORIGINS", "http://localhost:3000,http://localhost:5000"
            ).split(",")
            if origin.strip()
        )
        return cls(
            environment=environment,
            secret_key=configured_secret or secrets.token_urlsafe(48),
            expose_dev_otp=(
                os.getenv("KAVASAM_EXPOSE_DEV_OTP", "true").lower() == "true"
                and environment.lower() != "production"
            ),
            dev_otp=os.getenv("KAVASAM_DEV_OTP") or f"{secrets.randbelow(1_000_000):06d}",
            token_ttl_minutes=int(os.getenv("KAVASAM_TOKEN_TTL_MINUTES", "60")),
            rate_limit_per_minute=int(os.getenv("KAVASAM_RATE_LIMIT_PER_MINUTE", "120")),
            cors_origins=origins,
            gemini_api_keys=_load_api_keys("GEMINI"),
            gemini_model=os.getenv("GEMINI_MODEL", "gemini-3.7-flash"),
            n8n_guardian_webhook_url=os.getenv("N8N_GUARDIAN_WEBHOOK_URL") or None,
            n8n_signing_secret=os.getenv("N8N_SIGNING_SECRET") or None,
            elevenlabs_api_keys=_load_api_keys("ELEVENLABS"),
            elevenlabs_voice_id=os.getenv(
                "ELEVENLABS_VOICE_ID", "JBFqnCBsd6RMkjVDRZzb"
            ),
            elevenlabs_model=os.getenv(
                "ELEVENLABS_MODEL", "eleven_multilingual_v2"
            ),
        )
