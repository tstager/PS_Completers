# just completer

## What it completes / overview

`just_completer.ps1` registers a native PowerShell argument completer for `just`.

This completer is intentionally thin. It does not maintain a repository-local command tree or parse `just --help`. Instead, it forwards the current command line to `just`'s built-in completion entrypoint and converts the returned rows into PowerShell completion results.

## Registration and command names

- Registers with: `Register-ArgumentCompleter -Native`
- Command names:
  - `just`
  - `just.exe`

The script registers a single native completer script block for `just`.

## How completion works

The completer script block:

1. Receives the standard native completer parameters: `$wordToComplete`, `$commandAst`, and `$cursorPosition`.
2. Lazily resolves the installed `just` executable with `Get-Command -Name just.exe, just -CommandType Application, ExternalScript` and reuses that resolved command name for later completions.
3. Saves the current `JUST_COMPLETE` environment variable value, if any.
4. Sets `JUST_COMPLETE=powershell` so `just` emits PowerShell-oriented completion rows.
5. Reads the command line text from `$commandAst.Extent.Text` and truncates it to the current cursor position.
6. If the current word is empty, appends `' '` so the upstream completer still sees an empty trailing argument position.
7. Invokes the resolved `just` command with:

   ```powershell
   & '<resolved-just-command>' -- $args
   ```

8. Restores `JUST_COMPLETE` to its previous value, or removes it if it was not set before completion ran.
9. Splits each returned line on a tab character:
   - column 1 becomes the completion text
   - column 2, when present, becomes the tooltip text
   - if no tab is present, the completion text is also used as the tooltip
10. Emits each row as a `System.Management.Automation.CompletionResult` with `ParameterValue` result type.

## Key completion behaviors / supported values

- Completion behavior is delegated to the installed `just` executable rather than defined statically in this repository.
- The script forwards the full command line prefix up to the cursor, so upstream `just` completion can inspect subcommands, recipe names, flags, and value positions.
- When the cursor is after a space and there is no current word yet, the script intentionally preserves that empty argument slot before invoking `just`.
- Tooltip text comes from the second tab-separated field returned by `just`, when present.

## Dependencies or external command expectations

- Expects `Get-Command -Name just.exe, just -CommandType Application, ExternalScript` to resolve an installed `just` command from the current session.
- Expects the resolved command to support `JUST_COMPLETE=powershell`.
- Uses the local executable only; it does not make network calls.

The script now resolves `just` lazily through PowerShell command discovery instead of assuming a specific user profile or WinGet package directory. In practice this keeps the completer portable across machines and installation layouts while still invoking the locally installed `just` binary.

## Usage / loading example

```powershell
. .\just_completer.ps1
```

Example scenarios after loading:

```powershell
just <Tab>
just --<Tab>
just build <Tab>
```

## Limitations / notes

- The completer is a wrapper around `just`'s own completion output; coverage changes with the installed `just` version.
- If `Get-Command` cannot resolve `just`, the completer returns no results.
- The script uses `Invoke-Expression` to execute the constructed `just.exe -- ...` command line.
- There is no repository-local fallback if the upstream executable errors or returns no completions.
