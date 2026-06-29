# numfmt tab completion for PowerShell
# Static option completion for numfmt.exe and numfmt.

Set-StrictMode -Version 2.0

function Get-NumfmtCompletionOptions {
    $cache = Get-Variable -Name 'NumfmtCompletionOptions' -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('--debug', '--field', '--format', '--from', '--to', '--invalid', '--suffix', '--round', '--padding', '--grouping', '--header', '--zero-terminated', '--help', '--version', '-d', '-f', '-i', '-o', '-p', '-s', '-z')
    $commandCandidates = @('numfmt.exe', 'numfmt')
    foreach ($candidate in $commandCandidates) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            continue
        }

        try {
            $helpOutput = & $command.Source --help 2>&1 | Out-String
        } catch {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($helpOutput)) {
            continue
        }

        $options = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($line in ([regex]::Split($helpOutput, '\r?\n'))) {
            foreach ($match in [regex]::Matches($line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|$))')) {
                $rawOption = $match.Groups[1].Value
                $normalized = $rawOption.Trim()
                if ($normalized.StartsWith('--')) {
                    $normalized = $normalized -replace '\[.*$', ''
                    $normalized = $normalized -replace '=.*$', ''
                }
                if ($normalized -match '^-{1,2}[A-Za-z0-9][A-Za-z0-9-]*$') {
                    [void]$options.Add($normalized)
                }
            }
        }

        if ($options.Count -gt 0) {
            Set-Variable -Name 'NumfmtCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            return (Get-Variable -Name 'NumfmtCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'NumfmtCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'NumfmtCompletionOptions' -Scope Script).Value
}

function New-NumfmtCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Remove-NumfmtOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-NumfmtQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        $escaped = $Value.Replace('`', '``').Replace('"', '`"')
        return '"' + $escaped + '"'
    }

    $Value
}

function Get-NumfmtCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') {
        return ''
    }

    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-NumfmtPreviousToken {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    if ($elements.Count -le 1) {
        return $null
    }

    if ([string]::IsNullOrEmpty($CurrentWord)) {
        return $elements[-1]
    }

    if ($elements[-1] -eq $CurrentWord) {
        return $elements[-2]
    }

    return $elements[-1]
}

function Get-NumfmtValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $previousToken = Get-NumfmtPreviousToken -commandAst $commandAst -CurrentWord $CurrentWord
    if ($null -eq $previousToken) {
        return @()
    }

    switch ($previousToken) {
        '--field' { return @(
            New-NumfmtCompletionResult -CompletionText '1' -ListItemText '1' -ResultType 'ParameterValue' -ToolTip 'Select the first field.'
            New-NumfmtCompletionResult -CompletionText '1,2' -ListItemText '1,2' -ResultType 'ParameterValue' -ToolTip 'Select multiple fields.'
            New-NumfmtCompletionResult -CompletionText '<field-list>' -ListItemText '<field-list>' -ResultType 'ParameterValue' -ToolTip 'Field list such as 1,2 or 2-4.'
        ) }
        '--format' { return @(
            New-NumfmtCompletionResult -CompletionText '%f' -ListItemText '%f' -ResultType 'ParameterValue' -ToolTip 'Default floating-point format.'
            New-NumfmtCompletionResult -CompletionText '%d' -ListItemText '%d' -ResultType 'ParameterValue' -ToolTip 'Decimal format.'
            New-NumfmtCompletionResult -CompletionText '<format>' -ListItemText '<format>' -ResultType 'ParameterValue' -ToolTip 'Custom format string.'
        ) }
        '--from' { return @(
            New-NumfmtCompletionResult -CompletionText 'auto' -ListItemText 'auto' -ResultType 'ParameterValue' -ToolTip 'Auto-detect the input unit.'
            New-NumfmtCompletionResult -CompletionText 'none' -ListItemText 'none' -ResultType 'ParameterValue' -ToolTip 'Treat input as plain numbers.'
            New-NumfmtCompletionResult -CompletionText 'iec' -ListItemText 'iec' -ResultType 'ParameterValue' -ToolTip 'IEC units.'
        ) }
        '--to' { return @(
            New-NumfmtCompletionResult -CompletionText 'none' -ListItemText 'none' -ResultType 'ParameterValue' -ToolTip 'Render as plain numbers.'
            New-NumfmtCompletionResult -CompletionText 'si' -ListItemText 'si' -ResultType 'ParameterValue' -ToolTip 'SI units.'
            New-NumfmtCompletionResult -CompletionText 'iec' -ListItemText 'iec' -ResultType 'ParameterValue' -ToolTip 'IEC units.'
        ) }
        '--invalid' { return @(
            New-NumfmtCompletionResult -CompletionText 'abort' -ListItemText 'abort' -ResultType 'ParameterValue' -ToolTip 'Abort on invalid input.'
            New-NumfmtCompletionResult -CompletionText 'fail' -ListItemText 'fail' -ResultType 'ParameterValue' -ToolTip 'Emit a failure status.'
            New-NumfmtCompletionResult -CompletionText 'warn' -ListItemText 'warn' -ResultType 'ParameterValue' -ToolTip 'Warn and skip invalid input.'
        ) }
        '--round' { return @(
            New-NumfmtCompletionResult -CompletionText 'nearest' -ListItemText 'nearest' -ResultType 'ParameterValue' -ToolTip 'Round to the nearest value.'
            New-NumfmtCompletionResult -CompletionText 'up' -ListItemText 'up' -ResultType 'ParameterValue' -ToolTip 'Round upward.'
            New-NumfmtCompletionResult -CompletionText 'down' -ListItemText 'down' -ResultType 'ParameterValue' -ToolTip 'Round downward.'
        ) }
        '--padding' { return @(
            New-NumfmtCompletionResult -CompletionText '10' -ListItemText '10' -ResultType 'ParameterValue' -ToolTip 'Pad to a width of 10 characters.'
            New-NumfmtCompletionResult -CompletionText '<width>' -ListItemText '<width>' -ResultType 'ParameterValue' -ToolTip 'Width to pad to.'
        ) }
        '--suffix' { return @(
            New-NumfmtCompletionResult -CompletionText 'B' -ListItemText 'B' -ResultType 'ParameterValue' -ToolTip 'Use B as a suffix.'
            New-NumfmtCompletionResult -CompletionText '<suffix>' -ListItemText '<suffix>' -ResultType 'ParameterValue' -ToolTip 'Suffix to apply.'
        ) }
    }

    return @()
}

function Get-NumfmtPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-NumfmtOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]+$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like "$leaf*" } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = if ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $item.Name
        } elseif ([System.IO.Path]::IsPathRooted($cleanInput)) {
            Join-Path -Path $parent -ChildPath $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-NumfmtQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-NumfmtCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-NumfmtCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Complete-Numfmt {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-NumfmtCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        $valueCompletions = Get-NumfmtValueCompletions -commandAst $commandAst -CurrentWord $wordToComplete
        if ($valueCompletions.Count -gt 0) {
            return $valueCompletions
        }

        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-NumfmtCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-NumfmtCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'Option for numfmt.'
                }
            }
        )
    }

    Get-NumfmtPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'numfmt', 'numfmt.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Numfmt -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
