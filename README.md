# agent-memory

Persistent memory for coding agents, so one session can pick up where another left
off. Notes live in a git repo you own, outside the projects they describe.

Two problems it solves:

- **Handoff.** An agent finishing work knows what it tried, rejected, and left
  half-done. The next agent knows none of it. Git records what changed, not why.
- **Recall.** Writing notes is easy; getting them read is not. A `SessionStart` hook
  injects the relevant index automatically, so it does not depend on an agent
  remembering to look.

Built for [Claude Code](https://claude.com/claude-code). Bash, git and `python3`.

## Layout

Nothing is ever written into your project repos. Everything lives in the vault:

```
<vault>/
  <repo-name>/
    _intent.md                             # ground truth — you write this
    _intent.<branch>.md                    # optional per-branch override
    _index.md                              # one line per note, newest first
    2026-01-15-sage-heron-auth-refactor.md # one file per session
```

One folder per repo, shared by every worktree and branch of it — so an agent in one
worktree sees what an agent in another did. Repo identity comes from
`git rev-parse --git-common-dir`, so linked worktrees map back to the main repo.

One file per session. Two agents in the same worktree write two files, so there are
no write conflicts and no merge conflicts on content. Only `_index.md` can conflict,
and it resolves by keeping both lines.

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

Sections: **Open** (in flight / next step) → **Goal** → **Decisions** → **Changed**
→ **Don't** (tried and rejected).

`head` is the repo HEAD at last update, so `git diff <head>..HEAD` shows what moved
since the note was written. That turns *Changed* from a claim into something
checkable.

`agent` is an adjective-animal pseudonym derived deterministically from the session
id. It makes the index scannable when several agents work the same day. It does not
imply continuity — a fresh agent has no memory of a previous one.

**Open** matters most and is the section most often skipped, because the agent
writing it already knows what is in flight. It goes first for that reason.

## Ground truth

Session notes are dated reports. They are not authoritative and they go stale.

`<repo>/_intent.md` is. You write it by hand: goal, constraints, and directions
deliberately rejected. Agents read it, defer to it, and **never edit it unless asked**
— not even as a side effect of implementing what it describes.

Precedence, highest first: **your instruction → intent doc → code → session notes.**

If an agent finds the code or a note contradicting the intent doc, it says so and
stops rather than quietly reconciling. Start from `skill/templates/INTENT.md`.

The hook **inlines the whole doc** into context at session start, so the highest
authority in the system is not the one thing nobody loaded. Docs over 8KB degrade to
a pointer instead of flooding every session in that repo.

Keep it to a page. A long intent doc rots, and a rotted one is worse than none,
because agents have been told to trust it.

## Flow

```
session starts in a git repo
  └─ SessionStart hook fires
       ├─ resolves the repo via `git rev-parse --git-common-dir`
       ├─ inlines _intent.md if present    — branch override wins, 8KB cap
       └─ injects _index.md if present     — last 30 lines
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

It writes a config file, creates the vault as a git repo if missing, symlinks the
skill into `~/.claude/skills/agent-memory`, and merges two hooks into
`~/.claude/settings.json` — backing it up first, preserving hooks you already have,
and never duplicating on re-run.

**One manual step.** Paste the block from [`snippets/CLAUDE.md`](snippets/CLAUDE.md)
into your `~/.claude/CLAUDE.md`. The installer will not edit that file, because it is
yours and has your own structure.

Restart running sessions afterwards. Hook config reloads live, but `CLAUDE.md` and
`SessionStart` are both read at session start.

The vault is created with no remote. Add one yourself if you want it backed up —
make it **private**, since it will describe your work in detail.

### Uninstall

```bash
./install.sh --uninstall
```

Removes the hooks, the skill link, and the config. Never touches your vault. Remove
the `CLAUDE.md` block by hand.

## Machinery

| Piece | Role |
|---|---|
| `bin/memctx.sh` | Resolves vault, repo, branch, HEAD, pseudonym, paths. `--init` seeds the folder |
| `bin/session-start-hook.sh` | `SessionStart` — injects intent doc and index |
| `bin/guard-hook.sh` | `PreToolUse(Bash)` — blocks commit/push of the vault |
| `bin/doctor.sh` | Reports vault drift — unindexed notes, dangling links, bad frontmatter |
| `bin/archive.sh` | Prunes the index by marking old finished notes `archived: true` |
| `skill/SKILL.md` | Conventions the agent follows when reading and writing |
| `snippets/CLAUDE.md` | Always-loaded rules; the layer that makes writing reliable |

Three layers, and all three earn their place. `CLAUDE.md` is loaded every turn, so
writing needs no trigger. The skill holds the mechanics, keeping `CLAUDE.md` short.
The hook removes the "agent forgot to look" failure mode. A skill alone will not work
— skills load on description match, and "you are mid-session and should record
something" is not a match a model reliably makes.

## Commits

The vault is never committed by an agent. Notes are left as unstaged changes and you
commit them. A `PreToolUse` hook enforces this: `git commit` or `git push` targeting
the vault is rejected before it runs.

It matches `git` in command position only, so `grep "git commit"` and similar
read-only commands still work. It sees `Bash` tool calls, so an agent using a git MCP
server would bypass it — the instruction layer covers intent, the hook covers
accidents.

If you would rather the vault committed itself, add a `Stop` hook that commits, and
skip the guard. That is not shipped here because it is untested and the failure mode
is committing something you did not want committed.

## Configuration

`install.sh` writes `~/.config/agent-memory/config`:

```sh
VAULT=/home/you/notes/memory
BIN=/home/you/code/agent-memory/bin
```

`AGENT_MEMORY_VAULT` overrides `VAULT` for a single invocation, which is how the
tests run against a throwaway vault.

## Tests

```bash
for t in tests/*.test.sh; do bash "$t"; done
```

89 assertions across the hooks, the installer, and the maintenance scripts. They use
`mktemp` directories and a fake `$HOME`, so they never touch a real vault or
`~/.claude`. CI runs them on Ubuntu and macOS, plus shellcheck.

```bash
bash tests/e2e.sh
```

`tests/e2e.sh` is separate and not run by CI, because it needs an authenticated
`claude` CLI. It installs into a sandbox, seeds a vault, runs a real headless
session in a throwaway repo, and asserts the injected context actually reached the
model. That is the only test that proves the hook wiring rather than the scripts.

## Maintenance

Two commands, both safe to run at any time:

```bash
bin/doctor.sh [repo]     # report drift; exits 1 if anything is wrong
bin/archive.sh [repo]    # dry run; add --apply to act
```

`doctor.sh` catches the failure that matters most: a note written but never added to
`_index.md`, which makes it invisible to every future session. The skill tells agents
to run it after writing, scoped to the repo they touched.

`archive.sh` keeps the index short once it passes ~40 entries. It sets
`archived: true` on `status: done` notes older than 30 days (`--days N` to change)
and drops their index lines. Note files are **not moved**, so `continues:` wikilinks
between notes keep resolving — the index is what controls how much context a session
loads, not where files sit.

## Scope

Session narrative only — dated, superseded over time. Durable facts about you or a
project belong in Claude's own memory (`~/.claude/projects/*/memory/`), which this
does not touch.

## Licence

MIT.
