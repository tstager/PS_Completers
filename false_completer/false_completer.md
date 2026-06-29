# false completer

## What it completes / overview

false_completer.ps1 registers a standalone native PowerShell completer for false and false.exe.

It is a static-first completer for the no-op shell command. The script exposes the common help flags and otherwise stays quiet so it does not add unrelated fallback suggestions.

The completer covers:

- option-name suggestions for `--help` and `--version`
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'false', 'false.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\false_completer\false_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions.
- Non-option operand slots do not emit fallback suggestions so `false` stays simple.

## Representative validation scenarios

```powershell
false -
false 
```

Expected behavior:

- `false -` shows the supported options
- `false ` stays empty unless the user explicitly types a flag
- the completer remains importable through `Import-CompleterScript`
