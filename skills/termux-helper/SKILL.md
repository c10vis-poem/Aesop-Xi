---
name: termux-helper
description: "Termux on-device AI stack for Snapdragon 8 Elite. Use when working with Termux on Android: the llamad GGML plane (llama-server, Gemma 4 12B Q4_0, port 8081), the aesopd WebSocket bridge to the Horizons app (port 8765), termux-services daemon supervision, wake-lock persistence, and voice pipeline wiring. Also standard Termux operations: package management, $PREFIX paths, storage access, background services. Read Part 2 before any NPU/Hexagon work: it covers the GenieX GGUF→libggml-htp→HTP path, the HTP0/HTP1 weight split, and how to test NPU reach before claiming it."
---

# Termux Helper — On-Device AI Stack, Snapdragon 8 Elite

## Part 1: Termux Core

### 1.1 Packages

- `pkg install <pkg>`, never `apt-get`. Run `pkg up` first when dependencies fail.
- Build chain: `pkg install build-essential clang lld cmake`
- Python: `pkg install python python-dev python-pip`
- Net/tools: `pkg install openssh curl wget git jq tmux`

### 1.2 Paths

`$PREFIX` = `/data/data/com.termux/files/usr`. Binaries live there, not `/usr/bin`.

- Shebang: `#!/data/data/com.termux/files/usr/bin/bash`
- Convert foreign scripts: `termux-fix-shebang <script>`
- Never hardcode `/bin/bash`, `/usr/bin`, `/etc` — expand `$PREFIX`.

### 1.2a Commands for the operator to run — NEVER paste one-liners

The operator's shell is **zsh**. Pasted one-liners fail every time (history
confirmed across many sessions):

- `!` anywhere — including `#!` shebangs inside `printf`/`echo` — triggers zsh
  history expansion: `event not found`.
- Long lines wrap on the phone keyboard/paste and split into broken commands,
  leaving the terminal stuck at `quote>` / `dquote>` (fix: Ctrl+C).

Rule: anything longer than one short command goes in a **script file** (Write
it to `~/storage/shared/Documents/NovAExorpus/Scripts/`), and the operator runs
`sh <path>`. Never hand over a command containing `!`, heredocs, or nested quotes.

### 1.2b Node native builds (npm/pnpm) on Termux

- `/usr/bin/env` doesn't exist: global CLIs with `#!/usr/bin/env node` (e.g.
  `pnpm`) fail with "bad interpreter". Run via `node <path>/pnpm.mjs`, or a
  `$PREFIX/bin/sh` shim on PATH; after `npm link`, `termux-fix-shebang` the bin.
- `node-gyp` isn't on PATH: shim to npm's bundled
  `$PREFIX/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js` and set
  `GYP_DEFINES="android_ndk_path=''"`.
- Prebuilt native addons almost never ship `android-arm64`; expect a source
  build or a missing binding. Read the package before guessing.
- Termux clang defaults to API 24, so newer libc functions (`statx()`, etc.)
  are undeclared → "invalid operands" / implicit-declaration errors. Build with
  `CFLAGS="-target aarch64-linux-android30" CXXFLAGS="-target aarch64-linux-android30"`
  (device is API 36). Operator-supplied fix; verified on koffi 3.1.1.
  `pnpm rebuild <pkg>` may silently skip — run the package's own `install`
  script from its directory instead.

### 1.3 Storage

- One-time grant: `termux-setup-storage`
- Shared storage: `~/storage/shared/` → `/storage/emulated/0/`
- Downloads: `~/storage/downloads/` — where sideloaded GGUFs usually land.

### 1.4 When something needs glibc, not bionic (proot-Debian)

Termux is Android/bionic. A lot of upstream packages (Playwright, `libsql`,
prebuilt tree-sitter language wheels, and often a project's own native
Postgres extensions) only ship glibc Linux builds and fail with a `dlopen`
symbol error or "no wheel for this platform" — not a Termux bug, a real
platform gap. `proot-distro login debian` (installed via `pkg install
proot-distro && proot-distro install debian`) gives a genuine glibc aarch64
userland already on this device; install/build the glibc-only piece there
instead of fighting it in bare Termux. Two gotchas:

- **`proot-distro login` runs with `--kill-on-exit`.** A `nohup`/`disown`
  *inside* the login shell does not survive — the whole process tree dies the
  instant the invoking command returns. For a persistent background process,
  background the *outer* `proot-distro login debian -- ...` command itself.
- **Termux's own home is visible inside proot at the same absolute path**
  (`/data/data/com.termux/files/home/...`), but `~` inside proot resolves to
  `/root`, not that path — always use the full path, never `~`, when
  referencing a Termux-side file from inside a proot shell.

Prefer Termux's own native build over proot when one already exists and is
better — e.g. Termux ships Postgres natively (`pkg install postgresql`,
already has `initdb`/`pg_ctl`/`pg_config`+a build toolchain); building
`pgvector` from source against it is faster than running a second Postgres
inside proot, but needs `MKDIR_P`/`INSTALL` overridden to Termux's real paths
(its own `pg_config` bakes in nonexistent `/usr/bin/mkdir` / `/usr/bin/install`)
and `SHLIB_LINK="-lm"` added explicitly (bionic doesn't fold libm into libc
the way glibc does).

## Part 2: What Termux Can and Cannot Reach

**This is the section that matters. Get it wrong and you waste a night.**

Android sandboxes filesystems but **shares loopback**. Every process on the
device sees the same `127.0.0.1`. That single fact is what the whole stack
is built on.

**Read `~/.claude/NPU-ON-DEVICE.md` first: the settled facts, the exact command,
and the objections never to raise.** Summary below.

**The NPU (Hexagon HTP v79) has two routes. Both run on the phone itself.**

1. **GGUF on the NPU via GenieX (operator's Qualcomm-documented path).** A
   plain GGUF runs through the GenieX runtime: llama.cpp/GGML with
   `libggml-htp` → FastRPC (`libcdsprpc.so`, readable from Termux at
   `/vendor/lib64`) → HTP. It lands fully on the NPU, at the same GenieX
   endpoint as a precompiled QAIRT model. No QAI Hub compile is needed.
   - The libs are in `~/tools/geniex-bench/lib`: `libggml-hexagon.so`,
     `libggml-htp-v79.so`, and `qairt/htp-files/libQnnHtpV79*.so`.
   - **Weight split:** each FastRPC domain addresses about 3.5 GB. A model of
     3.2 GB or less runs on `HTP0`. Up to 6.5 GB splits across `HTP0,HTP1`
     (e.g. layers 0–24 / 25–48: `D=HTP0,HTP1 … --n-gpu-layers 49`). Bigger
     models need three domains or CPU offload.
   - GenieX modes are `--device hybrid` (the default), `npu`, `gpu` and `cpu`.
   - Docs: `~/repos/aesop-xi/HTP/HTP-Memory-Architecture-and-runtime-splitting (1).txt`
     and `~/repos/NovAExorpus/HTP/`. They come from the Qualcomm docs on the
     device: vault `QAIRT-QNN/` and `02_wiki_md/vendors/qualcomm/`.
2. **Precompiled QAIRT/GENIE contexts** (QAI Hub or LiteRT `.bin`), served by
   GenieX or by the app's `ort_engine`. An example on the device:
   `Documents/Models/qwen3_vl_4b_instruct-geniex_qairt-w4a16-qualcomm_snapdragon_8_elite (2).zip`.

Before claiming the NPU is or isn't reachable from Termux, run GenieX with
`--device npu` on a small GGUF and check the output for HTP execution versus
CPU fallback. Read the operator's Qualcomm docs before reasoning from memory.

The planned port layout:

| Plane | Owner | Port | Runs |
|-------|-------|------|------|
| NPU / HTP v79 | **App** (Hyperion-OXiLm) or GenieX | 8080 (app) / 18181 (`geniex serve`) | `ort_engine`, GENIE ctx binaries, GGUF via libggml-htp |
| GGML | **Termux** | 8081 | `llamad` → llama-server, Gemma 4 12B Q4_0 |
| Media (STT/TTS) | **App** | 8091 | Moonshine / Kokoro |
| Control / events | **Termux** | 8765 | `aesopd` WebSocket bridge |

**Port discipline:** Termux must never bind 8080 or 8091. The app must never
bind 8081 or 8765. A collision here is silent and miserable to debug.

Clients reach any engine over loopback HTTP: the app (8080), `geniex serve`
(18181) or llama-server (8081). The bridge (8765) routes between them.

## Part 3: The GGML Plane (`llamad`)

llama-server on 8081, supervised by runit. Backend ladder inside Termux is
Adreno 830 via OpenCL if the build carries it, CPU big cores otherwise.

**On the CPU/GPU plane, prefer Q4_0 quants.** llama.cpp runtime-repacks Q4_0
into the i8mm/dotprod aarch64 layout on this SoC; K-quants (Q4_K_XL etc.)
don't get that, so when both are on disk, pick Q4_0. Which model is
"strongest" (e.g. Gemma 4 12B QAT vs Qwen 3.5 9B) is an open question for the
operator. Don't rank models without a benchmark. Whatever runs on the NPU
(above) beats this plane on speed.

**Models are already on device.** Discover, never download. Never quantize —
these are pre-quantized and plug-and-play. If asked about quantization,
the answer is almost always "not needed, route it correctly instead."

Memory posture that survives a phone that bloats:

- Use mmap (the default). File-backed pages are reclaimable, so pressure
  evicts pages instead of the low-memory killer taking the whole daemon.
  `--no-mmap` turns a slowdown into a death.
- `-fa -ctk q8_0 -ctv q8_0` roughly halves KV cache at 4k ctx.
- `-t 6` — big cores only; more threads just fight the LITTLE cluster.
- Resident cost is ~7GB model + ~0.5-1GB cache while up. Every weight is
  touched per token, so there is no partial-load trick. `sv down llamad`
  returns all of it instantly.

## Part 4: The Bridge (`aesopd`)

Pure-stdlib RFC 6455 WebSocket server on 8765. One JSON object per text
frame; `id` correlates requests to streamed replies.

Routing:

- `llm.generate` with `backend: "ggml"` → `POST 127.0.0.1:8081/v1/chat/completions`
- `llm.generate` with `backend: "npu"` → `POST 127.0.0.1:8080/api/v1/generate`

llama-server applies the **GGUF's own chat template** server-side. Never
hand-roll Gemma turn markers on the client.

The data planes are independent of the control plane — killing `aesopd`
never interrupts a generation already running over direct HTTP.

Full wire spec: `aesop-xi/protocol/bridge-protocol.md`.

## Part 5: Persistence

The device reboots and the low-memory killer is aggressive, so supervision
is not optional.

```bash
pkg install termux-services      # then fully restart Termux
bash ~/repos/aesop-xi/deploy/phone/daemons/install-daemons.sh
sv status llamad aesopd
```

- `sv up|down|restart <svc>` — manual control
- `tail -f $PREFIX/var/log/llamad/current` — svlogd output
- `termux-wake-lock` before long runs; `termux-wake-unlock` after
- tmux is the fallback when services aren't installed, not the primary path

## Part 6: Debugging

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Port 8081 refused | `llamad` down or no GGUF found | `sv status llamad`, check log for "no .gguf found" |
| Daemon restart loop | Model missing; script exits, runit re-runs | Set `AESOP_MODEL=/path/to/q4_0.gguf` |
| Two processes fighting a port | Termux bound an app-owned port | Re-read the port table in Part 2 |
| Killed mid-generation | LMK under pressure | Confirm mmap is on; close background apps |
| Very slow first token | Pages evicted, re-reading from UFS | Free RAM; this is degraded-not-dead by design |
| Bridge won't connect | `aesopd` down | `sv status aesopd`; direct HTTP to 8081 still works |
| NPU run falls back to CPU | Model too big for one domain, or HTP libs not on the path | Check the size rule (Part 2), use `HTP0,HTP1`, set `LD_LIBRARY_PATH` to the geniex lib dirs |

## Part 7: Where This Lives

Canonical copy: `aesop-xi/skills/termux-helper/SKILL.md` (version controlled).

The local `~/.claude/skills/` copy is a **working copy, not the source of
truth** — not literally ephemeral on this phone (a persistent device, not a
disposable sandbox); it just silently drifts out of sync with the repo if
edited without committing, and other devices/sessions never see local-only
edits. On a disposable cloud sandbox editing this same repo, that local copy
is wiped outright when the container is reclaimed. Either way: when updating
this skill, commit to the repo.
