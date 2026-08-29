from __future__ import annotations

import logging
import time
import uuid

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import auth, fraud, guardian, payment, report
from app.container import AppContainer
from app.core.config import Settings
from app.core.rate_limit import InMemoryRateLimitMiddleware

logger = logging.getLogger("kavasam")


def create_app(settings: Settings | None = None) -> FastAPI:
    active_settings = settings or Settings.from_env()
    app = FastAPI(
        title="Kavasam Fraud Protection API",
        version="0.1.0",
        description="Consent-first fraud analysis and response assistance.",
    )
    app.state.container = AppContainer.build(active_settings)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(active_settings.cors_origins),
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    )
    app.add_middleware(
        InMemoryRateLimitMiddleware,
        requests_per_minute=active_settings.rate_limit_per_minute,
    )

    @app.middleware("http")
    async def request_logging(request: Request, call_next):
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        started = time.perf_counter()
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        logger.info(
            "request_completed method=%s path=%s status=%s duration_ms=%.2f request_id=%s",
            request.method,
            request.url.path,
            response.status_code,
            (time.perf_counter() - started) * 1000,
            request_id,
        )
        return response

    @app.get("/health", tags=["operations"])
    def health() -> dict[str, str]:
        return {
            "status": "ok",
            "environment": active_settings.environment,
            "ai": "gemini" if active_settings.gemini_api_key else "rules-only",
        }

    app.include_router(auth.router)
    app.include_router(fraud.router)
    app.include_router(payment.router)
    app.include_router(guardian.router)
    app.include_router(report.router)
    return app


app = create_app()
