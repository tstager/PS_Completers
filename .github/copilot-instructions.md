# PS_Completers Workspace Instructions

## Repo Purpose

This repository contains standalone PowerShell argument completer scripts for native command-line tools. Each file is intended to be dot-sourced into a PowerShell session or profile and should work independently without requiring a module or build step.

## What To Preserve

- Keep each completer self-contained in a single `.ps1` file.
- Match the existing script style before introducing a new pattern.
- Prefer repository-consistent PowerShell over abstract helper layers shared across files.
- Avoid adding module manifests, classes, or extra scaffolding unless the user explicitly asks for a structural change.

## Core Implementation Patterns

- Register completions with `Register-ArgumentCompleter` and use `-Native` for native executables when the existing file style does so.
- Accept the standard completer parameters: `$wordToComplete`, `$commandAst`, and `$cursorPosition`.
- Use `System.Management.Automation.CompletionResult` objects for emitted completions.
- Filter suggestions with prefix matching against `$wordToComplete`.
- Use `Set-StrictMode` near the top of the file. Existing scripts use either `2.0` or `Latest`; preserve the local style unless there is a clear reason to align a file differently.

## Choose The Right Completer Style

Use the simplest style that matches the command being completed.

- Static command trees:
  Use explicit `CompletionResult` lists and subcommand routing when the command surface is known and stable.
  Reference examples: `dotnet_completer.ps1`, `DSC_completer.ps1`

- Dynamic native/tool-backed completion:
  Prefer invoking the tool or its built-in completer when that keeps results aligned with the installed version.
  Reference examples: `gh_cli_completer.ps1`, `Git_completer.ps1`

- Help-text parsing:
  Parse `/?` or similar built-in help when the tool exposes authoritative switches or value hints there.
  Cache parsed data in script scope if the help call is expensive.
  Reference examples: `dism_completer.ps1`, `schtasks_completer.ps1`

## Repository-Specific Conventions

- Check that an external command exists before invoking it. Use `Get-Command -ErrorAction SilentlyContinue` or `Stop` with explicit error handling.
- Keep expensive discovery work cached in `$script:` scope rather than recalculating on every completion.
- When command context matters, derive it from `CommandAst.CommandElements` or tokenized input and route by subcommand.
- Use `CompletionResultType` intentionally:
  `ParameterName` for switches and flags, `ParameterValue` for subcommands, values, branch names, task names, and file paths.
- Prefer plain PowerShell collections and small local helper scriptblocks/functions over heavy abstraction.
- Keep comments short and only where they explain non-obvious parsing or caching logic.

## Editing Guidance

- Extend the existing command map, switch tables, or parser logic instead of rewriting a completer from scratch.
- Preserve naming and casing patterns already present in the target file.
- Do not add unrelated refactors while changing a completer.
- If a file already uses namespaces (`using namespace ...`), keep that style in the same file.
- If a file already uses script-scoped catalogs or caches, update those structures rather than introducing parallel state.

## Validation

There is no formal build or test harness in this repo. Validate changes with lightweight PowerShell checks.

- Dot-source the edited script in a PowerShell session.
- Confirm the target executable exists if the completer depends on it.
- Smoke-test that the completer loads without syntax/runtime errors.
- When practical, verify tab completion behavior for one or two representative commands.

Example load pattern:

```powershell
. .\Git_completer.ps1
. .\schtasks_completer.ps1
```

## Good Reference Files

- `Git_completer.ps1`: dynamic completions, token inspection, helper scriptblocks
- `dotnet_completer.ps1`: large static completion tree with subcommand routing
- `dism_completer.ps1`: help parsing plus script-scoped caching
- `schtasks_completer.ps1`: value hints, path completion, cached runtime data

## Avoid

- Adding a cross-file framework or shared dependency for a small one-file change
- Replacing targeted completion logic with generic placeholder suggestions
- Hardcoding values that can be discovered cheaply from the target tool
- Removing strict mode, command existence checks, or cache guards from dynamic completers
