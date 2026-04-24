# wpr completer

## What it completes / overview

`wpr_completer.ps1` registers a standalone native PowerShell completer for `wpr` and `wpr.exe`.

It is a **static-first** completer with safe local discovery for profile names, process names, and process IDs. The high-level command surface is stable, but local profiles and process data are runtime-dependent.

The completer covers:

- top-level WPR commands like `-start`, `-stop`, `-merge`, `-status`, `-profiles`, `-help`, and heap/snapshot commands
- `-help` topic completion
- local profile-name completion from `wpr -profiles`
- plus-delimited profile-list completion for `-profiledetails` and `-exportprofile`
- local process-name and PID completion for heap and snapshot commands
- local file and directory completion for path-bearing commands
- placeholder-only completion for free-form non-path slots such as problem descriptions and instance names

## Registration and command names

```powershell
Register-ArgumentCompleter -Native -CommandName @('wpr', 'wpr.exe') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\wpr_completer\wpr_completer.ps1
```

## Import-CompleterScript compatibility

The file keeps its top level compatible with `CompleterActions`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## Runtime quirks

- `wpr.exe` uses command-like leading `-start`, `-stop`, and `-help` tokens rather than slash switches.
- `--help` is not real help for `wpr.exe`; `-help`, `/?`, and `-?` are the relevant help forms.
- Local profile discovery comes from `wpr -profiles` and is cached briefly.
- Several value-bearing commands accept free-form strings, so the completer intentionally emits placeholders rather than speculative parsing.

## Validation examples

```powershell
wpr -
wpr -help 
wpr -start 
wpr -profiledetails 
wpr -snapshotconfig Heap -name 
wpr -enableperiodicsnapshot Heap 
wpr.exe -log 
```
