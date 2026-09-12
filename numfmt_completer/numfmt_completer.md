# numfmt completer

## What it completes / overview

numfmt_completer.ps1 registers a standalone native PowerShell completer for numfmt and numfmt.exe.

It is a help-driven completer with a static fallback for number-formatting workflows. The script exposes the common option catalog and offers placeholder values for the main option-bearing slots.

The completer covers:

- option-name suggestions for the supported flags
- placeholder and enum-aware suggestions for `--field`, `--format`, `--from`, `--to`, `--invalid`, `--round`, `--padding`, and `--suffix`
- filesystem path completion for operand slots
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `--debug`
- `-d`
- `--delimiter`
- `--field`
- `--format`
- `--from`
- `--from-unit`
- `--grouping`
- `--header`
- `--invalid`
- `--padding`
- `--round`
- `--suffix`
- `--to`
- `--to-unit`
- `-z`
- `--zero-terminated`
- `--help`
- `--version`
- `-M`
- `-B1`
- `-l`
- `-lh`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'numfmt', 'numfmt.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Numfmt -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\numfmt_completer\numfmt_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## How completion works

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. A static fallback list is used when the tool is not installed. The description text of each help line becomes the completion tooltip.
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
numfmt -
numfmt --
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`
