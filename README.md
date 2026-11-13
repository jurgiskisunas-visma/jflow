# jflow

Personal agentic development workflow for Claude Code: a task ledger (`jplan`), a pipeline (`/jflow`), safety hooks, agents, skills and the plugin set they rely on. This repo is the source of truth; `~/.claude` holds an installed copy.

The idea, the build log and the improvement paths are in [docs/how-it-works.md](docs/how-it-works.md).

## New machine

1. Install Claude Code and sign in. Install PowerShell 7 and `winget` if missing.
2. `gh auth login` with the Visma account (the ATO marketplace is private).
3. Clone and install:

```powershell
gh repo clone jurgiskisunas-visma/jflow D:\Projects\jflow
pwsh -File D:\Projects\jflow\install.ps1
```

4. Open a new terminal and restart Claude Code.
5. Do the steps under "Not automated".

`install.ps1` is safe to re-run. It installs missing tools with winget (Go included, which `jplan` needs to build), adds the marketplaces and plugins from `plugins.json`, copies `claude\` into `~/.claude` (a differing file is backed up to `~/.claude/backups/` first), registers the hooks in `settings.json`, tests and builds `jplan` into `~/.claude/bin`, puts that folder on the user PATH, seeds the planning root with the project profiles and runs the hook tests.

### Planning root

The planning root holds the task ledger, the live profiles and the project notes. It is a per-machine choice:

```powershell
pwsh -File D:\Projects\jflow\install.ps1 -PlanningRoot E:\plans
```

Without the parameter the installer keeps the root it used before, and on a first run it uses `~/project-planning`. The choice is stored in `~/.claude/jflow.json`. `jplan root` prints it, and the skills ask `jplan` for the root, so no file names a drive. `JPLAN_ROOT` overrides the file for one shell.

## What is in here

| Path | Content |
|---|---|
| `claude\CLAUDE.md` | User-level rules for every session |
| `claude\skills\jflow` | Pipeline v2: implement, investigate and review tracks |
| `claude\skills\*` | Other personal skills (`jurgis-crew`, `write-for-review`, `clean-code`, `harden-pr`, `friction-to-skill` and domain skills) |
| `claude\agents` | JTPS (planner) and JTI (implementer) |
| `claude\commands` | `/jflow`, `/jcrew`, `/jtps`, `/jti` |
| `claude\hooks` | `user-guard.ps1` (secret-file guard and outbound approval gate), `jcrew-ui-lock.ps1` (validation slot lock), implementer gate, tests |
| `jplan\` | The ledger tool in Go, with tests |
| `profiles\` | Project profiles (`<project>.json`) and project notes (`<project>.md`); seeds for the planning root |
| `plugins.json` | Marketplaces, plugins, tools and language servers this setup needs |
| `docs\` | How it works, build log, improvement paths |

## Daily use

```powershell
jplan ls                         # what is open
jplan new ato ATO-12345 title="..." type=implement
jplan idea "something to look at later"
```

In Claude Code: `/jflow ATO-12345`, or `/jflow investigate <question>`.

## Changing the workflow

Edit files in this repo, not in `~/.claude`. Then:

```powershell
pwsh -File D:\Projects\jflow\install.ps1 -SkipTools -SkipPlugins
```

Commit with a message that says why. The Improve step of `/jflow` proposes changes from `jplan stats`; each accepted change is a commit here and a line in `_profiles\improvements.md` in the planning root.

## Not automated

- **MCP servers.** Playwriter, Azure, Confluence, the SQL servers and the claude.ai connectors (Jira, Slack) are configured per machine and hold credentials. Set them up with `claude mcp` and the claude.ai connector settings.
- **Language servers.** The two commands under `languageServers` in `plugins.json`.
- **Task data.** The planning root (tasks, research, ideas, live profiles and notes) is not in this repo. Restore it from its own backup.
- **Repos.** Clone the ATO and e-accounting repos. The seed profiles in `profiles\*.json` name `D:\Projects\ATO`, `D:\Projects\ato-host` and `D:\Projects\eaccounting`; with other paths, edit the live profile in `<planning root>\_profiles\`, or let `/jflow` ask and fix it on first use.
- **Other `settings.json` values.** Permission mode, auto-mode rules and effort level are not copied.

## Known limits

- Windows only: the hooks and the installer are PowerShell.
- `claude\CLAUDE.md` is one person's rule file. The installer replaces `~/.claude/CLAUDE.md` with it (the old file goes to `~/.claude/backups/`), so someone else must merge their own rules back in.
- `plugins.json` lists the private ATO marketplace; without access to it those installs are reported as problems and the rest still works.
- The outbound gate's prompt has not been seen in a live session.
