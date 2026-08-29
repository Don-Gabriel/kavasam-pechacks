import asyncio
import base64
from uuid import uuid4

import pytest

from app.content_analysis import ContentAnalyzer
from app.schemas import ContentAnalysisRequest, FileAnalysisRequest, UrlAnalysisRequest


def test_message_rules_flag_combined_scam_tactics() -> None:
    analyzer = ContentAnalyzer()
    analyzer.api_key = ""
    result = asyncio.run(
        analyzer.analyze_text(
            ContentAnalysisRequest(
                schemaVersion=1,
                sessionId=uuid4(),
                kind="message",
                text=(
                    "URGENT! Transfer payment right now or your account will be blocked. "
                    "Send your OTP and install AnyDesk. Do not tell anyone!!!"
                ),
                locale="en-IN",
            )
        )
    )
    assert result.risk > 80
    assert result.level == "critical"
    assert "credential_request" in result.indicators
    assert "remote_access" in result.indicators


def test_known_shortener_is_dangerous_without_following_it() -> None:
    analyzer = ContentAnalyzer()
    analyzer.api_key = ""
    result = asyncio.run(
        analyzer.analyze_url(
            UrlAnalysisRequest(
                schemaVersion=1,
                sessionId=uuid4(),
                url="https://tinyurl.com/example",
                locale="en-IN",
            )
        )
    )
    assert result.risk > 80
    assert result.urlAssessment is not None
    assert result.urlAssessment.usesShortener is True
    assert result.urlAssessment.reachable is False


def test_private_url_destination_is_rejected() -> None:
    analyzer = ContentAnalyzer()
    with pytest.raises(ValueError, match="Private, local"):
        asyncio.run(
            analyzer.analyze_url(
                UrlAnalysisRequest(
                    schemaVersion=1,
                    sessionId=uuid4(),
                    url="http://127.0.0.1/internal",
                    locale="en-IN",
                )
            )
        )


def test_screenshot_signature_and_size_are_validated() -> None:
    analyzer = ContentAnalyzer()
    analyzer.api_key = ""
    valid_png = b"\x89PNG\r\n\x1a\n" + b"demo"
    result = asyncio.run(
        analyzer.analyze_file(
            FileAnalysisRequest(
                schemaVersion=1,
                sessionId=uuid4(),
                kind="screenshot",
                fileName="message.png",
                mimeType="image/png",
                dataBase64=base64.b64encode(valid_png).decode(),
                locale="en-IN",
            )
        )
    )
    assert result.source == "rules-fallback"
    with pytest.raises(ValueError, match="supported image"):
        asyncio.run(
            analyzer.analyze_file(
                FileAnalysisRequest(
                    schemaVersion=1,
                    sessionId=uuid4(),
                    kind="screenshot",
                    fileName="fake.png",
                    mimeType="image/png",
                    dataBase64=base64.b64encode(b"not-an-image").decode(),
                    locale="en-IN",
                )
            )
        )
