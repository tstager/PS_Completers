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

- `-File`, `-ConfigurationFile`, `-SettingsFile`, and `-WorkingDirectory` complete filesystem paths.
- `-Command` and `-CommandWithArgs` provide conservative PowerShell command-text suggestions.
- `-ExecutionPolicy` completes `Restricted`, `AllSigned`, `RemoteSigned`, `Unrestricted`, `Bypass`, `Undefined`, and `Default`.
- `-InputFormat` and `-OutputFormat` complete `Text` and `XML`.
- After `-File <path>`, remaining values are treated as script arguments and use placeholders rather than guessing script-specific parameters.

## Import Compatibility

The script top level is limited to:

- `Set-StrictMode`
- an importer-safe declaration block containing helper functions
- one literal `Register-ArgumentCompleter -Native` call

No help parsing, external process invocation, or cache initialization runs at import time.
