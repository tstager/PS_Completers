# shellrunas completer

## What it completes / overview

`shellrunas_completer.ps1` registers a standalone native PowerShell completer for `shellrunas` and `shellrunas.exe`.

The completer is static-only and based on the official Sysinternals ShellRunas documentation. Local `ShellRunas.exe /?` was not usable on this machine during validation and exited with Windows error 87, so the syntax in this completer is sourced from the published Sysinternals page instead of local help text.

## Documented syntax covered

The completer models the official usage forms:

```text
shellrunas /reg [/quiet]
shellrunas /regnetonly [/quiet]
shellrunas /unreg [/quiet]
shellrunas [/netonly] <program> [arguments]
```

## Key completion behaviors

- registration modes:
  - `/reg`
  - `/regnetonly`
  - `/unreg`
  - once one is present the grammar accepts only `/quiet`, so the completer offers `/quiet` and then nothing at all rather than falling through to a program list
- optional quiet mode:
  - `/quiet`
- launch mode option:
  - `/netonly`
  - it belongs to the launch grammar alone, so after `/netonly` the registration switches and `/netonly` itself are suppressed and only `<program>` is offered
- `<program>`:
  - local executable/path-aware completion
  - a word ending in `\` or `/` lists that directory's contents instead of re-suggesting the directory itself
  - an unterminated opening quote is kept whole, so `shellrunas "C:\Program Files\Com<TAB>` completes the real path
  - sample application names when the slot is blank
- later `[arguments]`:
  - conservative placeholder/echo completion only, to suppress filesystem fallback without pretending to understand the target program's own syntax

Parser state is built only from command elements that end at or before the cursor, and the cursor offset is rebased onto the command's own start offset, so completing in the middle of a line does not fold tokens to the right of the cursor into the state.

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('shellrunas', 'shellrunas.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-ShellRunas -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

## Notes

- The completer does not inspect or modify Explorer shell registration.
- It intentionally does not attempt to parse or complete the launched program's own arguments.

