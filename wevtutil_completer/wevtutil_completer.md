# wevtutil completer

## What it completes / overview

`wevtutil_completer.ps1` registers a native PowerShell completer for `wevtutil` and `wevtutil.exe`.

The script combines:

- a static catalog of canonical commands, aliases, command-specific options, value hints, and path-like options,
- dynamic discovery of log names from `wevtutil.exe el`,
- dynamic discovery of publisher names from `wevtutil.exe ep`,
- and lightweight caching to avoid rerunning those discovery commands on every tab press.

## Registration and command names

The script registers a native completer for:

- `wevtutil`
- `wevtutil.exe`

Registration is done with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'wevtutil', 'wevtutil.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Wevtutil -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

## How completion works

### 1. Static catalog initialization

On first use, `Initialize-WevtutilCompletionCatalog` creates a script-scoped catalog with:

- command aliases,
- top-level command suggestions,
- per-command option lists,
- per-command value hints,
- path-taking option prefixes,
- cached log names,
- cached publisher names.

### 2. Active command detection

The completer examines tokens before the cursor and resolves any command alias to its canonical command name.

Example aliases handled by the script include:

- `el` / `enum-logs`
- `gl` / `get-log`
- `sl` / `set-log`
- `ep` / `enum-publishers`
- `gp` / `get-publisher`
- `im` / `install-manifest`
- `um` / `uninstall-manifest`
- `qe` / `query-events`
- `gli` / `get-loginfo`
- `epl` / `export-log`
- `al` / `archive-log`
- `cl` / `clear-log`

### 3. Inline `/option:value` handling

When the current token looks like `/name:valuePrefix`, the script:

- detects the option prefix,
- checks whether that option has enumerated value hints for the active command,
- otherwise checks whether that option expects a filesystem path on the active command (the tables are keyed per verb because `sl /c:` is a config file while `qe /c:` is an event count),
- otherwise returns the option's placeholder (`/q:<xpath>`, `/ms:<n>`, `/r:<computer>`, ...),
- and returns completion results in the same inline `/option:value` form; an `/option:` word never falls through to option-name completion.

### 4. Positional argument detection

For commands that expect a positional value, the script figures out what kind of positional argument is still missing.

That logic is context-sensitive. For example, it checks whether options such as `/lf:true` or `/sq:true` are already present before deciding whether a positional argument should be treated as a log name, log file, or structured query file.

### 5. Dynamic caching

The script caches these dynamic results for 120 seconds:

- log names from `wevtutil.exe el`
- publisher names from `wevtutil.exe ep`

This keeps completion responsive while still updating reasonably often.

## Key completion behaviors / supported values

### Top-level command completion

Before a command is selected, the completer offers the command and alias list above. If the current token starts with `/`, it only offers `/?`.

### Command-specific option completion

After a command is selected, the completer offers the hard-coded option set for that command.

The catalog includes these command-specific switch families:

| Command | Option coverage in the script |
| --- | --- |
| `el` | common remote/auth/unicode options plus `/?` |
| `gl` | `/f:`, `/format:` plus common options |
| `sl` | log configuration switches such as `/e:`, `/q:`, `/fm:`, `/i:`, `/lfn:`, `/rt:`, `/ab:`, `/ms:`, `/l:`, `/k:`, `/ca:`, `/c:` plus common options |
| `ep` | common remote/auth/unicode options plus `/?` |
| `gp` | `/ge:`, `/gm:`, `/f:` plus common options |
| `im` | manifest/resource/message/parameter file options plus unicode options and `/?` |
| `um` | unicode options and `/?` |
| `qe` | `/lf:`, `/sq:`, `/q:`, `/bm:`, `/sbm:`, `/rd:`, `/f:`, `/l:`, `/c:`, `/e:` plus common options |
| `gli` | `/lf:` plus common options |
| `epl` | `/lf:`, `/sq:`, `/q:`, `/ow:` plus common options |
| `al` | `/l:` plus common options |
| `cl` | `/bu:` plus common options |

Common remote/auth/unicode options are:

- `/r:` / `/remote:`
- `/u:` / `/username:`
- `/p:` / `/password:`
- `/a:` / `/authentication:`
- `/uni:` / `/unicode:`
- `/?` where applicable

### Enumerated value hints

The script has explicit value completion for these option groups.

#### Common values

- `/a:` and `/authentication:` → `Default`, `Negotiate`, `Kerberos`, `NTLM`
- `/uni:` and `/unicode:` → `true`, `false`

#### `gl`

- `/f:` and `/format:` → `XML`, `Text`

#### `sl`

- `/e:` and `/enabled:` → `true`, `false`
- `/q:` and `/quiet:` → `true`, `false`
- `/i:` and `/isolation:` → `system`, `application`, `custom`
- `/rt:` and `/retention:` → `true`, `false`
- `/ab:` and `/autobackup:` → `true`, `false`
- `/l:` and `/level:` → `0` to `5`

#### `gp`

- `/ge:` and `/getevents:` → `true`, `false`
- `/gm:` and `/getmessage:` → `true`, `false`
- `/f:` and `/format:` → `XML`, `Text`

#### `qe`

- `/lf:` and `/logfile:` → `true`, `false`
- `/sq:` and `/structuredquery:` → `true`, `false`
- `/rd:` and `/reversedirection:` → `true`, `false`
- `/f:` and `/format:` → `XML`, `Text`, `RenderedXml`

#### `gli`

- `/lf:` and `/logfile:` → `true`, `false`

#### `epl`

- `/lf:` and `/logfile:` → `true`, `false`
- `/sq:` and `/structuredquery:` → `true`, `false`
- `/ow:` and `/overwrite:` → `true`, `false`

### Dynamic log and publisher completion

The script dynamically completes:

- log names for commands such as `gl`, `sl`, `cl`, and for `qe`/`gli`/`epl` when they expect a log name,
- publisher names for `gp`.

These values come directly from `wevtutil.exe` at runtime.

### Placeholder values

Value-bearing options without an enum or a path return a placeholder in the same inline form:

- common: `/r:<computer>`, `/u:<username>`, `/p:<password>`
- `sl`: `/fm:<n>`, `/ms:<n>`, `/k:<keyword-mask>`, `/ca:<sddl>`
- `qe`: `/q:<xpath>`, `/l:<locale>`, `/c:<n>`, `/e:<root-element>`
- `epl`: `/q:<xpath>`
- `al`: `/l:<locale>`

### Filesystem-aware completion

The script treats several inline options as path-like on the verbs that define them and completes them with `Get-ChildItem`, including extension filtering where the implementation defines one. A typed trailing `\` lists that directory, and completions keep the typed parent (relative paths stay relative).

Path-aware options include:

- `sl`: `/c:` and `/config:` → `.xml`; `/lfn:` and `/logfilename:` → `.etl`, `.evt`, `.evtx`, `.log`
- `im`: `/rf:` and `/resourcefilepath:`, `/mf:` and `/messagefilepath:`, `/pf:` and `/parameterfilepath:`
- `qe`: `/bm:` and `/bookmark:` → `.xml`; `/sbm:` and `/savebookmark:` → `.xml`
- `cl`: `/bu:` and `/backup:` → `.evtx`

### Positional argument completion

The script also completes positional arguments based on command context.

| Command | Positional behavior implemented |
| --- | --- |
| `gl` | first positional argument is a log name |
| `sl` | first positional argument is a log name unless `/c` or `/config` is already present |
| `gp` | first positional argument is a publisher name |
| `im` / `um` | first positional argument is a manifest file (`.man` or `.xml`) |
| `qe` | first positional argument is a log name by default, a log file when `/lf:true` is set, or a structured query file when `/sq:true` is set |
| `gli` | first positional argument is a log name by default, or a log file when `/lf:true` is set |
| `epl` | first positional argument is a log name by default, a log file when `/lf:true` is set, or a structured query file when `/sq:true` is set; second positional argument is an `.evtx` target file |
| `al` | first positional argument is a log file |
| `cl` | first positional argument is a log name |

## Dependencies or external command expectations

This completer expects `wevtutil.exe` to be available. Dynamic completion depends on:

- `wevtutil.exe el`
- `wevtutil.exe ep`

If `wevtutil.exe` is not available, the dynamic log and publisher caches stay empty.

## Usage / loading example

Dot-source the script:

```powershell
. .\wevtutil_completer.ps1
```

Example completion scenarios:

```powershell
wevtutil <TAB>
wevtutil gl <TAB>
wevtutil gl /f:<TAB>
wevtutil gp <TAB>
wevtutil qe /sq:true <TAB>
wevtutil cl /bu:C:\Logs\<TAB>
```

## Limitations / notes

- The script is designed around `wevtutil`'s inline `/option:value` style; value completion is implemented for that form.
- Dynamic discovery is limited to log names and publisher names.
- Filesystem completion only applies to options and positional arguments that the script explicitly marks as path-like.
- Log and publisher caches refresh every 120 seconds rather than on every completion request.
- The command and option catalog is source-defined in the script, so it will not automatically follow future `wevtutil` feature additions unless the file is updated.

