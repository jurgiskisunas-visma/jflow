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

`install.ps1` is safe to re-run. It installs missing tools with winget, adds the marketplaces and plugins from `plugins.json`, copies `claude\` into `~/.claude` (a differing file is backed up to `~/.claude/backups/` first), registers the hooks in `settings.json`, tests and builds `jplan`, puts it on the user PATH, seeds the planning root with the project profiles and runs the hook tests.

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
- **Task data.** The planning root (`D:\project-planning`: tasks, research, ideas, live profiles and notes) is not in this repo. Restore it from its own backup.
- **Repos.** Clone the ATO and e-accounting repos; the paths in `profiles\*.json` expect `D:\Projects\ATO`, `D:\Projects\ato-host` and `D:\Projects\eaccounting`.
- **Other `settings.json` values.** Permission mode, auto-mode rules and effort level are not copied.

## Known limits

- Windows only: the hooks and the installer are PowerShell.
- The user path `C:/Users/jurgis.kisunas` is hardcoded in JTPS, JTI, two commands, `jurgis-crew` and `profiles\ato.json`.
- `/jflow` has not run on a real task yet. The outbound gate's prompt has not been seen in a live session.
