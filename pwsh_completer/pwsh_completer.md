# pwsh completer

## Overview

`pwsh_completer.ps1` registers native PowerShell argument completion for:

- `pwsh`
- `pwsh.exe`

The completer is static-first because `pwsh.exe --help` publishes a stable command-line parameter surface. It avoids top-level setup work so `CompleterActions` can import it safely.

## Reference

The command surface comes from local `pwsh.exe --help`.

Covered parameters include:

- Startup and host switches such as `-NoProfile`, `-NoLogo`, `-NoExit`, `-NonInteractive`, `-STA`, and `-MTA`
- Terminal command parameters: `-File`, `-Command`, and `-CommandWithArgs`
- Path-bearing parameters: `-File`, `-ConfigurationFile`, `-SettingsFile`, and `-WorkingDirectory`
- Enum-like values for `-ExecutionPolicy`, `-InputFormat`, `-OutputFormat`, and `-WindowStyle`
- Help aliases: `-Help`, `-h`, `-?`, and `/?`

## Completion Behavior

- Every parameter is also offered in its double-dash spelling (`pwsh --nop<Tab>` -> `--NoProfile`), which pwsh accepts.
- `pwsh <Tab>` on an empty word offers the options plus the `.ps1` scripts and directories in the current directory, because `-File` is pwsh's default parameter.
- `-File`, `-ConfigurationFile`, and `-SettingsFile` complete directories plus files with the matching extension (`.ps1`, `.pssc`, `.json`); `-WorkingDirectory` completes directories only.
- `-Command` and `-CommandWithArgs` complete real command names from the current session (`[CompletionCompleters]::CompleteCommand`), plus `-` and `& { <script> }` as the documented stdin and script-block forms.
- Values are completed in the separate (`-ExecutionPolicy By`), attached `=` (`-ExecutionPolicy=By`) and attached `:` (`-ExecutionPolicy:By`) forms; the `=` form keeps the `-Option=` prefix on every suggestion.
- `-ExecutionPolicy` completes `Restricted`, `AllSigned`, `RemoteSigned`, `Unrestricted`, `Bypass`, `Undefined`, and `Default`.
- `-InputFormat` and `-OutputFormat` complete `Text` and `XML`.
- After `-File <path>`, remaining values are treated as script arguments and use placeholders rather than guessing script-specific parameters.

## Import Compatibility

The script top level is limited to:

- `Set-StrictMode`
- an importer-safe declaration block containing helper functions
- one literal `Register-ArgumentCompleter -Native` call

No help parsing, external process invocation, or cache initialization runs at import time.
