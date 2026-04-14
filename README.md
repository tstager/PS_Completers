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
| `accesschk`, `accesschk.exe` | [accesschk_completer.ps1](accesschk_completer/accesschk_completer.ps1) | [accesschk_completer.md](accesschk_completer/accesschk_completer.md) | Native PowerShell argument completer for AccessChk with mode-aware service, process, registry, and path hints. |
| `autorunsc`, `autorunsc.exe` | [autorunsc_completer.ps1](autorunsc_completer/autorunsc_completer.ps1) | [autorunsc_completer.md](autorunsc_completer/autorunsc_completer.md) | Native PowerShell argument completer for Autorunsc with validated category filters, offline path slots, and local profile hints. |
| `bun`, `bun.exe` | [bun_completer.ps1](bun_completer/bun_completer.ps1) | [bun_completer.md](bun_completer/bun_completer.md) | Hybrid Bun completer that merges parsed help output with static commands and local project metadata. |
| `contig`, `contig.exe` | [contig_completer.ps1](contig_completer/contig_completer.ps1) | [contig_completer.md](contig_completer/contig_completer.md) | Static-first Contig completer with mode-aware file, metadata, drive, and length suggestions. |
| `copilot`, `copilot.exe` | [copilot_completer.ps1](copilot_completer/copilot_completer.ps1) | [copilot_completer.md](copilot_completer/copilot_completer.md) | Hybrid GitHub Copilot CLI completer with a static argv tree plus dynamic local values for models, marketplaces, and installed plugins. |
| `curl`, `curl.exe` | [curl_completer.ps1](curl_completer/curl_completer.ps1) | [curl_completer.md](curl_completer/curl_completer.md) | Help-driven curl completer with enum-aware value hints, `@file` handling, and path completion for file-bearing options. |
| `dism` | [dism_completer.ps1](dism_completer/dism_completer.ps1) | [dism_completer.md](dism_completer/dism_completer.md) | Native PowerShell argument completer for Deployment Image Servicing and Management. |
| `dotnet` | [dotnet_completer.ps1](dotnet_completer/dotnet_completer.ps1) | [dotnet_completer.md](dotnet_completer/dotnet_completer.md) | Large static completion table for the .NET CLI. |
| `dsc` | [DSC_completer.ps1](DSC_completer/DSC_completer.ps1) | [DSC_completer.md](DSC_completer/DSC_completer.md) | Native PowerShell argument completer for the `dsc` CLI. |
| `du`, `du.exe` | [du_completer.ps1](du_completer/du_completer.ps1) | [du_completer.md](du_completer/du_completer.md) | Help-driven `du` completer with `-ct`, `-l` value hints, and directory-only operand completion. |
| `findstr`, `findstr.exe` | [findstr_completer.ps1](findstr_completer/findstr_completer.ps1) | [findstr_completer.md](findstr_completer/findstr_completer.md) | Static-first `findstr` completer with attached `/A:` `/C:` `/D:` `/F:` `/G:` `/Q:` handling, placeholder-safe search-string slots, and local file/directory completion. |
| `fsutil`, `fsutil.exe` | [fsutil_completer.ps1](fsutil_completer/fsutil_completer.ps1) | [fsutil_completer.md](fsutil_completer/fsutil_completer.md) | Native PowerShell argument completer for `fsutil` with cached local help-driven command discovery and targeted value-aware leaf completion. |
| `gawk`, `gawk.exe`, `awk`, `awk.exe` | [gawk_completer.ps1](gawk_completer/gawk_completer.ps1) | [gawk_completer.md](gawk_completer/gawk_completer.md) | Hybrid GNU awk completer with help-validated options, safe long-option abbreviations, and value-aware file/assignment completion. |
| `groff`, `groff.exe` | [groff_completer.ps1](groff_completer/groff_completer.ps1) | [groff_completer.md](groff_completer/groff_completer.md) | Hybrid GNU groff completer with static option grammar, cached local `-T` and `-m` discovery, and attached/separate value completion. |
| `handle`, `handle.exe` | [handle_completer.ps1](handle_completer/handle_completer.ps1) | [handle_completer.md](handle_completer/handle_completer.md) | Native PowerShell argument completer for Sysinternals Handle with safe help parsing, local `-p` hints, and placeholder-driven close-handle completion. |
| `gh` | [gh_cli_completer.ps1](gh_cli_completer/gh_cli_completer.ps1) | [gh_cli_completer.md](gh_cli_completer/gh_cli_completer.md) | Loads the official PowerShell completion script emitted by the installed GitHub CLI. |
| `git` | [Git_completer.ps1](Git_completer/Git_completer.ps1) | [Git_completer.md](Git_completer/Git_completer.md) | Builds completions from the installed Git CLI plus repository-local fallback data. |
| `icacls`, `icacls.exe` | [icacls_completer.ps1](icacls_completer/icacls_completer.ps1) | [icacls_completer.md](icacls_completer/icacls_completer.md) | Parses `icacls.exe /?` output and layers command-context completion on top. |
| `ipconfig`, `ipconfig.exe` | [ipconfig_completer.ps1](ipconfig_completer/ipconfig_completer.ps1) | [ipconfig_completer.md](ipconfig_completer/ipconfig_completer.md) | Native PowerShell argument completer for `ipconfig` with help-driven switches and cached adapter-name completion. |
| `just`, `j`, `just.exe` | [just_completer.ps1](just_completer/just_completer.ps1) | [just_completer.md](just_completer/just_completer.md) | Thin wrapper around `just`'s built-in PowerShell completion output. |
| `listdlls`, `listdlls.exe`, `Listdlls`, `Listdlls.exe` | [listdlls_completer.ps1](listdlls_completer/listdlls_completer.ps1) | [listdlls_completer.md](listdlls_completer/listdlls_completer.md) | Native PowerShell argument completer for Sysinternals Listdlls with safe help parsing, local process hints, and placeholder DLL-name completion. |
| `netsh`, `netsh.exe` | [netsh_completer.ps1](netsh_completer/netsh_completer.ps1) | [netsh_completer.md](netsh_completer/netsh_completer.md) | Native PowerShell argument completer for `netsh` with lazy help-driven context discovery. |
| `npm`, `npm.cmd`, `npm.exe`, `npm.ps1` | [npm_completer.ps1](npm_completer/npm_completer.ps1) | [npm_completer.md](npm_completer/npm_completer.md) | Hybrid npm completer that combines static command data, parsed help output, and local project metadata. |
| `oh-my-posh`, `oh-my-posh.exe` | [OhMyPosh_completer.ps1](OhMyPosh_completer/OhMyPosh_completer.ps1) | [OhMyPosh_completer.md](OhMyPosh_completer/OhMyPosh_completer.md) | PowerShell argument completer for Oh My Posh. |
| `pi`, `pi.cmd`, `pi.ps1` | [pi_completer.ps1](pi_completer/pi_completer.ps1) | [pi_completer.md](pi_completer/pi_completer.md) | Hybrid static-first Pi completer with root command/flag coverage, provider/tool/thinking enums, `@file` completion, and local model/source hints. |
| `playwright-cli`, `playwright-cli.cmd`, `playwright-cli.ps1` | [playwright_cli_completer.ps1](playwright_cli_completer/playwright_cli_completer.ps1) | [playwright_cli_completer.md](playwright_cli_completer/playwright_cli_completer.md) | Static-first Playwright CLI completer with full top-level verb coverage, option/value hints, path-aware file slots, and placeholder-driven browser/session targeting. |
| `procdump`, `procdump.exe` | [procdump_completer.ps1](procdump_completer/procdump_completer.ps1) | [procdump_completer.md](procdump_completer/procdump_completer.md) | Native PowerShell argument completer for ProcDump with static trigger grammar, value-aware numeric placeholders, and safe local target hints. |
| `psgetsid`, `psgetsid.exe` | [psgetsid_completer.ps1](psgetsid_completer/psgetsid_completer.ps1) | [psgetsid_completer.md](psgetsid_completer/psgetsid_completer.md) | Native PowerShell argument completer for PsGetsid with remote-target-aware switches, `@file` completion, and free-form identity placeholders. |
| `psexec`, `psexec.exe` | [psexec_completer.ps1](psexec_completer/psexec_completer.ps1) | [psexec_completer.md](psexec_completer/psexec_completer.md) | Static-first PsExec completer with remote-target placeholders, value-aware switch hints, and conservative command-tail handling. |
| `psfile`, `psfile.exe` | [psfile_completer.ps1](psfile_completer/psfile_completer.ps1) | [psfile_completer.md](psfile_completer/psfile_completer.md) | Static PsFile completer with remote-auth placeholders, identifier hints, and destructive `-c` awareness. |
| `psinfo`, `psinfo.exe` | [psinfo_completer.ps1](psinfo_completer/psinfo_completer.ps1) | [psinfo_completer.md](psinfo_completer/psinfo_completer.md) | Static-first PsInfo completer with filter hints, delimiter guidance, and safe remote-target completion. |
| `pskill`, `pskill.exe` | [pskill_completer.ps1](pskill_completer/pskill_completer.ps1) | [pskill_completer.md](pskill_completer/pskill_completer.md) | Native PowerShell argument completer for PsKill with local process/PID hints and placeholder-only remote targeting. |
| `psloglist`, `psloglist.exe` | [psloglist_completer.ps1](psloglist_completer/psloglist_completer.ps1) | [psloglist_completer.md](psloglist_completer/psloglist_completer.md) | Hybrid PsLogList completer with static syntax, cached local event-log hints, and remote-safe fallbacks. |
| `psping`, `psping.exe` | [psping_completer.ps1](psping_completer/psping_completer.ps1) | [psping_completer.md](psping_completer/psping_completer.md) | Hybrid PsPing completer with static mode grammar, help-topic completion, and value-aware placeholders for ping, latency, bandwidth, and server syntax. |
| `pslist`, `pslist.exe` | [pslist_completer.ps1](pslist_completer/pslist_completer.ps1) | [pslist_completer.md](pslist_completer/pslist_completer.md) | Native PowerShell argument completer for PsList with static-first switch grammar, remote-target placeholders, and local process hints. |
| `pspasswd`, `pspasswd.exe` | [pspasswd_completer.ps1](pspasswd_completer/pspasswd_completer.ps1) | [pspasswd_completer.md](pspasswd_completer/pspasswd_completer.md) | Static PsPasswd completer with safe remote placeholders, account hints, and password-slot suppression. |
| `psservice`, `psservice.exe` | [psservice_completer.ps1](psservice_completer/psservice_completer.ps1) | [psservice_completer.md](psservice_completer/psservice_completer.md) | Native PowerShell argument completer for PsService with remote-preamble awareness and local service-name hints. |
| `psshutdown`, `psshutdown.exe` | [psshutdown_completer.ps1](psshutdown_completer/psshutdown_completer.ps1) | [psshutdown_completer.md](psshutdown_completer/psshutdown_completer.md) | Native PowerShell argument completer for PsShutdown with value-aware placeholders and safe remote-target completion. |
| `pssuspend`, `pssuspend.exe` | [pssuspend_completer.ps1](pssuspend_completer/pssuspend_completer.ps1) | [pssuspend_completer.md](pssuspend_completer/pssuspend_completer.md) | Native PowerShell argument completer for PsSuspend with local process/PID hints and placeholder-only remote targeting. |
| `qwen`, `qwen.cmd`, `qwen.ps1` | [qwen_completer.ps1](qwen_completer/qwen_completer.ps1) | [qwen_completer.md](qwen_completer/qwen_completer.md) | Hybrid Qwen Code CLI completer with three-level subcommand tree, context-aware flag and enum completion, path completion for path-bearing flags, and placeholder suppression for free-form slots. |
| `reg`, `reg.exe` | [reg_completer.ps1](reg_completer/reg_completer.ps1) | [reg_completer.md](reg_completer/reg_completer.md) | Native PowerShell argument completer for `reg.exe` with help-driven subcommands, registry-key/value completion, and file-slot awareness. |
| `RegDelNull`, `RegDelNull.exe` | [RegDelNull_completer.ps1](RegDelNull_completer/RegDelNull_completer.ps1) | [RegDelNull_completer.md](RegDelNull_completer/RegDelNull_completer.md) | Small native completer for RegDelNull with registry-path completion and destructive-aware placeholders. |
| `regjump`, `regjump.exe` | [regjump_completer.ps1](regjump_completer/regjump_completer.ps1) | [regjump_completer.md](regjump_completer/regjump_completer.md) | Small native completer for regjump with registry-path completion and terminal `-c` handling. |
| `rg`, `rg.exe` | [rg_completer.ps1](rg_completer/rg_completer.ps1) | [rg_completer.md](rg_completer/rg_completer.md) | Help-driven ripgrep completer with cached type discovery, enum-aware value hints, and placeholder-safe pattern/glob handling. |
| `robocopy`, `robocopy.exe` | [robocopy_completer.ps1](robocopy_completer/robocopy_completer.ps1) | [robocopy_completer.md](robocopy_completer/robocopy_completer.md) | Native PowerShell argument completer for Robocopy. |
| `ru`, `ru.exe` | [ru_completer.ps1](ru_completer/ru_completer.ps1) | [ru_completer.md](ru_completer/ru_completer.md) | Help-driven, mode-aware `ru` completer for absolute registry paths and safe `-h <hive file>` completion. |
| `sc`, `sc.exe` | [sc_completer.ps1](sc_completer/sc_completer.ps1) | [sc_completer.md](sc_completer/sc_completer.md) | Native PowerShell argument completer for Service Control Manager commands with help-driven verbs and value-aware service/config completion. |
| `schtasks`, `schtasks.exe` | [schtasks_completer.ps1](schtasks_completer/schtasks_completer.ps1) | [schtasks_completer.md](schtasks_completer/schtasks_completer.md) | Native PowerShell argument completer for Scheduled Tasks CLI usage. |
| `sdelete`, `sdelete.exe` | [sdelete_completer.ps1](sdelete_completer/sdelete_completer.ps1) | [sdelete_completer.md](sdelete_completer/sdelete_completer.md) | Risk-bounded SDelete completer with mode-aware path, drive, disk, and pass-count suggestions. |
| `sed`, `sed.exe` | [sed_completer.ps1](sed_completer/sed_completer.ps1) | [sed_completer.md](sed_completer/sed_completer.md) | Native PowerShell argument completer for GNU sed. |
| `shellrunas`, `shellrunas.exe` | [shellrunas_completer.ps1](shellrunas_completer/shellrunas_completer.ps1) | [shellrunas_completer.md](shellrunas_completer/shellrunas_completer.md) | Static ShellRunas completer based on official Sysinternals docs, with program-path completion and conservative argument passthrough. |
| `sigcheck`, `sigcheck.exe` | [sigcheck_completer.ps1](sigcheck_completer/sigcheck_completer.ps1) | [sigcheck_completer.md](sigcheck_completer/sigcheck_completer.md) | Native PowerShell argument completer for Sigcheck with scan-mode-aware paths, policy hints, and certificate-store completion. |
| `systeminfo`, `systeminfo.exe` | [systeminfo_completer.ps1](systeminfo_completer/systeminfo_completer.ps1) | [systeminfo_completer.md](systeminfo_completer/systeminfo_completer.md) | Native PowerShell argument completer for `systeminfo` with help-driven singleton switches, value-aware placeholders, `/FO` value completion, and `/NH` compatibility handling. |
| `strings`, `strings.exe` | [strings_completer.ps1](strings_completer/strings_completer.ps1) | [strings_completer.md](strings_completer/strings_completer.md) | Native PowerShell argument completer for Strings with numeric value hints and path-aware operand completion. |
| `tar`, `tar.exe` | [tar_completer.ps1](tar_completer/tar_completer.ps1) | [tar_completer.md](tar_completer/tar_completer.md) | Native PowerShell argument completer for Windows `bsdtar` with mode-aware option, value, and operand completion. |
| `tasklist`, `tasklist.exe` | [tasklist_completer.ps1](tasklist_completer/tasklist_completer.ps1) | [tasklist_completer.md](tasklist_completer/tasklist_completer.md) | Native PowerShell argument completer for Task List. |
| `testlimit`, `testlimit.exe`, `Testlimit`, `Testlimit.exe` | [testlimit_completer.ps1](testlimit_completer/testlimit_completer.ps1) | [testlimit_completer.md](testlimit_completer/testlimit_completer.md) | Native PowerShell argument completer for Testlimit with static stress-switch grammar and numeric placeholder completion. |
| `tskill`, `tskill.exe` | [tskill_completer.ps1](tskill_completer/tskill_completer.ps1) | [tskill_completer.md](tskill_completer/tskill_completer.md) | Native PowerShell argument completer for Terminal Server task termination. |
| `uv`, `uv.exe`, `uvx`, `uvx.exe` | [uv_completer.ps1](uv_completer/uv_completer.ps1) | [uv_completer.md](uv_completer/uv_completer.md) | Native PowerShell argument completer for Astral's `uv` and `uvx`. |
| `wevtutil`, `wevtutil.exe` | [wevtutil_completer.ps1](wevtutil_completer/wevtutil_completer.ps1) | [wevtutil_completer.md](wevtutil_completer/wevtutil_completer.md) | Native PowerShell argument completer for Windows Event Utility. |
| `where.exe` | [where_completer.ps1](where_completer/where_completer.ps1) | [where_completer.md](where_completer/where_completer.md) | Native PowerShell argument completer for `where.exe`. |
| `whoami`, `whoami.exe` | [whoami_completer.ps1](whoami_completer/whoami_completer.ps1) | [whoami_completer.md](whoami_completer/whoami_completer.md) | Static-first `whoami` completer with mode-aware slash-switch completion and `/FO` value hints. |
| `wsl` | [wsl_completer.ps1](wsl_completer/wsl_completer.ps1) | [wsl_completer.md](wsl_completer/wsl_completer.md) | Native PowerShell argument completer for Windows Subsystem for Linux. |
| `wt`, `wt.exe` | [wt_completer.ps1](wt_completer/wt_completer.ps1) | [wt_completer.md](wt_completer/wt_completer.md) | Native PowerShell argument completer for Windows Terminal. |
| `xcopy`, `xcopy.exe` | [xcopy_completer.ps1](xcopy_completer/xcopy_completer.ps1) | [xcopy_completer.md](xcopy_completer/xcopy_completer.md) | Native PowerShell argument completer for `xcopy` with help-driven switches and inline `/D:` and `/EXCLUDE:` completion. |
| `zip`, `zip.exe` | [zip_completer.ps1](zip_completer/zip_completer.ps1) | [zip_completer.md](zip_completer/zip_completer.md) | Native PowerShell argument completer for Info-ZIP `zip` with help-driven options and value-aware archive/path completion. |

## Notes

- Each completer is intended to work independently; there is no module manifest or build step in this repository.
- Some completers are static, while others depend on the installed native tool or its help output at completion time. The companion `.md` file for each script describes those details.
