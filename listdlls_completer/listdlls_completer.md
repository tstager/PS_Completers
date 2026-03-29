# listdlls completer

## What it completes / overview

`listdlls_completer.ps1` registers a native PowerShell completer for `listdlls`, `listdlls.exe`, `Listdlls`, and `Listdlls.exe`.

The implementation is static-first with light safe runtime hints:

- it seeds the validated switch surface
- it optionally parses `Listdlls /?` to refine descriptions
- it adds local process-name and PID hints for the positional `processname|pid` slot
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
- `-?`
- `/?`
- `--help`

It then safely captures `Listdlls /?` when available and uses the parsed text to improve switch tooltips.

### Positional process hints

For the default `processname|pid` form, the completer uses `Get-Process` and a short-lived cache to surface:

- process names
- process IDs

### DLL-name placeholder

For `-d`, the script deliberately avoids live DLL probing and returns:

- `<dll-name>`

That suppresses filesystem fallback without pretending to inspect module state.

## Key completion behaviors / supported values

### Root completion

At `listdlls ` the completer offers:

- relevant switches
- local process names and PIDs
- a DLL-name placeholder for the `-d` workflow

### Context-sensitive switch handling

- once `-d` is in use, `-u` is hidden because it does not apply to the DLL-search form
- once a positional process target is supplied, `-d` is no longer suggested
- help aliases are limited to the initial position

### `-d dllname`

`listdlls -d ` returns:

- `<dll-name>`

If you already started typing a value, the completer echoes that current token back as a safe placeholder completion.

## Dependencies or external command expectations

- `Get-Process` is used for local process hints
- `Listdlls /?` is optionally parsed for help text refinement
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
