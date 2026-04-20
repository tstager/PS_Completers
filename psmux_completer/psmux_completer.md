# psmux completer

## What it completes / overview

`psmux_completer.ps1` registers a native PowerShell completer for `psmux` and `psmux.exe`.

The completer is static-first, authored from the local `psmux.exe --help` output. It covers the documented command families, common aliases, global options, and the most prominent value-bearing flags.

## Registration and command names

The script registers:

- `psmux`
- `psmux.exe`

with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('psmux', 'psmux.exe') -ScriptBlock { ... }
```

## Supported completion behavior

- Root completion suggests the documented session, window, pane, copy-buffer, key-binding, configuration, layout, and display commands, including aliases like `new`, `attach`, `ls`, `splitw`, and `selectl`.
- Global options such as `-f`, `-L`, `-S`, and `-t` are available from the root and from subcommands.
- Session-targeted flags such as `attach-session -t`, `kill-session -t`, and `switch-client -t` offer local session names when `psmux ls` succeeds, plus safe placeholders.
- `split-window -c`, `new-window -c`, and `source-file` complete filesystem paths.
- `select-layout` suggests the built-in presets: `even-horizontal`, `even-vertical`, `main-horizontal`, `main-vertical`, and `tiled`.
- `set-option` suggests documented option names and value hints for common booleans and enums such as `mode-keys`, `status-position`, `cursor-style`, and `bell-action`.
- `send-keys` offers common key names like `Enter`, `Escape`, `Tab`, and arrow keys.

## Dependencies or external command expectations

The completer was authored from the local `psmux.exe --help` output. During completion it may safely call `psmux ls` to offer local session-name hints. It does not enumerate remote systems or perform network operations.

## Usage / loading example

```powershell
. .\psmux_completer\psmux_completer.ps1
```

Example scenarios:

```powershell
psmux <TAB>
psmux new -s <TAB>
psmux attach -t <TAB>
psmux split-window -c <TAB>
psmux select-layout <TAB>
psmux set -g <TAB>
```

## Limitations / notes

- The command grammar is static rather than recursively queried from the runtime, so new upstream subcommands will require script updates.
- Several free-form command tails such as `run-shell`, `pipe-pane`, and `if-shell` use executable-name hints and placeholders instead of shell parsing.
- Target suggestions are intentionally conservative examples plus local session names when available.
