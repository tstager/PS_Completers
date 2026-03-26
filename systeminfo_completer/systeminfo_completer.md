# systeminfo completer

## What it completes / overview
`systeminfo_completer.ps1` registers a native PowerShell completer for `systeminfo` and `systeminfo.exe`.

The implementation is intentionally small and mostly static because `systeminfo` has a very small command surface:
- it seeds the known singleton switches `/S`, `/U`, `/P`, `/FO`, `/NH`, and `/?`
- it provides placeholder value completions for `/S`, `/U`, and `/P`
- it provides fixed value completion for `/FO`
- it follows real runtime ordering flexibility for `/S`, `/U`, and `/P` instead of over-constraining to the printed syntax nesting

The completer is designed for real `TabExpansion2` use and to suppress unhelpful filesystem fallback for the value-taking switches.

## Registration and command names
- Registers with `Register-ArgumentCompleter -Native`
- Command names: `systeminfo`, `systeminfo.exe`
- The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'systeminfo', 'systeminfo.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-Systeminfo -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

The file also enables `Set-StrictMode -Version 2.0`.

## How completion works
### Catalog initialization
The script-scoped `$script:SysteminfoCompletionCatalog` holds:
- `Initialized`
- `SwitchOrder`
- `SwitchInfo`
- `FormatValues`

`Initialize-SysteminfoCompletionCatalog` initializes a built-in static catalog for the known switch set.

### Token-state parsing
The completer:
- reads command elements from `$commandAst`
- reconstructs the current token from the command line when needed
- distinguishes trailing-space completion from in-token completion
- scans previously entered tokens to determine:
  - which singleton switches are already present
  - whether the current position is the value for `/S`, `/U`, `/P`, or `/FO`
  - the currently chosen `/FO` value, if any

That state is what keeps the completer reliable under normal registration and `TabExpansion2` usage.

## Key completion behaviors / supported values
### Root switch completion
At the root, the completer suggests the known switches and suppresses duplicates.

Behavior highlights:
- `/?` is treated as terminal and is only suggested before any other switch is present
- `/S`, `/U`, and `/P` remain available in any order until already used, because runtime accepts flexible ordering even though the help text prints them in a nested form
- `/NH` is not suggested after `/FO LIST`
- singleton switches are suppressed once already used
- once `/?` is already present, the completer suppresses further filesystem fallback by returning a terminal no-more-arguments completion

### `/S` value completion
For `/S`, the completer offers placeholder-style value hints:
- `<computer-name>`
- `<ip-address>`
- `localhost`
- `\\localhost`

If the user is already typing a value that does not match those placeholders, the completer echoes the current token back as a value completion so PowerShell does not fall back to filesystem suggestions.

### `/U` value completion
For `/U`, the completer offers:
- `<domain\user>`
- `<user>`

As with `/S`, it falls back to the current token as a value completion when needed to suppress filesystem completion.

### `/P` value completion
For `/P`, the completer offers:
- `<password>`

This is intentionally a placeholder only; it does not attempt to discover or echo secrets. If the user is typing a non-placeholder password token, the completer returns that token as a value completion to avoid filesystem fallback. If the user starts another switch after `/P`, the completer allows switch completion so the optional password can be omitted and prompted interactively.

### `/FO` value completion
`/FO` completes:
- `TABLE`
- `LIST`
- `CSV`

If `/NH` is already present earlier on the command line, `/FO` is restricted to:
- `TABLE`
- `CSV`

That keeps the value suggestions aligned with the known `/NH` compatibility rule.

## Dependencies or external command expectations
- No dynamic discovery is required
- The completer is fully self-contained and uses a static command model for the known `systeminfo` switch surface

## Usage / loading example
```powershell
. "$PSScriptRoot\systeminfo_completer.ps1"

# Example completions
# systeminfo <TAB>
# systeminfo /S <TAB>
# systeminfo /S localhost /U <TAB>
# systeminfo /FO <TAB>
# systeminfo /NH /FO <TAB>
```

## Limitations / notes
- The completer is intentionally permissive rather than fully modeling every invalid combination.
- It does not attempt network discovery, account discovery, or password prompting.
- `/NH` is suggested before `/FO` because runtime accepts `/NH /FO TABLE` and `/NH /FO CSV`.
- `/S`, `/U`, and `/P` are suggested in a more flexible order than the printed help because local runtime probing showed that `systeminfo.exe` accepts them out of the canonical sequence.
- Value placeholders are there to improve the native completion experience; they are hints, not validation.
