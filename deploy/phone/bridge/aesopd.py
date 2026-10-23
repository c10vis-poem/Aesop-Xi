#!/usr/bin/env python3
"""aesopd — AESOP bridge daemon (Termux side).

The control/event plane between the Termux harness and the Horizons app.
Pure stdlib (RFC 6455 WebSocket server, text frames) — no pip installs,
survives a fresh Termux with only `python` installed.

Topology (all loopback, all on-device):

  ws://127.0.0.1:8765            THIS daemon (control + events)
  http://127.0.0.1:8080          ort_engine   — NPU daemon in app context (QNN/HTP)
  http://127.0.0.1:8081          llama-server — Gemma 4 12B IT QAT GGUF (GGML)
  http://127.0.0.1:8091          media daemon — STT/TTS in app context

Why this shape: loopback is shared device-wide. The app's ort_engine is one
NPU gateway, reached by HTTP (GenieX npu-serve on 127.0.0.1:18181 is the
other NPU path; llama-server+ggml-hexagon currently fails with 0x80000414).
The Kotlin UI reaches US by WebSocket for streaming tokens, voice events,
and status. Everyone conspires over localhost.

Auth: loopback is shared by every app and browser page, so the upgrade needs
the bridge token (env AESOP_BRIDGE_TOKEN, else ~/.aesop/bridge-token, created
0600 on first start) as ?token=... or header X-Aesop-Token, and any Origin
header must be a localhost origin.

Protocol: newline-free JSON per text frame. Envelope: {"id", "type", ...}.
See aesop/protocol/bridge-protocol.md for the full spec.

Usage:  python3 aesopd.py [--port 8765]
Daemonized via termux-services (see deploy/phone/daemons/).
"""

import argparse
import base64
import hashlib
import hmac
import json
import os
import secrets
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
import urllib.error

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

GGML_BASE = os.environ.get("AESOP_GGML_BASE", "http://127.0.0.1:8081")
NPU_BASE = os.environ.get("AESOP_NPU_BASE", "http://127.0.0.1:8080")
MEDIA_BASE = os.environ.get("AESOP_MEDIA_BASE", "http://127.0.0.1:8091")
AESOP_DIR = os.environ.get("AESOP_DIR", os.path.expanduser("~/aesop"))
TTS_SCRIPT = os.path.join(AESOP_DIR, "deploy/phone/tts_speak.py")
TTS_OUT = os.path.expanduser("~/.aesop/tts-out.wav")
TOKEN_FILE = os.path.expanduser("~/.aesop/bridge-token")
MAX_FRAME = 1 << 20
MAX_HEADERS = 16384


def load_token():
    tok = os.environ.get("AESOP_BRIDGE_TOKEN")
    if tok:
        return tok
    if not os.path.exists(TOKEN_FILE):
        os.makedirs(os.path.dirname(TOKEN_FILE), mode=0o700, exist_ok=True)
        fd = os.open(TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(secrets.token_urlsafe(32))
    with open(TOKEN_FILE) as f:
        return f.read().strip()


TOKEN = None  # set in main()


def origin_ok(origin):
    if origin is None:
        return True
    return urllib.parse.urlparse(origin).hostname in ("localhost", "127.0.0.1", "::1")


def log(msg):
    print(f"[aesopd] {msg}", flush=True)


# ── RFC 6455 minimal server ─────────────────────────────────────────


OVERSIZE = -1


class WsConn:
    """One connected WebSocket client (the Horizons app, or a debug tool)."""

    def __init__(self, sock, addr):
        self.sock = sock
        self.addr = addr
        self.alive = True
        self.send_lock = threading.Lock()
        self.role = "unknown"

    def handshake(self):
        data = b""
        self.sock.settimeout(5)
        while b"\r\n\r\n" not in data:
            chunk = self.sock.recv(4096)
            if not chunk or len(data) > MAX_HEADERS:
                return False
            data += chunk
        lines = data.decode("utf-8", "replace").split("\r\n")
        headers = {}
        for line in lines[1:]:
            if ": " in line:
                k, v = line.split(": ", 1)
                headers[k.lower()] = v
        key = headers.get("sec-websocket-key")
        if not key:
            return False
        parts = lines[0].split(" ")
        query = urllib.parse.parse_qs(urllib.parse.urlparse(parts[1] if len(parts) > 1 else "").query)
        supplied = headers.get("x-aesop-token") or (query.get("token") or [""])[0]
        if not origin_ok(headers.get("origin")):
            self.sock.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
            return False
        if not hmac.compare_digest(supplied.encode(), TOKEN.encode()):
            self.sock.sendall(b"HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n")
            return False
        accept = base64.b64encode(
            hashlib.sha1((key + WS_GUID).encode()).digest()
        ).decode()
        resp = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        )
        self.sock.sendall(resp.encode())
        self.sock.settimeout(None)
        return True

    def recv_frame(self):
        """Returns (opcode, payload bytes) or (None, None) on close/error."""
        try:
            head = self._recv_exact(2)
            if head is None:
                return None, None
            b1, b2 = head
            opcode = b1 & 0x0F
            masked = b2 & 0x80
            length = b2 & 0x7F
            if length == 126:
                ext = self._recv_exact(2)
                if ext is None:
                    return None, None
                length = struct.unpack(">H", ext)[0]
            elif length == 127:
                ext = self._recv_exact(8)
                if ext is None:
                    return None, None
                length = struct.unpack(">Q", ext)[0]
            if length > MAX_FRAME:
                return OVERSIZE, None
            mask = b""
            if masked:
                mask = self._recv_exact(4)
                if mask is None:
                    return None, None
            payload = self._recv_exact(length) if length else b""
            if payload is None:
                return None, None
            if masked and payload:
                payload = bytes(
                    b ^ mask[i % 4] for i, b in enumerate(payload)
                )
            return opcode, payload
        except (OSError, socket.timeout):
            return None, None

    def _recv_exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                return None
            buf += chunk
        return buf

    def send_text(self, text):
        payload = text.encode("utf-8")
        n = len(payload)
        if n < 126:
            head = struct.pack(">BB", 0x81, n)
        elif n < 65536:
            head = struct.pack(">BBH", 0x81, 126, n)
        else:
            head = struct.pack(">BBQ", 0x81, 127, n)
        try:
            with self.send_lock:
                self.sock.sendall(head + payload)
            return True
        except OSError:
            self.alive = False
            return False

    def send_json(self, obj):
        return self.send_text(json.dumps(obj, ensure_ascii=False))

    def pong(self, payload):
        n = len(payload)
        head = struct.pack(">BB", 0x8A, n)
        try:
            with self.send_lock:
                self.sock.sendall(head + payload)
        except OSError:
            self.alive = False

    def close_frame(self, code):
        payload = struct.pack(">H", code)
        try:
            with self.send_lock:
                self.sock.sendall(struct.pack(">BB", 0x88, len(payload)) + payload)
        except OSError:
            pass

    def close(self):
        self.alive = False
        try:
            self.sock.close()
        except OSError:
            pass


# ── Backend plumbing ────────────────────────────────────────────────


def http_health(base, path="/health", timeout=2):
    try:
        with urllib.request.urlopen(base + path, timeout=timeout) as r:
            return r.status == 200
    except Exception:
        return False


def sse_stream(url, body, on_data):
    """POST JSON, iterate SSE `data:` lines. on_data(dict) → False aborts."""
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
            except json.JSONDecodeError:
                continue
            if on_data(obj) is False:
                break


def generate_ggml(conn, mid, prompt, opts):
    """Gemma 4 12B via llama-server's OpenAI endpoint (applies the GGUF's
    own chat template server-side — no hand-rolled Gemma turn markers)."""
    body = {
        "model": "local",
        "messages": [{"role": "user", "content": prompt}],
        "stream": True,
        "temperature": opts.get("temperature", 0.7),
        "max_tokens": opts.get("max_tokens", 1024),
    }
    idx = [0]

    def on_data(obj):
        if not conn.alive:
            return False
        delta = (obj.get("choices") or [{}])[0].get("delta", {})
        tok = delta.get("content")
        if tok:
            conn.send_json({"id": mid, "type": "llm.token", "token": tok, "index": idx[0]})
            idx[0] += 1
        return True

    sse_stream(GGML_BASE + "/v1/chat/completions", body, on_data)
    return idx[0]


def generate_npu(conn, mid, prompt, opts):
    """Bounce out to ort_engine (app context → Hexagon HTP). Its wire
    protocol is NpuClient.kt's: POST /api/v1/generate → data:{"token","index"}."""
    body = {
        "prompt": prompt,
        "temperature": opts.get("temperature", 0.7),
        "max_tokens": opts.get("max_tokens", 1024),
        "stream": True,
    }
    idx = [0]

    def on_data(obj):
        if not conn.alive:
            return False
        tok = obj.get("token")
        if tok:
            conn.send_json({"id": mid, "type": "llm.token", "token": tok, "index": obj.get("index", idx[0])})
            idx[0] += 1
        return True

    sse_stream(NPU_BASE + "/api/v1/generate", body, on_data)
    return idx[0]


def speak(text):
    """Kokoro TTS via the existing pipeline script (proot Debian)."""
    cmd = [
        "proot-distro", "login", "debian", "--bind", f"{os.path.expanduser('~')}:{os.path.expanduser('~')}",
        "--", "python3", TTS_SCRIPT, "--", TTS_OUT, text,
    ]
    os.makedirs(os.path.dirname(TTS_OUT), exist_ok=True)
    return subprocess.run(cmd, capture_output=True, timeout=120).returncode == 0


# ── Message router ──────────────────────────────────────────────────


def handle_message(conn, msg):
    mid = msg.get("id", "")
    mtype = msg.get("type", "")

    if mtype == "hello":
        conn.role = msg.get("role", "ui")
        conn.send_json({"id": mid, "type": "hello.ack", "server": "aesopd", "version": 1})

    elif mtype == "status.get":
        conn.send_json({
            "id": mid,
            "type": "status",
            "planes": {
                "bridge": True,
                "ggml": http_health(GGML_BASE),
                "npu": http_health(NPU_BASE),
                "media": http_health(MEDIA_BASE),
            },
        })

    elif mtype == "llm.generate":
        prompt = msg.get("prompt", "")
        backend = msg.get("backend", "ggml")
        t0 = time.time()
        try:
            gen = generate_npu if backend == "npu" else generate_ggml
            count = gen(conn, mid, prompt, msg)
            conn.send_json({
                "id": mid, "type": "llm.done", "tokens": count,
                "ms": int((time.time() - t0) * 1000), "backend": backend,
            })
        except urllib.error.URLError as e:
            conn.send_json({
                "id": mid, "type": "error",
                "error": f"{backend} backend unreachable: {e.reason}",
                "hint": "ggml→ is llamad running (sv status llamad)? npu→ is the app's ort_engine up?",
            })
        except Exception as e:  # keep the daemon alive no matter what
            conn.send_json({"id": mid, "type": "error", "error": str(e)})

    elif mtype == "tts.speak":
        ok = False
        try:
            ok = speak(msg.get("text", ""))
        except Exception as e:
            log(f"tts error: {e}")
        conn.send_json({"id": mid, "type": "tts.done", "ok": ok})

    elif mtype == "ping":
        conn.send_json({"id": mid, "type": "pong", "ts": time.time()})

    else:
        conn.send_json({"id": mid, "type": "error", "error": f"unknown type: {mtype}"})


def client_thread(conn):
    if not conn.handshake():
        conn.close()
        return
    log(f"client connected: {conn.addr}")
    while conn.alive:
        opcode, payload = conn.recv_frame()
        if opcode == OVERSIZE:
            conn.close_frame(1009)
            break
        if opcode is None or opcode == 0x8:  # closed
            break
        if opcode == 0x9:  # ping
            conn.pong(payload)
            continue
        if opcode != 0x1:  # only text frames carry protocol
            continue
        try:
            msg = json.loads(payload.decode("utf-8", "replace"))
        except ValueError:
            conn.send_json({"type": "error", "error": "bad json"})
            continue
        if not isinstance(msg, dict):
            conn.send_json({"type": "error", "error": "message must be a JSON object"})
            continue
        # Each request handled on its own thread so a long generation
        # doesn't block pings/status from the same client.
        threading.Thread(target=handle_message, args=(conn, msg), daemon=True).start()
    conn.close()
    log(f"client gone: {conn.addr}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=int(os.environ.get("AESOP_BRIDGE_PORT", 8765)))
    args = ap.parse_args()
    global TOKEN
    TOKEN = load_token()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(8)
    log(f"listening on ws://127.0.0.1:{args.port}")
    log(f"planes: ggml={GGML_BASE} npu={NPU_BASE} media={MEDIA_BASE}")

    while True:
        sock, addr = srv.accept()
        conn = WsConn(sock, addr)
        threading.Thread(target=client_thread, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
