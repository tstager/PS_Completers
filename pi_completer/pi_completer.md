# pi completer

## What it completes / overview

`pi_completer.ps1` registers a native PowerShell argument completer for:

- `pi`
- `pi.cmd`
- `pi.ps1`

The implementation is a **hybrid, static-first** completer:

- it hard-codes the stable top-level command and option grammar from `pi --help`
- it adds local dynamic values for custom providers and models from `models.json`
- it adds source-scheme and local-path hints for `install` / `remove` / `uninstall` / `update`
- and it uses path-aware completion for session, export, extension, skill, prompt-template, theme, and `@file` arguments

No completion-time probing depends on `pi config --help`, because that path behaves like an interactive TUI instead of normal help output.

## Registration and command names

The script registers a single importer-safe native completer:

```powershell
Register-ArgumentCompleter -Native -CommandName @('pi', 'pi.cmd', 'pi.ps1') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pi -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

This matches the installed Windows npm shim names for the CLI and avoids assuming a `pi.exe` exists.

## Import-CompleterScript compatibility

The script keeps its top level compatible with `CompleterActions`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter` call

There are no top-level assignments, loops, helper invocations, or external command calls.

## How completion works

### 1. Static command and option metadata

`Get-PiCompletionCache` lazily initializes:

- root commands: `install`, `remove`, `uninstall`, `update`, `list`, `config`
- global options such as `--provider`, `--model`, `--tools`, `--thinking`, `--session`, and `--export`
- subcommand-specific options such as `-l` / `--local` for `install`, `remove`, and `uninstall`
- built-in enums for:
  - `--mode` -> `text`, `json`, `rpc`
  - `--thinking` -> `off`, `minimal`, `low`, `medium`, `high`, `xhigh`
  - `--tools` -> `read`, `bash`, `edit`, `write`, `grep`, `find`, `ls`

### 2. Local dynamic values

The completer augments the static surface with safe local discovery:

- `Update-PiCustomModelData` reads `models.json` and adds custom provider names and model IDs
- `Get-PiKnownResourcePaths` discovers extension, skill, prompt-template, and theme paths in:
  - `~/.pi/agent/...`
  - `.pi/...`

These discoveries are cached with short TTLs so completion stays responsive.

### 3. Context-aware parsing

`Complete-Pi` tracks whether the user is in:

- root interactive mode (`pi [options] [@files...] [messages...]`)
- a package-management subcommand
- message tail mode after free-form prompt text starts
- an option value slot
- an inline `--flag=value` value slot
- `--export` output-path mode after the input session file was already supplied

That keeps the completer from offering unrelated command names or flags in the wrong place.

### 4. Path and placeholder behavior

Path completion is provided for:

- `--session`
- `--session-dir`
- `--fork` when it looks like a path
- `--extension`, `-e`
- `--skill`
- `--prompt-template`
- `--theme`
- `--export`
- `@file` root arguments
- local-path package sources such as `.\` or `C:\...`

Placeholder-only slots suppress noisy filesystem fallback for:

- `--api-key`
- `--system-prompt`
- `--append-system-prompt`
- `--model`
- `--models`
- `--list-models`
- non-path package sources
- free-form root messages
- session IDs / partial UUIDs for `--fork` and `--session`

## Notable runtime quirks

- `pi config --help` did not print normal help in clean PowerShell and instead behaved like an interactive TUI path, so the completer treats `config` as a command with no deeper help-driven probing.
- Root `@file` completion preserves the `@` prefix in the returned completions.

## Validation expectations

Representative validation for this script should include:

- `Import-CompleterScript` against the repo copy of `CompleterActions`
- clean-session `pwsh -NoProfile` load
- `TabExpansion2` for:
  - `pi `
  - `pi --mode `
  - `pi --thinking `
  - `pi --tools `
  - `pi @`
  - `pi install `
  - `pi install .\`
  - `pi remove `
  - `pi --session `
  - `pi --export `
  - `pi.cmd --mode `
  - `pi.ps1 --mode `
