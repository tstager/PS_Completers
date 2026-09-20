# seq completer

## What it completes / overview

seq_completer.ps1 registers a standalone native PowerShell completer for seq and seq.exe.

It is a help-driven completer with a static fallback for the sequence generator workflow. The script exposes the command's option catalog from the installed build and describes the numeric operand slots with placeholders; seq has no file operand, so it never offers filesystem paths.

The completer covers:

- option-name suggestions for the supported short and long flags
- numeric operand placeholders that follow `LAST | FIRST LAST | FIRST INCREMENT LAST`: `<LAST>`/`<FIRST>` in the first slot, `<LAST>`/`<INCREMENT>` in the second, `<LAST>` in the third, nothing after that
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-f`
- `--format`
- `-s`
- `--separator`
- `-w`
- `--equal-width`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'seq', 'seq.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Seq -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\seq_completer\seq_completer.ps1
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
- Operands are floating-point numbers, so an empty operand slot offers the placeholders for its position (negative numbers such as `-5` count as operands) and a partially typed number returns nothing; there is no path completion.
- Tokens are taken from the raw command text up to the cursor rather than from `CommandElements`, because the PowerShell parser drops a bare `,` (`seq -s , `) from the AST. A trailing bare `,` with the cursor directly after it is never handed to a native completer at all.
- Quoted values (`-s ";"`, `-s ' '`) are matched on their bare text and re-quoted the same way; the space, tab and newline separators are emitted in the PowerShell spelling that produces them (`' '`, `` "`t" ``, `` "`n" ``).
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `-f`, `--format`: `%g`, `%f`, `%e`, `%.2f`, `%05g`
- `-s`, `--separator`: `,`, `;`, `<string>`

## Representative validation scenarios

```powershell
seq -
seq --
seq --format 
seq --format=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--format` shows its documented values in both the separate and the attached form
- `seq ` offers `<LAST>` and `<FIRST>`, `seq 1 ` offers `<LAST>` and `<INCREMENT>`
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the sequence generator workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
