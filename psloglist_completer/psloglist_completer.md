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

- numeric slots (`-m`, `-n`, `-d`, `-h`) return sample numbers, filtered by the typed prefix
- date slots (`-a`, `-b`) return `mm/dd/yy`-style hints
- `-f` returns filter-letter samples such as `we`
- `-i` and `-e` return comma-separated event ID hints; the last comma-separated segment is what gets filtered, and once one of the pair is on the line the other is no longer offered
- `-t` returns delimiter hints and is only suggested after `-s`
- `-l` and `-g` use local path completion for saved/exported event log files (`.evt`/`.evtx` plus directories); an empty slot lists the current directory
- `-o` and `-q` complete comma-separated source names and always offer a `<source>*` hint for the documented substring form

Tokens to the right of the cursor are ignored, so editing an earlier value mid-line completes that slot, and a quoted multi-word log name such as `"Windows Pow` completes to `"Windows PowerShell"`.

### Event log and source hints

When no remote target is present, the completer harvests local hints lazily, only for the slot being completed:

- event log names come from the tool's own `psloglist -nobanner -z` listing (stdin closed, 1.5 s timeout, only when the Sysinternals EULA is already accepted), falling back to `Get-WinEvent -ListLog *`; the result is cached for two minutes whether or not the harvest succeeded
- provider names for `-o` and `-q` come from `(Get-WinEvent -ListLog <log>).ProviderNames` for the log named on the line (default `System`), cached per log

When a remote target is present, those runtime hints are disabled and the completer falls back to placeholders and a few static common names.

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('psloglist', 'psloglist.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsLogList -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

## Notes

- The completer does not query remote event logs.
- Cached local hints are advisory only and do not imply the command will succeed.
- Destructive switches such as `-c` are only surfaced as syntax; completion never executes them.

