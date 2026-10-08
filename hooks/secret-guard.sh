#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (Bash, Read): refuse printing secret files and skipping git hooks.
in=$(cat); tool=$(jq -r .tool_name <<<"$in")
SECRET='((^|[/[:space:]"~])\.env(\.[a-z]+)?([[:space:]"]|$)|\.credentials|\.claude\.json|secrets\.env|gh/hosts\.yml|\.git-credentials|[A-Za-z0-9_-]\.pem([[:space:]"]|$)|[A-Za-z0-9_-]\.key([[:space:]"]|$)|vm-desktop-pass|[A-Za-z0-9_-]\.service([[:space:]"]|$))'
if [ "$tool" = Read ]; then
  f=$(jq -r '.tool_input.file_path // ""' <<<"$in")
  grep -qiE "$SECRET" <<<"$f" && { echo "BLOCKED (secret-guard): $f may hold secrets. Print key names only, values redacted (e.g. sed -E 's/=.*/=<redacted>/')." >&2; exit 2; }
  exit 0
fi
c=$(jq -r '.tool_input.command // ""' <<<"$in")
grep -qE -- 'git[^|;&]*(--no-verify|config[^|;&]*core\.hooksPath)' <<<"$c" && { echo "BLOCKED (secret-guard): skipping or changing git hooks is not allowed." >&2; exit 2; }
if grep -qiE "$SECRET" <<<"$c" && grep -qE '(^|[|;&[:space:]])(cat|head|tail|less|more|bat|jq|grep|sed|awk|strings|xxd)[[:space:]]' <<<"$c" \
   && ! grep -qE 'redact|<redacted>|cut -d=? ?-f1|keys' <<<"$c"; then
  echo "BLOCKED (secret-guard): this would print a secret file. Show key names only or redact values." >&2; exit 2
fi
exit 0
