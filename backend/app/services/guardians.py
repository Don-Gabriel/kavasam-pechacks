from __future__ import annotations

import uuid

from app.domain.models import (
    GuardianAddRequest,
    GuardianAlertRequest,
    GuardianAlertResponse,
    GuardianLinkResponse,
)
from app.repositories.memory import InMemoryRepository


class GuardianService:
    def __init__(self, repository: InMemoryRepository) -> None:
        self.repository = repository

    def add(self, user_id: str, request: GuardianAddRequest) -> GuardianLinkResponse:
        guardian_id = str(uuid.uuid4())
        record = {
            "guardian_id": guardian_id,
            "guardian_phone": request.guardian_phone,
            "guardian_name": request.guardian_name,
            # Production adapters complete mutual OTP approval before activation.
            "status": "PENDING_APPROVAL",
        }
        self.repository.guardians.setdefault(user_id, []).append(record)
        return GuardianLinkResponse(
            guardian_id=guardian_id,
            guardian_name=request.guardian_name,
            status=record["status"],
        )

    def alert(self, user_id: str, request: GuardianAlertRequest) -> GuardianAlertResponse:
        recipients = [g for g in self.repository.guardians.get(user_id, [])]
        alert_id = str(uuid.uuid4())
        self.repository.alerts.append(
            {
                "alert_id": alert_id,
                "user_id": user_id,
                "event_id": request.event_id,
                "message": request.message,
                "recipients": len(recipients),
            }
        )
        return GuardianAlertResponse(
            alert_id=alert_id,
            status="QUEUED" if recipients else "NO_GUARDIAN_LINKED",
            recipients=len(recipients),
        )
