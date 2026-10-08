# pi completer

## What it completes / overview

`pi_completer.ps1` registers a native PowerShell argument completer for:

- `pi`
- `pi.cmd`
- `pi.ps1`

The implementation is a **hybrid, static-first** completer:

- it keeps static fallback metadata for the stable command grammar
- it lazily refreshes safe help-driven surfaces from local `pi --help` output
- it adds local dynamic values for providers and model ids from `models-store.json` and `models.json` / `models.jsonc`, led by the `defaultModel` from settings
- it adds installed-package sources from the `packages` array of the global and project `settings.json` (no process is started)
- it adds MCP server names from the global and project `mcp.json` for `pi mcp remove|login|logout`
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

- root commands: `install`, `remove`, `uninstall`, `update`, `list`, `config`, `auth` (with `print-api-key`, `print-bearer-token`, `check` and their `--provider`, `--model`, `--min-expiry`, `--json`, `--credentials`, `--no-refresh` flags), `mcp`
- the `pi mcp` tree, taken from pi 1.0.4's `pi mcp --help` and its option parser. `pi mcp` accepts no option before the sub-command (only `--help`/`-h`), and each sub-command has its own options:
  - `add <server>`: `-l`/`--local`, `--url`, `--env`, `--cwd` (directories), `--header`, `--bearer-token-env-var`, `--oauth-client-id`, `--oauth-client-secret`, `--oauth-callback-port`, `--oauth-client-name`, `--exposure` (`codemode`, `deferred`, `direct`, `hidden`), `--description`. Once the server name and a command word are typed, or after `--`, the rest belongs to the server command and nothing is offered
  - `remove <server>`: `-l`/`--local`
  - `list`: `--json`
  - `login <server>`: `--timeout <seconds>`
  - `logout <server>`
  - pi's mcp parser has no `--option=value` form, so attached values are not offered there
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
  - `--thinking` -> `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`
  - `--tui-mode` -> `regular`, `fullscreen`
  - `--provider` -> the 39 built-in provider ids of pi 0.85, plus every provider key found in `~/.pi/agent/models-store.json` and custom `models.json` providers
  - `--tools` -> `read`, `bash`, `edit`, `write`, `grep`, `find`, `ls`

### 2. Lazy help-driven refresh

On demand, the completer safely probes only these local help surfaces:

- `pi --help`
- `pi install --help`
- `pi remove --help`
- `pi uninstall --help`
- `pi update --help`
- `pi list --help`

Those results are cached for 15 minutes and merged over the static fallback metadata. The cache is dropped early when pi is upgraded or its packages change: the key is the write time of `<agent dir>/install/current-version`, `<agent dir>/settings.json` and the resolved shim. Captures go through `pi.cmd` (or a `pi` application) in preference to `pi.ps1`, which would add a pwsh start-up to each one, and are killed after 5 seconds. `pi --help` itself loads every installed extension to list their flags, so the first Tab in a session still waits for it (about 2-3 s on an idle machine). That keeps the script import-safe while allowing the completer to pick up:

- root global flags and aliases such as `--no-builtin-tools` / `-nbt`, `--tools` / `-t`, and `--no-context-files` / `-nc`
- extension CLI flags exposed in root help, such as `--plan` and `--mcp-config`
- new root commands that the static table does not know yet (they get a `--help` option and no positionals)
- enumerations stated inside option descriptions (`Set thinking level: ...`, `Output mode: ...`, `TUI mode: ...`), which refresh the `--thinking`, `--mode` and `--tui-mode` value sets
- value-bearing options whose placeholder is not modelled explicitly; they complete their `<placeholder>` text instead of being mistaken for boolean switches
- current safe subcommand options from the package-management help paths

If help parsing fails, completion falls back to the static metadata.

### 3. Local dynamic values

The completer augments the static surface with safe local discovery:

- `Update-PiCustomModelData` reads `models.json` / `models.jsonc` (JSONC with comments and trailing commas) and `models-store.json`, adding provider names plus every `models[].id` as `id` and `provider/id`; the `defaultModel` (and `defaultProvider/defaultModel`) from the global or project `settings.json` comes first
- `Get-PiKnownResourcePaths` discovers extension, skill, prompt-template, and theme paths in:
  - `~/.pi/agent/...`
  - `.pi/...`
- `Get-PiInstalledPackageSources` reads the `packages` entries (strings or `{ "source": ... }` objects) of the global and project `settings.json`, including local-path packages, for `remove`, `uninstall`, `update`, and `pi update --extension`
- `Get-PiMcpServerName` reads only the `mcpServers` key names of the global and project `mcp.json`; server configurations (headers, secrets) are never emitted

All of these files go through `Read-PiJsonFile`, which accepts comments and trailing commas, reads keys case-sensitively as pi does, and validates with `Test-Json` before `ConvertFrom-Json -AsHashtable`, so a malformed or empty file contributes nothing and adds no record to `$Error`.

The agent directory honours `PI_CODING_AGENT_DIR`. Installed package sources, MCP server names, theme names, session files, and file paths that contain spaces or PowerShell metacharacters are quoted, keeping the quote the user typed (ASCII or typographic, also after `--flag=`); single quotes are the default.

These discoveries are cached with short TTLs, keyed on the current directory where a project file takes part, so completion stays responsive.

### 4. Context-aware parsing

`Complete-Pi` tracks whether the user is in:

- root interactive mode (`pi [options] [@files...] [messages...]`)
- a package-management subcommand
- message tail mode after free-form prompt text starts
- an option value slot
- everything after a bare `--`, which is treated as messages/`@files`
- the token under the cursor when editing mid-line (`$cursorPosition` trims the command at the cursor, so `pi --provider ope|nai --model x` completes providers)
- comma-separated lists such as `--tools read,b`, which PowerShell parses as array literals; the raw extent text is used so `read,bash` is offered
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
- Root `@file` completion keeps the `@` inside the quotes (`'@.\a b.txt'`), since `@'` would open a here-string. A bare `@` does not parse, so `@.\a b` reaches the completer as a stranded `@` plus the path; those completions are `('@.\a b.txt')`, which turns the stranded `@` into `@(...)` and still passes one `@path` argument. The root hint is the placeholder `@<file>`.
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
  - `pi mcp `
  - `pi mcp add x -`
  - `pi mcp add x --exposure `
  - `pi mcp remove `
  - `pi --model gpt`
  - `pi.cmd --mode `
  - `pi.ps1 --mode `
