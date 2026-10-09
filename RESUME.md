# RESUME.md — Session Ledger

## Next session (from 2026-10-08, session 34c3e229)
- Branches `hooks-to-top-level` (hooks moved to `hooks/`; H2 blocking sync, change-log + /ok push, H8 ci-ready, documents-guard merged) and `raw-condensed` ship at wrap-up (workstream 3/4).
- PR #18 (orchestration contract) stays open for the grill; #33 gets closed.
- Fix: `hooks/tests/test-ship-v2.sh` fails 14/18 on main too. H8: compare required check names with real job names.
- Last of workstream 4: rename the repo to `Aesop-Xi` and every hook path that points at `~/repos/Aesop-Xi`.
Full plan, run as parallel subagent workstreams: vault `NovAExorpus/RESUME.md` START HERE.

Repository: `aesop-xi` (orchestration repo)
Last session: 2026-10-02 (phone, Claude Code). Full ledger: `~/.claude/session-work/2026-10-02/SESSION-LOG.md`. Master handoff: vault `RESUME.md`.

## WHAT LANDED (branch `feat/npu-serve-model-switching`, ships at /wrapup)
- `4a0b3a7`, `567d941`: npu-serve model switching (`deploy/phone/geniex-serve/models.json` registry; the request's `model` picks it).
- `34fb58a`: VLM path. Image input for GGUF + mmproj and for QAIRT VLM bundles. All 6 registry models answered an image correctly. InternVL3.5-4B QAIRT decodes at 15.4–17.1 tok/s (AI Hub S25: 16.0–16.4).
- `106a296`: npu-serve start script no longer hangs when piped; waits 240 s for big models.
- `995a7ba`: default model path → `Models/gguf/Qwen3.5-2B-Q4_0.gguf` (the `~/downloads` copy was a byte-identical duplicate, removed).
- `1627b3f`: H1–H7 attached to this repo (`.claude/settings.json` → `deploy/phone/hooks/run-hook.sh`). Tested: stands down where the global copy exists; otherwise the repo copy runs (secret-guard blocked a hook-skip commit).
- Wrap-up docs: CLAUDE.md (hook section), MEMORY.md, PENDING.md, this file.

## STATE
- Server: `npu-serve <name>` → `http://127.0.0.1:18181/v1`. Guide: vault `docs/NPU-SERVE-USER-GUIDE.md`.
- Speeds measured on a clock-capped phone; not trustworthy until the caps are explained (vault `docs/NPU-FINDINGS-2026-10-02.md`).

## NEXT
1. Add InternVL 2B to models.json (the X Elite bundle ran 27.5 tok/s, prefill 1,528 on this v79 phone; compare with the 8 Elite bundle).
2. Tool calls in npu-serve; multiple images per message.
3. NPU restart one model at a time with the operator (vault RESUME START HERE).

## Sources read this session (for this repo)
`deploy/phone/geniex-serve/{shim.c,server.py,models.json}`, `deploy/phone/bin/{npu-serve,npu-ask,ai-web}`, `deploy/phone/hooks/{settings.hooks.json,README.md,stop-gate.sh (head)}`, `.claude/settings.json`, CLAUDE.md (section list + hook grep), MEMORY.md, PENDING.md, the old RESUME.md (first 30 lines). Not read: the rest of CLAUDE.md, `docs/`, `skills/`, `tools/`.
