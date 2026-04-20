# apm completer

## What it completes / overview

`apm_completer.ps1` registers a standalone native PowerShell completer for:

- `apm`
- `apm.exe`

The implementation is **static-first**. The command surface was built from the official CLI reference, cross-checked against the upstream `microsoft/apm` repository for documented enum values and target aliases, and then validated locally against `apm --help` and targeted subcommand help output.

The completer covers:

- documented root commands and nested subcommands
- documented switches for each command path
- documented value-bearing options with enum, freeform, and path-aware handling
- source-backed target aliases that appear in the upstream click definitions:
  - `copilot`
  - `vscode`
  - `agents`
- placeholders for freeform package, marketplace, script, and server slots so PowerShell does not fall back to filesystem completion in the wrong place
- local path completion for documented path-bearing slots such as:
  - `apm unpack BUNDLE_PATH`
  - `--output`
  - `--file`
  - `temp-dir`

## Registration and command names

The script ends with one importer-safe native registration:

```powershell
Register-ArgumentCompleter -Native -CommandName @('apm', 'apm.exe') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\apm_completer\apm_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or external command calls.

## Command surface implemented

Root commands:

- `init`
- `install`
- `uninstall`
- `prune`
- `audit`
- `pack`
- `unpack`
- `update`
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
- `info`
  - hidden alias noted by the official docs

Nested subcommands:

- `deps`: `list`, `tree`, `info`, `clean`, `update`
- `mcp`: `list`, `search`, `show`
- `marketplace`: `add`, `list`, `browse`, `update`, `remove`
- `config`: `get`, `set`
- `runtime`: `setup`, `list`, `remove`, `status`

Key value surfaces:

- `install --runtime`, `install --exclude`: `copilot`, `codex`, `vscode`
- `install --only`: `apm`, `mcp`
- `install --target`, `deps update --target`, `pack --target`, `compile --target`:
  - `copilot`, `claude`, `cursor`, `opencode`, `codex`, `vscode`, `agents`, `all`
- `pack --format`: `apm`, `plugin`
- `audit --format`: `text`, `json`, `sarif`, `markdown`
- `view [FIELD]`: `versions`
- `config get/set [KEY]`: `auto-integrate`, `temp-dir`
- `config set auto-integrate VALUE`: `true`, `false`, `yes`, `no`, `1`, `0`
- `runtime setup/remove`: `copilot`, `codex`, `llm`

Freeform slots intentionally stay placeholder-driven:

- package specs and package names
- marketplace names and `OWNER/REPO` references
- script names
- MCP server names
- `--param`
- `--branch`, `--host`, `--version`, `--chatmode`

## Path handling

The completer uses local path completion only for documented path-bearing slots:

- `apm unpack BUNDLE_PATH`
- `audit --file`
- `audit --output`
- `pack --output`
- `unpack --output`
- `compile --output`
- `config set temp-dir`

For `apm install`, local path completion is offered only when the current package token already looks like a filesystem path such as `.\`, `..\`, `~\`, `C:\`, or `\\server\share`.

## Runtime quirks / notes

- The official docs and the upstream click definitions are not perfectly identical for some target-value aliases. This completer stays docs-first for command/switch coverage, and uses the upstream source to fill enum aliases where the implementation clearly accepts them.
- `apm info` is not a top-level documented section, but the official reference explicitly notes it as a hidden alias for `apm view`, so the completer includes it.
- Because the binary is not installed locally, this script does not attempt help parsing or live discovery.

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

## Validation gap

Without a local `apm` installation, validation is limited to:

- parser checks
- dot-sourcing in a clean PowerShell session
- `Import-CompleterScript` import safety
- static `TabExpansion2` behavior against the registered completer

It does **not** validate live `apm --help` output, binary-specific parsing behavior, or real command execution semantics.
