# findstr completer

## What it completes / overview

`findstr_completer.ps1` registers a standalone native PowerShell completer for `findstr` and `findstr.exe`.

It is a **static-first** completer because `findstr.exe` has a small, stable command surface that is fully described by `findstr /?`.

The completer covers:

- slash-style switches from the built-in help surface
- attached value switches:
  - `/A:`
  - `/C:`
  - `/D:`
  - `/F:`
  - `/G:`
  - `/Q:`
- local path completion for file operands and file-bearing switch values
- semicolon-delimited directory completion for `/D:`
- placeholder-driven completion for free-form search-string slots so PowerShell does not fall back to filesystem completion in the wrong place
- both `findstr` and `findstr.exe` registration names

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('findstr', 'findstr.exe') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\findstr_completer\findstr_completer.ps1
```

Like many completer scripts in this repo, dot-sourcing also applies:

```powershell
Set-StrictMode -Version Latest
```

If you only want to validate import compatibility without dot-sourcing into your session, use `CompleterActions` `Import-CompleterScript` as shown below.

## Import-CompleterScript compatibility

The file keeps its top level compatible with `CompleterActions`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or external command calls.

## How completion works

### 1. Static switch catalog

The completer lazily builds an in-memory catalog for the documented switch surface:

- flags: `/B`, `/E`, `/L`, `/R`, `/S`, `/I`, `/X`, `/V`, `/N`, `/M`, `/O`, `/P`, `/?`
- expanded help token `/OFF[LINE]` as:
  - `/OFF`
  - `/OFFLINE`
- attached-value switches:
  - `/A:` color attribute
  - `/C:` literal search string
  - `/D:` semicolon-delimited directory list
  - `/F:` file list path or `/` console sentinel
  - `/G:` pattern file path or `/` console sentinel
  - `/Q:` quiet flags

Because the catalog is created lazily inside a function, the script remains import-safe.

### 2. Attached value handling

The completer parses attached forms in-place rather than treating them as separate arguments.

Examples:

```powershell
findstr /A:
findstr /Q:
findstr /F:C:\
findstr /G:"C:\Program Files\
findstr "/D:C:\Windows;C:\Pro"
findstr /C:"hello there
```

Behavior by switch:

- `/A:` suggests common two-digit color values and a `<hh>` placeholder
- `/Q:` suggests `/Q:u`
- `/F:` and `/G:` offer:
  - file/path completion
  - the literal `/` sentinel (`/F:/`, `/G:/`) for console input
- `/D:` completes only the segment after the last `;`
- `/C:` never falls back to filesystem results; it emits placeholders or the typed text back as a completion result

### 3. Operand routing

In observed `findstr.exe` runtime behavior, the first bare positional behaves as the `strings` operand and later bare operands behave as filenames. The completer follows that behavior:

```text
findstr [switches] strings [filename ...]
```

That means the completer uses these rules:

- before a positional search string has been supplied, bare input stays in **search-string mode**
- after one bare search string, later bare operands are treated as **filenames**
- if `/C:` or `/G:` is present, later **bare** operands are treated as filenames, but later **slash-prefixed** arguments can still be switches until a filename operand actually starts
- once filename mode starts, slash-prefixed input is treated as a file/path operand rather than a late switch

Examples:

```powershell
findstr foo            # completing the search-string slot
findstr foo .\         # completing filenames
findstr /C:error /I    # still completing switches
findstr /C:error .\    # completing filenames
findstr /G:patterns.txt /? 
```

The completer still avoids risky probing such as `Test-Path` or command execution. It uses local path completion only when the grammar says the current slot is a file-bearing operand.

## Placeholder strategy

To suppress noisy filesystem fallback in free-form slots, the completer emits explicit placeholder values such as:

- `<search-string>`
- `/A:<hh>`
- `/Q:<qflags>`
- `/F:<file-list>`
- `/G:<pattern-file>`
- `/D:<dir[;dir...]>`

For nonblank free-form search-string slots, it echoes the user's current text back as a `ParameterValue` completion result.

That keeps PowerShell from switching to default path completion in `/C:` and in the initial positional `strings` slot.

## Usage examples

```powershell
findstr /
findstr /A:
findstr /Q:
findstr /C:
findstr /C:"hello there
findstr /F:
findstr /G:
findstr /D:
findstr foo 
findstr foo .\
findstr /C:error .\
findstr.exe /Q:
```

## Validation commands

Representative clean-session checks:

```powershell
pwsh -NoProfile -Command '
$file = ".\findstr_completer\findstr_completer.ps1"
$null = $tokens = $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors) | Out-Null
"PARSE_ERRORS=$($errors.Count)"
. $file
"LOADED=ok"
'
```

```powershell
pwsh -NoProfile -Command '
Import-Module "C:\Users\Trent\OneDrive\Documents\My Scripts\Code\PowerShell\Modules\CompleterActions\CompleterActions.psd1" -Force
$file = Resolve-Path ".\findstr_completer\findstr_completer.ps1"
$imported = @(Import-CompleterScript -LiteralPath $file)
"IMPORTED=$($imported.Count)"
$imported | Select-Object CommandName, ParameterName, CompleterType
'
```

```powershell
pwsh -NoProfile -Command '
. .\findstr_completer\findstr_completer.ps1
foreach ($s in @(
    "findstr /",
    "findstr /Q:",
    "findstr /C:",
    "findstr foo ",
    "findstr foo .\\",
    "findstr /C:error .\\",
    "findstr.exe /Q:"
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

- `findstr` uses attached values instead of separated switch arguments for `/A:`, `/C:`, `/D:`, `/F:`, `/G:`, and `/Q:`.
- `/OFF[LINE]` is presented as two concrete completions: `/OFF` and `/OFFLINE`.
- `/F:/` and `/G:/` are valid console sentinels and should not throw path-splitting errors.
- In PowerShell, `/D:` values containing `;` should usually be quoted because `;` is a statement separator.

## Limitations

- The completer does not execute `findstr.exe` or inspect the filesystem beyond local path enumeration for file-bearing slots.
- Path completion is local-only and prefix-based; it does not attempt wildcard-aware probing.
