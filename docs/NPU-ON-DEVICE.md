# NPU on this phone — settled facts (do not re-argue)

Device: Snapdragon 8 Elite (`SM8750`), Hexagon HTP **v79**. The operator has explained this more than 100 times. These are settled. Answer from this file, cite it, and stop raising the objections listed at the bottom.

## The route: plain GGUF → 100% on the NPU, on the phone, no computer
GenieX `llama_cpp` runtime → llama.cpp with Qualcomm's GGML Hexagon backend (`libggml-hexagon` + `libggml-htp-v79`) → FastRPC (`libcdsprpc.so`) → HTP. A plain GGUF runs on the NPU at the same GenieX endpoint as a precompiled QAIRT model.
- `--device npu` (or `compute_unit = "npu"`) pins `HTP0` with **all layers** (`ngl=999` / `nGpuLayers=-1`). That's 100% NPU. (`GenieX/docs/en/get-started/platforms.mdx:95`, `run/android/api-reference.mdx:166-173`, `tutorials/benchmarking.mdx` output `device=npu ngl=999`)
- `hybrid` is the HTP+CPU per-tensor scheduler, which Qualcomm calls "the fast path". (`platforms.mdx:98`)
- Big models split across sessions with `--compute HTP0,HTP1,…` (`run/cli/reference.mdx:76`). Each session addresses about 3.5 GB. llama.cpp can also map weights in and out dynamically on one session (`llama.cpp docs/backend/snapdragon/developer.md`, "Large model handling").
- Second route: `qairt` runs Qualcomm AI Hub precompiled bundles, NPU only, and is the fastest when a bundle exists.

## Run it from Termux (on device) — VERIFIED WORKING 2026-10-01
One-time setup. FastRPC looks for the skel in `lib/` and `lib/cdsp/` only (logcat: `apps_std_fopen … lib/./libggml-htp-v79.so`):
```
ln -sf llama_cpp/libggml-htp-v79.so ~/tools/geniex-bench/lib/libggml-htp-v79.so
```
Run (`/vendor/lib64` is needed for `libOpenCL.so`, or the plugin fails to load):
```
cd ~/tools/geniex-bench
LD_LIBRARY_PATH=lib:lib/llama_cpp:/vendor/lib64 GENIEX_PLUGIN_PATH=lib GGML_HEX_VERBOSE=1 \
  bin/geniex-bench --plugin llama_cpp --device npu -m <path.gguf>
```
Result on the QAI Hub Qwen 3.5 2B Q4_0 GGUF (`~/downloads/Qwen3.5-2B-Q4_0.gguf`), with the phone heavily loaded: `[ok] device=npu(id=HTP0) ngl=999 ttft=1678ms prefill=305 tok/s decode=16.5 tok/s` (best 429 / 20). `HTP0 new session … domain-id 3`, `offloaded 25/25 layers`, `HTP0-REPACK 698.7 MiB` (plus `CPU_REPACK 447 MiB`).
If the session fails with `error 0x80000406`, read `logcat -d | grep -i adsprpc`. It names every path FastRPC searched.
**Proof it's on the NPU:** the log shows `Hexagon Arch version v79` and a `libggml-htp-v79.so` session. If those lines are missing, it fell back to the CPU without saying so (`resources/troubleshooting.mdx:103`). If `HTP0` isn't found, the unversioned `libcdsprpc.so` isn't resolving (`troubleshooting.mdx:92`).

## What's on the device
- GenieX bench/runtime: `~/tools/geniex-bench` (bin + lib, including `libggml-hexagon.so`, `libggml-htp-v79.so`, and QNN HTP v79 in `lib/qairt/htp-files`); the v0.3.14 tarball is in the vault at `qairt_/`.
- `libcdsprpc.so`: `/vendor/lib64` (readable from Termux).
- Models, Q4_0 preferred for the HTP: `Documents/Models/` (Qwen 3.5 9B, Qwen 3.5 2B, Gemma 4 12B QAT, E4B, E2B, Granite micro) and `~/downloads`. The AI Hub bundle `qwen3_vl_4b_instruct-geniex_qairt-w4a16-…8_elite (2).zip` is also in `Documents/Models/`.
- Docs: the fork `~/repos/GenieX` (`docs/en/`, `notes/`, kept synced), `~/llama.cpp` (`docs/backend/snapdragon/`; read `origin/master`), and the operator's notes in `~/repos/aesop-xi/HTP/` and `~/repos/NovAExorpus/HTP/`. Full Qualcomm docs are in the vault `QAIRT-QNN/` and `02_wiki_md/vendors/qualcomm/`.
- Google LiteRT / LiteRT-LM (Qualcomm NPU accelerator) docs: vault `Vendor-Registries/GOOGLE _DEV/` (Jul 30). LiteRT is current, not removed.

## Objections that are WRONG — never raise them
- "It needs a computer / ADB / a PC split." → No. It runs on the phone.
- "Termux can't reach the NPU." → Untested claims don't count. Run the command above and read the log.
- "You must compile with QAI Hub first." → Only for the `qairt` route. A GGUF runs directly.
- "The model is too big for the NPU." → Use the multi-session split or dynamic mapping. Check the size before claiming it.
- "GenieX / LiteRT is old or removed." → The operator's information is newer than training data. Read the docs above.

## llama-server on the NPU — status 2026-10-01 (not working yet)
- The prebuilt Snapdragon llama.cpp package in vault `NovAExorpus/llm-wiki/` (Jul 4: `llama-server`, `libggml-hexagon.so`, `libggml-htp-v79.so`; copied to `~/tools/llama-hexagon`) opens the HTP session but fails on the DSP queue: logcat `Error 0x80000414 … libdspqueue_rpc_skel.so`. It falls back to CPU (2.6 tok/s).
- Mixing its llama libs with GenieX's newer ggml/hexagon libs (`~/tools/llama-mixed`) runs at 13.5 tok/s, but the same request with `--device none` gives 13 tok/s, so that's also CPU. Don't claim the NPU without a CPU baseline.
- The working NPU path today is `geniex-bench` (16.5–20 tok/s, logcat clean). Next step: build `llama-server` from GenieX's pinned `third-party/llama.cpp` against GenieX's own ggml libs.
- The Hexagon SDK 6.6.0.0 is on the device: vault `NovAExorpus/llm-wiki/Hexagon_SDK_Linux.zip` (3 GB).

## Benchmarks — Qwen 3.5 2B Q4_0, 256-token real prompt, phone loaded (2026-10-01)
| GenieX | mode | prefill | decode |
|---|---|---|---|
| v0.3.14 | `npu` | 151 tok/s | 16.8 tok/s |
| v0.3.14 | `hybrid` | 177 tok/s | **20.5 tok/s** (best so far) |
| v0.7.1 | `npu` | 98 tok/s | 2.7 tok/s (DSP-queue `0x80000414`; whole model on HTP) |
Target: Qualcomm's v79 numbers are ~51 tok/s (Llama 3.2 1B Q4_0) and ~48 tok/s (Gemma 2 2B Q4_0), so ~40–50 tok/s is expected for a 2B.
Leading hypothesis for the v0.7.1 slowdown: Termux can't read `/vendor/dsp/` (SELinux), so FastRPC falls back to the firmware's built-in shell, and the DSP-queue call fails. Test: run v0.7.1 as the adb shell user over loopback wireless debugging (on the phone, no PC). Qwen 3.5 is a hybrid model (6 attention + 24 recurrent GDN layers); newer llama.cpp adds `GGML_HEXAGON_GDN_SELECT`.
