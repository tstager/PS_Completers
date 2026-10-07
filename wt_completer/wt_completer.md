# wt completer

## What it completes / overview

`wt_completer.ps1` registers a native PowerShell completer for Windows Terminal (`wt` / `wt.exe`).

The option and subcommand tables are defined in the script. Profile names are read from the Windows Terminal settings file at completion time. `--colorScheme` completes the built-in schemes shipped with Windows Terminal, the settings `schemes` array, and every scheme a profile (or `profiles.defaults`) references, including both halves of a `{ "light", "dark" }` pair.

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

Words come from the parser's command elements, not a whitespace split: a quoted value such as `"Windows PowerShell"` is one word, and the element that contains the cursor (cut at the cursor) is the word being completed, so completion works mid-line and when `wt` is not the first statement on the line. An unterminated quote runs to the cursor; its opening quote is stripped before matching. The completed tokens are scanned to find the active subcommand and whether the previous token expects a value. A `;` or `` `; `` token, or a token ending in `;`, resets the subcommand context, so in `wt nt `; sp -` the options offered belong to `split-pane`. The first positional word at the top level (the implicit `new-tab`) or after `new-tab`/`split-pane` options starts the child commandline: from there to the next `;` the completer returns nothing, so `wt nt pwsh -` does not offer `wt` options. Value-taking options are skipped together with their value before that decision, including the top-level `--pos`, `--size`, `-w`/`--window` and `-s`/`--saved` when repeated after `new-tab`/`split-pane`, so `wt nt --pos 1,1 -` and `wt nt -w 0 -` still offer the `new-tab` options.

### 3. Output by context

- No subcommand: top-level options plus the `new-tab` options (which `wt` accepts before any subcommand) plus subcommand names.
- `move-focus` / `swap-pane`: direction values.
- Other subcommands: that subcommand's options.
- A value slot after `-p`/`--profile` lists profile names; after `--colorScheme` it lists scheme names; after `-w`/`--window` it lists the reserved window ids `new`, `last`, `-1` and `0`. The attached form `--option=value` completes the value for the same options and keeps `--option=` in the inserted text. A name containing whitespace or an argument-mode metacharacter is quoted: in the quote the user typed, or single quotes when none was typed. Other value slots return nothing so PowerShell's default completion applies.

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
wt -p "Windows Pow
wt --profile=Win
wt nt --colorScheme
wt nt `; sp -
Set-Location C:\; wt ft
wt move-focus
```

Expected behavior:

- `-p ` lists the profiles from settings.json, quoting names with spaces; `-p "Windows Pow` completes to `"Windows PowerShell"`; `--profile=Win` completes to `--profile='Windows PowerShell'`
- `nt --colorScheme ` lists the built-in schemes plus the schemes defined or referenced in settings.json
- after `` `; `` the `split-pane` options are offered
- `ft` completes when `wt` follows another statement on the line
- `move-focus ` lists the direction values
- `-w ` lists `new`, `last`, `-1`, `0`; `--window=l` completes to `--window=last`
- `nt pwsh -` returns nothing, because `-` belongs to the child commandline

## Dependencies or external command expectations

- `wt.exe` or `wt` on `PATH`
- `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` and the Preview equivalent for profile and scheme names; both are read once per session and unioned. The built-in scheme names are a static list taken from the 1.25/1.26 package `defaults.json`

## Limitations / notes

- The option and subcommand tables are authored, so a new Windows Terminal option must be added by hand.
- Window names and live window ids beyond the reserved values, directories, colors, titles and sizes have no value provider.
