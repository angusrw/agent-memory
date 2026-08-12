#!/usr/bin/env bash
# Exercises install.sh against a fake HOME. Never touches the real ~/.claude.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
CLAUDE="$HOME/.claude"
SETTINGS="$CLAUDE/settings.json"
VAULT="$HOME/vault"
mkdir -p "$CLAUDE"

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; fail=$((fail + 1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2] got [$3]"; fi; }

hookcount() { # hookcount <event> <substring>
  python3 -c '
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print(0); sys.exit()
print(sum(1 for g in d.get("hooks",{}).get(sys.argv[2],[])
            for h in g.get("hooks",[]) if sys.argv[3] in h.get("command","")))' \
    "$SETTINGS" "$1" "$2"
}

# A pre-existing hook and setting that must survive.
cat > "$SETTINGS" <<'EOF'
{
  "model": "opus",
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "/existing/hook.sh", "async": true}]}
    ]
  }
}
EOF

echo "install.sh — dry run"
"$REPO/install.sh" --vault "$VAULT" --dry-run >/dev/null 2>&1
check "settings.json unchanged by dry run" "0" "$(hookcount SessionStart session-start-hook)"
check "no vault created by dry run" "no" "$([ -d "$VAULT" ] && echo yes || echo no)"
check "no skill link by dry run" "no" "$([ -e "$CLAUDE/skills/agent-memory" ] && echo yes || echo no)"

echo "install.sh — install"
"$REPO/install.sh" --vault "$VAULT" >/dev/null 2>&1
check "SessionStart hook added"      "1" "$(hookcount SessionStart session-start-hook)"
check "PreToolUse guard added"       "1" "$(hookcount PreToolUse guard-hook)"
check "existing hook preserved"      "1" "$(hookcount SessionStart /existing/hook.sh)"
check "unrelated settings preserved" "opus" \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("model",""))' "$SETTINGS")"
check "vault initialised"     "yes" "$([ -d "$VAULT/.git" ] && echo yes || echo no)"
check "vault has no remote"   ""    "$(git -C "$VAULT" remote)"
check "skill symlinked"       "yes" "$([ -L "$CLAUDE/skills/agent-memory" ] && echo yes || echo no)"
check "skill resolves"        "yes" "$([ -r "$CLAUDE/skills/agent-memory/SKILL.md" ] && echo yes || echo no)"
check "config written"        "yes" "$([ -f "$XDG_CONFIG_HOME/agent-memory/config" ] && echo yes || echo no)"
check "config records vault"  "VAULT=$VAULT" \
  "$(grep '^VAULT=' "$XDG_CONFIG_HOME/agent-memory/config")"
check "CLAUDE.md not created" "no" "$([ -e "$CLAUDE/CLAUDE.md" ] && echo yes || echo no)"
check "backup written"        "yes" \
  "$(ls "$CLAUDE"/settings.json.backup-* >/dev/null 2>&1 && echo yes || echo no)"

echo "install.sh — idempotency"
"$REPO/install.sh" --vault "$VAULT" >/dev/null 2>&1
check "no duplicate SessionStart" "1" "$(hookcount SessionStart session-start-hook)"
check "no duplicate PreToolUse"   "1" "$(hookcount PreToolUse guard-hook)"

echo "install.sh — uninstall"
touch "$VAULT/a-note.md"
"$REPO/install.sh" --uninstall >/dev/null 2>&1
check "SessionStart hook removed"  "0"   "$(hookcount SessionStart session-start-hook)"
check "PreToolUse guard removed"   "0"   "$(hookcount PreToolUse guard-hook)"
check "existing hook still there"  "1"   "$(hookcount SessionStart /existing/hook.sh)"
check "skill link removed"         "no"  "$([ -e "$CLAUDE/skills/agent-memory" ] && echo yes || echo no)"
check "config removed"             "no"  "$([ -f "$XDG_CONFIG_HOME/agent-memory/config" ] && echo yes || echo no)"
check "vault survives uninstall"   "yes" "$([ -f "$VAULT/a-note.md" ] && echo yes || echo no)"

echo "install.sh — malformed settings.json"
echo '{ not json' > "$SETTINGS"
if "$REPO/install.sh" --vault "$VAULT" >/dev/null 2>&1; then
  bad "refuses to run on invalid JSON" "it exited 0"
else
  ok "refuses to run on invalid JSON"
fi
check "invalid file left alone" "{ not json" "$(cat "$SETTINGS")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
