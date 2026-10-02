# NPU server build log: Qwen 3.5 on GenieX, on the phone

*Written 2026-10-02 (phone, Claude Code). Covers the 2026-10-01 session and this one. User guide: [LOCAL-AI-GUIDE.md](LOCAL-AI-GUIDE.md). Settled facts: `~/.claude/NPU-ON-DEVICE.md`.*

**Sources read for this log:** the 2026-10-01 transcript (`b6ab92d6…`, the Qwen3-VL and HTP passages), `LOCAL-AI-GUIDE.md`, `NPU-ON-DEVICE.md`, `RESUME.md`, the GenieX fork docs (`platforms.mdx`, `models/supported.mdx`, `run/cli/reference.mdx`, `run/android/api-reference.mdx`), `sdk/include/geniex.h` at three revisions, and the GenieX release list and notes v0.3.16–v0.3.19.
**Not read:** the rest of the 2026-10-01 transcript, the Hexagon SDK, and GenieX source beyond the header.

---

## 1. Where it stands

| | |
|---|---|
| Runtime | **GenieX v0.7.1** (current release, 2026-09-28), `~/tools/geniex-bench-android-arm64-v0.7.1`. Tarball sha256 `857879f8…83bf01` matches Qualcomm's release. |
| Model | Qwen 3.5 2B Q4_0, AI Hub's curated GGUF (`~/downloads/Qwen3.5-2B-Q4_0.gguf`) |
| Device | `npu`: 100% on `HTP0`, all layers, power mode **burst** |
| Server | `npu-serve` → `http://127.0.0.1:18181/v1` (OpenAI API: `/v1/chat/completions` streaming or not, `/v1/models`, `/health`) |
| Measured | prefill 161–194 tok/s, decode 16.8–17.0 tok/s (server); bench: prefill 644, decode 15.9 tok/s |
| Proof it's on the NPU | log has `Hexagon Arch version v79`, `HTP0 new session … domain-id 3`, layers assigned to HTP0 |

## 2. What the 2026-10-01 session got right
- **Got a GGUF onto the HTP from Termux.** Two fixes: put `/vendor/lib64` on `LD_LIBRARY_PATH` (for `libOpenCL.so`, or the plugin won't load), and add the link `lib/libggml-htp-v79.so → llama_cpp/libggml-htp-v79.so` (FastRPC only searches `lib/` and `lib/cdsp/`).
- Wrote down how to prove the NPU is in use (the `Hexagon Arch` and `HTP0` log lines), and to always compare against a CPU baseline.
- Built the shortcuts `npu-ask`, `models`, `ai-web`, `ai-stop` and `talk`, and the facts file `NPU-ON-DEVICE.md`.
- Recorded the benchmarks and the target (~45–50 tok/s, Qualcomm's own number for a 2B Q4_0).

## 3. What it got wrong (corrected 2026-10-02)
| Claim | Reality |
|---|---|
| "Qwen3-VL 4B bundle is the ready-made NPU bundle" | Not needed. The Qwen 3.5 2B GGUF **is** an AI Hub model: AI Hub publishes curated GGUFs (`models/supported.mdx:10`), and GenieX runs it directly through its `llama_cpp` runtime (llama.cpp's Hexagon backend on the HTP). Any Unsloth GGUF has that path. `qairt` bundles are a second, optional route. |
| `hybrid` is "the fast path", so it's the default | GenieX's own default is `npu` (`platforms.mdx:95`). `npu-ask` now defaults to `npu`. |
| "Android GenieX only ships the bench tool, no HTTP server", so the browser runs on the CPU | The package ships the full SDK: `lib/libgeniex.so` with a C API (46 exported functions). `npu-serve` is built on it. |
| v0.7.1 is slow (2.7 tok/s) because Termux can't read `/vendor/dsp/` | Didn't reproduce on 2026-10-02 (bench: decode 15.9, server: ~17). `0x80000414` (dspqueue method 3) is still logged but is harmless. Cause of the old number unknown. |
| (process) | The fork wasn't synced before installing. It was already level with upstream (`073fcde2`), but the rule is to sync first. |

## 4. What was built 2026-10-02
- `~/tools/geniex-serve/shim.c`: a small C adapter over `libgeniex.so` (`geniex_init`, `geniex_resolve_device`, `geniex_llm_create`, `geniex_llm_apply_chat_template`, `geniex_llm_generate`). Each request is stateless (KV cache reset), and tokens stream through a callback.
- `~/tools/geniex-serve/server.py`: Python stdlib HTTP server, OpenAI-compatible, one model loaded once, one request at a time.
- Headers pinned per ABI: `geniex.h` (v0.3.14 era, fork commit `d8852590`, 2026-06-25) and `geniex-v0.7.1.h` (tag `v0.7.1`).
- Built shims: `libgeniex_shim.so` (v0.3.14) and `libgeniex_shim-v0.7.1.so` (`-DGX071`).
- `~/bin/npu-serve`: start, stop or status. Defaults to v0.7.1 and `npu`; `GENIEX=v0.3.14` for the old build.
- Source copies: aesop-xi `deploy/phone/geniex-serve/` and `deploy/phone/bin/` (branch `feat/h1-stop-gate`).

## 5. How it works
```
client (curl / OmniRoute / scripts)
  → server.py :18181  (OpenAI JSON ↔ C strings, ctypes)
  → libgeniex_shim-v0.7.1.so
  → libgeniex.so  (GenieX v0.7.1, plugin llama_cpp)
  → libggml-hexagon + libggml-htp-v79.so
  → FastRPC (/vendor/lib64/libcdsprpc.so)
  → HTP0 (Hexagon v79 NPU), burst power mode
```
- Environment set by `npu-serve`: `LD_LIBRARY_PATH=$G/lib:$G/lib/llama_cpp:$G/lib/qairt:/vendor/lib64`, `GENIEX_PLUGIN_PATH=$G/lib`, `GENIEX_SHIM=<shim>`, `GGML_HEX_VERBOSE=1`.
- Device resolution: `geniex_resolve_device(plugin=llama_cpp, mode=npu, ngl=999)` → `HTP0`, all layers.
- **v0.7.1 gotcha:** `ModelConfig.power_mode` left at zero means LOW_POWER_SAVER. The shim sets `GENIEX_POWER_MODE_BURST`.

## 6. Doing this going forward
**Use it**
```
npu-serve                     # start (Qwen 3.5 2B, npu)
npu-serve <model.gguf>        # another model; Q4_0 is best on the HTP
npu-serve status | stop
curl -s 127.0.0.1:18181/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"hi"}],"max_tokens":50}'
```
**Move to a new GenieX release**
1. `gh repo sync c10vis-poem/GenieX`, then `git pull` in `~/repos/GenieX` (the code). Releases are not copied to forks.
2. `gh release download <tag> -R qualcomm/GenieX -p 'geniex-bench-android-arm64-<tag>.tar.gz*'`, then check it with `sha256sum -c`.
3. Unpack it to `~/tools/geniex-bench-android-arm64-<tag>`, alongside the old one.
4. Get that tag's header: `gh api "repos/qualcomm/GenieX/contents/sdk/include/geniex.h?ref=<tag>" -q .content | base64 -d > ~/tools/geniex-serve/geniex-<tag>.h`
5. Diff the structs used by `shim.c` (`ModelConfig`, `LlmCreateInput`, `LlmChatMessage`, `GenerationConfig`, `SamplerConfig`, `ProfileData`) against the current header. Add an `#ifdef` for any change.
6. Build: `clang -O2 -shared -fPIC -D<FLAG> -o libgeniex_shim-<tag>.so shim.c -I. -L<lib> -lgeniex -Wl,-rpath,<lib>`
7. Add the tag to `npu-serve`, start it, and check the log for `Hexagon Arch version v79` and `HTP0 new session`. Measure decode against the previous build before switching the default.

**Rule:** never run a shim built against one GenieX version with another version's `libgeniex.so`. The struct layouts differ, and a mismatch corrupts the data passed in or crashes.

## 7. Open items
1. **Speed gap:** ~17 tok/s decode vs ~45–50 expected. Next: measure with other apps closed, then as the ADB shell user (RESUME's wireless-debugging test).
2. Point `npu-ask` at `npu-serve` (it still loads the v0.3.14 bench tool for each call).
3. Have OmniRoute and the wiki tools use `http://127.0.0.1:18181/v1`.
4. Qwen 3.5 9B on the NPU (multi-session split).
5. Vision (`geniex_vlm_*`) for image-capable models.
