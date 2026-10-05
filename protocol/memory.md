# Memory Protocol

The authoritative spec for Æsop-Xi's own memory architecture (what the *finished
agent* remembers and how) is `../ARCHITECTURE.md` §4 — four types, not three as
originally scoped: Declarative, Recall, Strategic, and Working/Ephemeral (added
2026-08-31, backed by the Redis container already in `deploy/jetson/docker-compose.yml`
that had no named memory role until now). This file does not duplicate that table —
edit it there, not here.

This file is separate from, and should not be confused with, the *dev-process*
handoff system for building Æsop-Xi: `../AGENTS.md` (standing conventions),
`../RESUME.md` (session snapshot, full rewrite each session), and
`../unresolved.md` (durable backlog). Those govern how a Claude Code session
maintains continuity while building Æsop-Xi. This file governs how the Æsop-Xi agent
itself manages memory once running. The two rhyme structurally (typed categories +
an index) but are not the same system and don't share content.

**Unresolved / open work backlog:** see `../unresolved.md`.
