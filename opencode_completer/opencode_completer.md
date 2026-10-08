# Opencode Completer

This PowerShell argument completer provides tab completion for the `opencode` command-line interface.

## Features

- Completes the full command tree of opencode 1.18.30: all 21 root commands with their aliases (`auth` for `providers`, `plug` for `plugin`) and every documented second- and third-level subcommand (`mcp add|list|auth|logout|debug`, `debug config|lsp|rg|file|...`, `db path`, `github install|run`, `providers list|login|logout`, `session list|delete`, `agent create|list`)
- Per-command option tables transcribed from `opencode <command> --help`, plus the root options (`--auto` carries its "dangerous!" wording in the tooltip)
- Option values in the separate and attached form: `--log-level`, `run --format`, `db --format`, `upgrade --method`, `run --variant`, `agent create --mode`, `session list --format`, `--hostname`; path options (`run --file`, `--dir`, `acp --cwd`, `agent create --path`) complete files or directories as one literal argument (quoted when the name needs it, in the quote style typed, typographic quotes included; `--file=` keeps the option inside the word); other values get a typed placeholder (`<port>`, `<title>`)
- Live identifiers (placeholder fallback when a source is missing or empty):
  - Session IDs for `-s/--session` (root, `run`, `attach`), `export [sessionID]` and `session delete <sessionID>`: the same set as `opencode session list` (root sessions of the current project, newest first), read with a bounded `opencode db "<select>" --format json` (5 s timeout, models.dev fetch and auto-update disabled; `db` skips the instance bootstrap, so nothing is registered or written). Cached until the database changes, and for at least 30 s
  - Models for `-m/--model` (root, `run`, `agent create`): `provider/model` pairs read from opencode's models cache (`~/.cache/opencode/models.json`) plus the `provider` blocks of the config files, filtered like `opencode models` (usable providers only, deprecated/alpha dropped, `opencode` free models without a key, `whitelist`/`blacklist`, `enabled_providers`/`disabled_providers`); never runs `opencode models`, which refreshes the cache over the network
  - Providers: usable ones for `models [provider]`, every catalog provider for `providers login -p`, and the names stored in `auth.json` for `providers logout` (names only, credential values are never read into the cache)
  - Agents for `--agent` and `debug agent <name>`: the built-ins plus `{agent,agents}/**/*.md`, `{mode,modes}/*.md` and the `agent`/`mode` config blocks from the global config directory and the project's `.opencode` directories (`disable: true` honoured)
  - MCP servers for `mcp auth|debug [name]` from the merged `mcp` config blocks, and for `mcp logout [name]` from `mcp-auth.json` (names only)
  - Values with spaces or metacharacters are quoted; a typed opening quote is kept
- Operands: `import <file>` completes paths, `attach <url>`, `pr <number>`, `plugin <module>` and `upgrade [target]` offer placeholders, `run [message..]` is free text
- Tokens right of the cursor are ignored and the word under the cursor is taken from the AST, so mid-line editing works
- Works with both `opencode` and `opencode.exe` (for Windows execution aliases)

## Installation

1. Copy the `opencode_completer` folder to your PowerShell completers directory
2. Import the completer in your PowerShell profile:
   ```powershell
   Import-CompleterScript -Path "path\to\opencode_completer\opencode_completer.ps1"
   ```
3. Or add it directly to your profile:
   ```powershell
   . "C:\path\to\opencode_completer\opencode_completer.ps1"
   ```

## Usage

After installation, the completer will automatically provide tab completion for:

- Main commands: `completion`, `acp`, `mcp`, `run`, `debug`, etc., and their subcommands
- Root options: `-h/--help`, `-v/--version`, `--model`, `--port`, `--auto`, `--mini`, etc.
- Subcommand-specific options and their values, for example `opencode run --format <TAB>` or `opencode upgrade --method=<TAB>`

## Implementation Notes

This completer follows the repository's implementation patterns:

- Self-contained in a single `.ps1` file
- Uses `Set-StrictMode -Version Latest`
- Registers with `Register-ArgumentCompleter -Native` for both `opencode` and `opencode.exe`
- Static-first: the command tree, options and enum values live in one lazily built `$script:` catalog; identifier slots read opencode's files passively (JSONC config, models cache, credential names), and only session IDs start a process (`opencode db`); all live data is cached in `$script:` state keyed by file stamps
- Implements context-aware completion by walking the command AST (command chain, pending option values, positional count)
- Uses placeholders where appropriate to avoid noisy fallback completion
- Safe completion behavior - no destructive or state-changing operations during completion

## Maintenance

If new opencode commands or options are added, update the completer by:
1. Checking `opencode --help` and `opencode <command> --help` for new commands and options
2. Adding them to the catalog in `Get-OpencodeCompletionCatalog` (`New-OpencodeCommand`, `New-OpencodeOption`, `New-OpencodePositional`)
3. Testing with `TabExpansion2` in a clean PowerShell session