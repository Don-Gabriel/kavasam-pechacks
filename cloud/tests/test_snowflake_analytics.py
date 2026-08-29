from uuid import uuid4

from app.snowflake_analytics import AnalyticsEvent, SnowflakeAnalytics


class FakeCursor:
    def __init__(self) -> None:
        self.calls: list[tuple[str, tuple[object, ...] | None]] = []

    def __enter__(self):
        return self

    def __exit__(self, *_args) -> None:
        return None

    def execute(self, sql: str, parameters=None) -> None:
        self.calls.append((sql, parameters))


class FakeConnection:
    def __init__(self) -> None:
        self.cursor_value = FakeCursor()

    def __enter__(self):
        return self

    def __exit__(self, *_args) -> None:
        return None

    def cursor(self) -> FakeCursor:
        return self.cursor_value


def _configured(monkeypatch) -> SnowflakeAnalytics:
    values = {
        "SNOWFLAKE_ACCOUNT": "org-account",
        "SNOWFLAKE_USER": "KAVASAM_SERVICE",
        "SNOWFLAKE_WAREHOUSE": "KAVASAM_WH",
        "SNOWFLAKE_DATABASE": "KAVASAM_DB",
        "SNOWFLAKE_SCHEMA": "PUBLIC",
        "SNOWFLAKE_ROLE": "KAVASAM_ROLE",
        "SNOWFLAKE_PRIVATE_KEY_B64": "not-decoded-by-this-test",
    }
    for name, value in values.items():
        monkeypatch.setenv(name, value)
    return SnowflakeAnalytics()


def test_snowflake_writer_contains_metadata_only(monkeypatch) -> None:
    sink = _configured(monkeypatch)
    connections: list[FakeConnection] = []

    def connect() -> FakeConnection:
        connection = FakeConnection()
        connections.append(connection)
        return connection

    monkeypatch.setattr(sink, "_connect", connect)
    event_id = uuid4()
    sink.record(
        AnalyticsEvent(
            event_id=event_id,
            analysis_type="message",
            risk=93,
            level="critical",
            source="gemini",
            vector_database="none",
            indicator_count=4,
        )
    )
    assert sink.status == "ready"
    insert = connections[-1].cursor_value.calls[-1]
    assert insert[1] == (
        str(event_id),
        "message",
        93,
        "critical",
        "gemini",
        "none",
        4,
        str(event_id),
    )
    lowered = insert[0].lower()
    for forbidden in ("phone", "message_text", "url", "audio", "transcript", "guardian"):
        assert forbidden not in lowered


def test_snowflake_failure_never_breaks_analysis(monkeypatch) -> None:
    sink = _configured(monkeypatch)

    def unavailable():
        raise OSError("warehouse unavailable")

    monkeypatch.setattr(sink, "_connect", unavailable)
    sink.record(
        AnalyticsEvent(
            event_id=uuid4(),
            analysis_type="call",
            risk=50,
            level="medium",
            source="rules-fallback",
        )
    )
    assert sink.status == "unavailable"
