from __future__ import annotations

from dataclasses import dataclass

from app.core.config import Settings
from app.core.security import TokenManager
from app.repositories.memory import InMemoryRepository
from app.services.analyzer import FraudAnalyzer
from app.services.automation import N8nAutomationClient
from app.services.elevenlabs import ElevenLabsVoiceClient
from app.services.gemini import GeminiFraudClient
from app.services.guardians import GuardianService
from app.services.payments import PaymentRiskService
from app.services.reports import ReportService


@dataclass(slots=True)
class AppContainer:
    settings: Settings
    repository: InMemoryRepository
    tokens: TokenManager
    analyzer: FraudAnalyzer
    payments: PaymentRiskService
    guardians: GuardianService
    reports: ReportService
    voice: ElevenLabsVoiceClient | None

    @classmethod
    def build(cls, settings: Settings) -> AppContainer:
        repository = InMemoryRepository()
        gemini_api_keys = settings.configured_gemini_api_keys
        gemini = (
            GeminiFraudClient(gemini_api_keys, settings.gemini_model)
            if gemini_api_keys
            else None
        )
        automation = (
            N8nAutomationClient(
                settings.n8n_guardian_webhook_url,
                settings.n8n_signing_secret,
            )
            if settings.n8n_guardian_webhook_url
            else None
        )
        elevenlabs_api_keys = settings.configured_elevenlabs_api_keys
        voice = (
            ElevenLabsVoiceClient(
                elevenlabs_api_keys,
                settings.elevenlabs_voice_id,
                settings.elevenlabs_model,
            )
            if elevenlabs_api_keys
            else None
        )
        return cls(
            settings=settings,
            repository=repository,
            tokens=TokenManager(settings.secret_key, settings.token_ttl_minutes),
            analyzer=FraudAnalyzer(repository, gemini),
            payments=PaymentRiskService(repository),
            guardians=GuardianService(repository, automation),
            reports=ReportService(repository),
            voice=voice,
        )
