# yes completer

## What it completes / overview

yes_completer.ps1 registers a standalone native PowerShell completer for yes and yes.exe.

It is a help-driven completer with a static fallback for the yes command surface. The script exposes the supported option catalog. The operand is a literal STRING (`Usage: yes [STRING]...`, `[default: y]`), so the completer never offers filesystem paths.

The completer covers:

- option-name suggestions for the supported short and long flags
- a `<string>` placeholder plus the common strings `y` and `n` for the operand slot
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'yes', 'yes.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Yes -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\yes_completer\yes_completer.ps1
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
- The operand slot is text, not a file: an empty word offers the `<string>` placeholder plus `y` (the tool's default) and `n`; a typed word gets `y` or `n` when it is a prefix of them and nothing otherwise. The placeholder appears only in an empty slot, and not when a token starts right at the cursor, so it never replaces typed text.
- A word that opens a quote and has no closing quote yet is read as one token, so an option-shaped fragment inside an open quoted string is not completed as an option.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
yes -
yes --
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `yes ` and `yes --help ` offer `<string>`, `y` and `n`; `yes y` completes to `y`
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the core yes option surface and its literal STRING operand.
- The implementation stays aligned with the repository's import-safe completer pattern.
