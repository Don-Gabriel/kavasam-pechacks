import hashlib
import hmac
import os
import sqlite3
import threading
from collections import Counter
from pathlib import Path

from .schemas import CommunityReputationResponse, ReputationReportRequest


CATEGORY_LABELS = {
    "telemarketing": "Telemarketing",
    "financial_fraud": "Financial fraud",
    "impersonation": "Impersonation scam",
    "robocall": "Robocall",
    "harassment": "Harassment",
    "delivery_scam": "Delivery scam",
    "other": "Suspected spam",
}

CATEGORY_WEIGHTS = {
    "telemarketing": 8,
    "financial_fraud": 28,
    "impersonation": 25,
    "robocall": 12,
    "harassment": 20,
    "delivery_scam": 22,
    "other": 10,
}


class CommunityReputationStore:
    """Stores only keyed number/reporter digests, never raw identifiers."""

    def __init__(self, database_path: str | None = None, secret: str | None = None) -> None:
        configured_path = database_path or os.getenv("KAVASAM_DB_PATH", "data/kavasam.db")
        self.database_path = configured_path
        self.secret = (secret or os.getenv("NUMBER_HMAC_SECRET") or "kavasam-development-secret-change-before-deploy").encode()
        self._lock = threading.Lock()
        if configured_path != ":memory:":
            Path(configured_path).parent.mkdir(parents=True, exist_ok=True)
        self._connection = sqlite3.connect(configured_path, check_same_thread=False)
        self._connection.execute("PRAGMA journal_mode=WAL")
        self._connection.execute("PRAGMA foreign_keys=ON")
        self._connection.execute(
            """
            CREATE TABLE IF NOT EXISTS community_reports (
                number_token TEXT NOT NULL,
                reporter_token TEXT NOT NULL,
                category TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (number_token, reporter_token)
            )
            """
        )
        self._connection.execute(
            "CREATE INDEX IF NOT EXISTS reports_number_idx ON community_reports(number_token)"
        )
        self._connection.commit()

    def _token(self, namespace: str, value: str) -> str:
        return hmac.new(self.secret, f"{namespace}:{value}".encode(), hashlib.sha256).hexdigest()

    def lookup(self, phone_number: str) -> CommunityReputationResponse:
        number_token = self._token("number", phone_number)
        with self._lock:
            rows = self._connection.execute(
                "SELECT category FROM community_reports WHERE number_token = ?",
                (number_token,),
            ).fetchall()
        if not rows:
            return CommunityReputationResponse(
                found=False,
                category="Unknown",
                risk=0,
                riskLabel="No community reports",
                reportCount=0,
                confidence=0.0,
                reasons=[],
                source="none",
            )
        counts = Counter(row[0] for row in rows)
        category, category_count = counts.most_common(1)[0]
        reports = len(rows)
        risk = min(96, 24 + reports * 11 + CATEGORY_WEIGHTS.get(category, 10))
        confidence = min(0.98, round(0.32 + reports * 0.13, 2))
        reasons = [f"{reports} independent community report{'s' if reports != 1 else ''}."]
        if category_count > 1:
            reasons.append(f"{category_count} reports agree on {CATEGORY_LABELS.get(category, category).lower()}.")
        return CommunityReputationResponse(
            found=True,
            category=CATEGORY_LABELS.get(category, "Suspected spam"),
            risk=risk,
            riskLabel="Likely scam" if risk >= 70 else "Suspected spam",
            reportCount=reports,
            confidence=confidence,
            reasons=reasons,
            source="community",
        )

    def report(self, event: ReputationReportRequest) -> CommunityReputationResponse:
        number_token = self._token("number", event.phoneNumber)
        reporter_token = self._token("reporter", str(event.reporterId))
        with self._lock:
            self._connection.execute(
                """
                INSERT INTO community_reports(number_token, reporter_token, category)
                VALUES (?, ?, ?)
                ON CONFLICT(number_token, reporter_token) DO UPDATE SET
                    category = excluded.category,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (number_token, reporter_token, event.category),
            )
            self._connection.commit()
        return self.lookup(event.phoneNumber)

    def close(self) -> None:
        self._connection.close()
