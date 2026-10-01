---
name: obsidian-vault
description: Search, create, and manage notes in the NovAExorpus Obsidian vault. The vault is the write endpoint for terrestrial-brain memory logging and graphify output.
---

# Obsidian Vault

## Vault location

`~/storage/shared/Documents/NovAExorpus/`

This IS the NovAExorpus repo — same name, same content. Synced to
GitHub via Obsidian Git plugin (`git@github.com:c10vis-poem/NovAExorpus.git`).
Not Drive-synced. The git repo at `~/repos/NovAExorpus/` is a separate
checkout of the same repo.

**Supersession rule:** LlmWiki content supersedes anything in git repos
when they conflict.

## Role in the pipeline

The vault is not a viewer — it is a **write endpoint**:

- **terrestrial-brain → vault**: every TB static memory write creates a
  markdown file in `memories/` with frontmatter (uuid, timestamp, category).
  This is enforced by the router-guard multi-write pipeline protocol.
- **graphify → vault**: `Codebase-Graphs/` receives GRAPH_REPORT.md,
  graph.json, and graph.html on every graphify update.
- **Obsidian Git**: auto-commits and pushes to GitHub so all writes
  propagate to any device that pulls the repo.

## Key directories

| Path | Purpose |
|------|---------|
| `memories/` | TB memory log (auto-created by pipeline) |
| `Codebase-Graphs/` | graphify output (report, json, html) |
| `LlmWiki/` | Planning docs (supersedes git repo content) |
| `NovAExorpus_Repos/` | Repo planning/spec docs |

## Naming conventions

- **Index notes**: aggregate related topics
- **Title case** for all note names
- Use Obsidian `[[wikilinks]]` syntax for linking

## Workflows

### Search for notes

```bash
find ~/storage/shared/Documents/NovAExorpus/ -name "*.md" | grep -i "keyword"
grep -rl "keyword" ~/storage/shared/Documents/NovAExorpus/ --include="*.md"
```

### Create a new note

1. Use **Title Case** for filename
2. Add `[[wikilinks]]` to related notes at the bottom
3. Place in the appropriate subdirectory if one exists

### Find backlinks

```bash
grep -rl "\[\[Note Title\]\]" ~/storage/shared/Documents/NovAExorpus/ --include="*.md"
```
