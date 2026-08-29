from __future__ import annotations

from fastapi import APIRouter

from app.api.dependencies import Container, CurrentUser
from app.domain.models import PaymentCheckRequest, PaymentCheckResponse

router = APIRouter(prefix="/payment", tags=["payment protection"])


@router.post("/check", response_model=PaymentCheckResponse)
def check_payment(
    request: PaymentCheckRequest, user_id: CurrentUser, container: Container
) -> PaymentCheckResponse:
    return container.payments.check(user_id, request)
