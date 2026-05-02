# takeown completer

## What it completes / overview

`takeown_completer.ps1` registers a standalone native PowerShell completer for `takeown` and `takeown.exe`.

It is a **static-first** completer because `takeown.exe /?` exposes a small, stable switch surface and only a few value-bearing slots need special handling.

The completer covers:

- slash-style switches from the documented help surface
- switch/value state transitions for:
  - `/S <system>`
  - `/U <[domain\]user>`
  - `/P [password]`
  - `/F <filename>`
  - `/D <Y|N>`
- local file and directory completion for `/F`
- placeholder-only completion for `/S`, `/U`, and `/P`
- UNC-safe placeholder completion for `/F` values that begin with `\\`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('takeown', 'takeown.exe') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\takeown_completer\takeown_completer.ps1
```

Both bare and `.exe` names are registered because native completion should work for either invocation form.

## Import-CompleterScript compatibility

The file keeps its top level compatible with `CompleterActions`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or external command calls.

## How completion works

### 1. Static switch catalog

The completer lazily builds a small in-memory catalog for:

- `/S`
- `/U`
- `/P`
- `/F`
- `/A`
- `/R`
- `/D`
- `/SKIPSL`
- `/?`

That keeps the top level import-safe while still centralizing switch descriptions and safe placeholder values.

### 2. Switch/value state machine

The completer routes suggestions by the actual slash-switch context:

- `/U` is only suggested after `/S` has received a value
- `/P` is only suggested after `/U` has received a value
- `/D` and `/SKIPSL` are only suggested after `/R`
- `/?` is terminal; once present, no further real arguments are suggested

The completer intentionally does **not** invent attached forms such as `/S:server`, `/F:path`, or `/D:Y`.

### 3. Safe value handling

Value behavior by switch:

- `/S`
  - current-machine and `<system>` placeholder suggestions only
  - no remote probing
- `/U`
  - current-user-safe suggestions only
  - includes `<user>` and `<domain\user>` placeholders
- `/P`
  - placeholder-only completion
  - never reads or inspects secrets
- `/D`
  - enum completion for `Y` and `N`
- `/F`
  - local path completion for files and directories
  - UNC values echo the typed path and add scoped placeholder guidance without enumerating remote shares

## Usage examples

```powershell
takeown /
takeown.exe /
takeown /S 
takeown /S server /
takeown /S server /U domain\user /
takeown /F C:\Win
takeown /R /
takeown /R /D 
```

## Validation commands

Representative clean-session checks:

```powershell
pwsh -NoProfile -Command '
$file = ".\takeown_completer\takeown_completer.ps1"
$null = $tokens = $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors) | Out-Null
"PARSE_ERRORS=$($errors.Count)"
. $file
"LOADED=ok"
'
```

```powershell
pwsh -NoProfile -Command '
Import-Module CompleterActions -Force
$file = Resolve-Path ".\takeown_completer\takeown_completer.ps1"
$imported = @(Import-CompleterScript -LiteralPath $file)
"IMPORTED=$($imported.Count)"
$imported | Select-Object CommandName, ParameterName, CompleterType
'
```

```powershell
pwsh -NoProfile -Command '
. .\takeown_completer\takeown_completer.ps1
foreach ($s in @(
    "takeown /",
    "takeown.exe /",
    "takeown /S ",
    "takeown /S server /",
    "takeown /S server /U domain\user /",
    "takeown /F C:\Win",
    "takeown /R /",
    "takeown /R /D "
)) {
    "INPUT=$s"
    (TabExpansion2 $s $s.Length).CompletionMatches |
        Select-Object -First 12 CompletionText, ResultType |
        Format-Table -AutoSize
    "---"
}
'
```

## Runtime quirks / notes

- `takeown.exe` documents `/?` as the real help form, and the completer treats it as terminal.
- `/P` accepts an optional password but should never surface sensitive data, so completion stays placeholder-only.
- `/F` may point at UNC paths, but the completer avoids probing remote systems and returns typed-path echo plus scoped UNC placeholder guidance instead.

## Limitations

- `/F` path completion is local-only for actual enumeration.
- UNC path completion is intentionally placeholder-based rather than live network discovery.
- This change does not update `README.md`; repository integration for that row was intentionally left for the separate follow-up todo.
