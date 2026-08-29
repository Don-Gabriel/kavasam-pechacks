# Kavasam

Kavasam is an Android-first, consent-first financial fraud prevention companion for Indian digital payment users. It detects manipulation in suspicious messages, calls, screenshots, QR codes, and payment requests, explains the risk in plain language, and helps users notify trusted guardians or prepare a cybercrime report.

## Repository layout

- `mobile/` — Flutter application with Android-native protection services
- `backend/` — FastAPI service and hybrid fraud-analysis engine
- `docs/` — product, API, AI/data, security, sponsor, and demo specifications

## Current MVP

The working Android MVP includes:

- Development OTP authentication with signed access tokens
- Android Share targets for text and images
- Opt-in on-device notification risk shielding
- Android `CallScreeningService` caller-metadata integration
- Live, visible microphone speech recognition for Protect Call mode
- Camera QR scanning and UPI receiver extraction
- Screenshot/photo OCR with Gemini multimodal analysis when configured
- Explainable rules with optional Gemini enrichment
- Payment/UPI risk checks before payment handoff
- Guardian linking and alert recording
- Optional signed n8n guardian-alert automation
- Cybercrime report draft generation
- Optional ElevenLabs multilingual warning audio with Android TTS fallback
- Paatti Mode accessibility controls

External services are real adapters, not startup requirements. The application remains runnable without cloud credentials, but the jury build should configure Gemini, ElevenLabs, and n8n so their integration is visible in the demo.

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

Android emulators use `http://10.0.2.2:8000` to reach the host machine. For a physical Android device connected over USB, run `adb reverse tcp:8000 tcp:8000` and use `http://127.0.0.1:8000` as the API URL.

## Verify

```powershell
cd backend
python -m pytest

cd ..\mobile
flutter analyze
flutter test
```

## Configuration

Copy `backend/.env.example` to `backend/.env`. Never commit API keys. Gemini and ElevenLabs are called only from the backend. n8n payloads can be protected with an HMAC signing secret.

See [Android build and sponsor status](docs/ANDROID_BUILD_AND_SPONSOR_STATUS.md) for the precise working/credential-required matrix and jury demo sequence.
