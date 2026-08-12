#!/usr/bin/env bash
# PreToolUse(Bash) hook. Blocks git commit and git push against the memory vault.
# The vault owner runs those by hand. Exit 2 rejects the tool call.

set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/_common.sh"

payload=$(cat 2>/dev/null)

read_field() {
  printf '%s' "$payload" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    for k in '$1'.split('.'):
        d = d.get(k, '') if isinstance(d, dict) else ''
    print(d or '')
except Exception:
    print('')
" 2>/dev/null
}

cmd=$(read_field tool_input.command)
cwd=$(read_field cwd)
[ -n "$cmd" ] || exit 0

# Match a real `git commit` or `git push` call only. git must sit in command
# position, at the start or after a separator, so quoted mentions of the words
# inside grep or echo arguments do not trip this.
printf '%s' "$cmd" \
  | grep -Eq '(^|[;&|(]|&&|\|\|)[[:space:]]*git([[:space:]]+-[A-Za-z-]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+(commit|push)\b' \
  || exit 0

# The command targets the vault if it names the vault, or if it runs from inside
# the vault without pointing -C somewhere else.
targets_vault=0
printf '%s' "$cmd" | grep -qF "$VAULT" && targets_vault=1

# Catch the tilde form of the configured vault path too.
vault_tilde="${VAULT/#$HOME/\~}"
if [ "$vault_tilde" != "$VAULT" ]; then
  printf '%s' "$cmd" | grep -qF "$vault_tilde" && targets_vault=1
fi

if [ "$targets_vault" -eq 0 ] && [ -n "$cwd" ]; then
  case "$cwd" in
    "$VAULT"|"$VAULT"/*)
      printf '%s' "$cmd" | grep -q '\-C ' || targets_vault=1
      ;;
  esac
fi

[ "$targets_vault" -eq 1 ] || exit 0

cat >&2 <<EOF
Blocked: do not commit or push the memory vault ($VAULT).

The vault owner commits and pushes it manually. Write the note and the index
line, leave them as unstaged changes, and say what you wrote.
EOF
exit 2
