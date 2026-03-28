# pslist completer

## What it completes / overview

`pslist_completer.ps1` registers a native PowerShell completer for `pslist` and `pslist.exe`.

The implementation is intentionally hybrid and static-first:

- it seeds the known local switch surface from researched help output
- it safely probes `pslist /?` to refine descriptions without treating exit code `1` as fatal
- it adds placeholder completions for remote-login and remote-target slots
- it adds live local process-name and PID suggestions for the final `name|pid` slot

The goal is to replace PowerShell's default filesystem fallback with command-relevant suggestions.

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `pslist`, `pslist.exe`
- The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('pslist', 'pslist.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-Pslist -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it into the current session with:

```powershell
. .\pslist_completer.ps1
```

The file also enables `Set-StrictMode -Version 2.0`.

When `pslist` resolves through the Windows app-execution alias surface, the script also creates a transparent `pslist -> pslist.exe` alias in the current session when no alias already exists. This keeps first-argument `TabExpansion2` behavior aligned with the registered native completer without overriding an existing user-defined alias or function.

## How completion works

### Static-first catalog initialization

The script-scoped `$script:PslistCompletionCatalog` stores:

- `SwitchOrder`
- `SwitchInfo`
- `PositionalInfo`
- numeric hint sets for `-s` and `-r`
- a short-lived local process cache

`Initialize-PslistCompletionCatalog` first seeds built-in metadata for the known local help surface:

- `-d`
- `-m`
- `-x`
- `-t`
- `-s`
- `-r`
- `-u`
- `-p`
- `-e`
- `-nobanner`
- `-?`
- `/?`

It then runs `pslist /?` when available and parses the parameter lines to refine the stored descriptions. `pslist /?` is expected to exit with code `1`, so the probe is treated as informational rather than as a success/failure check.

### Token-state parsing

The completer:

- reads command elements from `$commandAst`
- reconstructs the current token from the command line when needed
- distinguishes trailing-space completion from in-token completion
- scans previously entered tokens to determine:
  - which singleton switches are already present
  - whether the current position is the value for `-s`, `-r`, `-u`, or `-p`
  - whether a remote target has already been supplied
  - whether the positional `name|pid` target has already been supplied
  - whether the positional target is a process name or a PID

That state drives the switch list, value hints, and the special `-e` behavior.

## Key completion behaviors / supported values

### Root switch completion

At the root, the completer suggests the known switches instead of falling back to files and directories.

Behavior highlights:

- `-u` and `-p` are only suggested after a `\\computer` target is present
- `-r` is only suggested after `-s` is already present
- `-e` is only suggested when the positional target is a process name
- `-?` and `/?` are treated as terminal help aliases and are only suggested before any other arguments
- after a help alias is already present, the completer returns a terminal completion to suppress filesystem fallback

### `\\computer` placeholder completion

When no remote target or positional process target has been supplied yet, the completer offers:

- `\\computer`

This is a placeholder hint only; it does not attempt host discovery.

### `-u` and `-p` placeholder completion

For remote-login parameters, the completer offers:

- `-u` -> `<username>`
- `-p` -> `<password>`

`-p` remains placeholder-only. The completer does not attempt any prompting or live probing because that can block interactively.

### `-s [n]` and `-r n` numeric hints

The completer provides small numeric hint sets for the sampling and refresh slots:

- `1`
- `2`
- `5`
- `10`

For `-s`, the numeric value is optional, so after `-s` with trailing space the completer returns both numeric hints and other valid switches.

### Positional `name|pid` completion

When completing the final target slot with no remote computer specified, the completer uses `Get-Process` to build a short-lived cache of:

- unique local process names
- unique local PIDs

Both are returned as `ParameterValue` results.

### Remote target behavior

When a remote `\\computer` target is already present, the completer does **not** pretend to enumerate remote process names or PIDs.

Instead it returns placeholder-style suggestions for the final slot:

- `<process-name>`
- `<pid>`

If the user has already started typing a remote target value, the completer echoes that token back as a value completion so PowerShell does not fall back to filesystem suggestions.

### `-e` exact-match behavior

`-e` is only suggested when the positional target is recognized as a non-numeric process name.

If the positional target is numeric, `-e` is suppressed because it is not meaningful for a PID target.

## Dependencies or external command expectations

- `Get-Process` is used for local process-name and PID suggestions
- `pslist /?` is optionally used to refine tooltips when `pslist` is available on `PATH`
- no remote probing is attempted

## Usage / loading example

```powershell
. "$PSScriptRoot\pslist_completer.ps1"

# Example completions
# pslist <TAB>
# pslist -<TAB>
# pslist \\<TAB>
# pslist -s <TAB>
# pslist -s -r <TAB>
# pslist \\server -u <TAB>
# pslist notepad <TAB>
```

## Limitations / notes

- The completer is focused on the documented local help surface and does not attempt deep command validation.
- Remote process names and remote PIDs are intentionally **not** enumerated.
- Local process suggestions are dynamic and can change between invocations.
- The local process cache is intentionally short-lived to keep suggestions fresh during repeated `TabExpansion2` usage.
