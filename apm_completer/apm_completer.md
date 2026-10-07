# apm completer

## What it completes / overview

`apm_completer.ps1` registers a standalone native PowerShell completer for:

- `apm`
- `apm.exe`

The implementation is **static-first** with a live help layer. The static table was re-derived from every `--help` page of the installed apm 0.33.0 and cross-checked against the upstream `microsoft/apm` repository for enum values and target aliases. When `apm.exe` is on `PATH`, the completer also parses the live `--help` page of the command path being completed (once per session) and merges it over the static table, so subcommands and options added by newer releases complete without a script change.

The completer covers:

- documented root commands and nested subcommands
- documented switches for each command path
- documented value-bearing options with enum, freeform, and path-aware handling
- the full apm 0.33.0 `--target` / `--runtime` harness list (21 values, listed under "Key value surfaces" below)
- comma-separated value lists (`--target claude,cursor`, `pack -m claude,codex`): the segment after the last comma completes, values already in the list are not offered again
- placeholders for freeform package, marketplace, script, and server slots so PowerShell does not fall back to filesystem completion in the wrong place
- local path completion for documented path-bearing slots such as:
  - `apm unpack BUNDLE_PATH`
  - `--output`
  - `--file`
  - `temp-dir`

## Registration and command names

The script ends with one importer-safe native registration:

```powershell
Register-ArgumentCompleter -Native -CommandName @('apm', 'apm.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Apm -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\apm_completer\apm_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- one `Get-Variable`-guarded `$script:ApmLiveHelpCache` initialisation (dot-sourcing twice keeps the cache)
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

Nothing runs `apm` at load time.

## Command surface implemented

Root commands:

- `init`
- `install`
- `uninstall`
- `prune`
- `audit`
- `auth` (`HOST`: `github.com`, `gitlab.com` suggestions; `--check`, `--export`, `-v/--verbose`)
- `pack`
- `unpack`
- `update` (refresh dependencies: `-y`, `--dry-run`, `-v`, `-g`, `--force`, `--parallel-downloads`, `-t/--target`, `[PACKAGES]...`)
- `self-update` (`--check`)
- `view`
- `outdated`
- `deps`
- `mcp`
- `marketplace`
- `search`
- `run`
- `preview`
- `list`
- `compile`
- `config`
- `runtime`
- `approve`, `deny`
- `cache`
- `doctor`
- `experimental`
- `find`
- `lifecycle`
- `lock`
- `plugin`
- `policy`
- `publish`
- `targets`
- `info`
  - hidden alias noted by the official docs

Nested subcommands:

- `deps`: `list`, `tree`, `info`, `clean`, `update`, `why`
- `mcp`: `install`, `list`, `search`, `show`
- `marketplace`: `add`, `list`, `browse`, `update`, `remove`, `validate`, `init`, `check`, `outdated`, `audit`, `package` (`add`, `remove`, `set`), `migrate`
- `config`: `get`, `list`, `set`, `unset`
- `runtime`: `setup`, `list`, `remove`, `status`
- `cache`: `clean`, `info`, `prune`
- `experimental`: `disable`, `enable`, `list`, `reset`
- `lifecycle`: `init`, `test`, `trust`, `untrust`, `validate`
- `lock`: `export`
- `plugin`: `init`
- `policy`: `explain`, `status`

Key value surfaces (apm 0.33.0):

- `install --runtime`, `install --exclude`, `install --target`, `update --target`, `deps update --target`, `lock --target`, `mcp install --target`, `pack --target`, `compile --target`, `plugin init --target`:
  - `agent-skills`, `agents`, `agy`, `all`, `antigravity`, `claude`, `codex`, `copilot`, `copilot-app`, `copilot-cowork`, `cursor`, `gemini`, `grok-build`, `grok-cloud`, `hermes`, `intellij`, `kiro`, `openclaw`, `opencode`, `vscode`, `windsurf`
- comma-separated lists over those 21 values: `-t/--target` on `install`, `update`, `compile`, `lock`, `deps update`, `mcp install`, and `--target` on `init` and `plugin init`
- `pack -m/--marketplace` (comma-separated): `all`, `none`, `claude`, `codex`
- `init --format`: `text`, `json`, `yaml`
- `audit --external`: `skillspector`, `sarif`
- `install --only`: `apm`, `mcp`
- `install --transport`, `mcp install --transport`: `stdio`, `http`, `sse`, `streamable-http`
- `install --audit`: `off`, `warn`, `block`
- `pack --format`: `plugin`, `agent-plugin`, `claude`, `claude-plugin`, `apm`
- `pack --archive-format`: `zip`, `tar.gz`
- `audit --format`: `text`, `json`, `sarif`, `markdown`
- `lock export --format`: `cyclonedx`, `spdx`
- `lifecycle test [EVENT]`: `pre-install`, `post-install`, `pre-update`, `post-update`, `pre-uninstall`, `post-uninstall`
- `view [FIELD]`: `versions`
- `config get/set/unset [KEY]`: `auto-integrate`, `temp-dir`
- `config set auto-integrate VALUE`: `true`, `false`, `yes`, `no`, `1`, `0`
- `runtime setup/remove`: `copilot`, `codex`, `gemini`, `llm`

Freeform slots intentionally stay placeholder-driven:

- package specs and package names
- marketplace names and `OWNER/REPO` references
- script names
- MCP server names
- `--param`
- `--branch`, `--host`, `--version`, `--chatmode`
- `install --mcp`, `--skill`, `--as`, `--url`, `--env`, `--header`, `--mcp-version`, `--registry`, `--allow-insecure-host`; `view --registry`

## Path handling

The completer uses local path completion only for documented path-bearing slots:

- `apm unpack BUNDLE_PATH`
- `audit --file`
- `audit --output`
- `pack --output`
- `unpack --output`
- `compile --output`
- `install --root`, `compile --root`
- `audit --external-sarif`
- `config set temp-dir`

For `apm install`, local path completion is offered only when the current package token already looks like a filesystem path such as `.\`, `..\`, `~\`, `C:\`, or `\\server\share`.

## Runtime quirks / notes

- The official docs and the upstream click definitions are not perfectly identical for some target-value aliases. This completer stays docs-first for command/switch coverage, and uses the upstream source to fill enum aliases where the implementation clearly accepts them.
- `apm info` is not a top-level documented section, but the official reference explicitly notes it as a hidden alias for `apm view`, so the completer includes it.
- Live help layer: `apm <path> --help` runs with stdin closed, a 5 s timeout (the process is killed on expiry), stdout/stderr drained asynchronously and ANSI sequences stripped. Results are cached per session, keyed by the resolved `apm.exe` (the WinGet symlink is followed) and its write time, so an upgrade invalidates them. A missing tool or a failed page falls back to the static table and is not retried.
- The child process gets `APM_E2E_TESTS=1`. apm's root callback otherwise runs its update check (a GitHub API call plus a write to `%LOCALAPPDATA%\apm\cache\last_version_check`) before any subcommand's `--help`; that variable is the only environment switch that skips it.
- The static table is only walked for the command path. A word the table does not know (a new command) is looked up in the live page of the current command, which the completion needs anyway. As in Click, a group's first plain word is its subcommand, so a word that is in neither list (and is not the value of the option before it) ends the path: `apm foo install ` completes at the root and starts no `apm install --help`. An unknown word never triggers a help page of its own. Static definitions win over live ones because they carry richer value kinds; the live layer only adds what the table lacks (today that is `--help` on each command).
- An unquoted `claude,cu` reaches the completer as a PowerShell array literal: `$wordToComplete` is just `cu` and only that segment is replaced, while `apm` still receives `claude,cursor` as one argument. A quoted `'claude,cu` is replaced whole and keeps its quote.
- `view --registry [NAME]` (and any live option whose metavar is a single bracketed name) takes an optional value. Click consumes the next word as its value unless that word is an option (`apm view --registry a b c d` reports only `d` as extra), so the separate-word slot offers the `<registry>` placeholder plus the command's options, but not the `<package>` positional (a plain word there would become the registry name). `--registry -g ` is read as a bare `--registry` followed by `-g`, and `--registry=` offers only the value.

## Validation commands

Representative clean-session checks for this script:

```powershell
pwsh -NoProfile -Command '
$file = ".\apm_completer\apm_completer.ps1"
$null = $tokens = $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors) | Out-Null
"PARSE_ERRORS=$($errors.Count)"
. $file
"LOADED=ok"
'
```

```powershell
pwsh -NoProfile -Command '
$modulePath = Get-ChildItem "..\Modules\CompleterActions\*\CompleterActions.psd1" |
    Sort-Object { [version] $_.Directory.Name } -Descending |
    Select-Object -First 1 -ExpandProperty FullName
Import-Module $modulePath -Force
$file = Resolve-Path ".\apm_completer\apm_completer.ps1"
$imported = @(Import-CompleterScript -LiteralPath $file)
"IMPORTED=$($imported.Count)"
$imported | Select-Object CommandName, ParameterName, CompleterType
'
```

```powershell
pwsh -NoProfile -Command '
. .\apm_completer\apm_completer.ps1
foreach ($s in @(
    "apm ",
    "apm install --only ",
    "apm install --target ",
    "apm pack --format=",
    "apm view microsoft/apm ",
    "apm deps ",
    "apm runtime setup ",
    "apm.exe compile --target "
)) {
    "INPUT=$s"
    (TabExpansion2 $s $s.Length).CompletionMatches |
        Select-Object -First 12 CompletionText, ResultType |
        Format-Table -AutoSize
    "---"
}
'
```

## Validation

Validated against apm 0.33.0 (WinGet) with dot-sourced and `Import-CompleterScript | Register-Completer` sessions (identical results), a session with `apm` removed from `PATH` (static fallback), `Test-CompleterScript` (0 findings) and zero `$Error` records. A cold Tab on a new command path pays one `apm <path> --help` (about 0.7 s idle, about 2 s on a loaded machine); warm Tabs stay under about 100 ms.
