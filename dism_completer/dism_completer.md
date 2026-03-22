# dism completer

## What it completes / overview

`dism_completer.ps1` registers a native PowerShell argument completer for `dism`.

This completer is help-driven and partially lazy-loaded. It builds a cached catalog from DISM's built-in help output and expands command-specific switches when a command becomes active.

## Registration and command names

- Registers with: `Register-ArgumentCompleter -Native`
- Command name:
  - `dism`

The script discovers command verbs from DISM help rather than hardcoding the full command list. It reads:

- top-level help: `dism /?`
- `/Online` help: `dism /Online /?`
- additional help for individual global options and active commands as needed

## How completion works

The script stores cached data in `$script:DismCompletionCatalog`:

- `Commands`
- `GlobalSwitches`
- `HelpTokensByKey`
- `ValuesByOptionKey`

Initialization parses help output to extract:

- command verbs
- global switches
- option tokens for specific help contexts
- enumerated value hints for options

Value hints come from two help patterns:

- inline sets such as `/Option:{A | B}`
- option help blocks where accepted values are documented as `Value = Description`

When a specific command is present on the command line, the script lazily loads that command's help once and merges its switches into future suggestions for that context.

## Key completion behaviors / supported values

- At the root, it suggests:
  - discovered DISM command verbs
  - discovered global switches
- Once an active command is detected, it suggests:
  - global switches
  - command-specific switches parsed from that command's help
- If the current token already looks like `/Option:partialValue`, the completer:
  - suggests enumerated values when the option has a value map
  - otherwise falls back to path completion for path-like options
- Path-like options are detected by option names ending with:
  - `path`
  - `dir`
  - `file`
  - `image`
- File extension filtering is applied for these options:
  - `/PackagePath:` → `.cab`, `.msu`
  - `/WimFile:` → `.wim`, `.esd`, `.swm`
  - `/ImageFile:` → `.wim`, `.esd`, `.swm`, `.ffu`, `.vhd`, `.vhdx`
  - `/SourceImageFile:` → `.wim`, `.esd`, `.swm`, `.ffu`, `.vhd`, `.vhdx`
  - `/VhdFile:` → `.vhd`, `.vhdx`
  - `/SwmFile:` → `.swm`
- If the current word looks like a filesystem path or wildcard, the script returns matching path completions.

## Dependencies or external command expectations

- Requires `dism` to be available.
- Relies on the current DISM help format remaining parseable.
- Uses help from the installed DISM version, so suggestions track the local system instead of a static list.

## Usage / loading example

```powershell
. .\dism_completer.ps1
```

Example scenarios after loading:

```powershell
dism /<Tab>
dism /Online /<Tab>
dism /ImageFile:C:\Images\<Tab>
```

## Limitations / notes

- If DISM help cannot be read, suggestions may be empty or incomplete.
- Path completion is heuristic and based on option naming plus a few explicit extension maps.
- The script does not provide rich completion for arbitrary positional values outside the parsed help/value patterns.
