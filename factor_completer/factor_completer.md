# factor completer

## What it completes / overview

factor_completer.ps1 registers a standalone native PowerShell completer for factor and factor.exe.

It is a small help-driven completer for integer inputs. The script exposes the common help flags and then offers a placeholder for the first operand slot so the completer stays useful without relying on noisy filesystem fallback.

The completer covers:

- option-name suggestions for `--help` and `--version`
- a placeholder operand suggestion for the factor input position
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'factor', 'factor.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Factor -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
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

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. A static fallback list is used when the tool is not installed. The description text of each help line becomes the completion tooltip.
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Operand slots return nothing, so PowerShell's default filename completion applies.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
factor -
factor --
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- operand slots fall back to PowerShell's default filename completion
- the completer remains importable through `Import-CompleterScript`
