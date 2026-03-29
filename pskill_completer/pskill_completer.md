# pskill completer

## What it completes / overview

`pskill_completer.ps1` registers a native PowerShell completer for `pskill` and `pskill.exe`.

It focuses on the safe, validated PsKill surface:

- static switch completion
- local process-name and PID hints
- remote `\\computer` placeholder handling
- username and password placeholders for the remote-login path

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

- surface `\\computer` only as a placeholder
- keep `-u` and `-p` visible in switch completion so the remote-auth surface is discoverable
- still route `-u` and `-p` value completion to placeholder-only remote credential slots

### Local process hints

Without a remote target, the positional process slot uses `Get-Process` to return local:

- process names
- process IDs

## Key completion behaviors / supported values

### Root completion

At `pskill ` the completer offers:

- `-t`
- `-nobanner`
- `\\computer`
- local process names and PIDs

### Switch completion

At `pskill -`, the completer stays focused on PsKill switches instead of returning no completions.

### Remote value placeholders

- `-u` -> `<username>`
- `-p` -> `<password>`
- remote process slot -> `<process-or-pid>`

No remote process enumeration is attempted.

## Dependencies or external command expectations

- `Get-Process` is used for local process hints
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

- Remote targets remain placeholder-only.
- Local process hints are intentionally short-lived and dynamic.
