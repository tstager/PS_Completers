# code-insiders completer

## What it completes / overview

`code_insiders_completer.ps1` registers a standalone native PowerShell completer for `code-insiders` and `code-insiders.cmd`.

It uses a hybrid static-first model:

- static command metadata derived from the local VS Code Insiders CLI help surface
- nested routing for `chat`, `serve-web`, `agent-host`, `tunnel`, `tunnel user`, and `tunnel service`
- cached local extension ID discovery from `code-insiders.cmd --list-extensions`
- real file and directory completion for path-bearing switches
- placeholder-oriented suggestions for prompts, locales, JSON, profiles, names, and other free-form values

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('code-insiders', 'code-insiders.cmd') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\code_insiders_completer\code_insiders_completer.ps1
```

On this machine, `code-insiders` and `code-insiders.cmd` are the actual invokable wrapper names. The local help text refers to `code-insiders.exe` and `code-tunnel-insiders.exe`, but the completer registers the names that PowerShell users actually invoke here.

## Import and runtime behavior

The top level stays compatible with `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter` call

All runtime probing is lazy and cached inside helper functions.

## How completion works

### Static command routing

The completer hard-codes the stable command tree observed from the local CLI help:

- root options plus subcommands `chat`, `serve-web`, `agent-host`, `tunnel`
- `tunnel` subcommands `prune`, `kill`, `restart`, `status`, `rename`, `unregister`, `user`, `service`
- `tunnel user` subcommands `login`, `logout`, `show`
- `tunnel service` subcommands `install`, `uninstall`, `log`

### Enum-aware value completion

It suggests documented enum values such as:

- `--log` -> `critical`, `error`, `warn`, `info`, `debug`, `trace`, `off`
- `--sync` -> `on`, `off`
- `--locate-shell-integration-path` -> `bash`, `pwsh`, `zsh`, `fish`
- `chat --mode` -> `ask`, `edit`, `agent`

### Cached local extension IDs

When completing extension-oriented switches, the completer lazily captures and caches:

```powershell
code-insiders.cmd --list-extensions
```

That local cache is used for:

- `--uninstall-extension`
- `--disable-extension`
- `--enable-proposed-api`
- `--install-extension` when an extension ID prefix is already being typed

### Path and placeholder handling

Real path completion is used for switches such as:

- `--diff`, `--merge`, `--add`, `--remove`
- `--user-data-dir`, `--extensions-dir`
- `chat --add-file`
- `serve-web --connection-token-file`, `--server-data-dir`, `--default-folder`, `--default-workspace`
- `agent-host --connection-token-file`, `--server-data-dir`
- `tunnel --server-data-dir`

Free-form slots intentionally use placeholders to suppress noisy filesystem fallback, including:

- `chat <prompt>`
- `--profile`
- `--locale`
- `--category`
- `--add-mcp`
- `tunnel rename <name>`

## Usage examples

```powershell
code-insiders --
code-insiders --log=
code-insiders --locate-shell-integration-path=
code-insiders chat --mode
code-insiders chat -a .\
code-insiders tunnel
code-insiders tunnel user
code-insiders serve-web --server-data-dir .\
code-insiders.cmd --install-extension
```

## Dependencies or external command expectations

- Expects `code-insiders` or `code-insiders.cmd` to be resolvable for dynamic extension ID discovery
- Falls back to placeholder-oriented suggestions when runtime discovery returns nothing
- Uses only local CLI help and local installed extension state

## Limitations / notes

- The completer does not attempt to enumerate profile names or extension categories.
- `--goto` uses a placeholder-oriented `file:line[:character]` value model and only performs direct path completion while the token still looks like a plain path.
- The tunnel subcommand help is surfaced through `code-insiders tunnel ...`, even though the underlying help text references `code-tunnel-insiders.exe`.
