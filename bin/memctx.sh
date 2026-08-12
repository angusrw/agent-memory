#!/usr/bin/env bash
# Resolve memory context for a working directory.
# Usage: memctx.sh [--session <id>] [--cwd <path>] [--init]
# Prints shell-style KEY=value lines.

set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/_common.sh"

SESSION=""
CWD="$PWD"
INIT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --session) SESSION="${2:-}"; shift 2 ;;
    --cwd)     CWD="${2:-}"; shift 2 ;;
    --init)    INIT=1; shift ;;
    *)         shift ;;
  esac
done

# Repo identity: the MAIN worktree's directory name, so every worktree and
# branch of a repo shares one memory folder.
common_dir=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if [ -n "$common_dir" ]; then
  repo_root=$(dirname "$common_dir")
  repo=$(basename "$repo_root")
  branch=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)
  head=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null)
  worktree=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
else
  repo_root=""
  repo="_no-repo"
  branch=""
  head=""
  worktree="$CWD"
fi

# Pseudonym: deterministic from the session id, so it is stable for the whole
# session and needs no stored state. Purely for readability in the index.
ADJ=(amber ashen bright brisk calm clever coral dusk eager fleet glass grey
     hollow ivory keen lively mellow north opal pale quiet rapid sage slate
     still swift tawny umber vivid warm wild zinc)
ANI=(auk badger crane dipper eagle falcon gannet heron ibis jackdaw kite lynx
     marten newt otter petrel quail raven shrike tern urchin vole wren xerus
     yak zebu adder bittern chough dunlin egret finch)

if [ -n "$SESSION" ]; then
  h=$(printf '%s' "$SESSION" | shasum | cut -c1-8)
  n=$((16#$h))
else
  n=0
fi
agent="${ADJ[$(( n % ${#ADJ[@]} ))]}-${ANI[$(( (n / 32) % ${#ANI[@]} ))]}"

dir="$VAULT/$repo"

# --init makes the repo folder and seeds the index, so a first session in a new
# repo has somewhere to write. Idempotent; safe to run every time.
if [ "$INIT" -eq 1 ]; then
  if [ "$repo" = "_no-repo" ]; then
    echo "memctx.sh: --init needs a git repo; $CWD is not inside one" >&2
    exit 1
  fi
  mkdir -p "$dir"
  [ -f "$dir/_index.md" ] || printf '# %s\n\nSession notes, newest first.\n\n' "$repo" > "$dir/_index.md"
fi

printf 'VAULT=%s\n'     "$VAULT"
printf 'REPO=%s\n'      "$repo"
printf 'REPO_ROOT=%s\n' "$repo_root"
printf 'BRANCH=%s\n'    "$branch"
printf 'HEAD=%s\n'      "$head"
printf 'WORKTREE=%s\n'  "$worktree"
printf 'AGENT=%s\n'     "$agent"
printf 'DIR=%s\n'       "$dir"
printf 'INDEX=%s\n'     "$dir/_index.md"
printf 'DATE=%s\n'      "$(date +%Y-%m-%d)"
printf 'STAMP=%s\n'     "$(date +%Y-%m-%dT%H:%M)"
