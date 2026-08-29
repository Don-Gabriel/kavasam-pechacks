from __future__ import annotations

from fastapi import APIRouter

from app.api.dependencies import Container, CurrentUser
from app.domain.models import ReportGenerateRequest, ReportResponse

router = APIRouter(prefix="/report", tags=["cybercrime reporting"])


@router.post("/generate", response_model=ReportResponse)
def generate_report(
    request: ReportGenerateRequest, user_id: CurrentUser, container: Container
) -> ReportResponse:
    return container.reports.generate(user_id, request)
