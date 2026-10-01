---
name: corpus-verify
description: >
  Independent RLVR check. Reads source and clean files with different extraction
  libraries than tools/clean.py used, compares by named-atom and segment
  containment, and reports which details are missing. Hard rule 5: the tool that
  cleaned a file does not get a vote on whether the cleaning was good. Use after
  any corpus clean pass (first run, new sources, changes to tools/clean.py) or
  whenever a source is suspected of losing detail through cleaning.
allowed-tools: Bash, Read, Glob, Grep
---

# Corpus-Verify Skill

## When to use

Fire this skill after any of the following:

- First run of `tools/clean.py` on a new corpus
- New sources added to `01-sources/`
- `tools/clean.py` modified in any way
- A specific source is suspected of losing detail through cleaning
- Before any grill session or downstream compilation
- Whenever the RLVR check has not been run on the current head of `02-clean/`

Do not fire this skill as a dry-run only. The output files in `03-check/` are the permanent record. Always write them.

## What this skill does not do

- It does not modify `01-sources/` or `02-clean/`. Those directories are read-only from this skill's perspective.
- It does not repair any defect it finds. It reports and records. Repairs happen in a separate clean pass.
- It does not self-certify. It shares no code, no imports, and no comparison methods with `tools/clean.py`.

---

## Invocation

```bash
# Standard run — reads 01-sources/, compares against 02-clean/, writes 03-check/
python3 tools/check.py

# Dry run — prints roll-up to stdout, writes nothing
python3 tools/check.py --dry-run
```

Paths are hardcoded: `01-sources` (source), `02-clean` (clean), `03-check` (output). Run from the repo root.

### Dependencies

```bash
pip install pypdf
```

All other dependencies are Python stdlib: `zipfile`, `xml.etree`, `html.parser`, `difflib`, `unicodedata`, `io`, `os`, `re`, `json`, `datetime`.

---

## Extractor independence

This is the core of why the check works as RLVR. The tool that cleaned a file used one set of libraries; this checker uses a completely different set. A false pass cannot emerge from both extractors making the same mistake.

| Format | `tools/clean.py` uses | `tools/check.py` uses |
|---|---|---|
| PDF | pymupdf `fitz.page.get_text()` | pypdf `PdfReader.extract_text()` |
| DOCX | pandoc docx → markdown | stdlib `zipfile` + `xml.etree` over `word/document.xml`, headers, footers, footnotes, endnotes, hyperlinks via `document.xml.rels` |
| HTML | pandoc html → plain | stdlib `html.parser`, one text node at a time, tag boundaries preserved, `alt`/`title` captured |
| Text | `open().read()` utf-8 | byte read + BOM/encoding probe |
| ZIP | skipped | opened and enumerated — text members extracted and checked |

---

## Core algorithm

### squash(s)

Fold Unicode to ASCII via NFD decomposition, lowercase, strip everything non-alphanumeric. Makes `CHIP SM8750` and `CHIPSM8750` both `chipsm8750`. Used for containment checks where whitespace and punctuation differences are irrelevant.

### wordstream(s)

Same Unicode fold, but collapse separators to single spaces instead of stripping them. Preserves word boundaries. Detects whether a value survived as a separate word or got fused to its neighbor.

### find_atoms(text)

Extract named values from the source: URLs, file paths, version strings, measurements (e.g., `32 GB`), identifiers, dates. Each atom is checked by containment in the clean text (both squash and wordstream).

**Adjacency guard:** If the checker's own extractor produced an atom fused to its neighbor (i.e., wordstream of the atom is not found in wordstream of the checker's own extraction), that atom is set aside as unjudgeable. It is not reported as a finding. The checker cannot assert that the clean file is missing something it couldn't read cleanly itself.

### segment containment

The source text is split into segments. Each segment is checked for containment in the clean text via squash comparison. Segments that pass are done. Segments that fail go to chunk_split.

### chunk_split(segment, clean)

For a segment that fails containment: greedy search for the largest contiguous sub-runs that do survive in the clean text. The sub-runs that don't survive name the culprit words. This is reported verbatim — no percentage, no score.

### edge_check(source_line, clean_text)

For lines near the boundaries of a source document — where icon-font glyphs or format-specific artifacts often appear — uses a chunk-based test rather than exact-string matching. This prevents icon glyph rendering differences between extractors from producing false failures.

### furniture_class(line)

Classifies a line the checker found in the source that is absent from the clean file. Re-derives the furniture strip policy from `README.md` and `CLAUDE.md` independently, then checks whether the line matches any furniture rule. If it does, the absence is expected — not a finding. If it doesn't match any furniture rule, it's a content loss.

---

## Verdict labels

| Verdict | Meaning |
|---|---|
| `PASS` | All atoms and segments found in clean. All stripped lines are furniture. |
| `PASS WITH WARNINGS` | No content missing, but shape differences noted: respaced values, UTF-8 BOM present in markdown body, or similar. Not a content defect. |
| `FAIL` | At least one atom or segment is missing from the clean file and the adjacency guard does not excuse it. |
| `PASS + UPSTREAM DEFECT` | Content passed, but source itself ends mid-sentence or is truncated before this repo touched it. Not a cleaning defect — a defect in the source file. |
| `PASS WITH WARNINGS + UPSTREAM DEFECT` | Both conditions above together. |
| `NO-COUNTERPART` | A source file exists in `01-sources/` with no matching file in `02-clean/`. Requires decision: either clean it or formally document why it was skipped. |
| `ERROR` | The checker itself hit an exception processing this file. Investigate before treating as a pass. |

---

## Calibration rules — what to exclude from findings

These are not findings. Do not report them, do not add them to `FINDINGS.jsonl`.

1. **Atoms the checker's own extractor produced fused to its neighbor.** The adjacency guard handles this automatically. If an atom is unjudgeable by the checker's own read, it cannot be asserted missing.

2. **PDF table cells welded by pypdf.** pypdf does not respect table cell boundaries in all PDFs. If multiple cells are fused in the checker's extraction but not in the source, the affected atoms are unjudgeable.

3. **Icon-font glyphs that differ between readers.** Use the chunk-based edge test (`edge_check`), not exact-string. Two readers will render icon fonts differently; that difference is not a content loss.

4. **Lines matching the furniture strip policy.** `furniture_class` handles this. A line the clean file removed that matches the strip policy is expected; it is not a finding.

5. **UTF-8 BOM in markdown body.** Reported as a warning (shape), not as a content failure. `tools/clean.py` opens text files with `utf-8` not `utf-8-sig`, so BOMs pass through into the markdown. 21 files in the current corpus carry this. It is the cleaner's known behavior, documented.

6. **Source upstream defects.** A source that ends mid-sentence was truncated before this repo touched it — often because the operator stripped trailing prompts, hallucinated code, or filler before saving. These are reported as `UPSTREAM DEFECT` labels, not as cleaning failures. Do not attempt to repair them from the source.

---

## Output files

All output goes to `03-check/`. Directory structure mirrors `01-sources/`.

### Per-source report: `<name>.check.md`

```markdown
---
source: 01-sources/<path>
clean:  02-clean/<path>
kind:   pdf | docx | html | text | zip
verdict: PASS | PASS WITH WARNINGS | FAIL | ...
checked: 2026-08-27
---

## Verdict

[verdict label and one-sentence summary]

## Findings

[Only present if verdict is not PASS. Each finding includes:]
- Source line number(s)
- Verbatim text from source
- What the clean file contains instead (or: absent)
- Finding class: fused token | missing atom | truncated segment | ...

## Furniture audit

[Lines removed by clean.py, classified as furniture or content-loss]

## Edge check

[Results of boundary/icon-glyph checks near document start and end]
```

### Roll-up: `SUMMARY.md`

Verdict table (one row per source), total counts per verdict, list of every non-PASS with a link to its `.check.md`. Written to `03-check/SUMMARY.md`.

### Machine-readable: `FINDINGS.jsonl`

One JSON object per finding, written to `03-check/FINDINGS.jsonl`. Schema:

```json
{
  "source": "01-sources/path/to/file",
  "clean":  "02-clean/path/to/file",
  "kind":   "pdf | docx | html | text | zip",
  "severity": "FAIL | WARN | UPSTREAM",
  "class":  "fused token | missing atom | truncated segment | stray BOM | respaced value | truncated source",
  "finding": "human-readable sentence naming the problem",
  "detail": "verbatim text or additional context"
}
```

---

## Config layer

These are the parameters that should be configurable per-corpus invocation. Currently hardcoded in `tools/check.py`; the grill session should decide whether to expose them as CLI flags or a config file.

| Parameter | Current value | Description |
|---|---|---|
| `SRC` | `01-sources` | Source directory |
| `CLEAN` | `02-clean` | Clean directory |
| `OUT` | `03-check` | Output directory |
| `FORMATS` | `{pdf, docx, html, txt, md, zip}` | Which formats to process |
| `FURNITURE_POLICY` | Derived from README + CLAUDE.md at runtime | Strip rules — re-derived independently, not imported from clean.py |
| `ATOM_TYPES` | URL, path, measurement, version, identifier, date | Classes of values extracted by find_atoms |
| `ADJACENCY_GUARD` | On | Whether to exclude atoms the checker itself fused to neighbors |
| `EDGE_LINES` | 10 | Lines at document start/end to use edge_check instead of exact-string |

---

## After running — required actions

### On FAIL

1. Open `03-check/<name>.check.md` and read the finding verbatim.
2. Open `01-sources/<name>` and `02-clean/<name>` side by side.
3. Confirm the finding is real (not an adjacency-guard miss — those are excluded automatically).
4. Fix by re-running `tools/clean.py` with the specific source, or by patching the clean file directly if the cleaner cannot be made to produce the right output.
5. Re-run `python3 tools/check.py` to confirm the fix. The finding must be absent from the new report.
6. Commit both the fixed `02-clean/` file and the updated `03-check/` report together.

### On NO-COUNTERPART

Two options — pick one, document the decision in a comment at the top of the source file:

- **Clean it:** run `tools/clean.py` on just that source, confirm the clean file is produced, re-run the check.
- **Formally skip it:** add an entry to `03-check/<name>.check.md` with verdict `NO-COUNTERPART` and a one-sentence reason. Hard rule 2 (same file count out as in) is satisfied by the documented skip, not by pretending the file doesn't exist.

### On PASS WITH WARNINGS

No action required unless a warning escalates. UTF-8 BOM warnings are expected for 21 current files and require no action. Respaced-value warnings are shape differences, not content losses.

### On UPSTREAM DEFECT

Do not attempt to repair. The source is truncated before this repo touched it. Record it, leave it. If the operator later provides an updated source file, re-run both clean and check on it.

### On ERROR

Investigate immediately. Do not treat an ERROR as a pass. Read the stack trace in the `.check.md`, fix the underlying issue (usually a format the checker's reader can't parse), re-run.

---

## Extension to other corpora

This skill is not specific to the NovAExorpus corpus. To apply it to another repo or corpus:

1. Set `SRC`, `CLEAN`, `OUT` to the appropriate directories (make them configurable — see Config layer).
2. Confirm the furniture strip policy is documented in that repo's README or CLAUDE.md — `furniture_class` re-derives it from there.
3. Confirm `tools/check.py` is present or copied in (it imports nothing from `tools/clean.py` and has no repo-specific logic).
4. Run. The FINDINGS.jsonl schema is identical across all corpora.

The JSONL manifest pattern (Pattern 02 in this prep doc) pairs with corpus-verify: once a corpus has a `MANIFEST.jsonl`, the checker can be pointed at specific files by ID rather than walking the full tree.

---

## Known issues in current corpus (2026-08-27)

| File | Issue | Status |
|---|---|---|
| `Nova Corpus — Device Stack.html` | 7 fused tokens — CHIP, 32 GB, CLIENTS, 4 repo paths fused by pandoc html→plain. Source separates them at element boundaries. | **Open — needs re-clean with html.parser** |
| `SKILLS.md/technical-builder-style.skill.zip` | No counterpart in `02-clean/`. ZIP was skipped; it contains text members. | **Open — decide: clean or document skip** |
| 21 files | UTF-8 BOM passes through into markdown body | Warning only — no action required |
| 26 files | Source truncated mid-sentence (upstream defect) | Documented — no repair action |
