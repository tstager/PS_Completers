# sbx (Docker Sandboxes) completer

## What it completes / overview
`sbx_completer.ps1` delegates Docker Sandboxes CLI completion to the installed `sbx` executable by speaking cobra's completion protocol directly: every Tab projects the typed command line to literal arguments, runs `sbx __complete <args>` as a child process and turns its answer into completion results. Subcommands (`run`, `create`, `exec`, `rm`, `ttl`, ...), flags, enum values and live sandbox names therefore always match the installed `sbx` version (validated against `sbx` v0.47.0).

Around that delegation the wrapper adds:

- no evaluation of anything typed: sub-expressions, variables and splats on the line are sent to `sbx` as their literal text and never run
- a silent, negative-cached missing-tool path (no host output, one discovery per session)
- the closed flag value sets listed below, which cobra does not register
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
1. `Get-SbxCommandPath` resolves `sbx`/`sbx.exe` once and caches the path, or its absence, in script scope.
2. `Get-SbxCompletionRequest` projects the `CommandAst` to the argv cobra expects without evaluating it: string constants (bare, single- or double-quoted) by their value, every other element (`$(...)`, `@(...)`, `$var`, `"...$(...)"`) by its raw text. Elements at or after the cursor are dropped, the element under the cursor is cut at the cursor, and an empty final argument is sent when the cursor follows whitespace. A quote the user opened on the current word is remembered and stripped, and an attached `--flag=` prefix is split off the value.
3. `Invoke-SbxCompleteCommand` starts `sbx __complete <args>` through `ProcessStartInfo.ArgumentList` (no shell, no string concatenation) with `SBX_ACTIVE_HELP=0` set on the child only, stdin closed, stdout and stderr drained asynchronously, the session's filesystem location as working directory and a 5-second timeout after which the process tree is killed. Output is decoded as UTF-8 and ANSI-stripped.
4. `Get-SbxCobraCompletion` reads the final `:<directive>` line. `Error`, `FilterFileExt` and `FilterDirs` return nothing, as does an empty answer, so PowerShell's own path completion takes over where sbx allows files (`sbx cp <TAB>`); PowerShell rejects an empty completion text, so an empty `NoFileComp` answer (`sbx ls <TAB>`) cannot suppress that fallback either. Candidates (`value<TAB>description`) are filtered by the typed prefix, sorted unless `KeepOrder` is set, and emitted with the description as tooltip. The completion text keeps the `--flag=` prefix and the typed quote, and a value that needs quoting is single-quoted.
5. `Get-SbxFlagValueSlot` holds the closed value sets that `sbx <command> --help` documents but cobra does not register (validated against v0.47.0): `run`/`create` `--skills` (off, readonly, readwrite), `--on-timeout` (stop, restart, delete), `--platform` (linux/amd64, linux/arm64) and `--pull` (always, missing, never); `move` `--to` (local, cloud) and `--on-timeout` (stop, delete). `--skills` and `--pull` are local-only and are not offered under `--cloud`; nothing is offered after a bare `--`. In the separate form (`--pull <TAB>`) these values are used only when cobra returns nothing; the attached form (`--pull=<TAB>`) is answered from the table directly and keeps the `--flag=` prefix. A quote the user typed is kept on the emitted value. The table also works when `sbx` is not installed.

`sbx __complete` answers from sbx's own command tree and, for sandbox-name slots such as `sbx rm <TAB>`, from the local sandboxd daemon. Nothing is created, changed or removed by completion.

## Dependencies or external command expectations
- Requires `sbx` in `PATH` for delegated completion; without it every Tab other than the flag values above returns nothing, silently.
- Requires the installed Docker Sandboxes CLI to support the cobra `__complete` protocol.
- Each delegated Tab costs one `sbx` process start (about 250 ms on the validation machine); the table-only attached flag values need none.

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
