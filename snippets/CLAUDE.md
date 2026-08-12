Paste the block below into your `~/.claude/CLAUDE.md`. Adjust the heading level and
numbering to match your file — the content is what matters, not the structure.

The `SessionStart` hook surfaces the index without this, so an agent will still *read*
memory. This block is what makes it reliably *write* memory, because it is loaded on
every turn rather than only at session start.

---

## Ground Truth

**If `<vault>/<repo>/_intent.md` exists, it outranks everything except my current
instruction.**

It says what the project is trying to do — goal, constraints, rejected directions.
Hand-maintained by me, kept in the memory vault. **Never put it, or anything else
like it, in the project repo.**

Read it before planning substantive work. If code, a plan, or a session note
contradicts it, say so and stop. Don't silently reconcile, and don't assume the doc
is the stale one.

**Never edit it unless I ask.** Not as a side effect of implementing what it
describes. Suggest changes; don't make them. Don't create one uninvited either.

Precedence: my instruction → intent doc → code → session notes.

## Session Memory

**Record work so another agent can pick it up.**

A vault holds one note per session, one folder per repo. When doing substantive work
in a git repo, write a note as you go — decisions and rationale, what's still open,
approaches already rejected. Shorthand bullets, not prose. Git records what changed;
the note records why.

Read `<vault>/<repo>/_index.md` before starting related work. Treat notes as reports
from past sessions, not ground truth — check `head:` against current HEAD.

Use the `agent-memory` skill for paths, template, and conventions. Don't improvise
the layout.

Never commit or push the vault. Leave notes as unstaged changes; I commit them.

This is separate from Claude's own memory (`~/.claude/projects/*/memory/`), which
holds durable facts. Session narrative goes in the vault, not there.
