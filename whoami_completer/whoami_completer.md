# whoami completer

## What it completes / overview
`whoami_completer.ps1` registers a native PowerShell completer for `whoami` and `whoami.exe`.

The implementation is static-first because `whoami.exe` has a small, stable slash-switch surface:
- identity format switches: `/UPN`, `/FQDN`, `/LOGONID`
- detail-report switches: `/USER`, `/GROUPS`, `/CLAIMS`, `/PRIV`
- aggregate report switch: `/ALL`
- report formatting switches: `/FO` and `/NH`

The completer intentionally follows real runtime behavior instead of only the printed syntax layout. Local probing showed that `whoami.exe` accepts `/FO` and `/NH` before or between detail-report switches, as long as the command ultimately stays on a report-capable path.

## Registration and command names
- Registers with `Register-ArgumentCompleter -Native`
- Command names: `whoami`, `whoami.exe`
- The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'whoami', 'whoami.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-Whoami -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

The file also enables `Set-StrictMode -Version 2.0`.

## How completion works
### Import-safe catalog initialization
The script keeps its top level import-safe for `CompleterActions`:
- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter` call

The script-scoped catalog is created lazily inside `Get-WhoamiCompletionCatalog`, not at import time.

### Token-state parsing
The completer:
- reads command elements from `$commandAst`
- reconstructs the current token from the command line when needed
- distinguishes trailing-space completion from in-token completion
- scans previously entered tokens to determine:
  - whether the command is on an identity-only path
  - whether `/ALL` is active
  - which detail-report switches are already present
  - whether `/FO` is currently expecting a format value
  - the selected `/FO` value, if any
  - whether a report-prelude state exists because `/FO` or `/NH` was entered before the report selector

## Key completion behaviors / supported values
### Root switch completion
At the root, the completer suggests:
- `/UPN`, `/FQDN`, `/LOGONID`
- `/USER`, `/GROUPS`, `/CLAIMS`, `/PRIV`
- `/ALL`
- `/?`

`/FO` and `/NH` are not advertised on an empty command line, but they are still available when the user explicitly starts typing them, because runtime accepts those switches before `/USER` or `/ALL`.

### Identity mode
After `/UPN`, `/FQDN`, or `/LOGONID`, the completer treats the command as terminal and suppresses unhelpful filesystem fallback.

### Detail-report mode
After any of `/USER`, `/GROUPS`, `/CLAIMS`, or `/PRIV`, the completer:
- keeps the remaining detail switches available
- offers `/FO`
- offers `/NH` unless `/FO LIST` is already selected

### `/ALL` mode
`/ALL` is treated as exclusive with the individual detail switches. Once `/ALL` is present, the completer only keeps the formatting switches available.

### `/FO` value completion
`/FO` completes:
- `TABLE`
- `LIST`
- `CSV`

If `/NH` is already present, `/FO` is restricted to:
- `TABLE`
- `CSV`

When the user has typed a non-matching token in the `/FO` value slot, the completer echoes that token back as a `ParameterValue` result to suppress filesystem fallback.

### `/NH` handling
`/NH` is treated as a switch, not a value. The completer suppresses `/NH` once `/FO LIST` is selected.

## Dependencies or external command expectations
- No dynamic discovery is required
- The completer is fully self-contained and uses a static model of the documented `whoami.exe` switch surface

## Usage / loading example
```powershell
. "$PSScriptRoot\whoami_completer.ps1"

# Example completions
# whoami <TAB>
# whoami /user <TAB>
# whoami /user /fo <TAB>
# whoami /fo csv /<TAB>
# whoami.exe /all /fo <TAB>
```

## Limitations / notes
- The completer models the current local `whoami.exe` help surface, including `/CLAIMS`.
- It is intentionally permissive about the relative ordering of `/FO`, `/NH`, and the report switches because local runtime probing showed that `whoami.exe` accepts several orderings beyond the printed syntax blocks.
- It does not attempt to validate every invalid combination beyond the main exclusivity rules.
