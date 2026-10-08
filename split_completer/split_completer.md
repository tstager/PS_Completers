# split completer

## What it completes / overview

split_completer.ps1 registers a standalone native PowerShell completer for split and split.exe.

It is a help-driven completer with a static fallback for the file splitter workflow. The script exposes the command's option catalog from the installed build, then falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-a`
- `--suffix-length`
- `--additional-suffix`
- `-b`
- `--bytes`
- `-C`
- `--line-bytes`
- `-d`
- `--numeric-suffixes`
- `-x`
- `--hex-suffixes`
- `-e`
- `--elide-empty-files`
- `--filter`
- `-l`
- `--lines`
- `-n`
- `--number`
- `-t`
- `--separator`
- `-u`
- `--unbuffered`
- `--verbose`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'split', 'split.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Split -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\split_completer\split_completer.ps1
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
- A value slot that matches none of its documented values (`split -C R`, `split -t \`) returns the typed value unchanged, closing an unterminated quote, rather than returning nothing. An empty result would let PowerShell's filename fallback list paths for a SIZE or separator. PowerShell replaces the whole word under the cursor, so with the cursor inside a value (`split -b 5<Tab>0M`) the text after the cursor is part of the value: candidates must start with the whole word, and the echo keeps it. `--numeric-suffixes` and `--hex-suffixes` take `FROM` only in the attached form, so the word after them is still the INPUT operand.
- A value typed inside quotes (`split -b '1`) is matched by its unquoted text, and its candidates keep the user's quote.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped. A path is quoted when it contains whitespace, a PowerShell metacharacter or a quote character. The quote the user typed is kept, and single quotes are the default. Embedded single quotes, including the typographic ones, are doubled.
- The current word is the command element under the cursor, read from the parsed command, so a quoted word that holds spaces stays one word and completion works when the command is not the first statement on the line. The option that owns a value slot is the word before the cursor, not the last word on the line, so `split -b <Tab> in.txt` still offers sizes.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `-a`, `--suffix-length`: `<n>`
- `--additional-suffix`: `<suffix>`
- `-b`, `--bytes`, `-C`, `--line-bytes`: `1K`, `1M`, `10M`, `100M`, `1G`
- `--numeric-suffixes=`, `--hex-suffixes=`: `<from>` (attached form only)
- `--filter`: `<command>`
- `-l`, `--lines`: `<number>`
- `-n`, `--number`: `<chunks>`, `l/<n>`, `r/<n>`
- `-t`, `--separator`: `<sep>`

## Representative validation scenarios

```powershell
split -
split --
split --suffix-length 
split --suffix-length=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--suffix-length` shows its documented values in both the separate and the attached form
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the file splitter workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
