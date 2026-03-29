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
- Remote auth:
  - `-u` -> `<username>`, `<domain\user>`
  - `-p` -> `<password>`
- Identifier slot:
  - `<file-id>`
  - `<path>`
  - `"C:\path\fragment*"`
- Close switch:
  - `-c` is suggested only after an identifier is already present
  - its tooltip explicitly calls out the destructive effect

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('psfile', 'psfile.exe') -ScriptBlock { ... }
```

## Notes

- The completer does not attempt to infer whether the identifier is numeric or path-like.
- The `-c` completion is documentation-oriented only; completion never triggers close behavior.

