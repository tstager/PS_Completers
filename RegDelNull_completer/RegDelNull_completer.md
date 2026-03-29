# RegDelNull completer

## What it completes / overview

`RegDelNull_completer.ps1` registers a standalone native PowerShell completer for `RegDelNull` and `RegDelNull.exe`.

It is intentionally small and side-effect free:

- local registry-path completion for the primary path operand
- static switches for `-s`, `-y`, and `-nobanner`
- destructive-aware placeholder behavior for unmatched free-form path text

The completer does not scan or delete anything during completion.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'RegDelNull', 'RegDelNull.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\RegDelNull_completer\RegDelNull_completer.ps1
```

It also enables:

```powershell
Set-StrictMode -Version 2.0
```

## How completion works

### Registry path completion

The completer uses the PowerShell registry provider to complete:

- `HKLM\`
- `HKCU\`
- `HKCR\`
- `HKU\`
- `HKCC\`

It also preserves long-form roots such as `HKEY_LOCAL_MACHINE\` when the user starts typing them.

### Switch completion

Static switch suggestions include:

- `-s`
- `-y`
- `-nobanner`
- `/?`

### Destructive-aware placeholders

If the user is in the path slot and no local registry suggestions match, the completer echoes the current token as a path value rather than falling back to filesystem completion.

## Usage examples

```powershell
RegDelNull <TAB>
RegDelNull HKLM\Soft<TAB>
RegDelNull HKLM\Software -<TAB>
```

## Dependencies or external command expectations

- Depends on the local PowerShell registry provider for key enumeration
- Does not execute `RegDelNull.exe` during completion

## Limitations / notes

- Remote registry syntax is not modeled.
- `/?` is treated as terminal for completion.
- The completer is intentionally informative only; it does not validate whether a path actually contains embedded nulls.
