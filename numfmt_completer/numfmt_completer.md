# numfmt completer

## What it completes / overview

numfmt_completer.ps1 registers a standalone native PowerShell completer for numfmt and numfmt.exe.

It is a static-first completer for number-formatting workflows. The script exposes the common option catalog and offers placeholder values for the main option-bearing slots.

The completer covers:

- option-name suggestions for the supported flags
- placeholder and enum-aware suggestions for `--field`, `--format`, `--from`, `--to`, `--invalid`, `--round`, `--padding`, and `--suffix`
- filesystem path completion for operand slots
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include:

- `--debug`
- `--field`
- `--format`
- `--from`
- `--to`
- `--invalid`
- `--round`
- `--padding`
- `--grouping`
- `--header`
- `--zero-terminated`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'numfmt', 'numfmt.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\numfmt_completer\numfmt_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions from the static option catalog.
- Value-bearing options such as `--field`, `--format`, `--from`, `--to`, `--invalid`, `--round`, `--padding`, and `--suffix` offer concrete placeholder or enum values.
- Non-switch operand slots use filesystem path completion so common file and directory inputs resolve naturally.

## Representative validation scenarios

```powershell
numfmt --
numfmt --from 
numfmt .\
```

Expected behavior:

- `--` prefixes show matching option suggestions
- `--from` returns value suggestions such as `auto` or `none`
- operand completion offers filesystem items
- the completer remains importable through `Import-CompleterScript`
