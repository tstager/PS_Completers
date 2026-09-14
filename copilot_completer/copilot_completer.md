# copilot completer

## Overview

`copilot_completer.ps1` registers a standalone native PowerShell completer for `copilot` and `copilot.exe`.

It follows the repository's standalone completer pattern and uses a hybrid design:

- a static command / subcommand / option tree for the stable argv surface
- dynamic runtime providers for model names, marketplace names, and installed plugin names
- directory and file path completion for path-bearing values
- placeholder completions for freeform values so PowerShell does not fall back to unrelated filesystem suggestions

This completer is intentionally limited to CLI argv parsing. It does **not** attempt to complete interactive slash commands inside a Copilot session.

## Registration

- Uses `Set-StrictMode -Version Latest`
- Uses `Register-ArgumentCompleter -Native`
- Registers for `copilot` and `copilot.exe`

```powershell
. "$PSScriptRoot\copilot_completer.ps1"
```

## Static command coverage

Top-level commands:

- `completion <shell>` (`bash`, `zsh`, `fish`)
- `help`
- `init`
- `login`
- `mcp`
- `plugin`
- `plugins`
- `skill`
- `update [channel]` (`stable`, `prerelease`)
- `version`

An unknown command path never falls back to the root command list; only the global options are offered there.

Help topics:

- `commands`
- `config`
- `environment`
- `logging`
- `permissions`
- `providers`

Plugin tree:

- `plugin install`
- `plugin list`
- `plugin marketplace add`
- `plugin marketplace browse`
- `plugin marketplace list`
- `plugin marketplace remove`
- `plugin marketplace update`
- `plugin uninstall`
- `plugin update`

MCP tree:

- `mcp add` (`--env`, `--header`, `--json`, `--show-secrets`, `--timeout`, `--tools`, `--transport` with `stdio`/`http`/`sse`)
- `mcp get`, `mcp list`, `mcp remove`

Plugins tree (`copilot plugins`, the cross-kind inspector):

- `plugins disable` / `enable` / `remove|rm` (`--plugin`, `--mcp`, `--skill`)
- `plugins install|add` (`--plugin`, `--mcp`, `--skill`, `--scope` with `user`/`project`)
- `plugins list` (`--json`, `--kind`, `--scope`)
- `plugins marketplace|marketplaces` with `add`, `browse`, `list|ls`, `remove|rm`, `update|refresh`
- `plugins update` (`--all`)

Skill tree:

- `skill add` (`--project`)
- `skill list` (`--json`)
- `skill remove`

## Dynamic value providers

The completer keeps the stable command tree static, but resolves a few high-value dynamic lists from the local CLI:

- `copilot help config`
  - model names for `--model`
- `copilot plugin marketplace list`
  - marketplace names for `plugin marketplace browse` and `plugin marketplace remove`
- `copilot plugin list`
  - installed plugin names for `plugin uninstall` and `plugin update`

The script caches those runtime lists briefly to keep repeated completion responsive.

## Value-aware behavior

Notable value handling:

- `--model`
  - suggests models discovered from `copilot help config`
- `--log-level`
  - suggests `none`, `error`, `warning`, `info`, `debug`, `all`, `default`
- `--effort` / `--reasoning-effort`
  - suggests `low`, `medium`, `high`, `xhigh`
- `--output-format`
  - suggests `text`, `json`
- `--stream`
  - suggests `on`, `off`
- `--bash-env` and `--mouse`
  - support optional values and suggest `on`, `off`
- `login --host`
  - suggests example host URLs such as `https://github.com` and `https://example.ghe.com`
- `--add-dir`, `--config-dir`, `--log-dir`, `--plugin-dir`, `--extension-sdk-path`, `-C`
  - use directory completion; a value ending in `\` or `/` (and `.`, `..`, `~\`) descends into that directory
- `--attachment`
  - uses file completion
- `--mode` (`interactive`, `plan`, `autopilot`) and `--context` (`default`, `long_context`)
  - closed enum sets
- `--share[=path]`
  - supports inline `=` completion and file / directory path suggestions
- `--additional-mcp-config`
  - supports inline values
  - when the value starts with `@`, path completion is applied after the `@` prefix
- freeform slots such as `--agent`, `--prompt`, tool patterns, URL patterns, counts, and session IDs
  - use placeholders / echo completions rather than unrelated filesystem fallback

## Example scenarios

```powershell
. "$PSScriptRoot\copilot_completer.ps1"

# Root commands and global options
# copilot <TAB>

# Help topics
# copilot help <TAB>

# Nested plugin commands
# copilot plugin <TAB>
# copilot plugin marketplace <TAB>

# Dynamic values
# copilot --model <TAB>
# copilot plugin uninstall <TAB>
# copilot plugin marketplace browse <TAB>

# Path-aware values
# copilot --add-dir <TAB>
# copilot --share=<TAB>
# copilot --additional-mcp-config @<TAB>
```

## Notes and limitations

- The command / option tree is intentionally static so completion stays fast and predictable even if help text formatting changes.
- Dynamic discovery is only used for values that are both useful and cheap to query locally.
- Global options remain available under deeper command paths where the completer's parser still accepts them, not only at the root command.
- Tokens are selected by their extent relative to the cursor, so completing a value mid-line (or with the command after another statement) uses only the text left of the cursor.
- Optional-value switches such as `--resume`, `--share`, `--mouse`, and `--bash-env` are handled in both separated and inline `--flag=value` forms.
- The completer does not infer live session IDs, marketplace plugin catalogs, or interactive in-session slash commands.
- Runtime-backed suggestions depend on the installed `copilot` executable being available on `PATH`.
