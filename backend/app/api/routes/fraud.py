from __future__ import annotations

from fastapi import APIRouter

from app.api.dependencies import Container, CurrentUser
from app.domain.models import (
    CallAnalysisRequest,
    FeedbackRequest,
    FeedbackResponse,
    FraudAnalysisResponse,
    ImageAnalysisRequest,
    MessageAnalysisRequest,
)

router = APIRouter(tags=["fraud analysis"])


@router.post("/fraud/analyze-message", response_model=FraudAnalysisResponse)
async def analyze_message(
    request: MessageAnalysisRequest, user_id: CurrentUser, container: Container
) -> FraudAnalysisResponse:
    return await container.analyzer.analyze_text(user_id, request.text, request.language)


@router.post("/fraud/analyze-image", response_model=FraudAnalysisResponse)
async def analyze_image(
    request: ImageAnalysisRequest, user_id: CurrentUser, container: Container
) -> FraudAnalysisResponse:
    return await container.analyzer.analyze_image(
        user_id,
        request.image_base64,
        request.mime_type,
        request.context,
        request.language,
    )


@router.post("/call/analyze", response_model=FraudAnalysisResponse)
async def analyze_call(
    request: CallAnalysisRequest, user_id: CurrentUser, container: Container
) -> FraudAnalysisResponse:
    text = request.transcript or "Audio received; transcription provider is not configured."
    return await container.analyzer.analyze_text(user_id, text, request.language, kind="CALL")


@router.post("/fraud/feedback", response_model=FeedbackResponse)
def submit_feedback(
    request: FeedbackRequest, user_id: CurrentUser, container: Container
) -> FeedbackResponse:
    event = container.repository.get_event(user_id, request.event_id)
    if not event:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="Fraud event not found")
    container.repository.feedback.append(
        {"user_id": user_id, "event_id": request.event_id, "verdict": request.user_verdict}
    )
    return FeedbackResponse(status="RECORDED")
