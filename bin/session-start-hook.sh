#!/usr/bin/env bash
# SessionStart hook: surface the repo's intent doc and session-memory index.
# Reads the hook JSON payload on stdin. Silent outside a git repo.

set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/_common.sh"

BIN="$(cd "$(dirname "$0")" && pwd)"
MAX_ENTRIES=30
MAX_INTENT_BYTES=8192

payload=$(cat 2>/dev/null)

read_field() {
  printf '%s' "$payload" | python3 -c "
import json,sys
try:
    print(json.load(sys.stdin).get('$1','') or '')
except Exception:
    print('')
" 2>/dev/null
}

cwd=$(read_field cwd)
[ -n "$cwd" ] || cwd="$PWD"

# The index is shared across every worktree of a repo, so key it on the common dir.
common_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[ -n "$common_dir" ] || exit 0
repo=$(basename "$(dirname "$common_dir")")

# The intent doc lives in the vault, never in the project repo. A branch-specific
# file wins over the repo-wide one when it exists.
branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
branch_slug=$(printf '%s' "$branch" | tr '/' '-')

intent=""
for candidate in "_intent.$branch_slug.md" "_intent.md"; do
  if [ -f "$VAULT/$repo/$candidate" ]; then
    intent="$VAULT/$repo/$candidate"
    break
  fi
done

index="$VAULT/$repo/_index.md"

if [ -n "$intent" ]; then
  changed=$(git -C "$VAULT" log -1 --format='%ad' --date=short -- "$intent" 2>/dev/null)
  size=$(wc -c < "$intent" 2>/dev/null | tr -d ' ')
  size=${size:-0}

  echo "## Ground truth — $repo${branch:+ ($branch)}"
  echo

  # Inline the doc so it is actually in context. A pointer alone makes the
  # highest-authority document the least reliably read one. Oversized docs fall
  # back to a pointer rather than flooding every session in the repo.
  if [ "$size" -le "$MAX_INTENT_BYTES" ]; then
    echo "From \`$intent\` — the source of truth for what this project is trying to do."
    [ -n "$changed" ] && echo "Last changed $changed."
    echo
    cat "$intent"
    echo
  else
    echo "\`$intent\` is the source of truth for what this project is trying to do."
    [ -n "$changed" ] && echo "Last changed $changed."
    echo "It is $size bytes, too long to inline — read it before planning."
    echo
  fi

  echo "If the code, a session note, or the user's request contradicts it, say so and"
  echo "stop — do not silently reconcile. Edit it only when explicitly asked to."
  echo
fi

# grep -c prints 0 and exits 1 when there are no matches, so `|| echo 0` would
# append a second 0 and make this a non-integer. Take the output as-is.
entries=0
[ -f "$index" ] && entries=$(grep -c '^- ' "$index" 2>/dev/null)
entries=${entries:-0}

echo "## Session memory — $repo"
echo

if [ "$entries" -gt 0 ]; then
  echo "Prior sessions in this repo (newest first). Read the linked note before"
  echo "starting related work; these are notes from past sessions, not ground truth."
  echo
  grep '^- ' "$index" 2>/dev/null | head -n "$MAX_ENTRIES"

  if [ "$entries" -gt "$MAX_ENTRIES" ]; then
    echo
    echo "_($((entries - MAX_ENTRIES)) older entries omitted — see $index)_"
  fi
  echo
  echo "Notes live in \`$VAULT/$repo/\`. Use the agent-memory skill to write yours."
else
  echo "No session notes for this repo yet — this is the first."
  echo
  echo "If this session produces a decision, a non-obvious change, or a rejected"
  echo "approach, create the folder and write one. Otherwise leave it alone:"
  echo
  echo '```bash'
  echo "$BIN/memctx.sh --init --session \"\$CLAUDE_SESSION_ID\""
  echo '```'
  echo
  echo "That makes \`$VAULT/$repo/\` and seeds \`_index.md\`. Then use the"
  echo "agent-memory skill to write the note."
fi
