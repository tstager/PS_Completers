# Oh My Posh completer

## What it completes / overview

`OhMyPosh_completer.ps1` registers a standalone native PowerShell completer for `oh-my-posh` and `oh-my-posh.exe`.

It is help-driven. Commands, flags and positional values are parsed from `oh-my-posh <command...> --help` at completion time and cached per command path for the session, so sub-subcommands such as `config export` or `font install` and newly added commands appear without a hand-written table. A small static table of top-level commands and global flags is used only when the executable is not installed.

The completer covers:

- top-level commands and nested subcommands at any depth
- flags for the current command path, with the help description as the tooltip
- positional values published in the `Usage:` line, for example `oh-my-posh get [accent|shell|millis|toggles|width]`, or, for a single `[placeholder]` such as `oh-my-posh auth [service]`, the `- name: description` bullets in the help body (description as tooltip)
- shell names after `-s` / `--shell`, taken from the `oh-my-posh init` usage line so the list follows the installed version (a static list is used when the executable is absent)
- theme files from `$env:POSH_THEMES_PATH` plus ordinary path completion after `-c` / `--config` and `--data`
- the attached form `--flag=value`

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `oh-my-posh.exe`, `oh-my-posh`
- Entry point: `Complete-OhMyPosh`

```powershell
Register-ArgumentCompleter -Native -CommandName @('oh-my-posh.exe', 'oh-my-posh') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-OhMyPosh -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\OhMyPosh_completer\OhMyPosh_completer.ps1
```

## Import-CompleterScript compatibility

The top level contains only `Set-StrictMode`, one `Get-Variable`-guarded cache initialisation, function definitions and the literal `Register-ArgumentCompleter -Native` call, which is the shape the CompleterActions strict import grammar accepts.

## How completion works

1. `Get-OhMyPoshExecutable` resolves the executable once and caches the path.
2. `Complete-OhMyPosh` walks the command elements before the cursor. Tokens that match a known command extend the command path; tokens that start with `-` are flags, and a flag that takes a value (its help line names a type such as `string` or `int`) consumes the next token.
3. `Get-OhMyPoshHelp` runs `oh-my-posh <path> --help` with stdin closed for the current command path, parses the `Available Commands:`, `Flags:`, `Global Flags:` and `Usage:` sections, and caches the result in `$script:OhMyPoshCompletionCache.HelpByPath`.
4. If the word being completed is a value slot, the value provider answers: shell names for `--shell` (the positional values of `oh-my-posh init`), theme files and paths for `--config` and `--data`; other typed flags return nothing so PowerShell's default completion applies.
5. Otherwise a word starting with `-` lists the flags of the current path, and any other word lists the commands and positional values of the current path. Both take only the first operand slot: once an operand is given (`oh-my-posh auth copilot `, `oh-my-posh init pwsh `) nothing more is offered. A flag the current path does not list (`oh-my-posh auth --shell `) is treated as taking a value, so its slot offers nothing rather than commands or operands.

Prefix matching ignores case for commands, positional values, shell names and long flags (`CO` offers `config`, `--SH` offers `--shell`); short flags such as `-c` match ordinally so a case-distinct pair would never cross-match.

Results are deduplicated, so flags that appear in both the command and the global section are offered once.

## Representative validation scenarios

```powershell
oh-my-posh
oh-my-posh config
oh-my-posh get
oh-my-posh print --s
oh-my-posh --shell
oh-my-posh -c
oh-my-posh --shell=p
```

Expected behavior:

- the bare command lists all top-level commands from live help, including `antigravity`, `copilot` and `stream`
- `config` lists `dsc` and `export`; `get` lists its positional values
- `print --s` lists `--shell`, `--shell-version`, `--stack-count` and `--status` with their help text as tooltips
- `--shell` lists shell names; `-c` lists theme files followed by entries of the current directory
- the attached form keeps the `--shell=` prefix on each suggestion

## Dependencies or external command expectations

- `oh-my-posh` on `PATH` for live help; without it the static fallback covers the top-level commands, global flags and the `init` shell names only
- `$env:POSH_THEMES_PATH` for theme-file suggestions; when it is unset only ordinary paths are offered

## Limitations / notes

- The first completion for each command path spawns the executable once; later completions on that path are served from the cache for the session.
- Value slots other than `--shell`, `--config` and `--data` have no value provider and defer to PowerShell's default completion.
- Positional values are read from the bracketed alternation in the `Usage:` line, or from `- name: description` body bullets when the line has a single `[placeholder]`; commands whose help publishes neither offer no positional values.
