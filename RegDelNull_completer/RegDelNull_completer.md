# RegDelNull completer

## What it completes / overview

`RegDelNull_completer.ps1` registers a standalone native PowerShell completer for `RegDelNull` and `RegDelNull.exe`.

It is intentionally small and side-effect free:

- local registry-path completion for the primary path operand
- static switches for `-s`, `-y`, `-nobanner`, and the suite-wide `-accepteula`
- destructive-aware placeholder behavior for unmatched free-form path text

The completer does not scan or delete anything during completion.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'RegDelNull', 'RegDelNull.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-RegDelNull -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
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

The completer reads subkey names directly through `Microsoft.Win32.RegistryKey.GetSubKeyNames()` to complete:

- `HKLM\`
- `HKCU\`
- `HKCR\`
- `HKU\`
- `HKCC\`

It also preserves long-form roots such as `HKEY_LOCAL_MACHINE\` when the user starts typing them.

Reading names from the parent key rather than opening every child has three consequences that matter for this tool:

- keys the current session cannot open are still offered. `HKLM\` lists `BCD00000000` and `SECURITY` alongside the readable hives, and those are exactly the keys RegDelNull is normally run elevated to repair.
- key names containing a forward slash survive intact, so `HKCR\MAPI/Folder` and `HKCR\IE.text/html` are reachable and `HKCR\Folder` is no longer offered twice.
- a large hive costs one call. The typed leaf is filtered before sorting, the result count is capped at 300, and each parent's name list is cached for the session, so `HKCR\` answers in about 140 ms instead of enumerating 6050 keys.

Switch names are added to the path slot only when the word under the cursor is empty, so a partial path such as `HKLM\Soft` completes to the single real match rather than a five-item menu.

### Switch completion

Static switch suggestions include:

- `-s`
- `-y`
- `-nobanner`
- `-accepteula`
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

- Depends on local registry read access through the .NET `Microsoft.Win32.Registry` API for key enumeration; a key it cannot open yields an empty child list rather than an error
- Does not execute `RegDelNull.exe` during completion

## Limitations / notes

- Remote registry syntax is not modeled.
- `/?` is treated as terminal for completion.
- The completer is intentionally informative only; it does not validate whether a path actually contains embedded nulls.
