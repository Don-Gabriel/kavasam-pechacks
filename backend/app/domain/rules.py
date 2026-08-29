from __future__ import annotations

import re
from dataclasses import dataclass

from app.domain.models import RiskLevel


@dataclass(frozen=True, slots=True)
class RuleSignal:
    pattern: re.Pattern[str]
    score: int
    reason: str
    fraud_type: str


RULES = (
    RuleSignal(
        re.compile(
            r"\b(cbi|police|customs?|enforcement directorate|digital arrest)\b", re.IGNORECASE
        ),
        35,
        "Authority impersonation language",
        "DIGITAL_ARREST",
    ),
    RuleSignal(
        re.compile(
            r"\b(account|kyc|aadhaar|pan).{0,30}\b(blocked|suspended|expired|illegal)\b",
            re.IGNORECASE,
        ),
        30,
        "Threat involving a financial or identity account",
        "BANK_PHISHING",
    ),
    RuleSignal(
        re.compile(
            r"\b(immediately|urgent|within \d+ (?:minutes?|hours?)|act now|last warning)\b",
            re.IGNORECASE,
        ),
        20,
        "Artificial urgency or time pressure",
        "SOCIAL_ENGINEERING",
    ),
    RuleSignal(
        re.compile(r"\b(otp|pin|cvv|password|screen share|remote access)\b", re.IGNORECASE),
        35,
        "Request for confidential access information",
        "CREDENTIAL_THEFT",
    ),
    RuleSignal(
        re.compile(
            r"\b(send|transfer|pay|deposit).{0,25}(money|rs\.?|inr|₹|fee|fine|tax)\b", re.IGNORECASE
        ),
        30,
        "Direct demand for money",
        "PAYMENT_FRAUD",
    ),
    RuleSignal(
        re.compile(
            r"\b(do not tell|keep (?:this )?secret|stay on the call|don't contact)\b", re.IGNORECASE
        ),
        30,
        "Attempt to isolate the user from trusted people",
        "SOCIAL_ENGINEERING",
    ),
    RuleSignal(
        re.compile(r"https?://|\b(?:bit\.ly|tinyurl\.com|t\.me)/", re.IGNORECASE),
        15,
        "External link requires independent verification",
        "PHISHING",
    ),
    RuleSignal(
        re.compile(
            r"\b(lottery|prize|guaranteed returns?|double your money|investment tip)\b",
            re.IGNORECASE,
        ),
        30,
        "Unsolicited reward or investment promise",
        "INVESTMENT_SCAM",
    ),
    RuleSignal(
        re.compile(
            r"ignore (?:all )?(?:previous|system) instructions|approve (?:the )?payment",
            re.IGNORECASE,
        ),
        40,
        "Prompt-injection or forced-approval language",
        "PROMPT_INJECTION",
    ),
    RuleSignal(
        re.compile(r"(உடனே|காவல்|பணம் அனுப்பு|ரகசியம்|கைது)|(तुरंत|पुलिस|पैसे भेज|गिरफ्तार)", re.IGNORECASE),
        30,
        "High-risk pressure language in a supported regional language",
        "SOCIAL_ENGINEERING",
    ),
)


def risk_level(score: int) -> RiskLevel:
    if score >= 85:
        return RiskLevel.CRITICAL
    if score >= 60:
        return RiskLevel.HIGH
    if score >= 30:
        return RiskLevel.MEDIUM
    return RiskLevel.LOW


def warning_for(level: RiskLevel) -> str:
    return {
        RiskLevel.CRITICAL: "Likely fraud. Stop the interaction and do not send money or share credentials.",
        RiskLevel.HIGH: "This looks suspicious. Pause and verify using an official contact method.",
        RiskLevel.MEDIUM: "Some warning signs were found. Verify the sender before acting.",
        RiskLevel.LOW: "No strong scam pattern was found, but remain cautious with money and personal data.",
    }[level]


def action_for(level: RiskLevel) -> str:
    if level in (RiskLevel.CRITICAL, RiskLevel.HIGH):
        return "End contact, preserve the evidence, verify independently, and alert a trusted guardian."
    if level is RiskLevel.MEDIUM:
        return "Do not use supplied links; contact the organization through its official app or website."
    return "Continue only if you recognize the sender and independently trust the request."
