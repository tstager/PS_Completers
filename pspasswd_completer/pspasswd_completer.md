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
- Remote auth (offered only after a remote target and before the account):
  - `-u` -> `<username>`, `<domain\user>`
  - `-p` -> `<password>`
- Singleton switches: `-nobanner`, `-accepteula` (accepted by the binary, never printed by its help), `-?`, `/?`
- Account slot:
  - `<account>`
  - `<domain\account>`
  - representative examples such as `Administrator`
  - hints are filtered by the typed prefix, so `Adm<Tab>` narrows to `Administrator`
- New password slot:
  - returns `<new-password>` when blank
  - echoes the user-typed token when not blank, to suppress filesystem fallback without exposing secret-specific behavior
- Once both `<Account>` and `[NewPassword]` are present nothing else is offered, matching the usage line
- Only tokens that end at or before the cursor count as prior state, so editing an earlier switch mid-line still offers the switch list

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('pspasswd', 'pspasswd.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsPasswd -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

## Notes

- `@file` completion is local-only and path-aware.
- Domain-account syntax is represented as placeholders only; no directory lookups are attempted.

