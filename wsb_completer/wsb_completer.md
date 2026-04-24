# wsb completer

## What it completes / overview

`wsb_completer.ps1` registers a standalone native PowerShell completer for `wsb` and `wsb.exe`.

It is a **static-first** completer with a small amount of safe local discovery because the command surface is stable, but sandbox IDs depend on the local runtime state.

The completer covers:

- top-level commands and aliases such as `start`, `list`, `exec`, `share`, `stop`, `connect`, and `ip`
- command-specific options like `--id`, `--command`, `--working-directory`, `--run-as`, and `--host-path`
- inline `--id=` style value completion
- safe local sandbox-ID discovery from `wsb list --raw`
- local directory completion for `--host-path`
- placeholder-only completion for config strings, commands, and sandbox-internal paths

## Registration and command names

```powershell
Register-ArgumentCompleter -Native -CommandName @('wsb', 'wsb.exe') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\wsb_completer\wsb_completer.ps1
```

## Import-CompleterScript compatibility

The file keeps its top level compatible with `CompleterActions`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## Runtime quirks

- `wsb.exe` is a modern command-style CLI that supports subcommands and `--help`.
- Running sandbox IDs are discovered from `wsb list --raw` and cached briefly in script scope.
- Sandbox-internal values such as `--working-directory` and `--sandbox-path` deliberately use placeholders instead of local filesystem probing.

## Validation examples

```powershell
wsb 
wsb start --
wsb exec --run-as 
wsb share --host-path .\
wsb stop --id 
wsb.exe list --help
```
