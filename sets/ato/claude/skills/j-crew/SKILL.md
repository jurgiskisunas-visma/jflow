---
name: j-crew
description: The full pipeline for getting work done — plan (JTPS), implement in a worktree (JTI), then queue for the project's single UI-validation slot, land the branch in the main checkout, build, run services, validate in a real browser, open a draft PR, and report back in plain language. One task end to end, or several in parallel up to the UI slot. Use for "run the crew", "/jcrew", "plan and implement this ticket", "take ATO-12345 all the way", "do all of these in parallel", "batch these tasks".
---

# J crew — plan, build, prove, explain

`j-the-problem-solver` (JTPS) plans. `j-the-implementer` (JTI) builds. This skill runs the pipeline around them and owns the one thing that cannot be parallelised: the project's main checkout, its running services and the browser.

**Mental model.** A *project root* (for example `D:\Projects\ATO`, or `D:\Projects\eaccounting`) is one unit. Its repos may be many, but it has one main checkout per repo, one set of services, one browser. Code is written in worktrees, as many at a time as you like. Validation happens in the main checkout, **one task at a time, per project root** — a queue, not a race.

**One task is the normal case.** The parallel wording below simply collapses when there is one.

**Budget to beat.** The first run took 1h43m for a one-line fix: 25 minutes planning, 22 implementing, 40 on services and browser, 8 waiting on a human. Everything in this skill that says "once", "cap", or "do not" exists because of that run.

## Step 1 — Ground yourself in the project

- Resolve the project root and the target repo(s). Side-by-side clones: use the repo-router skill.
- Read the root `CLAUDE.md` and the target repo's `CLAUDE.md`. Note two things specifically: **how the repo is built and started** (the commands, the start script), and **what a fresh worktree needs that git does not carry** — `node_modules`, gitignored local config (`build/docker/.env`, `appsettings.local.json`, secrets files). Those are the worktree provisioning list.
- Inventory the project's agents and skills — `.claude/agents/`, `.claude/skills/`, enabled plugins. In ATO: `ato-agents` (reviewers, `service-runner`, `ui-tester`, database and messaging helpers), `ato-workflow` (`issue-start`, `push-pr`, `pre-pr-review`, `investigate`), `ato-conventions`, `ato-angular21`. Prefer them over anything generic and pass the list to every agent you launch.
- Note which Jira MCP is live (`mcp__spiris-jira__*` in ATO). JTPS reads tickets itself; if it reports it could not, that is a bug to fix, not a plan step to accept.

State one line before launching: task count, repo(s), the UI-slot status (`jcrew-ui-lock.ps1 -Status -ProjectRoot <root>`), and the repo skills in play.

## Step 2 — Check the task list

Resolve each input to a Jira key, a description, or an existing approach document at `$HOME/.claude/j/plans/<KEY>-approach.md`.

For more than one task, verify independence — disjoint file sets. Overlapping tasks get chained or merged.

## Step 2b — Create the task worktree, from `origin/<default>`

Before anyone reads code. The main checkout may sit on any branch (the first run's `tna` was on an Angular-21 upgrade branch), so **it is never the base for investigating or implementing.** The base is the remote default branch, fresh, unless the user names another base.

You create it; JTPS and JTI never do.

1. `git -C <repo> fetch origin`.
2. Branch `<KEY>-<Kebab-Description>` from `origin/<default>` — the repo's `issue-start` skill does this and moves the Jira ticket in one go (transition names differ per project; the skill knows them, you do not guess). If you branch by hand: `git branch <branch> origin/<default>`, never from `HEAD`.
3. `git worktree add <repo>/.claude/worktrees/<KEY> <branch>`.
4. **Provision it from the list in Step 1, in the background while JTPS plans.** `node_modules`: if the worktree's `package-lock.json` is byte-identical to the main checkout's, create a junction (`New-Item -ItemType Junction`) to the main `node_modules` — seconds. If it differs, `npm ci` in the worktree. Copy gitignored local config files. Then run the repo's build command in the worktree **once** — a JTI that comes back `blocked` on a missing `node_modules` is four wasted minutes and a human interrupt.

Known repo traps (put them in every JTI brief): **Taxation** — the WebApp/WebJob `PreBuild` target runs `TASKKILL /IM Taxation.WebApp.exe` machine-wide; build and test worktrees with `-p:DEPENDABOT=true`. **ato-host** (`D:\Projects\ato-host`, Aspire, ports +10000) — `start.ps1` does not notice a branch switch in its service clones and runs stale `bin/`; `dotnet build` the service after every checkout (and again after restoring the original branch). Company setup there needs `ASB_CONNECTION_STRING` (core-worker), or there is no browser test data. **Core** — every app's `PreBuild` runs a machine-wide `TASKKILL` and there is no skip property. Pass `-p:CustomAfterMicrosoftCommonTargets=<file>`, where the file overrides `<Target Name="PreBuild" />`, and run dotnet from PowerShell, because Git Bash mangles the path. LocalDB data tests under `.claude\worktrees\` exceed SQL Server's 259-character .mdf limit, so always pass a short `--results-directory` (e.g. `D:\tr\<KEY>`). A lone csproj build of anything referencing Core.Data fails on `$(SolutionDir)`, so build through the slnf.

**Services are not part of this step.** A worktree has its own `bin/`, `obj/`, `dist/` and binds no ports; nothing running from the main checkout blocks it. If a worktree build does hit a lock or a port, that is a repo bug to report, not a reason to ask the user to stop anything. **Do not mention, stop, restart or ask about running services before Step 8.** The first run asked the user to stop services during implementation — that request only ever belongs to the move into the main checkout.

If a repo's `CLAUDE.md` says worktrees cannot build there at all, the fallback is: JTI edits a branch in the main checkout directly, and the UI slot (Step 7) is acquired **before** Step 6, not after. Say which mode you are in.

## Step 3 — Plan (JTPS)

One `j-the-problem-solver` per task, all in a single message, up to 12. Each gets: ticket key or description, **the worktree path as the code to read**, the skill inventory, the plan output path. JTPS reads the worktree, not the main checkout — the plan must describe the code as it is on `origin/<default>`.

JTPS runs its review lenses itself and launches at most one `sceptic-reviewer`, only for boundary-touching changes. If you see it spawning code reviewers at a plan, that is a regression — stop it.

Its report carries `Feature flag:` and `Scope vs ticket:` lines. A `none` flag needs a one-line justification; without one, send a **plan revision request** naming the section. Cheap here, expensive later.

## Step 4 — Triage gate (you) + Jira fit check

**Jira fit check first — one cheap agent, fresh eyes.** JTPS wrote both the plan and its `## Acceptance criteria`, so the plan agrees with itself by construction; that says nothing about whether it agrees with the ticket. Launch one `general-purpose` agent on `model: sonnet`, given only: the ticket fetched **now** via the live Jira MCP (summary, description, every comment, attachments list) and the plan's `## The problem`, `## Acceptance criteria`, `## The approach` and `## Feature flag and rollout` sections. Its brief:

> Compare ticket to plan. Report only: (a) ticket requirements or acceptance criteria the plan does not cover, (b) plan scope the ticket never asked for, (c) a comment on the ticket that changes or narrows the ask and the plan ignores, (d) wording in the ticket the plan interpreted one way where another reading is plausible. `path`-free, one line each, `none` per bucket when empty. No style, no code, cap 3 minutes.

(a) or (c) non-empty → **plan revision request** to JTPS naming the gap. (b) → JTPS trims, or the user confirms the wider scope. (d) → the user, one question. Empty across the board → proceed. This costs one small agent and prevents the most expensive failure the pipeline has: a perfect implementation of the wrong thing.

Then per plan: **Proceed** / **Ask first** (blocking open question, or scope grew) / **Drop**. Never launch JTI against a plan with a blocking open question.

## Step 5 — Worktree ready?

Confirm the Step 2b provisioning finished green (build output in hand). If it did not, fix it now — before JTI, not through JTI.

## Step 6 — Implement (JTI)

JTI runs on **Sonnet** — cheap and fast, because the thinking happened in the plan. It follows the plan literally and makes no design decisions: anything the plan does not settle comes back as `blocked` with a question, anything the plan gets wrong comes back as `handed back to JTPS`. That is the deal that makes the cheap model safe. Do not "help" it by answering design questions yourself — route them to JTPS (a plan revision request) or to the user.

One `j-the-implementer` per task, up to 4 concurrent, each given: plan path, worktree path and branch, the skill inventory. When a plan lists two or more **independent** workstreams and only one task is running, you may launch one JTI per workstream on the same plan with `workstream=<name>`, each in its own worktree; merge in the plan's order afterwards. Several tasks → one JTI each, workstreams sequential.

JTI edits, tests, builds, commits, self-checks the diff once against `write-for-review`, and returns `done implementing`, `handed back to JTPS`, or `blocked`. **No review agents run here.** The reviewers' checklist is baked into what JTI writes; the actual review happens once, at Step 10b, on the whole branch, before the PR.

`blocked` carries a question and its options. Design question → JTPS as a plan revision request; environment or permission question → the user verbatim via AskUserQuestion. Act on the answer, relaunch. JTI cannot ask anyone itself.

Flag check, on the worktree diff, by reading: every new path gated, the flag is the one the plan named, registered and off by default, same name across repos. Ungated path → back to JTI with the path named. Do not exercise the flag here; that is the browser's job.

## Step 7 — Stand in line for the UI slot

Every task that passed Step 6 now queues for the project's single validation slot:

```
pwsh -NoProfile -File $HOME/.claude/hooks/jcrew-ui-lock.ps1 -Acquire -ProjectRoot <project root> -Task <KEY>
```

It blocks, printing one status line per 30 seconds, until the slot is free, then holds it. Exit 3 after 120 minutes means give up and tell the user who is holding it. Another `/jcrew` in another session shares the same queue — that is the point.

**While waiting, do nothing to the main checkout, the services or the browser.** Other tasks in this run that have not reached Step 6 keep going.

When the slot is yours, tell the user in one line: *"Taking the main checkout and services for `<KEY>` — please do not run `run-all` or switch branches in `<repo>` until I release."* The first run had the user restart all services by hand in the middle of the check.

## Step 8 — Land in the main checkout

**This is the first moment running services matter.** Only now — slot held, code committed in the worktree — may you stop, restart, or ask the user about a service. Everything here is recorded so Step 11 can undo it.

0. Services running from the main checkout hold file locks on `bin/`, `obj/` and `dist/` and will serve stale code. Stop the ones you own before building; for the ones you do not own, ask the user **once**, with PID, port and the exact command — see Step 9 for the wording. Do this before the checkout, not after a failed build.

1. In the main checkout of each affected repo: `git status --porcelain --untracked-files=no`. **Tracked uncommitted changes → stop and ask the user** (stash, commit, or abort). Never stash on your own.
2. Record the current branch — `original branch` — and the `package-lock.json` hash.
3. Free the branch without destroying the worktree: `git -C <worktree> checkout --detach` (a branch checked out in a worktree cannot be checked out elsewhere, but a detached worktree holds nothing). The worktree stays — its `node_modules`, its build output and the review baseline are all reused if the fix loop sends JTI back. It is removed in Step 11. When it finally goes: `git worktree remove <path>`; on Windows this can fail with `Invalid argument` — then `--force`, delete the folder, `git worktree prune`.
4. `git checkout <branch>` in the main checkout.
5. If `package-lock.json` changed against the recorded hash: `npm ci`. Otherwise not.
6. Build **once**, with the repo's real commands. JTI already proved the code compiles; this build proves the main checkout has it. Paste the decisive lines.

## Step 9 — Services

Use the repo's `service-runner` agent (ATO: `ato-agents:service-runner`) with a hard contract in its prompt:

> The code is already built. Do not rebuild. Start what is not running for `<project root>`, report PID, port and one HTTP 200 per service, and stop. Cap 3 minutes.

The first run's runner spent 7 minutes re-proving provenance by hashing bundles. That is not its job.

**If services are already running from a stale build**, they have to restart on the new code. The runner stops what it started itself. Anything else — a server the user started, a process the runner cannot stop, a port that will not free, a build lock — **you do not kill.** Ask the user, once, with the exact steps:

> "`<service>` is running (PID `<n>`, port `<p>`) and I cannot restart it. Please stop it (or run `<start script>`) and reply when done."

Then relaunch the runner. Never `Stop-Process` a PID you did not create; never start a second runner while the first is alive — stop your own child first.

## Step 10 — Browser validation

**Playwriter preflight, before launching a tester:** one `mcp__playwriter__reset`. If it reports `Multiple extensions connected. Specify extensionId.` or cannot reach a tab, ask the user once with the exact fix (disable the Playwriter extension in the other Chrome profile/tab, or which tab to keep), then retry. Do not launch the tester into a broken bridge — the first run burned four minutes and two human rounds on it.

Then the repo's `ui-tester` (ATO: `ato-agents:ui-tester`), with a brief that leaves nothing to discover:

- **Everything under test runs on this machine.** The code is the branch you just built in the main checkout, served by the services Step 9 started, on `localhost`. State the exact base URL with the port from the runner's report (ATO defaults: Toolsite `http://localhost:5019`, Core `:5016`, AdminTool `:5014`, Taxation `:5012`, Recon `:44398`, TNA `:44399`; Toolsite routes look like `http://toolsite.localhost:5019/...`). **Never a `*.vismaonline.com`, stage, or prod URL** — those run yesterday's code and prove nothing about this change; a tester that lands there has left the test. Local login: the user's session is already authenticated on localhost; no credentials.
- The URL(s) and the exact click path, from the plan's `## Testing` and `## Acceptance criteria`.
- The company/tenant and test data to use, if the plan names them.
- What "fixed" looks like and what "still broken" looks like.
- **Do not read source code. Do not grep the repo.** Everything you need is in this brief; if it is not, report `cannot reach` and stop. The first run's tester spent 10 minutes grepping `node_modules` for a caller the plan had already said was untouched.
- Cap 12 minutes.

Validate:

0. Before anything else, the tester confirms it is on the right build: the page's host is `localhost`, and one request in the network log hits the port the runner reported. A `vismaonline.com` host in the address bar or the network log ends the run as `cannot reach: not local`.
1. The ticket's flow, **flag on** — symptom gone or feature works. Screenshot.
2. The same flow, **flag off** — old behaviour intact. When the old behaviour *is* the crash the ticket fixes, seeing the crash reproduce is the proof; if reproducing it is destructive or impossible to reach, say so and skip with the reason, do not silently drop it.
3. Console: no new errors, no failed requests, no unhandled rejections.
4. The obvious adjacent path a user hits next.
5. **Visual fidelity, when the ticket has a design (Figma link, mock-up attachment):** screenshot the result and compare it side by side with the mock-up — alignment to columns, paddings, separators, button shape. Also compare it with the same control used elsewhere on the page. "The text and the button are there" is not a pass. VEA-76076 shipped a draft PR with correct behaviour and the wrong layout because this step was missing.
6. **Multi-instance state:** if the feature has per-row state (expand, select), open two or more, change one, and check the others are unchanged.
7. **Top error banner and open modals, after every click:** read the page's top error strip (eAccounting: the red "There is N error" / "Det finns N fel" bar) and whether a modal or message box is open, and log both next to each snapshot. A step is not "done" while a modal waits for an answer, and a finished flow shows no error alert at the top at any point; the only allowed banner is the one a deliberate negative test provokes. VEA-74714 (2026-10-23): a "short useful life" message box blocked a save that was read as a silent failure, and validation banners went unread because only the dialog was inspected.

No UI surface (handler, migration, job): validate at the nearest real boundary — send the message, run the job, hit the endpoint. "No UI" relocates validation, never skips it.

## Step 10b — Review, once, on the whole branch

The last local gate — the colleague's "once per *I think this is done*". It runs here, after the browser said yes, so it runs on code that already works and it runs **once** per task instead of once per implementation attempt. In ATO the chain is: implement → `/ato-pre-pr-review` → `/ato-push-pr` → CI Claude review → human review.

You run it yourself, from the main checkout (the branch is checked out there, the baseline lands in the main `.git`). Pick the tier by non-test lines changed in `git diff origin/<default>...HEAD`:

- **Under 30 lines, no new file, no boundary touched** (auth, tenancy, data, messaging, contract): `/code-review` at medium effort. One pass, correctness only.
- **30 to 200 lines, or a new file, no boundary**: `/ato-pre-pr-review --auto` — the diff-aware recommended subset.
- **Over 200 lines, or any boundary touched**: `/ato-pre-pr-review` with no flags — all eight reviewers (performance included since ato-workflow 1.20) plus verifiers.

Read the gate, not the per-reviewer table:

- **APPROVED** → Step 11.
- **REVIEW REQUIRED** → every surviving High is fixed (Step 12) or accepted with a written reason that goes into the PR body. No silent acceptance.
- **BLOCKED** → Step 12 with the Criticals. On return, re-run the **same** command — it reports the delta against its baseline, so the second pass is cheap.

"Rejected by verification" is settled; do not re-litigate. "Adjacent / pre-existing (not gated)" is not fixed in this branch — it goes into the report under *noticed*, and into Jira only on the user's per-item go. Reviewer disagreements are yours to decide; state the decision.

Then one **fresh-context grader against the ticket, not only the plan**: a single `general-purpose` agent on `model: sonnet`, given the diff, the plan's `## Acceptance criteria`, and the Jira ticket fetched **again now** — description and all comments, because a comment added while the crew was working is exactly what this catches. Brief: report what the ticket asks for that the diff does not do, what the diff does that the ticket did not ask for, and any acceptance criterion it cannot see proven in the diff or the browser evidence; no style, no code quality. Its verdict outranks everyone's sense of being done. A gap → Step 12; a ticket comment that changes the ask → JTPS, not JTI.

Both Jira checks (Step 4 and here) fetch the ticket live. Never reuse the text JTPS quoted in the plan — that is the version from before the work started.

If JTI wrote to `write-for-review`, this step should come back APPROVED most of the time. When it does not, the finding is also feedback on the checklist — note the rule that would have prevented it.

## Step 11 — Draft PR, then release

On a green Step 10b:

1. Push and open a **draft PR** with the repo's `push-pr` skill (ATO: `/ato-push-pr`; title `<KEY> <subject>`, base = default branch). Attach the browser evidence to the PR body: what was clicked, screenshots, console state — and the review gate (`APPROVED`, or the accepted Highs with their reasons), so the CI Claude review and the human reviewer start from what was already checked.
2. Post one comment to the Jira ticket: the PR link, the flag name, and two or three plain-language lines of what changed and how it was verified (localhost browser check, what was clicked) — written for the reporter, not the developer. The `push-pr` or `session-wrapup` skill knows the field names and the transition. If the Step 10b grader found the ticket ambiguous anywhere, the comment says which reading was implemented, so the reporter can object before anyone flips the PR to ready.
3. **Restore the main checkout:** `git checkout <original branch>`. If `package-lock.json` differs from the branch you are returning to, run `npm ci` again or, if that takes longer than a minute, tell the user in the report that their branch needs it. The first run left the user's Angular-21 branch with Angular-20 `node_modules` and did not say so.
4. Services: leave running if they were running when you arrived; stop your own if you started them and the user's were not running. Say which.
5. Remove the task worktree now that the PR exists and the fix loop is closed (`git worktree remove <path>`; Windows fallback as in Step 8.3).
6. Release the slot:

```
pwsh -NoProfile -File $HOME/.claude/hooks/jcrew-ui-lock.ps1 -Release -ProjectRoot <project root> -Task <KEY>
```

**Release on every exit path** — success, fix loop, hand-back, user abort. A slot held by a dead run blocks everyone for 150 minutes.

## Step 12 — The fix loop

Step 6's flag check, Step 10's browser, or Step 10b's review failed → back to JTI with what failed, the reproduction, the evidence (console output, screenshot, or the review finding with its `path:line`). JTI fixes through its decision ladder; a finding that is really a design question comes back `blocked` and goes to JTPS, not back to JTI with your own answer.

JTI needs the worktree again. It still exists, detached (Step 8.3). Move the main checkout off the branch first (`git checkout <original branch>` — services keep running on the built output, that is fine for now), then `git -C <worktree> checkout <branch>` and hand it to JTI. No re-provisioning, and `/ato-pre-pr-review`'s delta baseline under the worktree's git dir survives, so the re-review reports only what changed. Keep the UI slot if the fix is small and quick — a guard, a selector — because re-queueing costs more than holding for five minutes. Release it if the fix is structural. Say which.

After the fix lands again (Step 8): re-run Step 9 and 10 in full **unless** the fix is under 10 lines, touches no template, component, endpoint or serialised shape, and the review finding was not about runtime behaviour — then build plus the focused tests in the main checkout stand in for the browser, and you say so. Step 10b re-runs the same command it ran before; the delta is cheap. Never add reviewers of your own on top.

After the draft PR exists, review feedback from the CI Claude bot or a human comes back the same way: the fix goes through JTI in a worktree, then Steps 7–11 again (same review command, delta mode) before the PR is flipped to ready.

**Red CI on the draft PR** is not a fix-loop entry. Run the repo's `fix-red-pr` skill (ATO: `/ato-fix-red-pr`) — it fetches the failing job logs and classifies each failure as PR_BUG / MASTER_BUG / FLAKY / INFRA with the log line as evidence. Only a PR_BUG goes to JTI; a MASTER_BUG gets its own PR, never bundled; FLAKY and INFRA are re-run, not fixed. Do not spin up a general agent to "diagnose CI" — that is what happened before this skill existed. That is the colleague's "after addressing draft-PR feedback, before flipping to ready" loop; the repo's `pr-review-resolver` skill does the thread-handling part.

**Two fix rounds per approach.** Third failure → JTPS with all three reports (Step 13). The fix-round counter resets on a revised approach; the hand-back counter never does.

## Step 13 — Hand-backs

JTI `handed back to JTPS`: confirm the evidence, send the task to JTPS with the report attached, re-enter at Step 6 with the revised plan (the worktree still exists; reset it to `origin/<default>` first if JTI reverted nothing). **Twice per task.** Third hand-back → the user.

## Step 14 — The report

For a human on their phone. Normal conversational English, developer vocabulary welcome, no lecturing. Short sentences a non-native speaker reads once. A little humour when it carries meaning.

**One task = one report.** Several tasks: sections 1 and 2 per task, one shared section 3.

**Section 1 — What happened** (~1 minute). The sequence as a short story: asked, planned, built, what broke, what fixed it, what proved it. Dead ends included — a hand-back or a failed browser check is the interesting part. End with branch, PR link, and the state of the main checkout (restored to what, anything the user must run).

**Section 2 — The problem and the fix** (~1 minute). What was broken and why it mattered, in support-person terms. What happens now, which flag controls it, what the user sees on, what is identical off.

**Section 3 — Developer shoptalk** (2–3 minutes, written as talking, not bullets). How it works under the hood with named files and functions. Why this approach and not the rejected ones — the most useful paragraph. Trade-offs taken knowingly. What surprised you in the codebase. What to watch after ship, and the first thing to check if it misbehaves. Noticed but deliberately not fixed. If something is ugly, say so and say why it stays.

**Closing line:** status, branch, PR, what you need from the reader.

Keep it proportionate. A one-line fix does not get three unrelated live bugs from the sceptic pasted in as bonus content — those go to Jira as separate tickets, or into one line under "noticed".

## Non-negotiables

- One writer per file. One worktree per writing agent. Max 4 concurrent writers, 12 read-only.
- **One UI slot per project root.** Acquire before touching the main checkout, services or browser. Release on every exit path.
- The main checkout is restored to its original branch when you are done, or the report says exactly why not.
- Never `Stop-Process` a PID you did not start. Never stash the user's changes. Ask.
- An ungated path is a blocker, not a note.
- Browser or boundary validation is never skipped, only relocated.
- A pipeline ending in `handed back` is a successful outcome, not something to bury.
- Never claim a build, test or browser result you did not see in an agent's report or your own terminal.
- Never `git add -A`. Explicit paths.
- Agents are named by their registered name — check the agent list; ATO agents carry the `ato-agents:` prefix.
- `/jcrew` is expected to finish a one-line fix in well under an hour. If it is heading past that, say where the time is going before continuing.
