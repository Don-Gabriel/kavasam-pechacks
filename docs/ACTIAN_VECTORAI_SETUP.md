# Actian VectorAI DB setup

Kavasam uses Actian VectorAI DB for nearest-neighbor retrieval of transparent scam-behavior patterns. This is an online enhancement only: the Android dialer, call controls, local caller ID, and local risk engine do not depend on Actian.

## What the integration does

For each safety request that the user explicitly sends to the gateway:

1. The gateway converts the allowlisted safety fields into a 12-dimension behavior vector.
2. It creates the configured Actian collection with Cosine distance and seeds four versioned scam prototypes if needed.
3. It queries `POST /collections/{collection}/points/search` for the nearest pattern.
4. A sufficiently similar result is included as `vectorDatabase: "actian-vectorai"` and `vectorMatch` in the advisory response.
5. If Actian is absent or unavailable, the response says `local-fallback` or `actian-unavailable`; calling and local warnings continue.

No phone number, contact name, audio, transcript, address book, or call-log row is placed in an Actian vector or payload.

## Local Docker setup

Actian's Docker installation requires explicit EULA acceptance. Review the [Actian Docker instructions](https://docs.vectoraidb.actian.com/home/installation/instructions) before changing this value.

Edit `cloud/.env`:

```dotenv
ACTIAN_VECTORAI_ACCEPT_EULA=YES
ACTIAN_VECTORAI_COLLECTION=kavasam_scam_patterns
ACTIAN_VECTORAI_TIMEOUT_SECONDS=2.5
```

Then start both services from the repository root:

```powershell
docker compose up -d vectorai gateway
Invoke-RestMethod http://127.0.0.1:8080/health
```

The Compose network automatically supplies `ACTIAN_VECTORAI_URL=http://vectorai:6573` to the gateway. Actian's REST endpoint is exposed at port 6573, gRPC at 6574, and its local interface at [http://127.0.0.1:6575](http://127.0.0.1:6575). Persistent database files are written to ignored `actian_data/`.

Stop the services without deleting their data:

```powershell
docker compose down
```

## Gateway without Compose

When the FastAPI gateway runs directly on Windows, set:

```dotenv
ACTIAN_VECTORAI_URL=http://127.0.0.1:6573
ACTIAN_VECTORAI_ACCESS_TOKEN=
ACTIAN_VECTORAI_COLLECTION=kavasam_scam_patterns
ACTIAN_VECTORAI_TIMEOUT_SECONDS=2.5
```

Local development does not require authentication. For a production Actian instance, use an HTTPS URL and put its access token in `ACTIAN_VECTORAI_ACCESS_TOKEN`; the gateway sends it as a Bearer token. Never compile it into the APK.

## Verification

Before the first safety request, health reports `not-checked`. After a successful vector query it reports `ready`:

```json
{
  "status": "ok",
  "actianConfigured": true,
  "actianStatus": "ready",
  "actianCollection": "kavasam_scam_patterns"
}
```

The mobile safety card shows `vectors: actian-vectorai` and the nearest pattern label. The gateway also returns `X-Kavasam-Vector-Source: actian-vectorai`.

Run the integration tests without a live database:

```powershell
cd cloud
.\.venv\Scripts\python.exe -m pytest -q
```

The tests verify collection creation, pattern upsert, vector search, Bearer authentication, response attribution, and fail-open behavior.

## Production values needed

- `ACTIAN_VECTORAI_URL`: reachable Actian REST origin, normally HTTPS in production.
- `ACTIAN_VECTORAI_ACCESS_TOKEN`: production access token; blank only for trusted local development.
- `ACTIAN_VECTORAI_COLLECTION`: keep `kavasam_scam_patterns` unless a separate environment needs its own collection.
- `ACTIAN_VECTORAI_TIMEOUT_SECONDS`: request timeout; `2.5` is the default.
- `ACTIAN_VECTORAI_ACCEPT_EULA`: used only by the official Docker image; set to `YES` only after reviewing the Actian terms.

The implementation uses the documented REST API directly through the gateway's existing HTTP client. It does not require the optional Python SDK.
