# md5sum completer

## What it completes / overview

md5sum_completer.ps1 registers a standalone native PowerShell completer for md5sum and md5sum.exe.

It is a help-driven completer with a static fallback for checksum generation and verification. The script exposes the common checksum flags and then falls back to filesystem path completion for file operands.

The completer covers:

- option-name suggestions for the supported short and long flags
- file and directory operand completion for input paths
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'md5sum', 'md5sum.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Md5sum -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\md5sum_completer\md5sum_completer.ps1
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
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
md5sum -
md5sum --
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`
