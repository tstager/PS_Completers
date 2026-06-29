# nproc completer

## What it completes / overview

nproc_completer.ps1 registers a standalone native PowerShell completer for nproc and nproc.exe.

It is a static-first completer for processor-count queries. The script exposes the core option catalog and offers a placeholder for `--ignore` values.

The completer covers:

- option-name suggestions for the supported short and long flags
- a placeholder for `--ignore` values
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include:

- `-a`
- `--all`
- `--ignore`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'nproc', 'nproc.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\nproc_completer\nproc_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions from the static option catalog.
- The `--ignore` value slot offers a placeholder `<number>` to avoid falling back to noisy free-form completion.

## Representative validation scenarios

```powershell
nproc -
nproc --
nproc --ignore 
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions
- `--ignore` shows a numeric placeholder value
- the completer remains importable through `Import-CompleterScript`
