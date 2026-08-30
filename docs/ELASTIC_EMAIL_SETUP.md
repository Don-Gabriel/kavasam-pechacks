# Elastic + Jina scam-email analysis

Kavasam enriches **email PDF analysis** with Elasticsearch: known scam / phishing
email patterns are stored as a `semantic_text` field powered by **Jina embeddings**
(`.jina-embeddings-v5-text-small`) through Elastic's Inference Service — the same
stack as the Elastic + Jina workshop. When an email PDF is analysed, its text is
matched semantically against these patterns and the closest one is fed into the AI
verdict ("resembles a known invoice-fraud email").

Fully optional and fail-open: without Elastic configured, email analysis runs
exactly as before.

## Setup

1. Create an **Elastic Cloud (Serverless)** project (free trial) at cloud.elastic.co
   — Serverless includes the Elastic Inference Service with the Jina endpoints.
2. Copy the project's **Elasticsearch endpoint URL**.
3. Create an **API key** (Management → API keys, or the project's Connection details).
4. Add both to `cloud/.env`:

```
ELASTICSEARCH_URL=https://<your-project>.es.<region>.elastic.cloud:443
ELASTIC_API_KEY=<your-api-key>
# Optional overrides:
ELASTIC_SCAM_INDEX=kavasam_scam_emails
ELASTIC_INFERENCE_ID=.jina-embeddings-v5-text-small
```

5. Restart the gateway: `docker compose up -d gateway`.

On the first email analysis the gateway creates the `kavasam_scam_emails` index,
seeds it with known scam-email patterns (invoice fraud, credential phishing, KYC,
tax refund, delivery, lottery, job, tech support), and generates their Jina
embeddings automatically via the `semantic_text` field. `GET /health` then reports
`elasticStatus: ready`.

## Requirements

- The deployment must expose the `.jina-embeddings-v5-text-small` inference endpoint
  (Elastic Inference Service). Override `ELASTIC_INFERENCE_ID` if you use a different
  model (e.g. ELSER `.elser-2-elasticsearch`).
