# Local AI on your phone — operator guide

*Written 2026-10-01. Every command below was tested on this phone unless marked **not tested**. Device: Snapdragon 8 Elite (HTP v79).*

---

## 1. Shortcut commands (type these in Termux)

| Command | What it does |
|---|---|
| `models` | Lists every model on the phone, with size and full path |
| `npu-ask "question"` | Answers on the **NPU** and prints the answer in the terminal |
| `npu-ask -s "question"` | Same, and **speaks** the answer aloud |
| `npu-ask -m <path> "question"` | Uses a different model (path from `models`) |
| `npu-serve` | Starts the **NPU server** (GenieX, OpenAI API at `http://127.0.0.1:18181/v1`); `npu-serve status`, `npu-serve stop` |
| `ai-web` | Starts a **browser chat** at `http://127.0.0.1:8081` and opens it |
| `ai-web <path>` | Browser chat with a different model |
| `ai-stop` | Stops the browser chat and frees its memory |
| `talk` | **Voice:** you speak, the NPU model answers out loud (one question) |
| `talk -l` | Voice conversation loop; say "stop" to end |
| `vv` | Voice typing into Claude Code (see §6) |
| `speak "text"` | Reads text aloud; `speak --stop` cuts it off |

All shortcuts live in `~/bin/`. Each prints its own help with `-h`, or open the file to read its header.

---

## 2. Run your Qwen in the terminal (NPU) — `npu-ask`

```
npu-ask "Explain what an NPU is in two sentences."
```
- Default model: **Qwen 3.5 2B Q4_0** (`~/downloads/Qwen3.5-2B-Q4_0.gguf`).
- The status line at the end shows the model and speed, e.g. `[Qwen3.5-2B-Q4_0.gguf, decode=18.9tps]`.
- It runs through **GenieX** (`~/tools/geniex-bench`), Qualcomm's own runtime: a plain GGUF goes through llama.cpp's Hexagon backend onto the HTP. No internet, no computer.

**Options**
- `-s`: also speak the answer.
- `NPU_TOKENS=600 npu-ask "..."`: longer answers (default 300 tokens).
- `NPU_DEVICE=npu npu-ask "..."`: pure NPU. The default is `hybrid` (NPU + CPU per operation), Qualcomm's "fast path".
- Pipe text in: `cat notes.md | npu-ask -m <model>`.

**How each call works:** it loads the model, answers once, then exits, so each question has a few seconds of load time. It's a one-shot asker, not a chat with memory. For back-and-forth chat, use `ai-web` (§3).

**Measured speeds** (2B models, phone busy with other apps): Qwen 3.5 2B 18–23 tok/s, Gemma 4 E2B ~16 tok/s. Qualcomm's own numbers for 2B Q4_0 on this chip are ~45–50 tok/s. Closing other apps helps, and so will a fix for the newer GenieX (see §8).

---

## 3. Use it in a browser — `ai-web`

```
ai-web                 # default Qwen 2B
ai-web /storage/emulated/0/Documents/Models/Qwen3.5-9B-Q4_0.gguf
ai-stop                # when done (frees the RAM)
```
- It opens `http://127.0.0.1:8081` in your browser: a full chat page with history, built into llama.cpp's server.
- This browser chat page runs on the **CPU** (llama-server, ~25 tok/s on the 2B). For the **NPU**, use `npu-serve` below.

### NPU server — `npu-serve` (tested 2026-10-02)
```
npu-serve                       # Qwen 3.5 2B on the NPU, http://127.0.0.1:18181/v1
npu-serve <path.gguf> hybrid    # other model / mode
npu-serve status | stop
```
- Serves the model **from GenieX itself**: the Android GenieX package ships the full SDK (`libgeniex.so`), not just the benchmark tool. `~/tools/geniex-serve` is a small C shim plus a Python server over it, loading the model once and keeping it on the HTP.
- Measured: `Hexagon Arch version v79`, `HTP0 new session`, `offloaded 25/25 layers`; prefill 47.9 tok/s, decode 19.2 tok/s.
- OpenAI API (`/v1/chat/completions`, streaming or not, `/v1/models`, `/health`), so OmniRoute, scripts and wiki tools can call it. Log: `~/.cache/geniex-serve.log`.
- The log is in `~/.cache/ai-web.log`.

---

## 4. Qualcomm's test app vs your own browser URL

| | Qualcomm GenieX Chat app | Your browser URL (`ai-web`) |
|---|---|---|
| Runs on | **NPU**, inside an Android app (official path) | `ai-web` page: CPU. `npu-serve` API: **NPU** |
| Get it | Must be **built** (no ready-made APK is published) | Works now |
| Models | Picks and downloads models in-app (HF / AI Hub), NPU/GPU/CPU toggle | Any GGUF on the phone |
| Other tools can call it | No | Yes, OpenAI-style API |

**To get Qualcomm's app (not tested here).** Source: `github.com/qualcomm/ai-hub-apps`, under `geniex_chat_android` (see the "Android Install" page in your GenieX fork, `~/repos/GenieX/docs/en/run/android/install.mdx`).
1. Fork `qualcomm/ai-hub-apps` to `c10vis-poem` (your fork rule).
2. Build the APK with a GitHub Actions workflow (Gradle `assembleDebug`), or with Android Studio on a computer. Termux can't run Android Studio.
3. Install the APK, pick a model, choose **NPU**.

This is also the starting point for **Hyperion-OXiLm**: the same GenieX Android SDK (`com.qualcomm.qti:geniex-android`).

---

## 5. Swapping models

1. Run `models` to see what's on the phone.
2. Pick one:
   - terminal NPU: `npu-ask -m <full path> "..."`
   - browser: `ai-stop` first, then `ai-web <full path>`
3. **Chat format** is picked automatically from the file name: *qwen* and *gemma* are handled. For any other family (Granite, Llama…), use `NPU_FORMAT=raw`, or add its format to `~/bin/npu-ask`.
4. **Memory guide** (you have ~14 GB; close apps for the big ones):

| Model | Size | Notes |
|---|---|---|
| Qwen 3.5 2B Q4_0 | 1.1 GB | default, fast |
| Gemma 4 E2B | 2.4–3.1 GB | fast |
| Granite 4.0 H micro Q4_0 | 1.7 GB | use `NPU_FORMAT=raw` |
| Gemma 4 E4B | 4.5–4.8 GB | medium |
| Qwen 3.5 9B Q4_0 | 5.0–5.3 GB | the strong one; **not tested on the NPU yet**. Over ~3.5 GB, one NPU session has to map weights in and out or be split across sessions (see `~/.claude/NPU-ON-DEVICE.md`) |
| Gemma 4 12B QAT Q4_0 | 6.5 GB | close other apps first |

- **Q4_0 runs best on the NPU.** K-quants (`Q4_K_XL`, `q4_k_m`) and `IQ4_NL` get less NPU help.
- **The Qwen 3.5 2B GGUF is an AI Hub model.** AI Hub publishes curated GGUFs for llama.cpp alongside its precompiled bundles (`GenieX/docs/en/models/supported.mdx:10`), and GenieX runs it directly on the NPU through its `llama_cpp` runtime. No other model is needed.
- AI Hub's precompiled `qairt` bundles (`*.zip`, e.g. the Qwen3-VL 4B on the phone) are a second, optional route, not a requirement.

---

## 6. Voice pipeline (speech-to-text, voice detection, text-to-speech)

**What you have today**

| Piece | Tool | Status |
|---|---|---|
| Speech-to-text (default) | `vv` → Android's own speech-to-text | Works, but **stops at your first pause**, so you get half a sentence per press |
| Speech-to-text (offline) | `VV_ENGINE=local vv` → Moonshine model in the Debian proot | Works, with a **~10 s limit** per capture (Moonshine export limit); stop early with `vv stop` |
| Voice activity detection (auto-stop when you stop talking) | `aesop-xi/deploy/phone/vad_monitor.py` (Silero VAD) | **Built but never wired in**; its library `onnxruntime` isn't installed in the proot |
| Text-to-speech | `speak` → Android TTS (or piper if installed) | Works; nothing calls it automatically |
| Full loop | `talk` (new): Android speech-to-text → NPU model → `speak` | **Built today; not tested live with the mic** |
| Engine | `aesop-voice-pipeline` skill: `run_voice_loop.sh` (mic → VAD → STT → TTS) | `--demo` passed 2026-08-29; live mic loop not confirmed; its "LLM" step is still a stub |

**Try it now**
```
talk          # say one question after the buzz; it answers out loud
talk -l       # conversation; say "stop" to end
```

**Steps to a complete offline voice agent** (the open items, in order):
1. **Longer speech-to-text:** switch Moonshine to the streaming model `sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27`, which has no 10 s limit.
2. **Auto-stop when you stop talking:** install `onnxruntime` in the proot venv (`/root/venv`), then wire `vad_monitor.py` into `vv`'s local engine.
3. **Real model in the loop:** replace the stub in `live_voice_loop.py` (`response = f"You said: {text}"`) with a call to `npu-ask`, or later to the GenieX wrapper's HTTP address.
4. **Neural voice:** Kokoro TTS models are already on the phone (`~/kokoro/onnx/`, `~/sherpa-kokoro/`) and can replace Android TTS in `speak`.
5. **Long term:** the voice stack moves into **CloviX-AEyre** (the voice/vision app), per the naming plan.

Each step installs or changes things, so run them in a session with Claude, one at a time with an approval card each.

---

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| `npu-ask` says model not found | Use the full path from `models` |
| Plugin load error `libOpenCL.so not found` | Already handled in `npu-ask` (`/vendor/lib64` on the library path) |
| `failed to open session 0 : error 0x80000406` | The NPU code library must sit where FastRPC looks: `ln -sf llama_cpp/libggml-htp-v79.so ~/tools/geniex-bench/lib/libggml-htp-v79.so` (`npu-ask` does this automatically). Run `logcat -d \| grep -i adsprpc` to see every path searched |
| Is it really on the NPU? | Run `GGML_HEX_VERBOSE=1` with the bench tool: look for `Hexagon Arch version v79` and `HTP0 new session`. No such lines means it silently fell back to the CPU |
| Slow or killed | Close other apps; use `ai-stop`; use a smaller model |
| `ai-web` won't start | `cat ~/.cache/ai-web.log` |

---

## 8. Open items (as of 2026-10-01)

- **Newer GenieX v0.7.1** (installed at `~/tools/geniex-bench-android-arm64-v0.7.1`) puts the whole model on the NPU and reads prompts faster, but generation drops to ~3 tok/s from Termux. Its "DSP queue" call fails (`0x80000414`). Leading theory: Termux isn't allowed to read `/vendor/dsp/`. The test is to run it through wireless debugging (ADB to the phone itself).
- ~~GenieX HTTP wrapper~~ **done 2026-10-02:** `npu-serve` (§3).
- **Newer GenieX builds:** v0.3.16–v0.3.19 (Jul 20–Aug 7) came out after the installed v0.3.14 and update llama.cpp. Test their speed against v0.3.14.
- **Qualcomm chat app build** (§4).
- **The voice items** in §6.
- **Qwen 3.5 9B on the NPU:** not tested yet.
