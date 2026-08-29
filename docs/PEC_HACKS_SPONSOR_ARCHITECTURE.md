# Kavasam — PEC Hacks Sponsor Architecture

## Product thesis

Kavasam is a consent-first scam-safety dialer. Normal calling, contacts, caller ID, local reputation, blocking, and per-call safety tracking work offline. Cloud intelligence is a separate opt-in capability and must never be required to place, receive, answer, or reject a call.

The current Android build does **not** capture cellular call audio. Android reserves uplink/downlink call capture for privileged system applications, so the production feature tracks caller metadata and red flags explicitly selected by the user. This makes the demo technically honest, privacy-preserving, and reproducible across normal Android devices.

## Current offline flow

1. Tracking is off when every call begins.
2. The user taps **Track this call for safety**.
3. Kavasam starts a local session using the caller reputation score as its baseline.
4. The user can flag OTP/PIN requests, urgent payments, remote access, impersonation, secrecy/urgency, or threats.
5. A behavior vector is compared with a local scam prototype and produces an explainable 0–100 suspicion score.
6. The user can stop tracking at any time. A compact summary is stored locally; audio and transcripts are never stored.

## Authentic sponsor integrations

| Sponsor | Real product role | Data boundary | Prize demo |
|---|---|---|---|
| Gemini API | **Implemented.** Reason over a consented structured safety event and produce a short explanation plus safe next steps | Signal keys, local scores, coarse locale; no contact name, phone number, address book, audio, or raw call log | Compare local score with Gemini reasoning and show a grounded explanation |
| ElevenLabs | Speak an urgent multilingual warning selected from the Gemini response | Warning text and language only | Demonstrate a Tamil/English spoken warning after an OTP or remote-access signal |
| MongoDB Atlas Vector Search | Planned production scale-out for the implemented community reputation store | Server-HMAC number token or pattern vector; never store a raw phone number | Replace the SQLite repository with nearest scam-pattern retrieval when Atlas credentials are supplied |
| Snowflake | Aggregate privacy-safe program metrics for judges and fraud researchers | Daily counts and coarse categories only; no per-user identifiers | Dashboard of scam tactics, intervention rate, and false-positive feedback |
| n8n | Run a user-confirmed escalation workflow | User-approved incident summary only | After confirmation, notify a guardian or create a support ticket; never auto-send |
| Render | Host the minimal consent gateway and demo dashboard | Stateless API plus secret management | Deploy the Gemini/ElevenLabs gateway with health and audit endpoints |
| Vultr | Host an optional open-model classifier or regional redundancy | Same minimized structured payload | Benchmark sponsor-hosted classifier against the local and Gemini scores |
| Trace Commons | Provide reproducible evidence of the build process | Agent trace only after team consent and secret scanning | Submit the development trace and signed score attestation |
| Solana (optional) | Timestamp a user-approved incident evidence digest | One-way digest only; never PII or report contents | Verify that an exported evidence bundle existed at a given time |

Superficial integrations should not be claimed. A sponsor track is submission-ready only when its path is visible in the demo and covered by a test or audit record.

## Consent-gated cloud contract

The optional gateway should accept structured events, not call audio:

```json
{
  "schemaVersion": 1,
  "sessionId": "random-per-call-id",
  "localRisk": 68,
  "vectorSimilarity": 0.81,
  "signals": ["otp_pin", "secrecy_urgency"],
  "callerContext": {
    "savedContact": false,
    "locallyReported": true,
    "carrierVerificationFailed": false
  },
  "locale": "ta-IN"
}
```

The response must remain advisory:

```json
{
  "risk": 84,
  "level": "high",
  "reasons": [
    "The caller requested a secret OTP",
    "The request combines urgency with credential theft"
  ],
  "recommendedActions": [
    "Do not share the OTP",
    "End the call and contact the institution using its official number"
  ],
  "warningText": "Never share an OTP. End this call and verify independently."
}
```

## Security rules

- Cloud analysis requires a separate prominent consent toggle in addition to per-call local tracking.
- API keys stay on the server and are never compiled into the APK.
- Raw phone numbers, contact names, address books, call audio, and full call logs are excluded from cloud payloads.
- Do not use Android Accessibility Service as a call-recording workaround.
- Do not automatically message guardians, submit reports, move money, or block a caller based only on an AI response.
- Every warning explains which observed signals caused it.
- Users can delete local sessions and revoke cloud consent.

## Delivery order

1. **Complete:** offline consent button, structured signals, vector score, local summaries.
2. **Complete:** Gemini consent gateway, Render blueprint, strict schema validation, and redaction tests. Live Gemini output requires a server-side key.
3. **Complete:** persistent community reputation API with unique reporter deduplication and server-HMAC number identifiers.
4. ElevenLabs multilingual warning playback with Android offline TTS fallback.
5. MongoDB Atlas community-pattern scale-out using the existing server-HMAC identifiers.
6. User-confirmed n8n guardian/escalation workflow.
7. Snowflake aggregate dashboard and Vultr classifier benchmark.
8. Trace Commons submission after explicit team consent and secret scanning.

## Submission angle

Primary domain: FinTech and Open Innovation. The story is not “AI records every call.” It is: **Kavasam gives the user control over when safety analysis starts, detects structured scam tactics without covert recording, explains every warning, and keeps normal calling functional offline.**
