# Kavasam

Kavasam is a consent-first financial fraud prevention companion for Indian digital payment users. It detects manipulation in suspicious messages, calls, and payment requests, explains the risk in plain language, and helps users notify trusted guardians or prepare a cybercrime report.

## Repository layout

- `mobile/` — Flutter app for Android, iOS, and web
- `backend/` — FastAPI service and hybrid fraud-analysis engine
- `docs/` — product, API, AI/data, security, sponsor, and demo specifications

## Current MVP

The first vertical slice includes:

- Development OTP authentication with signed access tokens
- Message analysis using explainable rules with optional Gemini enrichment
- Payment/UPI risk checks
- User-authorized call transcript analysis
- Guardian linking and alert recording
- Cybercrime report draft generation
- Flutter demo flows for message, payment, and call protection
- Paatti Mode accessibility controls

External services are adapters, not startup requirements. The application remains runnable for a hackathon demo without cloud credentials.

## Run the backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[dev]"
Copy-Item .env.example .env
uvicorn app.main:app --reload
```

Open `http://localhost:8000/docs` for the interactive API documentation. In local development the generated OTP is returned by `/auth/login`; production mode never exposes it.

## Run the mobile app

```powershell
cd mobile
flutter pub get
flutter run --dart-define=KAVASAM_API_URL=http://10.0.2.2:8000
```

For Flutter web, use `http://localhost:8000`. Android emulators use `http://10.0.2.2:8000` to reach the host machine.

## Verify

```powershell
cd backend
python -m pytest

cd ..\mobile
flutter analyze
flutter test
```

## Configuration

Copy `backend/.env.example` to `backend/.env`. Never commit API keys. Gemini is called only from the backend, using the `x-goog-api-key` header and schema-constrained JSON output.

