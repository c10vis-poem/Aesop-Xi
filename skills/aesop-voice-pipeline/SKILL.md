---
name: aesop-voice-pipeline
description: Real-time on-device voice engine (mic -> VAD -> STT -> TTS -> speaker) for this Moto Razr, plus NPU/STT benchmark tools recovered from ~/downloads. Use for anything involving live voice interaction, Gemma-on-NPU benchmarking, or whisper.cpp/Parakeet testing. Companion to android-termux-operator, which owns the general device-operator workflow and safety rules — load that too for approval-card requirements.
---

# AESOP Voice Pipeline

Confirmed working end-to-end 2026-08-28/29 on this device after fixing two real bugs
that had blocked it since the underlying code was written. Follow
`android-termux-operator`'s approval-card workflow for anything here that installs,
downloads, or changes device state — this skill covers what to run, not whether to ask
first.

## What's here

Three tested tools in `scripts/`:

- **`run_voice_loop.sh`** — the actual real-time voice engine. Fixed replacement for
  `~/repos/Aesop-Xi/voice-engine/scripts/run_live.sh`, whose own PulseAudio socket
  discovery never matches a plainly-started daemon. Bakes in both audio-bridge fixes
  automatically (idempotent — safe to re-run).
  - `run_voice_loop.sh --demo` — TTS -> speaker -> STT self-test, no mic. Confirmed:
    generates a sentence, plays it, transcribes it back correctly.
  - `run_voice_loop.sh` — live mic loop. Not yet manually tested with a real spoken
    utterance end-to-end; confirm this still holds before trusting it blind.

- **`setup_geniex_bench.sh`** — extracts and validates GenieX's NPU benchmark tool
  (`~/downloads/geniex-bench-android-arm64-v0.3.14.tar.gz`, previously unused).
  Native Android/bionic binary, no proot needed. Installs to `~/tools/geniex-bench`.
  Confirmed working: `--help` prints full usage. Can benchmark a local `.gguf` file
  or a `org/repo[:quant]` model-manager id against `--device npu` directly — this is
  the tool to point at a Gemma GGUF for a real NPU benchmark, not a guess.

- **`setup_whisper_parakeet.sh`** — extracts and validates the whisper.cpp + Parakeet
  toolkit (`~/downloads/whisper-bin-ubuntu-arm64.tar.gz`, previously unused). glibc
  Linux binary — runs inside the Debian proot only, same reason sherpa-onnx does.
  Installs to `~/tools/whisper-parakeet`. Confirmed working: `whisper-server --help`
  runs inside `proot-distro login debian` with `LD_LIBRARY_PATH` set to the install
  dir. Also includes Parakeet CLI/quantize/test binaries.

## Known bugs, already fixed — do not re-diagnose

**Moonshine STT has a hard ~10 second input ceiling.** Bisected precisely on this
device: 9.5s of real speech transcribes correctly, 10.0s returns silently empty, no
error. This is a limitation of the specific quantized export
(`sherpa-onnx-moonshine-base-en-int8`), not Moonshine generally — Moonshine v2
(`sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27`) uses sliding-window streaming
attention specifically to avoid this and is the fix if it recurs. The offline engine
in `~/bin/vv` has no VAD auto-stop wired in (records until manual stop, 120s cap) —
`~/repos/Aesop-Xi/deploy/phone/vad_monitor.py` (Silero VAD tail-mode) was built to solve
this and was never wired in; its dependency (`onnxruntime`) was also never installed
in `/root/venv`.

**PulseAudio/proot audio bridge:** two separate root causes, both fixed inside
`run_voice_loop.sh`.
1. Debian's `portaudio19` package has no native PulseAudio hostapi at all (confirmed
   via `sounddevice.query_hostapis()` — only ALSA/OSS, both reporting zero devices).
   Fix: `/etc/asound.conf` routing ALSA's default device through the pulse ALSA
   plugin (`libasound_module_pcm_pulse.so`, already present via `libasound2-plugins`).
2. Connecting via `pactl`/`sounddevice` from inside the proot over the bind-mounted
   socket fails with `Protocol error` unless SHM is disabled **client-side inside the
   proot**: `/etc/pulse/client.conf` with `enable-shm = no`. The server's
   `--disable-shm` flag alone was not enough once a persistent default-path daemon
   was already running — and killing that daemon is unreliable on this device
   (`pulseaudio -k` fails silently; something respawns a default-path instance
   across kill attempts regardless). Work with whatever's already running rather
   than fighting to restart it.

## Extension points still open (from the original ARCHITECTURE.md)

- The LLM callback in `live_voice_loop.py` is a hardcoded stub
  (`response = f"You said: {text}"`) — wiring in a real model (Gemma via llama.cpp,
  or `geniex-bench`'s runtime) is the next step for a real conversational loop, not
  yet done.
- No HTTP/WebSocket server exists yet for remote invocation (e.g. from a DroidDesk
  browser on the tablet) — `ARCHITECTURE.md` already anticipated this
  ("adding one, e.g. Flask/FastAPI wrapping VoiceEngine, would enable remote
  invocation"), still unbuilt.

## Reference

`references/htp-backend-mismatch.md` — why `htp_backend_ext_config.json` (found in
`~/downloads`) can't be reused as-is for Gemma without regenerating it.

## Where This Lives

Canonical copy: `aesop-xi/skills/aesop-voice-pipeline/` (version controlled), same
convention as `termux-helper`. The `~/.claude/skills/aesop-voice-pipeline/` copy is
a **local working copy, not the source of truth**: on this phone (a persistent
device) it just silently drifts out of sync with the repo if edited without
committing; on a disposable cloud sandbox it is wiped outright when the container
is reclaimed. Either way, other devices/sessions never see local-only edits. When
updating this skill, commit to the repo.
