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
- `cursor-agent <path> --help`, fetched lazily the first time a validated subcommand path (`mcp`, `worker`, `plugin marketplace`, `bedrock`, ...) is completed and cached for the session (misses are cached too),
- and a small built-in value map for enum-style flags such as `--mode`, `--output-format`, `--sandbox`, and `status --format`.

### 2. Root-level suggestions

At the top level, the completer suggests:

- root switches such as `--api-key`, `--help`, `--mode`, `--output-format`, `--workspace`, and `--worktree`,
- and top-level subcommands such as `login`, `logout`, `mcp`, `worker`, `status`, `models`, `about`, `update`, `create-chat`, `generate-rule`, `rule`, and `ls`.

### 3. Subcommand-aware completion

The completer walks the committed tokens to the deepest validated subcommand path and offers only that node's own options and subcommands (commander does not inherit root options into subcommands). For example `cursor-agent mcp <TAB>` offers `login`, `list`, `list-tools`, `enable`, and `disable`; `cursor-agent mcp list <TAB>` offers just `-h`/`--help`; `cursor-agent worker --<TAB>` offers the worker options.

### 4. Value-aware option completion

A value slot is only opened for options whose help line shows a `<value>` or `[value]` placeholder, so boolean switches such as `--plan` or `--continue` fall through to normal option completion. Short spellings (`-e`, `-H`, `-w`) resolve to the same value slot as their long form. For value-taking options, the completer offers inline completions for enum values when the option is known to support them. For path-bearing flags such as `--workspace`, `--add-dir`, and `--plugin-dir`, it offers local path suggestions; other value slots get a placeholder. The attached long form completes the same values and keeps the option prefix: `cursor-agent --mode=pl<TAB>` gives `--mode=plan`, and `--workspace=<TAB>` lists paths as `--workspace=<path>`. Short options have no `=` form in commander (`-w=x` would pass `=x` as the value), so only `--opt=value` is handled.

Path completions that contain whitespace or argument-mode metacharacters (`{ } ( ) ; , | & < > ' " `` ` `` $`) are quoted so PowerShell passes them as one argument, and a quoted directory drops its trailing separator as PowerShell's own path completion does. A quote you already typed is kept (single quotes by default, with `'` doubled; double quotes escape `` ` ``, `"` and `$` with a backtick). In the attached form the whole token is quoted: `cursor-agent --workspace=pr<TAB>` gives `'--workspace=proj dir'`, and `--workspace="pr<TAB>` gives `"--workspace=proj dir"`. After a `--` terminator commander treats everything as positional, so the completer offers no options or option values there.

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
