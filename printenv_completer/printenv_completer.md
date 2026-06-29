# printenv completer

## What it completes / overview

printenv_completer.ps1 registers a standalone native PowerShell completer for printenv and printenv.exe.

It is a static-first completer for environment-variable inspection. The script exposes the common option catalog and offers environment-variable names discovered from the current PowerShell process.

The completer covers:

- option-name suggestions for the supported short and long flags
- environment-variable name completion for operand slots
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include:

- `-0`
- `--null`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'printenv', 'printenv.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\printenv_completer\printenv_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions from the static option catalog.
- Non-switch operand slots complete environment-variable names from the current process environment.

## Representative validation scenarios

```powershell
printenv -
printenv P
```

Expected behavior:

- `-` prefixes show matching option suggestions
- `P` returns matching environment variable names such as `PATH`
- the completer remains importable through `Import-CompleterScript`
