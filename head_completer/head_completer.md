# head completer

## What it completes / overview

head_completer.ps1 registers a standalone native PowerShell completer for head and head.exe.

It is a help-driven completer with a static fallback for the file header preview workflow. The script exposes the command's option catalog from the installed build, then falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-c`
- `--bytes`
- `-n`
- `--lines`
- `-q`
- `--quiet`
- `--silent`
- `-v`
- `--verbose`
- `-z`
- `--zero-terminated`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'head', 'head.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Head -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\head_completer\head_completer.ps1
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
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped. The typed directory part (including a leading `.\` or `./`) is kept exactly as typed, and a name starting with a dash (`-`, U+2013-U+2015) is offered as `.\-name` so PowerShell does not read it as a parameter.
- The current word is the PowerShell parser's command element under the cursor, cut at the cursor, so completion works when the command is not the first statement on the line and an unterminated quote with a space (`head "my f`) stays one word.
- Path completions keep the quote character the user typed. PowerShell reads `'` and the typographic quotes U+2018-U+201B as single quotes and `"` and U+201C-U+201E as double quotes, so a typed word that opens with any of them is read by the PowerShell tokenizer. Inside single quotes every single-quote character, typographic ones included, is doubled; inside double quotes `` ` ``, `"`, `$` and U+201C-U+201E are backtick-escaped. Unquoted names are single-quoted when they contain whitespace, an argument-mode metacharacter (`{ } ( ) ; , | & < > ' " `` ` `` $ @ #`) or a typographic quote.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `-c`, `--bytes`, `-n`, `--lines`: `<num>`, `-<num>` while the value is empty.
- Once a number is typed (`head -n 1`, `head -n -1`, `head --bytes=1`), the typed number is kept and a short ladder follows (`1`, `10`, `100`). For `-c`/`--bytes` the multiplier suffixes head accepts are offered too (`b`, `K`, `KiB`, `kB`, `M`, `MiB`, `MB`, `G`, `GiB`, `GB`); for `-n`/`--lines` they appear once a suffix letter is typed (`head -n 3M`).
- The value may be glued to the short option, as head accepts it: `head -n5` and `head -c1K` complete the value and keep the `-n`/`-c` prefix.

## Representative validation scenarios

```powershell
head -
head --
head --bytes 
head --bytes=
head -n 1
head -n5
head --bytes=1K
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--bytes` shows its documented values in both the separate and the attached form
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the file header preview workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
