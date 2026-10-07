# printf completer

## What it completes / overview

printf_completer.ps1 registers a standalone native PowerShell completer for printf and printf.exe.

It is a help-driven completer with a static fallback for the printf workflow. The script exposes the command's option catalog from the installed build, then falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- FORMAT substitution fields (`%%`, `%b`, `%q` and the `diouxXfeEgGcs` conversions) and interpreted escape sequences (`\n`, `\t`, `\"`, `\xHH`, ...)
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'printf', 'printf.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Printf -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\printf_completer\printf_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. Only the indented option column is read, and the scan stops at the first unindented paragraph after it, so dash words in prose (uutils printf's `-max places ...` and `ls --quoting=shell-escape`) are not offered. `--help` and `--version` are always included, and they are the static fallback when the tool is not installed. The description text of each help line becomes the completion tooltip.
- The FORMAT operand (the first operand, after an optional `--`) completes its trailing open piece:
  - a word ending in an open `%` spec (`%`, `'Total: %`, `%-5`, `%.2`) offers the conversions; `%%`, `%b` and `%q` are offered only for a bare `%`, because printf rejects flags, width or precision on them
  - a word ending in an unpaired backslash (`hello\`, `'Line\`) offers the escape sequences; `\xHH`, `\uHHHH` and `\UHHHHHHHH` insert their letter and leave the digits to type, and `\NNN` is not offered because it has no literal part. When the text before the backslash is an existing directory (`.\`, `\`, `C:\Program Files\`), path completion wins as before
  - the catalog is read from the same cached `--help` capture (GNU's two-column escape list, `%%`/`%b`/`%q` entries and the `ending with one of diouxXfeEgGcs` sentence), with a static GNU table for builds whose help uses another layout (uutils) or when the tool is absent
  - the word is read from the PowerShell parser, so an unterminated quote is one word; the typed quote is kept, and a bare word is single-quoted when the result needs it (`hello\` + `\"` becomes `'hello\"'`)
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
printf -
printf --
printf '%s %
printf 'Line\
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `'%s %` offers `'%s %%'`, `'%s %d'`, ... `'%s %s'`; `'Line\` offers `'Line\n'`, `'Line\t'`, ...
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the printf workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
