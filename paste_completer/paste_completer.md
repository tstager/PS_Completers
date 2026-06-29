# paste completer

## What it completes / overview

paste_completer.ps1 registers a standalone native PowerShell completer for paste and paste.exe.

It is a static-first completer for column pasting workflows. The script exposes the common option catalog and offers delimiter values for `-d/--delimiters` while also supporting filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- delimiter suggestions for `-d/--delimiters`
- filesystem path completion for operand slots
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include:

- `-d`
- `--delimiters`
- `-s`
- `--serial`
- `-z`
- `--zero-terminated`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'paste', 'paste.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\paste_completer\paste_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## How completion works

- Tokens that begin with `-` return `ParameterName` suggestions from the static option catalog.
- The `-d/--delimiters` value slot offers common delimiter values such as `\t`, `\n`, `,`, and `|`.
- Non-switch operand slots use filesystem path completion so common file and directory inputs resolve naturally.

## Representative validation scenarios

```powershell
paste -
paste --delimiters 
paste .\
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions
- `--delimiters` returns delimiter suggestions
- operand completion offers filesystem items
- the completer remains importable through `Import-CompleterScript`
