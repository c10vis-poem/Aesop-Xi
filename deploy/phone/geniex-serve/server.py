#!/data/data/com.termux/files/usr/bin/python3
"""OpenAI-compatible server for GenieX on the phone NPU (llama_cpp plugin -> HTP).

  server.py --model <path.gguf> [--mode npu|hybrid|cpu] [--port 18181] [--ctx 4096]

Endpoints: GET /health, GET /v1/models, POST /v1/chat/completions (stream or not).
One model, loaded once; requests run one at a time.
"""
import argparse, ctypes, json, os, sys, threading, time, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
CB = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_char_p, ctypes.c_void_p)

ap = argparse.ArgumentParser()
ap.add_argument("--model", required=True)
ap.add_argument("--mode", default="npu")
ap.add_argument("--port", type=int, default=18181)
ap.add_argument("--ctx", type=int, default=4096)
args = ap.parse_args()

shim = ctypes.CDLL(os.environ.get("GENIEX_SHIM") or os.path.join(HERE, "libgeniex_shim.so"))
shim.shim_load.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
shim.shim_chat.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p),
                           ctypes.c_int, ctypes.c_float, ctypes.c_float, ctypes.c_int, CB, ctypes.c_void_p,
                           ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_double),
                           ctypes.c_char_p, ctypes.c_int]
shim.shim_free.argtypes = [ctypes.c_void_p]

rc = shim.shim_load(args.model.encode(), args.mode.encode(), args.ctx)
if rc < 0:
    sys.exit(f"model load failed ({rc})")
MODEL_ID = os.path.basename(args.model)
lock = threading.Lock()
print(f"ready: {MODEL_ID} mode={args.mode} http://127.0.0.1:{args.port}/v1", flush=True)


def chat(body, on_token):
    msgs = body.get("messages") or []
    roles = (ctypes.c_char_p * len(msgs))(*[m.get("role", "user").encode() for m in msgs])
    texts = []
    for m in msgs:
        c = m.get("content") or ""
        if isinstance(c, list):  # OpenAI content parts: keep the text parts
            c = "".join(p.get("text", "") for p in c if isinstance(p, dict))
        texts.append(c.encode())
    contents = (ctypes.c_char_p * len(msgs))(*texts)
    cb = CB(lambda tok, _ud: bool(on_token(tok.decode("utf-8", "replace"))) if tok else True)
    out = ctypes.c_void_p(); stats = (ctypes.c_double * 4)(); stop = ctypes.create_string_buffer(32)
    with lock:
        rc = shim.shim_chat(len(msgs), roles, contents, int(body.get("max_tokens") or 512),
                            float(body.get("temperature", 0.7)), float(body.get("top_p", 0.95)),
                            1 if body.get("enable_thinking") else 0, cb, None,
                            ctypes.byref(out), stats, stop, 32)
    if rc < 0:
        raise RuntimeError(f"generate failed ({rc})")
    text = ctypes.string_at(out.value).decode("utf-8", "replace") if out.value else ""
    shim.shim_free(out)
    return text, list(stats), stop.value.decode()


class H(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        if self.path == "/health":
            return self._json(200, {"status": "ok", "model": MODEL_ID, "mode": args.mode})
        if self.path == "/v1/models":
            return self._json(200, {"object": "list", "data": [{"id": MODEL_ID, "object": "model", "owned_by": "geniex"}]})
        self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            return self._json(404, {"error": "not found"})
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        cid, now = "chatcmpl-" + uuid.uuid4().hex[:12], int(time.time())
        base = {"id": cid, "created": now, "model": MODEL_ID}
        try:
            if not body.get("stream"):
                text, st, stop = chat(body, lambda t: True)
                return self._json(200, {**base, "object": "chat.completion",
                    "choices": [{"index": 0, "message": {"role": "assistant", "content": text},
                                 "finish_reason": "length" if stop == "length" else "stop"}],
                    "usage": {"prompt_tokens": int(st[0]), "completion_tokens": int(st[1]),
                              "total_tokens": int(st[0] + st[1])},
                    "timings": {"prefill_tps": round(st[2], 1), "decode_tps": round(st[3], 1)}})
            self.send_response(200); self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache"); self.end_headers()

            def send(delta, finish=None):
                ch = {**base, "object": "chat.completion.chunk",
                      "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
                self.wfile.write(b"data: " + json.dumps(ch).encode() + b"\n\n"); self.wfile.flush()

            send({"role": "assistant"})
            _, st, stop = chat(body, lambda t: (send({"content": t}), True)[1])
            send({}, "length" if stop == "length" else "stop")
            self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush()
            print(f"stream done: {int(st[1])} tok, prefill {st[2]:.1f} tok/s, decode {st[3]:.1f} tok/s", flush=True)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            self._json(500, {"error": str(e)})

    def log_message(self, fmt, *a):
        print("%s %s" % (self.address_string(), fmt % a), flush=True)


ThreadingHTTPServer(("127.0.0.1", args.port), H).serve_forever()
