# claude_completer

PowerShell argument completer for the **Claude Code CLI** (`claude` / `claude.exe`).

## Installation

Dot-source the script from your PowerShell profile:

```powershell
. 'C:\path\to\Completers\claude_completer\claude_completer.ps1'
```

Or load it for the current session only:

```powershell
. .\claude_completer\claude_completer.ps1
```

## Registration

The completer registers a **native** `Register-ArgumentCompleter` for both
invocation forms that Claude Code resolves to on Windows:

| Registered name | Rationale |
| --- | --- |
| `claude`     | Bare command; resolves through the Windows app-execution alias |
| `claude.exe` | Explicit executable name used by some launchers and shells |

Both names share the same completer scriptblock.

## Coverage

### Top-level commands

`agents` · `auth` · `auto-mode` · `doctor` · `install` · `mcp` · `plugin` · `project` · `setup-token` · `ultrareview` · `update`

Command aliases are normalised when routing context:

| Alias | Canonical |
| --- | --- |
| `plugins`    | `plugin` |
| `upgrade`    | `update` |
| `plugin i`   | `plugin install` |
| `plugin remove` | `plugin uninstall` |
| `plugin autoremove` | `plugin prune` |
| `plugin marketplace rm` | `plugin marketplace remove` |

### Level-2 subcommands

| Command | Subcommands |
| --- | --- |
| `auth`      | `login` · `logout` · `status` · `help` |
| `auto-mode` | `config` · `critique` · `defaults` · `help` |
| `mcp`       | `add` · `add-json` · `add-from-claude-desktop` · `get` · `list` · `remove` · `reset-project-choices` · `serve` · `help` |
| `plugin`    | `details` · `disable` · `enable` · `install` · `list` · `marketplace` · `prune` · `tag` · `uninstall` · `update` · `help` |
| `project`   | `purge` · `help` |
| `agents` / `doctor` / `install` / `setup-token` / `ultrareview` / `update` | *(no L2 subcommands; own options/positionals)* |

### Level-3 subcommands

| Path | Subcommands |
| --- | --- |
| `plugin marketplace` | `add` · `list` · `remove` · `update` · `help` |

### Global flags

All global flags from the CLI surface are included, categorised by type:

| Type | Flags |
| --- | --- |
| Enum | `--effort` (low\|medium\|high\|xhigh\|max) · `--permission-mode` (acceptEdits\|auto\|bypassPermissions\|default\|dontAsk\|plan) · `--output-format` (text\|json\|stream-json) · `--input-format` (text\|stream-json) · `--prompt-suggestions` (true\|false\|1\|0\|yes\|no\|on\|off) |
| Boolean | `--allow-dangerously-skip-permissions` · `--bare` · `--brief` · `--chrome` · `--continue` (`-c`) · `--dangerously-skip-permissions` · `--disable-slash-commands` · `--exclude-dynamic-system-prompt-sections` · `--fork-session` · `--help` (`-h`) · `--ide` · `--include-hook-events` · `--include-partial-messages` · `--mcp-debug` · `--no-chrome` · `--no-session-persistence` · `--print` (`-p`) · `--replay-user-messages` · `--strict-mcp-config` · `--tmux` · `--verbose` · `--version` (`-v`) |
| Optional-value | `--debug` (`-d`) · `--resume` (`-r`) · `--worktree` (`-w`) · `--remote-control` · `--from-pr` · `--prompt-suggestions` |
| String | `--agent` · `--agents` · `--append-system-prompt` · `--fallback-model` · `--json-schema` · `--name` (`-n`) · `--remote-control-session-name-prefix` · `--session-id` · `--system-prompt` · `--model` |
| Number | `--max-budget-usd` |
| Array | `--add-dir` · `--allowedTools` / `--allowed-tools` · `--betas` · `--disallowedTools` / `--disallowed-tools` · `--file` · `--mcp-config` · `--plugin-dir` · `--plugin-url` · `--setting-sources` · `--settings` · `--tools` |
| Path/dir | `--add-dir` (dir) · `--plugin-dir` (dir) · `--debug-file` (file) · `--mcp-config` (file) · `--settings` (file) |

### Global short aliases

`-c`=`--continue` · `-d`=`--debug` · `-h`=`--help` · `-n`=`--name` · `-p`=`--print` · `-r`=`--resume` · `-v`=`--version` · `-w`=`--worktree`

### Context-specific flags

| Context | Extra flags |
| --- | --- |
| `agents` | `--add-dir` · `--allow-dangerously-skip-permissions` · `--cwd` · `--dangerously-skip-permissions` · `--effort` · `--json` · `--mcp-config` · `--model` · `--permission-mode` · `--plugin-dir` · `--setting-sources` · `--settings` |
| `auth login` | `--claudeai` · `--console` · `--email` · `--sso` |
| `auth status` | `--json` · `--text` |
| `auto-mode critique` | `--model` |
| `mcp add` | `--callback-port` · `--client-id` · `--client-secret` · `--env` (`-e`) · `--header` (`-H`) · `--scope` (`-s`, local\|user\|project) · `--transport` (`-t`, stdio\|sse\|http) |
| `mcp add-json` | `--client-secret` · `--scope` (`-s`) |
| `mcp add-from-claude-desktop` | `--scope` (`-s`) |
| `mcp remove` | `--scope` (`-s`) |
| `mcp serve` | `--debug` (`-d`) · `--verbose` |
| `install` | `--force` |
| `plugin disable` | `--all` (`-a`) · `--scope` (`-s`, user\|project\|local) |
| `plugin enable` | `--scope` (`-s`) |
| `plugin install` | `--config` · `--scope` (`-s`) |
| `plugin list` | `--available` · `--json` |
| `plugin prune` | `--dry-run` · `--scope` (`-s`) · `--yes` (`-y`) |
| `plugin tag` | `--dry-run` · `--force` (`-f`) · `--message` (`-m`) · `--push` · `--remote` |
| `plugin validate` | `--strict` |
| `project purge` | `--all` · `--dry-run` · `--interactive` (`-i`) · `--yes` (`-y`) |
| `ultrareview` | `--json` · `--timeout` |

### Value slot completion

| Slot type | Behaviour |
| --- | --- |
| Enum flags | Offers the known choices |
| `--model` | Offers model hints (`opus`, `sonnet`, `haiku`, `claude-opus-4-8`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`); free-form otherwise |
| `--setting-sources` | Offers `user`, `project`, `local`; comma-separated, free-form |
| Path flags (`--debug-file` · `--mcp-config` · `--settings`) | `CompleteFilename` |
| Dir flags (`--add-dir` · `--plugin-dir`) | `CompleteFilename` |
| Number flags (`--max-budget-usd` · `--callback-port` · `--timeout`) | `<n>` placeholder to suppress filesystem fallback |
| String / array flags | `<value>` placeholder to suppress filesystem fallback |

### Positional completion

| Context | Positional behaviour |
| --- | --- |
| `install [target]` | `stable` · `latest` enum plus `<target>` placeholder |
| `ultrareview [target]` | `<target>` placeholder (PR number / base branch) |
| `mcp add <name> <commandOrUrl> [args...]` | `<name>` · `<commandOrUrl>` · `<arg>` placeholders |
| `mcp add-json <name> <json>` | `<name>` · `<json>` placeholders |
| `mcp get` / `mcp remove <name>` | `<name>` placeholder |
| `plugin details/disable/enable/install/uninstall/update <plugin>` | `<plugin>` / `<name>` placeholder |
| `plugin tag [path]` / `plugin validate <path>` / `project purge [path]` | First positional → `CompleteFilename` |
| `plugin marketplace add <source>` | `<source>` placeholder |
| `plugin marketplace remove/update <name>` | `<name>` placeholder |

## Inline `--flag=value` syntax

All enum, model, hint, and path/dir flags support the `--flag=value` inline
syntax.  Typing `claude --effort=` followed by Tab offers `low`, `medium`,
`high`, `xhigh`, `max`.

## Design decisions

### Optional-value flags

`--debug`, `--resume`, `--worktree`, `--remote-control`, `--from-pr`, and
`--prompt-suggestions` accept an *optional* value.  The completer treats them
conservatively: they **never consume the next token** as a value, so a trailing
`claude --debug ` still routes to subcommand/positional completion rather than
swallowing the next word.  Their values are only offered through the explicit
inline form (`--prompt-suggestions=` offers the enum).  This avoids breaking
positional and subcommand routing after an optional-value flag.

### Both `claude` and `claude.exe`

Claude Code on Windows resolves through an app-execution alias, and some shells
or launchers invoke the explicit `claude.exe`.  Both names are registered with
the same scriptblock so completion works regardless of how the command is typed.

## Implementation style

- **Self-contained** single `.ps1` file; no external dependencies.
- **`Set-StrictMode -Version Latest`** throughout.
- **Idempotent** via a `$script:ClaudeCompleterRegistered` guard; safe to
  dot-source multiple times.
- **Static data** for all flags and subcommands (no runtime help parsing and no
  invocation of `claude` at completion time).  This avoids latency on every
  keystroke and is side-effect free.
- **Three command levels** tracked in the state machine (`$sub`, `$subsub`,
  `$sub3`), with alias normalisation as commands are matched.
- **Native convention detection** preserves compatibility with both the
  ReadLine `CompleteInput` path and the `TabExpansion2` path, so real runtime
  tab completion engages.

## Validation

```powershell
. .\claude_completer\claude_completer.ps1

# Top-level subcommands
(TabExpansion2 'claude ' 7).CompletionMatches.CompletionText

# Global flags
(TabExpansion2 'claude --' 9).CompletionMatches.CompletionText | Select-Object -First 5

# Enum value: --effort
(TabExpansion2 'claude --effort ' 16).CompletionMatches.CompletionText

# Enum value: --permission-mode
(TabExpansion2 'claude --permission-mode ' 25).CompletionMatches.CompletionText

# mcp subcommands and scope/transport enums
(TabExpansion2 'claude mcp ' 11).CompletionMatches.CompletionText
(TabExpansion2 'claude mcp add --scope ' 23).CompletionMatches.CompletionText
(TabExpansion2 'claude mcp add -t ' 18).CompletionMatches.CompletionText

# plugin tree and marketplace L3
(TabExpansion2 'claude plugin ' 14).CompletionMatches.CompletionText
(TabExpansion2 'claude plugin marketplace ' 26).CompletionMatches.CompletionText

# Path/dir flag value
(TabExpansion2 'claude --add-dir ' 17).CompletionMatches | Select-Object CompletionText, ResultType

# claude.exe registration
(TabExpansion2 'claude.exe ' 11).CompletionMatches.CompletionText
```
