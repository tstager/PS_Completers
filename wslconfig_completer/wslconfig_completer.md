# wslconfig completer

## What it completes / overview

`wslconfig_completer.ps1` registers a standalone native PowerShell completer for `wslconfig` and `wslconfig.exe`.

It is a **static-first** completer because the legacy `wslconfig.exe /?` surface is small and stable.

The completer covers:

- top-level switches such as `/l`, `/list`, `/s`, `/setdefault`, `/t`, `/terminate`, `/u`, and `/unregister`
- `/list` mode options `/all` and `/running`
- local WSL distribution-name completion for the distribution-bearing commands
- both bare and `.exe` command names

## Registration and command names

```powershell
Register-ArgumentCompleter -Native -CommandName @('wslconfig', 'wslconfig.exe') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\wslconfig_completer\wslconfig_completer.ps1
```

## Import-CompleterScript compatibility

The file keeps its top level compatible with `CompleterActions`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## Runtime quirks

- `wslconfig.exe` writes UTF-16 style output with embedded NUL characters; distribution discovery removes those before parsing names.
- `wslconfig.exe` is a legacy CLI with slash switches, so the completer only treats slash-prefixed tokens as switches.
- The command does not have a rich subcommand grammar; completion stays intentionally small and focused.

## Validation examples

```powershell
wslconfig /
wslconfig /l 
wslconfig /s 
wslconfig /t 
wslconfig.exe /u 
```
