#!/usr/bin/env bash
# Exercises the SessionStart hook and memctx.sh against throwaway repos and a
# throwaway vault. Touches nothing outside its own temp directories.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
H="$REPO/bin/session-start-hook.sh"
M="$REPO/bin/memctx.sh"

TMP=$(mktemp -d)
export AGENT_MEMORY_VAULT="$TMP/vault"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
check() { # check <label> <expected-substring> <actual>
  if printf '%s' "$3" | grep -qF "$2"; then
    printf '  ok   %s\n' "$1"; pass=$((pass + 1))
  else
    printf '  FAIL %s\n       expected to contain: %s\n       got: %s\n' "$1" "$2" "$3"
    fail=$((fail + 1))
  fi
}
check_empty() {
  if [ -z "$2" ]; then printf '  ok   %s\n' "$1"; pass=$((pass + 1))
  else printf '  FAIL %s\n       expected empty, got: %s\n' "$1" "$2"; fail=$((fail + 1)); fi
}
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; fail=$((fail + 1)); }

fire() { printf '{"cwd":"%s"}' "$1" | "$H"; }

git init -q "$TMP/proj"
git -C "$TMP/proj" config user.email t@example.com
git -C "$TMP/proj" config user.name tester
git -C "$TMP/proj" commit -q --allow-empty -m init
D="$AGENT_MEMORY_VAULT/proj"

echo "session-start-hook"

check "first session prompts to create the folder" \
  "No session notes for this repo yet" "$(fire "$TMP/proj")"
check "first session gives the --init command" \
  "memctx.sh --init" "$(fire "$TMP/proj")"

check_empty "silent outside a git repo" "$(fire "$TMP")"

"$M" --init --session s --cwd "$TMP/proj" >/dev/null
check "--init creates the index" "# proj" "$(cat "$D/_index.md")"

"$M" --init --session s --cwd "$TMP/proj" >/dev/null
check "--init is idempotent" "1" "$(grep -c '^# proj' "$D/_index.md")"

check "seeded but empty index still prompts" \
  "No session notes for this repo yet" "$(fire "$TMP/proj")"

printf -- '- [[a-note]] — did a thing\n' >> "$D/_index.md"
check "index entries are listed" "did a thing" "$(fire "$TMP/proj")"

printf '# Intent\n\n## Not doing\n- GraphQL — rejected, one shape only.\n' > "$D/_intent.md"
check "intent doc surfaces" "Ground truth — proj" "$(fire "$TMP/proj")"
check "intent doc path is shown" "_intent.md" "$(fire "$TMP/proj")"
check "intent doc CONTENTS are inlined" "GraphQL — rejected" "$(fire "$TMP/proj")"

# Oversized docs must degrade to a pointer, not flood every session.
python3 -c "open('$D/_intent.md','w').write('# Intent\n\nBLOATED ' + 'x'*9000 + '\n')"
out=$(fire "$TMP/proj")
check "oversized doc is not inlined" "too long to inline" "$out"
if printf '%s' "$out" | grep -qF "BLOATED"; then
  bad "oversized doc body withheld" "contents were inlined anyway"
else
  ok "oversized doc body withheld"
fi
printf '# Intent\n\n## Not doing\n- GraphQL — rejected, one shape only.\n' > "$D/_intent.md"

git -C "$TMP/proj" worktree add -q "$TMP/proj-feat" -b feature/x 2>/dev/null
check "worktree shares the repo folder" "Session memory — proj" "$(fire "$TMP/proj-feat")"
check "worktree without override gets the repo-wide doc" \
  "proj/_intent.md" "$(fire "$TMP/proj-feat")"

echo "# Intent, branch" > "$D/_intent.feature-x.md"
check "branch override wins on the branch" \
  "_intent.feature-x.md" "$(fire "$TMP/proj-feat")"
check "branch override does not leak to main" \
  "proj/_intent.md" "$(fire "$TMP/proj" | grep 'source of truth')"

echo "memctx"
ctx=$("$M" --session abc --cwd "$TMP/proj")
check "reports the repo" "REPO=proj" "$ctx"
check "reports the vault" "VAULT=$AGENT_MEMORY_VAULT" "$ctx"
check "pseudonym is deterministic" \
  "$(printf '%s' "$ctx" | grep '^AGENT=')" \
  "$("$M" --session abc --cwd "$TMP/proj" | grep '^AGENT=')"
check "no-repo directories are handled" "REPO=_no-repo" "$("$M" --session s --cwd "$TMP")"

echo "isolation"
check_empty "project repo untouched" "$(git -C "$TMP/proj" status --porcelain)"
check_empty "no stderr from a normal fire" \
  "$(printf '{"cwd":"%s"}' "$TMP/proj" | "$H" 2>&1 >/dev/null)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
