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
3. `Invoke-SbxCompletion` calls the block with `2>$null` and returns its output unchanged: `CompletionResult` objects, sbx's `""` no-file-completion sentinel, or nothing (file completion allowed, as for `sbx cp`).

Each Tab spawns `sbx __complete <args>`; sbx answers from its own command tree and, for sandbox-name slots such as `sbx rm <TAB>`, from the local sandboxd daemon. Nothing is created, changed or removed by completion.

## Dependencies or external command expectations
- Requires `sbx` in `PATH` for delegated completion; without it every Tab returns nothing, silently.
- Requires the installed Docker Sandboxes CLI to support `sbx completion powershell` and the cobra `__complete` protocol.
- Because the generated block is cobra's own, it sets `SBX_ACTIVE_HELP=0` in the session environment on each call (upstream behaviour) and shows descriptions only under the `MenuComplete` or `Complete` PSReadLine Tab functions.

## Usage / loading example
```powershell
. .\sbx_completer\sbx_completer.ps1

sbx <TAB>
sbx run --<TAB>
sbx completion <TAB>
sbx rm <TAB>
```
