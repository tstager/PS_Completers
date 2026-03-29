# testlimit completer

## What it completes / overview

`testlimit_completer.ps1` registers a native PowerShell completer for `testlimit`, `testlimit.exe`, `Testlimit`, and `Testlimit.exe`.

It is fully static and numeric-placeholder-driven:

- top-level stress switches
- nested `-n` and `-i` switch handling where those are context-specific
- numeric hints for MB, count, seconds, object size, and stack-KB slots

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `testlimit`, `testlimit.exe`, `Testlimit`, `Testlimit.exe`
- The file enables `Set-StrictMode -Version 2.0`

Load it with:

```powershell
. .\testlimit_completer.ps1
```

## How completion works

### Static switch catalog

The completer covers the validated Testlimit surface:

- `-a`
- `-c`
- `-d`
- `-e`
- `-g`
- `-h`
- `-i`
- `-l`
- `-m`
- `-n`
- `-p`
- `-r`
- `-s`
- `-t`
- `-u`
- `-v`
- `-w`
- `-?`
- `/?`

### Context tracking

The script tracks value-taking switches and the context-specific nested switches:

- `-n` is only suggested after `-p` or `-t`
- `-i` is only suggested after `-u`

### Numeric hint sets

Representative value completions include:

- MB slots -> `1`, `16`, `64`, `256`, `<mb>`
- `-c` -> `1`, `10`, `100`, `1000`, `<count>`
- `-e` -> `0`, `1`, `5`, `10`, `<seconds>`
- `-g` -> `0`, `1`, `256`, `4096`, `<object-size-bytes>`
- `-n` after `-t` -> `64`, `128`, `256`, `1024`, `<stack-kb>`

## Dependencies or external command expectations

This completer is fully static and does not need to invoke `Testlimit.exe` at completion time.

## Usage / loading example

```powershell
. .\testlimit_completer.ps1

# Example completions
# testlimit <TAB>
# testlimit -<TAB>
# testlimit -c <TAB>
# testlimit -t -n <TAB>
```

## Validation notes

Validated with `pwsh -NoProfile` and `TabExpansion2`, including both bare and `.exe` forms.

## Limitations / notes

- The completer does not try to model the full stress-workflow semantics beyond the validated switch/value shapes.
- It intentionally favors numeric placeholders over deeper command validation.
