#!/usr/bin/env bash
# agent-memory installer.
#
#   ./install.sh [--vault <path>] [--dry-run]
#   ./install.sh --uninstall [--dry-run]
#
# Installs:
#   1. a config file recording the vault and bin paths
#   2. the vault itself (git repo, created only if missing)
#   3. the skill, symlinked into ~/.claude/skills/agent-memory
#   4. two hooks merged into ~/.claude/settings.json
#
# It never edits your CLAUDE.md and never commits or pushes anything.
# --uninstall reverses steps 1, 3 and 4. It leaves the vault alone.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/agent-memory"
CONFIG="$CONFIG_DIR/config"
SKILL_LINK="$CLAUDE_DIR/skills/agent-memory"

VAULT_ARG=""
DRY_RUN=0
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --vault)     VAULT_ARG="${2:-}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
step() { printf '  %s\n' "$*"; }
run()  { if [ "$DRY_RUN" -eq 1 ]; then step "would: $*"; else "$@"; fi; }

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }
}
need git
need python3

# ---------------------------------------------------------------- settings.json

# Adds or removes our hook entries. Writes a timestamped backup first. Running it
# again adds nothing twice, and it keeps hooks you already have.
edit_settings() {
  local mode="$1"
  python3 - "$SETTINGS" "$mode" "$REPO" "$DRY_RUN" <<'PY'
import json, os, shutil, sys, time

path, mode, repo, dry = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
start_hook = os.path.join(repo, "bin", "session-start-hook.sh")
guard_hook = os.path.join(repo, "bin", "guard-hook.sh")

if os.path.exists(path):
    with open(path) as fh:
        try:
            settings = json.load(fh)
        except json.JSONDecodeError as exc:
            sys.exit(f"{path} is not valid JSON ({exc}); fix or move it first")
else:
    settings = {}

hooks = settings.setdefault("hooks", {})


def commands(event):
    return [h.get("command") for g in hooks.get(event, []) for h in g.get("hooks", [])]


def drop(event, command):
    groups = hooks.get(event)
    if not groups:
        return False
    kept = [g for g in groups
            if not any(h.get("command") == command for h in g.get("hooks", []))]
    if kept == groups:
        return False
    if kept:
        hooks[event] = kept
    else:
        hooks.pop(event, None)
    return True


changed = []
if mode == "install":
    if start_hook not in commands("SessionStart"):
        hooks.setdefault("SessionStart", []).append(
            {"hooks": [{"type": "command", "command": start_hook, "timeout": 10}]})
        changed.append("SessionStart")
    if guard_hook not in commands("PreToolUse"):
        hooks.setdefault("PreToolUse", []).append(
            {"matcher": "Bash",
             "hooks": [{"type": "command", "command": guard_hook, "timeout": 5}]})
        changed.append("PreToolUse")
else:
    if drop("SessionStart", start_hook):
        changed.append("SessionStart")
    if drop("PreToolUse", guard_hook):
        changed.append("PreToolUse")

if not hooks:
    settings.pop("hooks", None)

if not changed:
    print("  settings.json already correct, left alone")
    sys.exit(0)

if dry:
    print(f"  would update {path}: {', '.join(changed)}")
    sys.exit(0)

if os.path.exists(path):
    backup = f"{path}.backup-{time.strftime('%Y%m%d%H%M%S')}"
    shutil.copy2(path, backup)
    print(f"  backed up to {backup}")

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as fh:
    json.dump(settings, fh, indent=2)
    fh.write("\n")
print(f"  updated {path}: {', '.join(changed)}")
PY
}

# -------------------------------------------------------------------- uninstall

if [ "$UNINSTALL" -eq 1 ]; then
  say "Uninstalling agent-memory"

  step "removing hooks from settings.json"
  edit_settings remove

  if [ -L "$SKILL_LINK" ]; then
    step "removing skill symlink $SKILL_LINK"
    run rm "$SKILL_LINK"
  elif [ -e "$SKILL_LINK" ]; then
    step "$SKILL_LINK is not a symlink. Left in place, remove it yourself"
  else
    step "no skill symlink to remove"
  fi

  if [ -f "$CONFIG" ]; then
    step "removing $CONFIG"
    run rm "$CONFIG"
    rmdir "$CONFIG_DIR" 2>/dev/null || true
  fi

  say
  say "Your vault was not touched. Remove the CLAUDE.md block by hand if you added it."
  exit 0
fi

# ---------------------------------------------------------------------- install

# Resolve the vault from the flag, then the existing config, then the default.
VAULT="$VAULT_ARG"
if [ -z "$VAULT" ] && [ -f "$CONFIG" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG"
fi
VAULT="${VAULT:-$HOME/agent-memory-vault}"
case "$VAULT" in
  "~"/*) VAULT="$HOME/${VAULT#\~/}" ;;
esac

say "Installing agent-memory"
say "  repo:  $REPO"
say "  vault: $VAULT"
[ "$DRY_RUN" -eq 1 ] && say "  (dry run, nothing will be written)"
say

step "config"
run mkdir -p "$CONFIG_DIR"
if [ "$DRY_RUN" -eq 1 ]; then
  step "would write $CONFIG"
else
  cat > "$CONFIG" <<EOF
# agent-memory configuration. Written by install.sh; safe to edit.
VAULT=$VAULT
BIN=$REPO/bin
EOF
  step "wrote $CONFIG"
fi

step "vault"
if [ -d "$VAULT/.git" ]; then
  step "already a git repo, left alone"
else
  run mkdir -p "$VAULT"
  if [ "$DRY_RUN" -eq 0 ]; then
    git -C "$VAULT" init -q
    [ -f "$VAULT/.gitignore" ] || cat > "$VAULT/.gitignore" <<'EOF'
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/cache
.trash/
.DS_Store
EOF
    [ -f "$VAULT/README.md" ] || cat > "$VAULT/README.md" <<'EOF'
# memory vault

Session notes written by coding agents, one folder per repo, one file per session.
Created by agent-memory; see that repo for the layout and conventions.

Ground truth for a project goes in `<repo>/_intent.md`, hand-written by you.

Keep this repo private. It describes your work in detail.
EOF
    step "initialised git repo at $VAULT"
    step "no remote set. Add one yourself if you want a backup"
  fi
fi

step "skill"
run mkdir -p "$CLAUDE_DIR/skills"
if [ -e "$SKILL_LINK" ] && [ ! -L "$SKILL_LINK" ]; then
  echo "  $SKILL_LINK exists and is not a symlink. Move it and re-run" >&2
  exit 1
fi
run ln -sfn "$REPO/skill" "$SKILL_LINK"
step "linked $SKILL_LINK -> $REPO/skill"

step "hooks"
edit_settings install

say
say "Done."
say
say "One manual step left: paste the block from snippets/CLAUDE.md into"
say "$CLAUDE_DIR/CLAUDE.md. The installer will not edit that file for you."
say
say "Restart any running sessions to pick up the SessionStart hook."
