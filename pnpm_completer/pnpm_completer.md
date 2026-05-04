# pnpm completer

## What it completes / overview

`pnpm_completer.ps1` is a **tool-backed** standalone completer for the local
`pnpm` CLI.

It wraps pnpm's official generated PowerShell completion script from:

```powershell
pnpm completion pwsh
```

instead of re-implementing the full pnpm command tree in this repository.

The repository wrapper is also **importer-safe**:

- no top-level external command calls
- no top-level cache initialization
- no top-level loops or helper invocations
- one literal `Register-ArgumentCompleter -Native` call for all registered
  launcher names

## Registration and command names

The script registers a native completer for:

```powershell
'pnpm', 'pnpm.cmd', 'pnpm.ps1'
```

That broader registration is intentional on this machine because PowerShell can
resolve pnpm through multiple launcher names on Windows, while the upstream
generated script self-registers only for `pnpm`.

## How completion works

Execution flow:

1. `Set-StrictMode -Version Latest` is enabled.
2. On the first real completion request, the wrapper lazily resolves a launcher
   path, preferring `pnpm.cmd`, then `pnpm`, then `pnpm.ps1`.
3. It runs `pnpm completion pwsh` through that resolved launcher.
4. It rewrites pnpm's self-registration line into an invokable script block.
5. It compiles and caches that script block in script scope.
6. Later completion requests reuse the cached upstream invoker instead of
   regenerating the script.

## Minimal fallback behavior

The official pnpm completion is the primary engine.

However, on this machine the upstream generator can still leave some contexts
without results, which causes PowerShell to fall back to filesystem completion
for inputs like:

- `pnpm config `
- `pnpm store `
- `pnpm cache `

To keep those slots useful, the wrapper adds a **small lazy help-based
fallback**:

- root commands come from `pnpm help -a`
- nested `config`, `store`, and `cache` command surfaces come from
  `pnpm help <command>`
- option fallback stays limited to command names and option names only

The fallback does **not** do project/package/workspace/registry discovery.

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript`
by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, `try`/`catch` blocks, loops, helper
invocations, or external command calls.

## Runtime notes

- Local pnpm version during implementation: `10.33.3`
- Local launcher names observed: `pnpm`, `pnpm.cmd`, `pnpm.ps1`
- No `pnpm.exe` was present on this machine
- The wrapper intentionally depends on `pnpm help <command>` instead of
  `<command> --help` for fallback parsing
- The wrapper does not depend on `pnpm exec --help`, because that surface is
  unreliable in an empty or non-package repository

## Representative validation

Validated in clean `pwsh -NoProfile` sessions with:

- parser check and clean dot-source load
- `Import-CompleterScript`
- `TabExpansion2 'pnpm '`
- `TabExpansion2 'pnpm a'`
- `TabExpansion2 'pnpm add --'`
- `TabExpansion2 'pnpm config '`
- `TabExpansion2 'pnpm store '`
- `TabExpansion2 'pnpm cache '`
- `TabExpansion2 'pnpm.cmd '`
- `TabExpansion2 'pnpm.ps1 '`

Validation also confirmed:

- the upstream script is not loaded at import time
- first completion lazily creates the cached upstream invoker
- later completions reuse that cached invoker
