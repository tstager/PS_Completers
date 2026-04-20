# fd completer

## What it completes / overview

`fd_completer.ps1` registers a native PowerShell completer for `fd` and `fd.exe`.

It is help-driven: the script parses the locally installed `fd.exe --help` output to build the option catalog, then layers a small set of static value hints on top for enum and path-bearing options.

## Registration and command names

The script registers:

- `fd`
- `fd.exe`

with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('fd', 'fd.exe') -ScriptBlock { ... }
```

## Supported completion behavior

- Switch completion comes from the installed `fd.exe --help` output.
- `--color`, `--hyperlink`, and `--strip-cwd-prefix` offer `auto`, `always`, and `never`.
- `--type` offers both short and long file-type selectors such as `f`, `file`, `d`, `directory`, `x`, and `executable`.
- `--base-directory`, `--ignore-file`, and `--search-path` complete filesystem paths.
- `--extension`, `--size`, `--changed-within`, and `--changed-before` offer conservative example values and placeholders.
- After the first positional pattern has been supplied, subsequent positional arguments complete as search paths.

## Dependencies or external command expectations

The completer depends on the installed `fd` / `fd.exe` help output for the option list. It does not execute searches during completion, and it does not perform network operations.

## Usage / loading example

```powershell
. .\fd_completer\fd_completer.ps1
```

Example scenarios:

```powershell
fd --<TAB>
fd --type <TAB>
fd --color <TAB>
fd --base-directory <TAB>
fd pattern .\<TAB>
```

## Limitations / notes

- Enum-like value suggestions are static hints layered over the help-driven option catalog.
- `--exec` and `--exec-batch` provide placeholder suggestions rather than trying to parse arbitrary command tails.
- The first positional slot is treated as a search-pattern slot unless the current input already looks like a path.
