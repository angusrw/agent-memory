#!/usr/bin/env bash
# Archive finished session notes: set `archived: true` in their frontmatter and
# drop their line from the index. Files stay where they are, so `continues:`
# wikilinks between notes keep working.
#
#   archive.sh [<repo>] [--days N] [--apply]
#
# Defaults to a dry run over every repo in the vault. Nothing is written without
# --apply. A note is archivable when status is `done` and `updated` is older than
# N days (default 30).

set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/_common.sh"

REPO_FILTER=""
DAYS=30
APPLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --days)  DAYS="${2:-30}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)      echo "unknown argument: $1" >&2; exit 1 ;;
    *)       REPO_FILTER="$1"; shift ;;
  esac
done

[ -d "$VAULT" ] || { echo "vault not found: $VAULT" >&2; exit 1; }

python3 - "$VAULT" "$REPO_FILTER" "$DAYS" "$APPLY" <<'PY'
import datetime, os, re, sys

vault, repo_filter, days, apply = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4] == "1"
cutoff = datetime.date.today() - datetime.timedelta(days=days)

FM = re.compile(r"\A---\n(.*?)\n---\n", re.S)


def field(front, key):
    m = re.search(rf"^{key}:\s*(.+?)\s*$", front, re.M)
    return m.group(1).strip() if m else ""


def note_date(value):
    try:
        return datetime.date.fromisoformat(value[:10])
    except ValueError:
        return None


repos = sorted(
    d for d in os.listdir(vault)
    if os.path.isdir(os.path.join(vault, d)) and not d.startswith(".")
    and (not repo_filter or d == repo_filter)
)
if repo_filter and not repos:
    sys.exit(f"no such repo in vault: {repo_filter}")

total = 0
for repo in repos:
    rdir = os.path.join(vault, repo)
    index_path = os.path.join(rdir, "_index.md")
    archived = []

    for name in sorted(os.listdir(rdir)):
        if not name.endswith(".md") or name.startswith("_"):
            continue
        path = os.path.join(rdir, name)
        text = open(path).read()
        m = FM.match(text)
        if not m:
            continue
        front = m.group(1)
        if field(front, "status") != "done":
            continue
        if field(front, "archived") == "true":
            continue
        stamp = note_date(field(front, "updated") or field(front, "started"))
        if stamp is None or stamp > cutoff:
            continue

        archived.append(name)
        if apply:
            new_front = front + "\narchived: true"
            open(path, "w").write(text.replace(m.group(0), f"---\n{new_front}\n---\n", 1))

    if not archived:
        continue

    slugs = {os.path.splitext(n)[0] for n in archived}
    if os.path.exists(index_path):
        lines = open(index_path).read().splitlines(keepends=True)
        kept = [ln for ln in lines
                if not (ln.startswith("- ") and any(s in ln for s in slugs))]
        if apply and kept != lines:
            open(index_path, "w").writelines(kept)

    total += len(archived)
    print(f"{repo}: {len(archived)} note(s)")
    for name in archived:
        print(f"  {name}")

if total == 0:
    print(f"nothing to archive (status: done, updated before {cutoff})")
elif not apply:
    print(f"\ndry run — {total} note(s) would be archived. Re-run with --apply.")
else:
    print(f"\narchived {total} note(s); files left in place, index lines removed")
PY
