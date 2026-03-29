# du completer

## What it completes / overview

`du_completer.ps1` registers a standalone native PowerShell completer for `du` and `du.exe`.

It is a lightweight help-driven completer that:

- parses the local `du.exe /?` surface once during initialization
- offers `-c` and the attached `-ct` CSV variant
- provides sample numeric values for `-l`
- completes the final operand as a directory only

The completion path does not execute disk-usage scans.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'du', 'du.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\du_completer\du_completer.ps1
```

The script also enables:

```powershell
Set-StrictMode -Version 2.0
```

## How completion works

### Help-driven switch catalog

Initialization starts from a small static switch catalog and then overlays descriptions from local `du.exe /?`.

Modeled switches include:

- `-c`
- `-ct`
- `-l`
- `-n`
- `-q`
- `-u`
- `-v`
- `-nobanner`
- `/?`

### Value-aware handling

- `-l` is treated as a value-taking switch and returns numeric depth hints
- `-l`, `-n`, and `-v` are treated as mutually exclusive recursion-depth modes
- `-c` and `-ct` are treated as sibling forms so both are not suggested together

### Directory operand completion

For the final positional operand, the completer only returns directory candidates. That keeps the result set aligned with `du` usage and avoids generic file suggestions.

## Usage examples

```powershell
du <TAB>
du -c<TAB>
du -l <TAB>
du .\<TAB>
```

## Dependencies or external command expectations

- Expects `du.exe` or `du` to be resolvable if help text should be harvested
- Falls back to the static catalog if help capture is unavailable
- Directory completion depends on local filesystem access

## Limitations / notes

- The completer does not try to infer an appropriate directory from prior command history.
- `/?` is treated as terminal for completion.
- `-l` returns sample depth values and echoes a typed custom value when needed to suppress filesystem fallback.
