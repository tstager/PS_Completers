# docker compose tab completion for PowerShell

This completer provides native PowerShell completion for the Docker Compose surface exposed by `docker compose` and the legacy `docker-compose` executable.

## Coverage

- Root-level `docker compose` and `docker-compose` subcommand completion
- Subcommand-specific option completion for commands such as `build`, `config`, `up`, `down`, and others
- Dynamic value suggestions for enum-like options such as `--format` and `--ansi`
- Path completion for file- and directory-bearing flags such as `-f`, `--file`, `--env-file`, `--project-directory`, and `--output`

## Implementation notes

The completer is self-contained and import-safe. It uses the installed Docker CLI to read live help output from:

- `docker compose --help`
- `docker compose <subcommand> --help`
- `docker-compose --help`
- `docker-compose <subcommand> --help`

It also tolerates common Docker help heading variants such as `Options:`, `Flags:`, and `Commands:` so it stays usable across Docker releases. The registration path uses both native and standard argument completers to ensure the Docker command surface gets the compose-specific completion behavior in PowerShell.
