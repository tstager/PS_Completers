# stat completer

## What it completes / overview

stat_completer.ps1 registers a standalone native PowerShell completer for stat and stat.exe.

It is a help-driven completer with a static fallback for the file status display workflow. The script exposes the command's option catalog from the installed build, then falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-L`
- `--dereference`
- `-f`
- `--file-system`
- `--cached`
- `-c`
- `--format`
- `--printf`
- `-t`
- `--terse`
- `--append-exe`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'stat', 'stat.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Stat -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\stat_completer\stat_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. The tool is looked up once per session as an application only (`stat.exe`/`stat` on `PATH`), so a missing tool costs one lookup and never triggers module auto-load discovery; the static fallback list is then cached as the session's answer, and the format-sequence slots are served from the static tables without another lookup. The description text of each help line becomes the completion tooltip.
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Value-bearing options complete their documented values in the separate form (`--opt value`), the attached form (`--opt=value`) and for a partially typed value. Path-valued options use the script's own path completion. See the table below.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- A path is inserted in the quote the user typed. PowerShell reads `'` and the typographic quotes U+2018-U+201B as single quotes and `"` and U+201C-U+201E as double quotes, so a typed word that opens with any of them is read by the PowerShell tokenizer, which drops the quote and undoes its escapes. With no quote typed, a path that contains whitespace, an argument-mode metacharacter (`{ } ( ) ; , | & < > ' " `` ` `` `$ @ #`) or a typographic quote is single-quoted. Inside single quotes every single-quote character, typographic ones included, is doubled, so `stat it` completes to `'it''s.txt'`. Inside double quotes `` ` ``, `"`, `$` and U+201C-U+201E are backtick-escaped, so `stat "a` completes to ``"a`$b.txt"``. An attached path value is quoted as a whole word (`'--opt=a b.txt'`), because `--opt='a b.txt'` is not one constant argument.
- The typed directory part of a path, such as a leading `.\` or `./`, is kept exactly as typed. A name with no typed directory that starts with `-` or a U+2013-U+2015 dash gets a `.\` prefix (the platform separator), as PowerShell's own file completion does, because a bare word starting with a dash is read as a parameter: `stat '-` completes to `'.\-dash.txt'`.
- The current word is the command element under the cursor, cut at the cursor, so completion works when the command is not the first statement on the line and an unterminated quoted word stays one word.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `--cached`: `always`, `never`, `default`
- `-c`, `--format`, `--printf`: the format sequences parsed from the same `--help` text (GNU `  %a   desc` and uutils ``  -`%a`: desc`` shapes), with the help description as tooltip, plus `<format>`. When `-f`, a prefix of `--file-system`, or a short cluster with `f` before any `c` (such as `-Lf`) appears before `--`, the file-system sequence block is offered instead of the file block. Static fallbacks (9 file sequences, the 12 file-system sequences) apply when the tool is absent.
- A quoted value (`-c '%`, `--format="%`) matches without its quote; each candidate keeps the quote character the user typed and closes it, so `-c '%` completes to `'%a'` and `--format="%` to `--format="%a"`.

## Representative validation scenarios

```powershell
stat -
stat --
stat --cached 
stat --cached=
stat -c %
stat -c '%
stat -f -c 
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--cached` shows its documented values in both the separate and the attached form
- `-c %` lists every documented file format sequence; with `-f` on the line it lists the file-system sequences
- `-c '%` lists the same sequences single-quoted (`'%a'`), keeping the typed quote
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the file status display workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
