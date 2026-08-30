import json
from uuid import uuid4

from fastapi.testclient import TestClient

from app.main import app


def _create_room(client: TestClient) -> str:
    response = client.post("/v1/link/rooms", json={"deviceId": str(uuid4())})
    assert response.status_code == 200
    body = response.json()
    assert body["sampleRate"] == 16000
    assert len(body["code"]) == 6
    return body["code"]


def test_room_creation_returns_six_digit_code() -> None:
    client = TestClient(app)
    code = _create_room(client)
    assert code.isdigit()


def test_unknown_room_is_rejected() -> None:
    client = TestClient(app)
    try:
        with client.websocket_connect("/v1/link/ws/000000?role=host") as socket:
            socket.receive_text()
        raise AssertionError("expected the socket to close")
    except Exception:
        pass


def test_audio_relays_between_host_and_guest() -> None:
    client = TestClient(app)
    code = _create_room(client)
    with client.websocket_connect(f"/v1/link/ws/{code}?role=host") as host:
        joined = json.loads(host.receive_text())
        assert joined == {"type": "joined", "role": "host", "peerPresent": False}
        with client.websocket_connect(f"/v1/link/ws/{code}?role=guest") as guest:
            assert json.loads(guest.receive_text())["type"] == "joined"
            assert json.loads(host.receive_text()) == {"type": "peer-joined", "role": "guest"}
            host.send_bytes(b"\x01\x02" * 160)
            assert guest.receive_bytes() == b"\x01\x02" * 160
            guest.send_bytes(b"\x03\x04" * 160)
            assert host.receive_bytes() == b"\x03\x04" * 160


def test_duplicate_role_is_rejected() -> None:
    client = TestClient(app)
    code = _create_room(client)
    with client.websocket_connect(f"/v1/link/ws/{code}?role=host") as host:
        host.receive_text()
        try:
            with client.websocket_connect(f"/v1/link/ws/{code}?role=host") as second:
                second.receive_text()
            raise AssertionError("expected the duplicate role to be rejected")
        except Exception:
            pass
