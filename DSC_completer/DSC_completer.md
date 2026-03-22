# DSC completer

## What it completes / overview

`DSC_completer.ps1` registers a native PowerShell argument completer for the `dsc` CLI.

This script is a static command tree: it maps specific `dsc` command paths to predefined `CompletionResult` objects and does not call the external `dsc` executable for discovery.

## Registration and command names

- Registers with: `Register-ArgumentCompleter -Native`
- Command name:
  - `dsc`

Top-level command coverage includes:

- `completer`
- `config`
- `extension`
- `resource`
- `schema`
- `help`

Nested command coverage includes:

- `config get|set|test|validate|export|resolve|help`
- `extension list|help`
- `resource list|get|set|test|delete|schema|export|help`
- `help completer|config|extension|resource|schema|help`

The `help` branches mirror much of the main command tree, so help subcommands also receive completions.

## How completion works

The script builds a semicolon-delimited command path from the current `CommandAst`, starting at `dsc`.

It keeps adding tokens while they are:

- bare words
- not switches
- not the current word being completed

That command path is matched in a `switch` statement and returns a static list of `CompletionResult` objects for the matching context. Final output is then prefix-filtered against `$wordToComplete` and sorted by `ListItemText`.

## Key completion behaviors / supported values

- Root completion suggests:
  - global switches such as trace/progress/help/version options
  - top-level `dsc` subcommands
- `config` completion exposes:
  - shared configuration switches
  - verbs such as `get`, `set`, `test`, `validate`, `export`, and `resolve`
- `resource` completion exposes:
  - verbs such as `list`, `get`, `set`, `test`, `delete`, `schema`, and `export`
  - operation-specific switches like `--resource`, `--input`, `--file`, and `--output-format` where defined in the script
- `extension list` and `schema` have their own small static switch sets.
- `help` command paths are also modeled, so `dsc help ...` receives guided subcommand completion.

## Dependencies or external command expectations

- No external command invocation is required by this completer.
- The script only needs to be dot-sourced or otherwise loaded into the session.

## Usage / loading example

```powershell
. .\DSC_completer.ps1
```

Example scenarios after loading:

```powershell
dsc <Tab>
dsc config <Tab>
dsc resource get --<Tab>
```

## Limitations / notes

- The command tree is static, so it can drift from the installed `dsc` CLI over time.
- It does not provide dynamic completion for:
  - resource names
  - extension names
  - file paths
  - output-format values
- Like the `dotnet` completer, context detection stops when it reaches an option or another non-bareword token.
