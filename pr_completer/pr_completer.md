# pr completer

## What it completes / overview

pr_completer.ps1 registers a standalone native PowerShell completer for pr and pr.exe.

It is a static-first completer for page-formatting workflows. The script exposes the common option catalog and offers placeholder or enum values for several option-bearing slots while also supporting filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- value suggestions for `--columns`, `--header`, `--indent`, `--length`, `--width`, `--separator`, and `--page-range`
- filesystem path completion for operand slots
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include:

- `-a`
- `--across`
- `-c`
- `--show-control-chars`
- `-d`
- `--double-space`
- `-f`
- `--form-feed`
- `-h`
- `--header`
- `-l`
- `--length`
- `-m`
- `--merge`
- `-n`
- `--number-lines`
- `-w`
- `--width`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'pr', 'pr.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\pr_completer\pr_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions from the static option catalog.
- Value-bearing options such as `--columns`, `--header`, `--indent`, `--length`, `--width`, `--separator`, and `--page-range` offer useful values or placeholders.
- Non-switch operand slots use filesystem path completion so common file and directory inputs resolve naturally.

## Representative validation scenarios

```powershell
pr -
pr --length 
pr .\
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions
- `--length` returns value suggestions such as `66` or `<length>`
- operand completion offers filesystem items
- the completer remains importable through `Import-CompleterScript`
