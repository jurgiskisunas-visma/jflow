# ATO: project notes

What a session should know before working here. One dated line per fact; delete a line that turns out wrong. Under 60 lines.

## Traps

- 2026-11-13: Several repos hold untracked secret files that git does not ignore (`tna/build/docker/.env`, `taxation/docs/local-secrets-*.md`). Stage explicit paths only; the hook blocks sweeping `git add`.
- 2026-11-13: Six Core project files run `TASKKILL /F /IM` in a build target. A build in one checkout can kill services started from another.
- 2026-11-13: Marketplace skills that test `[ -d ".git" ]` stop in a linked worktree. Run them from the main checkout.
- 2026-11-13: `az` tokens expire daily. Refresh before telemetry queries, or use the Grafana path.

## Environment

- 2026-11-13: Two stacks can run side by side: native on ports 5xxx from `D:\Projects\ATO`, Aspire on ports 15xxx from `D:\Projects\ato-host` (`D:\Projects\ato.apphost` is an older copy, last commit 2026-09-11).
- 2026-11-13: Aspire ports are constants in `ato-host\src\AtoHost.AppHost\AtoEndpoints.cs`; the CORS lists and the login redirect in `build/docker/local-config*.env` repeat them as literals.

## What works

- 2026-11-13: Every behaviour change behind a feature flag; reviewers ask for it otherwise.
