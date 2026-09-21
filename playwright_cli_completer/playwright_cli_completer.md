# playwright-cli completer

## What it completes / overview

`playwright_cli_completer.ps1` registers a native PowerShell argument completer for:

- `playwright-cli`
- `playwright-cli.cmd`
- `playwright-cli.ps1`

The implementation is **static-first with a catalog overlay**: the command table is encoded in the script, and when `@playwright/cli` is installed its shipped `help.json` catalog is read once (no process spawn) to add commands and flags the table does not know and to drop entries the tool no longer has.

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

### 1. Command and option metadata

`Get-PlaywrightCliMetadata` lazily creates the command catalog the first time completion runs. It stores:

- all 102 top-level commands of `@playwright/cli` 0.1.21 and their descriptions (the tool has no `help` verb, only the global `--help [command]`)
- positional value kinds for each command
- option tables for each command
- global options `--help`, `--json`, `--raw`, `--version`, and `-s=`
- small enum tables for browsers, install channels, SameSite values, network state, video sizes, screenshot image formats, the `video-show-actions` position/cursor values, and the `set-color-scheme`, `set-reduced-motion`, `set-forced-colors`, `set-contrast` and `set-media` emulation values

`Get-PlaywrightCliHelpCatalog` resolves `playwright-cli` with `Get-Command`, walks from the launcher to `node_modules/@playwright/cli/node_modules/playwright-core/lib/tools/cli-client/help.json` (or the hoisted `node_modules/playwright-core/...` location), and parses it with `ConvertFrom-Json`. `Merge-PlaywrightCliHelpCatalog` then takes the catalog's command list and per-command flag map as the surface, keeps the static value kinds and wording for entries it knows, types unknown string flags as generic values and unknown boolean flags as switches, and omits static commands the catalog no longer lists. When the tool or the file is absent the static table serves on its own.

### 2. Command-context parsing

`Complete-PlaywrightCli` walks the tokens left of the cursor (the element under the cursor is the word being completed and anything right of it is ignored, so completing inside an earlier token works) and tracks:

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
- `screenshot --type` -> `png`, `jpeg`, `webp`
- `video-show-actions --position` -> `top-left` ... `bottom-right`; `--cursor` -> `pointer`, `none`
- `install-browser` -> `chromium`, `chromium-headless-shell`, `chrome`, the `-beta`/`-dev`/`-canary` channels, `firefox`, `webkit`, `msedge`

For the global session selector, root completion suggests `-s=` to match the CLI usage string, and native value completion is available after `playwright-cli -s ` in real PowerShell.

## Coverage notes

The script intentionally covers the visible runtime help surface for the installed `playwright-cli` command, including:

- core browser commands like `open`, `attach`, `goto`, `click`, `fill`, and `snapshot`
- navigation, keyboard, and mouse commands
- save/output commands like `screenshot` and `pdf`
- storage commands like `cookie-set`, `localstorage-set`, and `sessionstorage-set`
- network commands like `requests`, `request`, `request-headers`, `response-body`, `route`, `unroute`, and `network-state-set`
- devtools/test-flow commands like `console`, `run-code`, `recording-start`, `video-start`, `video-show-actions`, `show`, `pause-at`, `generate-locator`, and `highlight`
- workspace/session commands like `install`, `install-browser`, `config-print`, `list`, `close-all`, `kill-all`, and `tray`

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

