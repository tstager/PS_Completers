# pspasswd completer

## What it completes / overview

`pspasswd_completer.ps1` registers a standalone native PowerShell completer for `pspasswd` and `pspasswd.exe`.

The completer is intentionally pure static and explicitly non-enumerating:

- it never probes remote systems
- it never inspects local accounts or domain accounts
- it never tries to reveal or complete passwords from stored values

Instead, it focuses on the documented syntax shapes for both local-account and domain-account usage.

## Key completion behaviors

- Remote preamble for local-account mode:
  - `\\<computer>`
  - `\\localhost`
  - `\\*`
  - `@file`
- Remote auth:
  - `-u` -> `<username>`, `<domain\user>`
  - `-p` -> `<password>`
- Account slot:
  - `<account>`
  - `<domain\account>`
  - representative examples such as `Administrator`
- New password slot:
  - returns `<new-password>` when blank
  - echoes the user-typed token when not blank, to suppress filesystem fallback without exposing secret-specific behavior

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('pspasswd', 'pspasswd.exe') -ScriptBlock { ... }
```

## Notes

- `@file` completion is local-only and path-aware.
- Domain-account syntax is represented as placeholders only; no directory lookups are attempted.

