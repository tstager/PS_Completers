# base32 completer

## What it completes / overview

base32_completer.ps1 registers a standalone native PowerShell completer for base32 and base32.exe.

It is a help-driven completer with a static fallback for the base32 encoding workflow. The script exposes a compact option catalog for common base32 flags and falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for common short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-d`
- `--decode`
- `-i`
- `--ignore-garbage`
- `-w`
- `--wrap`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'base32', 'base32.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Base32 -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
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

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. A static fallback list is used when the tool is not installed. The description text of each help line becomes the completion tooltip.
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Value-bearing options complete their documented values in the separate form (`--opt value`), the attached form (`--opt=value`) and for a partially typed value. Path-valued options use the script's own path completion. See the table below.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `-w`, `--wrap`: `0`, `64`, `76`

## Representative validation scenarios

```powershell
base32 -
base32 --
base32 --wrap 
base32 --wrap=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--wrap` shows its documented values in both the separate and the attached form
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the base32 workflow and the option set surfaced in this repository's import-safe pattern.
- The implementation stays aligned with the repository's import-safe completer pattern.
