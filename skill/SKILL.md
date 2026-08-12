---
name: agent-memory
description: Record what a coding session did into the memory vault, so another agent can pick the work up. Use when starting substantive work in a git repo, when reaching a decision or a stopping point worth recording, when handing off mid-task, or when the user asks to save/record/write up what happened. Also use when the user asks what prior sessions did in a repo.
user-invocable: true
argument-hint: "[read | write | handoff]"
---

# Agent Memory

A markdown vault holding one note per coding session, in one folder per repo. It
exists so a later agent can pick up work an earlier one left.

This is session narrative — dated, superseded over time. It is **not** the same as
Claude's own memory directory (`~/.claude/projects/*/memory/`), which holds durable
facts about the user and standing project constraints. Do not write there from here.

## Resolve context first

Always start by running the helper. It resolves the vault path, repo folder, branch,
HEAD, and this session's pseudonym in one go:

```bash
. "${XDG_CONFIG_HOME:-$HOME/.config}/agent-memory/config" && \
  "$BIN/memctx.sh" --init --session "$CLAUDE_SESSION_ID"
```

`--init` creates the repo folder and seeds `_index.md` if they do not exist. It is
idempotent, so pass it whenever you are about to write. Omit it when only reading. A
repo with no folder is one nobody has written about yet — normal, not an error.

If `$CLAUDE_SESSION_ID` is not set, pass the session id from the transcript path, or
omit `--session` and pick any unused adjective-animal name.

It prints `VAULT`, `REPO`, `BRANCH`, `HEAD`, `WORKTREE`, `AGENT`, `DIR`, `INDEX`,
`DATE`, `STAMP`. Use those verbatim — do not re-derive paths by hand.

Every worktree and branch of a repo shares one folder. That is deliberate: an agent
in one worktree needs to see what an agent in another did. `branch` and `worktree`
in the note frontmatter carry the distinction.

## Ground truth beats memory

`$DIR/_intent.md` is the source of truth for what a project is trying to do — goal,
constraints, rejected directions. Hand-maintained by the user. It lives in the vault
alongside the notes, **never in the project repo.**

A branch-specific `$DIR/_intent.<branch-with-slashes-as-dashes>.md` overrides the
repo-wide one when it exists. Most repos will only ever have `_intent.md`.

Precedence, highest first: **the user's current instruction → the intent doc → the
code → session notes.**

- Read the intent doc before planning any substantive change.
- If a session note, the code, or a plan contradicts it, **say so and stop.** Do not
  silently reconcile, and do not assume the doc is the stale one.
- **Edit it only when explicitly asked.** Never as a side effect of doing the work it
  describes. Suggesting an edit is fine; making one unprompted is not.
- No doc for this repo? Carry on as normal. Do not create one uninvited.
- **Never write an intent doc, or any other file, into the project repo.**

A starting template is at `templates/INTENT.md` next to this file. If the user asks
for one, copy it to `$DIR/_intent.md` and fill it in there.

## Reading

Read `$INDEX` first — it is one line per note, newest first. Open only the notes that
look relevant. Do not read the whole folder.

Treat notes as reports from the past, not ground truth. Check `head:` against the
current HEAD; if they differ, `git diff <head>..HEAD` shows what moved since.

## Writing

One file per session: `$DIR/$DATE-$AGENT-<slug>.md`, e.g.
`2026-01-15-sage-heron-auth-refactor.md`. The slug is 2-4 words describing the work.

Create the note once you have something worth recording — a decision, a non-obvious
change, a rejected approach. Then keep updating it as the session goes. Do not wait
until the end; sessions get cut off.

```markdown
---
repo: <REPO>
branch: <BRANCH>
worktree: <WORKTREE>
agent: <AGENT>
session: <session id>
started: <STAMP>
updated: <STAMP>
head: <HEAD>
status: active
tags: [refactor]
continues: "[[2026-01-13-amber-vole-auth-spike]]"
---

## Open
- What is in flight, half-done, or the next step. Write this first and keep it current.

## Goal
- What this session set out to do.

## Decisions
- Chose X over Y because Z.

## Changed
- `path/to/file.ts` — what and why, one line.

## Don't
- Approach already tried and rejected, and why. Saves the next agent re-deriving it.
```

Rules:

- **Shorthand, not prose.** Bullets. No narration, no restating the diff.
- **Open goes first** and stays current. It is the section a fresh agent needs and the
  one most likely to get skipped, because the agent writing it already knows.
- **Rationale over record.** Git already stores what changed. Record *why*, and what
  was considered and rejected.
- **`head`** is the repo HEAD at last update. It makes `Changed` checkable.
- **`tags`** — closed set only: `feat`, `fix`, `refactor`, `investigation`, `spike`,
  `chore`. Nothing topical.
- **`continues`** — wikilink to the prior note if this carries on the same thread.
  Omit otherwise.
- **`status`** — `active` while working, `handoff` if stopping deliberately mid-task,
  `done` when finished.

Two agents in one worktree write two separate files. Never edit another session's
note; link to it with `continues` instead.

## The index

After creating a note, and again if its one-line summary changes materially, add or
update its line in `$INDEX`. `--init` will have created it. Newest first:

```markdown
- [[2026-01-15-sage-heron-auth-refactor]] — swapped token refresh to a background
  worker; `status: handoff`, retry backoff still unwired
```

Keep it to one line: what happened, and anything left open. This is what gets injected
into future sessions, so it carries most of the value.

## Check your work

After writing the note and its index line, run:

```bash
"$BIN/doctor.sh" "$REPO"
```

It exits 0 when clean and lists problems otherwise. The one that matters is **not
indexed** — a note with no index line is invisible to every future session, which
wastes the whole exercise. Fix anything it reports before you finish.

## Pruning the index

When the index passes ~40 entries, archive finished notes:

```bash
"$BIN/archive.sh" "$REPO"            # dry run, shows what would go
"$BIN/archive.sh" "$REPO" --apply
```

That sets `archived: true` on `status: done` notes older than 30 days and removes
their index lines. **Files stay where they are**, so `continues:` wikilinks between
notes keep resolving. Do not move note files by hand.

## Never commit or push

**Do not run `git commit` or `git push` in the vault. Ever.** The vault owner does
that manually. No exceptions, including when a session ends, when a note is marked
`done`, or when the working tree looks untidy.

Write the note and the index line, then leave them as unstaged changes. That is the
finished state. Say what you wrote; do not offer to commit it.

This applies even if the user has approved a commit elsewhere in the session, and even
if a note says a previous session committed. A `PreToolUse` hook enforces this, but do
not rely on it — the rule is the rule.

## When not to write

Skip trivia. No note for a one-line typo fix, a question answered without touching
code, or work with no decision behind it. An index of noise is worse than no index.
