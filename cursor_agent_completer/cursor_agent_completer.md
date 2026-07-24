# cursor-agent completer

## What it completes / overview

`cursor_agent_completer.ps1` registers a standalone native PowerShell argument completer for the Cursor Agent CLI.

The script follows the repository's standalone completer pattern:

- it uses a script-scoped lazy cache,
- it registers with `Register-ArgumentCompleter -Native`,
- it resolves the installed `cursor-agent` launcher (`cursor-agent.cmd`, `cursor-agent.ps1`, or `cursor-agent`),
- and it uses live `cursor-agent --help` output for root switches and subcommands.

## Registration and command names

The script registers the same native completer for:

- `cursor-agent`
- `cursor-agent.cmd`
- `cursor-agent.ps1`

Note that the bare `agent` name is deliberately not registered. Cursor Agent shipped `agent.cmd` in earlier
versions and still installs it as a legacy alias, but `agent` is now ambiguous on a machine that also has the
Grok CLI installed, which provides its own `agent.exe`. See [grok_completer.md](../grok_completer/grok_completer.md),
which claims `agent` for that binary.

## How completion works

### 1. Help-driven discovery

`Initialize-CursorAgentCompletionCatalog` lazily loads the root help surface from the installed Cursor Agent CLI.

It uses:

- `cursor-agent --help` for the root command surface,
- `cursor-agent mcp --help` for `mcp` subcommand completion,
- and a small built-in value map for enum-style flags such as `--mode`, `--output-format`, and `--sandbox`.

### 2. Root-level suggestions

At the top level, the completer suggests:

- root switches such as `--api-key`, `--help`, `--mode`, `--output-format`, `--workspace`, and `--worktree`,
- and top-level subcommands such as `login`, `logout`, `mcp`, `worker`, `status`, `models`, `about`, `update`, `create-chat`, `generate-rule`, `rule`, and `ls`.

### 3. Subcommand-aware completion

When the user selects `mcp`, the completer adds `mcp` subcommands such as `login`, `list`, `list-tools`, `enable`, and `disable`.

### 4. Value-aware option completion

For value-taking options, the completer offers inline completions for enum values when the option is known to support them. For path-bearing flags such as `--workspace`, `--add-dir`, and `--plugin-dir`, it offers local path suggestions.

## Dependencies or external command expectations

The completer expects an installed `cursor-agent` launcher on `PATH` (for example `cursor-agent.cmd` in the Cursor Agent install directory).

If the command is not available, the completer returns no suggestions.

## Usage / loading example

Dot-source the script:

```powershell
. .\cursor_agent_completer.ps1
```

Example completion scenarios:

```powershell
cursor-agent <TAB>
cursor-agent --<TAB>
cursor-agent mcp <TAB>
cursor-agent --output-format <TAB>
cursor-agent --workspace <TAB>
```
