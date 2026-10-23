#!/data/data/com.termux/files/usr/bin/bash
# H7 classifier. Contract: Aesop-Xi/protocol/classify.md
# stdin:  {"prompt": "...", "cwd": "...", "loaded_skills": ["..."]}
# stdout: {"backend": "...", "required": [{"id","require","scope"}]}
# Backend: $CLASSIFY_URL (POST, 2 s timeout) if set and it answers with valid JSON,
# else the keyword rows in ENFORCEMENTS.md. Never fails: worst case prints an empty list.
in=$(cat)
REG=${ENFORCEMENTS_FILE:-$HOME/.claude/ENFORCEMENTS.md}

if [ -n "$CLASSIFY_URL" ]; then
  out=$(curl -s --max-time 2 -H 'Content-Type: application/json' -d "$in" "$CLASSIFY_URL" 2>/dev/null)
  if jq -e '.required|type=="array"' <<<"$out" >/dev/null 2>&1; then
    jq -c '. + {backend: "remote"}' <<<"$out"; exit 0
  fi
fi

# Lowercase, and drop path-like tokens (anything with a /) so words inside
# paths such as .../com.termux/... never count as keywords.
prompt=$(jq -r '.prompt // ""' <<<"$in" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^[:space:]]*/[^[:space:]]*# #g')
# Command text for mode=command rows: a verb plus the next 6 words (a sentence break ends the window),
# or the whole prompt when it is short (6 words or fewer, no "?"). A passing mention has no verb in front.
verbs='run|build|install|fix|test|load|start|stop|set|setup|create|make|add|write|update|edit|debug|deploy|configure|convert|download|compile|flash|launch|enable|measure|profile'
pc=$(grep -oE "(^|[^a-z0-9])($verbs)([ ,]+[^ ,.?!;:]+){0,6}" <<<"$prompt" | tr '\n' ' ')
[ "$(wc -w <<<"$prompt")" -le 6 ] && [[ $prompt != *\?* ]] && pc=$prompt
cwd=$(jq -r '.cwd // ""' <<<"$in")
repo=$(git -C "${cwd:-/}" rev-parse --show-toplevel 2>/dev/null); repo=${repo##*/}
case $cwd in */NovAExorpus*) repo=vault ;; esac

[ -f "$REG" ] || { echo '{"backend":"keywords","required":[]}'; exit 0; }
awk -F'|' -v p=" $prompt " -v pc=" $pc " -v repo="$repo" '
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  NF >= 6 {
    id = trim($2); when = trim($3); req = trim($4); scope = trim($5); mode = trim($7)   # mode column is last; absent/empty = always
    if (id == "id" || id ~ /^-+$/ || id == "") next
    hit = 0
    if (when ~ /^kw:/) {
      n = split(substr(when, 4), kws, ",")
      for (i = 1; i <= n; i++) {
        k = tolower(trim(kws[i])); if (k == "") continue
        gsub(/[.]/, "\\.", k)
        if ((mode == "command" ? pc : p) ~ ("[^a-z0-9]" k "[^a-z0-9]")) { hit = 1; break }
      }
    } else if (when ~ /^repo:/) {
      if (trim(substr(when, 6)) == repo) hit = 1
    }
    if (hit) printf "%s\t%s\t%s\n", id, req, (scope == "" ? "session" : scope)
  }' "$REG" | jq -R -s -c '{backend: "keywords", required: [split("\n")[] | select(length > 0) | split("\t") | {id: .[0], require: .[1], scope: .[2]}]}'
