# PowerShell Completers

This repository contains standalone PowerShell argument completer scripts for native tools. Each `*_completer` folder contains a self-contained `*_completer.ps1` script that can be dot-sourced into a PowerShell session or profile, plus a companion `*_completer.md` document describing coverage and implementation details.

## Quick start

From the repository root, dot-source one or more completer scripts into the current session:

```powershell
. .\Git_completer\Git_completer.ps1

# Load more than one completer if you want
. .\dotnet_completer\dotnet_completer.ps1
. .\gh_cli_completer\gh_cli_completer.ps1
```

To make selected completers available in future sessions, dot-source them from your PowerShell profile:

```powershell
. 'C:\path\to\Completers\Git_completer\Git_completer.ps1'
. 'C:\path\to\Completers\dotnet_completer\dotnet_completer.ps1'
```

## Repository layout

- `*_completer\`: one folder per completer
- `*_completer\*_completer.ps1`: standalone PowerShell argument completer script
- `*_completer\*_completer.md`: companion repository doc for that completer

## Completer index

| Command(s) | Script | Doc | Notes |
| --- | --- | --- | --- |
| `7z`, `7z.exe` | [7z_completer.ps1](7z_completer/7z_completer.ps1) | [7z_completer.md](7z_completer/7z_completer.md) | Native PowerShell argument completer for 7-Zip. |
| `dism` | [dism_completer.ps1](dism_completer/dism_completer.ps1) | [dism_completer.md](dism_completer/dism_completer.md) | Native PowerShell argument completer for Deployment Image Servicing and Management. |
| `dotnet` | [dotnet_completer.ps1](dotnet_completer/dotnet_completer.ps1) | [dotnet_completer.md](dotnet_completer/dotnet_completer.md) | Large static completion table for the .NET CLI. |
| `dsc` | [DSC_completer.ps1](DSC_completer/DSC_completer.ps1) | [DSC_completer.md](DSC_completer/DSC_completer.md) | Native PowerShell argument completer for the `dsc` CLI. |
| `gh` | [gh_cli_completer.ps1](gh_cli_completer/gh_cli_completer.ps1) | [gh_cli_completer.md](gh_cli_completer/gh_cli_completer.md) | Loads the official PowerShell completion script emitted by the installed GitHub CLI. |
| `git` | [Git_completer.ps1](Git_completer/Git_completer.ps1) | [Git_completer.md](Git_completer/Git_completer.md) | Builds completions from the installed Git CLI plus repository-local fallback data. |
| `icacls`, `icacls.exe` | [icacls_completer.ps1](icacls_completer/icacls_completer.ps1) | [icacls_completer.md](icacls_completer/icacls_completer.md) | Parses `icacls.exe /?` output and layers command-context completion on top. |
| `npm`, `npm.cmd`, `npm.exe`, `npm.ps1` | [npm_completer.ps1](npm_completer/npm_completer.ps1) | [npm_completer.md](npm_completer/npm_completer.md) | Hybrid npm completer that combines static command data, parsed help output, and local project metadata. |
| `oh-my-posh`, `oh-my-posh.exe` | [OhMyPosh_completer.ps1](OhMyPosh_completer/OhMyPosh_completer.ps1) | [OhMyPosh_completer.md](OhMyPosh_completer/OhMyPosh_completer.md) | PowerShell argument completer for Oh My Posh. |
| `robocopy`, `robocopy.exe` | [robocopy_completer.ps1](robocopy_completer/robocopy_completer.ps1) | [robocopy_completer.md](robocopy_completer/robocopy_completer.md) | Native PowerShell argument completer for Robocopy. |
| `schtasks`, `schtasks.exe` | [schtasks_completer.ps1](schtasks_completer/schtasks_completer.ps1) | [schtasks_completer.md](schtasks_completer/schtasks_completer.md) | Native PowerShell argument completer for Scheduled Tasks CLI usage. |
| `tasklist`, `tasklist.exe` | [tasklist_completer.ps1](tasklist_completer/tasklist_completer.ps1) | [tasklist_completer.md](tasklist_completer/tasklist_completer.md) | Native PowerShell argument completer for Task List. |
| `tskill`, `tskill.exe` | [tskill_completer.ps1](tskill_completer/tskill_completer.ps1) | [tskill_completer.md](tskill_completer/tskill_completer.md) | Native PowerShell argument completer for Terminal Server task termination. |
| `uv`, `uv.exe`, `uvx`, `uvx.exe` | [uv_completer.ps1](uv_completer/uv_completer.ps1) | [uv_completer.md](uv_completer/uv_completer.md) | Native PowerShell argument completer for Astral's `uv` and `uvx`. |
| `wevtutil`, `wevtutil.exe` | [wevtutil_completer.ps1](wevtutil_completer/wevtutil_completer.ps1) | [wevtutil_completer.md](wevtutil_completer/wevtutil_completer.md) | Native PowerShell argument completer for Windows Event Utility. |
| `where.exe` | [where_completer.ps1](where_completer/where_completer.ps1) | [where_completer.md](where_completer/where_completer.md) | Native PowerShell argument completer for `where.exe`. |
| `wsl` | [wsl_completer.ps1](wsl_completer/wsl_completer.ps1) | [wsl_completer.md](wsl_completer/wsl_completer.md) | Native PowerShell argument completer for Windows Subsystem for Linux. |
| `wt`, `wt.exe` | [wt_completer.ps1](wt_completer/wt_completer.ps1) | [wt_completer.md](wt_completer/wt_completer.md) | Native PowerShell argument completer for Windows Terminal. |

## Notes

- Each completer is intended to work independently; there is no module manifest or build step in this repository.
- Some completers are static, while others depend on the installed native tool or its help output at completion time. The companion `.md` file for each script describes those details.
