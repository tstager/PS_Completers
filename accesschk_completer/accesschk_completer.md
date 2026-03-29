# accesschk completer

## What it completes / overview

`accesschk_completer.ps1` registers a native PowerShell completer for `accesschk` and `accesschk.exe`.

The completer is static-first and behavior-safe:

- it covers the locally validated help switches, including `-?` and `/?`
- it understands the major AccessChk modes (`-a`, `-c`, `-h`, `-k`, `-m`, `-o`, `-p`)
- it suppresses PowerShell's generic filesystem fallback in value-taking slots
- it adds safe local hints only where they are cheap and non-invasive, such as local process and service names

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `accesschk`, `accesschk.exe`
- The script enables `Set-StrictMode -Version 2.0`

Load it into the current session with:

```powershell
. .\accesschk_completer.ps1
```

## How completion works

### Switch completion

The script exposes the locally validated AccessChk switch surface:

- `-a`
- `-c`
- `-d`
- `-e`
- `-f`
- `-h`
- `-i`
- `-k`
- `-l`
- `-L`
- `-m`
- `-n`
- `-o`
- `-p`
- `-nobanner`
- `-r`
- `-s`
- `-t`
- `-u`
- `-v`
- `-w`
- `-?`
- `/?`

The completer keeps `-f` and `-t` value-aware:

- `-f` becomes a comma-separated account filter unless process mode `-p` is already active
- `-t` suggests object types after `-o`, but remains a plain switch after `-p`

### Mode-aware value and positional completion

The completer adds targeted values for the major AccessChk modes:

- `-a` -> common account rights plus `*`
- `-c` -> `*`, `scmanager`, and cached local service names
- `-h` -> share placeholders such as `ADMIN$`, `C$`, `IPC$`, and `*`
- `-k` -> registry-root and local registry-key completion
- `-m` -> common event-log names plus `*`
- `-o` -> Object Manager namespace roots and object-type hints
- `-p` -> cached local process names, PIDs, and `*`

Without an explicit mode, the completer supports the documented `[username] <object>` shape by offering:

- common user/group samples such as `Everyone`, `Users`, and `Administrators`
- path-aware completion for filesystem-style object paths

### Path-aware slots

The script uses local `Get-ChildItem` inspection for path-like operands so that:

- bare operand slots can complete files and directories
- command-specific value slots do not fall back to unrelated provider completion
- partial and quoted paths still produce usable completions

## Dependencies or external command expectations

This completer does not invoke `accesschk` during completion.

It only depends on:

- PowerShell native argument completer support
- local `Get-Process` for process hints
- local `Get-Service` for service-name hints
- local registry provider access for registry-key suggestions
- local filesystem access for path completion

## Usage / loading example

```powershell
. .\accesschk_completer.ps1

accesschk -<TAB>
accesschk -p <TAB>
accesschk -c <TAB>
accesschk -k HK<TAB>
accesschk Everyone .\<TAB>
```

## Limitations / notes

- The completer does not attempt remote discovery or enumerate risky live data sources.
- Registry completion is local-only.
- Event-log completion is based on safe static names rather than live enumeration.
- AccessChk has flexible syntax; the completer focuses on the validated help surface and the highest-value operand positions.
