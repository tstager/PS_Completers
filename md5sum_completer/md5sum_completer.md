# md5sum completer

## What it completes / overview

md5sum_completer.ps1 registers a standalone native PowerShell completer for md5sum and md5sum.exe.

It is a static-first completer for checksum generation and verification. The script exposes the common checksum flags and then falls back to filesystem path completion for file operands.

The completer covers:

- option-name suggestions for the supported short and long flags
- file and directory operand completion for input paths
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'md5sum', 'md5sum.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\md5sum_completer\md5sum_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions.
- Non-switch operand slots use filesystem path completion so common file and directory inputs resolve naturally.

## Representative validation scenarios

```powershell
md5sum -
md5sum .\
```

Expected behavior:

- `md5sum -` shows the supported options
- `md5sum .\` offers local filesystem path suggestions
- the completer remains importable through `Import-CompleterScript`
