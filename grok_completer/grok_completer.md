# grok completer

## What it completes / overview

`grok_completer.ps1` registers a standalone native PowerShell argument completer for the `grok` CLI.

The script follows the repository's standalone completer pattern:

- it uses a script-scoped lazy cache,
- it registers with `Register-ArgumentCompleter -Native`,
- it resolves the installed `grok` executable and consumes its live `--help` / `help <subcommand>` output,
- and it completes root switches, subcommands, and value-bearing options without relying on a stale hard-coded list.

## Registration and command names

The script registers the same native completer for:

- `grok`
- `grok.exe`

## How completion works

### 1. Live help discovery

`Initialize-GrokCompletionCatalog` lazily loads a catalog from the installed `grok` binary.

It uses:

- `grok --help` for the root command surface,
- `grok help <subcommand>` for subcommand-specific options and nested commands,
- and cached parsed output so completion stays fast after the first lookup.

### 2. Root-level suggestions

At the top level, the completer suggests:

- root switches such as `--agent`, `--continue`, `--help`, `--model`, and `--output-format`,
- and top-level subcommands such as `agent`, `completions`, `models`, `plugin`, `sessions`, `update`, and `worktree`.

### 3. Subcommand-aware completion

Once a known top-level subcommand is selected, the completer switches to that subcommand's own option and command catalog. For example:

- `grok agent <TAB>` suggests agent subcommands such as `stdio`, `headless`, `serve`, and `leader`,
- `grok completions <TAB>` suggests shell values such as `bash`, `fish`, `powershell`, and `zsh`.

### 4. Value-aware option completion

When the previous token is a value-taking option, the completer attempts to use help-derived values when `grok` publishes them. If the help does not provide specific values, it falls back to a conservative placeholder such as `<value>` or path-aware completion for path-like options such as `--cwd` and `--debug-file`.

## Dependencies or external command expectations

The completer expects an installed `grok` executable on `PATH` or in the standard `~/.grok/bin` install location.

If `grok` is not available, the completer returns no suggestions.

## Usage / loading example

Dot-source the script:

```powershell
. .\grok_completer.ps1
```

Example completion scenarios:

```powershell
grok <TAB>
grok --<TAB>
grok agent <TAB>
grok completions <TAB>
grok --output-format <TAB>
```
