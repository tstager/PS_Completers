# pssuspend completer

## What it completes / overview

`pssuspend_completer.ps1` registers a native PowerShell completer for `pssuspend` and `pssuspend.exe`.

It mirrors the safe PsSuspend syntax surface with:

- static switch completion
- local process-name and PID hints
- remote `\\computer` placeholder handling
- placeholder completion for remote credentials and remote process values

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `pssuspend`, `pssuspend.exe`
- The file enables `Set-StrictMode -Version 2.0`

Load it with:

```powershell
. .\pssuspend_completer.ps1
```

## How completion works

### Static switch catalog

The completer covers:

- `-r`
- `-u`
- `-p`
- `-nobanner`
- `-?`
- `/?`
- `--help`

### Remote preamble parsing

The script tracks the documented syntax:

```text
[\\RemoteComputer [-u Username [-p Password]]] <process Id or name>
```

That keeps the remote-login path context-aware without probing remote systems, while still leaving `-u` and `-p` visible in switch completion so the remote-auth surface stays discoverable.

### Local process hints

For local usage, the first positional process slot is completed from `Get-Process`:

- process names
- process IDs

## Key completion behaviors / supported values

### Root completion

At `pssuspend ` the completer offers:

- `-r`
- `-nobanner`
- `\\computer`
- local process names and PIDs

### Switch completion

At `pssuspend -`, it returns PsSuspend switches instead of leaving completion empty.

### Remote placeholders

- `-u` -> `<username>`
- `-p` -> `<password>`
- remote process slot -> `<process-or-pid>`

## Dependencies or external command expectations

- `Get-Process` is used for local process hints
- no remote process or host discovery is attempted

## Usage / loading example

```powershell
. .\pssuspend_completer.ps1

# Example completions
# pssuspend <TAB>
# pssuspend -<TAB>
# pssuspend \\<TAB>
# pssuspend pwsh<TAB>
# pssuspend \\server -u <TAB>
```

## Validation notes

Validated with `pwsh -NoProfile` and `TabExpansion2`, including bare-name and `.exe` forms.

## Limitations / notes

- Remote values are placeholder-only by design.
- Local process hints are dynamic and cached briefly.
