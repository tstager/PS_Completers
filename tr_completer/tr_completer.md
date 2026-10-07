# tr completer

## What it completes / overview

tr_completer.ps1 registers a standalone native PowerShell completer for tr and tr.exe.

It is a help-driven completer with a static fallback for the character translator and deleter workflow. The script exposes the command's option catalog from the installed build, offers the SET1/SET2 character-set vocabulary in the operand slots that still take a SET, and otherwise keeps the filesystem fallback.

The completer covers:

- option-name suggestions for the supported short and long flags
- SET1/SET2 vocabulary: the twelve POSIX classes (`[:alpha:]`, `[:digit:]`, ...), the backslash escapes (`\\`, `\n`, `\t`, ...), and closers for `[=c=]` and `[c*n]`
- operand completion for path-like arguments when no vocabulary entry matches
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-c`
- `-C`
- `--complement`
- `-d`
- `--delete`
- `-s`
- `--squeeze-repeats`
- `-t`
- `--truncate-set1`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'tr', 'tr.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Tr -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\tr_completer\tr_completer.ps1
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
- Option names are harvested from every help line, including clap-style `[alias: -C]` suffixes, so the `-C` alias of `--complement` is offered.
- A SET slot, including an empty word, offers the SET vocabulary from a static table (uutils `tr --help` prints no sequence list, and the classes and escapes are POSIX-fixed). Matching is case-sensitive. Typing `[=a` offers `[=a=]`, and `[x*` or `[x*3` offers `[x*]` or `[x*3]`. When the word starts with a quote, the result keeps the user's quote character (`'[:al` -> `'[:alpha:]'`).
- A slot is a SET slot while fewer operands have been given than tr accepts: one with `-d`/`--delete` alone (`-cd` included), otherwise two (`-ds`, translation, `-t`; with `-s` alone SET2 is optional but still accepted). Options end at `--` or at the first operand, as in uutils `tr` (`tr a b -d` reports an extra operand); long options may be abbreviated (`--del`).
- tr reads standard input, so its operands are never files. An empty word outside a SET slot (`tr a-z A-Z `, `tr -d [:space:] `) returns nothing and PowerShell's own `.\name` listing answers, as before the vocabulary existed. A typed word that matches no vocabulary entry keeps the script's path completion, with wildcard characters in the typed text escaped; the typed text is split at the last `\` or `/` by hand rather than with `Split-Path`, so bracket operands such as `[:` never raise a path error.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
tr -
tr --
tr -d [:
tr '[:al
tr \
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help, including `-C`
- `[:` lists the POSIX classes, `'[:al` offers `'[:alnum:]'` and `'[:alpha:]'`, and `\` lists only the escapes
- `tr -d [:space:] ` and `tr a-z A-Z ` (no SET left to give) fall back to PowerShell's `.\name` listing
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the character translator and deleter workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
