#!/data/data/com.termux/files/usr/bin/bash
# setup-graph-pipeline.sh — One script to wire graphify, CRG, obsidian vault,
# smart-grep hook, and git hooks for the entire NovÆxorpus stack.
#
# Run once per project. Idempotent — safe to re-run.
# Usage: bash ~/repos/aesop-xi/tools/setup-graph-pipeline.sh [repo-path]
set -euo pipefail

REPO="${1:-$HOME/storage/shared/Documents/NovAExorpus}"
VAULT="$HOME/storage/shared/Documents/NovAExorpus"
GRAPHIFY_OUT="$REPO/graphify-out"
CRG_DIR="$REPO/.code-review-graph"
CLAUDE_DIR="$REPO/.claude"
HOOKS_DIR="$REPO/.git/hooks"
VAULT_MEMORIES="$VAULT/memories"
VAULT_GRAPHS="$VAULT/Codebase-Graphs"

ok()   { echo "  ✓ $*"; }
skip() { echo "  – $* (skipped)"; }
fail() { echo "  ✗ $*" >&2; }

echo "=== Graph Pipeline Setup ==="
echo "Repo:  $REPO"
echo "Vault: $VAULT"
echo ""

# ── 1. Verify CLIs ──────────────────────────────────────────────────────
echo "1. Checking CLIs"
if command -v graphify >/dev/null 2>&1; then
  ok "graphify $(graphify --version 2>/dev/null || echo 'present')"
else
  fail "graphify not on PATH — install via: proot-distro login debian -- pipx install graphifyy"
fi

if command -v code-review-graph >/dev/null 2>&1; then
  ok "code-review-graph $(code-review-graph --version 2>/dev/null || echo 'present')"
else
  fail "code-review-graph not on PATH — install via: proot-distro login debian -- pip install code-review-graph"
fi

# ── 2. Create directories ───────────────────────────────────────────────
echo ""
echo "2. Creating directories"
mkdir -p "$GRAPHIFY_OUT" "$VAULT_MEMORIES" "$VAULT_GRAPHS" "$CLAUDE_DIR"
ok "graphify-out/, vault/memories/, vault/Codebase-Graphs/"

# ── 3. Build / update graphify graph (AST-only, zero tokens) ────────────
echo ""
echo "3. Graphify: building graph"
cd "$REPO"
if command -v graphify >/dev/null 2>&1; then
  graphify update . 2>&1 | tail -5
  ok "graphify graph updated"

  # Export to obsidian vault
  if [ -f "$GRAPHIFY_OUT/GRAPH_REPORT.md" ]; then
    cp "$GRAPHIFY_OUT/GRAPH_REPORT.md" "$VAULT_GRAPHS/GRAPH_REPORT.md"
    ok "GRAPH_REPORT.md copied to vault"
  fi
  if [ -f "$GRAPHIFY_OUT/graph.json" ]; then
    cp "$GRAPHIFY_OUT/graph.json" "$VAULT_GRAPHS/graph.json"
    ok "graph.json copied to vault"
  fi
  if [ -f "$GRAPHIFY_OUT/graph.html" ]; then
    cp "$GRAPHIFY_OUT/graph.html" "$VAULT_GRAPHS/graph.html"
    ok "graph.html copied to vault"
  fi
else
  skip "graphify not installed"
fi

# ── 4. Build / update CRG graph ─────────────────────────────────────────
echo ""
echo "4. CRG: building graph"
cd "$REPO"
if command -v code-review-graph >/dev/null 2>&1; then
  code-review-graph build 2>&1 | tail -5
  ok "CRG graph built"
else
  skip "code-review-graph not installed"
fi

# ── 5. Git hooks (graphify + CRG, detached) ─────────────────────────────
echo ""
echo "5. Installing git hooks"
if [ -d "$REPO/.git" ]; then
  mkdir -p "$HOOKS_DIR"

  # Resource guard function shared by all hooks
  RESOURCE_GUARD='_resources_ok() {
  load=$(awk "{print \$1}" /proc/loadavg 2>/dev/null || echo 0)
  mem_free=$(awk "/MemAvailable/{print \$2}" /proc/meminfo 2>/dev/null || echo 999999)
  if awk "BEGIN{exit (!($load > 4.0))}"; then return 1; fi
  if [ "$mem_free" -lt 204800 ]; then return 1; fi
  return 0
}'

  # post-commit: CRG update (fast, ~0.4s) + graphify update (detached)
  cat > "$HOOKS_DIR/post-commit" << 'HOOKEOF'
#!/bin/sh
_resources_ok() {
  load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)
  mem_free=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo 999999)
  if awk "BEGIN{exit (!($load > 4.0))}"; then return 1; fi
  if [ "$mem_free" -lt 204800 ]; then return 1; fi
  return 0
}
_resources_ok || exit 0
# CRG: fast incremental
command -v code-review-graph >/dev/null 2>&1 && \
  nohup code-review-graph update --skip-flows >/dev/null 2>&1 &
# graphify: detached (slower, ~10s)
command -v graphify >/dev/null 2>&1 && \
  nohup graphify update . >/dev/null 2>&1 &
HOOKEOF
  chmod +x "$HOOKS_DIR/post-commit"
  ok "post-commit hook (CRG + graphify)"

  # post-checkout: same as post-commit
  cp "$HOOKS_DIR/post-commit" "$HOOKS_DIR/post-checkout"
  chmod +x "$HOOKS_DIR/post-checkout"
  ok "post-checkout hook"
else
  skip "not a git repo — no hooks installed"
fi

# ── 6. Claude Code hooks (settings.local.json) ──────────────────────────
echo ""
echo "6. Claude Code hooks"
SETTINGS_LOCAL="$CLAUDE_DIR/settings.local.json"
SETTINGS_EXAMPLE="$CLAUDE_DIR/settings.example.json"

# The hook config — CRG Stop hook only (graphify is git-hooks-only)
HOOK_JSON='{
  "hooks": {
    "PostToolUse": [],
    "Stop": [
      {
        "_comment": "CRG auto-update after AI turn — PID-guarded, no pile-up",
        "hooks": [{
          "type": "command",
          "command": "command -v code-review-graph >/dev/null 2>&1 && [ -d .code-review-graph ] && [ ! -f /tmp/crg-updating.pid ] && { echo $$ > /tmp/crg-updating.pid; code-review-graph update --skip-flows; rm -f /tmp/crg-updating.pid; } || true",
          "timeout": 5
        }]
      }
    ],
    "SessionStart": [
      {
        "_comment": "CRG graph status on session open",
        "hooks": [{
          "type": "command",
          "command": "command -v code-review-graph >/dev/null 2>&1 && code-review-graph status 2>/dev/null || true",
          "timeout": 10
        }]
      }
    ]
  }
}'

# Write example (committed reference)
echo "$HOOK_JSON" > "$SETTINGS_EXAMPLE"
ok "settings.example.json written"

# Write local (live) only if it doesn't exist
if [ ! -f "$SETTINGS_LOCAL" ]; then
  echo "$HOOK_JSON" > "$SETTINGS_LOCAL"
  ok "settings.local.json created"
else
  skip "settings.local.json already exists — not overwriting"
fi

# ── 7. Smart-grep hook (PreToolUse interceptor) ─────────────────────────
echo ""
echo "7. Smart-grep hook"
SMART_GREP="$HOME/.claude/scripts/smart-grep-hook.sh"
mkdir -p "$(dirname "$SMART_GREP")"
cat > "$SMART_GREP" << 'SGEOF'
#!/bin/sh
# smart-grep-hook.sh — PreToolUse interceptor
# Routes structural questions through CRG first, graphify on miss, grep as fallback.
# Installed as a PreToolUse hook in ~/.claude/settings.json
QUERY="$1"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

# If CRG graph exists, try semantic search first
if command -v code-review-graph >/dev/null 2>&1 && [ -d "$REPO_ROOT/.code-review-graph" ]; then
  result=$(code-review-graph query "$QUERY" 2>/dev/null)
  if [ -n "$result" ] && [ "$result" != "No results found" ]; then
    echo "$result"
    exit 0
  fi
fi

# Fallback: graphify query (if graph exists)
if command -v graphify >/dev/null 2>&1 && [ -f "$REPO_ROOT/graphify-out/graph.json" ]; then
  result=$(graphify query "$QUERY" --graph "$REPO_ROOT/graphify-out/graph.json" --budget 1500 2>/dev/null)
  if [ -n "$result" ]; then
    echo "$result"
    exit 0
  fi
fi

# Final fallback: let grep run normally
exit 1
SGEOF
chmod +x "$SMART_GREP"
ok "smart-grep-hook.sh at $SMART_GREP"

# ── 8. CRG_TOOLS env (strip 25 tools to 8) ──────────────────────────────
echo ""
echo "8. CRG tool allow-list"
CRG_TOOLS="semantic_search_nodes_tool,query_graph_tool,get_impact_radius_tool,traverse_graph_tool,list_communities_tool,get_community_tool,get_review_context_tool,list_graph_stats_tool"
# Write to shell profile if not already there
if ! grep -q "CRG_TOOLS" "$HOME/.zshrc" 2>/dev/null; then
  echo "" >> "$HOME/.zshrc"
  echo "# CRG tool allow-list (8 of 25 — 70% schema reduction)" >> "$HOME/.zshrc"
  echo "export CRG_TOOLS=\"$CRG_TOOLS\"" >> "$HOME/.zshrc"
  ok "CRG_TOOLS exported in .zshrc"
else
  skip "CRG_TOOLS already in .zshrc"
fi

# ── 9. Obsidian vault wiring ────────────────────────────────────────────
echo ""
echo "9. Obsidian vault links"
# Symlink graphify-out into the vault for Graph View
if [ -d "$GRAPHIFY_OUT" ] && [ ! -L "$VAULT_GRAPHS/graphify-out" ]; then
  ln -sf "$GRAPHIFY_OUT" "$VAULT_GRAPHS/graphify-out" 2>/dev/null && \
    ok "graphify-out symlinked into vault" || skip "symlink failed (storage permissions)"
else
  skip "graphify-out link already exists or dir missing"
fi

# ── 10. Ignore files ────────────────────────────────────────────────────
echo ""
echo "10. Ignore files"
cd "$REPO"
for f in .graphifyignore .code-review-graphignore; do
  [ -f "$f" ] || touch "$f"
done
# Ensure gitignore has the generated dirs
for entry in graphify-out/ .code-review-graph/ .claude/settings.local.json; do
  grep -qxF "$entry" .gitignore 2>/dev/null || echo "$entry" >> .gitignore
done
ok ".graphifyignore, .code-review-graphignore, .gitignore updated"

# ── 11. Verification ────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="

# Graphify
if [ -f "$GRAPHIFY_OUT/GRAPH_REPORT.md" ]; then
  nodes=$(grep -oP '\d+ nodes' "$GRAPHIFY_OUT/GRAPH_REPORT.md" | head -1)
  ok "graphify: $nodes"
else
  fail "graphify: no GRAPH_REPORT.md"
fi

# CRG
if command -v code-review-graph >/dev/null 2>&1; then
  code-review-graph status 2>/dev/null | head -5
else
  skip "CRG not installed"
fi

# Git hooks
[ -x "$HOOKS_DIR/post-commit" ] && ok "post-commit hook executable" || fail "post-commit hook missing"
[ -x "$HOOKS_DIR/post-checkout" ] && ok "post-checkout hook executable" || fail "post-checkout hook missing"

# Claude hooks
[ -f "$SETTINGS_EXAMPLE" ] && ok "settings.example.json present" || fail "settings.example.json missing"

# Smart-grep
[ -x "$SMART_GREP" ] && ok "smart-grep-hook.sh executable" || fail "smart-grep-hook.sh missing"

# Vault dirs
[ -d "$VAULT_MEMORIES" ] && ok "vault/memories/ exists" || fail "vault/memories/ missing"
[ -d "$VAULT_GRAPHS" ] && ok "vault/Codebase-Graphs/ exists" || fail "vault/Codebase-Graphs/ missing"

# OmniRoute
curl -sf "http://34.31.112.77:20128/api/monitoring/health" >/dev/null 2>&1 && \
  ok "OmniRoute VM healthy" || fail "OmniRoute VM not responding"

# mem0
echo '{"query":"test","top_k":1}' | timeout 5 curl -sf -X POST "https://mcp.mem0.ai/mcp" -d @- >/dev/null 2>&1 && \
  ok "mem0 cloud reachable" || skip "mem0 cloud — can't verify via curl (MCP protocol)"

echo ""
echo "=== Done ==="
echo "Next: run 'graphify update .' in any repo to add it to the graph"
echo "      run 'code-review-graph build' in any repo for CRG"
echo "      vault notes land in $VAULT_MEMORIES on every TB write"
