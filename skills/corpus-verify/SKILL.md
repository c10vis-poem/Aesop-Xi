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
- New sources added under `raw_database/`
- `tools/clean.py` modified in any way
- A specific source is suspected of losing detail through cleaning
- Before any grill session or downstream compilation
- Whenever the RLVR check has not been run on the current state of `clean_md/`

A full run writes `audit/`, which is the permanent record. Use `--dry-run` only to look before writing, or to grade a candidate file that is not in `clean_md/` yet.

## What this skill does not do

- It does not modify `raw_database/` or `clean_md/`. Both are read-only from this skill's point of view.
- It does not repair any defect it finds. It reports and records. Repairs happen in a separate clean pass.
- It does not self-certify. It shares no code, no imports, and no extraction library with `tools/clean.py`.

---

## Layout

Everything sits at the vault root (`/storage/emulated/0/Documents/NovAExorpus`, found by `find_dirs()` as the folder under `Documents/` whose name contains `xorpus`):

| Path | Role |
|---|---|
| `raw_database/raw/` | sources |
| `raw_database/02_MY_ORIGINALS/` | sources |
| `raw_database/Dump/zip/` | sources |
| `clean_md/` | cleaned Markdown written by `tools/clean.py` |
| `audit/` | output of `tools/check.py` |

There is no `Repos*` level and no `01-sources/`, `02-clean/`, `03-check/` any more.

## Invocation

Run from the vault root:

```bash
# Check every clean_md/*.md (POINTER.md excluded); writes audit/
python3 tools/check.py

# Check named files only (any path; the file need not live in clean_md/)
python3 tools/check.py clean_md/foo.md "some dir/bar.md"

# Dry run: prints the roll-up to stdout, writes nothing
python3 tools/check.py --dry-run [CLEAN_MD ...]
```

Usage line: `check.py [--dry-run] [CLEAN_MD ...]`. The exit code is 1 when any file FAILs, else 0.

Pairing is by frontmatter. `check.py` reads the `source:` line from the first 500 characters of the clean file (quotes stripped) and resolves it, in order, as a path relative to the vault root (or absolute), then as a bare filename in `raw/`, `02_MY_ORIGINALS/`, and `Dump/zip/`. A clean file whose source cannot be resolved gets `NO-SOURCE`.

### Dependencies

```bash
pip install pypdf beautifulsoup4
```

Everything else is stdlib: `zipfile`, `xml.etree`, `difflib`, `unicodedata`, `os`, `re`, `datetime`.

---

## Extractor independence

This is why the check works as RLVR. The cleaner read a file with one set of libraries; the checker reads it with a different set, so a false pass cannot come from both extractors making the same mistake.

| Format | `tools/clean.py` uses | `tools/check.py` uses |
|---|---|---|
| PDF | mutool (mupdf) `mutool draw -F text` | pypdf `PdfReader.extract_text()` |
| DOCX | python-docx (paragraphs, heading levels, tables) | stdlib `zipfile` + `xml.etree` over `word/document.xml` (`w:t` runs per `w:p`) |
| HTML | stdlib `html.parser` | BeautifulSoup4 `get_text(separator="\n")` |
| Text | `open().read()` utf-8 | byte read + encoding probe (utf-8, then latin-1), BOM noted |

Type is sniffed from magic bytes, not the extension. In `check.py` anything starting with `PK` is read as DOCX, and XML-like markup that is not HTML is read as text.

`clean.py` extractors raise on failure (mutool missing or non-zero exit, a DOCX python-docx cannot open, an unreadable HTML file). `main()` counts the file under Errors and writes no clean file, so an error string never becomes cleaned content. `clean.py` also skips any raw file that a `clean_md/` file already names in its `source:` line, so reruns no longer add `_N.md` copies.

---

## Core algorithm

### squash(s) and wordstream(s)

`fold` maps Unicode to comparable ASCII (NFKC, invisible marks and the BOM dropped, ligatures such as Æ to AE, then NFKD with combining marks removed) and lowercases. `squash` then strips everything non-alphanumeric, so `CHIP SM8750` and `CHIPSM8750` both become `chipsm8750`. `wordstream` collapses separators to single spaces instead, which keeps word boundaries and shows whether a value survived as its own word or got fused to a neighbor.

### find_atoms(lines)

Extracts named values from the checker's read of the source (URLs, paths, versions, measurements, identifiers, dates; see `ATOM_RULES`). Each atom is looked for by containment in the clean text, squashed and as a wordstream.

**Adjacency guard:** if the checker's own extractor produced an atom fused to its neighbor, the atom is set aside as unjudgeable and is not a finding. The checker cannot claim the clean file lost something it could not read cleanly itself.

### Segment containment and chunk_split

Each non-blank source line is a segment (lines over 300 characters are split at sentence ends); segments of at least `MIN_SEGMENT` squashed characters are checked for containment. A segment that fails goes to `chunk_split`, a greedy search for the longest sub-runs that do survive. The pieces that do not survive name the lost words, verbatim, with no score.

### edge_check

The first and last `EDGE_CHARS` (60) squashed characters of the source are tested chunk by chunk rather than as one run, because two PDF readers disagree about icon glyphs and line breaks at page ends. A piece found nowhere in the clean file means the start or end was lost.

### furniture_class(line, kind)

Says whether a source line missing from the clean file is furniture. The policy is transcribed by hand into `check.py` from `README.md` "The one job" (it is not read at runtime and not imported from `clean.py`): blank lines, browser or app chrome (`CHROME`: "Use code with caution", "Show more", "Sign in" and similar), and, for PDFs only, bare page numbers (`PAGE_NUMBER`). A line made of nothing but these fragments is furniture; anything else that went missing is a finding.

### looks_truncated

If the source itself stops mid-sentence, that is reported as an upstream defect, never repaired.

---

## Verdict labels

| Verdict | Meaning |
|---|---|
| `PASS` | Every atom and segment the checker found in the source is in the clean file. |
| `PASS WITH WARNINGS` | Nothing missing, but shape differences noted, for example a respaced value or a UTF-8 BOM carried into the Markdown body. |
| `FAIL` | At least one atom, segment, or edge piece is missing and the adjacency guard does not excuse it. |
| `... + UPSTREAM DEFECT` | Suffix on any of the above: the source itself ends mid-sentence. |
| `NO-SOURCE` | The clean file has no `source:` line, or the source it names cannot be found. |

There is no `ERROR` verdict. An exception inside the checker stops the run with a traceback; fix the cause and rerun. Never read a crashed run as a pass.

---

## Calibration rules: what is not a finding

1. **Atoms the checker's own extractor fused to a neighbor.** The adjacency guard drops them automatically.
2. **PDF table cells welded by pypdf.** Atoms affected that way are unjudgeable, not missing.
3. **Icon-font glyphs that differ between readers.** `edge_check` is chunk-based for this reason.
4. **Lines matching the furniture policy.** `furniture_class` handles them.
5. **UTF-8 BOM in a Markdown body.** A warning (shape), not a content failure.
6. **Source upstream defects.** Reported as `UPSTREAM DEFECT`, not as cleaning failures. Do not repair them from the source.

---

## Output files

A full run (no `--dry-run`) writes into `audit/`:

- `audit/<clean name>.check.md`, one per checked clean file. Frontmatter: `checker`, `checked`, `source`, `cleaned`, `source_kind`, `extractor`, `independent_of`, `verdict`, `fails`, `warnings`, `upstream_defects`. Body: verdict, a meta table (atoms judged, atoms set aside, segments checked, furniture lines, whether the start and end survive), then sections for Fails, Warnings, Upstream defects (each capped at `MAX_LIST` = 40 entries), and the independent furniture audit.
- `audit/rlvr_verification_report.md`, the roll-up: one table row per clean file with verdict and fail count.

Stdout prints one line per file (`[VERDICT] name N fails`), the first five fail reasons indented under it, and a summary of PASS, FAIL, and other counts.

---

## Tunables

Constants at module level in `tools/check.py`; there are no CLI flags beyond `--dry-run`.

| Constant | Value | Meaning |
|---|---|---|
| `MIN_MISSING` | 3 | squashed length below which absence cannot be asserted |
| `MIN_FUSED` | 4 | squashed length below which a substring hit means nothing |
| `MIN_SEGMENT` | 24 | squashed length of a segment worth checking as a whole |
| `EDGE_CHARS` | 60 | squashed characters tested at each end of the source |
| `MAX_LIST` | 40 | findings listed per section in a `.check.md` |
| `CHROME`, `PAGE_NUMBER` | see code | the hand-transcribed furniture policy |

---

## After running: required actions

### On FAIL

1. Open `audit/<name>.check.md` and read the finding verbatim.
2. Open the source and the clean file side by side.
3. Confirm the finding is real.
4. Fix by re-cleaning that source (delete or move the stale clean file first, since `clean.py` skips sources that already have one), or by patching the clean file directly when the cleaner cannot produce the right output.
5. Rerun `python3 tools/check.py <clean file>`. The finding must be gone.

### On NO-SOURCE

Fix the `source:` line so it resolves (vault-relative path or a bare filename present in `raw/`, `02_MY_ORIGINALS/`, or `Dump/zip/`), or record why the file has no source.

### On PASS WITH WARNINGS

No action unless a warning escalates. BOM and respaced-value warnings are shape differences, not content losses.

### On UPSTREAM DEFECT

Do not repair. The source was truncated before this repo touched it. Record it and leave it. If the operator later provides a complete source, rerun both clean and check on it.

---

## Extension to other corpora

1. Point `find_dirs()` in `tools/check.py` at the other corpus's source, clean, and audit folders.
2. Re-transcribe the furniture policy (`CHROME`, `PAGE_NUMBER`) from that corpus's README by hand; do not import it from its cleaner.
3. Confirm the cleaner there uses different extraction libraries from the ones listed above for `check.py`, or swap the checker's extractors so they stay disjoint.
4. Run.

---

## Known issues (2026-10-08)

| Issue | Status |
|---|---|
| `clean_md/` holds `_N.md` copies from earlier `clean.py` runs; 82 files are exact duplicates of another (ignoring the `cleaned:` date). `clean.py` prints this count each run. | Open: not deleted, needs an operator decision |
| `build_pairs()` in `check.py` is unused (left over from a splice) | Harmless |
| A `PK` file that is a plain ZIP, not a DOCX, makes `check.py` crash (no `word/document.xml`) | Open |
