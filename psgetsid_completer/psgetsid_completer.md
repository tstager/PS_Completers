# psgetsid completer

## What it completes / overview
`psgetsid_completer.ps1` registers a standalone native PowerShell completer for `psgetsid` and `PsGetsid.exe`.

The implementation is intentionally small and static, based on locally validated PsGetsid runtime behavior:
- first positional completion models the real ambiguity between remote-target syntax and local `account | SID`
- `-u` and `-p` are only offered in remote context, not before a remote target
- `@file` uses filesystem-aware completion
- free-form identity, username, and password slots return placeholder hints or echo the current token to suppress irrelevant filesystem fallback
- `-?` and `/?` are treated as terminal help triggers

The script also enables `Set-StrictMode -Version 2.0` and emits `System.Management.Automation.CompletionResult` objects throughout.

## Registration and command names
- Registers with `Register-ArgumentCompleter -Native`
- Command names: `psgetsid`, `PsGetsid.exe`
- The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'psgetsid', 'PsGetsid.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsGetsid -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it into the current session with:

```powershell
. .\psgetsid_completer\psgetsid_completer.ps1
```

## How completion works
### Static command model
The completer uses a small script-scoped catalog for the locally confirmed surface:
- `-u`
- `-p`
- `-nobanner`
- `-?`
- `/?`

It does not attempt remote discovery or remote enumeration.

### Token-state parsing
`Complete-PsGetsid` reconstructs the active token from the command line when needed and scans prior tokens to determine:
- whether the command is in local or remote mode
- whether the current position is the value slot for `-u` or `-p`
- whether a remote target has already been supplied
- whether an identity argument is already present
- whether help mode is terminal

That state is what keeps the completer aligned with normal registered runtime use and `TabExpansion2`.

### First positional ambiguity
The first non-switch slot is intentionally modeled as ambiguous:
- remote target forms:
  - `\\<computer>`
  - `\\localhost`
  - `\\<current-computer>`
  - `\\*`
  - `@<file>`
- local identity hints:
  - `<account>`
  - `<domain\user>`
  - `<SID>`

If the user starts with `\\...` or `@...`, the completer stays in remote-target handling.
If the user starts with any other free-form token, the completer treats that position as the local `account | SID` slot.

### Remote-target handling
The completer supports the documented remote token shapes without trying to enumerate actual machines:
- `\\computer`
- `\\*`
- comma-separated lists as one token, for example `\\server1,\\server2`
- `@file`

For `@file`, the completer uses local filesystem completion and preserves directory navigation by returning container results with a trailing path separator.

### Remote credential handling
Once a remote target is present:
- `-u` becomes available
- `-p` becomes available only after a `-u` value has been supplied
- `-nobanner` remains available as a singleton switch

The value slots provide placeholder hints:
- `-u`:
  - `<username>`
  - `<domain\user>`
- `-p`:
  - `<password>`

If the current token is already a free-form value, the completer echoes it back as a value completion so PowerShell does not fall back to file paths.

### Help handling
`-?` and `/?` are treated as terminal help triggers.

Before substantive arguments are present, they are suggested alongside `-nobanner`.
After either help token is already on the command line, the completer returns a terminal no-more-arguments completion to suppress unrelated fallback suggestions.

## Key completion behaviors / supported values
### Root / first-slot completion
At the start of the command, completion can suggest:
- remote-target placeholders
- local identity placeholders
- `-nobanner`
- `-?`
- `/?`

### Remote target examples
```powershell
psgetsid \\<TAB>
psgetsid \\localhost,<TAB>
psgetsid @<TAB>
```

### Remote credential examples
```powershell
psgetsid \\localhost -<TAB>
psgetsid \\localhost -u <TAB>
psgetsid \\localhost -u domain\user -<TAB>
```

### Identity examples
```powershell
psgetsid <TAB>
psgetsid S-1-5-<TAB>
psgetsid \\localhost Administrator<TAB>
```

## Dependencies or external command expectations
- No remote enumeration is performed
- No network probing is performed
- The completer does not need to execute `PsGetsid.exe` to produce completions
- `@file` completion depends on local filesystem access

## Usage / loading example
```powershell
. "$PSScriptRoot\psgetsid_completer.ps1"

# Example completions
# psgetsid <TAB>
# psgetsid \\localhost -<TAB>
# psgetsid @<TAB>
# psgetsid \\localhost -u <TAB>
# psgetsid \\localhost Administrator<TAB>
```

## Limitations / notes
- The completer intentionally uses placeholders and current-token echoing for free-form values rather than attempting account or SID discovery.
- It does not validate whether a typed SID or account is real.
- It does not try to discover remote computers or parse computer-name files.
- `-u` and `-p` are intentionally withheld before a remote target because local runtime probing showed they are remote-context switches.
- `-?` and `/?` are modeled as terminal help paths even though `-nobanner` may still appear separately in the syntax surface.
- In PowerShell, partially typed `@file` operands may complete more reliably when the whole token is quoted, for example `"@R<TAB>"`, because bare `@name` text can run into parser ambiguity before native completion runs.
