# classify — task classification contract (Æsop-Xi)

The enforcement hooks (`enforce-prompt.sh`) ask one question per prompt: **what must be used before work starts?** Whoever answers implements this contract.

## Request (JSON, POST body or stdin)
```json
{"prompt": "user text", "cwd": "/abs/path", "loaded_skills": ["task-observer"]}
```

## Response (JSON)
```json
{"backend": "name", "required": [{"id": "termux", "require": "skill: android-termux-operator", "scope": "session"}]}
```
- `require`: `skill: <name>` | `read: <path>` | `run: <command start>`
- `scope`: `session` (once per session) | `turn` (every matching prompt)
- An empty `required` means nothing is enforced.

## Backends
- **Default:** keyword and repo rows in `~/.claude/ENFORCEMENTS.md` (`classify.sh`, local, deterministic).
- **Pluggable:** set `CLASSIFY_URL` to any loopback HTTP service that speaks this contract, for example a jev model, the on-device edge orchestration agent, or the cross-agent auditor.
- **Fail-safe:** no answer within 2 s, or invalid JSON → the keyword backend is used. A down classifier never blocks work.

## Learning side (not classifiers)
ReasoningBank, Continual Harness and task-observer read the pass/block log (`~/.claude/state/enforce-<session>.log`, summarised in each session recap). They may **propose** new ENFORCEMENTS rows; the builder approves the rows.
