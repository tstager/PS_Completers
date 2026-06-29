# link completer

## What it completes / overview

link_completer.ps1 registers a standalone native PowerShell completer for link and link.exe.

It is a static-first completer for filesystem link creation. The script exposes the common help flags and then falls back to filesystem path completion for both source and destination operands.

The completer covers:

- option-name suggestions for `--help` and `--version`
- file and directory operand completion for both link arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'link', 'link.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\link_completer\link_completer.ps1
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
link -
link .\
```

Expected behavior:

- `link -` shows the supported options
- `link .\` offers local filesystem path suggestions
- the completer remains importable through `Import-CompleterScript`
