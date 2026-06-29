# fmt completer

## What it completes / overview

fmt_completer.ps1 registers a standalone native PowerShell completer for fmt and fmt.exe.

It is a static-first completer for paragraph reformatting. The script exposes the common formatting flags and then falls back to filesystem path completion for file operands.

The completer covers:

- option-name suggestions for the supported short and long flags
- file and directory operand completion for input paths
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'fmt', 'fmt.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\fmt_completer\fmt_completer.ps1
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
fmt -
fmt .\
```

Expected behavior:

- `fmt -` shows the supported options
- `fmt .\` offers local filesystem path suggestions
- the completer remains importable through `Import-CompleterScript`
