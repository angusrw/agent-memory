#!/usr/bin/env bash
# Checks the vault for drift. Reports problems and changes nothing.
#
#   doctor.sh [<repo>]
#
# Exits 1 if anything is wrong, so it can gate a script or a hook.
#
# Checks, per repo folder:
#   - notes missing from _index.md, which hides them from future sessions
#   - index lines pointing at files that do not exist
#   - notes with frontmatter it cannot parse, or missing required keys
#   - archived notes still listed in the index
#   - a repo folder with no _index.md at all

set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/_common.sh"

REPO_FILTER="${1:-}"
[ -d "$VAULT" ] || { echo "vault not found: $VAULT" >&2; exit 1; }

python3 - "$VAULT" "$REPO_FILTER" <<'PY'
import os, re, sys

vault, repo_filter = sys.argv[1], sys.argv[2]
FM = re.compile(r"\A---\n(.*?)\n---\n", re.S)
REQUIRED = ("repo", "agent", "started", "status")
LINK = re.compile(r"\[\[([^\]]+)\]\]")

repos = sorted(
    d for d in os.listdir(vault)
    if os.path.isdir(os.path.join(vault, d)) and not d.startswith(".")
    and (not repo_filter or d == repo_filter)
)
if repo_filter and not repos:
    sys.exit(f"no such repo in vault: {repo_filter}")

problems = 0


def report(repo, kind, detail):
    global problems
    problems += 1
    print(f"{repo}: {kind}: {detail}")


for repo in repos:
    rdir = os.path.join(vault, repo)
    index_path = os.path.join(rdir, "_index.md")

    notes = sorted(n for n in os.listdir(rdir)
                   if n.endswith(".md") and not n.startswith("_"))

    if not os.path.exists(index_path):
        if notes:
            report(repo, "no index", f"{len(notes)} note(s) with no _index.md")
        continue

    index_text = open(index_path).read()
    linked = {t.split("|")[0].strip() for t in LINK.findall(index_text)}

    archived_slugs = set()
    for name in notes:
        slug = os.path.splitext(name)[0]
        text = open(os.path.join(rdir, name)).read()
        m = FM.match(text)
        if not m:
            report(repo, "no frontmatter", name)
            continue
        front = m.group(1)
        missing = [k for k in REQUIRED
                   if not re.search(rf"^{k}:\s*\S", front, re.M)]
        if missing:
            report(repo, "missing frontmatter", f"{name} lacks {', '.join(missing)}")
        if re.search(r"^archived:\s*true\s*$", front, re.M):
            archived_slugs.add(slug)
            if slug in linked:
                report(repo, "archived but indexed", name)
        elif slug not in linked:
            report(repo, "not indexed", f"{name}, no future session will see it")

    existing = {os.path.splitext(n)[0] for n in notes}
    for slug in sorted(linked - existing):
        report(repo, "dangling link", f"_index.md points at missing {slug}.md")

if problems == 0:
    scope = repo_filter or f"{len(repos)} repo(s)"
    print(f"ok, no problems found in {scope}")
    sys.exit(0)

print(f"\n{problems} problem(s) found")
sys.exit(1)
PY
