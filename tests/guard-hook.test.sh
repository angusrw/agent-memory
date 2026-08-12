#!/usr/bin/env bash
# Exercises the PreToolUse guard hook. Uses a throwaway vault path; runs no git
# commands of its own beyond creating an empty sandbox.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
G="$REPO/bin/guard-hook.sh"

TMP=$(mktemp -d)
export AGENT_MEMORY_VAULT="$TMP/vault"
V="$AGENT_MEMORY_VAULT"
mkdir -p "$V"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0

# payload <cwd> <command>
payload() {
  python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],
                  "tool_input":{"command":sys.argv[2]}}))' "$1" "$2"
}

expect() { # expect <blocked|allowed> <label> <cwd> <command>
  local want="$1" label="$2" cwd="$3" cmd="$4" got
  payload "$cwd" "$cmd" | "$G" >/dev/null 2>&1
  [ $? -eq 2 ] && got=blocked || got=allowed
  if [ "$got" = "$want" ]; then
    printf '  ok   %-46s %s\n' "$label" "$got"; pass=$((pass + 1))
  else
    printf '  FAIL %-46s want %s, got %s\n' "$label" "$want" "$got"; fail=$((fail + 1))
  fi
}

echo "guard-hook: should block"
expect blocked "git -C <vault> commit"        "$TMP"   "git -C $V commit -m x"
expect blocked "git -C <vault> push"          "$TMP"   "git -C $V push"
expect blocked "bare commit from inside"      "$V"     "git commit -m note"
expect blocked "add then commit from inside"  "$V"     "git add -A && git commit -q -m note"
expect blocked "push from a subdirectory"     "$V/sub" "git push"
expect blocked "amend from inside"            "$V"     "git commit --amend"
expect blocked "commit after a separator"     "$V"     "cd .; git commit -m x"

echo "guard-hook: should allow"
expect allowed "commit in an unrelated repo"  "$TMP"   "git commit -m x"
expect allowed "-C elsewhere from inside"     "$V"     "git -C $TMP/other commit -m x"
expect allowed "git status inside"            "$V"     "git status --short"
expect allowed "git log inside"               "$V"     "git log --oneline -3"
expect allowed "git diff inside"              "$V"     "git diff HEAD"
expect allowed "grep for the words"           "$TMP"   "grep -rn \"git commit\" $V"
expect allowed "echo mentioning both"         "$TMP"   "echo $V needs git push"
expect allowed "unrelated command inside"     "$V"     "ls -la"

echo "guard-hook: message"
msg=$(payload "$V" "git commit -m x" | "$G" 2>&1 >/dev/null)
if printf '%s' "$msg" | grep -q "Blocked"; then
  printf '  ok   %s\n' "explains why it blocked"; pass=$((pass + 1))
else
  printf '  FAIL %s\n' "explains why it blocked"; fail=$((fail + 1))
fi
# The message must name only the configured vault, never a baked-in home path.
if printf '%s' "$msg" | grep -qF "$V"; then
  printf '  ok   %s\n' "message names the configured vault"; pass=$((pass + 1))
else
  printf '  FAIL %s\n' "message names the configured vault"; fail=$((fail + 1))
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
