# NPU on this phone — settled facts (do not re-argue)

Device: Snapdragon 8 Elite (`SM8750`), Hexagon HTP **v79**. The operator has explained this more than 100 times. These are settled. Answer from this file, cite it, and stop raising the objections listed at the bottom.

## The route: plain GGUF → 100% on the NPU, on the phone, no computer
GenieX `llama_cpp` runtime → llama.cpp with Qualcomm's GGML Hexagon backend (`libggml-hexagon` + `libggml-htp-v79`) → FastRPC (`libcdsprpc.so`) → HTP. A plain GGUF runs on the NPU at the same GenieX endpoint as a precompiled QAIRT model.
- `--device npu` (or `compute_unit = "npu"`) pins `HTP0` with **all layers** (`ngl=999` / `nGpuLayers=-1`). That's 100% NPU. (`GenieX/docs/en/get-started/platforms.mdx:95`, `run/android/api-reference.mdx:166-173`, `tutorials/benchmarking.mdx` output `device=npu ngl=999`)
- `hybrid` is the HTP+CPU per-tensor scheduler, which Qualcomm calls "the fast path". (`platforms.mdx:98`)
- Big models split across sessions with `--compute HTP0,HTP1,…` (`run/cli/reference.mdx:76`). Each session addresses about 3.5 GB. llama.cpp can also map weights in and out dynamically on one session (`llama.cpp docs/backend/snapdragon/developer.md`, "Large model handling").
- Second route: `qairt` runs Qualcomm AI Hub precompiled bundles, NPU only, and is the fastest when a bundle exists.

## Run it from Termux (on device)
```
cd ~/tools/geniex-bench
LD_LIBRARY_PATH=lib:lib/llama_cpp GENIEX_PLUGIN_PATH=lib GGML_HEX_VERBOSE=1 \
  bin/geniex-bench --plugin llama_cpp --device npu -m <path.gguf>
```
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
