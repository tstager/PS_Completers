# sha1sum completer

## What it completes / overview

sha1sum_completer.ps1 registers a standalone native PowerShell completer for sha1sum and sha1sum.exe.

It is a help-driven completer with a static fallback for the sha1sum workflow. The script exposes the command's option catalog from the installed build, then falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-b`
- `--binary`
- `-c`
- `--check`
- `--tag`
- `-t`
- `--text`
- `-z`
- `--zero`
- `--ignore-missing`
- `--quiet`
- `--status`
- `--strict`
- `-w`
- `--warn`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'sha1sum', 'sha1sum.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Sha1sum -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\sha1sum_completer\sha1sum_completer.ps1
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
- A single-dash word made only of known short flags (`-cw`) is treated as a getopt cluster and completed by appending each remaining short flag (`-cwh`, `-cwV`, ...). Every sha1sum option is a boolean switch, so no letter in a cluster takes a value.
- Options are filtered by mode, because the tool rejects the wrong combination with an error. Verify mode is on when another word on the line (before any `--`) is `-c`, a short cluster containing `c`, or `--check` or an unambiguous abbreviation of it. In verify mode, `-c`/`--check`, `--tag`, `-z`/`--zero`, `-b`/`--binary` and `-t`/`--text` are dropped. Otherwise the verify-only options `-w`/`--warn`, `--status`, `--quiet`, `--strict` and `--ignore-missing` are dropped. Cluster completion applies the same filter, and a cluster that contains `c` counts as verify mode.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is the parser element that contains the cursor, cut at the cursor, so completion works when the command is not the first statement on the line. An unterminated quote is one word, so `sha1sum "my d` completes `my d.txt` rather than the fragment after the space.
- The typed word is read the way PowerShell reads it: the typographic quotes (U+2018-U+201B and U+201C-U+201E) open a quote like `'` and `"`, and doubled quotes and backtick escapes are undone by the parser before the path is matched, so `'it’` looks for names starting with `it`.
- Path completions keep the quote style the user typed: a single quote gives single-quoted results with every single-quote character (`'` and U+2018-U+201B) doubled, and a double quote gives double-quoted results with `` ` ``, `"`, `$` and U+201C-U+201E escaped. Unquoted names are single-quoted when they contain whitespace, any of `` { } ( ) ; , | & < > ' " ` $ ``, a typographic quote, or start with `@`, `#`, `-` or U+2013-U+2015.
- A typed directory part, including a leading `.\` or `./`, is kept exactly as typed in every path result. A relative name that starts with a dash (`-`, U+2013-U+2015) gets the `.\` prefix PowerShell's own file completion adds, so `sha1sum .\-` completes `.\-dash.txt` and it is never read as a parameter.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
sha1sum -
sha1sum --
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the sha1sum workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
