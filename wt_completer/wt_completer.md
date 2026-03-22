# wt completer

## What it completes / overview

`wt_completer.ps1` registers a native PowerShell completer for Windows Terminal (`wt` / `wt.exe`).

The implementation is entirely source-defined in the script. It does not call `wt --help` or query Windows Terminal profiles at runtime. Instead, it uses static tables for:

- top-level options,
- supported subcommands and aliases,
- subcommand-specific options,
- direction values for pane-navigation commands.

## Registration and command names

The script registers a native completer for:

- `wt`
- `wt.exe`

Registration is done with:

```powershell
Register-ArgumentCompleter -Native -CommandName wt, wt.exe -ScriptBlock $WtCompleter
```

Before producing results, the script accepts either `wt.exe` or `wt` as present on `PATH`.

## How completion works

### 1. Static option and subcommand tables

The script defines separate tables for:

- top-level options,
- `new-tab` options,
- `split-pane` options,
- `focus-tab` options,
- `move-pane` options,
- `focus-pane` options,
- direction values,
- subcommand names and aliases.

Each entry includes completion text, display text, result type, and tooltip text.

### 2. Token parsing and context selection

The completer tokenizes the command line prefix with a regular expression, then determines:

- the currently typed prefix,
- the previous token,
- the active subcommand, if any,
- whether the previous token expects a value,
- whether the current completion request is for an option or a non-option value.

Aliases such as `nt` and `sp` are normalized through `$subcommandMap`.

### 3. Context-specific completion output

The script then chooses one of these behaviors:

- top-level options only,
- top-level options plus subcommands,
- subcommand-specific options,
- direction values for pane-navigation commands,
- no suggestions when the implementation knows the current position should contain a free-form value.

## Key completion behaviors / supported values

### Top-level options

The script offers these top-level options:

- `-h`, `--help`
- `-v`, `--version`
- `-M`, `--maximized`
- `-F`, `--fullscreen`
- `-f`, `--focus`
- `--pos`
- `--size`
- `-w`, `--window`
- `-s`, `--saved`

### Supported subcommands and aliases

The script includes these subcommands:

- `new-tab`, `nt`
- `split-pane`, `sp`
- `focus-tab`, `ft`
- `move-focus`, `mf`
- `move-pane`, `mp`
- `swap-pane`
- `focus-pane`, `fp`
- `x-save`

### `new-tab` option coverage

For `new-tab` / `nt`, the script offers:

- `-p`, `--profile`
- `--sessionId`
- `-d`, `--startingDirectory`
- `--title`
- `--tabColor`
- `--suppressApplicationTitle`
- `--useApplicationTitle`
- `--colorScheme`
- `--appendCommandLine`
- `--inheritEnvironment`
- `--reloadEnvironment`

### `split-pane` option coverage

For `split-pane` / `sp`, the script offers all `new-tab` options plus:

- `-H`, `--horizontal`
- `-V`, `--vertical`
- `-s`, `--size`
- `-D`, `--duplicate`

### `focus-tab` option coverage

For `focus-tab` / `ft`, the script offers:

- `-t`, `--target`
- `-n`, `--next`
- `-p`, `--previous`

### `move-pane` option coverage

For `move-pane` / `mp`, the script offers:

- `-t`, `--tab`

### `focus-pane` option coverage

For `focus-pane` / `fp`, the script offers:

- `-t`, `--target`

### Direction value completion

For `move-focus` / `mf` and `swap-pane`, the script offers these direction values:

- `left`
- `right`
- `up`
- `down`
- `previous`
- `nextInOrder`
- `previousInOrder`
- `first`

### Value-taking options without enumerated suggestions

The script explicitly knows that many options take values, including:

- `--pos`, `--size`, `-w`, `--window`, `-s`, `--saved`
- `-p`, `--profile`, `--sessionId`, `-d`, `--startingDirectory`, `--title`, `--tabColor`, `--colorScheme`
- `-t`, `--target`, `--tab`

When the current argument position is one of these value slots, the completer usually returns no guesses instead of inventing values.

## Dependencies or external command expectations

This completer expects either `wt.exe` or `wt` to be available via `Get-Command`.

Unlike some other completers in the repository, it does not depend on runtime help parsing or external discovery commands after the initial command-availability check.

## Usage / loading example

Dot-source the script:

```powershell
. .\wt_completer.ps1
```

Example completion scenarios:

```powershell
wt <TAB>
wt --<TAB>
wt new-tab --<TAB>
wt split-pane --<TAB>
wt move-focus <TAB>
wt swap-pane <TAB>
```

## Limitations / notes

- The completer is static; it will not automatically learn new Windows Terminal options or subcommands.
- It does not enumerate profile names, window IDs, directories, colors, titles, or numeric values.
- For most value-taking options, the script intentionally suppresses suggestions rather than returning placeholders.
- `move-focus` and `swap-pane` are the only subcommands in this file that return non-option argument values.
- The script models a single active subcommand context and does not attempt richer parsing of compound Windows Terminal command lines.

