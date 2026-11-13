---
description: JTPS — J the Problem Solver. Turn a Jira ticket or task description into a reviewed, battle-tested implementation instruction.
argument-hint: <ATO-12345 | task description>
---

Launch the `j-the-problem-solver` agent (JTPS) via the Agent tool with this task:

$ARGUMENTS

If no argument was given, ask which Jira key or task description to work on before launching.

Pass the current repo path. The agent writes its document to `$HOME/.claude/j/plans/<KEY>-approach.md`.

Do not do the analysis yourself in the main thread — the agent owns it. When it returns, relay its summary — including the `Feature flag:` and `Scope vs ticket:` lines — and the path to the instruction document, and offer to hand that document to `/jti`.
