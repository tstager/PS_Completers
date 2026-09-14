# listdlls completer

## What it completes / overview

`listdlls_completer.ps1` registers a native PowerShell completer for `listdlls`, `listdlls.exe`, `Listdlls`, and `Listdlls.exe`.

The implementation is static-first with light safe runtime hints:

- it seeds the validated switch surface
- it optionally parses `Listdlls -accepteula -nobanner /?` (stdin closed, 5 s timeout) to refine descriptions
- it adds local process-name hints for the positional `processname|pid` slot, and PID hints once the typed prefix is numeric
- it uses a placeholder for the free-form `-d dllname` slot

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `listdlls`, `listdlls.exe`, `Listdlls`, `Listdlls.exe`
- The file enables `Set-StrictMode -Version 2.0`

Load it with:

```powershell
. .\listdlls_completer.ps1
```

## How completion works

### Static switch catalog

The completer seeds these switches:

- `-r`
- `-v`
- `-u`
- `-d`
- `-accepteula`
- `-nobanner`
- `-?`
- `/?`
- `--help`

`-accepteula` and `-nobanner` are accepted by Listdlls v3.2 but never printed by its help, so they stay in the static catalog.

It then safely captures `Listdlls -accepteula -nobanner /?` when available (stdin closed, bounded by a 5 s timeout) and uses the parsed text to improve switch tooltips.

### Positional process hints

For the default `processname|pid` form, the completer uses `Get-Process` and a short-lived cache to surface:

- process names, sorted, when the typed prefix is empty or non-numeric
- process IDs, numerically sorted, only when the typed prefix is all digits (PIDs 0 and 4 are omitted because Listdlls cannot open them)

### DLL-name placeholder

For `-d`, the script deliberately avoids live DLL probing and returns:

- `<dll-name>`

That suppresses filesystem fallback without pretending to inspect module state.

## Key completion behaviors / supported values

### Root completion

At `listdlls ` the completer offers:

- relevant switches (including `-?`, `/?` and `--help` while nothing else has been typed)
- local process names (PIDs appear once you type a digit)

The `<dll-name>` placeholder is only offered in the real `-d` value slot, since a DLL name is not a legal bare operand.

### Context-sensitive switch handling

Modelled on the two usage forms `listdlls [-r] [-v | -u] [processname|pid]` and `listdlls [-r] [-v] [-d dllname]`:

- `-v` and `-u` are mutually exclusive: once one is present the other is hidden
- once `-d` or `-u` is in use, the other is hidden because `-u` does not apply to the DLL-search form
- once a positional process target is supplied, `-d` is no longer suggested
- help aliases are limited to the initial position

### `-d dllname`

`listdlls -d ` returns:

- `<dll-name>`

If you already started typing a value, the completer echoes that current token back as a safe placeholder completion.

## Dependencies or external command expectations

- `Get-Process` is used for local process hints
- `Listdlls -accepteula -nobanner /?` is optionally parsed for help text refinement (help output only; the call is bounded by a timeout and never prompts)
- no local DLL enumeration is attempted

## Usage / loading example

```powershell
. .\listdlls_completer.ps1

# Example completions
# listdlls <TAB>
# listdlls -<TAB>
# listdlls -d <TAB>
# listdlls note<TAB>
```

## Validation notes

Validated with `pwsh -NoProfile` and `TabExpansion2` for both bare and `.exe` command names.

## Limitations / notes

- The completer intentionally does not enumerate loaded module names.
- Process hints are local-only and short-lived.
