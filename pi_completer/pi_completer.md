# pi completer

## What it completes / overview

`pi_completer.ps1` registers a native PowerShell argument completer for:

- `pi`
- `pi.cmd`
- `pi.ps1`

The implementation is a **hybrid, static-first** completer:

- it keeps static fallback metadata for the stable command grammar
- it lazily refreshes safe help-driven surfaces from local `pi --help` output
- it adds local dynamic values for custom providers and models from local `models.json` / `models.jsonc`
- it adds installed-package source suggestions from `pi list` when that local call succeeds
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

### 1. Static fallback metadata

`Get-PiCompletionCache` lazily initializes:

- root commands: `install`, `remove`, `uninstall`, `update`, `list`, `config`
- global options such as `--provider`, `--model`, `--tools`, `--thinking`, `--session`, and `--export`
- subcommand-specific options such as `-l` / `--local` for `install`, `remove`, and `uninstall`
- the current static fallback for `update`:
  - positional target `source | self | pi`
  - `--self`
  - `--extensions`
  - `--extension <source>`
  - `--force`
- built-in enums for:
  - `--mode` -> `text`, `json`, `rpc`
  - `--thinking` -> `off`, `minimal`, `low`, `medium`, `high`, `xhigh`
  - `--tools` -> `read`, `bash`, `edit`, `write`, `grep`, `find`, `ls`

### 2. Lazy help-driven refresh

On demand, the completer safely probes only these local help surfaces:

- `pi --help`
- `pi install --help`
- `pi remove --help`
- `pi uninstall --help`
- `pi update --help`
- `pi list --help`

Those results are cached with short TTLs and merged over the static fallback metadata. That keeps the script import-safe while allowing the completer to pick up:

- root global flags and aliases such as `--no-builtin-tools` / `-nbt`, `--tools` / `-t`, and `--no-context-files` / `-nc`
- extension CLI flags exposed in root help, such as `--plan` and `--mcp-config`
- current safe subcommand options from the package-management help paths

If help parsing fails, completion falls back to the static metadata.

### 3. Local dynamic values

The completer augments the static surface with safe local discovery:

- `Update-PiCustomModelData` reads `models.json` / `models.jsonc`, parses JSONC locally with comment + trailing-comma support, and adds custom provider names and model IDs
- `Get-PiKnownResourcePaths` discovers extension, skill, prompt-template, and theme paths in:
  - `~/.pi/agent/...`
  - `.pi/...`
- `Get-PiInstalledPackageSources` parses `pi list` output for installed package sources used by `remove`, `uninstall`, `update`, and `pi update --extension`

These discoveries are cached with short TTLs so completion stays responsive.

### 4. Context-aware parsing

`Complete-Pi` tracks whether the user is in:

- root interactive mode (`pi [options] [@files...] [messages...]`)
- a package-management subcommand
- message tail mode after free-form prompt text starts
- an option value slot
- an inline `--flag=value` value slot
- `--export` output-path mode after the input session file was already supplied, including `--export=<session.jsonl>` inline input
- `pi update` target-selection mode so `--self` / `--extensions` / `--extension <source>` suppress incompatible positional target suggestions

That keeps the completer from offering unrelated command names or flags in the wrong place.

### 5. Path and placeholder behavior

Path completion is provided for:

- `--session`
- `--session-dir`
- `--fork` when it looks like a path
- `--extension`, `-e`
- `--skill`
- `--prompt-template`
- `--theme`
- `--mcp-config`
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
- Root help may include extension-registered CLI flags. Those are parsed lazily from `pi --help`, but only when the local help output is available and parseable.
- Root `@file` completion preserves the `@` prefix in the returned completions.
- Export output-path completion keeps working after both spaced and inline `--export` input forms, including `output.html` prefix matching.

## Validation expectations

Representative validation for this script should include:

- `Import-CompleterScript` against the repo copy of `CompleterActions`
- clean-session `pwsh -NoProfile` load
- `TabExpansion2` for:
  - `pi `
  - `pi --no-b`
  - `pi --pl`
  - `pi --plan `
  - `pi --mcp-config `
  - `pi --export=`
  - `pi --export=foo.jsonl `
  - `pi update `
  - `pi update --`
  - `pi update --self `
  - `pi update self `
  - `pi update --extension `
  - `pi install --`
  - `pi install `
  - `pi remove `
  - `pi config `
  - `pi.cmd --mode `
  - `pi.ps1 --mode `
