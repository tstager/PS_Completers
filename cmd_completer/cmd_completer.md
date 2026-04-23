# cmd completer

## Overview

`cmd_completer.ps1` registers native PowerShell argument completion for:

- `cmd`
- `cmd.exe`

The completer is static-first because `cmd.exe /?` exposes a small, stable command-line surface. It does not call external tools at import time.

## Reference

The command surface comes from local `cmd.exe /?`.

Covered switches include:

- `/A`, `/U`, `/Q`, `/D`, and `/S`
- `/C`, `/K`, and compatibility alias `/R`
- `/X` and `/Y`
- `/E:ON`, `/E:OFF`
- `/F:ON`, `/F:OFF`
- `/V:ON`, `/V:OFF`
- `/T:fg`
- `/?`

## Completion Behavior

- Root completion suggests documented `cmd.exe` switches.
- `/E:`, `/F:`, and `/V:` complete `ON` and `OFF` as attached values.
- `/T:` completes common foreground/background color pairs.
- After `/C`, `/K`, or `/R`, completion switches to command-string mode and suggests `cmd.exe` internal commands, installed applications, path completions for path-like input, and a `<command>` placeholder.

## Import Compatibility

The script top level is limited to:

- `Set-StrictMode`
- an importer-safe declaration block containing helper functions
- one literal `Register-ArgumentCompleter -Native` call

No help parsing, registry reads, or command discovery runs at import time. Application discovery only happens lazily after `/C`, `/K`, or `/R` when the user is completing a command string.
