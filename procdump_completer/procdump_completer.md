# procdump completer

## What it completes / overview

`procdump_completer.ps1` registers a native PowerShell completer for `procdump` and `procdump.exe`.

It is intentionally static-first and placeholder-heavy because ProcDump exposes a wide, context-sensitive surface:

- dump-type switches
- trigger and threshold switches
- install / uninstall / launch-mode entry points
- counter, numeric, comment, and path values
- target process name or PID hints

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `procdump`, `procdump.exe`
- The file enables `Set-StrictMode -Version 2.0`

Load it with:

```powershell
. .\procdump_completer.ps1
```

## How completion works

### Static switch catalog

The completer seeds the validated root surface, including:

- dump types such as `-mm`, `-ma`, `-mac`, `-mt`, `-mp`, `-mc`, `-md`, `-mk`
- trigger and threshold switches such as `-n`, `-s`, `-c`, `-cl`, `-cp`, `-m`, `-ml`, `-p`, `-pl`, `-f`, `-fx`, `-dc`, `-r`, `-at`
- exception and event switches such as `-e`, `-g`, `-b`, `-ld`, `-ud`, `-ct`, `-et`
- mode switches such as `-w`, `-x`, `-i`, `-u`, `-cancel`, `-accepteula`

### Context tracking

The completer tracks:

- whether ProcDump is in capture, install, uninstall, or `-x` launch mode
- whether the current slot is the value for a numeric/path/string switch
- when `-p` or `-pl` is waiting on counter path versus numeric threshold
- when `-e` is waiting for the optional first-chance `1`
- whether a capture target or dump path has already been supplied

### Local process hints

For capture targets and `-cancel`, the script uses `Get-Process` to build a short-lived cache of:

- process names
- process IDs

Everything else stays placeholder-driven.

## Key completion behaviors / supported values

### Root and switch completion

At `procdump ` and `procdump -`, the completer returns ProcDump-specific switches instead of filesystem fallback.

### Numeric and threshold slots

Representative examples:

- `-mc` -> hexadecimal mask samples plus `<hex-mask>`
- `-n` -> dump-count samples plus `<count>`
- `-s` -> second samples plus `<seconds>`
- `-c` / `-cl` -> CPU threshold samples plus `<cpu-percent>`
- `-cp` -> worker-count samples plus `<workers>`
- `-m` / `-ml` -> commit MB samples plus `<commit-mb>`
- `-r` -> clone concurrency samples plus `<concurrency>`
- `-at` -> timeout samples plus `<timeout-seconds>`

### Counter workflow

For `-p` and `-pl`:

- first value -> representative counter paths plus `<counter>`
- second value -> numeric threshold samples plus `<threshold>`

### Free-form and path slots

The completer uses placeholders for:

- `-md` callback DLL path
- `-f` / `-fx` filter text
- `-dc` dump comment
- `-i` optional dump folder
- `-x` dump folder and image file
- final capture dump file/folder slot

### Capture targets

At the capture target position, the completer offers:

- local process names
- local process IDs
- `<service-name>`

## Dependencies or external command expectations

- `Get-Process` is used for local target hints
- no live performance-counter enumeration is attempted
- no filesystem probing is required to complete path placeholders

## Usage / loading example

```powershell
. .\procdump_completer.ps1

# Example completions
# procdump <TAB>
# procdump -<TAB>
# procdump -p <TAB>
# procdump -mc <TAB>
# procdump pwsh <TAB>
```

## Validation notes

Validated with `pwsh -NoProfile` and `TabExpansion2` for both root and representative value contexts, including `-p <counter>`.

## Limitations / notes

- The completer intentionally prefers placeholders over live introspection.
- Service names are not enumerated.
- Counter paths are representative samples, not discovered from the local machine.
