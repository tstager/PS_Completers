# od completer

## What it completes / overview

od_completer.ps1 registers a standalone native PowerShell completer for od and od.exe.

It is a help-driven completer with a static fallback for octal/decimal/hex dumps. The script exposes the common option catalog and offers placeholder or enum values for the main option-bearing slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- placeholder and enum-aware suggestions for `--address-radix`, `--format`, `--skip-bytes`, `--read-bytes`, `--strings`, and `--width`
- filesystem path completion for operand slots
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `--traditional`
- `-j`
- `-A`
- `--address-radix`
- `--endian`
- `--skip-bytes`
- `-N`
- `--read-bytes`
- `-S`
- `--strings`
- `-t`
- `--format`
- `-v`
- `--output-duplicates`
- `-w`
- `--width`
- `--help`
- `--version`
- `-a`
- `-b`
- `-c`
- `-d`
- `-f`
- `-i`
- `-l`
- `-o`
- `-s`
- `-x`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'od', 'od.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Od -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\od_completer\od_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## How completion works

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. A static fallback list is used when the tool is not installed. The description text of each help line becomes the completion tooltip.
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Value-bearing options complete their documented values in the separate form (`--opt value`), the attached form (`--opt=value`) and for a partially typed value. Path-valued options use the script's own path completion. See the table below.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `-A`, `--address-radix`: `d`, `o`, `x`, `n`
- `-t`, `--format`: `a`, `c`, `d1`, `d2`, `d4`, `d8`, `o1`, `o2`, `o4`, `o8`, `u1`, `u2`, `u4`, `u8`, `x1`, `x2`, `x4`, `x8`, `f4`, `f8`
- `--endian`: `big`, `little`
- `-j`, `--skip-bytes`, `-N`, `--read-bytes`, `-S`, `--strings`: `<bytes>`
- `-w`, `--width`: `16`, `32`, `<bytes>`

## Representative validation scenarios

```powershell
od -
od --
od --address-radix 
od --address-radix=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--address-radix` shows its documented values in both the separate and the attached form
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`
