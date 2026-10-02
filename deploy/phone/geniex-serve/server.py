#!/data/data/com.termux/files/usr/bin/python3
"""OpenAI-compatible server for GenieX on the phone NPU (llama_cpp plugin -> HTP).

  server.py --model <path.gguf> [--mode npu|hybrid|cpu] [--port 18181] [--ctx 4096]

Endpoints: GET /health, GET /v1/models, POST /v1/chat/completions (stream or not).
One model, loaded once; requests run one at a time.
"""
import argparse, base64, ctypes, json, os, sys, tempfile, threading, time, urllib.request, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
CB = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_char_p, ctypes.c_void_p)

ap = argparse.ArgumentParser()
ap.add_argument("--model", required=True, help="path, or a name from models.json")
ap.add_argument("--mode", default="npu")
ap.add_argument("--port", type=int, default=18181)
ap.add_argument("--ctx", type=int, default=4096)
args = ap.parse_args()

shim = ctypes.CDLL(os.environ.get("GENIEX_SHIM") or os.path.join(HERE, "libgeniex_shim.so"))
shim.shim_load.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
shim.shim_load2.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p]
shim.shim_chat.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p),
                           ctypes.c_int, ctypes.c_float, ctypes.c_float, ctypes.c_int, CB, ctypes.c_void_p,
                           ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_double),
                           ctypes.c_char_p, ctypes.c_int]
shim.shim_free.argtypes = [ctypes.c_void_p]
shim.shim_load_vlm.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p]
shim.shim_vlm_chat.argtypes = shim.shim_chat.argtypes[:3] + [ctypes.POINTER(ctypes.c_char_p)] + shim.shim_chat.argtypes[3:]

REG = json.load(open(os.path.join(HERE, "models.json")))
lock = threading.Lock()
MODEL_ID = None
VLM = False  # loaded model went through geniex_vlm_create (accepts images)
IMG_DIR = tempfile.mkdtemp(prefix="npu-serve-img-")


def load(name_or_path):
    """Load a model by models.json name or by path; unloads the current one first."""
    global MODEL_ID, VLM
    e = REG.get(name_or_path) or {"path": name_or_path, "plugin": "qairt" if os.path.isdir(name_or_path) else "llama_cpp"}
    vlm = bool(e.get("mmproj") or e.get("vlm"))
    shim.shim_unload()
    if vlm:
        rc = shim.shim_load_vlm(e["path"].encode(), (e.get("mmproj") or "").encode(), args.mode.encode(),
                                args.ctx, e["plugin"].encode())
    else:
        rc = shim.shim_load2(e["path"].encode(), args.mode.encode(), args.ctx, e["plugin"].encode())
    if rc < 0:
        MODEL_ID = None
        raise RuntimeError(f"load failed ({rc}) for {name_or_path}")
    MODEL_ID, VLM = (name_or_path if name_or_path in REG else os.path.basename(name_or_path)), vlm
    print(f"loaded {MODEL_ID} ({e['plugin']}{', vlm' if vlm else ''})", flush=True)


def image_file(url):
    """OpenAI image_url -> local file path (data: URLs and http(s) are written to IMG_DIR)."""
    if url.startswith("data:"):
        head, b64 = url.split(",", 1)
        ext = head.split("/")[1].split(";")[0] if "/" in head else "png"
        data = base64.b64decode(b64)
    elif url.startswith(("http://", "https://")):
        data, ext = urllib.request.urlopen(url, timeout=30).read(), url.rsplit(".", 1)[-1][:4] or "jpg"
    else:
        return url[7:] if url.startswith("file://") else url
    path = os.path.join(IMG_DIR, uuid.uuid4().hex + "." + ext)
    open(path, "wb").write(data)
    return path


load(args.model)
print(f"ready: {MODEL_ID} mode={args.mode} http://127.0.0.1:{args.port}/v1", flush=True)


def chat(body, on_token):
    msgs = body.get("messages") or []
    roles = (ctypes.c_char_p * len(msgs))(*[m.get("role", "user").encode() for m in msgs])
    texts, imgs, tmp = [], [], []
    for m in msgs:
        c, img = m.get("content") or "", None
        if isinstance(c, list):  # OpenAI content parts: text parts joined, first image_url kept
            for p in c:
                if isinstance(p, dict) and p.get("type") == "image_url" and img is None:
                    u = p["image_url"]["url"] if isinstance(p["image_url"], dict) else p["image_url"]
                    img = image_file(u)
                    if img.startswith(IMG_DIR): tmp.append(img)
            c = "".join(p.get("text", "") for p in c if isinstance(p, dict))
        texts.append(c.encode()); imgs.append(img.encode() if img else None)
    contents = (ctypes.c_char_p * len(msgs))(*texts)
    images = (ctypes.c_char_p * len(msgs))(*imgs)
    cb = CB(lambda tok, _ud: bool(on_token(tok.decode("utf-8", "replace"))) if tok else True)
    out = ctypes.c_void_p(); stats = (ctypes.c_double * 4)(); stop = ctypes.create_string_buffer(32)
    want = body.get("model")
    with lock:
        if want and want in REG and want != MODEL_ID:
            load(want)
        if any(imgs) and not VLM:
            raise RuntimeError(f"{MODEL_ID} was loaded without vision; images need a models.json entry with mmproj")
        head = (len(msgs), roles, contents, images) if VLM else (len(msgs), roles, contents)
        rc = (shim.shim_vlm_chat if VLM else shim.shim_chat)(*head, int(body.get("max_tokens") or 512),
                            float(body.get("temperature", 0.7)), float(body.get("top_p", 0.95)),
                            1 if body.get("enable_thinking") else 0, cb, None,
                            ctypes.byref(out), stats, stop, 32)
    for f in tmp: os.remove(f)
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
            return self._json(200, {"object": "list", "loaded": MODEL_ID, "data": [{"id": k, "object": "model", "owned_by": "geniex", "plugin": v["plugin"], "vision": bool(v.get("mmproj") or v.get("vlm"))} for k, v in REG.items()]})
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
            fin = {**base, "object": "chat.completion.chunk",
                   "choices": [{"index": 0, "delta": {}, "finish_reason": "length" if stop == "length" else "stop"}],
                   "usage": {"prompt_tokens": int(st[0]), "completion_tokens": int(st[1])},
                   "timings": {"prefill_tps": round(st[2], 1), "decode_tps": round(st[3], 1)}}
            self.wfile.write(b"data: " + json.dumps(fin).encode() + b"\n\n"); self.wfile.flush()
            self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush()
            print(f"stream done: {int(st[1])} tok, prefill {st[2]:.1f} tok/s, decode {st[3]:.1f} tok/s", flush=True)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            self._json(500, {"error": str(e)})

    def log_message(self, fmt, *a):
        print("%s %s" % (self.address_string(), fmt % a), flush=True)


ThreadingHTTPServer(("127.0.0.1", args.port), H).serve_forever()
