from __future__ import annotations

import re

from app.domain.models import PaymentCheckRequest, PaymentCheckResponse
from app.repositories.memory import InMemoryRepository

UPI_PATTERN = re.compile(r"^[A-Za-z0-9._-]{2,256}@[A-Za-z]{2,64}$")
BUSINESS_TERMS = re.compile(
    r"\b(store|shop|mart|hotel|restaurant|pharmacy|services?)\b", re.IGNORECASE
)
PERSONAL_HANDLES = re.compile(r"@(oksbi|okaxis|okhdfcbank|okicici|ybl|paytm)$", re.IGNORECASE)
PRESSURE_TERMS = re.compile(
    r"\b(urgent|refund|verification fee|release amount|cashback)\b", re.IGNORECASE
)


class PaymentRiskService:
    def __init__(self, repository: InMemoryRepository) -> None:
        self.repository = repository

    def check(self, user_id: str, request: PaymentCheckRequest) -> PaymentCheckResponse:
        score = 5
        reasons: list[str] = []
        if not UPI_PATTERN.fullmatch(request.upi_id):
            score += 55
            reasons.append("UPI address format is invalid or unusual")
        if BUSINESS_TERMS.search(request.merchant_name) and PERSONAL_HANDLES.search(request.upi_id):
            score += 30
            reasons.append("Business payment appears to use a personal UPI handle")
        if request.amount >= 25_000:
            score += 15
            reasons.append("High-value payment deserves independent verification")
        if PRESSURE_TERMS.search(request.context):
            score += 30
            reasons.append("Payment context contains a known pressure tactic")

        score = min(score, 100)
        if score >= 70:
            status = "WARNING"
            action = "Do not pay until the recipient is verified through an independent channel."
        elif score >= 30:
            status = "VERIFY"
            action = "Confirm the displayed recipient name and UPI address before paying."
        else:
            status = "SAFE"
            action = (
                "No strong warning was found; confirm the recipient before authorizing payment."
            )

        reasons = reasons or ["UPI format and payment context show no known warning pattern"]
        event_id = self.repository.save_event(
            user_id,
            "PAYMENT",
            {"risk_score": score, "status": status, "reasons": reasons},
        )
        return PaymentCheckResponse(
            event_id=event_id,
            risk_score=score,
            status=status,
            reason=reasons[0],
            reasons=reasons,
            recommended_action=action,
        )
