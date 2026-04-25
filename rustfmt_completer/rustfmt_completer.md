# rustfmt completer

## What it completes / overview

`rustfmt_completer.ps1` registers a standalone native PowerShell completer for `rustfmt` and `rustfmt.exe`.

It is a **help-driven** completer with safe local discovery:

- parses the installed `rustfmt --help` surface for switches
- reads local `rustfmt --help=config` output for config key names
- completes local files and directories for file-bearing arguments

The completion path does not format files or modify configuration.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('rustfmt', 'rustfmt.exe') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\rustfmt_completer\rustfmt_completer.ps1
```

The script also enables:

```powershell
Set-StrictMode -Version 2.0
```

## Import-CompleterScript compatibility

The file keeps its top level compatible with `CompleterActions`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, `try` blocks, helper invocations, or external command calls.

## How completion works

### Switch surface

The completer covers the documented top-level switches, including:

- `--check`
- `--emit`
- `--backup`
- `--config-path`
- `--edition`
- `--style-edition`
- `--color`
- `--print-config`
- `-l`, `--files-with-diff`
- `--config`
- `-v`, `--verbose`
- `-q`, `--quiet`
- `-V`, `--version`
- `-h`, `--help`

### Representative value slots

The completer returns value suggestions for common non-path slots:

- `--emit` → `files`, `stdout`
- `--edition` → `2015`, `2018`, `2021`, `2024`
- `--style-edition` → `2015`, `2018`, `2021`, `2024`
- `--color` → `always`, `never`, `auto`
- `--print-config` → `default`, `minimal`, `current`
- `--help` → `config`
- `--config` → config keys from installed `rustfmt --help=config`

For `--config`, the completer also recognizes `key=value` forms and suggests values for several documented keys such as:

- `edition`
- `style_edition`
- `newline_style`
- `use_small_heuristics`
- `match_arm_leading_pipes`
- `fn_params_layout`
- common boolean config keys

### Path completion

The completer uses local-only filesystem enumeration for:

- `--config-path`
- the path argument after `--print-config`
- positional file operands

### Multi-value switch handling

`--print-config` takes two values in sequence:

```text
--print-config [default|minimal|current] PATH
```

The completer tracks that state so the first value is the mode and the next value becomes a local path completion slot.

## Usage examples

```powershell
rustfmt -<TAB>
rustfmt --color <TAB>
rustfmt --emit <TAB>
rustfmt --print-config <TAB>
rustfmt --print-config current <TAB>
rustfmt --config <TAB>
rustfmt --config edition=<TAB>
rustfmt .\<TAB>
rustfmt.exe --help <TAB>
```

## Runtime notes

- The completer registers both `rustfmt` and `rustfmt.exe`.
- Help/config harvesting is lazy and cached in script scope.
- `--config-path` is treated as a local directory search root because rustfmt searches from that path for `rustfmt.toml`.

## Limitations

- `--config` accepts comma-delimited key/value lists; this completer only suggests a single `key=` or `key=value` segment at a time.
- It does not attempt to inspect project-specific config schemas beyond the installed help output.
- Path completion is local-only and prefix-based.
