# RESUME: Snapdragon 8 Elite Local AI Stack — Next Session

**Date:** 2026-07-25  
**Status:** All PRs passing CI. Repos clean. Ready for on-device deployment.  
**Session Context:** User explicitly removed all permission prompts — you have full access across all repos, GitHub, Google Drive, MCP. **Stop asking for permission.** Keep repos strictly separated.

---

## What's Done ✓

### 1. Core Infrastructure Pushed (3 repos, all PRs passing CI)

**aesop** (PR#2: bridge daemon + daemons)
- `deploy/phone/bridge/aesopd.py` — RFC 6455 WebSocket bridge (pure stdlib, 500 lines)
  - Routes `llm.generate[ggml]` → `http://127.0.0.1:8081/v1/chat/completions` (llama-server SSE)
  - Routes `llm.generate[npu]` → `http://127.0.0.1:8080/api/v1/generate` (ort_engine SSE)
  - Proxies TTS via proot Kokoro, serves plane health
- `deploy/phone/daemons/install-daemons.sh` — termux-services setup (creates runit services)
- `deploy/phone/daemons/llamad-run` — llama-server runit wrapper with model discovery (never downloads)
- `protocol/bridge-protocol.md` — Complete wire spec (v1), port map, message types, error model
- `deploy/phone/boot.sh` — **CRITICAL FIX:** removed 8080 binding collision, now checks supervised daemons first

**Port Discipline (locked in):**
- 8080 = ort_engine (app/Horizons, NPU on Hexagon HTP v79)
- 8081 = llamad (Termux/llama.cpp, GGML plane, Gemma 4 12B IT QAT)
- 8091 = media daemon (app, STT/TTS, Moonshine/Kokoro)
- 8765 = aesopd (Termux, WebSocket control/event plane)

**novus-agenti** (PR#26: model configs + Kotlin clients)
- `models/qwen-9b-q4_0/geniex-config.yaml` — Agent 2 (deep thinker, 5.74GB, on-demand)
- `models/qwen-2b-compiled/geniex-config.yaml` — Agent 1 (router, 1.6GB, always-hot)
- `models/gemma-12b-it-qat/geniex-config.yaml` — Fallback single-agent (current MVP, 9.36GB)
- `models/{qwen-9b,qwen-2b,gemma-12b}/hf-download-link.txt` — wget-friendly URLs
- `runtimes/geniex-orchestration.md` — 540-line technical walkthrough (handoff logic, MEMO queries, HTP context, fallback chain)
- `docs/MODELS-README.md` — 400+ lines, port discipline, architecture, testing
- `docs/model-routing-guide.md` — Decision tree (which agent handles what), complexity heuristics, system prompts
- `scripts/download-models.sh` — Pure bash/wget bootstrap (no pip, finds models locally, falls back to download)
- `horizons/src/main/java/com/horizons/core/llm/TermuxLlmRuntime.kt` — LlmRuntime impl (streams from llamad)
- `horizons/src/main/java/com/horizons/bridge/AesopBridgeClient.kt` — OkHttp3 WebSocket client (ws://127.0.0.1:8765)

**openwiki** (PR#3: llm-wiki-termux-setup.md rewrite)
- Complete rewrite of `openwiki/operations/llm-wiki-termux-setup.md` (443 insertions, 82 deletions)
  - Part 1: GenieX unified stack (no separate llama.cpp + QAIRT, prevents HTP thrashing)
  - Part 2: MEMO layer (JSON fast-lookup for Agent 1)
  - Part 3: Voice pipeline (VAD→STT→LLM→TTS via sherpa-onnx)
  - Part 4: OpenWiki shell agent coordinator loop
  - Part 5: Device persistence (boot.sh wake-lock, tmux auto-launch)
  - Part 6: GGUF quantization (Q4_0 optimal)
  - Part 7: NPU optimization & debugging
  - Part 8: Testing orchestration (curl/jq)
  - Part 9: Tuning & fallback strategy
- CI fix: `npx prettier --write openwiki/operations/llm-wiki-termux-setup.md` + recommit ✓

---

## Termux Setup Bash Commands (On-Device)

Run these in Termux when at phone:

```bash
# 1. Install termux-services
pkg install termux-services

# 2. Restart Termux app (kill from drawer, relaunch)

# 3. Install daemon supervisor
bash ~/aesop/deploy/phone/daemons/install-daemons.sh

# 4. Verify daemons started (supervised, auto-restart on reboot)
sv status llamad aesopd
# Expected: both "run: llamad: (pid XXXXX) NNNs" and "run: aesopd: (pid XXXXX) NNNs"

# 5. Tail llamad logs if needed
tail -f /var/log/llamad/current

# 6. Manually start/stop if testing
sv up llamad aesopd     # bring up
sv down llamad aesopd   # bring down
sv restart llamad       # restart one

# 7. Check HTP reachability from app (Kotlin will probe this)
curl -s http://127.0.0.1:8081/health | jq .
# If curl not installed: pkg install curl
```

### Phase 2: Verify Bridge Connectivity (5 min)

**From browser dev console or via netcat:**
```bash
# Test llama-server health (GGML plane)
curl -s http://127.0.0.1:8081/health | jq .

# Test bridge daemon is listening
curl -i http://127.0.0.1:8765  # Should upgrade to WebSocket

# OR use websocat (if available): websocat ws://127.0.0.1:8765
# Send: {"type":"hello","role":"ui"}
# Expect: {"type":"hello.ack","server":"aesopd","version":1}
```

### Phase 3: Test Bridge from App (Horizons)

- Horizons app connects `AesopBridgeClient` to `ws://127.0.0.1:8765`
- Sends initial `hello` frame
- Calls `requestStatus()` to probe planes
- Try `generate(prompt="Hello", backend="ggml")` to stream from Gemma 12B via llama-server
- Fallback: if GGML down, switch `backend="npu"` to use app's ort_engine

---

## Key Architecture Notes (No Changes Needed)

### Why Gemma 4 12B IT QAT (not E4B)?
- **12B IT QAT** = GGUF format, runs on llama-server in Termux via llamad daemon
  - Termux cannot reach HTP (DSP is app-context only, Termux is sandboxed from vendor libs)
  - Routes: llama.cpp → GGML → CPU/Adreno in Termux sandbox (always works, fallback rung)
- **E4B** = pre-compiled GENIE/QNN context for HTP v79, runs in app (ort_engine on 8080)
  - App context CAN reach HTP; aesopd bridges Termux to app's NPU daemon for escalation
  - This is the Kotlin hook — Horizons accesses E4B via ort_engine, not via Termux

### Why Termux Daemon Supervision?
- Device reboots daily (Android low-RAM killer)
- termux-services (runit) auto-restarts llamad + aesopd with svlogd logging
- No manual intervention needed after boot.sh installs daemons

### Why Bridge Over HTTP?
- Android sandboxes filesystems but shares loopback (127.0.0.1) across all apps
- **Termux cannot reach HTP** (DSP vendor libs + SELinux boundary)
  - Termux llamad (llama-server) handles GGML via CPU/Adreno only
  - aesopd in Termux routes escalation requests to the app
- **App (Horizons) CAN reach HTP** (ort_engine daemon in app context has vendor lib access)
  - ort_engine listens on 8080, serves GENIE/QNN compiled models (E4B, Qwen E4B, etc.)
- Bridge conspires both planes: Termux talks HTTP to aesopd, aesopd talks HTTP back to app's ort_engine on 8080
  - UI (Kotlin) sees unified fallback: try HTP first (via app), fall back to GGML (Termux) if needed

### Memory Unified, Not Separate VRAM
- Snapdragon 8 Elite = 16GB LPDDR5X shared by CPU/GPU/NPU
- RAM Boost = swap to UFS storage (20× slower), max recommended 8GB
- Keep two Chromium engines = 800MB+ overhead each → consolidate to Soul (daily) + Brave Beta (YouTube Music/PWAs only)

---

## No Further Action Needed (Session Wrap-Up)

- ✓ All repos clean, branches up-to-date
- ✓ All PRs passing CI
- ✓ No uncommitted changes
- ✓ No loose ends (models pre-quantized, no quantization work needed)
- ✓ termux-helper skill updated with full GenieX/MEMO/voice guidance (not re-executed)
- ✓ Browser optimization discussed (consolidate to Soul + Brave Beta if desired)
- ✓ PR monitoring scheduled: check-in every ~1 hour until all merged

---

## Git Branches (All Locked to Designated Branch)

- **c10vis-poem/aesop** → `claude/wiki-quinn-npu-local-m1crql`
- **c10vis-poem/openwiki** → `claude/wiki-quinn-npu-local-m1crql`
- **c10vis-poem/novus-agenti** → `claude/wiki-quinn-npu-local-m1crql`
- **c10vis-poem/graphify** → `claude/wiki-quinn-npu-local-m1crql` (no changes this session)
- **c10vis-poem/obsidian-skills** → `claude/wiki-quinn-npu-local-m1crql` (no changes this session)
- **c10vis-poem/notebooklm-py** → `claude/wiki-quinn-npu-local-m1crql` (no changes this session)
- **c10vis-poem/reasoning-bank** → `claude/wiki-quinn-npu-local-m1crql` (no changes this session)

**All development happens on these branches. Never push to main/master without explicit permission.**

---

## Resume Script for Next Session

**Copy-paste this into the next session's first message:**

```
Resume from previous session (2026-07-25). Three PRs pushed and passing CI:
1. c10vis-poem/aesop#2 — bridge daemon + supervised daemons installed
2. c10vis-poem/novus-agenti#26 — model configs + Kotlin bridge clients
3. c10vis-poem/openwiki#3 — llm-wiki-termux-setup.md rewrite + CI fix

All repos clean. Ready for on-device deployment:
- Run: pkg install termux-services; restart Termux; bash ~/aesop/deploy/phone/daemons/install-daemons.sh
- Verify: sv status llamad aesopd
- Test: curl http://127.0.0.1:8081/health && websocat ws://127.0.0.1:8765

Full context: see RESUME_NEXT_SESSION.md in scratchpad.
```

---

## Session Economics

- **Tokens used this session:** ~400k (major infrastructure push)
- **Recommendation for next session:** Monitor PR activity, fix any CI failures, prepare for on-device testing
- **Timeline:** Bridge ready to test as soon as daemons installed on device

---

**End of housekeeping. All systems ready for resume.**
