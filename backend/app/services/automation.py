from __future__ import annotations

import hashlib
import hmac
import json
from dataclasses import dataclass
from typing import Any

import httpx


@dataclass(frozen=True, slots=True)
class N8nAutomationClient:
    webhook_url: str
    signing_secret: str | None = None
    timeout_seconds: float = 6.0

    async def dispatch_guardian_alert(self, payload: dict[str, Any]) -> bool:
        encoded = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
        headers = {"Content-Type": "application/json"}
        if self.signing_secret:
            headers["X-Kavasam-Signature"] = hmac.new(
                self.signing_secret.encode(), encoded, hashlib.sha256
            ).hexdigest()
        try:
            async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                response = await client.post(
                    self.webhook_url,
                    content=encoded,
                    headers=headers,
                )
                response.raise_for_status()
            return True
        except httpx.HTTPError:
            return False
