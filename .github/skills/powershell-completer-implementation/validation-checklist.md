# PowerShell Completer Validation Checklist

Use these patterns to validate new or changed native completers in this repository.

## 1. Parse and load in a clean session

```powershell
pwsh -NoProfile -Command '
$file = ".\<name>_completer\<name>_completer.ps1"
$null = $tokens = $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors) | Out-Null
"PARSE_ERRORS=$($errors.Count)"
. $file
"LOADED=ok"
'
```

## 2. Verify switch surface

```powershell
pwsh -NoProfile -Command '
. .\<name>_completer\<name>_completer.ps1
$s = "<command> -"
(TabExpansion2 $s $s.Length).CompletionMatches |
    Select-Object CompletionText, ResultType |
    Format-Table -AutoSize
'
```

Expect switches to appear as `ParameterName`.

## 3. Verify representative value slots

Test at least one value-bearing switch and one operand slot:

```powershell
pwsh -NoProfile -Command '
. .\<name>_completer\<name>_completer.ps1
foreach ($s in @(
    "<command> <value-switch> ",
    "<command> "
)) {
    "INPUT=$s"
    (TabExpansion2 $s $s.Length).CompletionMatches |
        Select-Object -First 12 -ExpandProperty CompletionText
    "---"
}
'
```

## 4. Verify path, provider, or @file handling

If the completer supports paths, registry paths, or `@file` syntax, test those explicitly:

```powershell
pwsh -NoProfile -Command '
. .\<name>_completer\<name>_completer.ps1
foreach ($s in @(
    "<command> @",
    "<command> .\",
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

## 5. Validate both command names when relevant

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

## 6. Watch for common regressions

- switch emitted as `ParameterValue` instead of `ParameterName`
- root switch suggestions mixed into active path completion
- bare `@` causing `Split-Path` errors
- literal `/` or other partial tokens leaking into slash-style command results
- direct helper invocation working while registered `TabExpansion2` behavior does not
- fallback filesystem completion appearing in slots that should be placeholders

## 7. Validate the integration surface

When the task includes repository integration:

- verify the companion `.md` file exists
- verify `README.md` has the new alphabetical row
- if the user requested it, verify the profile dot-sources the new completer
