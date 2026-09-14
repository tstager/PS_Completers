# psfile completer

## What it completes / overview

`psfile_completer.ps1` registers a standalone native PowerShell completer for `psfile` and `psfile.exe`.

The completer is intentionally pure static and non-enumerating:

- no remote sessions are probed
- no file IDs are discovered dynamically
- no paths are enumerated from remote hosts

Instead, it completes the documented PsFile syntax with remote placeholders, remote-auth placeholders, file-id/path placeholders, and a clearly marked destructive `-c` suggestion.

## Key completion behaviors

- Remote preamble: `\\<RemoteComputer>`, `\\localhost`, `\\*`
  - offered only in the leading positional slot, because the documented usage
    `psfile [\\RemoteComputer [-u Username [-p Password]]] [[Id | path] [-c]]`
    forbids a remote target after the identifier or after `-c`
- Remote auth:
  - `-u` -> `<username>`, `<domain\user>`
  - `-p` -> `<password>`
- Identifier slot:
  - `<file-id>`
  - `<path>`
  - `"C:\path\fragment*"`
- Switches: `-nobanner`, `-accepteula`, `-?`, `/?`; the slash forms `/nobanner`
  and `/accepteula` (real but undocumented) appear only once the typed word
  starts with `/`
- Close switch:
  - `-c` is suggested only after an identifier is already present, exactly once
  - its tooltip explicitly calls out the destructive effect

Every suggestion goes through one emitter that applies a single case-insensitive
prefix filter and de-duplicates by completion text, so a partially typed
identifier or path is never rewritten into an unrelated switch. Any token that
starts with `-` or `/` is treated as a switch, never as the file identifier.

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('psfile', 'psfile.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsFile -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

## Notes

- The completer does not attempt to infer whether the identifier is numeric or path-like.
- The `-c` completion is documentation-oriented only; completion never triggers close behavior.

