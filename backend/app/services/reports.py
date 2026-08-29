from __future__ import annotations

import uuid

from fastapi import HTTPException, status

from app.domain.models import ReportGenerateRequest, ReportResponse
from app.repositories.memory import InMemoryRepository


class ReportService:
    def __init__(self, repository: InMemoryRepository) -> None:
        self.repository = repository

    def generate(self, user_id: str, request: ReportGenerateRequest) -> ReportResponse:
        event = self.repository.get_event(user_id, request.event_id)
        if not event:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Fraud event not found"
            )

        result = event["result"]
        score = result.get("risk_score", "unknown")
        kind = event["kind"].lower()
        notes = f" User notes: {request.incident_notes}" if request.incident_notes else ""
        return ReportResponse(
            report_id=str(uuid.uuid4()),
            incident_summary=(
                f"Kavasam analyzed a user-authorized {kind} event with risk score {score}.{notes}"
            ),
            evidence_list=[
                f"Event reference: {event['id']}",
                f"Analysis type: {event['kind']}",
                *result.get("reasons", []),
            ],
            timeline=[f"{event['timestamp']} — Evidence analyzed by Kavasam"],
            recommended_complaint_details=[
                "Call India's cybercrime helpline 1930 immediately if money was transferred.",
                "Submit the draft and original evidence through the official cybercrime portal.",
                "Contact the bank or payment provider using an official number.",
            ],
        )
