# pr completer

## What it completes / overview

pr_completer.ps1 registers a standalone native PowerShell completer for pr and pr.exe.

It is a help-driven completer with a static fallback for page-formatting workflows. The script exposes the common option catalog and offers placeholder or enum values for several option-bearing slots while also supporting filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- value suggestions for `--columns`, `--header`, `--indent`, `--length`, `--width`, `--separator`, and `--page-range`
- filesystem path completion for operand slots
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `--pages`
- `-COLUMN`
- `--columns`
- `-a`
- `--across`
- `-c`
- `--show-control-chars`
- `-d`
- `--double-space`
- `-D`
- `--date-format`
- `-e`
- `--expand-tabs`
- `-F`
- `-f`
- `--form-feed`
- `-h`
- `--header`
- `-i`
- `--output-tabs`
- `-J`
- `--join-lines`
- `-W`
- `--sep-string`
- `-l`
- `--length`
- `-t`
- `-m`
- `--merge`
- `-n`
- `--number-lines`
- `-N`
- `--first-line-number`
- `-o`
- `--indent`
- `-w`
- `-r`
- `--no-file-warnings`
- `-s`
- `--separator`
- `-S`
- `--omit-header`
- `-T`
- `--omit-pagination`
- `-v`
- `--show-nonprinting`
- `--width`
- `--page-width`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'pr', 'pr.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pr -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\pr_completer\pr_completer.ps1
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
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `--columns`: `<n>`
- `-D`, `--date-format`: `<format>`
- `-e`, `--expand-tabs`, `-i`, `--output-tabs`, `-s`, `--separator`: `<char>`
- `-h`, `--header`: `<header>`
- `-l`, `--length`: `66`, `<lines>`
- `-n`, `--number-lines`: `<sep>`
- `-N`, `--first-line-number`: `<number>`
- `-o`, `--indent`: `<margin>`
- `-S`, `--sep-string`: `<string>`
- `-w`, `--width`, `-W`, `--page-width`: `72`, `<cols>`

## Representative validation scenarios

```powershell
pr -
pr --
pr --columns 
pr --columns=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--columns` shows its documented values in both the separate and the attached form
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`
