# pskill completer

## What it completes / overview

`pskill_completer.ps1` registers a native PowerShell completer for `pskill` and `pskill.exe`.

It focuses on the safe, validated PsKill surface:

- static switch completion
- local process-name and PID hints
- remote `\\computer` hosts from local state, with a placeholder
- local user names for `-u`, and a password placeholder for `-p`

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `pskill`, `pskill.exe`
- The file enables `Set-StrictMode -Version 2.0`

Load it with:

```powershell
. .\pskill_completer.ps1
```

## How completion works

### Static switch catalog

The completer covers:

- `-t`
- `-u`
- `-p`
- `-nobanner`
- `-?`
- `/?`
- `--help`

### Remote preamble parsing

The script tracks the documented PsKill syntax:

```text
[\\computer [-u username [-p password]]] <process ID | name>
```

That lets it:

- offer known hosts in the `\\computer` slot, followed by the `\\computer` placeholder
- keep `-u` and `-p` visible in switch completion so the remote-auth surface is discoverable
- route `-u` to local user names and keep `-p` placeholder-only

### Local process hints

Without a remote target, the positional process slot uses `Get-Process` to return local:

- process names
- process IDs

## Key completion behaviors / supported values

### Root completion

At `pskill ` the completer offers:

- `-t`
- `-nobanner`
- known hosts such as `\\%COMPUTERNAME%`, then `\\computer`
- local process names and PIDs

### Switch completion

At `pskill -`, the completer stays focused on PsKill switches instead of returning no completions.

### Remote host and user values

- `\\` -> known hosts filtered by the typed prefix: `\\` plus `%COMPUTERNAME%`, `%LOGONSERVER%` and the servers behind persistent mapped drives (`HKCU\Network\*\RemotePath`). `\\computer` follows only while no host name has been typed. A typed host that matches nothing is kept as typed (a no-op), because an empty answer would hand it to PowerShell's UNC fallback, which queries the network for share names.
- `-u` -> `%USERNAME%`, `%USERDOMAIN%\%USERNAME%` and the enabled local accounts (read once per session from the local SAM through `[ADSI]'WinNT://<computer>,computer'`), then `<username>`. Names are matched after an opening quote, keep a typed quote, and are single-quoted when they contain spaces or metacharacters.
- `-p` -> `<password>`
- remote process slot -> `<process-or-pid>`

No remote host, account or process is ever queried.

## Dependencies or external command expectations

- `Get-Process` is used for local process hints
- `-u` reads local account names through ADSI (WinNT provider, local SAM only), cached for the session
- host names come from environment variables and the HKCU\Network registry key
- no remote probing is performed

## Usage / loading example

```powershell
. .\pskill_completer.ps1

# Example completions
# pskill <TAB>
# pskill -<TAB>
# pskill \\<TAB>
# pskill -t pwsh<TAB>
# pskill \\server -u <TAB>
```

## Validation notes

Validated with `pwsh -NoProfile` and `TabExpansion2`, including bare-name and `.exe` forms plus local process/PID suggestions.

## Limitations / notes

- Remote host suggestions are limited to local state; hosts reached only through session (non-persistent) connections are not listed.
- Local process hints are intentionally short-lived and dynamic.
