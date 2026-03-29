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
- optional quiet mode:
  - `/quiet`
- launch mode option:
  - `/netonly`
- `<program>`:
  - local executable/path-aware completion
  - sample application names when the slot is blank
- later `[arguments]`:
  - conservative placeholder/echo completion only, to suppress filesystem fallback without pretending to understand the target program's own syntax

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('shellrunas', 'shellrunas.exe') -ScriptBlock { ... }
```

## Notes

- The completer does not inspect or modify Explorer shell registration.
- It intentionally does not attempt to parse or complete the launched program's own arguments.

