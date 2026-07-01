# jq completer

## What it completes / overview

`jq_completer.ps1` registers a standalone native PowerShell completer for `jq` and `jq.exe`.

The completer uses `jq --help` output as its source of truth when the tool is available, so it discovers options dynamically instead of relying on a hard-coded switch list. That keeps it resilient to future changes in the command's help output.

It covers:

- option-name suggestions for jq's documented short and long flags
- path completion for file- and directory-bearing options such as `-f`, `--from-file`, `-L`, `--library-path`, `--rawfile`, and `--slurpfile`
- placeholder values for `--arg`, `--argjson`, `--rawfile`, and `--slurpfile` name slots
- an import-safe registration shape that can be loaded directly in PowerShell

Representative options include:

- `-n`
- `--null-input`
- `-f`
- `--from-file`
- `-L`
- `--library-path`
- `--arg`
- `--argjson`
- `--rawfile`
- `--slurpfile`
- `--args`
- `--jsonargs`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'jq', 'jq.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\jq_completer\jq_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions discovered from `jq --help` output.
- Options that take filesystem values such as `-f`, `--from-file`, `-L`, `--library-path`, `--rawfile`, and `--slurpfile` use path completion for the current argument slot.
- The completer supplies simple placeholders for variable-name slots to keep the user experience predictable when a value is expected but no dynamic value domain is available.

## Representative validation scenarios

```powershell
jq -
jq --
jq -f .
jq --from-file .
jq --arg 
```

Expected behavior:

- `-` and `--` style prefixes show matching option suggestions
- file-oriented options offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- The implementation purposely keeps the completion surface aligned with the installed `jq` help output rather than hard-coding a narrow option list.
- If `jq` is not available, the script falls back to a compact built-in option catalog so the completer still loads cleanly.
