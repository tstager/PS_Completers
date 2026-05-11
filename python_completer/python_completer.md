# python completer

## Overview

`python_completer.ps1` registers a standalone native PowerShell completer for:

- `python`
- `python.exe`

The completer is static-first and uses the locally derived `python --help` / `python --help-xoptions` surface as its source of truth. It does not shell out to Python during completion.

## Covered surface

Root command-line forms modeled from help include:

- `-b`, `-bb`, `-B`
- `-c`, `-d`, `-E`
- `-h`, `-?`, `--help`
- `-i`, `-I`, `-m`
- `-O`, `-OO`, `-P`
- `-q`, `-s`, `-S`
- `-u`, `-v`, `-V`, `--version`
- `-W`, `-x`, `-X`
- `--check-hash-based-pycs`
- `--help-env`, `--help-xoptions`, `--help-all`
- first positional `-` for stdin

Modeled `-X` values include:

- `context_aware_warnings=0|1`
- `cpu_count=default|<N>`
- `dev`
- `disable-remote-debug`
- `faulthandler`
- `frozen_modules=on|off`
- `importtime[=2]`
- `int_max_str_digits=<N>`
- `no_debug_ranges`
- `perf`
- `perf_jit`
- `pycache_prefix=<PATH>`
- `showrefcount`
- `thread_inherit_context=0|1`
- `tracemalloc[=1|<N>]`
- `utf8[=0|1]`
- `warn_default_encoding`

## Completion behavior

- Root switches are emitted as `CompletionResultType = ParameterName`.
- `--check-hash-based-pycs` completes `always`, `default`, and `never`.
- `-X` completes static xoption names and helpful `name=value` forms without invoking Python.
- `-X tracemalloc=` and similar `=` partials stay in xoption mode instead of falling back to filesystem completion.
- `-W` returns a placeholder filter form: `<action:message:category:module:lineno>`.
- `-c` returns `<command-string>`.
- `-m` returns `<module>`.
- The first positional script operand uses filesystem completion and is not limited to `.py`.
- The first positional operand also exposes `-` as the stdin sentinel.
- After `-c`, `-m`, or a script/stdin program operand takes over, the completer stops offering root switches and falls back to placeholders or path-like argument completion only.

## Import compatibility

The script top level is limited to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, `try` blocks, or external command invocations, so the script stays `Import-CompleterScript`-safe.

## Representative validation commands

```powershell
pwsh -NoProfile -Command '
$file = ".\python_completer\python_completer.ps1"
$null = $tokens = $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors) | Out-Null
"PARSE_ERRORS=$($errors.Count)"
. $file
"LOADED=ok"
'
```

```powershell
pwsh -NoProfile -Command '
$modulePath = Get-ChildItem "..\Modules\CompleterActions\*\CompleterActions.psd1" |
    Sort-Object { [version] $_.Directory.Name } -Descending |
    Select-Object -First 1 -ExpandProperty FullName
Import-Module $modulePath -Force
$file = Resolve-Path ".\python_completer\python_completer.ps1"
$imported = @(Import-CompleterScript -LiteralPath $file)
"IMPORTED=$($imported.Count)"
$imported | Select-Object CommandName, ParameterName, CompleterType
'
```

```powershell
pwsh -NoProfile -Command '
. .\python_completer\python_completer.ps1
foreach ($s in @(
    "python -",
    "python.exe -",
    "python --check-hash-based-pycs ",
    "python -X ",
    "python -X tracemalloc=",
    "python -W ",
    "python -m ",
    "python -c ",
    "python .\",
    "python script.py "
)) {
    "INPUT=$s"
    (TabExpansion2 $s $s.Length).CompletionMatches |
        Select-Object -First 12 CompletionText, ResultType |
        Format-Table -AutoSize
    "---"
}
'
```
