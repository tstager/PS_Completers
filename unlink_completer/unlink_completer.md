# unlink completer

## What it completes / overview

unlink_completer.ps1 registers a standalone native PowerShell completer for unlink and unlink.exe.

It is a help-driven completer with a static fallback for the unlink command surface. The script exposes the supported option catalog and falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'unlink', 'unlink.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Unlink -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\unlink_completer\unlink_completer.ps1
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
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped. The typed directory part, including a leading `.\` or `./`, is kept exactly as typed, and a name with no directory that starts with a dash (`-`, U+2013-U+2015) gets a `.\` prefix so PowerShell does not parse it as a parameter.
- The current word is the command element the PowerShell parser places under the cursor, so completion works when the command is not the first statement on the line, and an unterminated quote such as `unlink "C:\Program F` completes the whole typed path instead of the text after its last space.
- A word opened with a quote (ASCII or typographic, U+2018-U+201E) is read with the PowerShell tokenizer before matching (so `'it''s` matches `it's`), and the completion keeps the user's quote character. Unquoted names that contain whitespace, an argument-mode metacharacter (`{` `}` `(` `)` `;` `,` `|` `&` `<` `>` `'` `"` `` ` `` `$` `@` `#`) or a typographic quote are emitted in single quotes. Inside single quotes every single-quote character (`'` and U+2018-U+201B) is doubled; inside double quotes `` ` ``, `"`, `$` and U+201C-U+201E are backtick-escaped.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
unlink -
unlink --
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the core unlink option surface and the standard operand fallback.
- The implementation stays aligned with the repository's import-safe completer pattern.
