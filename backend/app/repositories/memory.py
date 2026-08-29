from __future__ import annotations

import hmac
import secrets
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any


@dataclass(slots=True)
class InMemoryRepository:
    sessions: dict[str, dict[str, Any]] = field(default_factory=dict)
    users: dict[str, dict[str, Any]] = field(default_factory=dict)
    events: dict[str, dict[str, Any]] = field(default_factory=dict)
    guardians: dict[str, list[dict[str, Any]]] = field(default_factory=dict)
    alerts: list[dict[str, Any]] = field(default_factory=list)
    feedback: list[dict[str, Any]] = field(default_factory=list)

    def create_session(self, phone_number: str, otp: str) -> str:
        session_id = secrets.token_urlsafe(24)
        self.sessions[session_id] = {"phone_number": phone_number, "otp": otp, "used": False}
        return session_id

    def verify_session(self, session_id: str, otp: str) -> str | None:
        session = self.sessions.get(session_id)
        if not session or session["used"] or not hmac.compare_digest(session["otp"], otp):
            return None
        session["used"] = True
        user_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"kavasam:{session['phone_number']}"))
        self.users.setdefault(
            user_id,
            {
                "id": user_id,
                "phone_number": session["phone_number"],
                "created_at": datetime.now(UTC).isoformat(),
            },
        )
        return user_id

    def save_event(self, user_id: str, kind: str, result: dict[str, Any]) -> str:
        event_id = str(uuid.uuid4())
        self.events[event_id] = {
            "id": event_id,
            "user_id": user_id,
            "kind": kind,
            "result": result,
            "timestamp": datetime.now(UTC).isoformat(),
        }
        return event_id

    def get_event(self, user_id: str, event_id: str) -> dict[str, Any] | None:
        event = self.events.get(event_id)
        return event if event and event["user_id"] == user_id else None
