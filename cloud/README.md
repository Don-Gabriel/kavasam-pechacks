# Kavasam Consent Gateway

This FastAPI service is the only network boundary used by Kavasam. The AI-safety route rejects every field outside its redacted schema, including phone numbers, contact names, audio, transcripts, and call history. Community reputation and guardian approval are separate, explicit flows. Guardian numbers are used transiently for SMS delivery and stored only as keyed HMAC tokens.

When `GEMINI_API_KEY` is set, `/v1/safety/analyze` uses Gemini structured JSON output. Without a key—or when the provider is unavailable—it returns an explainable `rules-fallback` result so the app never loses safety guidance.

When `ACTIAN_VECTORAI_URL` is set, every accepted safety request also performs nearest-neighbor retrieval against the configured Actian scam-pattern collection. The response and health endpoint state whether Actian was used, unavailable, or not configured. See [the Actian setup guide](../docs/ACTIAN_VECTORAI_SETUP.md).

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
# A local cloud/.env is already created and ignored by Git. Fill its blanks.
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m uvicorn app.main:app --port 8080
```

`app.main` automatically loads `cloud/.env` for local development. Hosting environment variables keep priority, and Docker/Render deployments do not copy the local secrets file.

Endpoints:

- `GET /health`
- `POST /v1/safety/analyze`
- `POST /v1/reputation/lookup`
- `POST /v1/reputation/report`
- `POST /v1/guardian/enrollments`
- `GET /v1/guardian/enrollments/{id}?deviceId=...`
- `POST /v1/guardian/approvals`
- `GET /v1/guardian/approvals/{id}?deviceId=...`
- `POST /v1/guardian/reply` (authenticated n8n callback)
- `GET /docs` for the generated OpenAPI explorer

API keys, `ACTIAN_VECTORAI_ACCESS_TOKEN`, `NUMBER_HMAC_SECRET`, `N8N_WEBHOOK_URL`, and `N8N_WEBHOOK_SECRET` belong in host environment secrets. Set `PUBLIC_BASE_URL` to the gateway's public HTTPS origin outside Render. Do not add secrets to Dart defines, source control, or the Android package.
