# pathchk completer

## What it completes / overview

pathchk_completer.ps1 registers a standalone native PowerShell completer for pathchk and pathchk.exe.

It is a static-first completer for path validation. The script exposes the common option catalog and supports filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- filesystem path completion for operand slots
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include:

- `-p`
- `--portability`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'pathchk', 'pathchk.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\pathchk_completer\pathchk_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions from the static option catalog.
- Non-switch operand slots use filesystem path completion so common file and directory inputs resolve naturally.

## Representative validation scenarios

```powershell
pathchk -
pathchk .\
```

Expected behavior:

- `-` prefixes show matching option suggestions
- operand completion offers filesystem items
- the completer remains importable through `Import-CompleterScript`
