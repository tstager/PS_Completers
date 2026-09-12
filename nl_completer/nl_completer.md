# nl completer

## What it completes / overview

nl_completer.ps1 registers a standalone native PowerShell completer for nl and nl.exe.

It is a help-driven completer with a static fallback for numbered line output. The script exposes the common numbering flags and then falls back to filesystem path completion for file operands.

The completer covers:

- option-name suggestions for the supported short and long flags
- file and directory operand completion for input paths
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'nl', 'nl.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Nl -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\nl_completer\nl_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. A static fallback list is used when the tool is not installed. The description text of each help line becomes the completion tooltip.
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Value-bearing options complete their documented values in the separate form (`--opt value`), the attached form (`--opt=value`) and for a partially typed value. Path-valued options use the script's own path completion. See the table below.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `-b`, `--body-numbering`, `-f`, `--footer-numbering`, `-h`, `--header-numbering`: `a`, `t`, `n`, `p<regex>`
- `-d`, `--section-delimiter`: `<cc>`
- `-i`, `--line-increment`, `-l`, `--join-blank-lines`, `-v`, `--starting-line-number`, `-w`, `--number-width`: `<number>`
- `-n`, `--number-format`: `ln`, `rn`, `rz`
- `-s`, `--number-separator`: `<string>`

## Representative validation scenarios

```powershell
nl -
nl --
nl --body-numbering 
nl --body-numbering=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--body-numbering` shows its documented values in both the separate and the attached form
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`
