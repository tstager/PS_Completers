<#
.SYNOPSIS
    Registers a native PowerShell argument completer for attrib.

.DESCRIPTION
    Provides a static-first native completer for `attrib` and `attrib.exe`.

    The completer covers:
    - whole-token attribute toggles such as `+R` and `-H`
    - slash-style switches `/S`, `/D`, `/L`, and `/?`
    - local filesystem path and wildcard operand completion

    The script keeps its top level compatible with `Import-CompleterScript`.
#>

Set-StrictMode -Version 2.0

function New-AttribCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $ListItemText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Test-AttribStartsWith {
    param(
        [string]$Candidate,
        [string]$Prefix
    )

    [string]::IsNullOrEmpty($Prefix) -or $Candidate.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-AttribAttributeSpecs {
    @(
        [pscustomobject]@{ Token = '+R'; Description = 'Sets the read-only file attribute.' }
        [pscustomobject]@{ Token = '-R'; Description = 'Clears the read-only file attribute.' }
        [pscustomobject]@{ Token = '+A'; Description = 'Sets the archive file attribute.' }
        [pscustomobject]@{ Token = '-A'; Description = 'Clears the archive file attribute.' }
        [pscustomobject]@{ Token = '+S'; Description = 'Sets the system file attribute.' }
        [pscustomobject]@{ Token = '-S'; Description = 'Clears the system file attribute.' }
        [pscustomobject]@{ Token = '+H'; Description = 'Sets the hidden file attribute.' }
        [pscustomobject]@{ Token = '-H'; Description = 'Clears the hidden file attribute.' }
        [pscustomobject]@{ Token = '+O'; Description = 'Sets the offline attribute.' }
        [pscustomobject]@{ Token = '-O'; Description = 'Clears the offline attribute.' }
        [pscustomobject]@{ Token = '+I'; Description = 'Sets the not-content-indexed file attribute.' }
        [pscustomobject]@{ Token = '-I'; Description = 'Clears the not-content-indexed file attribute.' }
        [pscustomobject]@{ Token = '+X'; Description = 'Sets the no-scrub file attribute.' }
        [pscustomobject]@{ Token = '-X'; Description = 'Clears the no-scrub file attribute.' }
        [pscustomobject]@{ Token = '+P'; Description = 'Sets the pinned attribute.' }
        [pscustomobject]@{ Token = '-P'; Description = 'Clears the pinned attribute.' }
        [pscustomobject]@{ Token = '+U'; Description = 'Sets the unpinned attribute.' }
        [pscustomobject]@{ Token = '-U'; Description = 'Clears the unpinned attribute.' }
        [pscustomobject]@{ Token = '+B'; Description = 'Sets the SMR blob attribute.' }
        [pscustomobject]@{ Token = '-B'; Description = 'Clears the SMR blob attribute.' }
        [pscustomobject]@{ Token = '+V'; Description = 'Sets the integrity attribute.' }
        [pscustomobject]@{ Token = '-V'; Description = 'Clears the integrity attribute.' }
    )
}

function Get-AttribSlashSwitchSpecs {
    @(
        [pscustomobject]@{ Token = '/S'; Description = 'Processes matching files in the current folder and all subfolders.' }
        [pscustomobject]@{ Token = '/D'; Description = 'Processes folders as well.' }
        [pscustomobject]@{ Token = '/L'; Description = 'Works on symbolic link attributes instead of the target.' }
        [pscustomobject]@{ Token = '/?'; Description = 'Displays attrib help.' }
    )
}

function Get-AttribTokenState {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    if ($null -eq $Line) {
        $Line = ''
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    $tokens = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    $quoteChar = [char]0

    foreach ($character in $prefix.ToCharArray()) {
        if (($character -eq [char]34) -or ($character -eq [char]39)) {
            if ($quoteChar -eq [char]0) {
                $quoteChar = $character
            } elseif ($quoteChar -eq $character) {
                $quoteChar = [char]0
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and $quoteChar -eq [char]0) {
            if ($builder.Length -gt 0) {
                $tokens.Add($builder.ToString())
                [void]$builder.Clear()
            }

            continue
        }

        [void]$builder.Append($character)
    }

    $hasTrailingSpace = $prefix -match '\s$'
    if ($builder.Length -gt 0) {
        $tokens.Add($builder.ToString())
    }

    if ($hasTrailingSpace) {
        return [pscustomobject]@{
            CurrentToken = ''
        }
    }

    return [pscustomobject]@{
        CurrentToken = if ($tokens.Count -gt 0) { $tokens[$tokens.Count - 1] } else { '' }
    }
}

function Get-AttribCommandTextForCompletion {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    if ($null -eq $CommandAst) {
        return [pscustomobject]@{
            Line           = ''
            CursorPosition = 0
        }
    }

    $line = if ($null -ne $CommandAst.Extent -and $null -ne $CommandAst.Extent.Text) {
        $CommandAst.Extent.Text
    } else {
        $CommandAst.ToString()
    }

    if ($null -eq $line) {
        $line = ''
    }

    $startOffset = if ($null -ne $CommandAst.Extent) { $CommandAst.Extent.StartOffset } else { 0 }
    $relativeCursor = [Math]::Max($CursorPosition - $startOffset, 0)
    $trailingWhitespaceLength = $relativeCursor - $line.Length

    if ($trailingWhitespaceLength -gt 0) {
        $line += ' ' * $trailingWhitespaceLength
    }

    [pscustomobject]@{
        Line           = $line
        CursorPosition = $relativeCursor
    }
}

function Get-AttribToggleCompletions {
    param([string]$CurrentWord)

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    $sign = if ($CurrentWord.StartsWith('-')) { '-' } else { '+' }

    foreach ($spec in Get-AttribAttributeSpecs) {
        if (-not $spec.Token.StartsWith($sign, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if (Test-AttribStartsWith -Candidate $spec.Token -Prefix $CurrentWord) {
            [void]$results.Add((New-AttribCompletionResult -CompletionText $spec.Token -ResultType 'ParameterName' -ToolTip $spec.Description))
        }
    }

    if ($results.Count -eq 0) {
        [void]$results.Add((New-AttribCompletionResult -CompletionText $CurrentWord -ResultType 'ParameterName' -ToolTip 'Attribute toggle.'))
    }

    @($results.ToArray())
}

function Get-AttribSlashCompletions {
    param([string]$CurrentWord)

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    foreach ($spec in Get-AttribSlashSwitchSpecs) {
        if (Test-AttribStartsWith -Candidate $spec.Token -Prefix $CurrentWord) {
            [void]$results.Add((New-AttribCompletionResult -CompletionText $spec.Token -ResultType 'ParameterName' -ToolTip $spec.Description))
        }
    }

    if ($results.Count -eq 0) {
        [void]$results.Add((New-AttribCompletionResult -CompletionText $CurrentWord -ResultType 'ParameterName' -ToolTip 'attrib slash switch.'))
    }

    @($results.ToArray())
}

function Get-AttribPathCompletions {
    param([string]$CurrentWord)

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    $inputPath = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }

    foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($inputPath)) {
        [void]$results.Add([System.Management.Automation.CompletionResult]::new(
                $item.CompletionText,
                $item.CompletionText,
                $item.ResultType,
                $item.ToolTip
            ))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($inputPath)) { '<path>' } else { $inputPath }
        [void]$results.Add((New-AttribCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip 'File or directory path or wildcard operand.'))
    }

    @($results.ToArray())
}

function Complete-Attrib {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $commandState = Get-AttribCommandTextForCompletion -CommandAst $commandAst -CursorPosition $cursorPosition
    $tokenState = Get-AttribTokenState -Line $commandState.Line -CursorPosition $commandState.CursorPosition
    $currentWord = if ($null -eq $tokenState.CurrentToken) { '' } else { $tokenState.CurrentToken }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @(Get-AttribPathCompletions -CurrentWord '')
    }

    if ($currentWord.StartsWith('+') -or $currentWord.StartsWith('-')) {
        return @(Get-AttribToggleCompletions -CurrentWord $currentWord)
    }

    if ($currentWord.StartsWith('/')) {
        return @(Get-AttribSlashCompletions -CurrentWord $currentWord)
    }

    @(Get-AttribPathCompletions -CurrentWord $currentWord)
}

Register-ArgumentCompleter -Native -CommandName @('attrib', 'attrib.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Attrib -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
