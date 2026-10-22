---
name: corpus-batch-processing
description: Orchestrator+subagent workflow for converting a repo's raw/ dump into clean_md/ at scale. Use whenever a repo's raw/ folder has more source files than one agent should process serially (roughly 20+) inside project NovÆxorpus. Trigger on "process raw", "convert the dump", "run phase 1 on <repo>", or "clean up the raw sources for <repo>".
---

# Corpus Batch Processing (Phase 1: raw/ → clean_md/ + tools/)

## Why this exists

Processing 100+ raw files serially in one agent's own context is slow and burns
that agent's context window on file contents it doesn't need to keep. Splitting
the work across parallel subagents, each handling a batch, finishes faster and
keeps each subagent's context scoped to just its own files.

## Orchestrator's job

1. `find <repo>/raw -type f | sort` — get the full file list.
2. Eyeball the list once for anything that needs a skip/withhold rule before
   dispatching (credential-shaped filenames, personal/billing CSVs, binary git
   internals like `.rev` pack files, anything that isn't real corpus content).
3. Split into batches of ~25-30 files each. More batches = more parallelism,
   but each subagent still needs enough files to be worth the dispatch
   overhead. 4 batches of ~25-30 has worked well for a 100-file raw/ folder.
4. Dispatch one `general-purpose` agent per batch (see prompt template below),
   each with its own explicit file list — never let two agents claim the same
   file.
5. Do not read the subagents' output transcripts. Wait for each one's own
   terse report (a table: filename | action | note) and collect those.
6. After all batches report back, spot-check a handful of the written
   `clean_md/` files against their `raw/` originals before considering the
   pass done — subagents can still make mistakes on a full pass.

## Subagent prompt template (the rules that go in every dispatch)

1. **Verbatim technical content, strip only conversational fluff.** Remove
   chat scaffolding — greetings, "Sure, here's...", meta-commentary — but
   preserve 100% of technical content: every rule, parameter, code block,
   decision, number, named entity survives untouched. No summarizing, no
   interpreting, no paraphrasing technical content.
2. **There is no fixed rule for or against merging/dropping sources — decide per file, by actually comparing content, the way the Lex-Novi audits already model:** each source gets one of three real dispositions:
   - **Port straight across** — the default. Clean it into its own `clean_md/` output, fluff stripped.
   - **Combine** — when two or more sources are genuinely the same thing (a later draft superseding an earlier one, the same export saved under two filenames, etc.): read both, pick the more complete/correct one as the canonical `clean_md/` output, and note the other's relationship to it in the canonical file's frontmatter. Don't delete the superseded raw source — it stays in `raw/` regardless.
   - **Omit** — when a source is pure noise (a raw search-engine scrape page, a truncated/corrupted duplicate with no unique content) with nothing worth cleaning. Log it as omitted with a one-line reason; don't write a `clean_md/` output for it.
   Never guess a disposition from filenames alone — if two sources look like they might be related, actually read both before deciding. When genuinely unsure, port straight across (the safe default) rather than omitting or merging on a guess.
3. **Never modify or delete anything under `raw/`.** Read-only source, always.
4. **Output path:** `<repo>/clean_md/<slug>.md`, where slug = lowercase
   filename, non-alphanumeric runs collapsed to single hyphens, ligatures
   folded (Æ→ae). Frontmatter on every output:
   ```yaml
   ---
   source: raw/<original relative path>
   cleaned: <YYYY-MM-DD>
   converter: <how it was read - e.g. "plain text read", "pdf extraction via Read tool">
   ---
   ```
5. **Per source, ask: does it define an action?** If not, it's reference
   content — the `clean_md/` write is all it needs. If it does, classify what
   kind of action-artifact it produces — **skill**, **tool**, **hook**, or
   **script** — and extract that artifact into its matching folder (`skills/`,
   `tools/`, `hooks/`, `scripts/`), *in addition to* the `clean_md/` write, not
   instead of it. **A single source can produce more than one artifact type**
   if it covers multiple distinct steps of a process (e.g. one doc might
   contain both a tool and a hook, or a skill and a script) — extract each one
   separately, don't force it into a single category. This is a
   classification question about what the content *is*, not a merging
   operation.
   - A **tool**/**script**: a complete, standalone executable (`.py`/`.sh`, or
     a fenced code block that's a runnable utility, not an illustrative
     snippet). Write it with the correct shebang into `tools/` or `scripts/`
     as fits. Note: on this device, `chmod +x` has no effect on anything under
     `/sdcard` — it's a FUSE mount with no Unix execute bits. Run it anyway
     (costs nothing) but don't report the file as "made executable."
   - A **skill**: a reasoning heuristic or multi-step procedure meant to be
     loaded and followed by an agent — write a real `SKILL.md` (YAML
     frontmatter: `name`, `description` with explicit trigger conditions)
     into `skills/<name>/`.
   - A **hook**: an event-triggered automation (fires on a specific tool-use
     event, file change, or session event) — write into `hooks/`.
6. **Skip/withhold rules — never silently process these into shared output:**
   - Credential/API-token-shaped files (e.g. `tokens.txt`, anything that reads
     like a key or secret) — do not read the content into any output or
     report. Just log "skipped - credential file, not processed."
   - Personal/billing data (e.g. `USER-SETTINGS.CSV`, subscription exports) —
     write a withheld-content stub only ("Sensitive user data — content
     withheld, see raw/<path> directly"), never quote actual values anywhere,
     including the subagent's own report back to the orchestrator.
   - Binary git-internal files (`.rev` pack files, etc.) — skip entirely.
7. PDFs/docx: use the Read tool (handles PDF text extraction) or
   `pandoc`/`pdftotext` via Bash if the Read tool doesn't get clean text.
8. End with a compact table report: filename | action taken (clean_md
   written / tool extracted / skill extracted / hook extracted /
   skipped-sensitive / skipped-binary — list all that apply, a source can hit
   more than one) | one-line note. No prose report — a table only, so the
   orchestrator can scan results across all batches quickly.
9. **Write a mem0 memory before finishing** (`mcp__mem0-mcp__add_memory`,
   `agent_id: novaexorpus-corpus`) summarizing what this batch actually did:
   which files were cleaned, which skills/tools were extracted, what got
   skipped and why. This is in addition to the table report, not instead of
   it — the table is for the orchestrator to read right now, the mem0 entry
   is so a later session can query what happened without re-reading every
   clean_md file.

## Known related tools

- `doc_to_skill_and_tool.py` (formerly in the retired `novae-xorpus/tools/`; not found on device 2026-10-01) — does a similar
  fenced-code-block extraction automatically for a single file. Useful as a
  spot-check tool after a batch pass, not a replacement for it (it doesn't do
  the conversational-fluff stripping this skill's subagents do).
- `clean.py` / `check.py` (in the vault's `tools/`, `~/storage/shared/Documents/NovAExorpus/tools/`) —
  a different, narrower pipeline for that repo's own `01-sources/`→`02-clean/`
  job. Different scope, same spirit (verbatim extraction, independent
  verification). Don't conflate the two.

## What this does NOT do

- Does not run the RLVR/independent-verification check (Phase 2). Run
  `corpus-verify`/`tools/check.py`-equivalent against the batch's output
  separately, with a *different* extraction method than whatever the batch
  subagents used, per Hard Rule 5 (extractor independence — the tool that
  cleaned a file doesn't get to grade its own cleaning).
- Does not populate the wiki (Phase 4) or generate chunk.jsonl markers
  (Phase 3). Those are separate passes, run after clean_md/ is verified.
