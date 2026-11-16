# How the workflow is built

Living document. It explains what the system is, why each piece exists and what happened while building it, so that slides for the team can be made from it later. Decisions and the full action list are in `..\OVERVIEW.md`; evidence is in `..\research\`.

## 1. The idea in one paragraph

Own the process, not the code. The agent reads and writes the code; the human decides at the first step (the plan) and the last step (the evidence), and deterministic gates sit in between. State lives in files, not in chats. Review effort follows risk. Nothing leaves the machine without a yes. Token spend is measured per task.

## 2. Why: what the research showed

| Problem | Number |
|---|---|
| Task state lives in long chat sessions | Nine sessions older than 7 days held 65% of weighted tokens; "what's left" was asked 17 times in 5 weeks |
| Review is expensive and untiered | `/code-review` took 17.8% of weighted tokens; a `max` run costs 18 times a `high` run |
| Nothing gated outbound actions | 15 stray PR approvals from one prompt; a wrong-session prompt changed a Jira ticket |
| The guard for secret files had holes | `git -C <dir> add .` passed |
| PR bots miss from shallow depth | ATO's CI reviewer stopped after 8 to 16 turns on two security misses |
| A fan-out without a budget check | 12 agents used a whole 5-hour window in 25 minutes |

## 3. The layers

| Layer | What it is | State |
|---|---|---|
| Gates | Hooks that deny or ask: secret-file guard, outbound-action approval | Built 2026-11-13 |
| Ledger | A folder per task under `D:\project-planning\`, Markdown for notes, JSON for structure, a generated overview, an ideas file, one fast command-line tool, a cleanup command | Design next |
| Pipeline | One pipeline, three task types: implement (ends in a draft PR), investigate (ends in findings and ticket drafts), review (ends in drafted comments). Plan gate, verify script bound to the commit, tiered review, fix loop of at most three rounds, validation slots declared per project | After the ledger |
| Skills for hand-typed work | Colleague-PR review with a personal lens and no code-preference findings, close-out, CI babysitting, batch refresh, drafting | Alongside |
| Self-improvement | A retrospective after each task, statistics across tasks, a change only when a problem class shows up in several tasks, and a check afterwards that the change helped | With the ledger |
| Team rollout | Proven pieces contributed to the marketplace with evidence | Last |

## 4. Design rules

1. A gate is a hook or a script. An instruction is not a gate.
2. Every loop has a round limit and ends with a human.
3. Files carry state; any fresh session can resume from the task folder.
4. The cheapest model that does the job; a task moves up a tier when it struggles.
5. A rule change needs evidence from several tasks and gets removed when it does not help.
6. Everything runs in plain Claude Code; other shells are optional.
7. Nothing is hardcoded to one project; each project has a profile.

## 5. Build log

### 2026-11-11: research
Thirteen research units and seven addenda: own configuration, the ATO marketplace, e-accounting, PR review reality, session mining, token economics, the workspace, T3 Code, official guidance, OpenAI and community practice, the Advisor factory. Lesson: the first 12-agent wave hit the usage limit; fan-outs now go in small waves after a gauge check.

### 2026-11-13: decisions and first build
- Decisions Q1 to Q11 taken (decision log in the overview).
- ATO marketplace refreshed after four weeks of silent staleness; four plugins updated.
- Plugins: `sdw` (Visma maturity check) and `mattpocock-skills` installed; duplicate `superpowers` removed.
- Session rule added to the user-level `CLAUDE.md`: one task per session, hand-off file above about 150K tokens of context.
- `user-guard.ps1` rewritten. The secret-file guard now catches `git -C <dir> add .`, `./`, `-Av`, `:/`, `*` and `git stage`. A new outbound gate asks before `gh pr review`, `comment`, `merge` and `close`, `gh issue comment`, `create` and `close`, `gh api` writes including GraphQL mutations, and Jira and Slack writes through MCP. 50 table-driven tests pass (`~/.claude/hooks/tests/user-guard.tests.ps1`). The previous script is kept as `user-guard.ps1.bak`.
- JCrew validation lock fixed: wait time now longer than stale time, an unreadable lock file is reclaimed, and check plus takeover run under a mutex. Before: 6 of 40 simultaneous stale takeovers let two tasks in. After: 8 rounds of 6 simultaneous takeovers, one winner each.
- Token rules added to `CLAUDE.md`: usage gauge read before a wave of agents, a model named on every agent call, report file first, `/code-review` at `high` by default.
- Ledger tool `pp` built in Go (`D:\project-planning\_tools\pp`, binary in `_tools\bin`, on the user PATH). Commands: `new`, `ls`, `show`, `set`, `event`, `stats`, `idea`, `index`, `clean`. One `task.json` per task, a generated `INDEX.md`, a root `IDEAS.md`. Five tests pass. Measured: 25 ms per call, against 343 to 538 ms for a PowerShell script. This rework is registered as the first task.
- Self-improvement, first half: `pp event` records a problem class on a task; `pp stats` counts in how many of the last 20 tasks each class occurs and marks a class seen in 3 or more tasks as a pattern. The second half (proposing a change, checking afterwards that it helped) is not built.
- Ledger tool renamed from `pp` to `jplan` (same commands; root variable `JPLAN_ROOT`).
- Pipeline v2, first version: skill `~/.claude/skills/jflow/SKILL.md` and command `/jflow`. One orchestrator, three tracks. Implement: intake, plan (limit 1,500 words, minimal and robust option), human plan gate, implementation in a worktree, verify file bound to the commit, review tiered by risk (light, standard, full), fix loop of at most three rounds, validation in a slot the project profile declares, draft PR, human evidence gate, close. Investigate: scope, evidence, findings, options, human gate, ticket drafts for other people, Jira creation through the approval gate. Review: drafted comments without code-preference findings. Project profiles in `D:\project-planning\_profiles\` (`ato.json`, `eaccounting.json`; check commands not filled in yet). JCrew is left in place for comparison. Not yet run on a real task.
- `jflow` refined: plan length follows difficulty (simple 600 words, normal 1,500, hard 4,000 with a stated reason); project notes per project (`_profiles\<project>.md`: traps, environment, what works) read at intake and extended at close; profiles fill themselves in while working; an Improve step after every close (pattern from `jplan stats`, one proposed change with evidence, a record in `_profiles\improvements.md`, removal of changes that did not help after 10 tasks).
- e-accounting's slot idea checked against ATO. Usable today: two stacks side by side (native on 5xxx, Aspire on 15xxx), both now in the ATO profile. Numbered slots beyond two need a change in `ato-host` (ports are constants in `AtoEndpoints.cs`, and the CORS and login-redirect env files repeat them); parked in `IDEAS.md`.
- Not yet verified: how the approval prompt behaves in a live session and in a session nobody is watching.

### 2026-11-13: first real task and what it changed

- First `/jflow` run: task `ato/core-docker-ci-speed` (later ATO-19607), Core Docker CI. Measured result: PR run 18m31s against 36 to 41 minutes, the same 8,163 tests, one core PR (#9585). The flow held where it mattered: measurements went to `notes\` before the plan, the plan gate was used twice (the human changed the option), review ran at the light tier and found one defect, evidence files are named after the commit, and every outbound text was drafted to `scratch\` and posted only after a yes.
- What broke, and the fix made in the same day:
  - `jplan` was not on PATH in a session started before the install, and the skill named a fixed drive. Now `jplan` lives in `~/.claude/bin`, the planning root is stored in `~/.claude/jflow.json`, `jplan root` prints it, and the skill and `CLAUDE.md` ask for the root and name the fallback path.
  - A context compaction lost the ledger key, and `jplan set ATO-19607` failed because the task id was a slug. Intake now prints a `Ledger:` line that every report repeats, and `jplan` finds a task by its `jira` field.
  - Branch and commits carried the placeholder `ATO-10` until the real ticket arrived. The plan gate now asks for the ticket key.
- Portability for other people: user-specific paths in the agents, commands, `j-crew` and the ATO seed profile are `$HOME/.claude`; the agents and the crew skill are named `j-the-problem-solver`, `j-the-implementer` and `j-crew`; the shared rules are a separate `jflow-rules.md` that a person's own `CLAUDE.md` imports; `plugins.json` is split into `core`, `ato` and `personal` sets; the installer takes `-PlanningRoot`, remembers it, and installs Go when it is missing.
- ATO stays with ATO: ATO-only skills (`j-crew`, `harden-pr`, `write-for-review-ato`, three domain skills) and the project seed profiles live in `sets/<set>/` and are installed only with that set; `jflow` uses `ato-*` agents and skills only for a task whose project is `ato`. `write-for-review` was split into a generic core and the ATO half.
- Cross-platform (2026-11-16): the installer and hooks run under PowerShell 7 on Windows, macOS and Linux. Tools come from winget or Homebrew; Go falls back to a private download under `~/.claude/tools`. Hooks use the system temp folder, not `%TEMP%`. Tested from scratch in a Linux container; macOS not tested.
- Outbound gate, live check: `gh pr comment --help` in a T3 session ran without being blocked. Whether a prompt was shown is not visible to the agent, so the gate's value depends on the client's permission mode.
- Seen and not fixed: the plan was 1,600 words plus a 5 KB appendix against a 1,500 limit; `tokens` was never recorded on the task; a workflow that pushes images was reviewed at the light tier because the tier follows line count and `sensitivePaths` has no entry for CI workflows.

## 6. Improvement paths

- Measure first: tokens and wall time per task, review passes per ticket, findings accepted against findings raised.
- Deeper CI reviewer for the team, with e-accounting as precedent.
- Evaluation set from past PRs, re-run when a model or a skill changes.
- Port the gates to a cross-shell form so that teammates on other setups can use them.
- Share the investigation track: findings and ticket drafts that read in 1 to 3 minutes.

## 7. Slide outline (draft)

1. The principle: own the process, not the code.
2. What the numbers said (section 2).
3. Gates: two incidents, one hook, 50 tests.
4. The ledger: a task survives the chat.
5. One pipeline, three exits.
6. Review that scales with risk, without code-preference noise.
7. A system that improves itself with evidence.
8. Results after ten tasks (to be measured).
9. What the team can take today.
