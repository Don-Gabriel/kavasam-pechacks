from __future__ import annotations

import base64

from fastapi import APIRouter, HTTPException

from app.api.dependencies import Container, CurrentUser
from app.domain.models import VoiceWarningRequest, VoiceWarningResponse

router = APIRouter(prefix="/voice", tags=["accessible warnings"])


@router.post("/warning", response_model=VoiceWarningResponse)
async def create_voice_warning(
    request: VoiceWarningRequest,
    _user_id: CurrentUser,
    container: Container,
) -> VoiceWarningResponse:
    if not container.voice:
        raise HTTPException(status_code=503, detail="Natural voice provider is not configured")
    audio = await container.voice.synthesize(request.text)
    if not audio:
        raise HTTPException(status_code=502, detail="Natural voice generation failed")
    return VoiceWarningResponse(audio_base64=base64.b64encode(audio).decode())
