# codex completer

## What it completes / overview

`codex_completer.ps1` is a tool-backed wrapper around the local `codex` CLI's
own PowerShell completion generator.

Instead of re-implementing the `codex` command tree in this repository, the
script runs `codex completion powershell`, rewrites the generated
self-registration into an invokable script block, and caches that script block
for later completion requests.

## Registration and command names

The repository script registers a native completer for:

```powershell
'codex', 'codex.cmd', 'codex.ps1'
```

That broader registration is intentional on Windows:

- `codex` is the normal command users type
- `codex.cmd` is the preferred native launcher path for generating completions
- `codex.ps1` can also be resolved by `Get-Command` in PowerShell sessions

The generated upstream script currently self-registers only for `codex`, so the
wrapper removes that registration line and invokes the generated script block
directly for all three command names.

## How completion works

Execution flow:

1. `Set-StrictMode -Version Latest` is enabled.
2. On first completion request, the script resolves a launcher path, preferring
   `codex.cmd`, then `codex`, then `codex.ps1`.
3. It runs `completion powershell` against that resolved launcher and captures
   stdout only.
4. It rewrites the generated `Register-ArgumentCompleter` line into a named
   script block assignment.
5. It compiles the rewritten source with `[scriptblock]::Create(...)` and caches
   the invoker in script scope.
6. Later completions reuse the cached invoker without re-running `codex`.

## Runtime quirks

- On this machine, both `codex.cmd` and `codex.ps1` emit a PATH update warning
  on stderr before printing the completion script. The wrapper suppresses stderr
  so only the generated PowerShell source is cached.
- The generated script is authoritative for command, subcommand, and option
  coverage, so completion behavior tracks the installed `codex` version.
- The current upstream script does not appear to offer shell-name completions
  after `codex completion`, so PowerShell can still fall back to filesystem
  completion for inputs such as `codex completion p`.
- Import time stays cheap because the script does not call `codex` until a real
  completion request occurs.

## Usage / loading example

```powershell
. "$PSScriptRoot\codex_completer.ps1"

# codex <TAB>
# codex exec <TAB>
# codex.cmd completion <TAB>
# codex.ps1 review <TAB>
```

## Limitations / notes

- If `codex` is not installed or `codex completion powershell` fails, the
  wrapper returns no completions.
- The wrapper depends on the current generated script shape continuing to expose
  a single inline `Register-ArgumentCompleter -Native -CommandName 'codex'`
  block.
- This implementation intentionally avoids top-level cache initialization,
  registration loops, and external command calls so it remains importer-safe.
