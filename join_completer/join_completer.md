# join completer

## What it completes / overview

join_completer.ps1 registers a standalone native PowerShell completer for join and join.exe.

It is a static-first completer for the relational join workflow. The script exposes the command's option catalog from the installed build, then falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include:

  - `-a`
  - `--a`
  - `-e`
  - `--echo`
  - `-o`
  - `--output`
  - `-t`
  - `--field-separator`
  - `-1`
  - `-2`
  - `-j`
  - `--join-field`
  - `-j1`
  - `-j2`
  - `-v`
  - `--header`
  - `-z`
  - `--zero-terminated`
  - `--check-order`
  - `--nocheck-order`
  - `-h`
  - `--help`
  - `-V`
  - `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'join', 'join.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\join_completer\join_completer.ps1
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
join -
join --
join -t
```

Expected behavior:

- `-` and `--` style prefixes show matching option suggestions
- the first non-option operand slot offers filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the relational join workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.