---
name: powershell-completer-implementation
description: Implement or extend standalone PowerShell argument completers for native commands in this repository. Use this when asked to create, refine, document, or validate a completer script, especially when the command surface comes from /?, --help, subcommand help, or cautious runtime discovery.
argument-hint: "[command] [executable] [help source] [expected behaviors]"
---

# PowerShell Completer Implementation

Use this skill for work in the `PS_Completers` repository when the task is to add or improve a native PowerShell completer.

This skill captures the repository's implementation patterns, the recurring runtime issues discovered while building completers, and the clean-session validation flow that proved the work actually functions in real `pwsh` usage.

## Goal

Deliver a standalone completer that:

- lives in its own `<name>_completer` folder
- keeps all completer logic in a single `.ps1` file
- includes a companion `.md` document
- updates the alphabetical row in `README.md`
- works through real `Register-ArgumentCompleter -Native` runtime behavior, not only direct helper invocation

## When to use which implementation style

Choose the simplest style that matches the target command:

- **Static-first**
  Use explicit switch tables, subcommand maps, and placeholder values when the command grammar is stable.
  Good references:
  - `dotnet_completer\dotnet_completer.ps1`
  - `DSC_completer\DSC_completer.ps1`
  - `psshutdown_completer\psshutdown_completer.ps1`

- **Help-driven**
  Parse `/?`, `-?`, `--help`, or subcommand help when the tool publishes authoritative switches or values.
  Cache expensive parsing in `$script:` scope.
  Good references:
  - `dism_completer\dism_completer.ps1`
  - `schtasks_completer\schtasks_completer.ps1`
  - `du_completer\du_completer.ps1`
  - `ru_completer\ru_completer.ps1`

- **Tool-backed / dynamic**
  Use installed tool output or safe local discovery only when that keeps the completer aligned with the installed version and does not introduce risk or latency.
  Good references:
  - `Git_completer\Git_completer.ps1`
  - `gh_cli_completer\gh_cli_completer.ps1`
  - `pslist_completer\pslist_completer.ps1`
  - `psloglist_completer\psloglist_completer.ps1`

## Implementation rules

### Keep the file self-contained

- Put the completer in a single shipped `.ps1` file.
- Avoid cross-file helper frameworks for one command.
- Prefer small local helper functions and script-scoped caches.

### Match repository conventions

- Use `Set-StrictMode` near the top and preserve local style (`2.0` or `Latest`) unless there is a good reason not to.
- Use `Register-ArgumentCompleter -Native`.
- Accept the standard parameters: `$wordToComplete`, `$commandAst`, `$cursorPosition`.
- Emit `System.Management.Automation.CompletionResult`.
- Use `ParameterName` for switches and `ParameterValue` for values, subcommands, process names, registry paths, file paths, and placeholders.

### Prefer safe completion behavior

- Do not make destructive or state-changing calls while completing.
- Do not enumerate remote systems during completion.
- For risky verbs or sensitive slots, offer placeholders instead of live probing.
- Use local-only caches for safe data like process names, event logs, services, or directories.

### Use placeholders to beat noisy fallback

When PowerShell would otherwise fall back to filesystem completion in a non-path slot, emit explicit placeholder values instead:

- `<username>`
- `<domain\user>`
- `<new-password>`
- `\\<computer>`
- `@file`
- `<path>`

This is especially useful for native commands with free-form value positions.

### Route by actual command context

- Inspect `CommandAst.CommandElements` and tokenized input.
- Track tokens before the current word.
- Detect whether the user is completing a switch, switch value, operand, registry path, `@file`, executable path, or subcommand.
- When already in a path or provider-path mode, suppress unrelated root switch suggestions.

### Cache expensive discovery carefully

- Cache parsed help output in `$script:` scope.
- Cache local discovery with short-lived or lazy initialization if it is moderately expensive.
- Do not recompute heavy discovery on every keystroke.

## Runtime edge cases learned from this repo

Apply these checks proactively:

- **Native registration should usually cover both bare and `.exe` names.**
  This matters for commands that resolve through Windows app execution aliases.

- **Some commands need explicit bare-name alias help.**
  If real `TabExpansion2` proves the native completer does not engage reliably for the bare command, add a conservative alias bootstrap only when no alias already exists.

- **Do not assume help exits `0`.**
  Many native tools print valid help and exit nonzero. Treat useful help output as authoritative even when the exit code is not.

- **Do not assume `--help` is real help.**
  Some tools treat it as an operand or behave differently from `/?`.

- **Test `@file` with a bare `@`.**
  Empty path portions must not throw from `Split-Path`.

- **Test slash-prefixed apps separately.**
  Commands like `shellrunas` may use `/reg`, `/unreg`, `/quiet`, and can accidentally leak a literal `/` completion if path completion is not gated.

- **Provider paths need dedicated handling.**
  Registry-aware completers should preserve provider completion for values like `HKLM:\` or `HKCU\Software\`.

## Recommended workflow

1. Inspect the target command locally with `Get-Command` and help output.
2. If local help is incomplete or graphical, use authoritative vendor or product docs.
3. Choose static, help-driven, or tool-backed completion based on the real command surface.
4. Create:
   - `<name>_completer\<name>_completer.ps1`
   - `<name>_completer\<name>_completer.md`
5. Implement the completer with repository-consistent helper naming and caching style.
6. Update the alphabetical row in `README.md`.
7. Validate in clean `pwsh -NoProfile` sessions with `TabExpansion2`.
8. If runtime behavior differs from direct helper invocation, fix the registered/runtime path.

## Validation requirements

Use the checklist in [validation-checklist.md](./validation-checklist.md).

Minimum validation for a new completer:

- parse the script with PowerShell's parser
- dot-source the script in a clean session
- confirm representative `TabExpansion2` results
- verify one or more switch surfaces
- verify value completions for at least one non-path slot
- verify path or provider-path completion when the completer supports it
- validate both bare and `.exe` invocation names when relevant

Prefer representative real-world checks over calling helper functions directly.

## Repository integration

For repository work, finish with all of the following:

- standalone folder added
- `.ps1` script added
- `.md` doc added
- `README.md` row added in alphabetical order
- clean-session validation performed
- if requested by the user, add the completer to the profile's `#region Argument Completers`

## Reference files

- `README.md`
- `.github/copilot-instructions.md`
- `Git_completer\Git_completer.ps1`
- `dism_completer\dism_completer.ps1`
- `schtasks_completer\schtasks_completer.ps1`
- `du_completer\du_completer.ps1`
- `ru_completer\ru_completer.ps1`
- `pslist_completer\pslist_completer.ps1`
- `psshutdown_completer\psshutdown_completer.ps1`
- `groff_completer\groff_completer.ps1`

## Output expectations

When using this skill:

- explain which completer style you chose and why
- mention any special runtime quirks discovered
- validate with clean-session `pwsh -NoProfile` commands
- call out whether registration needed both bare and `.exe` names
- mention any deliberately placeholder-only or non-enumerating slots
