# handle completer

## What it completes / overview

`handle_completer.ps1` registers a native PowerShell completer for `handle` and `handle.exe`.

It is intentionally static-first and safe:

- it seeds the known Handle switch surface from local research
- it optionally parses `handle /?` to refine tooltips without treating the non-zero help exit code as a failure
- it provides local process-name and PID hints for `-p`
- it uses a placeholder alone for the risky `-c <handle>` slot and completes the trailing name fragment from the filesystem

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

The three help aliases are offered only while no argument has been typed yet, and they are
reachable from either prefix style: `handle -<TAB>` offers `-?` and `--help`, `handle /<TAB>`
offers `/?`.

`Initialize-HandleCompletionCatalog` then safely probes `handle /?` when available and replaces the built-in tooltips with parsed help text where possible.

### Token-state parsing

The completer reconstructs the current token when needed and scans prior arguments to determine:

- whether the current slot is the value for `-c` or `-p`
- which of handle's three alternative groups the line has committed to

  Live usage is `handle [[-a [-l]] [-v|-vt] [-u] | [-c <handle> [-y]] | [-s]] [-p <process>|<pid>] [name] [-nobanner]`. Every switch in those brackets carries its group in the catalog, and the first group-exclusive switch on the line fixes the group, so `handle -v ` no longer offers `-c` and `-s` alongside it. `-g`, `-p`, `-nobanner` and the help aliases belong to every group. `-l` and `-y` are offered only once their own parent switch (`-a`, `-c`) is present.
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

`-c` returns the placeholder alone:

- `<hex-handle>`

No sample handle values are offered. `-c` closes an arbitrary handle in another process, requires administrator rights, and handle's own help warns that it can destabilise an application or the system, so a value that looks real must never be presented as a completion. The tooltip carries that warning verbatim from parsed help.

### `-p <process|pid>`

`-p` returns safe local process hints from `Get-Process`.

In normal search mode it offers both names and PIDs, with names first: handle's own help for `-p` says "partial name accepted", so names are the primary input and are kept in a separate sorted list rather than being buried behind 500 lexically sorted digits. PID 0 (Idle) is skipped, and each PID's tooltip names its owning process.

In close-handle mode, it falls back to PID-oriented suggestions or a `<pid>` placeholder.

### Trailing search fragment

For an empty trailing `name` slot the completer returns the `<name-fragment>` placeholder.

Once you start typing, the fragment is completed from the filesystem with
`[System.Management.Automation.CompletionCompleters]::CompleteFilename`, because handle's
canonical example searches a path fragment and the filesystem is the only real source of
candidates for an object name.

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

- `-c` remains placeholder-only by design, with no sample values.
- The completer does not enumerate live handles or infer safe close targets.
- Local process hints are dynamic and intentionally short-lived.
