import json
import os
import re

import httpx

from .schemas import SafetyAnalysisRequest, SafetyAnalysisResponse


SIGNAL_DETAILS = {
    "otp_pin": (35, "The caller requested an OTP or PIN."),
    "payment_transfer": (30, "The caller requested an urgent payment or transfer."),
    "remote_access": (35, "The caller requested remote access to the device."),
    "impersonation": (24, "The caller may be impersonating an institution or authority."),
    "secrecy_urgency": (22, "The caller used secrecy or unusual urgency."),
    "threats": (30, "The caller used threats or intimidation."),
}


TRANSCRIPT_KEYWORDS = {
    "otp": (12, "The conversation mentioned an OTP or verification code."),
    "password": (10, "The conversation mentioned a password."),
    "gift card": (14, "The conversation mentioned gift cards, a common scam payment."),
    "anydesk": (16, "The conversation mentioned a remote-access app."),
    "teamviewer": (16, "The conversation mentioned a remote-access app."),
    "arrest": (12, "The conversation contained an arrest threat."),
    "warrant": (10, "The conversation mentioned a warrant."),
    "processing fee": (10, "The conversation asked for an upfront fee."),
    "keep this secret": (10, "The caller asked for secrecy."),
}


def _transcript_findings(transcript: str) -> tuple[int, list[str]]:
    spoken = transcript.lower()
    score = 0
    reasons: list[str] = []
    for phrase, (points, reason) in TRANSCRIPT_KEYWORDS.items():
        if phrase in spoken and reason not in reasons:
            score += points
            reasons.append(reason)
    return min(score, 30), reasons[:2]


def fallback_analysis(event: SafetyAnalysisRequest) -> SafetyAnalysisResponse:
    signal_score = sum(SIGNAL_DETAILS[key][0] for key in event.signals)
    context_score = (
        (12 if event.callerContext.locallyReported else 0)
        + (8 if event.callerContext.carrierVerificationFailed else 0)
        - (12 if event.callerContext.savedContact else 0)
    )
    transcript_score, transcript_reasons = _transcript_findings(event.transcriptExcerpt)
    risk = max(
        0,
        min(
            100,
            round(
                event.localRisk * 0.55
                + signal_score * 0.65
                + context_score
                + transcript_score
            ),
        ),
    )
    level = "critical" if risk >= 85 else "high" if risk >= 60 else "medium" if risk >= 30 else "low"
    reasons = (
        [SIGNAL_DETAILS[key][1] for key in event.signals[:3]] + transcript_reasons
    )[:4]
    if not reasons:
        reasons = ["No high-confidence scam tactic has been selected."]
    actions = (
        [
            "Do not share passwords, OTPs, PINs, or banking details.",
            "End the call and verify using an official number you find independently.",
        ]
        if risk >= 60
        else ["Stay cautious and independently verify unexpected requests."]
    )
    warning = (
        "High scam risk. Do not share credentials or transfer money. End the call and verify independently."
        if risk >= 60
        else "No high-confidence scam pattern yet. Keep personal and financial details private."
    )
    return SafetyAnalysisResponse(
        risk=risk,
        level=level,
        reasons=reasons,
        recommendedActions=actions,
        warningText=warning,
        source="rules-fallback",
    )


class GeminiAnalyzer:
    def __init__(self) -> None:
        self.api_key = os.getenv("GEMINI_API_KEY", "").strip()
        model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash-lite").strip()
        self.model = model if re.fullmatch(r"[A-Za-z0-9._-]+", model) else "gemini-3.5-flash-lite"

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    async def analyze(self, event: SafetyAnalysisRequest) -> SafetyAnalysisResponse:
        if not self.configured:
            return fallback_analysis(event)

        compact_event = event.model_dump(mode="json")
        compact_event.pop("sessionId", None)
        transcript = compact_event.pop("transcriptExcerpt", "") or ""
        # Defense in depth: the phone already masks digit runs before upload.
        transcript = re.sub(r"\d{3,}", "###", transcript)[:2400]
        transcript_block = (
            "\n\nPartial microphone transcript (one-sided, possibly garbled speech "
            "recognition in mixed English/Hindi/Tamil; numbers are masked; treat it "
            f"as weak evidence): {json.dumps(transcript)}"
            if transcript
            else ""
        )
        prompt = (
            "You are a defensive phone-scam safety classifier. Assess only the supplied "
            "structured signals. Do not infer identity, guilt, protected traits, or location. "
            "Give short, calm, actionable advice. This is advisory, not a blocking decision.\n\n"
            f"Event: {json.dumps(compact_event, separators=(',', ':'))}"
            f"{transcript_block}"
        )
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {
                "temperature": 0.1,
                "thinkingConfig": {"thinkingLevel": "LOW"},
                "responseMimeType": "application/json",
                "responseJsonSchema": {
                    "type": "object",
                    "properties": {
                        "risk": {"type": "integer", "minimum": 0, "maximum": 100},
                        "level": {"type": "string", "enum": ["low", "medium", "high", "critical"]},
                        "reasons": {"type": "array", "items": {"type": "string"}, "maxItems": 4},
                        "recommendedActions": {"type": "array", "items": {"type": "string"}, "maxItems": 4},
                        "warningText": {"type": "string", "maxLength": 320},
                    },
                    "required": ["risk", "level", "reasons", "recommendedActions", "warningText"],
                },
            },
        }
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
        try:
            async with httpx.AsyncClient(timeout=12.0) as client:
                response = await client.post(
                    url,
                    headers={"x-goog-api-key": self.api_key},
                    json=payload,
                )
                response.raise_for_status()
            text = response.json()["candidates"][0]["content"]["parts"][0]["text"]
            result = SafetyAnalysisResponse.model_validate({**json.loads(text), "source": "gemini"})
            floor = max(0, min(100, event.localRisk - 15))
            return result.model_copy(update={"risk": max(result.risk, floor)})
        except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError):
            return fallback_analysis(event)
