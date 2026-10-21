#!/data/data/com.termux/files/usr/bin/bash
# H9 carry-over ledger (observation 0030). A START HERE item that a session leaves unfinished is
# "carried over". The Stop gate reads this to refuse a second deferral without the operator's reason.
# Sourced by stop-gate.sh; also a CLI: carryover.sh list <snapshot> [sid]  (prints carried items).
# Ledger: ~/.claude/state/carryover/<sid>.tsv, one per session, rewritten on every wrap-up Stop run:
#   key \t status \t date \t title     (status: deferred | open; confirmed-done items are left out)
# Items match across sessions by key: the title lowercased, markdown and punctuation dropped, first
# 40 letters/digits. A reworded title is a new item, so RESUME rewrites must keep item titles.
co_dir="$HOME/.claude/state/carryover"

co_key() { sed -E 's/\*\*|`|\[|\]//g' <<<"$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-40; }

# co_items SNAPSHOT -> "n \t title" for each numbered START HERE item
co_items() {
  awk '/^#+ .*START HERE/{f=1;next} f&&/^#/{exit} f&&/^[0-9]+\. /{n=$0; sub(/\..*/,"",n); t=$0; sub(/^[0-9]+\. /,"",t); print n "\t" t}' "$1"
}

# co_prior KEY SID -> how many OTHER sessions left this item unfinished
co_prior() {
  [ -n "$1" ] && [ -d "$co_dir" ] || { echo 0; return; }
  grep -lF -- "$1	" "$co_dir"/*.tsv 2>/dev/null | grep -vF -- "/$2.tsv" | while read -r f; do
    awk -F'\t' -v k="$1" '$1==k{print; exit}' "$f"; done | grep -c .
}

# co_record SID SNAPSHOT CONFIRM_TSV -> rewrite this session's ledger from the operator's latest marks
co_record() {
  local sid=$1 snap=$2 conf=$3 n t last k
  mkdir -p "$co_dir"
  co_items "$snap" | while IFS=$'\t' read -r n t; do
    last=$(grep "^$n	" "$conf" 2>/dev/null | tail -1 | cut -f2)
    [ "$last" = confirmed-done ] && continue
    k=$(co_key "$t"); [ -n "$k" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$k" "$( [ "$last" = deferred ] && echo deferred || echo open)" "$(date +%F)" "$t"
  done > "$co_dir/$sid.tsv.tmp" && mv "$co_dir/$sid.tsv.tmp" "$co_dir/$sid.tsv"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case $1 in
    list) [ -f "$2" ] || { echo "usage: carryover.sh list <snapshot> [sid]" >&2; exit 1; }
          co_items "$2" | while IFS=$'\t' read -r n t; do
            c=$(co_prior "$(co_key "$t")" "${3:-none}"); [ "$c" -gt 0 ] && printf '%s\t%s\t%s\n' "$n" "$c" "$t"; done ;;
    *) echo "usage: carryover.sh list <snapshot> [sid]" >&2; exit 1 ;;
  esac
fi
