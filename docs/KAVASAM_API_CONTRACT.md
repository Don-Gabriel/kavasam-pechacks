# KAVASAM API CONTRACT

## Purpose

This document defines the exact communication contract between Flutter
mobile app, FastAPI backend, AI services and Firebase services.

Codex must implement APIs according to this specification.

------------------------------------------------------------------------

# Base URL

Production:

https://api.kavasam.app

Development:

http://localhost:8000

------------------------------------------------------------------------

# Authentication APIs

## POST /auth/login

Purpose: Start OTP authentication.

Request:

{ "phone_number": "+91XXXXXXXXXX" }

Response:

{ "message":"OTP sent", "session_id":"xxxx" }

------------------------------------------------------------------------

## POST /auth/verify

Purpose: Verify OTP.

Request:

{ "session_id":"xxxx", "otp":"123456" }

Response:

{ "access_token":"token", "user_id":"userid" }

------------------------------------------------------------------------

# Fraud Analysis APIs

## POST /fraud/analyze-message

Purpose: Analyse SMS, WhatsApp text or screenshots.

Request:

{ "text":"Your bank account will be blocked", "language":"Tamil" }

Response:

{ "risk_score":92, "risk_level":"CRITICAL",
"fraud_type":"BANK_PHISHING", "confidence":0.94, "reasons":\[ "Urgent
action request", "Fake banking identity"\], "warning":"Do not click this
link", "recommended_action":"Ignore and report" }

------------------------------------------------------------------------

## POST /fraud/analyze-image

Purpose: Analyse screenshots and images.

Input: - screenshot - QR image - payment proof

Output:

Same fraud analysis format.

------------------------------------------------------------------------

# Payment Protection APIs

## POST /payment/check

Request:

{ "upi_id":"abc@upi", "merchant_name":"Store", "amount":500 }

Response:

{ "risk_score":75, "status":"WARNING", "reason":"Unknown payment
receiver" }

------------------------------------------------------------------------

# Call Protection APIs

## POST /call/analyze

Purpose: Analyse user-authorized suspicious call recordings.

Request:

{ "audio_chunk":"base64_audio", "language":"Tamil" }

Response:

{ "risk_score":88, "fraud_type":"DIGITAL_ARREST", "warning":"Police
never demand money through phone calls" }

------------------------------------------------------------------------

# Guardian APIs

## POST /guardian/add

Add trusted family member.

## POST /guardian/alert

Send fraud alert.

Payload:

{ "user_id":"123", "event_id":"456", "message":"Possible fraud detected"
}

------------------------------------------------------------------------

# Report APIs

## POST /report/generate

Creates cybercrime report draft.

Output:

-   Incident summary
-   Evidence list
-   Timeline
-   Recommended complaint details

------------------------------------------------------------------------

# API Security Requirements

All APIs require:

-   Authentication token
-   Request validation
-   Rate limiting
-   Logging
-   Error handling

Never expose Gemini API keys to mobile application.
