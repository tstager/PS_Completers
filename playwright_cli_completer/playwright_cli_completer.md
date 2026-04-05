# playwright-cli completer

## What it completes / overview

`playwright_cli_completer.ps1` registers a native PowerShell argument completer for:

- `playwright-cli`
- `playwright-cli.cmd`
- `playwright-cli.ps1`

The implementation is **static-first** because the installed `playwright-cli` help surface is explicit and stable enough to encode directly without completion-time help parsing.

It covers:

- the full top-level `playwright-cli` command set shown by local `--help`
- command-specific options
- inline `--option=value` completion
- path completion for file and directory arguments
- enum/value hints for browsers, network state, SameSite, video size, and skills
- placeholder completions for free-form selectors, session names, URLs, code snippets, and other non-path slots

## Registration and command names

The script uses a single importer-safe registration:

```powershell
Register-ArgumentCompleter -Native -CommandName @('playwright-cli', 'playwright-cli.cmd', 'playwright-cli.ps1') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-PlaywrightCli -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

That keeps the top level compatible with `CompleterActions` `Import-CompleterScript`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter` call

There are no top-level assignments, loops, external command calls, or registration wrappers.

## How completion works

### 1. Static command and option metadata

`Get-PlaywrightCliMetadata` lazily creates the command catalog the first time completion runs. It stores:

- top-level commands and descriptions
- positional value kinds for each command
- option tables for each command
- global options such as `--help`, `--raw`, `--version`, and `-s=`
- small enum tables for browsers, SameSite values, network state, and video sizes

### 2. Command-context parsing

`Complete-PlaywrightCli` walks the already-entered tokens and tracks:

- the active command
- how many positional arguments were already consumed
- whether the previous option is waiting for a value
- whether the current token is using inline `--flag=value` syntax

That lets the completer switch between:

- root command completion
- option-name completion
- option-value completion
- positional placeholder or enum completion

### 3. Path-aware value completion

`Get-PlaywrightCliPathCompletions` uses PowerShell's filename completer so path-bearing slots behave like normal shell completion.

This is used for:

- `open --config`
- `open --profile`
- `attach --config`
- `snapshot --filename`
- `eval --filename`
- `screenshot --filename`
- `pdf --filename`
- `state-load`
- `state-save`
- `run-code --filename`
- `video-start`

### 4. Placeholder and enum values

For free-form non-path slots, the script returns explicit placeholders so PowerShell does not fall back to noisy filesystem completion.

Examples:

- `goto <TAB>` -> `https://`, `http://`
- `click <TAB>` -> `<target>`
- `attach -s=<TAB>` -> `<session>`
- `pause-at <TAB>` -> `<file>:<line>`

It also supplies concrete enums where the CLI help exposed useful fixed values, including:

- `open --browser` -> `chrome`, `firefox`, `webkit`, `msedge`
- `cookie-set --sameSite` -> `Strict`, `Lax`, `None`
- `network-state-set` -> `online`, `offline`
- `install --skills` -> `claude`, `agents`

For the global session selector, root completion suggests `-s=` to match the CLI usage string, and native value completion is available after `playwright-cli -s ` in real PowerShell.

## Coverage notes

The script intentionally covers the visible runtime help surface for the installed `playwright-cli` command, including:

- core browser commands like `open`, `attach`, `goto`, `click`, `fill`, and `snapshot`
- navigation, keyboard, and mouse commands
- save/output commands like `screenshot` and `pdf`
- storage commands like `cookie-set`, `localstorage-set`, and `sessionstorage-set`
- network commands like `route`, `unroute`, and `network-state-set`
- devtools/test-flow commands like `console`, `run-code`, `video-start`, and `pause-at`
- workspace/session commands like `install`, `install-browser`, `list`, `close-all`, and `kill-all`

The completer does **not** probe live browser sessions, tabs, selectors, cookies, or storage keys during completion. Those slots use placeholders instead of runtime enumeration.

## Validation expectations

Representative validation for this script should include:

- dot-sourcing the script in clean `pwsh -NoProfile`
- `Import-CompleterScript` against the repo copy of `CompleterActions`
- `TabExpansion2` checks for:
  - root command completion
- `playwright-cli --` global options
- `playwright-cli open --browser `
- `playwright-cli cookie-set --sameSite `
- `playwright-cli state-load `
- `playwright-cli -s `

