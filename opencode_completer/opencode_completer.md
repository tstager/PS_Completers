# Opencode Completer

This PowerShell argument completer provides tab completion for the `opencode` command-line interface.

## Features

- Completes the full command tree of opencode 1.18.30: all 21 root commands with their aliases (`auth` for `providers`, `plug` for `plugin`) and every documented second- and third-level subcommand (`mcp add|list|auth|logout|debug`, `debug config|lsp|rg|file|...`, `db path`, `github install|run`, `providers list|login|logout`, `session list|delete`, `agent create|list`)
- Per-command option tables transcribed from `opencode <command> --help`, plus the root options (`--auto` carries its "dangerous!" wording in the tooltip)
- Option values in the separate and attached form: `--log-level`, `run --format`, `db --format`, `upgrade --method`, `run --variant`, `agent create --mode`, `session list --format`, `--hostname`; path options (`run --file`, `--dir`, `acp --cwd`, `agent create --path`) complete files or directories; other values get a typed placeholder (`<provider/model>`, `<session-id>`, `<port>`)
- Operands: `import <file>` completes paths, `attach <url>`, `pr <number>`, `plugin <module>`, `upgrade [target]` and `models [provider]` offer placeholders, `run [message..]` is free text
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
- Static-first: the command tree, options and enum values live in one lazily built `$script:` catalog; the completer never launches `opencode`
- Implements context-aware completion by walking the command AST (command chain, pending option values, positional count)
- Uses placeholders where appropriate to avoid noisy fallback completion
- Safe completion behavior - no destructive or state-changing operations during completion

## Maintenance

If new opencode commands or options are added, update the completer by:
1. Checking `opencode --help` and `opencode <command> --help` for new commands and options
2. Adding them to the catalog in `Get-OpencodeCompletionCatalog` (`New-OpencodeCommand`, `New-OpencodeOption`, `New-OpencodePositional`)
3. Testing with `TabExpansion2` in a clean PowerShell session