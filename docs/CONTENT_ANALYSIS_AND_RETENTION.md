# Content analysis, danger retention, and guardian reports

## User-facing analyzers

- **Message:** the user pastes an SMS, chat message, or email text. Rules and optional Gemini structured output score credential theft, payments, urgency, threats, impersonation, secrecy, prizes, remote access, and embedded links.
- **Email PDF:** the app accepts a PDF up to 8 MB. The gateway validates the PDF signature, reads at most 40 pages in memory with pypdf, analyzes extracted text, and does not retain the file or text.
- **Hyperlink:** the gateway accepts only HTTP(S), rejects credentials in URLs and private/local/reserved targets, detects known shorteners, resolves each public redirect destination, caps redirects at five, and reports host changes. Query strings are omitted from the displayed redirect chain.
- **QR:** ML Kit decodes the QR payload locally from a selected image. URL payloads use the hyperlink analyzer; other payloads use the QR text analyzer.
- **Screenshot:** the gateway validates PNG, JPEG, or WebP bytes and sends the explicit upload to Gemini multimodal analysis. The request is not retained. If Gemini is unavailable, Kavasam clearly returns its rules fallback rather than inventing a visual result.

All results are advisory. A score strictly greater than 80 is labeled **Dangerous**.

## Call-safety behavior

The Android Telecom call remains a normal SIM call and works offline. Pressing **Track this call** starts an explicit safety session. Kavasam analyzes caller reputation plus the scam signals the user selects during the conversation. Whenever those signals change, the consent gateway can provide a new Gemini and Actian VectorAI second opinion. Cellular call audio is not captured or uploaded because ordinary Android default dialers do not have a reliable, portable way to capture both sides of a carrier call.

Only AI call assessments above 80 are written to the native high-risk history. Each item has an explicit expiry seven days after creation; expired items are pruned on every read and write. Other tracked-call sessions remain aggregate local counters and do not enter this danger history.

## Guardian relationship

1. The protected user enters an alias and guardian number.
2. n8n sends an SMS invitation containing a random four-digit reference.
3. The guardian replies `JOIN #1234` or enters the same phone and reference in Kavasam's separate Guardian tab.
4. The gateway stores only a keyed HMAC token for the phone number and issues the guardian device a revocable 30-day bearer session.
5. A tracked call above 80 is saved locally and submitted once as a minimized report. n8n sends an SMS alert, and the guardian can refresh the in-app report inbox.
6. Guardian reports are also pruned after seven days.

SMS provider credentials remain in n8n. The APK contains no MSG91, n8n, Gemini, Actian, or Snowflake secret.

## Snowflake

Snowflake is optional and fail-open. With valid key-pair variables, the gateway creates `KAVASAM_ANALYSIS_EVENTS` and asynchronously stores only:

- random analysis event ID;
- analysis type;
- risk and level;
- rules/Gemini source;
- vector database source;
- indicator count;
- server timestamp.

Raw messages, PDFs, screenshots, URLs, numbers, names, call audio, transcripts, reasons, signals, and guardian identifiers are deliberately excluded. If Snowflake is unavailable, analysis continues and `/health` reports `snowflakeStatus: unavailable`.
