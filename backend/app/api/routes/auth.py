from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from app.api.dependencies import Container
from app.domain.models import LoginRequest, LoginResponse, VerifyRequest, VerifyResponse

router = APIRouter(prefix="/auth", tags=["authentication"])


@router.post("/login", response_model=LoginResponse)
def login(request: LoginRequest, container: Container) -> LoginResponse:
    session_id = container.repository.create_session(
        request.phone_number, container.settings.dev_otp
    )
    return LoginResponse(
        message="OTP sent",
        session_id=session_id,
        dev_otp=container.settings.dev_otp if container.settings.expose_dev_otp else None,
    )


@router.post("/verify", response_model=VerifyResponse)
def verify(request: VerifyRequest, container: Container) -> VerifyResponse:
    user_id = container.repository.verify_session(request.session_id, request.otp)
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid OTP session")
    return VerifyResponse(access_token=container.tokens.issue(user_id), user_id=user_id)
