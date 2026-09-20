# fmt completer

## What it completes / overview

fmt_completer.ps1 registers a standalone native PowerShell completer for fmt and fmt.exe.

It is a help-driven completer with a static fallback for paragraph reformatting. The script exposes the common formatting flags and then falls back to filesystem path completion for file operands.

The completer covers:

- option-name suggestions for the supported short and long flags
- file and directory operand completion for input paths
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'fmt', 'fmt.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Fmt -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\fmt_completer\fmt_completer.ps1
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
- Only option-table rows (lines starting with whitespace and `-`) are harvested, and all-uppercase short tokens are rejected, so GNU's prose `The option -WIDTH is an abbreviated form of --width=DIGITS.` no longer yields a bogus `-WIDTH` option. The row's metavariable (`--width=WIDTH`, `--skip-prefix <PSKIP>`) is cached per option, so options the static table does not list still get a typed hint: `WIDTH`/`GOAL`/`DIGITS` -> `72`, `80`, `<width>`; `TABWIDTH` -> `4`, `8`, `<tabwidth>`; anything else -> `<name>`.
- `-72` (the legacy `-WIDTH` abbreviation of `--width=72`) is echoed as a value with an explanatory tooltip, and `-<width>` is listed next to the options as a reminder of that form.
- A single-dash word made only of known value-less short flags (`-csu`) is treated as a getopt cluster and completed by appending each remaining boolean flag.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `-p`, `--prefix`: `<string>`
- `-w`, `--width`, `-g`, `--goal`: `72`, `80`, `<width>`
- any other value-taking option in the live help (uutils: `-P`/`--skip-prefix <PSKIP>`, `-T`/`--tab-width <TABWIDTH>`): hint derived from the metavariable, for example `4`, `8`, `<tabwidth>` and `<pskip>`

## Representative validation scenarios

```powershell
fmt -
fmt --
fmt --prefix 
fmt --prefix=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--prefix` shows its documented values in both the separate and the attached form
- `fmt -72` echoes the legacy width, `fmt -csu` offers cluster extensions, `fmt -T ` offers tab widths
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`
