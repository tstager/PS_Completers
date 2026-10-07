# gh CLI completer

## What it completes / overview
`gh_cli_completer.ps1` delegates GitHub CLI completion to the installed `gh` executable by speaking cobra's completion protocol directly: every Tab runs `gh __complete <typed arguments>` and turns its answer into completion results. Subcommands, flags, `--json` fields and enums therefore always match the installed `gh` version.

The typed command line is never evaluated. Older versions ran the script printed by `gh completion -s powershell`, which rebuilds the typed line as a string and runs it through `Invoke-Expression`, so a `$(...)` typed before Tab was executed. This completer does not run that script.

Around the delegation the completer adds:

- a silent, negative-cached missing-tool path (no host output, one lookup per session)
- a small value model for the slots gh's own completer leaves empty (see below)

## Registration and command names
The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('gh', 'gh.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-GhCliCompletion -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\gh_cli_completer\gh_cli_completer.ps1
```

## How completion works
1. `Get-GhCliCommandPath` resolves `gh`/`gh.exe` once and caches the path, or its absence, in script scope.
2. `Get-GhCliCompletionRequest` projects the command AST to cobra's argument list without evaluating anything. Words before the cursor are passed as typed: string constants (bare, single- or double-quoted) by value, and anything else (variables, subexpressions, splats) as its literal source text. The word under the cursor is cut at the cursor, and an empty final argument is added when the cursor follows whitespace. When the word under the cursor is not literal text, gh is not asked.
3. `Invoke-GhCliCompleteRequest` starts `gh __complete ...` through `ProcessStartInfo.ArgumentList` (no shell, no command-line string), with `GH_ACTIVE_HELP=0` set on the child only, stdin closed, the session's file-system location as the working directory (gh resolves the repository from it) and a 5-second limit after which the process tree is killed. Output is ANSI-stripped.
4. `Get-GhCliLiveCompletion` parses cobra's answer: `value<TAB>description` lines and a final `:<directive>`. Error, FilterFileExt and FilterDirs answers yield nothing; otherwise candidates are prefix-filtered (case-insensitive), sorted unless KeepOrder is set, and returned with their descriptions as tooltips. For `--flag=value` words the flag spelling is put back in front of each value. Flags are typed `ParameterName`, values `ParameterValue`. A value that needs quoting is single-quoted; a quote the user already typed is kept. A bare comma list such as `number,title` stays bare, because PowerShell passes it to a native command as one argument.
5. When gh has nothing (or is not installed), `Get-GhCliFallbackCompletion` consults the value model. For `gh help <topic>` the fallback's help topics are appended to gh's own command list.
6. If neither has anything the completer returns nothing and PowerShell's own path completion applies, as it did with gh's generated script. Neither gh's answers (including empty ones and quoted words) nor the fallback leave a record in `$Error`.

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

The value model is local, so it also works when `gh` is not installed.

## Dependencies or external command expectations
- Requires `gh` in `PATH` for delegated completion; without it only the local value model answers, silently.
- Relies on cobra's hidden `__complete` command, which every cobra-based `gh` release ships.
- The branch provider requires `git`; the alias and host providers read the gh config directory (`GH_CONFIG_DIR`, `%APPDATA%\GitHub CLI`, or `~/.config/gh`).

## Usage / loading example
```powershell
. .\gh_cli_completer\gh_cli_completer.ps1

gh <TAB>
gh pr <TAB>
gh pr list --json number,ti<TAB>
gh api -X <TAB>
gh config set git_protocol <TAB>
gh help <TAB>
```

## Limitations / notes
- Completion coverage changes with the installed GitHub CLI version because gh answers every Tab itself.
- Some of gh's own completions (repository, issue or pull-request slots) may query the GitHub API, exactly as gh's generated completer does; the fallback model never calls the API.
- FilterFileExt and FilterDirs answers fall through to PowerShell's unfiltered path completion.
- A word under the cursor that is not literal text (for example `$name` or `$(...)`) gets no gh completions.
