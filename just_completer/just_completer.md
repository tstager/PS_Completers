# just completer

## What it completes / overview

`just_completer.ps1` registers a native PowerShell argument completer for `just`.

This completer is intentionally thin. It does not maintain a repository-local command tree or parse `just --help`. Instead, it forwards the current command line to `just`'s built-in completion entrypoint and converts the returned rows into PowerShell completion results.

## Registration and command names

- Registers with: `Register-ArgumentCompleter -Native`
- Command names:
  - `just`
  - `j` - Alias needs to be set in Shell.
  - `just.exe`

The script registers a single native completer script block for `just`.

## How completion works

The completer script block:

1. Receives the standard native completer parameters: `$wordToComplete`, `$commandAst`, and `$cursorPosition`.
2. Saves the current `JUST_COMPLETE` environment variable value, if any.
3. Sets `JUST_COMPLETE=powershell` so `just.exe` emits PowerShell-oriented completion rows.
4. Reads the command line text from `$commandAst.Extent.Text` and truncates it to the current cursor position.
5. If the current word is empty, appends `' '` so the upstream completer still sees an empty trailing argument position.
6. Invokes the hardcoded WinGet-installed `just.exe` path with:

   ```powershell
   & "C:\Users\Trent\AppData\Local\Microsoft\WinGet\Packages\Casey.Just_Microsoft.Winget.Source_8wekyb3d8bbwe\just.exe" -- $args
   ```

7. Restores `JUST_COMPLETE` to its previous value, or removes it if it was not set before completion ran.
8. Splits each returned line on a tab character:
   - column 1 becomes the completion text
   - column 2, when present, becomes the tooltip text
   - if no tab is present, the completion text is also used as the tooltip
9. Emits each row as a `System.Management.Automation.CompletionResult` with `ParameterValue` result type.

## Key completion behaviors / supported values

- Completion behavior is delegated to the installed `just` executable rather than defined statically in this repository.
- The script forwards the full command line prefix up to the cursor, so upstream `just` completion can inspect subcommands, recipe names, flags, and value positions.
- When the cursor is after a space and there is no current word yet, the script intentionally preserves that empty argument slot before invoking `just`.
- Tooltip text comes from the second tab-separated field returned by `just`, when present.

## Dependencies or external command expectations

- Expects `just.exe` to exist at:

  `C:\Users\Trent\AppData\Local\Microsoft\WinGet\Packages\Casey.Just_Microsoft.Winget.Source_8wekyb3d8bbwe\just.exe`

- Expects that executable to support `JUST_COMPLETE=powershell`.
- Uses the local executable only; it does not make network calls.

The script itself invokes that concrete WinGet package path rather than calling `Get-Command just` or resolving `just` from `PATH`. In practice, a WinGet install may also expose `just` on `PATH` via a shim or app execution alias, but this completer does not depend on that mechanism because it calls the package path directly.

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
- The executable path is hardcoded to a specific WinGet install location, even though that same installation may also be reachable as `just` on `PATH` through a shim or alias. Completion will still fail if the package path changes and the script is not updated.
- The script uses `Invoke-Expression` to execute the constructed `just.exe -- ...` command line.
- There is no repository-local fallback if the upstream executable errors or returns no completions.
