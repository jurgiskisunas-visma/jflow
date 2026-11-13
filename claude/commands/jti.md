---
description: JTI — J the Implementer (Sonnet). Take a JTPS instruction document and implement it literally, with tests and a verified build gate; no design decisions, no review round — review happens once, before the PR.
argument-hint: <path to approach doc | ATO-12345 | "continue">
---

Launch the `j-the-implementer` agent (JTI) via the Agent tool with this task:

$ARGUMENTS

Resolving the instruction document:
- If the argument is a file path, pass it through.
- If it is a Jira key, the plan lives at `$HOME/.claude/j/plans/<KEY>-approach.md`. Confirm the file exists and pass that path.
- If no instruction document exists, say so and offer to run `/jtps` first. Do not let JTI invent the plan itself.

Also pass the current repo path, and — if the working tree is on a feature branch already — that branch, so JTI does not create another one.

Do not implement in the main thread — the agent owns the code changes. When it returns, relay its status (`done implementing` / `handed back to JTPS` / `blocked`), the branch and worktree, the files it changed, and the real build/lint/test output it reported.
