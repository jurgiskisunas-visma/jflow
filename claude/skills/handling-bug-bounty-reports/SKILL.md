---
name: handling-bug-bounty-reports
description: Use when a Visma bug bounty (BUB) report is assigned or linked - validating whether a BUB case is real, re-scoring its severity, opening the ATO case for it, moving the BUB case to In Progress, or resolving it after a fix reaches Stage. Triggers on BUB-NNNN keys, jira.visma.com/browse/BUB-*, "bounty report", "Intigriti", "is this report valid", "bug bounty severity".
---

# Handling Bug Bounty Reports

Visma runs its bug bounty on Intigriti. Reports arrive as `BUB-NNNN` Jira cases assigned to the security engineer. This skill covers the whole path from a new report to a resolved one.

**Core principle: never accept or reject a claim without reading the code.** Researchers are often right about the pattern and wrong about the impact. Both halves matter.

## Stage detection

Work out which stage the case is in before doing anything. Check the BUB case status and whether an ATO case is linked to it.

| BUB status | ATO case linked? | Stage to run |
|---|---|---|
| Open / new | no | 1. Validate |
| Open, validated | no | 2. Decide and create the ATO case |
| Open | yes | 3. Move to In Progress + comment |
| In Progress | yes, Resolved, fix on Stage | 4. Resolve + comment |
| Open | no, but validation finds an existing ATO case whose fix is already on Stage | Link that ATO case (`Connect`), then go straight to 4. The comment proposes duplicate and gives a severity; no new ATO case. |

If it is unclear, ask which stage rather than guessing.

## Permissions

- **Validation**: run it. Read-only.
- **The decide step**: agree with the user first whether the case is worth working on. Do not create the ATO case before that.
- **ATO case**: create it directly once the decision is made. No draft needed - it is internal.
- **Every BUB comment**: draft it, show it, do not post until the user says so.
- **BUB status changes**: apply without asking, but only when the stage clearly calls for it (In Progress at stage 3, Resolved at stage 4).

## Keep this skill current

**When the user corrects you on how this work is done, update this file in the same turn.** The point of the skill is that a preference is stated once.

Signals that a correction just happened:

- A rule here is contradicted ("the tiers are different", "that field should be empty")
- A draft is rejected for its shape, length or tone ("too long", "too much", "simpler")
- A judgement is overruled ("that risk is low, not worth it", "this is overkill")
- A new fixed value appears (a field, a link type, a status, an epic)
- The user explains why something was wrong - the reason matters more than the correction

**Before editing, apply one test: will this apply to the next report too?**

- Yes, it is a standing rule → update this file.
- No, it is specific to this one case → do not write it down.

How to edit:

- Change the line that was wrong. Do not append a second rule next to it that says the opposite.
- Write the rule, and the reason when the reason is what makes it usable.
- Put it in the section it belongs to. Do not start a "notes" or "updates" pile at the end.
- Keep the file about the same size. If a section grows past its usefulness, tighten it rather than letting the skill spread.
- If the correction removes something the user asked for earlier, ask before deleting it.

Then say in one line what was updated. Do not narrate more than that.

Only do this when the correction is about **how bug bounty work is done**. Corrections about a specific code fix belong in the ATO case, not here.

---

## Stage 1 - Validate

Fan out one subagent per report. Reports arrive in batches, and a batch shares root causes - handling them one at a time hides the duplicates.

Each subagent must return, with `file:line` evidence for every statement:

1. **Verdict**: VALID / PARTIALLY VALID / INVALID.
2. **Every claim confirmed or refuted separately.** Researchers mix true and false claims in one report. List which is which.
3. **Is it already fixed?** Search git history and closed ATO cases. A previous bounty fix often already covers the exact PoC.
4. **Cross-tenant reachable?** This decides severity more than anything else. In ATO the answer is almost always no, because `BaseCompanyEntityRepository` adds `.Where(t => t.CompanyId == this.CompanyId)` to every query and stamps `CompanyId` on create. Verify it, do not assume it.
5. **Existing ATO cases** covering the same thing, so we do not open a duplicate.
6. **Fix shape**: shortest correct fix, which repo and file, and whether it needs a feature flag.

### Things that are easy to get wrong

- **The endpoint may not be in the repo the host name suggests.** Consolidated Accounts / Koncern endpoints are split between `core` and `Recon`. Check both.
- **Check whether an error string actually reaches the UI** before asking anyone to translate it. Many backend messages are swallowed by an HTTP client or never displayed, and the frontend often has its own translated message already.
- **A claim about how a file is served** needs the download endpoint read, not assumed. Content type, `Content-Disposition` and `nosniff` are usually already correct.

---

## Severity

Intigriti tiers, from the [Intigriti Bug Bounty Private Policy](https://confluence.visma.com/display/SECURITY/Intigriti+Bug+Bounty+Private+Policy) (Confluence, SECURITY space):

**Exceptional · Critical · High · Medium · Low**

`Informative`, `Duplicate` and `Out of scope` are **closing states, not severities**. Never propose them as a tier. The Confluence severity table mixes them into the same list - it is wrong on that point.

**BUB does not use CVSS.** Severity comes from the vulnerability class plus business impact. Do not argue a BUB severity with a CVSS vector - CVSS belongs to the separate pentest track (`SecTest_*` labels).

| Tier | Classes |
|---|---|
| Critical | RCE, SQL injection, authentication or authorization bypass |
| High | Local file inclusion, account takeover, mass PII extraction, XXE, vertical privilege escalation, horizontal privilege escalation **across customer contexts** |
| Medium | IDOR, horizontal privilege escalation **within the same customer context**, SSRF, XSS (any kind), CSRF, sensitive data exposure |
| Low | GUID-based IDOR, mass user enumeration, cleartext password submission, open redirect, HTML content injection |

**The levers that decide most ATO reports:**

- **The customer boundary is the one-band split.** Across customer contexts = High. Within one = Medium. Nothing that stays inside one tenant goes above Medium.
- **Denial of service is out of scope.** This includes storage growth and "unlimited resource" arguments.
- **"No impact means no bounty."** Business impact adjusts severity in both directions.
- **Own-tenant data integrity has no tier.** Missing server-side validation of a business rule is not in the policy at all. If the user can already change that data through the UI, it lands at Low.
- **Duplicates are broad**: the same endpoint counts regardless of HTTP verb while the fix is not applied, and a thing we already knew internally counts as a duplicate even if the researcher reported it first.

If the severity should change, say so in the comment with the reason (see stage 3).

---

## Stage 2 - Create the ATO case

Agree with the user first on the grouping and the fix scope. A valid or partially valid report always gets fixed, even at Low - the tier sets the payout, not whether we fix it. Never offer "close as low value" for a confirmed gap; only the expensive-fix rule below can trim scope.

Group by where the fix lands: same repo + same handler/validator = one ATO case; a different repo = its own case. Our own findings that no researcher reported get a separate ATO case with no BUB link.

**Fixed fields:**

| Field | Value |
|---|---|
| Issue type | `Standalone technical task` |
| Epic Link (`customfield_13061`) | `ATO-8` (Security) |
| Link to the BUB case | link type **`Connect`** - a mention in the text is not enough |
| Feature Flag (`customfield_21760`) | leave empty - the flag number comes from the repo's next-to-use pointer at implementation time |
| Assignee | leave unassigned so the team can pick it up |

**Title:** short and plain. Say what is missing, not what could happen.

- Good: `Validate exchange rates server-side in consolidated accounts settings`
- Good: `Validate shareOwnedCapital server-side on GroupVoucher create and update`
- Bad: `Potential data integrity risk in the consolidation module`

Most of these reports are missing server-side validation. Call it that. Do not invent a more dramatic framing.

**Description - always these sections, in this order:**

```
h3. Problem

[2-4 sentences: what is missing, and what the API accepts because of it.
Then say why it is bad and why we fix it - the real consequence, not a
hypothetical one. Include a short concrete example if it makes it clearer.]

h3. Steps to reproduce

# [numbered, from the UI, ending at the observable wrong result]

h3. Proposed fix

[The shortest correct fix. Name the file and method. Say whether it needs a
feature flag and which enum. Be prescriptive: show the way, with pseudo code
where it helps, and say which options we considered and rejected and why.]

h3. Acceptance criteria

* [one line per checkable outcome]
* [always include: normal use still works]
* [always include: old behaviour kept behind the flag, if flagged]

h3. References

* Report: BUB-NNNN
* [existing ATO cases worth copying or citing]
```

Add `h3. Concerns and things to check` as a bullet list when there are traps the developer could miss. Point at *where to look*, not a full list of everything affected - the repro steps are the starting point and the developer investigates from there.

### Do not propose expensive fixes with low value

Judge effort against risk before writing the fix section. Skip anything that costs a lot to build and maintain but removes little risk.

Examples of fixes to leave out:
- Validating a storage id against Blob Storage to prove the blob exists
- Any cross-service consistency check to catch a problem the user could cause anyway through supported use
- Rewriting a working mechanism because a report described it inaccurately

If the report asks for one of these, say in the comment that we looked at it and chose not to, and why.

### Team pickup post

When asked to post the pickup message, post without another draft round (format agreed 2026-10-16).

- **Channel:** `#spi-tax_annualaccounts-coding` (`C0A9491730S`).
- **Which tasks:** bounty-derived ATO cases that are Open and unassigned: `project = ATO AND "Epic Link" = ATO-8 AND status = Open AND assignee is EMPTY AND (text ~ "BUB*" OR text ~ "\"bug bounty\"")`. The text filter matters - ATO-8 also holds old non-bounty tasks. Plain `text ~ "BUB"` returns nothing. Internal findings are included because their description names the BUB they came from. Nothing ready → say so, post nothing.
- **Main message**, then **one thread reply per task** so people claim by reacting:

Slack MCP takes standard markdown (`**bold**`, `[text](url)`), not Slack mrkdwn. Post the main message, then each task with `thread_ts` = its ts.

```
:shield: **New bug bounty security tasks are ready to pick up**

Each task is in the thread below. To take one, react on the task with :raising_hand: and assign the Jira case to yourself.
Every case has the steps to reproduce, the proposed fix and the acceptance criteria. All need a new feature flag.
```

```
[:rotating_light: if urgent ]**[ATO-NNNNN](https://jira.visma.com/browse/ATO-NNNNN)** · <Repo / area> · <size or **please take first**>
<Jira title>
<one plain sentence: what is wrong, or what to check first>
```

- No BUB keys and no exploit detail - say what is missing, not how to abuse it.
- Urgent tasks first.

---

## Stage 3 - In Progress + comment

Set the BUB case to **In Progress**. Then draft this comment.

Keep it short. Two short paragraphs is normal.

```
We validated this report against our code and confirmed [what holds].
[If parts did not reproduce, one sentence saying which and why.]
We have created an internal task and will start working on it.

[Severity paragraph - only if it should change. See below.]

Thanks for the report.
```

**Severity paragraph** - include only when the tier should change:

```
On severity: we would suggest [tier] rather than [current tier], because
[reason in one or two sentences - usually that the impact stays inside the
reporter's own customer context, or that the class is excluded from the
programme scope]. That is of course a call for the bug bounty team.
```

---

## Stage 4 - Resolve + comment

Only when the fix is merged **and** deployed to Stage - the bounty programme runs against Stage. For a flagged fix this means the feature flag is **active on Stage**, not just that the code is deployed.

Set the BUB case to **Resolved**, then **reassign it to whoever was assigned before you** - check the case history for the previous assignee. The MCP does not return the changelog and REST returns 403 on BUB, so use the comments: the person who pinged you with "another report for you" is the one to hand back to (`vilte.grazuleviciute` or `sofia.leino` so far - check, it varies per case). This hands it back to the bug bounty team so they can pay out, close it, or ask the researcher to re-test.

Then draft this comment.

```
Our team has resolved the issue, and the fix is live on the Staging environment.

[1-2 sentences on what changed, in plain terms - what the server does now
that it did not do before.]

[Any caveat or mismatch with the report. Required if there is one - see below.]
```

Three parts, nothing else. Do not invite the researcher to re-test - they will anyway. Do not repeat the severity or disposition here; that was said at stage 3 and belongs to the bug bounty team.

**Only add a note when the report claimed something and we found otherwise.** The note corrects the record. Examples worth writing:

- Part of the report did not reproduce
- The report said a control was missing, but it was already there
- Something in the report was already fixed before it was submitted
- We deliberately did not do one of the things the report asked for, and why

**Do not write a note about extra work we did.** If the fix went wider than the report, or covered places the researcher never found, keep it to ourselves. That is not a correction, it is bragging.

---

## Writing rules for everything the researcher or the team reads

We work in a team where nobody is a native English speaker. Simple English is a requirement, not a style preference.

- Short sentences. One idea each.
- Common words. `use` not `utilise`, `enough` not `sufficient`, `about` not `regarding`, `so` not `consequently`.
- No idioms, no metaphors, no jokes that depend on English.
- Active voice where it is natural.
- Say the thing directly. Do not build up to it.
- This applies to ATO case descriptions too, not only BUB comments.

## BUB comments are read by the researcher

BUB cases sync to Intigriti. Assume every comment reaches the person who reported it.

**Answer only what is in this BUB case and its comments.** The BUB case is the whole context. If something was discussed in the ATO case, in a pull request, or between us and it is not part of what this researcher reported, it does not go in the comment - even when it is true and related.

This matters most when one ATO case covers several BUB cases. Each BUB case gets a comment about its own report only. Do not describe a change that belongs to the neighbouring report.

**Never put in a BUB comment:**
- Details of a vulnerability that is still unfixed
- Findings we made that the researcher did not report - that is handing over free findings
- Internal ticket keys, file paths, branch names, feature flag names
- Anything about how our infrastructure is built

## Common mistakes

| Mistake | Do this instead |
|---|---|
| Proposing `Informative` or `Out of scope` as a severity | They are closing states. Propose a tier, or propose closing. |
| Scoring with CVSS | BUB uses the class table plus impact. |
| Accepting the report's impact claim | Check cross-tenant reachability yourself. It is usually not reachable. |
| Rejecting a report because one claim is wrong | Split it. Confirm and refute each claim separately. |
| Opening one ATO case per BUB case | Group by root cause. Two reports on the same handler are one case. |
| Writing a long ATO description | Problem, repro, fix, criteria. Nothing else. |
| Asking for translation of a backend string | Check first whether it reaches the UI at all. |
| Resolving the BUB case when the PR merges | Wait until it is on Stage. |

## Self-improvement

If a BUB case exposes a rule or trap this skill does not cover - a policy lever, a Jira field, a wording constraint - add it here in the same session (per `friction-to-skill`). Next report should not rediscover it.
