#!/usr/bin/env bash
# Exercises archive.sh and doctor.sh against a throwaway vault.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
A="$REPO/bin/archive.sh"
D="$REPO/bin/doctor.sh"
M="$REPO/bin/memctx.sh"

TMP=$(mktemp -d)
export AGENT_MEMORY_VAULT="$TMP/vault"
V="$AGENT_MEMORY_VAULT"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; fail=$((fail + 1)); }
has() { if printf '%s' "$3" | grep -qF "$2"; then ok "$1"; else bad "$1" "missing [$2] in: $3"; fi; }
hasnt() { if printf '%s' "$3" | grep -qF "$2"; then bad "$1" "unexpected [$2]"; else ok "$1"; fi; }

note() { # note <file> <status> <updated> [extra-frontmatter]
  cat > "$V/proj/$1" <<EOF
---
repo: proj
agent: sage-heron
started: $3
updated: $3
status: $2
${4:-}
---

## Open
- nothing
EOF
}

mkdir -p "$V/proj"
OLD=$(python3 -c 'import datetime;print(datetime.date.today()-datetime.timedelta(days=90))')
NEW=$(python3 -c 'import datetime;print(datetime.date.today()-datetime.timedelta(days=2))')

note "2020-01-01-a-old-done.md"   "done"   "$OLD"
note "2020-01-02-b-new-done.md"   "done"   "$NEW"
note "2020-01-03-c-old-active.md" active "$OLD"

cat > "$V/proj/_index.md" <<'EOF'
# proj

- [[2020-01-01-a-old-done]] — old and finished
- [[2020-01-02-b-new-done]] — recent and finished
- [[2020-01-03-c-old-active]] — old but still open
EOF

echo "archive.sh"
out=$("$A" proj)
has  "dry run names the eligible note"   "2020-01-01-a-old-done.md" "$out"
hasnt "dry run skips recent done notes"  "b-new-done" "$out"
hasnt "dry run skips active notes"       "c-old-active" "$out"
has  "dry run says it is a dry run"      "dry run" "$out"
hasnt "dry run did not edit the note"    "archived: true" "$(cat "$V/proj/2020-01-01-a-old-done.md")"
has  "dry run left the index alone"      "a-old-done" "$(cat "$V/proj/_index.md")"

out=$("$A" proj --apply)
has  "apply reports what it did"    "archived 1 note" "$out"
has  "apply sets archived: true"    "archived: true" "$(cat "$V/proj/2020-01-01-a-old-done.md")"
hasnt "apply removed the index line" "a-old-done" "$(cat "$V/proj/_index.md")"
has  "apply left the file in place" "yes" "$([ -f "$V/proj/2020-01-01-a-old-done.md" ] && echo yes)"
has  "other index lines survive"    "b-new-done" "$(cat "$V/proj/_index.md")"

out=$("$A" proj --apply)
has "second run is a no-op" "nothing to archive" "$out"

out=$("$A" proj --days 1 2>&1)
has "--days widens the window" "b-new-done" "$out"

echo "doctor.sh"
out=$("$D" proj); rc=$?
has "clean vault passes" "ok — no problems" "$out"
if [ "$rc" -eq 0 ]; then ok "clean vault exits 0"; else bad "clean vault exits 0" "got $rc"; fi

note "2020-01-04-d-orphan.md" active "$NEW"
out=$("$D" proj); rc=$?
has "unindexed note is reported" "not indexed" "$out"
if [ "$rc" -eq 1 ]; then ok "problems exit 1"; else bad "problems exit 1" "got $rc"; fi

printf -- '- [[2020-01-04-d-orphan]] — now indexed\n' >> "$V/proj/_index.md"
out=$("$D" proj)
has "indexing it clears the problem" "ok — no problems" "$out"

printf -- '- [[2020-01-09-z-missing]] — never existed\n' >> "$V/proj/_index.md"
has "dangling index link is reported" "dangling link" "$("$D" proj)"
sed -i.bak '/z-missing/d' "$V/proj/_index.md" && rm -f "$V/proj/_index.md.bak"

printf -- '- [[2020-01-01-a-old-done]] — back from the dead\n' >> "$V/proj/_index.md"
has "archived-but-indexed is reported" "archived but indexed" "$("$D" proj)"
sed -i.bak '/back from the dead/d' "$V/proj/_index.md" && rm -f "$V/proj/_index.md.bak"

printf 'no frontmatter here\n' > "$V/proj/2020-01-05-e-broken.md"
has "missing frontmatter is reported" "no frontmatter" "$("$D" proj)"
rm "$V/proj/2020-01-05-e-broken.md"

note "2020-01-06-f-partial.md" active "$NEW"
python3 - "$V/proj/2020-01-06-f-partial.md" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write(re.sub(r"^agent:.*\n", "", s, count=1, flags=re.M))
PY
has "missing required key is reported" "lacks agent" "$("$D" proj)"
rm "$V/proj/2020-01-06-f-partial.md"

echo "memctx --init guard"
out=$("$M" --init --session s --cwd "$TMP" 2>&1); rc=$?
has "refuses to init outside a repo" "needs a git repo" "$out"
if [ "$rc" -eq 1 ]; then ok "exits 1 outside a repo"; else bad "exits 1 outside a repo" "got $rc"; fi
hasnt "no _no-repo folder created" "_no-repo" "$(ls "$V")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
