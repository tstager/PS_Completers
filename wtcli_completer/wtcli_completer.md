# wtcli completer

`wtcli_completer.ps1` registers a standalone native PowerShell completer for `wtcli` and `wtcli.exe`, the command-line client of the Windows Terminal Protocol shipped with [Intelligent Terminal](https://github.com/microsoft/intelligent-terminal) (the agent-focused Windows Terminal fork). It drives a running Terminal tmux-style: list windows, tabs, panes and profiles, open tabs and split panes, send keys, capture output, and publish or listen to agent events.

Completion follows the installed binary. Commands, aliases, options, value types and enums are parsed from `--help` and cached per subcommand. Window, tab, pane and profile values come from read-only `wtcli --json list-*` queries, and only inside an Intelligent Terminal pane.

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('wtcli', 'wtcli.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Wtcli -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

`wtcli.exe` is an app execution alias in `%LOCALAPPDATA%\Microsoft\WindowsApps` from the `Microsoft.IntelligentTerminal` package, so both the bare and the `.exe` name are registered.

## How completion works

- `wtcli --help` lists the subcommands with their aliases (`list-windows, lsw`, `split-pane, splitw`, `send-event, se`, ...) and the root options `--json`, `--skip-authenticate` and `-h` / `--help`. Aliases complete like their command, with an "Alias for" tooltip.
- `wtcli <command> --help` is read once per command, with stdin closed and a 3 second timeout. wtcli is a CLI11 program, so `--help` is handled while parsing and never runs the command. A failed help call is retried after 30 seconds; if wtcli is not installed, the root help of Intelligent Terminal 0.3.3083.0 embedded in the script is used and subcommands offer only `-h` / `--help`.
- CLI11 accepts root options only before the subcommand (`wtcli list-windows --json` is a parse error), so after a subcommand only that command's options are offered. Command and option names are case-sensitive: `split-pane -h` (help) and `-H` (horizontal) stay distinct.
- The help's type column decides which options take a value (`TEXT`, `INT`, `UINT`, `FLOAT`); flags such as `--background`, `--last-prompt`, `--raw` and `--existing-only` take none. Values complete in the separate form (`--direction up`), the attached form (`--direction=up`), after an alias (`splitw -d`), and after a flag cluster (`split-pane -Hd`).
- Enums are read from the help descriptions: `split-pane -d` / `--direction` gets `right`, `left`, `up`, `down`, `auto`; `set-env -s` / `--shell` gets `powershell`, `bash`, `cmd`.
- Settled words are walked with absolute `Extent.EndOffset` values, so completion works when `wtcli` is not the first statement on the line. `--` ends option parsing.

## Value slots

| Slot | Values |
| --- | --- |
| `-t` / `--target` (capture-pane, get-pane-context, pane-status, split-pane, kill-pane, send-keys, focus-pane, wait-for, listen), `send-event -p` / `--pane` | This pane's `$env:WT_SESSION`, then every pane's session GUID with window, tab, title and pid in the tooltip (live); otherwise `<session-guid>` |
| `-w` / `--window-id` (list-tabs, list-panes, new-tab) | Live window ids with title and focus; `new-tab` also offers `0` (the most recent window); otherwise `<window-id>` |
| `list-panes -t` / `--tab-id` | Live tab ids of the window named by `-w` on the line, or of every window; otherwise `<tab-id>` |
| `-p` / `--profile` (new-tab, split-pane) | Live profile names and `{GUID}`s from `list-profiles`, quoted as needed (`'Command Prompt'`); otherwise `<profile>` |
| `--agent-provider` | `copilot`, `claude`, `codex`, `gemini`, `opencode`, `antigravity` (`BuiltinNativeProfileAgents` in `src/cascadia/inc/AgentRegistry.h`), live agent-profile ids such as `custom:mine`, and `custom:<name>` |
| `agent-hook -c` / `--cli-source` | `copilot`, `claude`, `codex`, `gemini`, `opencode`, `antigravity` (the official `wt-agent-hooks` bundles) |
| `agent-hook -e` / `--event` | The hook topics: `agent.session.start`, `.end`, `.unbind`, `.renamed`, `agent.prompt.submit`, `agent.tool.starting`, `.finished`, `.failed`, `agent.stop`, `agent.subagent.stop`, `agent.notification`, `agent.error` |
| `send-event -e` / `--event` | The hook topics plus the `doc/specs/llm-agent-event-integration.md` types (`agent.started`, `agent.task.started`, `agent.task.completed`, `agent.tool.invoked`, `agent.tool.completed`, `agent.idle`), and `<event-type>` because Terminal passes any type through |
| `listen --event` | The same topics plus the trailing-wildcard filters `agent.*`, `agent.session.*`, `agent.tool.*`, `agent.task.*` |
| `listen --parent-pid` | This PowerShell's `$PID`, and `<pid>` |
| `new-tab -d` / `--cwd` | Directories only, quoted as one literal argument in the quote you typed; `<directory>` when there are none |
| `send-keys` keys | The tokens wtcli translates (`TranslateKeys` in `wtcli_functions.h`): `Enter`, `Space`, `Tab`, `Escape`, `BSpace`, `C-c`, `C-d`, `C-z`, `C-l`, and `C-a`..`C-z` once `C-` is typed; then `<text>`. With `--raw` the payload is literal, so only `<text>` |
| `publish` / `send-event` JSON | `<json>`; `publish --stdin` excludes the positional, so only options are offered |
| Other values | Placeholders: `<lines>`, `<chars>`, `<ms>`, `<seconds>`, `<fraction>`, `<command>`, `<title>`, `<token>` |

## Live values and why they are gated

wtcli finds Terminal through `WT_COM_CLSID`, which only an Intelligent Terminal pane sets, next to `WT_SESSION`. The list commands use normal COM activation (`doc/wtcli-commands.md`): run outside a pane with the CLSID inherited, they could start Terminal or a headless server. Completion must not do that, so live queries run only when both `WT_COM_CLSID` and `WT_SESSION` are set, the same gate the official hook bundles use. Elsewhere every live slot offers its placeholder, and `$env:WT_SESSION` is still offered for session slots when it is set.

Inside a pane:

- Queries are `wtcli --json list-windows`, `list-tabs -w <id>`, `list-panes -w <id> -t <id>` and `list-profiles`: read-only, with stdin closed and a 1.5 second timeout.
- `list-panes` covers one tab, so the session-GUID slot walks every window and tab, stopping after 2.5 seconds; the whole result is cached for 5 seconds. Window and tab lists are cached for 5 seconds and profiles for 30 seconds.
- A failed or malformed query (non-zero exit, timeout, output that is not the documented JSON) yields the placeholder and is not retried for 10 seconds, so a stopped server costs one Tab, not every Tab.
- Upstream `AGENTS.md` routes agent-requested Terminal mutations through the confirmation-gated session MCP path; the protocol server that answers wtcli (`TerminalPage.Protocol.cpp`) has no confirmation step, so these reads do not prompt.

## Safety

Completion never runs a command that changes Terminal state. It does not call `new-tab`, `split-pane`, `kill-pane`, `send-keys`, `focus-pane`, `wait-for`, `publish`, `send-event`, `agent-hook`, `listen`, `capture-pane`, `get-pane-context`, `get-settings`, `set-env` or `test-pipe`, and it does not read pane contents or settings.

## Version

Built against Intelligent Terminal 0.3.3083.0 (`wtcli.exe` has no `--version`; the package version comes from `Get-AppxPackage Microsoft.IntelligentTerminal`) and the upstream sources at `microsoft/intelligent-terminal` commit `47c9063` (`src/tools/wtcli/main.cpp`, `Formatting.cpp`, `wtcli_functions.h`). The completer follows live help, so new commands and options appear without a script change; only the value-slot overlays above are static.
