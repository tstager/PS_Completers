# od completer

## What it completes / overview

od_completer.ps1 registers a standalone native PowerShell completer for od and od.exe.

It is a static-first completer for octal/decimal/hex dumps. The script exposes the common option catalog and offers placeholder or enum values for the main option-bearing slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- placeholder and enum-aware suggestions for `--address-radix`, `--format`, `--skip-bytes`, `--read-bytes`, `--strings`, and `--width`
- filesystem path completion for operand slots
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include:

- `-A`
- `--address-radix`
- `-j`
- `--skip-bytes`
- `-N`
- `--read-bytes`
- `-S`
- `--strings`
- `-t`
- `--format`
- `-v`
- `--output-duplicates`
- `-w`
- `--width`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'od', 'od.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\od_completer\od_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions from the static option catalog.
- Value-bearing options such as `--address-radix`, `--format`, `--skip-bytes`, `--read-bytes`, `--strings`, and `--width` offer useful values or placeholders.
- Non-switch operand slots use filesystem path completion so common file and directory inputs resolve naturally.

## Representative validation scenarios

```powershell
od -
od --format 
od .\
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions
- `--format` returns value suggestions such as `d` or `x`
- operand completion offers filesystem items
- the completer remains importable through `Import-CompleterScript`
