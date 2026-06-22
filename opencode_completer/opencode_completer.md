# Opencode Completer

This PowerShell argument completer provides tab completion for the `opencode` command-line interface.

## Features

- Completes main opencode commands and subcommands
- Provides global option completion (`--help`, `--version`, `--model`, etc.)
- Context-aware completion for various subcommands
- Works with both `opencode` and `opencode.exe` (for Windows execution aliases)

## Installation

1. Copy the `opencode_completer` folder to your PowerShell completers directory
2. Import the completer in your PowerShell profile:
   ```powershell
   Import-CompleterScript -Path "path\to\opencode_completer\opencode_completer.ps1"
   ```
3. Or add it directly to your profile:
   ```powershell
   & "C:\path\to\opencode_completer\opencode_completer.ps1"
   ```

## Usage

After installation, the completer will automatically provide tab completion for:

- Main commands: `completion`, `acp`, `mcp`, `run`, `debug`, etc.
- Global options: `-h/--help`, `-v/--version`, `--model`, `--port`, etc.
- Subcommand-specific options where applicable

## Implementation Notes

This completer follows the repository's implementation patterns:

- Self-contained in a single `.ps1` file
- Uses `Set-StrictMode -Version Latest`
- Registers with `Register-ArgumentCompleter -Native` for both `opencode` and `opencode.exe`
- Implements context-aware completion by parsing the command AST
- Uses placeholders where appropriate to avoid noisy fallback completion
- Safe completion behavior - no destructive or state-changing operations during completion

## Maintenance

If new opencode commands or options are added, update the completer by:
1. Checking `opencode --help` for new commands and options
2. Adding them to the appropriate completion lists
3. Testing with `TabExpansion2` in a clean PowerShell session