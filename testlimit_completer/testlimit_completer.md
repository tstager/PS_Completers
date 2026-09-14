# testlimit completer

## What it completes / overview

`testlimit_completer.ps1` registers a native PowerShell completer for `testlimit`, `testlimit.exe`, `Testlimit`, and `Testlimit.exe`.

It is fully static and numeric-placeholder-driven, and it models the v5.24 usage
grammar rather than a flat switch list:

```text
testlimit [[-h [-u]] | [-p [-n]] | [-t [-n [KB]]] | [-u [-i]] | [-g [object size]]
          | [-a|-d|-l|-m|-r|-s|-v [MB]] | [-w]] [-c [count]] [-e [seconds]]
```

- top-level stress switches, restricted to one primary mode group at a time
- nested `-n` and `-i` switch handling where those are context-specific
- numeric hints for MB, count, seconds, object size, and stack-KB slots
- every numeric value is optional, so the still-legal switches stay reachable in
  a value slot

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
- `-accepteula`
- `/?`
- `/accepteula`

`-accepteula` and `/accepteula` are real but undocumented: both literals sit next
to `EulaAccepted` and `Accept Eula (Y/N)?` in the binary's string table. The two
slash forms are only offered once the typed word starts with `/`.

### Context tracking

The script tracks value-taking switches, the active primary mode group, and the
context-specific nested switches:

- exactly one primary mode may be chosen, so once `-m` (say) is on the line only
  that group's modifiers plus `-c`, `-e` and `-accepteula` are offered
- `-n` is only suggested after `-p` or `-t`
- `-i` is only suggested after `-u`
- `-c` "must be the last option specified", so once it is present no further
  switch is suggested
- `-?` and `/?` are offered while no other switch has been consumed
- a `-` or `/` typed inside a value slot completes switches, never a value

### Numeric hint sets

Representative value completions include:

- MB slots -> `1`, `16`, `64`, `256`, `<mb>`
- `-c` -> `1`, `10`, `100`, `1000`, `<count>`
- `-e` -> `0`, `1`, `5`, `10`, `<seconds>`
- `-g` -> `0`, `1`, `256`, `4096`, `<object-size-bytes>`
- `-n` after `-t` -> `64`, `128`, `256`, `1024`, `<stack-kb>`

Each of these slots also lists the switches that remain legal, because the value
is optional in every case. A typed value that is not in the sample ladder is
offered back when it is numeric; anything else collapses to the placeholder so a
numeric-only slot never confirms invalid input.

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
