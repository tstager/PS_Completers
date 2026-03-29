# regjump completer

## What it completes / overview

`regjump_completer.ps1` registers a standalone native PowerShell completer for `regjump` and `regjump.exe`.

The implementation is intentionally tiny:

- local registry-path completion for the main operand
- static completion for `-c`
- terminal handling when `-c` is already present so PowerShell does not fall back to filesystem suggestions

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'regjump', 'regjump.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\regjump_completer\regjump_completer.ps1
```

It also enables:

```powershell
Set-StrictMode -Version 2.0
```

## How completion works

### Registry-path mode

When no arguments have been supplied yet, the completer offers:

- `-c`
- local registry roots
- child-key completion under typed roots such as `HKLM\Software\`

### Clipboard mode

When `-c` is present, the completer returns a terminal placeholder because `regjump -c` is a complete command form that reads the target path from the clipboard.

## Usage examples

```powershell
regjump <TAB>
regjump HKCU\Soft<TAB>
regjump -c <TAB>
```

## Dependencies or external command expectations

- Depends on the local PowerShell registry provider for key enumeration
- Does not execute `regjump.exe` during completion

## Limitations / notes

- Only local registry paths are modeled.
- The completer does not inspect the clipboard contents in `-c` mode.
