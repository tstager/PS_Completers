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

On the definition row itself only the leading `-s, --long` cluster names the
option. Dashed words later in the description (`--parallel int  Control max
parallelism, -1 for`, `--tls  Use TLS; implied by --tlsverify`) are description
text, not aliases, so they neither appear as flags nor hide the real name and
its value type.

The synthetic `-h`/`--help` pair is added unless the help already lists one of
them, compared case-sensitively, so the root's `-H` (`--host`) does not count.

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
- live object names in operand and option-value slots, taken from the CLI's
  own cobra completion (`docker __complete <settled words> ""`): containers for
  `docker logs <TAB>` / `docker exec <TAB>`, images for `docker run <TAB>` /
  `docker rmi <TAB>`, networks for `docker run --network <TAB>` (and
  `--network=b<TAB>`), volumes, and Compose service names for
  `docker compose up <TAB>` in a project directory. The partial word is filtered
  locally, so one query serves every keystroke; a name that needs quoting, or a
  word the user opened with a quote, is emitted quoted
- context names for `docker -c <TAB>`, `docker --context=<TAB>` and the
  `CONTEXT` operand of `docker context use|rm|inspect|export|update`, read
  passively from `<config>/contexts/meta/*/meta.json` plus `default` (only the
  name and the docker endpoint, shown as the tooltip, are read)
- a `<type>` placeholder for a value slot with no enum, no path meaning and no
  live values, so the slot does not silently fill with unrelated file names
- operand placeholders taken from the `Usage:` line when no live names exist
  (`docker network create <TAB>` offers `<NETWORK>`); operands named `PATH`,
  `URL`, `FILE` or `DIR` are left to the engine's own path completion
- nothing after the operands of a command whose usage ends in a `COMMAND` /
  `ARG...` tail (`run`, `create`, `exec`, their `container` forms, and
  `compose run|exec`): `docker run alpine <TAB>` and `docker run alpine -<TAB>`
  belong to the container's command line, which docker's own completion also
  leaves alone, so docker's flags are not offered there

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
- `docker __complete` runs through the same bounded child (stdin closed,
  four-second budget, ANSI stripped). Its answer, including an empty one, is
  cached for 15 seconds per working directory, `DOCKER_HOST`, `DOCKER_CONTEXT`,
  `DOCKER_CONFIG`, `COMPOSE_FILE`, `COMPOSE_PROFILES` and settled words
- Daemon-backed queries run only when the effective endpoint (resolved like the
  CLI: `--context`, `-H/--host`, `DOCKER_HOST`, `DOCKER_CONTEXT`, the store's
  `currentContext`) is a local `npipe://` pipe that already exists or a local
  `unix://` socket. A remote endpoint (`tcp://`, `ssh://`), an unknown context,
  or a stopped engine keeps the placeholder: completion never makes a network
  call and never starts Docker Desktop
- Compose service completion reads the project files and needs no daemon, so it
  is not gated on the engine. Other CLI plugins (`scout`, `buildx`, `model`,
  `debug`, ...) are never asked, because their completion may reach the network

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
- Live names (Docker 29.8.2, Desktop running): `docker logs ` (12 -> 24, 13
  containers replace `<CONTAINER>`), `docker run ` (115 -> 174 images),
  `docker compose up ` in a project (38 -> 52 services), `docker -c ` and
  `docker context use ` (`desktop-linux`, `default`),
  `docker run --network=b` (0 -> `--network=bridge`),
  `docker logs 'ai_memory-d` (0 -> quoted container names). `docker -H tcp://...
  logs `, `docker --context nosuchctx logs ` and `docker buildx use ` start no
  process and keep their placeholders. Cold Tab 0.5-0.7 s, warm about 25 ms
- Docker 29.8.2: `docker -` (17 with a duplicate `--tlsverify` -> 18, adding
  `-h` and `--help`), `docker --he` (0 -> `--help`), `docker compose -` (loses
  `-1`), `docker compose --parallel ` and `docker update --pids-limit `
  (`<for>` -> `<int>`), `docker run alpine -` and `docker run alpine ls `
  (114 run flags -> none; PowerShell's filename fallback applies),
  `docker exec <container> ` (17 exec flags -> none)

## Limitations / notes
- This script does not implement every Docker plugin surface as a static custom grammar.
- The authoritative source remains the installed Docker CLI help output, so behavior matches the local Docker version.
- The script keeps the separate Compose surface out of the repository; Compose is completed as a nested branch under the root `docker` command.
