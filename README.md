# agent-memory

Persistent memory for coding agents. One session writes down what it did, and the
next session reads it. Notes live in a git repo you own, outside the projects they
describe.

It solves two problems:

- **Handoff.** An agent that finishes work knows what it tried, what it rejected, and
  what it left half-done. The next agent knows none of that. Git records what changed.
  It does not record why.
- **Recall.** Writing notes is easy. Getting them read is the hard part. A
  `SessionStart` hook injects the index at the start of every session, so nothing
  depends on an agent choosing to look.

Built for [Claude Code](https://claude.com/claude-code). Needs bash, git and
`python3`.

## Layout

Nothing goes into your project repos. The vault holds everything:

```
<vault>/
  <repo-name>/
    _intent.md                             # ground truth, written by you
    _intent.<branch>.md                    # optional per-branch override
    _index.md                              # one line per note, newest first
    2026-01-15-sage-heron-auth-refactor.md # one file per session
```

One folder per repo. Every worktree and branch of that repo shares it, so an agent in
one worktree sees what an agent in another wrote. `git rev-parse --git-common-dir`
resolves the identity, which maps linked worktrees back to the main repo.

One file per session. Two agents in the same worktree write two files, so they never
overwrite each other and git never sees a content conflict. `_index.md` is the only
file that can conflict, and you resolve it by keeping both lines.

## Note format

```yaml
---
repo: myproject
branch: feature/auth
worktree: /home/you/code/myproject
agent: sage-heron
session: <session id>
started: 2026-01-15T14:22
updated: 2026-01-15T16:05
head: a1b2c3d
status: active        # active | handoff | done
tags: [refactor]      # feat fix refactor investigation spike chore
continues: "[[2026-01-13-amber-vole-auth-spike]]"
---
```

Sections run Open, Goal, Decisions, Changed, Don't.

`head` records the repo HEAD at the last update. Run `git diff <head>..HEAD` to see
what moved since. That makes *Changed* checkable instead of a claim.

`agent` is an adjective-animal pseudonym, derived from the session id by hash. It
makes the index readable when several agents work on the same day. It implies no
continuity: a fresh agent remembers nothing of an earlier one.

Put **Open** first. It is what a new agent needs, and it is the section most likely to
get skipped, because the agent writing it already knows what is in flight.

## Ground truth

Session notes are dated reports. They go stale and they carry no authority.

`<repo>/_intent.md` carries it. You write it by hand: the goal, the constraints, and
the directions you rejected. Agents read it and defer to it. They do not edit it
unless you ask, and not as a side effect of the work it describes.

Precedence, highest first: **your instruction, then the intent doc, then the code,
then session notes.**

An agent that finds the code or a note contradicting the intent doc says so and stops
instead of reconciling on its own. Start from `skill/templates/INTENT.md`.

The hook inlines the whole doc at session start. A pointer on its own leaves your
highest authority as the one file nobody reads. Docs over 8KB fall back to a pointer
so they do not flood every session in that repo.

Keep it to a page. A long intent doc goes stale, and a stale one does more damage than
none, because you have told agents to trust it.

## Flow

```
session starts in a git repo
  └─ SessionStart hook fires
       ├─ resolves the repo via `git rev-parse --git-common-dir`
       ├─ inlines _intent.md if present    (branch override wins, 8KB cap)
       └─ injects _index.md if present     (last 30 lines)
            └─ no folder yet? says so, and gives the --init command
  └─ agent reads intent, opens only the notes that look relevant
  └─ agent works
  └─ agent runs `memctx.sh --init` before its first write
       └─ creates <repo>/ and seeds _index.md, idempotent
  └─ agent writes <date>-<agent>-<slug>.md as it goes, not at the end
       ├─ Open / Goal / Decisions / Changed / Don't
       └─ adds one line to _index.md
  └─ leaves everything unstaged
  └─ guard hook rejects any commit or push of the vault
  └─ you commit
```

Outside a git repo the hook stays silent.

## Install

```bash
git clone https://github.com/angusrw/agent-memory
cd agent-memory
./install.sh --vault ~/notes/memory
```

`--vault` defaults to `~/agent-memory-vault`. Add `--dry-run` to see what it would do
first.

The installer writes a config file, creates the vault as a git repo if it is missing,
symlinks the skill into `~/.claude/skills/agent-memory`, and merges two hooks into
`~/.claude/settings.json`. It backs that file up first, keeps hooks you already have,
and adds nothing twice on a re-run.

**One manual step.** Paste the block from [`snippets/CLAUDE.md`](snippets/CLAUDE.md)
into your `~/.claude/CLAUDE.md`. The installer leaves that file alone, because it is
yours and has your own structure.

Restart running sessions afterwards. Claude Code reloads hook config live, but it
reads `CLAUDE.md` and fires `SessionStart` only when a session starts.

`install.sh` sets no remote on the vault. Add one if you want a backup, and make it
private. The vault describes your work in detail.

### Uninstall

```bash
./install.sh --uninstall
```

This removes the hooks, the skill link, and the config. It leaves your vault alone.
Remove the `CLAUDE.md` block by hand.

## Machinery

| Piece | Role |
|---|---|
| `bin/memctx.sh` | Resolves vault, repo, branch, HEAD, pseudonym, paths. `--init` seeds the folder |
| `bin/session-start-hook.sh` | `SessionStart`. Injects the intent doc and the index |
| `bin/guard-hook.sh` | `PreToolUse(Bash)`. Blocks commit and push of the vault |
| `bin/doctor.sh` | Reports vault drift: unindexed notes, dangling links, bad frontmatter |
| `bin/archive.sh` | Prunes the index by marking old finished notes `archived: true` |
| `skill/SKILL.md` | Conventions the agent follows when reading and writing |
| `snippets/CLAUDE.md` | Always-loaded rules. This layer is what makes writing happen |

All three layers earn their place. Claude Code loads `CLAUDE.md` on every turn, so
writing needs no trigger. The skill holds the mechanics, which keeps `CLAUDE.md`
short. The hook covers the case where an agent forgets to look. The skill cannot do
the job on its own: skills load on description match, and "you are mid-session and
should record something" is not a match a model makes.

## Commits

No agent commits the vault. Agents leave notes as unstaged changes and you commit
them. A `PreToolUse` hook enforces that. It rejects `git commit` or `git push` aimed
at the vault before the command runs.

The hook matches `git` in command position, so `grep "git commit"` and other
read-only commands still run. It sees `Bash` tool calls only, so an agent using a git
MCP server gets past it. The instruction layer covers intent. The hook covers
accidents.

To have the vault commit itself, add a `Stop` hook that commits and skip the guard.
This repo does not ship that, because nobody has tested it and the failure mode is a
commit you did not want.

## Configuration

`install.sh` writes `~/.config/agent-memory/config`:

```sh
VAULT=/home/you/notes/memory
BIN=/home/you/code/agent-memory/bin
```

`AGENT_MEMORY_VAULT` overrides `VAULT` for a single run. The tests use it to point at
a throwaway vault.

## Tests

```bash
for t in tests/*.test.sh; do bash "$t"; done
```

89 assertions cover the hooks, the installer, and the maintenance scripts. They run in
`mktemp` directories against a fake `$HOME`, so they never touch a real vault or
`~/.claude`. CI runs them on Ubuntu and macOS, plus shellcheck.

```bash
bash tests/e2e.sh
```

`tests/e2e.sh` sits outside CI because it needs an authenticated `claude` CLI. It
installs into a sandbox, seeds a vault, runs a real headless session in a throwaway
repo, and checks that the injected context reached the model. It is the only test
that covers the hook wiring rather than the scripts on their own.

## Maintenance

Two commands, both safe to run at any time:

```bash
bin/doctor.sh [repo]     # report drift; exits 1 if anything is wrong
bin/archive.sh [repo]    # dry run; add --apply to act
```

`doctor.sh` catches the worst failure: a note written but never added to `_index.md`,
which hides it from every later session. The skill tells agents to run it after
writing, scoped to the repo they touched.

`archive.sh` keeps the index short once it passes about 40 entries. It sets
`archived: true` on `status: done` notes older than 30 days and drops their index
lines. Use `--days N` to change the window. It does not move note files, so
`continues:` wikilinks keep resolving. The index controls how much context a session
loads, not where the files sit.

## Scope

The vault holds session narrative: dated, superseded over time. Durable facts about
you or a project belong in Claude's own memory (`~/.claude/projects/*/memory/`), which
this repo does not touch.

## Licence

MIT.
