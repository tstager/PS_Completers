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
- `/T:` completes the 16 foreground digits from `COLOR /?` with their colour names, then the 16 background/foreground pairs once a digit is typed (`/T:3` offers `/T:3` and `/T:30`..`/T:3F`).
- After `/C`, `/K`, or `/R`, completion switches to command-string mode: the first word suggests `cmd.exe` internal commands (including `CHCP`, `DPATH`, `KEYS`, `MKLINK`), installed applications, path completions for path-like input, and a `<command>` placeholder. A quoted first word (`cmd /c "dir`) is matched without its quote and completed as `"DIR"`.
- Later words in the command string belong to that command: an empty word gets an `<argument>` placeholder, a path-like word gets path completion, and a `/`-word is kept as typed (the inner command's switches are not modelled) instead of being treated as a filesystem root.

## Import Compatibility

The script top level is limited to:

- `Set-StrictMode`
- an importer-safe declaration block containing helper functions
- one literal `Register-ArgumentCompleter -Native` call

No help parsing, registry reads, or command discovery runs at import time. Application discovery only happens lazily after `/C`, `/K`, or `/R` when the user is completing a command string.
