#!/usr/bin/env bash
# End-to-end: run a real headless Claude Code session inside a sandbox git repo
# with the agent-memory hooks layered in via --settings, and a sandbox vault via
# AGENT_MEMORY_VAULT. Writes nothing to the real ~/.claude or any real vault.
#
# Needs an authenticated `claude` CLI, so it is NOT part of the CI suite and is
# not named *.test.sh. Run it by hand:  bash tests/e2e.sh

set -uo pipefail

TOOL="$(cd "$(dirname "$0")/.." && pwd)"
E2E=$(mktemp -d)
VAULT="$E2E/vault"
export AGENT_MEMORY_VAULT="$VAULT"

echo "sandbox: $E2E"
echo

echo "=== 1. sandbox project repo"
PROJ="$E2E/widget-service"
git init -q "$PROJ"
git -C "$PROJ" config user.email t@example.com
git -C "$PROJ" config user.name tester
git -C "$PROJ" commit -q --allow-empty -m init
echo "    $PROJ"

echo
echo "=== 2. sandbox vault"
mkdir -p "$VAULT/widget-service"
cat > "$VAULT/widget-service/_intent.md" <<'EOF'
# Intent — widget-service

## Goal
Serve widgets over HTTP with a strict 50ms p99.

## Not doing
- GraphQL — rejected, the client only ever needs one shape.
EOF
cat > "$VAULT/widget-service/_index.md" <<'EOF'
# widget-service

Session notes, newest first.

- [[2026-01-15-sage-heron-cache-layer]] — added an LRU in front of the widget store; `status: handoff`, eviction metric still unwired
EOF
echo "    _intent.md + _index.md seeded"

echo
echo "=== 3. standalone settings with only the agent-memory hooks"
SETTINGS="$E2E/settings.json"
cat > "$SETTINGS" <<EOF
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "$TOOL/bin/session-start-hook.sh", "timeout": 10}]}
    ],
    "PreToolUse": [
      {"matcher": "Bash",
       "hooks": [{"type": "command", "command": "$TOOL/bin/guard-hook.sh", "timeout": 5}]}
    ]
  }
}
EOF
echo "    $SETTINGS"

echo
echo "=== 4. headless session inside the project repo"
PROMPT='Answer these three questions in one short line each, no preamble, using only
the context you were given at session start. Do not use any tools.
1. What repo name appears in a "Session memory" block?
2. What is the single index entry about?
3. What does a "Ground truth" block say is NOT being done?
If a block is absent, answer NONE for that question.'

cd "$PROJ" || exit 1
OUT=$(claude -p "$PROMPT" --settings "$SETTINGS" 2>&1)
RC=$?
echo "    exit: $RC"
echo
echo "--- model output ---"
printf '%s\n' "$OUT"
echo "--------------------"

echo
echo "=== 5. verdict"
fail=0
check() {
  if printf '%s' "$OUT" | grep -qiF "$2"; then
    echo "    ok   $1"
  else
    echo "    FAIL $1 (expected: $2)"
    fail=1
  fi
}
check "SessionStart hook fired for the sandbox repo" "widget-service"
check "index entry reached the model"                "eviction"
check "intent doc reached the model"                 "GraphQL"

echo
echo "=== 6. real vault untouched"
if [ -e "$HOME/agent-memory-vault" ]; then
  echo "    note: $HOME/agent-memory-vault exists (default path) — check it was not written"
else
  echo "    ok   no default vault created in \$HOME"
fi

echo
if [ "$fail" -eq 0 ]; then echo "END-TO-END PASS"; else echo "END-TO-END FAIL"; fi
echo "sandbox left at $E2E"
