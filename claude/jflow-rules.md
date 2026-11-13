# jflow rules

Installed by jflow and imported from `~/.claude/CLAUDE.md`. Edit it in the jflow repo, not here.

- One task per session. A new task gets a new session, not another prompt in an old one.
- Tasks live in the ledger at `<root>\<project>\<KEY-or-slug>\`, where `<root>` is what `jplan root` prints (`$HOME/.claude/bin/jplan.exe` when `jplan` is not on PATH). A task folder holds `task.json`, `task.md`, `plan.md`, `notes\`, `evidence\`, and `scratch\` for anything large.
- Use `jplan` (`jplan help`): `jplan ls` for what is open instead of scanning folders, `jplan new` at task start, `jplan set <key> status=... next=...` whenever state changes, `jplan event <key> <class>` when the user corrects you or a review finds something, `jplan idea` to park an idea. `/jflow` runs a task through the pipeline.
- Above ~150K context, or when a task pauses for the day: write a hand-off file (state, decisions, next step, open questions, paths) to `<root>\<project>\<KEY-or-slug>\handoff.md` and continue from it in a fresh session. Below ~100K, an idle gap alone is no reason to restart.
