# gh CLI completer

## What it completes / overview
`gh_cli_completer.ps1` delegates GitHub CLI completion to the installed `gh` executable: on the first Tab it runs `gh completion -s powershell`, strips the upstream `Register-ArgumentCompleter` line, compiles the remaining cobra block into a cached script-scoped scriptblock, and forwards every Tab to it. Subcommands, flags, `--json` fields and enums therefore always match the installed `gh` version.

Around that delegation the wrapper adds:

- a silent, negative-cached missing-tool path (no host output, one discovery per session)
- stderr suppression, so cobra's `Completion ended with directive: ...` banner never reaches the console
- a small value model for the slots gh's own completer leaves empty (see below)

## Registration and command names
The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('gh', 'gh.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-GhCliCompletion -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\gh_cli_completer\gh_cli_completer.ps1
```

## How completion works
1. `Get-GhCliCommandPath` resolves `gh`/`gh.exe` once and caches the path in script scope.
2. `Get-GhCliCompletionInvoker` runs `gh completion -s powershell` once, patches the two places where the upstream block pipes a `$null` value list (an empty result would otherwise leave a record in `$Error` on every such Tab), compiles the block with `Set-StrictMode -Off` prepended and caches it. A failed discovery sets `$script:GhCliCompletionUnavailable`, so later Tabs return immediately; diagnostics go to the verbose stream only.
3. `Invoke-GhCliCompletion` calls the block with `2>$null`. When it yields real `CompletionResult` objects they are returned unchanged.
4. Otherwise `Get-GhCliFallbackCompletion` consults the value model. For `gh help <topic>` the fallback's help topics are appended to gh's own command list.
5. If neither has anything the completer returns nothing. gh's `""` no-file-completion sentinel is not passed on, because PowerShell rejects an empty completion text (and records the failure in `$Error`); PowerShell's own path completion applies instead.

## Fallback value model
Used when gh returns no suggestions (and, for `gh help `, alongside them):

- `gh api -X ` / `--method ` → `GET POST PUT PATCH DELETE HEAD`, and the attached spellings `--method=P` / `-XP` → `--method=POST` / `-XPOST`
- `gh api ` → common endpoint paths (`user`, `graphql`, `repos/{owner}/{repo}`, ...) or an `<endpoint>` placeholder
- `gh config get|set ` → the documented keys; `gh config set <key> ` → the closed value set for enum keys (`git_protocol`, `prompt`, `clipboard`, `telemetry`, ...)
- `gh alias delete|set ` → alias names read from the local `config.yml`
- `--hostname ` → hosts from the local `hosts.yml` plus `github.com`
- `gh workflow run|view|enable|disable ` → `.github/workflows/*.yml|yaml`
- `gh pr checkout ` (and the `co` alias) → local and remote branch names from `git for-each-ref`
- `gh extension remove|upgrade ` (and the `ext`/`extensions`/`uninstall` aliases) → installed extensions from the `gh-*` entries of `%XDG_DATA_HOME%\gh\extensions` or `%LOCALAPPDATA%\GitHub CLI\extensions`, plus `--all` for upgrade, or an `<extension>` placeholder
- `gh secret|variable set ` → a `<NAME>` placeholder
- `gh help ` → the HELP TOPICS parsed once from `gh --help`, added to the commands gh offers for that slot

## Dependencies or external command expectations
- Requires `gh` in `PATH` for delegated completion; without it every Tab returns nothing, silently.
- Requires the installed GitHub CLI to support `gh completion -s powershell`.
- The branch provider requires `git`; the alias and host providers read the gh config directory (`GH_CONFIG_DIR`, `%APPDATA%\GitHub CLI`, or `~/.config/gh`).

## Usage / loading example
```powershell
. .\gh_cli_completer\gh_cli_completer.ps1

gh <TAB>
gh pr <TAB>
gh api -X <TAB>
gh config set git_protocol <TAB>
gh help <TAB>
```

## Limitations / notes
- Completion coverage changes with the installed GitHub CLI version because the upstream script is generated at load time.
- The fallback model is deliberately small and local; it never calls the GitHub API.
- The strip regex that removes gh's own registration line is pinned to the current upstream spelling.
