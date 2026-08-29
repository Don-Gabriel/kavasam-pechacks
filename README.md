# Kavasam

Kavasam is an Android-first, consent-first fraud protection companion. It checks suspicious messages, calls, screenshots, QR codes, and UPI payment requests, explains the warning signs, and helps a user alert a trusted guardian or prepare an incident report.

## What is in this repository

- `mobile/` — Flutter Android application plus native Android protection services
- `backend/` — FastAPI API, deterministic fraud rules, and sponsor integrations
- `docs/` — product, API, AI/data, security, sponsor, and demo specifications
- `render.yaml` — one-click Render Blueprint for the backend

The current MVP includes Android sharing, notification shielding, caller metadata screening, visible microphone-based call protection, message analysis, QR and screenshot scanning, UPI checks, guardian alerts, report generation, Gemini analysis, ElevenLabs warnings, and Android TTS fallback.

## Prerequisites

Install these before cloning the project:

- Git
- Python 3.11 or newer
- Flutter SDK with Dart 3.12 or newer
- Android Studio, Android SDK, and an Android emulator or physical Android phone
- JDK 17 (Android Studio's bundled JDK is suitable)

Confirm the Android toolchain is ready:

```powershell
flutter doctor
flutter doctor --android-licenses
adb devices
```

Resolve every blocking issue reported by `flutter doctor` before continuing.

## 1. Clone the repository

```powershell
git clone https://github.com/Don-Gabriel/kavasam-pechacks.git
cd kavasam-pechacks
```

This is a private hackathon repository. `backend/.env` is intentionally shared so authorised teammates receive the demo credentials when they clone. Do not make the repository public, paste the file into logs, or distribute it outside the team. Rotate all keys if repository access changes.

## 2. Start the backend locally

PowerShell:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

macOS/Linux:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Verify the backend:

- Health: `http://localhost:8000/health`
- Interactive API docs: `http://localhost:8000/docs`

Keep this terminal running while using the app. The checked-in development configuration exposes a temporary demo OTP to the app. Real SMS authentication must replace this before a public production release.

## 3. Run the Android app

Open a second terminal:

```powershell
cd mobile
flutter pub get
flutter devices
```

For an Android emulator:

```powershell
flutter run --dart-define=KAVASAM_API_URL=http://10.0.2.2:8000
```

For a physical Android phone connected by USB:

```powershell
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=KAVASAM_API_URL=http://127.0.0.1:8000
```

If several devices are connected, add `-d DEVICE_ID` from `flutter devices` to the command.

On first launch, grant the permissions needed for the feature being demonstrated. Open **Protection setup** inside Kavasam to enable notification access and select Kavasam as the call-screening app. Camera, microphone, notification, and Bluetooth permissions are requested only when required.

## 4. Use the hosted Render backend

The repository contains a Render Blueprint configured for this monorepo.

1. Sign in to Render and connect the GitHub account that can access this private repository.
2. Select **New → Blueprint**.
3. Choose `Don-Gabriel/kavasam-pechacks` and the `main` branch.
4. Render detects `render.yaml`; review the `kavasam-api` service and deploy it.
5. Wait for `/health` to pass, then copy the service URL, for example `https://kavasam-api.onrender.com`.
6. Verify `https://YOUR-SERVICE.onrender.com/health` and `/docs`.

Run the mobile app against Render:

```powershell
cd mobile
flutter run --dart-define=KAVASAM_API_URL=https://YOUR-SERVICE.onrender.com
```

Render redeploys the backend when `main` changes. The current repository stores demo state in memory, so users, guardian links, and incidents reset whenever the service restarts or redeploys. This is appropriate for the hackathon demo; persistent storage is a separate production step.

## 5. Build a shareable Android APK

Use the Render URL so the APK works without a teammate's laptop running the backend:

```powershell
cd mobile
flutter build apk --release --dart-define=KAVASAM_API_URL=https://YOUR-SERVICE.onrender.com
```

The APK is generated at:

```text
mobile/build/app/outputs/flutter-apk/app-release.apk
```

Install it on a connected device with:

```powershell
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## API-key fallback

Gemini and ElevenLabs each have four ordered key slots in `backend/.env`. Key 1 is used first. If a provider rejects, rate-limits, or exhausts that key, the backend tries the next configured key and keeps the successful key active. API keys never enter the Flutter application or APK.

## Verification

Backend:

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
python -m ruff check app tests
python -m pytest
```

Mobile:

```powershell
cd mobile
flutter analyze
flutter test
```

## Common problems

- **The app cannot reach the backend:** confirm `/health` works, use `10.0.2.2` for an emulator, or run `adb reverse` for a USB phone.
- **No device is available:** start an Android emulator or enable USB debugging and accept the phone's RSA prompt.
- **Android build tools are missing:** run `flutter doctor`, install the requested SDK component in Android Studio, then accept the Android licences.
- **Render deploy fails:** confirm the service root is `backend`, the build command is `pip install .`, and the start command binds to `$PORT`.
- **A cloud provider is unavailable:** Kavasam continues with deterministic fraud rules and Android TTS; check `/health` to see which integrations loaded.

See [Android build and sponsor status](docs/ANDROID_BUILD_AND_SPONSOR_STATUS.md) for the feature/credential matrix and jury demo sequence.
