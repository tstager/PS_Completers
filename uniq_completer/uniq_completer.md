# uniq completer

## What it completes / overview

uniq_completer.ps1 registers a standalone native PowerShell completer for uniq and uniq.exe.

It is a help-driven completer with a static fallback for the duplicate line filter workflow. The script exposes the command's option catalog from the installed build, then falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-c`
- `--count`
- `-d`
- `--repeated`
- `-D`
- `--all-repeated`
- `-f`
- `--skip-fields`
- `--group`
- `-i`
- `--ignore-case`
- `-s`
- `--skip-chars`
- `-u`
- `--unique`
- `-z`
- `--zero-terminated`
- `-w`
- `--check-chars`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'uniq', 'uniq.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Uniq -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\uniq_completer\uniq_completer.ps1
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
- `--group` and `--all-repeated` take an optional METHOD that uniq accepts only attached (`--group=both`); `uniq --group separate` reads `separate` as the INPUT file. Their values are offered only after `=`, and the word after a space completes as an operand.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is the command element that contains the cursor, cut at the cursor, so completion works when the command is not the first statement on the line. An unterminated quote (`uniq "C:\Program Fi`) is one element running to the cursor, so the whole quoted path is completed rather than its last space-separated fragment.
- Path candidates keep the quote the user typed. PowerShell reads `'` and the typographic quotes U+2018-U+201B as single quotes and `"` and U+201C-U+201E as double quotes, so a typed word that opens with any of them is read by the PowerShell tokenizer, which drops the quote and undoes its escapes. Inside single quotes every single-quote character, typographic ones included, is doubled (`uniq it` completes to `'it''s.txt'`); inside double quotes `` ` ``, `"`, `$` and U+201C-U+201E are backtick-escaped (`uniq "a` completes to ``"a`$b.txt"``). With no quote typed, a path that contains whitespace, an argument-mode metacharacter (`{ } ( ) ; , | & < > ' " `` ` `` `$ @ #`) or a typographic quote is single-quoted.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe and the tool lookup use `-ErrorAction Ignore` so a cold load adds nothing to `$Error`, even when uniq is not installed.

## Option values

- `--all-repeated=`: `none`, `prepend`, `separate` (attached form only)
- `--group=`: `separate`, `prepend`, `append`, `both` (attached form only)
- `-f`, `--skip-fields`, `-s`, `--skip-chars`, `-w`, `--check-chars`: `<number>`

## Representative validation scenarios

```powershell
uniq -
uniq --
uniq --all-repeated 
uniq --all-repeated=
uniq "C:\Program Fi
uniq 'C:\Program Fi
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--all-repeated=` shows its documented values; `--all-repeated ` (space) falls through to operand completion
- operand slots offer filesystem completion
- `"C:\Program Fi` offers `"C:\Program Files\"` and `"C:\Program Files (x86)\"`; `'C:\Program Fi` offers the same paths in single quotes
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the duplicate line filter workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
