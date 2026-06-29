# factor completer

## What it completes / overview

factor_completer.ps1 registers a standalone native PowerShell completer for factor and factor.exe.

It is a small static-first completer for integer inputs. The script exposes the common help flags and then offers a placeholder for the first operand slot so the completer stays useful without relying on noisy filesystem fallback.

The completer covers:

- option-name suggestions for `--help` and `--version`
- a placeholder operand suggestion for the factor input position
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'factor', 'factor.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\factor_completer\factor_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions.
- The first non-option operand slot offers a `<number>` placeholder so completions remain explicit.

## Representative validation scenarios

```powershell
factor -
factor 
```

Expected behavior:

- `factor -` shows the supported options
- `factor ` offers the placeholder operand suggestion
- the completer remains importable through `Import-CompleterScript`
