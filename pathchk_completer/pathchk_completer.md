# pathchk completer

## What it completes / overview

pathchk_completer.ps1 registers a standalone native PowerShell completer for pathchk and pathchk.exe.

It is a help-driven completer with a static fallback for path validation. The script exposes the common option catalog and supports filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- filesystem path completion for operand slots
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-p`
- `-P`
- `--portability`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'pathchk', 'pathchk.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pathchk -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\pathchk_completer\pathchk_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## How completion works

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. A static fallback list is used when the tool is not installed. The description text of each help line becomes the completion tooltip.
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is the command element under the cursor as the PowerShell parser read it, so quotes and escapes are already resolved (an unterminated quote is one word) and completion works when the command is not the first statement on the line. A word the parser splits at a paren or sub-expression (an unquoted `p(1)\` is `p`, `(1)` and `\`) is offered back unchanged, so Tab is a no-op instead of PowerShell's own file-name fallback replacing the fragment with unrelated paths; quoting the path (`'p(1)\`) completes it. A paren, sub-expression, variable or array element gets no path completion.
- A path is quoted when the user opened a quote, or when it contains whitespace, an argument-mode metacharacter (`{ } ( ) ; , | & < > ' " $`, the backtick, or a typographic quote) or starts with `@` or `#`. The user's quote character is kept; otherwise single quotes are used with embedded `'` doubled, and inside double quotes `` ` ``, `"` and `$` are backtick-escaped. Names such as `a$b.txt`, `x;y.txt` or `p(1).txt` therefore stay one literal argument.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe and tool lookup use `-ErrorAction Ignore` so neither a cold load nor a missing tool adds anything to `$Error`.

## Representative validation scenarios

```powershell
pathchk -
pathchk --
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`
