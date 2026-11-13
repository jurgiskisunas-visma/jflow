---
name: friction-to-skill
description: Use when the same friction has happened twice in a session — the user repeats a correction, a command fails for a knowable environment reason, a review bot catches a bug class a local gate could have caught, or context had to be rediscovered. Also use when the user says "stop making me repeat this", "fix the skill not the output", or asks why they keep fighting the same thing.
---

# Friction to skill

Repeated friction is a tooling defect. The fix belongs in the generator — the hook, skill, CLAUDE.md rule, or memory note — not only in the current output. Fixing the output leaves the next session to relearn it.

## Trigger

Second occurrence, in one session, of any of:

| Signal | Example |
|---|---|
| Same correction repeated | "too technical" twice; "revert that, I said investigate only" |
| Knowable environment failure | piped to `jq` (not installed); bash syntax in PowerShell; expired `az` token |
| Late-caught bug class | review bot finds an un-reset counter, an ungated path |
| Rediscovered context | re-deriving a shard mapping, a flag number, a ticket convention |
| Same manual sequence typed out again | the third time you spell out the same 5 steps |

One occurrence is noise. Two is a pattern. Do not wait for three.

## Choose the mechanism — strongest that fits

| Mechanism | Guarantees | Use when | Lives in |
|---|---|---|---|
| **Hook** | Yes — runs every time, no model judgment | The rule is mechanically checkable (a command shape, a file pattern, a build after edit) | `~/.claude/hooks/*.ps1` + `settings.json`, or a plugin's `hooks.json` |
| **Skill** | No — model must invoke it | A multi-step procedure or judgment call recurs | `~/.claude/skills/<name>/SKILL.md`, or the repo's `.claude/skills/` if repo-specific |
| **CLAUDE.md line** | Advisory only | A short always-on constraint, not mechanically checkable | `~/.claude/CLAUDE.md` (all projects) or the repo's |
| **Memory note** | Recall only, probabilistic | A fact worth remembering that does not prescribe behaviour | the project memory dir |

Prefer the strongest mechanism that fits. A rule that can be a hook should not be a CLAUDE.md line — instructions get ignored under pressure, hooks do not.

## Procedure

1. **Name it in one line.** "Third time I've had to say investigate-only." No essay, no apology.
2. **Classify** the mechanism from the table above.
3. **Locate the existing generator first.** Grep the relevant `.claude/skills`, `CLAUDE.md`, and hooks before creating anything — the rule usually exists and is too weak, mis-scoped, or unregistered (a hook script with no `settings.json` entry runs never).
4. **Edit rather than add** where possible. Never add a rule without deleting or narrowing the one it overlaps — duplicated guidance is how CLAUDE.md files rot into being ignored.
5. **Match the form to the failure.** A skipped rule wants a prohibition plus the specific loophole closed. Wrong-shaped output wants a positive recipe stating what the output *is* — prohibitions measurably backfire there. A missing element wants a required slot in a template.
6. **Say the path, then apply.** Repo files and shared plugins: propose the edit and wait. `~/.claude/CLAUDE.md`, a user-level skill, or a memory note: apply immediately and report it in one line.
7. **Verify it fires.** A hook gets a payload smoke-test (`echo '<json>' | pwsh -NoProfile -File <script>`; expect exit 2 to block, 0 to pass). A skill gets tried on the next real instance — untested guidance is not a fix.

## Do not

- Do not turn a one-off into a rule. Two occurrences minimum.
- Do not write a rule for something a person would never mechanically repeat (taste that genuinely varies per artifact).
- Do not silently rewrite a shared plugin skill — those are org-wide; propose the change.
- Do not stack a new rule on top of a contradicting old one. Resolve the contradiction.
- Do not report "fixed the skill" without naming the file and what will now happen differently.

## Self-improvement

This skill is itself subject to its own rule. If the classification table sends you to the wrong mechanism twice, fix this file.
