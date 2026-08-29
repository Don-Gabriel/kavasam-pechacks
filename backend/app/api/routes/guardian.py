from __future__ import annotations

from fastapi import APIRouter, HTTPException

from app.api.dependencies import Container, CurrentUser
from app.domain.models import (
    GuardianAddRequest,
    GuardianAlertRequest,
    GuardianAlertResponse,
    GuardianLinkResponse,
)

router = APIRouter(prefix="/guardian", tags=["guardian network"])


@router.post("/add", response_model=GuardianLinkResponse)
def add_guardian(
    request: GuardianAddRequest, user_id: CurrentUser, container: Container
) -> GuardianLinkResponse:
    return container.guardians.add(user_id, request)


@router.post("/alert", response_model=GuardianAlertResponse)
async def alert_guardians(
    request: GuardianAlertRequest, user_id: CurrentUser, container: Container
) -> GuardianAlertResponse:
    if not container.repository.get_event(user_id, request.event_id):
        raise HTTPException(status_code=404, detail="Fraud event not found")
    return await container.guardians.alert(user_id, request)
