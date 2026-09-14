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

Once a known top-level subcommand is selected, the completer switches to that subcommand's own option and command catalog, and keeps descending for every further subcommand on the line (`grok help <a> <b>` is fetched lazily and cached per path). Subcommand aliases printed as `[aliases: ...]` (`ls`, `rm`, `disk-usage`, `v`) resolve to their canonical node. For example:

- `grok agent <TAB>` suggests agent subcommands such as `stdio`, `headless`, `serve`, and `leader`,
- `grok worktree db <TAB>` suggests `path`, `rebuild`, and `stats`,
- `grok completions <TAB>` suggests shell values such as `bash`, `fish`, `powershell`, and `zsh`.

### 4. Value-aware option completion

When the previous token is a value-taking option (or the current word is the attached `--option=value` form), the completer uses help-derived values when `grok` publishes them, including clap's multi-line `Possible values:` blocks (`--output-format`) and the inline `[possible values: ...]` form (`--permission-mode`). Option aliases from `[aliases: ...]` and `(compat alias: ...)` notes (`--effort`, `--ref`, `--allowedTools`) resolve to the same option. The value kind is derived from the metavariable and description: `<CWD>`/`<DIR>` options complete directories only, `<FILE>`/`<PATH>` options and options whose description mentions a file complete paths, and everything else falls back to a conservative `<value>` placeholder.

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
