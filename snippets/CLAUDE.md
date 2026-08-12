Paste the block below into your `~/.claude/CLAUDE.md`. Adjust the heading level and
numbering to match your file. The content is what matters, not the structure.

The `SessionStart` hook surfaces the index without this block, so an agent will still
*read* memory. This block is what makes an agent *write* it, because Claude Code loads
`CLAUDE.md` on every turn rather than only at session start.

---

## Ground Truth

**If `<vault>/<repo>/_intent.md` exists, it outranks everything except my current
instruction.**

It states what the project is trying to do: goal, constraints, rejected directions. I
maintain it by hand and keep it in the memory vault. **Never put it, or anything like
it, in the project repo.**

Read it before planning substantive work. If code, a plan, or a session note
contradicts it, say so and stop. Do not reconcile the two on your own, and do not
assume the doc is the stale one.

**Never edit it unless I ask.** Not as a side effect of implementing what it
describes. Suggest changes. Do not make them. Do not create one uninvited either.

Precedence: my instruction, then the intent doc, then the code, then session notes.

## Session Memory

**Record work so another agent can pick it up.**

A vault holds one note per session, one folder per repo. When doing substantive work
in a git repo, write a note as you go: decisions and rationale, what is still open,
approaches you already rejected. Shorthand bullets, not prose. Git records what
changed. The note records why.

Read `<vault>/<repo>/_index.md` before starting related work. Treat notes as reports
from past sessions, not as ground truth. Check `head:` against the current HEAD.

Use the `agent-memory` skill for paths, template, and conventions. Do not improvise
the layout.

Never commit or push the vault. Leave notes as unstaged changes. I commit them.

Claude's own memory (`~/.claude/projects/*/memory/`) is a different thing, holding
durable facts. Session narrative goes in the vault, not there.
