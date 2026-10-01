# Æsop-Xi: System Arbitration & Policy Governance Specification


**Subsystem Identifier**: `aesop-xi`  
**Core Responsibility**: Tactical Orchestration, Ethical Safety, Priority Arbitration, and Security Clearance Governance  
**Repository Target**: `aesop-xi/`  
**Operational Standard**: Zero-Trust Boundary & Universal 5+1 Locality Standard  


---


## 1. Subsystem Architecture & Operational Invariants


`aesop-xi` (Agentic Execution Split Operations Protocol) functions as the central governance kernel across the federated ecosystem. It arbitrates model execution priorities, manages hardware resource headroom, issues cryptographic execution clearance tokens, and enforces security guardrails over tool invocations.


### Core Governance Invariants
1. **Sensory Immutability**: All original evidentiary inputs and raw assets are strictly read-only. No agent or policy rule may authorize an in-place mutation or deletion of canonical sources.
2. **Explicit Locality of Behavior**: Policies, clearance rules, and arbitration heuristics live directly within `aesop-xi/` and are enforced at the execution boundary.
3. **Fail-Closed Gatekeeping**: If a tool invocation, JSON payload, or runtime parameter violates a schema or fails an assertion, the system defaults to an immediate execution halt (`BLOCKED`).
4. **Deterministic Exit Codes**: All scripts and verification routines supervised by Æsop-Xi must yield deterministic exit codes (`0` for verified success, non-zero `1` or `2` for errors).


---


## 2. Priority Arbitration Logic (`arbitration/arbitration_engine.py`)


The arbitration engine evaluates all proposed execution actions across the tri-tier model hierarchy (0.8B Triage, 9B Reasoning, and Frontier fallback), enforcing clearance gating before any command or tool executes.


### 2.1 ClearanceToken Handshake Protocol
Before any tool execution or database write occurs, the runtime must obtain a `ClearanceToken`:


```json
{
  "token_id": "TKN-EXAMPLE-0001",
  "tool_name": "bash",
  "status": "APPROVED",
  "risk_level": "LOW",
  "priority_rank": 1,
  "caller": "novus-aexenti/executor_bridge",
  "issued_at": "2026-09-07T20:12:00Z",
  "lease_duration_ms": 5000
}
```


* **Clearance Status States**:
  * `APPROVED`: Request passed all guardrails; execution proceeds immediately.
  * `APPROVED_WITH_WARNING`: Minor heuristic discrepancy logged to telemetry; non-critical task proceeds with telemetry audit tag.
  * `BLOCKED`: Direct violation of path boundaries, memory limits, or protected file directives; execution halted immediately.
  * `QUARANTINED`: Malformed syntax, unvetted external scripts, or untrusted payload; quarantined for inspection.


### 2.2 Precedence & Conflict Resolution Matrix
When multiple agents or execution threads compete for resources:
1. **Operator Precedence**: Explicit in-session instructions from the human operator immediately override any autonomous background heuristic.
2. **Safety Invariant Priority**: Rules prohibiting deletions, moves, and overwrites of canonical files supersede performance and task-completion directives.
3. **Asymmetric Concurrency**:
   * Read-only inspection tasks execute concurrently across threads.
   * State-mutating actions (file writes, database commits, socket reconfiguration) require exclusive sequential locks.


---


## 3. Hardware Resource Headroom & Throttling (`arbitration/hardware_throttler.py`)


Designed specifically for Node Alpha (Motorola Razr Ultra 2025 / Snapdragon 8 Elite Hexagon v79 HTP) and Node Beta (Jetson Orin Nano Super):


### 3.1 Memory Protection Floors
* **Mobile Node RAM Ceiling**: 4,800 MB active model footprint ceiling.
* **Low Memory Killer (LMK) Mitigation**:
  * Native daemons run under elevated ADB shell UID 2000 (`oom_score_adj = -950`), completely bypassing standard Android app killing.
  * If total device free RAM drops below 1,500 MB, the throttler forces an immediate SIGTERM on active GGUF contexts via `npu_manager.py` before Android's kernel panics.


### 3.2 Thermal Headroom Tiers
The hardware throttler continuously inspects silicon thermal zones (`/sys/class/thermal/`):


| Thermal Zone | Silicon Temp Range | Orchestration Policy | Permitted Model Backends |
| :--- | :--- | :--- | :--- |
| **Zone 0 (Nominal)** | < 42°C | Full concurrency enabled. High-throughput continuous generation. | 9B Qwen GGUF on NPU/CUDA + 0.8B Triage + Voice Stack |
| **Zone 1 (Warm)** | 42°C – 47°C | Bounded execution. KV-cache context window clamped to 4,096 tokens. Background RAG batch indexing offloaded to Node Beta. | 9B Qwen (throttled) + 0.8B Triage |
| **Zone 2 (Critical)** | > 47°C | Immediate task shedding. 9B executor unloaded from RAM. Concurrency locked to 1. | 0.8B Triage on GenieX only |


---


## 4. Policy Governance & Security Clearance Schemas (`policies/`)


### 4.1 Tool Usage Guardrails (`policies/tool_usage_guardrails.json`)
Defines the strict execution perimeter for worker agents:


```json
{
  "schema_version": "2.0.0",
  "enforcement_mode": "STRICT_FAIL_CLOSED",
  "path_whitelist": [
    "/tmp/*",
    "~/novae-xorpus/*/clean_md/*",
    "~/novae-xorpus/*/tools/*",
    "~/novae-xorpus/*/pending/*",
    "~/novae-xorpus/05_episodic_logs/*"
  ],
  "path_blacklist": [
    "~/novae-xorpus/01_raw_sources/*",
    "~/novae-xorpus/*/raw/*",
    "__NovÆxorpus_LIVING_MASTER_CANON/*",
    "OPERATOR_README.md",
    "OPERATOR_MAP.md",
    "00_DEFINITIVE_MASTER_SPECIFICATION_V3_COMPLETE.md"
  ],
  "disallowed_shell_patterns": [
    "rm -rf *",
    "rm -r *",
    "chmod 777 *",
    "mkfs *",
    "dd if=*",
    "> /dev/sd*",
    ":(){ :|:& };:"
  ],
  "max_execution_duration_sec": 300
}
```


### 4.2 Security Clearance Hierarchy (`policies/security_clearance.yaml`)
Enforces role-based capabilities across the agent fleet:


```yaml
version: "2.0.0"
clearance_tiers:
  TIER_1_TRIAGE:
    roles: ["TriageAgent", "VoiceClassifier"]
    allowed_tools: ["analyze_intent", "read_chunk", "token_estimate"]
    filesystem_access: "READ_ONLY"
    network_access: "LOCAL_LOOPBACK_ONLY"


  TIER_2_EXECUTOR:
    roles: ["CodeExecutor", "SpecCompiler", "TestHarness"]
    allowed_tools: ["bash_scoped", "python3_eval", "ast_graphify", "compile_manifest"]
    filesystem_access: "READ_WRITE_SCRATCH_ONLY"
    network_access: "LOCAL_LOOPBACK_ONLY"


  TIER_3_ADMINISTRATOR:
    roles: ["FileAdministrator", "OrchestratorKernel"]
    allowed_tools: ["issue_clearance_token", "swap_model", "sync_manifest", "housekeeper_sweep"]
    filesystem_access: "CONTROLLED_MIRROR_ACCESS"
    network_access: "TAILSCALE_MESH_ENABLED"
```


---


## 5. Daemon Supervision & Network Topology


### 5.1 Local Daemon Supervision (Runit / Termux-Services)
* `llamad` (llama-server / GGML plane): Bound to `http://127.0.0.1:8081`. Supervised via `runit` with `respawn` guards.
* `aesopd` (Orchestration Bridge): Bound to WebSocket `ws://127.0.0.1:8765`. Routes IPC packets between presentation shells and backend engines.


### 5.2 OmniRoute Memory Extraction Tap
All incoming and outgoing inference requests pass through the OmniRoute gateway on `http://127.0.0.1:20128/v1`:
* **Token Compression**: Applies RTK (Real-Time Keyphrase) and Caveman formatting, reducing payload overhead by 15% to 65% prior to context injection.
* **Asynchronous Memory Tap**: Transparently intercepts candidate interaction turns, extracting habit keys and task progress directly into `#d.u.m.b.a.s.s.` SQLite/Postgres tables without adding inference latency.


### 5.3 Local Air-Gapped Mesh Protocol
To execute multi-node compute with zero external bandwidth consumption:
* A standalone, un-metered Wi-Fi router serves as a dedicated physical LAN switch.
* Node Alpha connects via 5GHz Wi-Fi; Node Beta and Node Gamma connect via Gigabit Ethernet.
* Inter-agent RPC flows across local static IPs (`192.168.1.x`) or encrypted Tailscale subnet routes with zero data routed over public internet lines.