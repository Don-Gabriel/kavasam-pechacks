"""Elasticsearch scam-email pattern retrieval.

Holds a small index of known scam / phishing email patterns as a
`semantic_text` field powered by Jina embeddings through Elastic's Inference
Service (matching the Elastic + Jina workshop). When an email PDF is analysed,
its text is matched semantically against these patterns so the AI verdict is
grounded in "this resembles a known invoice-fraud / credential-phishing email".

Fully optional and fail-open: without Elastic configured, email analysis runs
exactly as before.
"""

from __future__ import annotations

import os

try:
    from elasticsearch import Elasticsearch
except ImportError:  # pragma: no cover - client always present in the container
    Elasticsearch = None  # type: ignore

try:
    from elasticsearch import ApiError, TransportError
except ImportError:  # pragma: no cover - exception names vary by client version
    ApiError = TransportError = Exception  # type: ignore

DEFAULT_INDEX = "kavasam_scam_emails"
DEFAULT_INFERENCE_ID = ".jina-embeddings-v5-text-small"

# Seed patterns so semantic search returns useful matches during the demo.
SEED_PATTERNS: tuple[tuple[str, str, str], ...] = (
    (
        "Invoice / payment redirection fraud",
        "invoice_fraud",
        "Please find attached the updated invoice. Note our bank account has "
        "changed, kindly process the outstanding payment to the new account "
        "details below before end of day to avoid late fees.",
    ),
    (
        "Credential phishing (account verification)",
        "credential_phishing",
        "We detected unusual activity on your account. Your account will be "
        "suspended unless you verify your identity. Click the secure link and "
        "confirm your username, password and one time passcode immediately.",
    ),
    (
        "Bank / KYC update phishing",
        "bank_kyc",
        "Your bank account KYC is incomplete and will be blocked within 24 "
        "hours. Update your PAN, Aadhaar and net-banking details using the link "
        "to keep your account active.",
    ),
    (
        "Tax refund lure",
        "tax_refund",
        "You are eligible for an income tax refund. To receive the refund amount "
        "please confirm your bank account and card details through the refund "
        "portal within 12 hours.",
    ),
    (
        "Parcel / delivery fee scam",
        "delivery_scam",
        "Your parcel is on hold at the courier facility due to an unpaid customs "
        "fee. Pay the small delivery charge now using the link to release your "
        "package, otherwise it will be returned.",
    ),
    (
        "Lottery / prize scam",
        "prize_scam",
        "Congratulations! Your email has won the international lottery draw. To "
        "claim your prize money, send your full name, address and a processing "
        "fee to the claims agent listed below.",
    ),
    (
        "Job offer / advance fee scam",
        "job_scam",
        "You have been shortlisted for a work from home job with a high daily "
        "salary. To confirm your onboarding, pay a small refundable registration "
        "and training fee and share your bank details.",
    ),
    (
        "Tech support / remote access scam",
        "tech_support",
        "This is a security alert from technical support. Your computer is "
        "infected. Call the support number and install the remote access tool so "
        "our engineer can fix your device.",
    ),
)


class ElasticScamStore:
    def __init__(
        self,
        url: str | None = None,
        api_key: str | None = None,
        index: str | None = None,
        inference_id: str | None = None,
    ) -> None:
        self._url = url if url is not None else os.getenv("ELASTICSEARCH_URL", "").strip()
        self._api_key = (
            api_key if api_key is not None else os.getenv("ELASTIC_API_KEY", "").strip()
        )
        self._index = index or os.getenv("ELASTIC_SCAM_INDEX", DEFAULT_INDEX)
        self._inference_id = (
            inference_id or os.getenv("ELASTIC_INFERENCE_ID", DEFAULT_INFERENCE_ID)
        )
        self._client = None
        self._status = "not-configured"
        if self._url and self._api_key and Elasticsearch is not None:
            self._status = "not-checked"
            try:
                self._client = Elasticsearch(
                    self._url, api_key=self._api_key, request_timeout=10
                )
            except Exception:
                self._client = None
                self._status = "unavailable"

    @property
    def configured(self) -> bool:
        return self._client is not None

    @property
    def status(self) -> str:
        return self._status

    @property
    def index(self) -> str:
        return self._index

    def ensure_ready(self) -> bool:
        """Creates the index and seeds patterns if needed. Safe to call repeatedly."""
        if self._client is None:
            return False
        try:
            if not self._client.indices.exists(index=self._index):
                self._client.indices.create(
                    index=self._index,
                    mappings={
                        "properties": {
                            "label": {"type": "keyword"},
                            "category": {"type": "keyword"},
                            "content": {"type": "text", "copy_to": "content_semantic"},
                            "content_semantic": {
                                "type": "semantic_text",
                                "inference_id": self._inference_id,
                            },
                        }
                    },
                )
                for label, category, content in SEED_PATTERNS:
                    self._client.index(
                        index=self._index,
                        document={"label": label, "category": category, "content": content},
                    )
                self._client.indices.refresh(index=self._index)
            self._status = "ready"
            return True
        except (ApiError, TransportError, Exception):
            self._status = "unavailable"
            return False

    def match(self, text: str) -> dict[str, object] | None:
        """Returns the closest known scam-email pattern, or None."""
        if self._client is None:
            return None
        query_text = text.strip()[:2000]
        if not query_text:
            return None
        try:
            if self._status != "ready" and not self.ensure_ready():
                return None
            response = self._client.search(
                index=self._index,
                size=1,
                query={"semantic": {"field": "content_semantic", "query": query_text}},
                source=["label", "category"],
            )
            hits = response.get("hits", {}).get("hits", [])
            if not hits:
                return None
            top = hits[0]
            return {
                "label": top["_source"].get("label", "Unknown pattern"),
                "category": top["_source"].get("category", "unknown"),
                "score": float(top.get("_score", 0.0)),
            }
        except (ApiError, TransportError, Exception):
            self._status = "unavailable"
            return None
