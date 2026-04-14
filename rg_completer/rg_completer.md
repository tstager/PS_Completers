# rg completer

## What it completes / overview

`rg_completer.ps1` registers a standalone native PowerShell completer for `rg` and `rg.exe`.

It is a help-driven completer that:

- parses the local `rg.exe --help` surface once per session
- caches file type names from `rg.exe --type-list`
- suggests both short and long options
- supports inline `--option=value` completion and attached `-tTYPE` / `-TTYPE` type completion
- provides targeted enum hints for `--engine`, `--color`, `--sort`, `--generate`, `--hyperlink-format`, and common encodings
- completes real filesystem paths for path-bearing operands and options like `-f` and `--ignore-file`
- suppresses noisy filesystem fallback for regex, glob, replacement, separator, and command-valued slots with placeholder-oriented suggestions

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'rg', 'rg.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\rg_completer\rg_completer.ps1
```

The script also enables:

```powershell
Set-StrictMode -Version 2.0
```

## Import and runtime behavior

The completer keeps its top level import-safe for `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal native `Register-ArgumentCompleter` call

All help parsing, command resolution, and type discovery happen lazily from helper functions during completion instead of at import time.

## How completion works

### Help-driven option catalog

Initialization captures `rg.exe --help` and parses the option synopsis lines into a cached option catalog. That gives the completer a local view of the installed ripgrep build without hard-coding the entire flag set.

### Dynamic type completion

The completer also captures `rg.exe --type-list` and caches the discovered type names. Those are used for:

- `-t`, `--type`
- `-T`, `--type-not`
- `--type-clear`

### Operand routing

The completer tracks ripgrep's main positional modes:

- normal search mode expects a first positional pattern
- `-e` / `--regexp` and `-f` / `--file` switch ripgrep into path-only positional mode
- `--files` also uses path-only positionals
- terminal modes such as `--type-list`, `--version`, and `--pcre2-version` suppress normal positional suggestions

### Placeholder-only slots

Free-form slots such as regex patterns, globs, replacements, separators, and preprocessor commands intentionally return placeholders or the typed value instead of generic filesystem completions.

## Usage examples

```powershell
rg 
rg -
rg --sort=
rg --engine=
rg --type=
rg -tps
rg foo .\
rg -f .\
```

## Dependencies or external command expectations

- Expects `rg.exe` or `rg` to be resolvable if help data and type names should be harvested
- Falls back to placeholder-oriented completion when runtime discovery is unavailable
- Filesystem completion depends on local filesystem access

## Limitations / notes

- The completer does not attempt to parse every combined short-flag form; it focuses on the most relevant attached ripgrep type form (`-tTYPE`, `-TTYPE`) plus long `--option=value`.
- Encoding suggestions use a curated common set instead of enumerating every WHATWG label.
- `--colors` and `--type-add` use representative examples and placeholders rather than trying to fully validate ripgrep's mini-languages during completion.
