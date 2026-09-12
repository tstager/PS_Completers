# PowerShell Completer Validation Checklist

Use these patterns to validate new or changed native completers in this repository. Run everything in `pwsh -NoProfile`; the profile loads the gallery copy of CompleterActions and the full completer set, which hides load-order and cold-start problems.

## 1. Check the strict import grammar

```powershell
pwsh -NoProfile -Command '
Import-Module CompleterActions -MinimumVersion 2.0.0
$findings = @(Test-CompleterScript -LiteralPath ".\<name>_completer\<name>_completer.ps1")
"FINDINGS=$($findings.Count)"
$findings | Format-List Line, Column, Construct, Message, Hint
'
```

Expect `FINDINGS=0`. Every finding is an `Error` for the strict tier; the `Hint` says how to move the construct into a function or a `Get-Variable` guard. A script that does not parse yields one finding per parse error and is not checked further.

## 2. Parse and load in a clean session without polluting `$Error`

```powershell
pwsh -NoProfile -Command '
$file = ".\<name>_completer\<name>_completer.ps1"
$null = $tokens = $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors) | Out-Null
"PARSE_ERRORS=$($errors.Count)"
$Error.Clear()
. $file
"LOADED=ok ERRORS_AFTER_LOAD=$($Error.Count)"
'
```

Expect `ERRORS_AFTER_LOAD=0`. A `Get-Variable` probe with `-ErrorAction SilentlyContinue` is the usual cause of a stray record; use `-ErrorAction Ignore`.

## 3. Run the repository gate

```powershell
pwsh -NoProfile -File ./tools/Export-CompleterSetFile.ps1   # only when a script was added, renamed, or removed
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
```

The gate runs `Test-CompleterScript` over every script, then imports `ps_completers.psd1` lazily and checks it lists exactly the scripts in the repository. A whole-set strict import is a useful second check:

```powershell
pwsh -NoProfile -Command '
Import-Module CompleterActions -MinimumVersion 2.0.0
$r = Get-ChildItem -Recurse -Filter *_completer.ps1 | Import-CompleterScript -ErrorAction Continue 2>&1
"IMPORTED=$(@($r | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count) ERRORS=$(@($r | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count)"
'
```

## 4. Verify switch surface

```powershell
pwsh -NoProfile -Command '
. .\<name>_completer\<name>_completer.ps1
$s = "<command> -"
(TabExpansion2 $s $s.Length).CompletionMatches |
    Select-Object CompletionText, ResultType, ToolTip |
    Format-Table -AutoSize
'
```

Expect switches to appear as `ParameterName` with the help description as the tooltip. If the tool has a case-distinct pair such as `-d`/`-D`, confirm both are present and that `<command> -D` completes only `-D`.

## 5. Verify representative value slots

Test at least one value-bearing switch in the separate form, the attached form, and with a partial value, plus one operand slot:

```powershell
pwsh -NoProfile -Command '
. .\<name>_completer\<name>_completer.ps1
foreach ($s in @(
    "<command> <value-switch> ",
    "<command> <value-switch>=",
    "<command> <value-switch> <partial>",
    "<command> "
)) {
    "INPUT=$s"
    (TabExpansion2 $s $s.Length).CompletionMatches |
        Select-Object -First 12 -ExpandProperty CompletionText
    "---"
}
'
```

The attached form must keep the `<value-switch>=` prefix on every suggestion.

## 6. Verify the cursor is rebased

```powershell
pwsh -NoProfile -Command '
. .\<name>_completer\<name>_completer.ps1
$s = "Write-Output x; <command> --"
(TabExpansion2 $s $s.Length).CompletionMatches | Select-Object -First 8 -ExpandProperty CompletionText
$s = "Write-Output x; <command> --op --other"
(TabExpansion2 $s 28).CompletionMatches | Select-Object -First 8 -ExpandProperty CompletionText
'
```

Both must return the same suggestions as the command at column 0. Zero results here means `$cursorPosition` was used against the command-relative string without subtracting `$commandAst.Extent.StartOffset`.

## 7. Verify path, provider, or @file handling

If the completer supports paths, registry paths, or `@file` syntax, test those explicitly, including a wildcard character in the typed text:

```powershell
pwsh -NoProfile -Command '
. .\<name>_completer\<name>_completer.ps1
foreach ($s in @(
    "<command> @",
    "<command> .\",
    "<command> fo[",
    "<command> HKLM:\"
)) {
    "INPUT=$s"
    (TabExpansion2 $s $s.Length).CompletionMatches |
        Select-Object -First 12 CompletionText, ResultType |
        Format-Table -AutoSize
    "---"
}
'
```

## 8. Validate both command names when relevant

If the tool resolves through Windows app execution aliases or has both bare and `.exe` usage, test both registrations:

```powershell
pwsh -NoProfile -Command '
. .\<name>_completer\<name>_completer.ps1
foreach ($s in @(
    "<command> -",
    "<command>.exe -"
)) {
    "INPUT=$s"
    (TabExpansion2 $s $s.Length).CompletionMatches |
        Select-Object -First 12 CompletionText, ResultType |
        Format-Table -AutoSize
    "---"
}
'
```

## 9. Compare against the previous version when changing a script

```powershell
git show HEAD:<name>_completer/<name>_completer.ps1 > $env:TEMP\<name>_old.ps1
```

Dot-source the old copy in one `pwsh -NoProfile` and the new one in another and run the same probes in both; a fix should show as a changed result, not just a passing gate.

## 10. Watch for common regressions

- switch emitted as `ParameterValue` instead of `ParameterName`
- root switch suggestions mixed into active path completion
- bare `@` or an empty operand causing `Split-Path` errors
- literal `/` or other partial tokens leaking into slash-style command results
- direct helper invocation working while registered `TabExpansion2` behavior does not
- fallback filesystem completion appearing in slots that should be placeholders
- an exception inside the completer being swallowed by `TabExpansion2` and surfacing as filesystem fallback (`.Count` on a scalar under `Set-StrictMode`, `-like` on text containing `[`)
- case-insensitive comparers or hashtable literals collapsing `-D`/`-d` style option pairs
- an unrebased `$cursorPosition` making mid-line completion return nothing
- an external help call without `$null |` on stdin, or with no timeout for a slow tool
- a `Get-Variable` probe leaving a record in `$Error` on cold load
- `Set-Alias`, `$env:` writes, or other session mutation during completion
- top-level assignment, loop, helper call, or `try` block making `Test-CompleterScript` report a finding
- dynamic `-CommandName` / `-ParameterName` metadata instead of literal strings or a literal `@(...)`
- `ps_completers.psd1` not regenerated after adding, renaming, or removing a script

## 11. Validate the integration surface

When the task includes repository integration:

- verify the companion `.md` file exists and its registration snippet matches the script
- verify `README.md` has the new alphabetical row
- verify `ps_completers.psd1` lists the script (the Pester gate checks this)
- if the user requested it, verify the profile dot-sources the new completer
