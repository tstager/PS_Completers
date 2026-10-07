# qwen_completer

PowerShell argument completer for the **Qwen Code CLI** (`qwen` / `qwen.cmd` / `qwen.ps1`).

## Installation

Dot-source the script from your PowerShell profile:

```powershell
. 'C:\path\to\Completers\qwen_completer\qwen_completer.ps1'
```

Or load it for the current session only:

```powershell
. .\qwen_completer\qwen_completer.ps1
```

## Registration

The completer registers a **native** `Register-ArgumentCompleter` for all three
invocation forms that the npm-installed Qwen Code CLI may appear as:

| Registered name | Rationale |
| --- | --- |
| `qwen`      | Bare command; resolves to `qwen.ps1` in the npm global bin path under PowerShell |
| `qwen.cmd`  | Windows CMD shim created by npm; used by older shells and some launchers |
| `qwen.ps1`  | Explicit PowerShell-script form when the user types the extension |

All three share the same completer scriptblock.

## Coverage

### Top-level commands

`mcp` · `extensions` · `hooks` · `hook` · `channel`

`auth` is not offered: upstream replaced it with a stub that only prints
"qwen auth has been removed." (configure providers with `/auth` instead).

### Level-2 subcommands

| Command | Subcommands |
| --- | --- |
| `mcp`        | `add` · `remove` · `list` · `reconnect` |
| `extensions` | `install` · `uninstall` · `list` · `update` · `disable` · `enable` · `link` · `new` · `settings` |
| `channel`    | `start` · `stop` · `status` · `pairing` · `configure-weixin` |
| `hooks` / `hook` | *(no subcommands; see quirks)* |

### Level-3 subcommands

| Path | Subcommands |
| --- | --- |
| `extensions settings` | `set` · `list` |
| `channel pairing`     | `list` · `approve` |

### Global flags (selected)

All non-hidden options from upstream `TOP_LEVEL_GLOBAL_OPTIONS` and
`DEFAULT_COMMAND_OPTIONS` (QwenLM/qwen-code `packages/cli/src/config/top-level-options.ts`)
are included, plus `--help`, `--version` and the `--add-dir` alias.  Enum choices:

| Flag | Choices |
| --- | --- |
| `--approval-mode` | `plan` · `default` · `auto` · `auto-edit` · `yolo` |
| `--auth-type` | `openai` · `openai-responses` · `anthropic` · `qwen-oauth` · `gemini` · `vertex-ai` |
| `--channel` | `VSCode` · `ACP` · `SDK` · `CI` · `desktop` · `daemon` |
| `--sandbox` / `-s` | `true` · `false` · `docker` · `podman` · `sandbox-exec` *(a string option since 2026-10; yargs takes the next word as its value unless it starts with `-`; declared by the default command only, so it is neither offered nor read as `--sandbox` after a subcommand such as `extensions install`)* |
| `--input-format` | `text` · `stream-json` |
| `--output-format` / `-o` | `text` · `json` · `stream-json` |
| `--telemetry-target` | `local` · `gcp` |
| `--telemetry-otlp-protocol` | `grpc` · `http` |

`--web-search-default`, `--tavily-api-key`, `--google-api-key`,
`--google-search-engine-id` and `--checkpointing` no longer exist upstream and
are not offered.

### Context-specific flags

| Context | Extra flags |
| --- | --- |
| `mcp add` | `--scope` (user\|project) · `--transport` (stdio\|sse\|http) · `--env` · `--header` · `--timeout` · `--trust` · `--description` · `--include-tools` · `--exclude-tools` · `--oauth-client-id` · `--oauth-client-secret` · `--oauth-redirect-uri` · `--oauth-authorization-url` · `--oauth-token-url` · `--oauth-scopes` |
| `mcp reconnect` | `--all` |
| `extensions install` | `--ref` · `--auto-update` · `--pre-release` · `--registry` · `--consent` · `--scope` (user\|project\|workspace) |
| `extensions update` | `--all` |
| `extensions disable` | `--scope` *(free-form string, default "User")* |
| `extensions enable` | `--scope` *(free-form string)* |
| `extensions settings set` | `--scope` (user\|workspace) |

### Value slot completion

| Slot type | Behaviour |
| --- | --- |
| Enum flags | Offers the known choices |
| Path flags (`--telemetry-outfile` · `--mcp-config` · `--json-file` · `--input-file`) | `CompleteFilename` |
| Dir flags (`--openai-logging-dir` · `--include-directories` · `--add-dir`) | `CompleteFilename` (file system, user filters) |
| Number flags (`--max-session-turns` · `--json-fd` · `--max-tool-calls` · `--max-subagent-depth`) | `<n>` placeholder to suppress filesystem fallback |
| A word starting with `-` after a value flag | Completed as a flag, matching yargs (only a negative number is taken as a value) |
| String / array flags | `<value>` placeholder to suppress filesystem fallback |

### Positional completion

| Context | Positional behaviour |
| --- | --- |
| `extensions link <path>` | First positional → `CompleteFilename` |
| `extensions new <path>` | First positional → `CompleteFilename`; second positional → `<template>` |
| `extensions install <source>` | First positional → `CompleteFilename` plus `<source>` placeholder (also accepts URLs/package names) |
| `mcp add <name> <commandOrUrl> [args...]` | Positional placeholders: `<name>` · `<commandOrUrl>` · `<arg>` |
| `mcp remove <name>` / `mcp reconnect [server-name]` | Positional placeholders |
| `extensions uninstall|update|disable|enable <name>` | Positional placeholders |
| `extensions settings set <name> <setting>` / `list <name>` | Positional placeholders |
| `channel start [name]` / `channel pairing list <name>` / `approve <name> <code>` | Positional placeholders |
| `channel configure-weixin [action]` | First positional → `clear` |

## Inline `--flag=value` syntax

All enum and path flags support the `--flag=value` inline syntax.  Typing
`qwen --approval-mode=` followed by Tab offers `plan`, `default`, `auto`, `auto-edit`, `yolo`.

## Known runtime quirks

### `hooks --help` returns blank output

`qwen hooks --help` exits 0 but produces no option text on this installation.
The completer does not probe `hooks --help` at completion time; the `hooks`
subcommand is listed with an empty sub-subcommand set.  Global flags are still
offered when the user types `qwen hooks --`.

### `extensions new --help` throws ENOENT

`qwen extensions new --help` raises a Node.js `ENOENT` error because the
examples directory is missing locally.  The completer does not call this help
command at completion time, so it degrades gracefully.  `extensions new`
completions are static.

### Context short aliases

The completer understands the documented context-specific short aliases where
they would otherwise conflict with global aliases:

- `qwen mcp add -s` → `--scope`
- `qwen mcp add -t` → `--transport`
- `qwen mcp add -e` → `--env`
- `qwen mcp add -H` → `--header`
- `qwen mcp reconnect -a` → `--all`
- `qwen extensions install|update|disable|enable -s` → no meaning (the extensions builders declare no `-s`), so it is not taken as `--sandbox` and its next word completes as a positional

## Implementation style

- **Self-contained** single `.ps1` file; no external dependencies.
- **`Set-StrictMode -Version Latest`** throughout.
- **Idempotent**: re-registration replaces the same completer, so the script is
  safe to dot-source multiple times.
- **Static data** for all flags and subcommands (no runtime help parsing).
  This avoids latency on every keystroke and is resilient to broken help
  commands (`extensions new`, `hooks`).
- **Three command levels** tracked in the state machine (`$sub`, `$subsub`,
  `$sub3`), covering the deepest paths in the CLI tree.
- **Engine word and cursor**: the word under the cursor is the engine's
  `$wordToComplete`, and only the command elements that end before the cursor
  are treated as committed, so Tab in an empty slot in the middle of a line, or
  on a command that follows another statement, completes that slot.

## Validation

```powershell
# Load the completer
. .\qwen_completer\qwen_completer.ps1

# Root switches
(TabExpansion2 'qwen --' 8).CompletionMatches.CompletionText | Select-Object -First 5

# Enum value: --approval-mode
(TabExpansion2 'qwen --approval-mode ' 20).CompletionMatches.CompletionText

# Enum value: --sandbox (a string option, not a switch)
(TabExpansion2 'qwen --sandbox ' 15).CompletionMatches.CompletionText

# Nested: channel pairing subcommands
(TabExpansion2 'qwen channel pairing ' 22).CompletionMatches.CompletionText

# Nested: extensions settings subcommands
(TabExpansion2 'qwen extensions settings ' 26).CompletionMatches.CompletionText

# Terminal command with no child subcommands
(TabExpansion2 'qwen hooks ' 11).CompletionMatches | Select-Object -First 5 CompletionText, ResultType

# Nested: extensions settings set --scope values
(TabExpansion2 'qwen extensions settings set --scope ' 38).CompletionMatches.CompletionText

# Context flag: mcp add --scope values
(TabExpansion2 'qwen mcp add --scope ' 21).CompletionMatches.CompletionText

# Context short alias value completion
(TabExpansion2 'qwen mcp add -s ' 17).CompletionMatches.CompletionText

# qwen.cmd registration
(TabExpansion2 'qwen.cmd --approval-mode ' 25).CompletionMatches.CompletionText

# Path flag value
(TabExpansion2 'qwen --telemetry-outfile ' 25).CompletionMatches | Select-Object CompletionText, ResultType
```
