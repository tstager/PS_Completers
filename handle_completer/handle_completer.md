# handle completer

## What it completes / overview

`handle_completer.ps1` registers a native PowerShell completer for `handle` and `handle.exe`.

It is intentionally static-first and safe:

- it seeds the known Handle switch surface from local research
- it optionally parses `handle /?` to refine tooltips without treating the non-zero help exit code as a failure
- it provides local process-name and PID hints for `-p`
- it uses placeholders for risky or free-form slots such as `-c <handle>` and trailing name-fragment search

The goal is to suppress PowerShell's filesystem fallback and replace it with Handle-relevant suggestions.

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `handle`, `handle.exe`
- The file enables `Set-StrictMode -Version 2.0`

Load it into the current session with:

```powershell
. .\handle_completer.ps1
```

## How completion works

### Static-first switch catalog

The completer seeds a script-scoped catalog with the validated local Handle surface:

- `-a`
- `-l`
- `-c`
- `-y`
- `-s`
- `-g`
- `-u`
- `-v`
- `-vt`
- `-p`
- `-nobanner`
- `-?`
- `/?`
- `--help`

`Initialize-HandleCompletionCatalog` then safely probes `handle /?` when available and replaces the built-in tooltips with parsed help text where possible.

### Token-state parsing

The completer reconstructs the current token when needed and scans prior arguments to determine:

- whether the current slot is the value for `-c` or `-p`
- whether the command is in `-a`, `-c`, or `-s` mode
- whether a process target has already been supplied
- whether a trailing search-name fragment has already been supplied

### Local process cache

For `-p`, the script uses `Get-Process` to build a short-lived cache of unique:

- process names
- process IDs

When `-c` is already active, `-p` narrows to PID-oriented suggestions because the close-handle path requires the owning PID.

## Key completion behaviors / supported values

### Root and switch completion

At the root, and for `handle -`, the completer returns Handle switches instead of filesystem entries.

It also keeps a few contextual restrictions:

- `-l` is only suggested after `-a`
- `-y` is only suggested after `-c`
- `-v` and `-vt` suppress each other
- help aliases are only suggested before other arguments

### `-c <handle>`

`-c` returns hexadecimal samples plus a placeholder:

- `0000007c`
- `00000120`
- `000004b0`
- `<hex-handle>`

This stays placeholder-driven because the close-handle workflow is destructive.

### `-p <process|pid>`

`-p` returns safe local process hints from `Get-Process`.

In normal search mode, it offers both names and PIDs.
In close-handle mode, it falls back to PID-oriented suggestions or a `<pid>` placeholder.

### Trailing search fragment

For the trailing `name` slot, the completer returns:

- `<name-fragment>`

If you already started typing a fragment, it echoes that token back so PowerShell does not fall back to filesystem completion.

## Dependencies or external command expectations

- `Get-Process` is used for local `-p` hints
- `handle /?` is optionally used to refine tooltips
- no live handle enumeration is attempted
- no destructive probing is performed

## Usage / loading example

```powershell
. .\handle_completer.ps1

# Example completions
# handle <TAB>
# handle -<TAB>
# handle -p <TAB>
# handle -c <TAB>
# handle notepad<TAB>
```

## Validation notes

Validated in a clean `pwsh -NoProfile` session with `TabExpansion2` for both bare and `.exe` command names.
No transparent alias bootstrap was required after fixing the real runtime completion path.

## Limitations / notes

- `-c` remains placeholder-driven by design.
- The completer does not enumerate live handles or infer safe close targets.
- Local process hints are dynamic and intentionally short-lived.
