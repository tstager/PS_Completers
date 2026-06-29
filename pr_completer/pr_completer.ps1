# pr tab completion for PowerShell
# Static option completion for pr.exe and pr.

Set-StrictMode -Version 2.0

function Get-PrCompletionOptions {
    $cache = Get-Variable -Name 'PrCompletionOptions' -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-a', '--across', '-c', '--show-control-chars', '-d', '--double-space', '-e', '--expand-tabs', '-f', '--form-feed', '-h', '--header', '-i', '--indent', '-l', '--length', '-m', '--merge', '-n', '--number-lines', '-o', '--output-tabs', '-r', '--no-file-warnings', '-s', '--separator', '-t', '--omit-header', '-T', '--omit-pagination', '-v', '--show-all', '-w', '--width', '-F', '--page-range', '--help', '--version')
    $commandCandidates = @('pr.exe', 'pr')
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
            Set-Variable -Name 'PrCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            return (Get-Variable -Name 'PrCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'PrCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'PrCompletionOptions' -Scope Script).Value
}

function New-PrCompletionResult {
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

function Remove-PrOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-PrQuotedValue {
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

function Get-PrCurrentToken {
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

function Get-PrPreviousToken {
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

function Get-PrValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $previousToken = Get-PrPreviousToken -commandAst $commandAst -CurrentWord $CurrentWord
    if ($null -eq $previousToken) {
        return @()
    }

    switch ($previousToken) {
        '--columns' { return @(
            New-PrCompletionResult -CompletionText '2' -ListItemText '2' -ResultType 'ParameterValue' -ToolTip 'Split into two columns.'
            New-PrCompletionResult -CompletionText '3' -ListItemText '3' -ResultType 'ParameterValue' -ToolTip 'Split into three columns.'
        ) }
        '--header' { return @(
            New-PrCompletionResult -CompletionText '<header>' -ListItemText '<header>' -ResultType 'ParameterValue' -ToolTip 'Custom header text.'
        ) }
        '--indent' { return @(
            New-PrCompletionResult -CompletionText '<indent>' -ListItemText '<indent>' -ResultType 'ParameterValue' -ToolTip 'Indent string.'
        ) }
        '--length' { return @(
            New-PrCompletionResult -CompletionText '66' -ListItemText '66' -ResultType 'ParameterValue' -ToolTip 'Standard page length.'
            New-PrCompletionResult -CompletionText '<length>' -ListItemText '<length>' -ResultType 'ParameterValue' -ToolTip 'Page length.'
        ) }
        '--width' { return @(
            New-PrCompletionResult -CompletionText '72' -ListItemText '72' -ResultType 'ParameterValue' -ToolTip 'Standard page width.'
            New-PrCompletionResult -CompletionText '<width>' -ListItemText '<width>' -ResultType 'ParameterValue' -ToolTip 'Page width.'
        ) }
        '--separator' { return @(
            New-PrCompletionResult -CompletionText '<separator>' -ListItemText '<separator>' -ResultType 'ParameterValue' -ToolTip 'Column separator.'
        ) }
        '--page-range' { return @(
            New-PrCompletionResult -CompletionText '1-2' -ListItemText '1-2' -ResultType 'ParameterValue' -ToolTip 'Page range.'
            New-PrCompletionResult -CompletionText '<range>' -ListItemText '<range>' -ResultType 'ParameterValue' -ToolTip 'Page range to print.'
        ) }
    }

    return @()
}

function Get-PrPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-PrOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-PrQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-PrCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-PrCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Complete-Pr {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-PrCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        $valueCompletions = Get-PrValueCompletions -commandAst $commandAst -CurrentWord $wordToComplete
        if ($valueCompletions.Count -gt 0) {
            return $valueCompletions
        }

        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-PrCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-PrCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'Option for pr.'
                }
            }
        )
    }

    Get-PrPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'pr', 'pr.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pr -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
