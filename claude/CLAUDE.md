# User-level rules (all projects, all sessions)

Project `CLAUDE.md` files override these where they conflict. Keep this file short — prune any line that would not change behaviour.

## Editing

- Modify files with Edit/Write. Never via Bash heredoc, `sed`, `cat >`, or shell redirection — past attempts left stray syntax and needed reverts.
- Stage explicit paths. **Never `git add -A` / `git add .`** — several ATO repos hold untracked, non-gitignored secret files (`tna/build/docker/.env` with live PATs, `taxation/docs/local-secrets-*.md`); one such commit already forced a token rotation.
- Comments: write very few. Delete restatement and rationale essays; one short line only where a non-obvious constraint would otherwise be "fixed" into a bug. No `/// <summary>` on test methods — the test name carries the meaning. Full story goes in the commit message / PR description.

## Sessions

- One task per session. A new task gets a new session, not another prompt in an old one.
- Tasks live in the ledger at `<root>\<project>\<KEY-or-slug>\`, where `<root>` is what `jplan root` prints (`$HOME/.claude/bin/jplan.exe` when `jplan` is not on PATH) (`task.json`, `task.md`, `plan.md`, `notes\`, `evidence\`, `scratch\` for anything large). Use `jplan` (`jplan help`): `jplan ls` for what is open instead of scanning folders, `jplan new` at task start, `jplan set <key> status=... next=...` whenever state changes, `jplan event <key> <class>` when I correct you or a review finds something, `jplan idea` to park an idea. `/jflow` runs a task through the pipeline.
- Above ~150K context, or when a task pauses for the day: write a hand-off file (state, decisions, next step, open questions, paths) to `<root>\<project>\<KEY-or-slug>\handoff.md` and continue from it in a fresh session. Below ~100K, an idle gap alone is no reason to restart.

## Scope

- Investigation, diagnosis, or explanation requests get **no repo edits** — state the proposed change and wait.
- Never offer a destructive path (instance rebuild, force-push, mass delete) as the first option.
- Review comments posted on another dev's PR: only behaviour, correctness, real test gaps, rollout. No nits — parameter order/shape, duplicated predicates, whitespace, doc-comment wording, "FYI" notes. Those apply only when I implement.

## Evidence

- Verify a claim about repo/branch/config state with a second method before stating it (`git ls-tree` on the remote ref, not only a local file check). Git Bash on Windows has produced false negatives.
- Security verdicts reason about on-disk bytes and observed telemetry, not intended runtime behaviour.
- Say what was actually run and what it actually output. A skipped step gets reported as skipped.

## Environment

- Windows. PowerShell 7 and Git Bash. **`jq` is not installed** — use `gh --jq` / `-q` instead.
- Git Bash mangles `ref:path` arguments (`git show origin/master:.github/x.yml`) via MSYS path conversion — prefix with `MSYS_NO_PATHCONV=1` or use `git cat-file -p <blob>`.
- Long-running watchers echo one status line per poll, so a silent failure is visible.
- `az` tokens expire daily; run `az account get-access-token` before telemetry queries, or use the Grafana path.

## Before calling a change done

1. Every new code path gated behind a feature flag — name which flag covers which path.
2. Re-read the diff for state that must be reset on **every** branch (retry counters, totals, latches).
3. Build + relevant tests run, real output pasted.
4. Verified end-to-end in browser/CLI, not only by reading code.

## Parallelism — fan out, fan in

When a prompt or plan reaches a stage with **2+ independent units of work** — no shared state, no ordering between them — launch one agent per unit in a single message and synthesize the results yourself. Do not ask permission first; this is standing authorization. It is faster, and it keeps each unit's file dumps out of my context.

Independent means: per repo, per app, per PR, per reviewer role, per file cluster, per research question, per ticket. Sequential means: output of A is input to B — then do not fan out, chain it.

**Fan-in crunches.** N agents produce **one** answer, not N sections. The report is written as if one investigator did all the work: the answer up front, then only the findings that survived cross-checking, merged where two agents said the same thing, and contradictions resolved — or named as an open question when they cannot be. Per-agent structure, per-agent headings, and "Agent 3 also noted…" do not appear; who found what is mentioned only when the source changes what to do about it. If two agents' units genuinely have separate deliverables, that is two answers, not seven.

The compression is the point: 7 agents' output crunched to one answer is why fanning out is cheaper than doing it inline, not just faster.

Contract for every fanned-out agent: one line of scope, the exact output shape wanted, read-only unless the unit is an edit, its own worktree if it writes, cap any single command at 10 minutes and report the tail instead of blocking. `superpowers:dispatching-parallel-agents` and `superpowers:using-git-worktrees` carry the mechanics.

**Calibration (tune this, do not add a second rule below it):**

- Default ceiling: **12 concurrent**, hard cap 15. Beyond that, batch in waves of 12. Agents on the top model tier at high/max effort: **waves of 3, the parent included** (so two children while the parent also works), and give well-specified implementation units and mechanical read-only units (inventories, greps, doc drift, lint runs) a cheaper `model` — an 11-agent top-tier wave at max effort hit the session limit in ~11 minutes twice (2026-11-11), and 4 top-tier + 4 opus children plus a working parent hit the rate limit after ~40 minutes (2026-11-12). Children never inherit `max` effort: set `high` on a top-tier child, and after one limit kill in a session delegate no further top-tier children - finish serially, or hand a tightly specified unit to a cheaper model (two top-tier children at max effort beside a mostly idle parent were killed again after ~60 minutes, 2026-11-12). Tell every writing agent to commit after each work item, so a kill loses little.
- Before any wave of 3+ agents, read the usage gauge (`usageLimits` in `~/.t3/caches/claudeAgent.json`, or `/usage`) and state it in the launch line; above 60% of the 5-hour window, go serial or cheaper. Every Agent call names its `model`. Every agent writes its report file before anything else, so a kill leaves the findings on disk.
- `/code-review` runs at `high`; `max` only for diffs touching auth, secrets, crypto, SQL, PII or tenant isolation (a `max` run cost 18.1M weighted tokens against 1.0M at `high`).
- The harness caps **all live subagents at 20, nested ones included**. A `/ato-pre-pr-review` gate alone spawns up to 9, so run one review gate at a time while other agents are live.
- Read-only / exploratory units (test sweeps, searches, reviews) go at the ceiling. Reserve small counts for units that write.
- Don't fan out for fewer than 2 real units, or when one grep answers it.
- Don't fan out an edit across agents touching the same files.
- State the count and the split in one line before launching, so it can be cut before the tokens burn.

If feedback says too many agents, too few, wrong split granularity, or wasted cost: **edit the numbers and conditions in this block**, in the same turn — do not append a caveat elsewhere, and do not carry the correction only in session memory.

## Self-improvement (standing rule)

Treat repeated friction as a tooling defect, not a fact of life.

When, during a session, any of these happens **twice**:

- I correct the same behaviour again (scope, tone, format, verbosity, a convention),
- a command fails for an environment reason that was knowable (missing tool, wrong shell, expired token),
- a review bot or a later check finds a class of bug that a local gate could have caught,
- I ask for the same context you had to rediscover,

then before finishing the turn: name the friction in one line, and fix the **generator** — the skill, hook, memory file, or CLAUDE.md rule that would have prevented it — not just the current output. Propose the edit and its exact file path; apply it once I agree, or immediately if it is only this file, a user-level skill, or a memory note. Use `friction-to-skill` for the classification.

Prefer, in order: a deterministic hook (guarantees it) > a skill (teaches the procedure) > a CLAUDE.md line (advisory) > a memory note (recall only). Never add a rule without deleting or narrowing one that overlaps it.
