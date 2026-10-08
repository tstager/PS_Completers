# shred completer

## What it completes / overview

shred_completer.ps1 registers a standalone native PowerShell completer for shred and shred.exe.

It is a help-driven completer with a static fallback for the secure file overwrite workflow. The script exposes the command's option catalog from the installed build, then falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-f`
- `--force`
- `-n`
- `--iterations`
- `--random-source`
- `-s`
- `--size`
- `-u`
- `--remove`
- `-v`
- `--verbose`
- `-x`
- `--exact`
- `-z`
- `--zero`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'shred', 'shred.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Shred -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\shred_completer\shred_completer.ps1
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
- The current word is the command element under the cursor, taken from the parser and cut at the cursor, so completion works when the command is not the first statement on the line. An unclosed quoted word (`shred "with s`) is one element running to the cursor, so a path with a space is matched whole and emitted quoted.
- PowerShell replaces an unclosed quoted word up to the end of the line, so when the cursor is inside one (`shred "with s| out.bin`) every candidate carries the words typed after the cursor, from the first whitespace on: accepting gives `shred "with space\" out.bin` instead of deleting `out.bin`. The rest of the current word after the cursor (`shred "it's|.txt`) is replaced, as for any other word.
- The typed word is unquoted by the PowerShell parser (`'it''s` matches `it's.txt`, `` with` s `` matches `with space`); a bare word that does not parse, such as `it's`, is taken as typed, so it matches `it's.txt` too. A candidate keeps the kind of quote the user typed; a bare word that needs quoting (whitespace, `{ } ( ) ; , | & < > ' " `` ` `` $ @ #` or a typographic quote) is single-quoted. Single-quote characters (`'` and U+2018-U+201B) are doubled inside single quotes; `` ` ``, `"`, `$` and U+201C-U+201E are backtick-escaped inside double quotes.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe, the tool lookup and the folder listing use `-ErrorAction Ignore` so a missing tool or folder adds nothing to `$Error`.

## Option values

- `-n`, `--iterations`: `3`, `<n>`
- `--random-source`: filesystem paths
- `-s`, `--size`: `<size>`, `1K`, `1M`, `1G`
- `--remove`: `unlink`, `wipe`, `wipesync`

## Representative validation scenarios

```powershell
shred -
shred --
shred --iterations 
shred --iterations=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--iterations` shows its documented values in both the separate and the attached form
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the secure file overwrite workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
