# RESUME.md — Session Ledger

Repository: `aesop-xi`
Last session: 2026-09-15 (second session this date)

## WHAT LANDED THIS SESSION

- **terrestrial-brain MCP server brought up from scratch.** Database
  `terrestrial_brain` created (role `brain_app`, 23 migrations applied),
  pgvector `CREATE EXTENSION vector` done, MCP server running on
  `localhost:8000/mcp` via system deno. Round-trip verified with
  `tools/list` returning `search_thoughts`, `list_thoughts`, etc.
  Env vars `TB_MCP_URL=http://localhost:8000/mcp` and `TB_MCP_KEY` set
  in `~/repos/NovA-terrestrial-brain/local-mcp/.env.local`.
- **mem0 CLI plugin fixed.** API key was in wrong directory since Sep 9
  (`~/.mem0/claude-code-plugin/` instead of
  `~/.claude/plugins/data/mem0-mem0-plugins/`). All doctor checks now
  passing, hooks firing (170+ events captured this session). Both MCP
  and CLI paths verified working.
- **mem0 MCP populated.** 14+ memories written covering architecture,
  workflow, infrastructure, preferences, priorities. Was completely empty.
- **File-based auto memory updated.** 11 entries (was 7, all stale from
  Aug 28–31). Updated PENDING.md/unresolved.md workflow, added session
  startup rules, repo-must-be-runnable feedback, architecture, runtime state.
- **NovAExorpus/projects/ fully wired.** All 7 base repos now have
  symlinks for RESUME.md, CLAUDE.md, PENDING.md, AGENTS.md. Was only
  aesop-xi with 2 of 4. horizons-ui AGENTS.md created from template.
- **OmniRoute deploy-target decided.** Google Cloud VM (operator choice).
- **CLAUDE.md updated.** `unresolved.md` references changed to
  `PENDING.md` throughout session handoff workflow section.
- **scripts/bootstrap-stack.sh deleted** (duplicate bootstrap, caused
  agent confusion). CLAUDE.md historical reference marked retired.

## RUNTIME INFRASTRUCTURE VERIFIED LIVE

- **Postgres 18.2** on `localhost:5432` (data: `~/pgdata/`)
- **pgvector v0.8.6** — `CREATE EXTENSION vector` done in
  `terrestrial_brain` database
- **terrestrial-brain MCP** on `localhost:8000/mcp` (open-brain v1.0.0,
  deno process). Start: `cd ~/repos/NovA-terrestrial-brain/supabase/functions/terrestrial-brain-mcp && LOCAL_PG_URL="postgres://brain_app:brain_local_dev@127.0.0.1:5432/terrestrial_brain" MCP_ACCESS_KEY="$(grep MCP_ACCESS_KEY ~/repos/NovA-terrestrial-brain/local-mcp/.env.local | cut -d= -f2)" OPENROUTER_API_KEY="$OPENROUTER_API_KEY" deno run --allow-net --allow-env --allow-read --allow-write index.ts`
- **mem0 hosted MCP** verified with key at `~/.mem0/.env`
- **mem0 plugin** (v0.3.0) hooks firing, key at
  `~/.claude/plugins/data/mem0-mem0-plugins/api-key`
- **OmniRoute** NOT deployed — goes on Google Cloud VM (P0)

## STANDING RULES

- 3-plane split: **aesop-xi = data · novus-aexenti = cognitive ·
  NovAExopia = execution**. NovAExorpus is the vault.
- **Never call mem0/terrestrial-brain directly** — route through
  OmniRoute once deployed. Until then, direct calls are acceptable.
- Repo-specific backlog: **PENDING.md** (not unresolved.md).
  Cross-repo backlog: `~/repos/NovAExorpus/unresolved.md`.
- **Post-grill only**: Novus-Agenti demolish + repo-shape decisions.

## PRIORITY ORDER (operator-stated, do not resequence)

1. **OmniRoute on Google Cloud VM** — deploy, configure, point
   `tools/omniroute/` + `skills/omniroute/` at it
2. **Full LlmWiki ingestion** — 5000+ files
3. Post-corpus loose ends
4. **Grill session** — AFTER corpus
5. **15-20 tools/skills/scripts** build-out

## FIRST ACTION NEXT SESSION

```bash
cd ~/repos/aesop-xi
bash tools/bootstrap.sh
```

Then:
1. Read this file + CLAUDE.md + PENDING.md
2. Run `mem0:status` — verify `api_key_configured: true` and events
   incrementing (use `--plugin-data-dir ~/.claude/plugins/data/mem0-mem0-plugins`)
3. Verify terrestrial-brain is running: `nc -z localhost 8000`
   (if not, start it per the command in RUNTIME INFRASTRUCTURE above)
4. Check OmniRoute VM status — is it deployed yet?

## Related handoffs

- Cross-repo backlog: `~/repos/NovAExorpus/unresolved.md`
- Repo-specific backlog: `PENDING.md` (this repo)
- NovAExorpus/projects/ has symlinks to all 7 base repos' handoff docs
