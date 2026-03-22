# Oh My Posh completer

## What it completes / overview
`OhMyPosh_completer.ps1` registers a PowerShell argument completer for `oh-my-posh` and `oh-my-posh.exe`.

The implementation is static and table-driven. It suggests top-level subcommands, a shared set of global flags, and a smaller set of subcommand-specific flags for a predefined subset of commands.

## Registration and command names
- Registers with `Register-ArgumentCompleter`
- Command names: `oh-my-posh`, `oh-my-posh.exe`
- Entry point: `$OhMyPoshCompleter`

```powershell
Register-ArgumentCompleter -CommandName oh-my-posh.exe, oh-my-posh -ScriptBlock $OhMyPoshCompleter
```

Unlike some other completers in this repository, this file does not use `-Native` and does not enable strict mode.

## How completion works
The completer scriptblock accepts the standard parameters:
- `$wordToComplete`
- `$commandAst`
- `$cursorPosition`

It derives the active subcommand by converting the command AST to text, splitting on a literal space, and taking the second token:

```powershell
$tokens = $commandAst.ToString().Split(' ')
$subcommand = $tokens | Select-Object -Skip 1 | Select-Object -First 1
```

The rest of the logic is driven by static arrays and a hashtable:
- `$mainCommands` contains the top-level command list.
- `$globalFlags` contains flags offered everywhere.
- `$subcommandFlags` maps selected subcommands to their extra flags.

Behavior:
- If no recognized subcommand is present, it suggests matching top-level commands and matching global flags.
- If a recognized subcommand is present, it suggests that subcommand's mapped flags and then also suggests matching global flags.
- Every emitted item is returned as a `System.Management.Automation.CompletionResult` with `ParameterValue` as the result type.

## Key completion behaviors / supported values
### Top-level commands
The static top-level command list is:
- `auth`
- `cache`
- `claude`
- `config`
- `debug`
- `disable`
- `enable`
- `font`
- `get`
- `help`
- `init`
- `notice`
- `print`
- `shell`
- `toggle`
- `upgrade`
- `version`

### Global flags
The shared flag list is:
- `--config`
- `-c`
- `--shell`
- `-s`
- `--plain`
- `--trace`
- `--version`
- `--help`
- `-h`
- `--init`
- `-i`

### Subcommand-specific flag tables
The file defines extra flags for these subcommands:
- `init`: `--shell`, `-s`, `--config`, `-c`, `--print`, `-p`
- `config`: `--output`, `-o`, `--config`, `-c`, `--list`, `-l`
- `print`: `--shell`, `-s`, `--config`, `-c`, `--cursor-position`, `--error`
- `debug`: `--shell`, `-s`, `--config`, `-c`
- `get`: `--shell`, `-s`, `--config`, `-c`
- `toggle`: `--config`, `-c`, `--shell`, `-s`
- `enable`: `--config`, `-c`
- `disable`: `--config`, `-c`
- `cache`: `--clean`, `--delete`, `--info`
- `font`: `--install`, `--info`, `--list`
- `auth`: `--login`, `--logout`, `--status`

Subcommands that are in `$mainCommands` but not in `$subcommandFlags` still receive the shared global flags when active.

## Dependencies or external command expectations
This script does not call `oh-my-posh` to discover completion data and does not verify that the executable exists before registering the completer.

Its only runtime dependency is PowerShell's argument completer infrastructure and `System.Management.Automation.CompletionResult`.

## Usage / loading example
```powershell
. "$PSScriptRoot\OhMyPosh_completer.ps1"

# Example completions
# oh-my-posh <TAB>
# oh-my-posh init <TAB>
# oh-my-posh font <TAB>
```

## Limitations / notes
- The command and flag lists are fully static in this file.
- Completion logic only looks at the second space-delimited token to determine the active subcommand.
- Because parsing uses `Split(' ')`, it does not attempt to handle quoting or more advanced tokenization.
- The script does not complete option values, config file paths, shell names, or dynamically discovered data.
- There is no existence check for `oh-my-posh` / `oh-my-posh.exe`, so the completer can still be registered even if the executable is not installed.