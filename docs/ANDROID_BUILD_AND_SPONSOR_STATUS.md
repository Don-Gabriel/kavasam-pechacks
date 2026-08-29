# Kavasam Android Build and Sponsor Status

## Product boundary

Kavasam is Android-first. It uses Android APIs that a normal user-installable application can legitimately request. It does not claim to read private app databases, intercept cellular audio, or block payments inside unrelated banking apps.

## Working feature matrix

| Feature | Current implementation | Demo truth |
| --- | --- | --- |
| Share suspicious text | Android `ACTION_SEND` share target routes evidence directly into analysis | Working |
| Share screenshot | Android share target copies the granted image into app cache, runs on-device OCR, then analyzes it | Working |
| Notification shield | User-approved `NotificationListenerService` performs immediate on-device fraud-signal checks and raises a warning | Working; Android permission required |
| Incoming call shield | User-selected `CallScreeningService` receives caller metadata and network verification status | Working on Android 10+; no call audio |
| Protect Call | Visible microphone + Android speech recognition builds a short live transcript and sends it to the fraud engine | Working; speakerphone/device behavior varies |
| QR PayGuard | Camera decodes a QR, extracts UPI payee, name, amount and note, and checks the receiver before any payment handoff | Working |
| Screenshot intelligence | ML Kit OCR works offline; Gemini inspects the original pixels when configured | OCR works; Gemini needs a key |
| Voice warning | ElevenLabs natural voice is attempted first; Android TTS is the automatic fallback | Fallback works; ElevenLabs needs a key |
| Guardian network | Guardian linking and alert actions are in the Android UI and API | Working locally |
| Response automation | Guardian alerts are sent to a signed n8n webhook when configured | Code complete; webhook needed |
| Cybercrime evidence | Any analyzed event can generate a structured complaint/report draft with the 1930 next step | Working |

## Sponsor/tool ledger

| Sponsor/tool | Product use | Repository evidence | State |
| --- | --- | --- | --- |
| Google Gemini | Schema-constrained text and multimodal screenshot/QR fraud reasoning | `backend/app/services/gemini.py` | Integrated; `GEMINI_API_KEY` required |
| ElevenLabs | Natural multilingual high-urgency voice warning | `backend/app/services/elevenlabs.py`, `/voice/warning` | Integrated with Android TTS fallback; key required |
| n8n | Guardian notification/evidence workflow | `backend/app/services/automation.py` | Integrated; webhook and signing secret required |
| Render | Public FastAPI hosting for the jury device | FastAPI is deployable; deployment config is the next infrastructure step | Not deployed yet |
| MongoDB Atlas | Durable fraud intelligence and event storage | Current repository is still in-memory | Not implemented; do not claim it |
| Trace Commons | Agent trace scoring and hackathon-track evidence | Trace Commons Codex/Claude setup and final consent-gated submission flow | Preserve sessions now; submit only with user consent |

## Credentials needed for the sponsor-enabled jury build

Put these in `backend/.env`, never in Flutter. For this private team demo repository only, the file is intentionally versioned so authorised teammates receive the same configuration:

```dotenv
GEMINI_API_KEY_1=
GEMINI_API_KEY_2=
GEMINI_API_KEY_3=
GEMINI_API_KEY_4=
GEMINI_MODEL=gemini-3.7-flash

ELEVENLABS_API_KEY_1=
ELEVENLABS_API_KEY_2=
ELEVENLABS_API_KEY_3=
ELEVENLABS_API_KEY_4=
ELEVENLABS_VOICE_ID=JBFqnCBsd6RMkjVDRZzb
ELEVENLABS_MODEL=eleven_multilingual_v2

N8N_GUARDIAN_WEBHOOK_URL=
N8N_SIGNING_SECRET=
```

The backend now includes a root-level Render Blueprint. Persistent hosted storage remains a later production step; the hackathon service intentionally uses in-memory demo state.

## Exact physical-device development run

Terminal 1:

```powershell
cd backend
python -m pip install -e ".[dev]"
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

Terminal 2:

```powershell
adb reverse tcp:8000 tcp:8000
cd mobile
flutter pub get
flutter run --dart-define=KAVASAM_API_URL=http://127.0.0.1:8000
```

For an emulator, omit `adb reverse` and replace the URL with `http://10.0.2.2:8000`.

## Jury demo sequence

1. Enable Message Notification Shield and Incoming Call Screening from Automatic Protection.
2. Receive a realistic scam notification. Show Kavasam's immediate on-device warning.
3. Tap the alert. Show automatic Gemini/rules explanation and a spoken warning.
4. Scan a UPI QR. Show the decoded receiver before payment.
5. Run Protect Call on speakerphone with a short digital-arrest script.
6. Tap Alert my guardian, then Prepare cybercrime report.
7. Explain the truth boundary: no stealth audio interception, no hidden WhatsApp database access, and no payment authorization by Kavasam.
