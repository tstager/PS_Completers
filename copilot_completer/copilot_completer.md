# copilot completer

## Overview

`copilot_completer.ps1` registers a standalone native PowerShell completer for `copilot` and `copilot.exe`.

It follows the repository's standalone completer pattern and uses a hybrid design:

- a static command / subcommand / option tree for the stable argv surface
- dynamic runtime providers for model names, marketplace names, and installed plugin names
- directory and file path completion for path-bearing values
- placeholder completions for freeform values so PowerShell does not fall back to unrelated filesystem suggestions

This completer is intentionally limited to CLI argv parsing. It does **not** attempt to complete interactive slash commands inside a Copilot session.

## Registration

- Uses `Set-StrictMode -Version Latest`
- Uses `Register-ArgumentCompleter -Native`
- Registers for `copilot` and `copilot.exe`

```powershell
. "$PSScriptRoot\copilot_completer.ps1"
```

## Static command coverage

Top-level commands (re-derived from `copilot --help` and every nested `--help` of 1.0.92):

- `app`
- `completion <shell>` (`bash`, `zsh`, `fish`)
- `config [key] [value]` (`--list`, `--rm`, `--json`, `--global`, `--repo`, `--local`)
- `help [topic]`
- `init` (`--no-experimental`, `--no-eager-powershell-resolution`)
- `instruction list` (`--json`)
- `login` (`--host`, `--device-code`, `--web-flow`, `--with-token`)
- `lsp list` (`--json`)
- `mcp`
- `memories import <memories.jsonl>` (`--dry-run`, `--output json`, `--on-conflict skip|error`)
- `plugin`
- `sandbox ca` with `create`, `remove`, `rotate`, `status`, `trust [certificate]` (`--allow-host`)
- `sessions import <transcript.jsonl>` (`--dry-run`, `--output json`, `--working-directory`, `--name`)
- `skill`
- `update [channel]` (`stable`, `prerelease`)
- `version`
- `workflow run <name>` (`--args <json|@path>`, `--result-file`, `-s/--silent`, `--output-format`)

Option scoping follows copilot's clap parser: the root options (`--model`, `--allow-all`, `-C`, ...) are only accepted before the first subcommand (`copilot mcp list --model x` fails with "unexpected argument '--model' found"), so after a subcommand only that subcommand's own options are offered. Commands and options are case-sensitive, as in copilot.

An unknown command ends completion; it never falls back to the root command list.

Help topics:

- `billing`
- `commands`
- `config`
- `environment`
- `limits`
- `logging`
- `monitoring`
- `permissions`
- `providers`
- `sandbox`

Plugin tree:

- `plugin disable` / `enable` / `uninstall` (installed plugin name)
- `plugin install <source>`
- `plugin list` (`--json`)
- `plugin update` (`--all`)
- `plugin marketplace add`, `browse` (`--json`), `list` (`--json`), `remove` (`-f/--force`), `update`

Hidden aliases are understood while parsing but not offered: `plugins` (= `plugin`), `plugin add` (= `install`), `plugin remove|rm` (= `uninstall`), `plugin marketplaces` (= `marketplace`), and `plugin marketplace ls|rm|refresh` (= `list|remove|update`). The pre-1.0.92 cross-kind flags (`--kind`, `--scope`, `--mcp`, `--plugin`, `--skill`) were removed from copilot and are no longer offered.

MCP tree:

- `mcp add <name>` (`--env`, `--header`, `--json`, `--show-secrets`, `--timeout`, `--tools`, `--transport` with `stdio`/`http`/`sse`)
- `mcp disable`, `mcp enable`, `mcp get` (`--json`, `--show-secrets`), `mcp list` (`--json`), `mcp remove`

Skill tree:

- `skill add` (`--project`)
- `skill disable`, `skill enable`
- `skill list` (`--json`)
- `skill remove`

## Dynamic value providers

The completer keeps the stable command tree static, but resolves a few high-value dynamic lists from the local CLI:

- `copilot help config`
  - model names for `--model`
- `copilot completion bash`
  - `copilot config` setting keys (the removable keys after `--rm`, by `--repo`/`--local` scope) and per-key values: enum and boolean choices, and file or directory completion for path-valued settings
- `copilot plugin marketplace list`
  - marketplace names for `plugin marketplace browse`, `remove` and `update`
- `copilot plugin list`
  - installed plugin names for `plugin uninstall`, `update`, `enable` and `disable`

Each capture runs with stdin closed and an 8 second timeout (the process is killed on timeout). The script caches those runtime lists briefly to keep repeated completion responsive; when copilot is not installed the slots fall back to placeholders such as `<model>`, `<key>` and `<plugin-name>`.

## Value-aware behavior

Notable value handling:

- `--model`
  - suggests `auto` (let Copilot pick) followed by the models discovered from `copilot help config`
- `--log-level`
  - suggests `none`, `error`, `warning`, `info`, `debug`, `all`, `default`
- `--effort` / `--reasoning-effort`
  - suggests `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`
- `--output-format`
  - suggests `text`, `json`
- `--stream`
  - suggests `on`, `off`
- `--bash-env` and `--mouse`
  - support optional values and suggest `on`, `off`
- `login --host`
  - suggests example host URLs such as `https://github.com` and `https://example.ghe.com`
- `login --device-code`, `--web-flow`, `--with-token`
  - the authentication-mode switches documented by `copilot login --help`
- `--add-dir`, `--log-dir`, `--plugin-dir`, `--extension-sdk-path`, `-C`
  - use directory completion; a value ending in `\` or `/` (and `.`, `..`, `~\`) descends into that directory; a directory with no subdirectories yields the typed value (or a `<directory>` placeholder) rather than PowerShell's file fallback
- `--enable-mcp-server` / `--disable-mcp-server`
  - `<server-name>` placeholder
- `--usage-output-file`
  - file completion
- attached `--option=` on placeholder slots (`--agent=`, `--name=`, `--resume=`, `--allow-tool=` ...)
  - offers `--option=<placeholder>` rather than echoing the flag; a short-flag cluster such as `-sp` falls back to the option list
- `--attachment`
  - uses file completion
- `--mode` (`interactive`, `plan`, `autopilot`), `--context` (`default`, `long_context`) and `--auto-tier` (`efficiency`, `balance`, `intelligence`)
  - closed enum sets
- `--dynamic-retrieval`
  - suggests `skills=on`, `skills=off`
- `--mcp-github-auth`
  - `<server>=<origin>` placeholder
- `config <key> <value>`
  - keys and values from `copilot completion bash` (see above); after `--list` no key is offered, and after `--rm` a value is offered only for list settings
- `--share[=path]`
  - supports inline `=` completion and file / directory path suggestions
- `--additional-mcp-config` and `workflow run --args`
  - supports inline values
  - when the value starts with `@`, path completion is applied after the `@` prefix, and the `@` stays inside the quotes (`'@my file.json'`) so PowerShell does not read it as a splat; PowerShell completes a bare `@name` as a splatted variable itself, so type `'@name` to complete a file after a partial name
- freeform slots such as `--agent`, `--prompt`, tool patterns, URL patterns, counts, and session IDs
  - use placeholders / echo completions rather than unrelated filesystem fallback

## Example scenarios

```powershell
. "$PSScriptRoot\copilot_completer.ps1"

# Root commands and global options
# copilot <TAB>

# Help topics
# copilot help <TAB>

# Nested plugin commands
# copilot plugin <TAB>
# copilot plugin marketplace <TAB>

# Dynamic values
# copilot --model <TAB>
# copilot plugin uninstall <TAB>
# copilot plugin marketplace browse <TAB>
# copilot config <TAB>
# copilot config theme <TAB>

# Path-aware values
# copilot --add-dir <TAB>
# copilot --share=<TAB>
# copilot --additional-mcp-config @<TAB>
```

## Notes and limitations

- The command / option tree is intentionally static so completion stays fast and predictable even if help text formatting changes.
- Dynamic discovery is only used for values that are both useful and cheap to query locally.
- Root options are offered only before the first subcommand, because copilot rejects them after one.
- Tokens are selected by their extent relative to the cursor, so completing a value mid-line (or with the command after another statement) uses only the text left of the cursor.
- Optional-value switches such as `--resume`, `--share`, `--mouse`, and `--bash-env` are handled in both separated and inline `--flag=value` forms; as in copilot, a separated optional value takes the next word even when it is a command name (`copilot --resume mcp` resumes the session named `mcp`).
- The list options `--allow-tool`, `--deny-tool`, `--allow-url`, `--deny-url`, `--available-tools`, `--excluded-tools` and `--secret-env-vars` (`[<x>...]`) take every following word up to the next option, so after `copilot --allow-tool read write ` another value or an option is offered, never a command. The attached form (`--allow-tool=read`) takes only its one value.
- File and directory candidates are quoted when they hold whitespace or PowerShell metacharacters (`$`, `&`, `;`, `(`, `{`, `,`, a backtick, quotes), in the quote you typed (ASCII or typographic) or single quotes by default; attached forms keep the option outside the quotes (`--attachment='my file.png'`). A typed directory part (`.\`, `../`) is kept as typed, a name starting with a dash gets a `.\` prefix (`.\-notes.txt`) so it is not read as an option, and a value picked from a list after a typed quote is quoted the same way (`--model 'gpt-5.5'`).
- After `--` every word is an operand (`copilot config powershellFlags -- -NoProfile`, `copilot mcp add <name> -- <command>`), so no options or commands are offered there.
- The completer does not infer live session IDs, marketplace plugin catalogs, or interactive in-session slash commands.
- Runtime-backed suggestions depend on the installed `copilot` executable being available on `PATH`.
