from fastapi import FastAPI, Response

from .analyzer import GeminiAnalyzer
from .reputation import CommunityReputationStore
from .schemas import (
    CommunityReputationResponse,
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
reputation = CommunityReputationStore()


@app.middleware("http")
async def privacy_headers(request, call_next):
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    return HealthResponse(geminiConfigured=analyzer.configured)


@app.post("/v1/safety/analyze", response_model=SafetyAnalysisResponse)
async def analyze(event: SafetyAnalysisRequest, response: Response) -> SafetyAnalysisResponse:
    result = await analyzer.analyze(event)
    response.headers["X-Kavasam-Analysis-Source"] = result.source
    return result


@app.post("/v1/reputation/lookup", response_model=CommunityReputationResponse)
async def lookup_reputation(event: ReputationLookupRequest) -> CommunityReputationResponse:
    return reputation.lookup(event.phoneNumber)


@app.post("/v1/reputation/report", response_model=CommunityReputationResponse)
async def report_reputation(event: ReputationReportRequest) -> CommunityReputationResponse:
    return reputation.report(event)
