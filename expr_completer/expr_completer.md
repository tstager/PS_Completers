# expr completer

## What it completes / overview

expr_completer.ps1 registers a standalone native PowerShell completer for expr and expr.exe.

It is a small help-driven completer for expression-style operands. The script exposes the common help flags and then offers a placeholder for the first operand slot so the completer stays useful without relying on noisy filesystem fallback.

The completer covers:

- option-name suggestions for `--help` and `--version`, offered only as the first argument
- the operand forms of the expression grammar (`match`, `substr`, `index`, `length`, `(`, `+`) and the infix operators (`|`, `&`, `<`, `<=`, `=`, `!=`, `>=`, `>`, `+`, `-`, `*`, `/`, `%`, `:`, and `)` inside a group)
- argument placeholders for the keyword operators (`<string>`, `<regexp>`, `<pos>`, `<length>`, `<chars>`) and for `+ TOKEN`
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'expr', 'expr.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Expr -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\expr_completer\expr_completer.ps1
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
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.
- `--help` and `--version` are offered only for the first argument, because expr accepts an option only as its sole argument. After a completed `--help` or `--version` the completer returns nothing.
- The arguments before the cursor are read from the command AST and walked through the expr grammar. Where an operand is expected, it offers `match`, `substr`, `index`, `length`, `(` and `+`. After a completed operand, it offers the infix operators, plus `)` while a `(` group is open. A leading `-` in an operand slot is a negative number or a string, so it is not completed as an option.
- Keyword arity follows the help: `match STRING REGEXP`, `substr STRING POS LENGTH`, `index STRING CHARS`, `length STRING`. With an empty word, each argument slot shows its placeholder, such as `<regexp>`. A typed prefix in that slot is matched against the operand forms, because a keyword argument can itself be a nested primary (`expr length length abc` prints `1`). The token after `+` shows `<token>`.
- Operators that contain PowerShell metacharacters (`|`, `&`, `<`, `<=`, `>=`, `>`, `(`, `)`) are emitted in single quotes. If the word was started with a `'` or `"`, that quote character is kept.
- The Windows expr builds expand an unquoted `*` as a file wildcard, even when PowerShell passes it quoted, so `*` works only where it matches no file. Its tooltip says so.

## Representative validation scenarios

```powershell
expr -
expr --
expr 
expr 1 
expr match abc 
expr 1 -
```

Expected behavior:

- `-` and `--` as the first argument show matching option suggestions with descriptions taken from the tool's help
- `expr ` offers the operand forms, `expr 1 ` offers the infix operators, and `expr match abc ` shows `<regexp>`
- `expr 1 -` keeps `-` as the subtraction operator instead of offering `--help`
- the completer remains importable through `Import-CompleterScript`
