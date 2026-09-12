# wt completer

## What it completes / overview

`wt_completer.ps1` registers a native PowerShell completer for Windows Terminal (`wt` / `wt.exe`).

The option and subcommand tables are defined in the script. Profile names and color scheme names are read from the Windows Terminal settings file at completion time, so `-p`/`--profile` and `--colorScheme` complete the entries that exist on the machine.

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `wt`, `wt.exe`
- Entry point: `Complete-WtNative`

```powershell
Register-ArgumentCompleter -Native -CommandName @('wt', 'wt.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-WtNative -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

The completer returns nothing when neither `wt.exe` nor `wt` is on `PATH`.

## How completion works

### 1. Tables

The script defines top-level options, `new-tab` options, `split-pane` extras, `focus-tab`, `move-pane` and `focus-pane` options, direction values, and the subcommand list with aliases (`nt`, `sp`, `ft`, `mf`, `mp`, `fp`). Each entry carries completion text, display text, result type and tooltip.

### 2. Tokenizing and context

The cursor is rebased to the command's start offset, so completion works when `wt` is not the first statement on the line. The completed tokens are scanned to find the active subcommand and whether the previous token expects a value. A `;` or `` `; `` token, or a token ending in `;`, resets the subcommand context, so in `wt nt `; sp -` the options offered belong to `split-pane`.

### 3. Output by context

- No subcommand: top-level options plus the `new-tab` options (which `wt` accepts before any subcommand) plus subcommand names.
- `move-focus` / `swap-pane`: direction values.
- Other subcommands: that subcommand's options.
- A value slot after `-p`/`--profile` lists profile names; after `--colorScheme` it lists scheme names; names containing spaces are quoted. Other value slots return nothing so PowerShell's default completion applies.

## Key completion behaviors / supported values

- Top-level options: `-h`/`--help`, `-v`/`--version`, `-M`/`--maximized`, `-F`/`--fullscreen`, `-f`/`--focus`, `--pos`, `--size`, `-w`/`--window`, `-s`/`--saved`
- Subcommands: `new-tab`/`nt`, `split-pane`/`sp`, `focus-tab`/`ft`, `move-focus`/`mf`, `move-pane`/`mp`, `swap-pane`, `focus-pane`/`fp`, `x-save`
- `new-tab` options: `-p`/`--profile`, `--sessionId`, `-d`/`--startingDirectory`, `--title`, `--tabColor`, `--suppressApplicationTitle`, `--useApplicationTitle`, `--colorScheme`, `--appendCommandLine`, `--inheritEnvironment`, `--reloadEnvironment`
- `split-pane` adds `-H`/`--horizontal`, `-V`/`--vertical`, `-s`/`--size`, `-D`/`--duplicate`
- `focus-tab`: `-t`/`--target`, `-n`/`--next`, `-p`/`--previous`; `move-pane`: `-t`/`--tab`; `focus-pane`: `-t`/`--target`
- Direction values: `left`, `right`, `up`, `down`, `previous`, `nextInOrder`, `previousInOrder`, `first`

## Representative validation scenarios

```powershell
wt -p
wt nt --colorScheme
wt nt `; sp -
Set-Location C:\; wt ft
wt move-focus
```

Expected behavior:

- `-p ` lists the profiles from settings.json, quoting names with spaces
- `nt --colorScheme ` lists the color schemes from settings.json
- after `` `; `` the `split-pane` options are offered
- `ft` completes when `wt` follows another statement on the line
- `move-focus ` lists the direction values

## Dependencies or external command expectations

- `wt.exe` or `wt` on `PATH`
- `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` and the Preview equivalent for profile and scheme names; both are read once per session and unioned

## Limitations / notes

- The option and subcommand tables are authored, so a new Windows Terminal option must be added by hand.
- Window ids, directories, colors, titles and sizes have no value provider.
