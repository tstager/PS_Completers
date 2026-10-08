# fold completer

## What it completes / overview

fold_completer.ps1 registers a standalone native PowerShell completer for fold and fold.exe.

It is a help-driven completer with a static fallback for line wrapping. The script exposes the common wrapping flags and then falls back to filesystem path completion for file operands.

The completer covers:

- option-name suggestions for the supported short and long flags
- file and directory operand completion for input paths
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'fold', 'fold.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Fold -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\fold_completer\fold_completer.ps1
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
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is cut from the `CommandAst` element that contains the cursor, up to the cursor. An unterminated quote is one token, so `fold "my d` completes `my dir` rather than a file named `d*`.
- A path is quoted when the user opened a quote or the path holds whitespace, any of `{ } ( ) ; , | & < > ' " $ @ #`, a backtick, or a typographic quote (U+2018-U+201E, which PowerShell reads as quotes). It keeps the quote the user typed, and single quotes are the default. Single quotes double every single-quote character, typographic ones included; double quotes escape `` ` ``, `"`, `$` and U+201C-U+201E with a backtick.
- A typed quoted word is unescaped by the PowerShell parser before it is matched, so `'it''s` finds `it's.txt` and a typographic opening quote such as `‘Dad` is understood.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe, the tool lookup and the directory listing use `-ErrorAction Ignore` so no completion adds anything to `$Error`, even with fold absent from PATH.

## Option values

- `-w`, `--width`: `72`, `80`, `<width>`

## Representative validation scenarios

```powershell
fold -
fold --
fold --width 
fold --width=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--width` shows its documented values in both the separate and the attached form
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`
