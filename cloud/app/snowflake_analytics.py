from __future__ import annotations

import base64
import os
import re
import threading
from dataclasses import dataclass
from uuid import UUID


IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]{0,254}$")


@dataclass(frozen=True)
class AnalyticsEvent:
    event_id: UUID
    analysis_type: str
    risk: int
    level: str
    source: str
    vector_database: str = "none"
    indicator_count: int = 0


class SnowflakeAnalytics:
    """Fail-open, metadata-only Snowflake analytics sink.

    Raw messages, files, URLs, phone numbers, contact names, audio, transcripts,
    reasons, and guardian identifiers are deliberately excluded.
    """

    def __init__(self) -> None:
        self.account = os.getenv("SNOWFLAKE_ACCOUNT", "").strip()
        self.user = os.getenv("SNOWFLAKE_USER", "").strip()
        self.warehouse = os.getenv("SNOWFLAKE_WAREHOUSE", "").strip()
        self.database = os.getenv("SNOWFLAKE_DATABASE", "").strip()
        self.schema = os.getenv("SNOWFLAKE_SCHEMA", "").strip()
        self.role = os.getenv("SNOWFLAKE_ROLE", "").strip()
        self.private_key_b64 = os.getenv("SNOWFLAKE_PRIVATE_KEY_B64", "").strip()
        self.private_key_passphrase = os.getenv(
            "SNOWFLAKE_PRIVATE_KEY_PASSPHRASE", ""
        )
        self._status = "not-checked" if self.configured else "not-configured"
        self._ready = False
        self._lock = threading.RLock()

    @property
    def configured(self) -> bool:
        values = (
            self.account,
            self.user,
            self.warehouse,
            self.database,
            self.schema,
            self.role,
            self.private_key_b64,
        )
        return all(values) and all(
            IDENTIFIER.fullmatch(value)
            for value in (self.warehouse, self.database, self.schema, self.role)
        )

    @property
    def status(self) -> str:
        return self._status

    def check(self) -> bool:
        if not self.configured:
            return False
        try:
            self._ensure_table()
            return True
        except Exception:
            self._status = "unavailable"
            self._ready = False
            return False

    def record(self, event: AnalyticsEvent) -> None:
        if not self.configured:
            return
        try:
            self._ensure_table()
            with self._connect() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        """
                        INSERT INTO KAVASAM_ANALYSIS_EVENTS(
                            EVENT_ID, ANALYSIS_TYPE, RISK, LEVEL, SOURCE,
                            VECTOR_DATABASE, INDICATOR_COUNT
                        ) SELECT %s, %s, %s, %s, %s, %s, %s
                        WHERE NOT EXISTS (
                            SELECT 1 FROM KAVASAM_ANALYSIS_EVENTS WHERE EVENT_ID = %s
                        )
                        """,
                        (
                            str(event.event_id),
                            event.analysis_type[:32],
                            max(0, min(100, event.risk)),
                            event.level[:16],
                            event.source[:32],
                            event.vector_database[:32],
                            max(0, min(100, event.indicator_count)),
                            str(event.event_id),
                        ),
                    )
            self._status = "ready"
        except Exception:
            self._status = "unavailable"
            self._ready = False

    def _ensure_table(self) -> None:
        if self._ready:
            return
        with self._lock:
            if self._ready:
                return
            with self._connect() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        """
                        CREATE TABLE IF NOT EXISTS KAVASAM_ANALYSIS_EVENTS (
                            EVENT_ID VARCHAR(36) NOT NULL,
                            ANALYSIS_TYPE VARCHAR(32) NOT NULL,
                            RISK NUMBER(3, 0) NOT NULL,
                            LEVEL VARCHAR(16) NOT NULL,
                            SOURCE VARCHAR(32) NOT NULL,
                            VECTOR_DATABASE VARCHAR(32) NOT NULL,
                            INDICATOR_COUNT NUMBER(3, 0) NOT NULL,
                            CREATED_AT TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
                            CONSTRAINT KAVASAM_ANALYSIS_EVENTS_PK PRIMARY KEY (EVENT_ID)
                        )
                        """
                    )
            self._ready = True
            self._status = "ready"

    def _connect(self):
        import snowflake.connector
        from cryptography.hazmat.primitives import serialization

        pem = base64.b64decode(self.private_key_b64, validate=True)
        password = self.private_key_passphrase.encode() or None
        key = serialization.load_pem_private_key(pem, password=password)
        private_key = key.private_bytes(
            encoding=serialization.Encoding.DER,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
        return snowflake.connector.connect(
            account=self.account,
            user=self.user,
            private_key=private_key,
            warehouse=self.warehouse,
            database=self.database,
            schema=self.schema,
            role=self.role,
            login_timeout=10,
            network_timeout=15,
            client_session_keep_alive=False,
        )
