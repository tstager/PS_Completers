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

Section headers are matched with the trailing colon optional, because Docker CLI
plugins are inconsistent about it: `docker mcp --help` prints `Available
Commands:` while `docker scout --help` prints `Available Commands` and `Usage`
with no colon at all.

Option rows are recognised by their indentation - a flag starting at column 2 or
6 - rather than by "the line contains something that looks like a flag". Docker
wraps long descriptions onto deeply indented continuation lines, and those lines
contain text such as `states) (default -1)`, which a flag-shaped regex otherwise
harvests as an option named `-1`. Continuation lines are appended to the option's
description instead, which is also what makes the enum harvest below work.

## Key completion behaviors / supported values
The script provides:
- root `docker` subcommand completion
- root `docker` option completion, including `-h` and `--help`, which Docker's
  own root help does not list
- nested completion for `docker compose`, CLI plugins such as `scout` and `mcp`,
  and deeper branches
- completion of an exact subcommand under the cursor (`docker ps<TAB>` offers
  `ps`), because a token that ends at or after the cursor is treated as the word
  being completed rather than as a settled argument
- option values in both the separate (`--log-level <TAB>`) and attached
  (`--format=j<TAB>`) forms, where the attached form keeps the `--opt=` prefix
- enum values harvested from the option's own description text: parenthesised
  alternatives such as `("debug", "info", "warn", "error", "fatal")` and
  `("never"|"always"|"auto")`, plus Docker's `--format` modes, which it documents
  as `'table':` / `'json':`
- filename completion for path-shaped options (`--config`, `--file`,
  `--env-file`, `--tlscacert`, `--project-directory`, ...) and for any
  path-shaped word, so `docker compose -f .\<TAB>` still walks the filesystem
- a `<type>` placeholder for a value slot with no enum and no path meaning, so
  the slot does not silently fill with unrelated file names
- operand placeholders taken from the `Usage:` line (`docker logs <TAB>` offers
  `<CONTAINER>`, `docker network create <TAB>` offers `<NETWORK>`); operands
  named `PATH`, `URL`, `FILE` or `DIR` are left to the engine's own path
  completion

Because completion is based on live help output, it remains aligned with the
installed Docker version rather than a stale, manually-maintained static table.

## Dependencies or external command expectations
- Requires Docker to be installed and available in `PATH`
- Uses the installed Docker executable to request `--help` output from the real CLI
- Each `--help` child runs with standard input closed and a four-second budget,
  and is killed if it outlives it, so a hung CLI plugin cannot hang the prompt
- A catalog that comes back empty is treated as a transient failure and retried
  after thirty seconds rather than being cached for the rest of the session
- Does not make any destructive or state-changing calls while completing
- Does not enumerate containers, images, volumes or contexts; those slots get a
  placeholder instead of a daemon round-trip

## Usage / loading example
```powershell
. "$PSScriptRoot\docker_completer.ps1"

# After loading, use docker and rely on the help-driven completion tree
# docker <TAB>
# docker compose <TAB>
# docker compose build <TAB>
# docker compose up <TAB>
```

## Runtime notes
- Docker version during this revision: `29.7.2`
- Validated in clean `pwsh -NoProfile` sessions with `TabExpansion2`:
  `docker ps` with the cursor at the end of `ps` (filename fallback -> `ps`),
  `docker ps --format ` (14 flags -> `table json`),
  `docker ps --format=j` (0 -> `--format=json`),
  `docker --log-level ` (82 root commands -> `debug info warn error fatal`),
  `docker run --cgroupns ` (114 flags -> `host private`),
  `docker run --pull ` (114 flags -> `always missing never`),
  `docker compose --ansi ` (49 subcommands -> `never always auto`),
  `docker scout ` (filename fallback -> 19 subcommands and flags),
  `docker context use ` (filename fallback -> `<CONTEXT>`, `-h`, `--help`),
  `docker logs ` (9 -> 12, adding `<CONTAINER>`, `-h`, `--help`),
  `docker compose up -` (38 -> 37, losing the bogus `-1` and gaining
  `--timeout`, `--timestamps`, `--wait`, `-h`, `--help`),
  `docker build .\` and `docker compose -f .\` unchanged at path completion,
  `$x = 1; docker ps -` identical to the same input at the start of a line
- `$Error` did not grow across the probe set

## Limitations / notes
- This script does not implement every Docker plugin surface as a static custom grammar.
- The authoritative source remains the installed Docker CLI help output, so behavior matches the local Docker version.
- The script keeps the separate Compose surface out of the repository; Compose is completed as a nested branch under the root `docker` command.
