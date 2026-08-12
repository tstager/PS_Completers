# Docker completer

## What it completes / overview
`docker_completer.ps1` implements a help-driven native PowerShell completer for the Docker CLI. It targets the root `docker` command and routes nested help output into the appropriate command context, including `docker compose` and deeper compose subcommands like `build`, `up`, `logs`, and `exec`.

This is intentionally not a separate `docker-compose` surface. Compose is treated as a first-class subcommand under `docker` and is completed from the same root command tree.

## Registration and command names
The script registers completions directly with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('docker', 'docker.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-DockerCommand -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

This keeps the repository in line with the expected import-safe shape for native completers in this repo.

## How completion works
The script uses Docker's own `--help` output as the authority for available commands and flags.

Execution flow:
1. Resolve the installed `docker` or `docker.exe` path from `PATH`.
2. Cache a command catalog in `$script:` based on the current command path.
3. Parse `docker --help` and nested command help such as `docker compose --help` and `docker compose build --help`.
4. Use the current token stream to determine whether the user is completing:
   - root Docker commands
   - root Docker flags
   - a nested subcommand branch
   - a nested flag set for that subcommand
5. Return matching `CompletionResult` entries for subcommands and option names.

The parsing intentionally tracks sections such as:
- `Common Commands`
- `Management Commands`
- `Commands`
- `Options`
- `Global Options`

and then normalizes them into a reusable help catalog.

## Key completion behaviors / supported values
The script provides:
- root `docker` subcommand completion
- root `docker` option completion, including `-h` and `--help`
- nested completion for `docker compose` and deeper `compose` branches
- help-driven completion for subcommand names and option names
- filtering by the active partial word so suggestions stay narrow and predictable

Because completion is based on live help output, it remains aligned with the installed Docker version rather than a stale, manually-maintained static table.

## Dependencies or external command expectations
- Requires Docker to be installed and available in `PATH`
- Uses the installed Docker executable to request `--help` output from the real CLI
- Does not make any destructive or state-changing calls while completing

## Usage / loading example
```powershell
. "$PSScriptRoot\docker_completer.ps1"

# After loading, use docker and rely on the help-driven completion tree
# docker <TAB>
# docker compose <TAB>
# docker compose build <TAB>
# docker compose up <TAB>
```

## Limitations / notes
- This script does not implement every Docker plugin surface as a static custom grammar.
- The authoritative source remains the installed Docker CLI help output, so behavior matches the local Docker version.
- The script keeps the separate Compose surface out of the repository; Compose is completed as a nested branch under the root `docker` command.
