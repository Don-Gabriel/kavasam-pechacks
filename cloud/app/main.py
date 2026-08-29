import asyncio
import hmac
import os
from uuid import UUID

from fastapi import FastAPI, Header, HTTPException, Query, Response
from dotenv import load_dotenv

load_dotenv()

from .actian_vector import ActianVectorStore, augment_with_actian
from .analyzer import GeminiAnalyzer
from .guardian import GuardianApprovalStore
from .reputation import CommunityReputationStore
from .schemas import (
    CommunityReputationResponse,
    GuardianApprovalRequest,
    GuardianApprovalResponse,
    GuardianEnrollmentRequest,
    GuardianEnrollmentResponse,
    GuardianReplyRequest,
    GuardianReplyResponse,
    HealthResponse,
    ReputationLookupRequest,
    ReputationReportRequest,
    SafetyAnalysisRequest,
    SafetyAnalysisResponse,
)

app = FastAPI(
    title="Kavasam Consent Gateway",
    version="1.0.0",
    description="Consent gateway for redacted AI safety and tokenized community reputation.",
)
analyzer = GeminiAnalyzer()
actian = ActianVectorStore()
reputation = CommunityReputationStore()
guardian = GuardianApprovalStore()


@app.middleware("http")
async def privacy_headers(request, call_next):
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    return HealthResponse(
        geminiConfigured=analyzer.configured,
        guardianConfigured=guardian.configured,
        actianConfigured=actian.configured,
        actianStatus=actian.status,
        actianCollection=actian.collection,
    )


@app.post("/v1/safety/analyze", response_model=SafetyAnalysisResponse)
async def analyze(event: SafetyAnalysisRequest, response: Response) -> SafetyAnalysisResponse:
    result, vector_match = await asyncio.gather(
        analyzer.analyze(event),
        actian.match(event),
    )
    result = augment_with_actian(result, vector_match, actian)
    response.headers["X-Kavasam-Analysis-Source"] = result.source
    response.headers["X-Kavasam-Vector-Source"] = result.vectorDatabase
    return result


@app.post("/v1/reputation/lookup", response_model=CommunityReputationResponse)
async def lookup_reputation(event: ReputationLookupRequest) -> CommunityReputationResponse:
    return reputation.lookup(event.phoneNumber)


@app.post("/v1/reputation/report", response_model=CommunityReputationResponse)
async def report_reputation(event: ReputationReportRequest) -> CommunityReputationResponse:
    return reputation.report(event)


@app.post("/v1/guardian/enrollments", response_model=GuardianEnrollmentResponse)
def enroll_guardian(event: GuardianEnrollmentRequest) -> GuardianEnrollmentResponse:
    try:
        return guardian.enroll(event)
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail="Guardian invitation delivery failed.") from error


@app.get(
    "/v1/guardian/enrollments/{enrollment_id}",
    response_model=GuardianEnrollmentResponse,
)
def guardian_enrollment_status(
    enrollment_id: UUID,
    device_id: UUID = Query(alias="deviceId"),
) -> GuardianEnrollmentResponse:
    try:
        return guardian.enrollment_status(enrollment_id, device_id)
    except KeyError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error


@app.post("/v1/guardian/approvals", response_model=GuardianApprovalResponse)
def request_guardian_approval(
    event: GuardianApprovalRequest,
) -> GuardianApprovalResponse:
    try:
        return guardian.request_approval(event)
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail="Guardian alert delivery failed.") from error


@app.get(
    "/v1/guardian/approvals/{request_id}",
    response_model=GuardianApprovalResponse,
)
def guardian_approval_status(
    request_id: UUID,
    device_id: UUID = Query(alias="deviceId"),
) -> GuardianApprovalResponse:
    try:
        return guardian.approval_status(request_id, device_id)
    except KeyError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error


@app.post("/v1/guardian/reply", response_model=GuardianReplyResponse)
def guardian_reply(
    event: GuardianReplyRequest,
    webhook_secret: str = Header(default="", alias="X-Kavasam-Webhook-Secret"),
) -> GuardianReplyResponse:
    expected = os.getenv("N8N_WEBHOOK_SECRET", "")
    if not expected or not hmac.compare_digest(webhook_secret, expected):
        raise HTTPException(status_code=401, detail="Invalid webhook authentication.")
    return guardian.receive_reply(event.senderPhone, event.message)
