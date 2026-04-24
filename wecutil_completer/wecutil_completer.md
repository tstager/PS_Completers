# wecutil completer

## What it completes / overview

`wecutil_completer.ps1` registers a standalone native PowerShell completer for `wecutil` and `wecutil.exe`.

It is a **help-driven** completer because `wecutil.exe` exposes its command-specific option surface through `wecutil COMMAND -?` help output.

The completer covers:

- top-level command aliases and long names such as `gs`, `get-subscription`, `ss`, `set-subscription`, and `qc`, `quick-config`
- command-specific `/option:value` tokens parsed from command help
- selected enum values for common high-value options like `/format:`, `/unicode:`, `/configurationmode:`, `/contentformat:`, and `/transportname:`
- config-file path completion for `/c:` and `/config:`
- local subscription-name completion when `wecutil es` succeeds
- placeholder-only completion for risky or free-form values such as credentials, queries, event-source names, and descriptions

## Registration and command names

```powershell
Register-ArgumentCompleter -Native -CommandName @('wecutil', 'wecutil.exe') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\wecutil_completer\wecutil_completer.ps1
```

## Import-CompleterScript compatibility

The file keeps its top level compatible with `CompleterActions`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## Runtime quirks

- `wecutil.exe` uses command aliases plus long command names; the completer supports both.
- Option discovery is command-specific and is parsed lazily from `wecutil <command> -?` help text.
- Local subscription enumeration may fail if the Event Collector service or RPC path is unavailable; when that happens the completer falls back to placeholders.
- Free-form query, credential, and event-source slots intentionally avoid remote probing.

## Validation examples

```powershell
wecutil 
wecutil gs 
wecutil gs sub1 /f:
wecutil ss /c:
wecutil cs .\
wecutil qc /q:
wecutil.exe gr sub1 
```
