# PowerShell Completers

This repository contains standalone PowerShell argument completer scripts for native tools. Each top-level `*_completer.ps1` file is self-contained and intended to be dot-sourced into a PowerShell session or profile. The companion `*_completer.md` files document what each completer covers and how it works.

## Quick start

From the repository root, dot-source one or more completer scripts into the current session:

```powershell
. .\Git_completer.ps1

# Load more than one completer if you want
. .\dotnet_completer.ps1
. .\gh_cli_completer.ps1
```

To make selected completers available in future sessions, dot-source them from your PowerShell profile:

```powershell
. 'C:\path\to\Completers\Git_completer.ps1'
. 'C:\path\to\Completers\dotnet_completer.ps1'
```

## Repository layout

- `*_completer.ps1`: standalone PowerShell argument completer scripts
- `*_completer.md`: companion repository docs for each completer

## Completer index

| Command(s) | Script | Doc | Notes |
| --- | --- | --- | --- |
| `7z`, `7z.exe` | [7z_completer.ps1](7z_completer.ps1) | [7z_completer.md](7z_completer.md) | Native PowerShell argument completer for 7-Zip. |
| `dism` | [dism_completer.ps1](dism_completer.ps1) | [dism_completer.md](dism_completer.md) | Native PowerShell argument completer for Deployment Image Servicing and Management. |
| `dotnet` | [dotnet_completer.ps1](dotnet_completer.ps1) | [dotnet_completer.md](dotnet_completer.md) | Large static completion table for the .NET CLI. |
| `dsc` | [DSC_completer.ps1](DSC_completer.ps1) | [DSC_completer.md](DSC_completer.md) | Native PowerShell argument completer for the `dsc` CLI. |
| `gh` | [gh_cli_completer.ps1](gh_cli_completer.ps1) | [gh_cli_completer.md](gh_cli_completer.md) | Loads the official PowerShell completion script emitted by the installed GitHub CLI. |
| `git` | [Git_completer.ps1](Git_completer.ps1) | [Git_completer.md](Git_completer.md) | Builds completions from the installed Git CLI plus repository-local fallback data. |
| `icacls`, `icacls.exe` | [icacls_completer.ps1](icacls_completer.ps1) | [icacls_completer.md](icacls_completer.md) | Parses `icacls.exe /?` output and layers command-context completion on top. |
| `oh-my-posh`, `oh-my-posh.exe` | [OhMyPosh_completer.ps1](OhMyPosh_completer.ps1) | [OhMyPosh_completer.md](OhMyPosh_completer.md) | PowerShell argument completer for Oh My Posh. |
| `robocopy`, `robocopy.exe` | [robocopy_completer.ps1](robocopy_completer.ps1) | [robocopy_completer.md](robocopy_completer.md) | Native PowerShell argument completer for Robocopy. |
| `schtasks`, `schtasks.exe` | [schtasks_completer.ps1](schtasks_completer.ps1) | [schtasks_completer.md](schtasks_completer.md) | Native PowerShell argument completer for Scheduled Tasks CLI usage. |
| `tasklist`, `tasklist.exe` | [tasklist_completer.ps1](tasklist_completer.ps1) | [tasklist_completer.md](tasklist_completer.md) | Native PowerShell argument completer for Task List. |
| `tskill`, `tskill.exe` | [tskill_completer.ps1](tskill_completer.ps1) | [tskill_completer.md](tskill_completer.md) | Native PowerShell argument completer for Terminal Server task termination. |
| `uv`, `uv.exe`, `uvx`, `uvx.exe` | [uv_completer.ps1](uv_completer.ps1) | [uv_completer.md](uv_completer.md) | Native PowerShell argument completer for Astral's `uv` and `uvx`. |
| `wevtutil`, `wevtutil.exe` | [wevtutil_completer.ps1](wevtutil_completer.ps1) | [wevtutil_completer.md](wevtutil_completer.md) | Native PowerShell argument completer for Windows Event Utility. |
| `where.exe` | [where_completer.ps1](where_completer.ps1) | [where_completer.md](where_completer.md) | Native PowerShell argument completer for `where.exe`. |
| `wsl` | [wsl_completer.ps1](wsl_completer.ps1) | [wsl_completer.md](wsl_completer.md) | Native PowerShell argument completer for Windows Subsystem for Linux. |
| `wt`, `wt.exe` | [wt_completer.ps1](wt_completer.ps1) | [wt_completer.md](wt_completer.md) | Native PowerShell argument completer for Windows Terminal. |

## Notes

- Each completer is intended to work independently; there is no module manifest or build step in this repository.
- Some completers are static, while others depend on the installed native tool or its help output at completion time. The companion `.md` file for each script describes those details.
