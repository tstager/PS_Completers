# compact completer

## What it completes / overview

`compact_completer.ps1` registers a standalone native PowerShell completer for `compact` and `compact.exe`.

It is a **static-first** completer because `compact.exe /?` exposes a small, stable switch surface.

The completer covers:

- slash-style switches
- attached-value switches such as `/S:`, `/EXE:`, `/CompactOs:`, and `/WinDir:`
- enum values for `/EXE:` and `/CompactOs:`
- local file and directory completion for operand paths

## Registration and command names

```powershell
Register-ArgumentCompleter -Native -CommandName @('compact', 'compact.exe') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\compact_completer\compact_completer.ps1
```

## Import-CompleterScript compatibility

The file keeps its top level compatible with `CompleterActions`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## Runtime quirks

- `compact.exe` uses attached slash forms for several value-bearing switches, so the completer routes `/S:`, `/EXE:`, `/CompactOs:`, and `/WinDir:` separately.
- `-?` and `--help` are not real help for `compact.exe`; `/?` is the authoritative help form.
- `/CompactOs` is exposed both as a bare switch and as `/CompactOs:` for explicit option values.

## Validation examples

```powershell
compact /
compact /EXE:
compact /CompactOs:
compact /S:
compact .\
compact.exe /WinDir:
```
