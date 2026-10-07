# sbx (Docker Sandboxes) completer

## What it completes / overview
`sbx_completer.ps1` delegates Docker Sandboxes CLI completion to the installed `sbx` executable: on the first Tab it runs `sbx completion powershell`, strips the upstream `Register-ArgumentCompleter` line, compiles the remaining cobra block into a cached script-scoped scriptblock, and forwards every Tab to it. Subcommands (`run`, `create`, `exec`, `rm`, `ttl`, ...), flags, enum values and live sandbox names therefore always match the installed `sbx` version (validated against `sbx` v0.43.0).

Around that delegation the wrapper adds:

- a silent, negative-cached missing-tool path (no host output, one discovery per session)
- stderr suppression, so cobra's `Completion ended with directive: ...` banner never reaches the console
- registration for both `sbx` and `sbx.exe` inside the CompleterActions strict import grammar

## Registration and command names
The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('sbx', 'sbx.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-SbxCompletion -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\sbx_completer\sbx_completer.ps1
```

## How completion works
1. `Get-SbxCommandPath` resolves `sbx`/`sbx.exe` once and caches the path in script scope.
2. `Get-SbxCompletionInvoker` runs `sbx completion powershell` once, patches the block's final `$Values | ForEach-Object` to skip a `$null` pipeline (otherwise a no-suggestion Tab in a path slot such as `sbx cp .\x` builds a `CompletionResult` from a null name and leaves an exception in `$Error`), compiles it with `Set-StrictMode -Off` prepended (the upstream block dereferences an empty pipeline when there are no suggestions) and caches it. A failed discovery sets `$script:SbxCompletionUnavailable`, so later Tabs return immediately; diagnostics go to the verbose stream only.
3. `Invoke-SbxCompletion` calls the block with `2>$null` and returns its `CompletionResult` objects. It drops sbx's `""` no-file-completion sentinel, which PowerShell rejects as an empty completion text, so an empty answer (`sbx ls <TAB>`, `sbx rm zzzz<TAB>`) simply yields nothing.
4. `Get-SbxFlagValueSlot` holds the closed value sets that `sbx <command> --help` documents but cobra does not register (validated against v0.47.0): `run`/`create` `--skills` (off, readonly, readwrite), `--on-timeout` (stop, restart, delete), `--platform` (linux/amd64, linux/arm64) and `--pull` (always, missing, never); `move` `--to` (local, cloud) and `--on-timeout` (stop, delete). `--skills` and `--pull` are local-only and are not offered under `--cloud`; nothing is offered after a bare `--`. In the separate form (`--pull <TAB>`) these values are used only when cobra returns nothing; the attached form (`--pull=<TAB>`) is answered from the table directly and keeps the `--flag=` prefix. A quote the user typed is kept on the emitted value. The table also works when `sbx` is not installed.

Each Tab spawns `sbx __complete <args>`; sbx answers from its own command tree and, for sandbox-name slots such as `sbx rm <TAB>`, from the local sandboxd daemon. Nothing is created, changed or removed by completion.

## Dependencies or external command expectations
- Requires `sbx` in `PATH` for delegated completion; without it every Tab other than the flag values above returns nothing, silently.
- Requires the installed Docker Sandboxes CLI to support `sbx completion powershell` and the cobra `__complete` protocol.
- Because the generated block is cobra's own, it sets `SBX_ACTIVE_HELP=0` in the session environment on each call (upstream behaviour) and shows descriptions only under the `MenuComplete` or `Complete` PSReadLine Tab functions.

## Usage / loading example
```powershell
. .\sbx_completer\sbx_completer.ps1

sbx <TAB>
sbx run --<TAB>
sbx completion <TAB>
sbx rm <TAB>
sbx run --pull <TAB>
sbx move SANDBOX --to=<TAB>
```
