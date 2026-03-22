# gh CLI completer

## What it completes / overview
`gh_cli_completer.ps1` does not implement custom completion logic for GitHub CLI itself. Instead, it loads the official PowerShell completion script emitted by the installed `gh` executable.

This makes the repository's `gh` completer a thin wrapper whose main job is to validate that `gh` exists, request its native completion script, and evaluate that script in the current session.

## Registration and command names
This file does not call `Register-ArgumentCompleter` directly.

Instead it runs:

```powershell
$completionScript = & $ghCommand.Source completion -s powershell | Out-String
Invoke-Expression $completionScript
```

The command name registration is therefore whatever the upstream `gh completion -s powershell` script defines. In practice, this script is intended to enable completion for `gh`.

## How completion works
The file is a wrapper around the GitHub CLI's built-in completion support.

Execution flow:
1. `Set-StrictMode -Version Latest` is enabled.
2. `Get-Command -Name gh -ErrorAction Stop` resolves the executable.
3. The script runs `gh completion -s powershell` using the resolved command source path.
4. It verifies that the returned script text is not empty.
5. It executes the returned script with `Invoke-Expression`.

There is no repository-local parsing of command lines, flags, or subcommands here. All actual completion behavior is delegated to the installed GitHub CLI.

## Key completion behaviors / supported values
Because behavior comes from the upstream GitHub CLI, this repository file does not define subcommands or values directly.

What this script does guarantee from its own implementation:
- it targets PowerShell completion output via `completion -s powershell`
- it only attempts to load completions when `gh` can be resolved from `PATH`
- it reports an error if `gh` is missing
- it reports an error if `gh` returns an empty completion script
- it reports an error if loading the completion script throws

## Dependencies or external command expectations
- Requires `gh` to be installed and available in `PATH`
- Requires the installed GitHub CLI to support `gh completion -s powershell`
- Trusts the script emitted by the installed `gh` executable

The wrapper uses `$ghCommand.Source`, so it executes the resolved command path rather than assuming a bare `gh` command name.

## Usage / loading example
```powershell
. "$PSScriptRoot\gh_cli_completer.ps1"

# After loading, use gh and rely on its official PowerShell completer
# gh <TAB>
# gh repo <TAB>
# gh pr <TAB>
```

## Limitations / notes
- This file is only a loader; it does not add repository-specific fallback completions.
- Completion coverage changes with the installed GitHub CLI version because the upstream script is generated at load time.
- The script must be run or dot-sourced in each PowerShell session where completion should be available.
- `Invoke-Expression` is used intentionally because `gh` returns PowerShell code, so the wrapper trusts the local `gh` installation.
- If `gh` is unavailable or returns empty output, no completer is loaded.
