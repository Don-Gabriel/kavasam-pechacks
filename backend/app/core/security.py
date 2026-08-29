from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from dataclasses import dataclass

from fastapi import HTTPException, status


def _encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


@dataclass(frozen=True, slots=True)
class TokenManager:
    secret_key: str
    ttl_minutes: int

    def issue(self, user_id: str) -> str:
        now = int(time.time())
        payload = {"sub": user_id, "iat": now, "exp": now + self.ttl_minutes * 60}
        encoded_payload = _encode(json.dumps(payload, separators=(",", ":")).encode())
        signature = hmac.new(
            self.secret_key.encode(), encoded_payload.encode(), hashlib.sha256
        ).digest()
        return f"{encoded_payload}.{_encode(signature)}"

    def verify(self, token: str) -> str:
        try:
            encoded_payload, encoded_signature = token.split(".", maxsplit=1)
            expected = hmac.new(
                self.secret_key.encode(), encoded_payload.encode(), hashlib.sha256
            ).digest()
            if not hmac.compare_digest(expected, _decode(encoded_signature)):
                raise ValueError("signature mismatch")
            payload = json.loads(_decode(encoded_payload))
            if int(payload["exp"]) < int(time.time()):
                raise ValueError("token expired")
            return str(payload["sub"])
        except (ValueError, KeyError, json.JSONDecodeError) as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired access token",
                headers={"WWW-Authenticate": "Bearer"},
            ) from exc
