from __future__ import annotations

from dataclasses import dataclass

from app.core.config import Settings
from app.core.security import TokenManager
from app.repositories.memory import InMemoryRepository
from app.services.analyzer import FraudAnalyzer
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

    @classmethod
    def build(cls, settings: Settings) -> AppContainer:
        repository = InMemoryRepository()
        gemini = (
            GeminiFraudClient(settings.gemini_api_key, settings.gemini_model)
            if settings.gemini_api_key
            else None
        )
        return cls(
            settings=settings,
            repository=repository,
            tokens=TokenManager(settings.secret_key, settings.token_ttl_minutes),
            analyzer=FraudAnalyzer(repository, gemini),
            payments=PaymentRiskService(repository),
            guardians=GuardianService(repository),
            reports=ReportService(repository),
        )
