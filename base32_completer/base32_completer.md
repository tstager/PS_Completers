# base32 completer

## What it completes / overview

base32_completer.ps1 registers a standalone native PowerShell completer for base32 and base32.exe.

It is a static-first completer for the base32 encoding workflow. The script exposes a compact option catalog for common base32 flags and falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for common short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include:

  - `-d`
  - `--decode`
  - `--ignore-garbage`
  - `-w`
  - `--wrap`
  - `--help`
  - `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'base32', 'base32.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\base32_completer\base32_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions from the static option catalog.
- Non-switch operand slots use filesystem path completion so common file and directory inputs resolve naturally.
- The completer remains intentionally simple and does not try to model deeper command semantics beyond the supported option surface.

## Representative validation scenarios

```powershell
base32 -
base32 --
base32 -d
```

Expected behavior:

- `-` and `--` style prefixes show matching option suggestions
- the first non-option operand slot offers filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the base32 workflow and the option set surfaced in this repository's import-safe pattern.
- The implementation stays aligned with the repository's import-safe completer pattern.
