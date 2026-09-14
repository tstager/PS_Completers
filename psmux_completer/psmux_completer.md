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
Register-ArgumentCompleter -Native -CommandName @('psmux', 'psmux.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Psmux -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

## Supported completion behavior

- Root completion suggests the documented session, window, pane, copy-buffer, key-binding, configuration, layout, and display commands, including aliases like `new`, `attach`, `ls`, `splitw`, and `selectl`, plus `kill-server` and `detach-client`/`detach`.
- Global options such as `-f`, `-L`, `-S`, and `-t` are available from the root and from subcommands. A documented command without its own option table (for example `ls` or `kill-window`) offers only the root switches after the command word.
- Option tokens match case-sensitively, so `new-session -s` (session name) never binds to the root `-S` (socket path).
- `new-session -s` / `new -s` and the session-targeted flags `attach-session -t`, `kill-session -t`, `switch-client -t` and `detach-client -s` offer local session names when `psmux ls` succeeds (stdin closed), plus a `<session-name>` placeholder.
- `detach-client` offers `-t <client>`, `-s <session>`, `-a` and `-P`; `bind-key -T` offers the key tables `prefix`, `root`, `copy-mode` and `copy-mode-vi`.
- `split-window -c`, `new-window -c`, and `source-file` complete filesystem paths.
- `select-layout` suggests the built-in presets: `even-horizontal`, `even-vertical`, `main-horizontal`, `main-vertical`, and `tiled`.
- `set-option` suggests documented option names and value hints for common booleans and enums such as `mode-keys`, `status-position`, `cursor-style`, and `bell-action`; every `*-style` option (and `status-bg`/`status-fg`) completes the documented style grammar (`fg=`/`bg=` followed by a colour, `bold`, `dim`, `underscore`, `italics`, `reverse`, named colours, `colour0`-`colour255`, `#RRGGBB`) one comma-separated segment at a time.
- `send-keys` offers key names including `Enter`, `Escape`, arrow and navigation keys, `C-`/`M-` chords and `F1`-`F12`; a value consumed by `-t` is not counted as the key operand.
- `display-message` offers every documented format variable (`#S`, `#W`, `#I`, `#F`, `#P`, `#T`, `#D`, `#H`, `#h`) and the conditional, comparison, substitution, truncation, basename, dirname and literal forms.
- After the documented `--` pass-through (`new-session -- <cmd>`, `new-window -- <cmd>`) the completer offers executable names.

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
