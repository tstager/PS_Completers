# schtasks completer

## What it completes / overview

`schtasks_completer.ps1` registers a native argument completer for `schtasks` and `schtasks.exe`.

It is primarily help-driven: the script parses `schtasks.exe /?` and subcommand help text to discover top-level subcommands and per-subcommand option tokens. It supplements that with targeted value completion for common option values, task names, and paths.

## Registration and command names

The script ends by calling:

```powershell
Register-ArgumentCompleter -Native -CommandName 'schtasks', 'schtasks.exe' -ScriptBlock { ... }
```

Load it into the current session with:

```powershell
. .\schtasks_completer.ps1
```

## How completion works

### Initialization

On first use, the script initializes `$script:SchtasksCompletionCatalog` by:

- running `schtasks.exe /?`
- parsing the `Parameter List:` section to discover top-level tokens
- treating the discovered top-level tokens except `/?` as subcommands
- running `schtasks.exe <subcommand> /?` for each discovered subcommand
- parsing each subcommand help page to collect its option tokens
- loading a small static table of value hints for selected options

This initialization happens once per session.

### Subcommand-aware completion

The completer inspects command tokens to determine the active subcommand. Before any subcommand is chosen, it offers:

- discovered subcommands
- `/?`

After a subcommand is present, it offers only the option tokens collected for that subcommand.

### Value-aware completion

When the previous token is an option that expects a value, the script switches to value completion instead of more option names.

The script has dedicated handling for:

- `/TN` task names
- `/TR` path completion
- `/XML` path completion restricted to `.xml` files
- several static enumerated value sets

### Quoting behavior

Path and task-name suggestions are quoted when needed for spaces, or when the current input already started with a quote.

## Key completion behaviors / supported values

### Top-level and subcommand options

Subcommands and option tokens are discovered from the installed `schtasks.exe` help text, not hardcoded command maps.

### Static value hints

The script provides explicit value suggestions for these options:

- `/SC`: `MINUTE`, `HOURLY`, `DAILY`, `WEEKLY`, `MONTHLY`, `ONCE`, `ONSTART`, `ONLOGON`, `ONIDLE`, `ONEVENT`
- `/FO`: `TABLE`, `LIST`, `CSV`
- `/RL`: `LIMITED`, `HIGHEST`
- `/D`: `MON`, `TUE`, `WED`, `THU`, `FRI`, `SAT`, `SUN`, `*`
- `/M`: `JAN`, `FEB`, `MAR`, `APR`, `MAY`, `JUN`, `JUL`, `AUG`, `SEP`, `OCT`, `NOV`, `DEC`, `*`
- `/XML`: `ONE`
- `/RU`: `SYSTEM`, `"NT AUTHORITY\SYSTEM"`, `"NT AUTHORITY\LOCALSERVICE"`, `"NT AUTHORITY\NETWORKSERVICE"`

### Task-name completion

For `/TN`, the script runs:

```powershell
schtasks.exe /Query /FO CSV
```

It extracts the first CSV column as task names, sorts them uniquely, and caches them for 60 seconds.

Task-name suggestions are only returned for `/TN` when the active subcommand is **not** `/Create`.

### Path completion

The completer uses filesystem completion for:

- `/TR` with general file or directory suggestions
- `/XML` with suggestions limited to `.xml` files and directories

### Token parsing behavior

The script derives the current token from the command line text so it can continue suggesting values correctly when the cursor is on a partially typed token or after trailing whitespace.

## Dependencies or external command expectations

This completer expects:

- `schtasks.exe` to be available, otherwise completion is empty
- access to `schtasks.exe /?` and `schtasks.exe <subcommand> /?` for initialization
- access to `schtasks.exe /Query /FO CSV` for task-name completion
- local filesystem access for `/TR` and `/XML` path suggestions

## Usage / loading example

```powershell
. .\schtasks_completer.ps1

schtasks <TAB>
schtasks /Create <TAB>
schtasks /Create /SC <TAB>
schtasks /Query /TN <TAB>
schtasks /Create /XML <TAB>
```

## Limitations / notes

- The script only provides explicit value suggestions for the options listed in its static hint table.
- `/TN` completion is intentionally skipped for `/Create`.
- Path completion is only specialized for `/TR` and `/XML`.
- The available subcommands and option tokens depend on the help text exposed by the installed `schtasks.exe`.

