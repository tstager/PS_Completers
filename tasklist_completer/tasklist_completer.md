# tasklist completer

## What it completes / overview

`tasklist_completer.ps1` registers a native argument completer for `tasklist` and `tasklist.exe`.

It parses `tasklist.exe /?` to discover switches and filter definitions, then adds runtime-aware completion for `/FI` filter expressions using live process, service, module, user, window-title, and session data.

## Registration and command names

The script ends by calling:

```powershell
Register-ArgumentCompleter -Native -CommandName @('tasklist', 'tasklist.exe') -ScriptBlock { ... }
```

Load it into the current session with:

```powershell
. .\tasklist_completer.ps1
```

## How completion works

### Initialization

On first use, the script initializes `$script:TasklistCompletionCatalog` by:

- seeding default switch tokens and tooltips
- parsing `tasklist.exe /?` to refine switch metadata
- parsing the `Filters:` section to discover filter names and valid operators
- loading explicit value hints for selected options such as `/FO`

### Token-state parsing

The completer does not rely only on PowerShell's current word. It tokenizes the command line up to the cursor, tracks whether the cursor is inside quotes, and determines:

- argument tokens
- the current token
- tokens before the current token
- whether the cursor is after trailing whitespace

That token state drives switch completion, option-value completion, and `/FI` expression completion.

### Switch and value routing

The main completion flow is:

1. if the current token starts with `/`, suggest switches
2. otherwise, if the command is currently inside a `/FI` expression, suggest filter expression pieces
3. otherwise, if the previous token expects a value, suggest values for that option
4. otherwise, when the current token is empty, suggest switches

## Key completion behaviors / supported values

### Switch completion

Switch suggestions come from parsed help text combined with default tokens. The script is prepared to complete tokens such as:

- `/S`, `/U`, `/P`
- `/M`, `/SVC`, `/APPS`, `/V`
- `/FI`, `/FO`, `/NH`, `/?`

### `/FO` value completion

`/FO` returns these output-format values:

- `TABLE`
- `LIST`
- `CSV`

### `/FI` filter-expression completion

The script expects filter expressions in quoted form and builds suggestions progressively:

1. filter name
2. operator
3. filter value

For example, it can generate completions shaped like:

```text
"STATUS eq RUNNING"
"PID gt 1000"
```

Filter names and valid operators are sourced from `tasklist.exe /?`.

### Runtime-backed filter values

For selected filters, the script gathers live values and caches them for a short period:

- `IMAGENAME`, `PID`, `SESSION`, `SESSIONNAME` from `tasklist.exe /FO CSV /NH` (15-second cache)
- `USERNAME` from `Get-Process -IncludeUserName` plus the current `USERDOMAIN\USERNAME` (30-second cache)
- `SERVICES` from `Get-Service` (60-second cache)
- `WINDOWTITLE` from `Get-Process` main window titles (10-second cache)
- `MODULES` from `Get-Process -Module` (30-second cache)

The `STATUS` filter uses documented values, and `CPUTIME` / `MEMUSAGE` use small built-in sample values.

### Supported filter value behaviors

The completer has specific value-generation logic for:

- `STATUS`
- `CPUTIME`
- `MEMUSAGE`
- `IMAGENAME`
- `PID`
- `SESSION`
- `SESSIONNAME`
- `USERNAME`
- `SERVICES`
- `WINDOWTITLE`
- `MODULES`

## Dependencies or external command expectations

This completer expects:

- `tasklist.exe` or `tasklist` to be available, otherwise it returns no completions
- `tasklist.exe /?` to initialize switch and filter metadata
- `tasklist.exe /FO CSV /NH` for runtime process/session snapshots
- `Get-Process`, `Get-Service`, and local process inspection for runtime-backed filter values

## Usage / loading example

```powershell
. .\tasklist_completer.ps1

tasklist <TAB>
tasklist /FO <TAB>
tasklist /FI <TAB>
tasklist /FI "STATUS <TAB>
tasklist /FI "IMAGENAME eq <TAB>
```

## Limitations / notes

- The completer recognizes `/S`, `/U`, `/P`, and `/M` as value-taking options, but it does not generate value suggestions for them.
- `/FI` completion is focused on quoted filter expressions.
- Some filter values come from live system state, so suggestions can change between invocations.
- Runtime-backed suggestions depend on the commands and process metadata being accessible in the current session.

