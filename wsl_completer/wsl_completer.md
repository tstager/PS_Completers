# wsl completer

## What it completes / overview

`wsl_completer.ps1` registers a native PowerShell completer for `wsl` and `wsl.exe`.

It is a static, mode-aware completer. The top-level switch list is authored from `wsl --help`; each mode switch has its own sub-option group; enum-valued options complete their documented values; and distribution names are discovered live from the installed WSL configuration.

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `wsl`, `wsl.exe`
- Entry point: `Complete-WslNative`

```powershell
Register-ArgumentCompleter -Native -CommandName @('wsl', 'wsl.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-WslNative -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

The completer returns nothing when `wsl` is not on `PATH`.

## How completion works

1. The command line is tokenized and the completed argument tokens and the previous token are derived, taking a trailing space into account.
2. The first argument token that is a mode switch selects the mode: `--install`, `--mount`, `--export`, `--import`, `--shutdown`, `--update`, `--list`/`-l` or `--manage`.
3. Value slots are answered first:
   - distribution names after `-d`/`--distribution`, `--export`, `--manage`, `--set-default`/`-s`, `--set-version`, `--terminate`/`-t` and `--unregister`, from `wsl -l -q`
   - distribution ids after `--distribution-id`, from the registry
   - `1`/`2` after `--version` and `--set-default-version`, and as the second operand of `--set-version <Distro>`
   - `standard`/`login`/`none` after `--shell-type`
   - `true`/`false` after `--set-sparse`, and after `-s` inside `--manage`
   - `tar`/`tar.gz`/`tar.xz`/`vhd` after `--format`; `ext4`/`drvfs` after `--type`; `root` after `-u`/`--user`
   - path and free-text slots (`--from-file`, `--location`, `--move`, `--cd`, `--name`, the file operands of `--export`/`--import`, the disk operand of `--mount`) return nothing so PowerShell's default completion applies
4. Inside a mode, the mode's sub-options are offered: for example `--install` offers `--no-launch`, `--web-download`, `--no-distribution`, `--enable-wsl1`, `--from-file`, `--name`, `--location`, `--version` and `--legacy`; `--manage <Distro>` offers `--move`, `--resize`, `--set-default-user`, `--set-sparse` and `-s`.
5. Otherwise the top-level switch list is offered.

## Representative validation scenarios

```powershell
wsl --install
wsl --shell-type
wsl --manage
wsl --manage Ubuntu -
wsl -l
wsl -d
wsl --set-version Ubuntu
```

Expected behavior:

- `--install ` lists the install sub-options
- `--shell-type ` lists `standard`, `login`, `none`
- `--manage ` lists the installed distributions; after a distribution its sub-options appear
- `-l ` lists the list sub-options; `-d ` lists distributions
- `--set-version Ubuntu ` lists `1` and `2`

## Dependencies or external command expectations

- `wsl` on `PATH`
- `wsl -l -q` for distribution names; an empty result yields no distribution suggestions
- `HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss` for distribution ids

## Limitations / notes

- The switch surface is authored, not parsed from `wsl --help`, because that help is printed in UTF-16 with embedded NULs.
- Command text after `-e`/`--exec` or `--` is not completed.
- Online distribution names for `--install` are not fetched; the sub-options are offered instead.
