# tskill completer

## What it completes / overview

`tskill_completer.ps1` registers a native argument completer for `tskill` and `tskill.exe`.

It is a lightweight completer that focuses on:

- the documented switch tokens
- the first positional process target
- inline `/ID:` session values
- inline `/SERVER:` placeholders

## Registration and command names

The script ends by calling:

```powershell
Register-ArgumentCompleter -Native -CommandName @('tskill', 'tskill.exe') -ScriptBlock { ... }
```

Load it into the current session with:

```powershell
. .\tskill_completer.ps1
```

## How completion works

### Static switch catalog

The script stores a small script-scoped catalog containing these switch tokens:

- `/SERVER:`
- `/ID:`
- `/A`
- `/V`
- `/?`

### Positional target completion

Before any positional target has been completed, the completer suggests process names and process IDs gathered from `Get-Process`.

It builds a cache of unique process names and IDs, sorts them, and stores them for 2 seconds in `$script:TskillCompletionCatalog.ProcessEntries`.

### Session ID completion

For `/ID:`, the script gathers session IDs by running one of these commands:

- `qwinsta.exe`
- `query.exe session` (fallback when `qwinsta.exe` is not available)

It extracts numeric session IDs from the command output and caches them for 20 seconds.

### Current-token handling

If PowerShell does not provide a usable `wordToComplete`, the script reconstructs the current token from the command line text and cursor position. This lets it distinguish between:

- completing a partially typed token
- completing after trailing whitespace
- completing inline values such as `/ID:1`

## Key completion behaviors / supported values

### Switch completion

When the current token starts with `/`, the completer filters the static switch catalog by prefix and returns matching switch names.

### Process completion

When no positional target has been completed yet, the completer returns:

- unique process names
- unique process IDs

Both are returned as `ParameterValue` results.

### `/ID:` completion

When the current token starts with `/ID:`, the completer suggests session IDs in inline form, for example:

```text
/ID:1
/ID:2
```

### `/SERVER:` completion

When the current token starts with `/SERVER:`:

- if no server name has been typed yet, the script returns the literal `/SERVER:` token with a tooltip of `Remote server name`
- if text has already been typed after the colon, the script returns no hostname suggestions

## Dependencies or external command expectations

This completer expects:

- `tskill.exe` or `tskill` to be available, otherwise it returns no completions
- `Get-Process` for process-name and process-ID suggestions
- `qwinsta.exe` or `query.exe` for session ID discovery used by `/ID:`

## Usage / loading example

```powershell
. .\tskill_completer.ps1

tskill <TAB>
tskill /<TAB>
tskill /ID:<TAB>
tskill notepad <TAB>
```

## Limitations / notes

- `/ID:` and `/SERVER:` are handled as inline options with a colon, not as separate option/value tokens.
- `/SERVER:` does not enumerate remote host names.
- After one positional process target has already been supplied, the completer stops offering additional positional suggestions.
- Process and session suggestions are cached briefly to reduce repeated system queries while staying fairly current.

