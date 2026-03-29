# psloglist completer

## What it completes / overview

`psloglist_completer.ps1` registers a standalone native completer for `psloglist` and `psloglist.exe`.

The implementation is hybrid:

- the syntax surface is static and help-driven
- local-only runtime hints are used for event log names and event source/publisher names
- runtime hints are cached, cheap, and explicitly disabled when a remote target is present

## Key completion behaviors

### Remote and auth preamble

- `\\<computer>`
- `\\localhost`
- `\\*`
- `@file`
- `-u` -> `<username>`, `<domain\user>`
- `-p` -> `<password>`

### Value-aware switches

- numeric slots (`-m`, `-n`, `-d`, `-h`) return sample numbers
- date slots (`-a`, `-b`) return `mm/dd/yy`-style hints
- `-f` returns filter-letter samples such as `we`
- `-i` and `-e` return comma-separated event ID hints
- `-t` returns delimiter hints and is only suggested after `-s`
- `-l` and `-g` use local path completion for saved/exported event log files

### Event log and source hints

When no remote target is present, the completer builds a short-lived cache from local `Get-WinEvent -ListLog *` data:

- event log names feed the final `<event log>` slot
- provider names feed `-o` and `-q`

When a remote target is present, those runtime hints are disabled and the completer falls back to placeholders and a few static common names.

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('psloglist', 'psloglist.exe') -ScriptBlock { ... }
```

## Notes

- The completer does not query remote event logs.
- Cached local hints are advisory only and do not imply the command will succeed.
- Destructive switches such as `-c` are only surfaced as syntax; completion never executes them.

