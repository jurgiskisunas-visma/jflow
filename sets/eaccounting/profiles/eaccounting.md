# e-accounting: project notes

What a session should know before working here. One dated line per fact; delete a line that turns out wrong. Under 60 lines.

## Traps

- 2026-11-13: The local checkout is a detached HEAD far behind origin. Update it before trusting anything read from disk.
- 2026-11-13: Three nested worktrees sit under `.claude\worktrees\`; a scan of `.claude\` counts files three times unless it excludes them.

## Environment

- 2026-11-13: The repo has its own slot scheme (`LocalDevSlot`, each slot on its own ports, slot 0 for the IDE, agents use 1 to 9; `Start-LocalApps.ps1 -Slot N`, `Stop-LocalApps.ps1 -Slot N`). Read `docs/local-apps-kestrel.md` on an up-to-date checkout and wire it into the profile on first use.
- 2026-11-13: Browsers do not keep cookies apart by port; use a separate browser profile per slot.

## What works

- 2026-11-13: Never resolve a review thread; the reply answers, the commenter resolves.
