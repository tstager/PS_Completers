# dd completer

## What it completes / overview

dd_completer.ps1 registers a standalone native PowerShell completer for dd and dd.exe.

It is a help-driven completer with a static fallback for the dd block-copy workflow. The script exposes a compact option catalog for common dd flags and falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for common short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'dd', 'dd.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Dd -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\dd_completer\dd_completer.ps1
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
- `dd` takes `key=value` operands rather than dashed options. The operand keywords complete in any bare slot, and the documented values complete after `key=` (see the table below).
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `if`, `of`: filesystem paths
- `bs`, `ibs`, `obs`, `cbs`: `<size>`, `1K`, `1M`, `1G`
- `count`, `skip`, `seek`: `<blocks>`
- `conv`: `ascii`, `ebcdic`, `block`, `unblock`, `lcase`, `ucase`, `sparse`, `swab`, `sync`, `excl`, `nocreat`, `notrunc`, `noerror`, `fdatasync`, `fsync`
- `iflag`, `oflag`: `append`, `direct`, `directory`, `dsync`, `sync`, `fullblock`, `nonblock`, `noatime`, `nocache`, `noctty`, `nofollow`
- `status`: `none`, `noxfer`, `progress`

## Representative validation scenarios

```powershell
dd -
dd --
dd 
dd if=
dd conv=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- a bare slot shows the operand keywords, `if=` completes paths and `conv=` completes conversion flags
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the dd workflow and the option set surfaced in this repository's import-safe pattern.
- The implementation stays aligned with the repository's import-safe completer pattern.
