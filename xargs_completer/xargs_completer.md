# xargs completer

## What it completes / overview

`xargs_completer.ps1` registers a standalone native PowerShell completer for `xargs` and `xargs.exe`.

It is a static-first completer that:

- covers the documented GNU coreutils `xargs` option surface from `xargs --help`
- suggests short and long options at the start of the command line
- provides value-aware completion for argument-file, delimiter, numeric, replace-token, and eof-string slots
- offers command-name suggestions for the trailing command operand when the current position is not consuming an option value

## Command and build

The completer targets the Windows `xargs.exe` implementation from the coreutils family. The option set is derived from the local `xargs --help` output observed on this machine and is encoded directly in the script so the completer remains fully self-contained and does not depend on a module or build step.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'xargs', 'xargs.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\xargs_completer\xargs_completer.ps1
```

It also enables:

```powershell
Set-StrictMode -Version 2.0
```

## Completion behavior

### Options

The completer suggests the documented options from the coreutils help output:

- `-a`, `--arg-file` for an input-file path
- `-d`, `--delimiter` for a delimiter token
- `-x`, `--exit`
- `-n`, `--max-args` and `-L`, `--max-lines` for numeric values
- `-l` for an optional numeric `max-lines` value
- `-P`, `--max-procs` for a numeric process count
- `-r`, `--no-run-if-empty`
- `-0`, `--null`
- `-s`, `--max-chars` for a numeric character budget
- `-t`, `--verbose`
- `-i`, `--replace` and `-I` for replace-token values
- `-E`, `-e`, `--eof` for an eof string
- `-h`, `--help` and `-V`, `--version`

### Value slots

When the current token is in a value-bearing option slot, the completer returns placeholder or context-aware suggestions:

- `-a`, `--arg-file` uses local path completion
- `-d`, `--delimiter` offers a placeholder for a delimiter value
- numeric options show an `<max>` placeholder
- `-i`, `--replace`, `-I`, `-E`, `-e`, and `--eof` show a `<R>` or `<eof-string>` placeholder

### Command operand

When the current position is the first non-option operand, the completer offers command names discovered from the current PowerShell session.

## Usage examples

```powershell
xargs 
xargs -
xargs -a 
xargs --arg-file=
xargs -n 
xargs -i 
xargs -e 
```

## Dependencies or external command expectations

- The completer is self-contained and does not require a build step.
- It uses the documented `xargs --help` option surface observed on the current machine as the basis for its option catalog.
- Command-name suggestions depend on the current PowerShell session's command discovery.
