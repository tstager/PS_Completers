# Chocolatey (`choco`) completer

## Overview

`choco_completer.ps1` provides native PowerShell argument completion for both
`choco` and `choco.exe`. It is designed around the installed Chocolatey 2.x
command surface and uses `choco --help` plus `choco <command> --help` as the
primary source for commands, aliases, switches, switch descriptions, and
value-bearing options.

The static catalog is used only when Chocolatey is unavailable or its help
cannot be parsed. Dynamic help data is cached for the PowerShell session.

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('choco', 'choco.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-ChocoNative -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Dot-source the script to install the registration:

```powershell
. .\choco_completer\choco_completer.ps1
```

## Completion behavior

The completer understands the command and subcommand routing documented by
Chocolatey's live help, including:

- `apikey`, `setapikey`: `list`, `add`, `remove`
- `cache`: `list`, `remove`
- `config`: `list`, `get`, `set`, `unset`
- `feature`, `features`: `list`, `get`, `disable`, `enable`
- `license`: `info`
- `pin`: `list`, `add`, `remove`
- `rule`: `list`, `get`
- `source`, `sources`: `list`, `add`, `remove`, `disable`, `enable`
- `template`, `templates`: `list`, `info`

Global and per-command options are parsed from the installed command. Both
single-dash, double-dash, and slash forms are accepted. Separate
(`/source <value>`) and attached (`/source=<value>`) value forms are completed,
with the option prefix retained. File-system values with spaces or PowerShell
metacharacters are quoted as one argument.

## Safe dynamic values

The completer uses bounded, short-lived caches for read-only local commands:

- `choco list --local-only --limit-output --no-color` for package names and
  locally installed versions
- `choco source list --limit-output --no-color` for configured source names
  and locations
- `choco feature list --limit-output --no-color` for feature names
- `choco config list --limit-output --no-color` for config keys
- `choco rule list --limit-output --no-color` for rule identifiers
- `choco template list --limit-output --no-color` for installed templates

Processes close standard input, redirect output, and use a short timeout, so
completion cannot wait for interactive input.

Sensitive slots are deliberately placeholder-only. API keys, passwords,
certificate passwords, installer arguments, and package parameters are never
enumerated from Chocolatey configuration or package state.

## Path and value completion

Path-aware completion is provided for:

- cache, log, certificate, export, and output directory options
- local package inputs for `install`, `pack`, and `push`
- source locations

The completer also provides enum and numeric candidates for documented values
such as checksum algorithms, search ordering, source priorities, timeouts,
and pagination. Unknown value-bearing options receive an explicit `<value>`
placeholder, suppressing PowerShell's unrelated file fallback.

## Validation

The script is shaped for the CompleterActions strict import grammar: its
top-level statements are `Set-StrictMode`, the blessed script-cache guard,
function declarations, and the literal native registration call.

Representative validation uses:

```powershell
Import-Module CompleterActions -MinimumVersion 3.0.0
Test-CompleterScript -LiteralPath .\choco_completer\choco_completer.ps1

pwsh -NoProfile -Command ". .\choco_completer\choco_completer.ps1; (TabExpansion2 'choco install --' 15).CompletionMatches"
```
