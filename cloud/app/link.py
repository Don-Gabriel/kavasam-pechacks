"""Kavasam Link: an in-app phone-to-phone call relayed by the gateway.

Android silences microphone capture for normal apps during cellular calls,
so real-time scam analysis needs a call whose audio the app owns. Two
Kavasam phones join a short-lived room; the gateway relays raw PCM16 mono
16 kHz audio between them and periodically transcribes each side with
Gemini, broadcasting redacted text back to both phones for on-device
risk scoring.

Rooms are in-memory and expire quickly. No audio is stored: relay frames
are forwarded immediately and transcription buffers are discarded as soon
as a chunk is transcribed or the room closes.
"""

import asyncio
import base64
import json
import os
import re
import secrets
import struct
import time

import httpx
from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect

from .schemas import LinkRoomRequest, LinkRoomResponse

SAMPLE_RATE = 16000
BYTES_PER_SECOND = SAMPLE_RATE * 2  # PCM16 mono
ROOM_TTL_SECONDS = 900
TRANSCRIBE_INTERVAL_SECONDS = 8.0
MIN_TRANSCRIBE_SECONDS = 1.5
MAX_BUFFER_SECONDS = 12
SILENCE_RMS_FLOOR = 220
ROLES = ("host", "guest")

router = APIRouter()


class _Room:
    def __init__(self, code: str) -> None:
        self.code = code
        self.created_at = time.monotonic()
        self.peers: dict[str, WebSocket] = {}
        self.buffers: dict[str, bytearray] = {role: bytearray() for role in ROLES}
        self.transcriber: asyncio.Task | None = None

    @property
    def expired(self) -> bool:
        return time.monotonic() - self.created_at > ROOM_TTL_SECONDS


_rooms: dict[str, _Room] = {}


def _prune_rooms() -> None:
    for code in [code for code, room in _rooms.items() if room.expired and not room.peers]:
        _rooms.pop(code, None)


@router.post("/v1/link/rooms", response_model=LinkRoomResponse)
async def create_room(event: LinkRoomRequest) -> LinkRoomResponse:
    _prune_rooms()
    if len(_rooms) >= 50:
        raise HTTPException(status_code=429, detail="Too many active link rooms.")
    code = f"{secrets.randbelow(900000) + 100000}"
    while code in _rooms:
        code = f"{secrets.randbelow(900000) + 100000}"
    _rooms[code] = _Room(code)
    return LinkRoomResponse(
        code=code,
        expiresInSeconds=ROOM_TTL_SECONDS,
        sampleRate=SAMPLE_RATE,
    )


@router.websocket("/v1/link/ws/{code}")
async def link_socket(websocket: WebSocket, code: str, role: str = "") -> None:
    room = _rooms.get(code)
    if room is None or room.expired:
        await websocket.close(code=4404)
        return
    if role not in ROLES or role in room.peers:
        await websocket.close(code=4409)
        return
    await websocket.accept()
    room.peers[role] = websocket
    other_role = "guest" if role == "host" else "host"
    await _send_json(websocket, {"type": "joined", "role": role, "peerPresent": other_role in room.peers})
    await _broadcast(room, {"type": "peer-joined", "role": role}, exclude=role)
    if room.transcriber is None:
        room.transcriber = asyncio.create_task(_transcribe_loop(room))
    try:
        while True:
            message = await websocket.receive()
            if message.get("type") == "websocket.disconnect":
                break
            data = message.get("bytes")
            if data:
                buffer = room.buffers[role]
                buffer.extend(data)
                overflow = len(buffer) - MAX_BUFFER_SECONDS * BYTES_PER_SECOND
                if overflow > 0:
                    del buffer[:overflow]
                peer = room.peers.get(other_role)
                if peer is not None:
                    await peer.send_bytes(data)
                continue
            text = message.get("text")
            if text:
                await _handle_control(room, role, text)
    except WebSocketDisconnect:
        pass
    finally:
        if room.peers.get(role) is websocket:
            room.peers.pop(role, None)
        room.buffers[role].clear()
        await _broadcast(room, {"type": "peer-left", "role": role})
        if not room.peers:
            if room.transcriber is not None:
                room.transcriber.cancel()
            _rooms.pop(room.code, None)


async def _handle_control(room: _Room, role: str, raw: str) -> None:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return
    if payload.get("type") == "bye":
        await _broadcast(room, {"type": "peer-left", "role": role}, exclude=role)


async def _broadcast(room: _Room, payload: dict, exclude: str | None = None) -> None:
    for peer_role, socket in list(room.peers.items()):
        if peer_role == exclude:
            continue
        await _send_json(socket, payload)


async def _send_json(websocket: WebSocket, payload: dict) -> None:
    try:
        await websocket.send_text(json.dumps(payload, separators=(",", ":")))
    except Exception:
        pass


async def _transcribe_loop(room: _Room) -> None:
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        return
    try:
        while True:
            await asyncio.sleep(TRANSCRIBE_INTERVAL_SECONDS)
            for role in ROLES:
                pcm = bytes(room.buffers[role])
                room.buffers[role].clear()
                if len(pcm) < MIN_TRANSCRIBE_SECONDS * BYTES_PER_SECOND:
                    continue
                if _rms(pcm) < SILENCE_RMS_FLOOR:
                    continue
                text = await _transcribe(api_key, pcm)
                if text:
                    await _broadcast(room, {"type": "transcript", "role": role, "text": text})
    except asyncio.CancelledError:
        pass


def _rms(pcm: bytes) -> float:
    usable = len(pcm) - (len(pcm) % 2)
    if usable <= 0:
        return 0.0
    # Sample every 8th frame; plenty for a speech/silence decision.
    samples = struct.unpack(f"<{usable // 2}h", pcm[:usable])[::8]
    if not samples:
        return 0.0
    return (sum(sample * sample for sample in samples) / len(samples)) ** 0.5


def _wav_header(pcm_length: int) -> bytes:
    return struct.pack(
        "<4sI4s4sIHHIIHH4sI",
        b"RIFF",
        36 + pcm_length,
        b"WAVE",
        b"fmt ",
        16,
        1,
        1,
        SAMPLE_RATE,
        BYTES_PER_SECOND,
        2,
        16,
        b"data",
        pcm_length,
    )


async def _transcribe(api_key: str, pcm: bytes) -> str:
    model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash-lite").strip()
    if not re.fullmatch(r"[A-Za-z0-9._-]+", model):
        model = "gemini-3.5-flash-lite"
    wav = _wav_header(len(pcm)) + pcm
    payload = {
        "contents": [
            {
                "parts": [
                    {
                        "text": (
                            "Transcribe this short phone-call audio clip. Speakers may mix "
                            "Indian English, Hindi, and Tamil; transliterate Hindi/Tamil into "
                            "Latin script. Return ONLY the spoken words as plain text with no "
                            "labels or commentary. Return an empty response if there is no speech."
                        )
                    },
                    {
                        "inline_data": {
                            "mime_type": "audio/wav",
                            "data": base64.b64encode(wav).decode("ascii"),
                        }
                    },
                ]
            }
        ],
        "generationConfig": {"temperature": 0.0, "thinkingConfig": {"thinkingLevel": "LOW"}},
    }
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    try:
        async with httpx.AsyncClient(timeout=12.0) as client:
            response = await client.post(url, headers={"x-goog-api-key": api_key}, json=payload)
            response.raise_for_status()
        text = response.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
    except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError):
        return ""
    # Mask digit runs so spoken OTPs and numbers never reach the phones as text.
    return re.sub(r"\d{3,}", "###", text)[:400]
