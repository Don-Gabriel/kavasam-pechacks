# Kavasam Consent Gateway

This FastAPI service is the only network boundary used by Kavasam. The AI-safety route rejects every field outside its redacted schema, including phone numbers, contact names, audio, transcripts, and call history. Community reputation is a separate consented route: it accepts a number over HTTPS, converts it immediately to a keyed HMAC token, and stores only that token plus categorized reports.

When `GEMINI_API_KEY` is set, `/v1/safety/analyze` uses Gemini structured JSON output. Without a key—or when the provider is unavailable—it returns an explainable `rules-fallback` result so the app never loses safety guidance.

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m uvicorn app.main:app --port 8080
```

Endpoints:

- `GET /health`
- `POST /v1/safety/analyze`
- `POST /v1/reputation/lookup`
- `POST /v1/reputation/report`
- `GET /docs` for the generated OpenAPI explorer

API keys and `NUMBER_HMAC_SECRET` belong in host environment secrets. Do not add them to `.env.example`, Dart defines, source control, or the Android package.
