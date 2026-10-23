# AESOP Bridge Protocol — Termux ⇄ Horizons Wire Spec

How the Termux harness and the Horizons app conspire over device loopback.
One spec, three planes, four ports. Version 1.

## The Planes

| Port | Process | Context | Plane | Direction of use |
|------|---------|---------|-------|------------------|
| 8080 | `ort_engine` | **App** (Horizons) | NPU data plane — QNN ctx binaries on Hexagon HTP v79 | App via `NpuClient`; **Termux via plain HTTP** (the "bounce out") |
| 8081 | `llamad` (llama-server) | **Termux** | GGML data plane — Gemma 4 12B IT QAT GGUF | App via `TermuxLlmRuntime`; Termux orchestrator directly |
| 8091 | media daemon | **App** | Media plane — Moonshine STT / Kokoro TTS | App via `DaemonSttClient`/`DaemonTtsClient`; Termux via HTTP |
| 8765 | `aesopd` | **Termux** | **Control/event plane — this spec** | App connects as WebSocket client |

**The one fact everything rests on:** Android sandboxes filesystems, not
loopback. Every process on the device shares `127.0.0.1`. The NPU is reachable
by HTTP into a daemon that already holds it (`ort_engine` in app context, or
GenieX `npu-serve` on 127.0.0.1:18181). llama-server with ggml-hexagon
currently fails with 0x80000414 and falls back to CPU; GenieX is the working
NPU path from Termux (see `docs/NPU-ON-DEVICE.md`). And the app can't run GGML models
without bloating the APK — but it can HTTP into `llamad`. The bridge daemon
(`aesopd`) is the switchboard that lets either side drive the other and
streams events to the UI.

**Port discipline:** Termux must never bind 8080 or 8091 (app-owned).
The app must never bind 8081 or 8765 (Termux-owned). The old
`boot.sh` bound llama-server to 8080 — that collided with `ort_engine`
and is fixed; Termux GGML is 8081 forever.

## Transport

WebSocket, text frames only, one JSON object per frame (RFC 6455; server
is stdlib-only, no extensions, no compression). Connect:

```
ws://127.0.0.1:8765/?token=<bridge token>
```

The token is `AESOP_BRIDGE_TOKEN`, or the 0600 file `~/.aesop/bridge-token`
(generated on first start). It may instead be sent as an `X-Aesop-Token`
header. A missing or wrong token gets HTTP 401; an `Origin` header that is not
localhost gets HTTP 403. Frames over 1 MiB close the connection with code
1009. A message that is not a JSON object gets an `error` reply.

Every message carries:

```json
{ "id": "<caller-chosen correlation id>", "type": "<message type>" }
```

Replies and streamed events echo the request's `id`.

## Message Types

### Session

| Type | Direction | Payload | Reply |
|------|-----------|---------|-------|
| `hello` | client → bridge | `role`: `"ui"` \| `"agent"` | `hello.ack` `{server, version}` |
| `ping` | client → bridge | — | `pong` `{ts}` |
| `status.get` | client → bridge | — | `status` `{planes: {bridge, ggml, npu, media}}` — each `true`/`false` from live health probes |

### LLM generation

Request:

```json
{ "id": "q1", "type": "llm.generate", "prompt": "…",
  "backend": "ggml",            // "ggml" (Gemma 12B) | "npu" (ort_engine)
  "temperature": 0.7, "max_tokens": 1024 }
```

Streamed back (many):

```json
{ "id": "q1", "type": "llm.token", "token": "…", "index": 0 }
```

Terminal (exactly one):

```json
{ "id": "q1", "type": "llm.done", "tokens": 142, "ms": 8213, "backend": "ggml" }
```

or

```json
{ "id": "q1", "type": "error", "error": "ggml backend unreachable: …", "hint": "…" }
```

Backend routing inside the bridge:

- `"ggml"` → `POST http://127.0.0.1:8081/v1/chat/completions` (SSE).
  llama-server applies the **GGUF's own chat template** — never hand-roll
  Gemma turn markers on the client.
- `"npu"` → `POST http://127.0.0.1:8080/api/v1/generate` (SSE,
  `data: {"token","index"}` — `NpuClient.kt`'s exact wire protocol).

### TTS

| Type | Direction | Payload | Reply |
|------|-----------|---------|-------|
| `tts.speak` | client → bridge | `text` | `tts.done` `{ok}` — synthesized via Kokoro in proot (`tts_speak.py`) |

The app may instead use its own media daemon (8091) directly — both are
legitimate; the bridge path exists so Termux-side agents can speak too.

## Error Model

Any request can be answered by `{"id", "type": "error", "error", "hint"?}`.
The bridge never dies on a bad request or a downed backend — worst case is
an `error` frame. Reconnect policy for clients: exponential backoff
(1s → 2s → 4s → … cap 30s), re-send `hello` on reconnect.

## Failure Modes & Fallback Chain

| Situation | Behavior |
|-----------|----------|
| `llamad` down | `llm.generate[ggml]` → `error` with hint; client may retry with `backend:"npu"` |
| App/`ort_engine` down | `llm.generate[npu]` → `error`; client falls back to `"ggml"` |
| Both down | UI shows planes from `status.get`; MEMO/OpenWiki file lookups still work |
| Bridge down | App's `AesopBridgeClient` backoff-reconnects; direct-HTTP paths (8080/8081) unaffected |

The two data planes are deliberately independent of the control plane:
killing `aesopd` never interrupts a generation running over direct HTTP.

## Version

`hello.ack.version` = 1. Additive changes (new types) don't bump it;
breaking changes to existing frames do.
