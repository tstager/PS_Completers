# nproc completer

## What it completes / overview

nproc_completer.ps1 registers a standalone native PowerShell completer for nproc and nproc.exe.

It is a help-driven completer with a static fallback for processor-count queries. The script exposes the core option catalog and offers a placeholder for `--ignore` values.

The completer covers:

- option-name suggestions for the supported short and long flags
- a placeholder for `--ignore` values
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `--all`
- `--ignore`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'nproc', 'nproc.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Nproc -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
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

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. A static fallback list is used when the tool is not installed. The description text of each help line becomes the completion tooltip.
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Value-bearing options complete their documented values in the separate form (`--opt value`), the attached form (`--opt=value`) and for a partially typed value. Path-valued options use the script's own path completion. See the table below.
- Operand slots return nothing, so PowerShell's default filename completion applies.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `--ignore`: `<number>`

## Representative validation scenarios

```powershell
nproc -
nproc --
nproc --ignore 
nproc --ignore=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--ignore` shows its documented values in both the separate and the attached form
- operand slots fall back to PowerShell's default filename completion
- the completer remains importable through `Import-CompleterScript`
