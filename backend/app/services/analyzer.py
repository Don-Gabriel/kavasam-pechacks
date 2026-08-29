from __future__ import annotations

from collections import defaultdict

from app.domain.models import FraudAnalysisResponse
from app.domain.rules import RULES, action_for, risk_level, warning_for
from app.repositories.memory import InMemoryRepository
from app.services.gemini import GeminiFraudClient


class FraudAnalyzer:
    def __init__(
        self,
        repository: InMemoryRepository,
        gemini: GeminiFraudClient | None = None,
    ) -> None:
        self.repository = repository
        self.gemini = gemini

    async def analyze_text(
        self,
        user_id: str,
        text: str,
        language: str,
        kind: str = "MESSAGE",
    ) -> FraudAnalysisResponse:
        reasons: list[str] = []
        type_scores: dict[str, int] = defaultdict(int)
        score = 5

        for signal in RULES:
            if signal.pattern.search(text):
                score += signal.score
                type_scores[signal.fraud_type] += signal.score
                if signal.reason not in reasons:
                    reasons.append(signal.reason)

        score = min(score, 100)
        specific_types = {
            fraud_type: type_score
            for fraud_type, type_score in type_scores.items()
            if fraud_type not in {"SOCIAL_ENGINEERING", "PHISHING"}
        }
        classification_pool = specific_types or type_scores
        fraud_type = (
            max(classification_pool, key=classification_pool.get)
            if classification_pool
            else "NO_STRONG_PATTERN"
        )
        source = "rules"
        ai_assessment = await self.gemini.analyze_text(text, language) if self.gemini else None

        if ai_assessment:
            source = "rules+gemini"
            # A model can add caution but cannot override deterministic warning signals downward.
            if ai_assessment.risk_score > score:
                score = ai_assessment.risk_score
                fraud_type = ai_assessment.fraud_type
            reasons.extend(reason for reason in ai_assessment.evidence if reason not in reasons)

        level = risk_level(score)
        confidence = min(0.98, 0.45 + (len(reasons) * 0.1)) if reasons else 0.55
        result = {
            "risk_score": score,
            "risk_level": level,
            "fraud_type": fraud_type,
            "confidence": confidence,
            "reasons": reasons or ["No known high-risk manipulation pattern matched"],
            "warning": warning_for(level),
            "recommended_action": action_for(level),
            "analysis_source": source,
        }
        event_id = self.repository.save_event(user_id, kind, result)
        return FraudAnalysisResponse(event_id=event_id, **result)

    async def analyze_image(
        self,
        user_id: str,
        image_base64: str,
        mime_type: str,
        context: str,
        language: str,
    ) -> FraudAnalysisResponse:
        # The adapter boundary is ready for multimodal Gemini. Context is analyzed now so
        # local demos stay useful without uploading sensitive images to a third party.
        local_context = context or f"User submitted a {mime_type} image for fraud analysis."
        return await self.analyze_text(user_id, local_context, language, kind="IMAGE")
