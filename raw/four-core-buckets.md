# Four Core Buckets — canonical repository blueprint

The ecosystem has evolved through multiple naming conventions and target iterations — ranging from early terminal-native sandboxes (AESOP, Termux CLI Stack) to native on-device hardware engines (Novus-Agenti, NovA-Claw, N0.V4, and the upgraded Horizons Workbench UI).

The canonical repository blueprint requires sorting everything into Four Core Buckets to prevent engineering agents from drifting into old contexts or hallucinating stale runtime targets.

## Tier 1: The Cold Archive & Source References (/raw_sources/)

Heavy, static background documents, technical metrics, and community tutorials that the model should use strictly as read-only reference data — never as active working rules.

- **Stanford AI Index & General Trends**: Artificial Intelligence Index Report | Stanford HAI (industry benchmark data bank)
- **External Technical / Framework Discoveries**: MEMO (Modular Framework for Training a Dedicated Memory Model), Together AI OSCAR (2-bit attention-aware KV cache optimization spec), NVIDIA Polar (gateway rollout framework for token-faithful GRPO training loops), GitAgent, OpenAI Symphony, CopilotKit, GitHub Spec-Kit, OmniVoice Studio (Tauri/FastAPI local alternative reference stack), Hexo Labs SIA (self-improving agent scaffold loops)
- **Qualcomm / Hardware Specific Specs**: qualcomm/Phi-4-Mini-Instruct, qualcomm/Qwen3.5-0.8B, unsloth/Qwen3.5-9B-GGUF, Gemma-4-E4B-it, qualcomm/LiteHRNet, qualcomm/PiperTTS-DE, Liquid AI LFM2.5-8B-A1B, "hybridized agentic on device neuro mesh" (8.2mb pdf)
- **Keyboard & Input Utilities**: FUTO Keyboard, Voice Input Models

## Tier 2: Core Architecture Vault (/master_wiki/)

The single source of truth for design constraints, structural layouts, and evolution reports mapping out the native system topology.

- **Native Android (Kotlin/Compose) Next-Gen Workbenches**: `HORIZONS_state_and_corrections_MASTER.md` (canonical state document — structural panel layouts, model layer bindings, credential list rewrite), `ARCHITECTURE_REVIEW_v3_amendment.md` (Cloud Failover Ladder vs. VLM Context Dispatcher), The Horizons Workbench guide, Four Rooms & Seven-Tile Modular Architecture spec, The Horizons Workflow (Storage to Switch), `HORIZONS_UI_SPEC_v3.md`, `N0_V4_ARCHITECTURE_v3.md`, Agentic Neural Mesh master architecture/evolution report
- **Legacy / Interim Sandbox Ecosystem Templates (contextual reference only)**: `TERMUX_CLI_STACK.md`, `Copy of SOTU-2026-07-27.md`, `deploy_T3-BRINGUP.md` (Jetson Orin Nano Super + Rubik Pi 3 over Tailscale)

## Tier 3: The Almanac & Skill Definitions (/inference_skills/)

Line-delimited facts, structured JSONL logs, terminal execution setups, and open `SKILL.md` plugin files used to instantly direct local engines.

- **Active Agent Tool Routing Rules**: `horizons-wiki-SKILL.md`, wiki-folder/frontmatter operational instructions, `claude-skills.md`
- **Terminal Environment & API Wiring Recipes**: `GENIEX-DAEMON-PLAN.md` (standalone geniex serve, port 18181), UNIX socket protocol / zero-copy IPC blueprints, `llm-wiki-termux-setup-full-notes.md` / `llm-wiki-termux-setup-urls.txt`

## Tier 4: Session Execution & Hygiene Logs (/automation_scripts/)

Active working tracks, debugging sequences, failure logs, and step-by-step master checklists used to eliminate sessional drift.

- **Current Iteration Logs**: `BUILD-ACTION-PLAN.md` (Repo vs. Device partitioning), `FAILURE_LOG_SESSION_20260527.md` / `weekly_audit_prompt.md` (failure-frequency tracker for specification drift / tool error loops), `NeuroOmni_agy_build_pack.md` (milestone execution checkpoints)

## Step-by-Step Execution for Unified Analysis

To prevent context corruption, do not load heavy references simultaneously with the active target code:

1. **Lock the Base Pool** — use `HORIZONS_state_and_corrections_MASTER.md` + `ARCHITECTURE_REVIEW_v3_amendment.md` as the architectural anchor.
2. **Evaluate Path Congruence** — use `BUILD-ACTION-PLAN.md` to verify file alterations stay distinct across active sub-sessions.
3. **Run the Audit Matrix** — filter incoming tracking data using the failure categories in `weekly_audit_prompt.md` before generating patches.
