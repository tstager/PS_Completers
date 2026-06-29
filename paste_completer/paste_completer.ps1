# paste tab completion for PowerShell
# Static option completion for paste.exe and paste.

Set-StrictMode -Version 2.0

function Get-PasteCompletionOptions {
    @(
        '-d', '--delimiters', '-s', '--serial', '-z', '--zero-terminated', '--help', '--version'
    )
}

function New-PasteCompletionResult {
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

function Remove-PasteOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-PasteQuotedValue {
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

function Get-PasteCurrentToken {
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

function Get-PastePreviousToken {
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

function Get-PasteValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $previousToken = Get-PastePreviousToken -commandAst $commandAst -CurrentWord $CurrentWord
    if ($null -eq $previousToken) {
        return @()
    }

    if ($previousToken -eq '--delimiters' -or $previousToken -eq '-d') {
        return @(
            New-PasteCompletionResult -CompletionText '\t' -ListItemText '\t' -ResultType 'ParameterValue' -ToolTip 'Tab delimiter.'
            New-PasteCompletionResult -CompletionText '\n' -ListItemText '\n' -ResultType 'ParameterValue' -ToolTip 'Newline delimiter.'
            New-PasteCompletionResult -CompletionText ',' -ListItemText ',' -ResultType 'ParameterValue' -ToolTip 'Comma delimiter.'
            New-PasteCompletionResult -CompletionText '|' -ListItemText '|' -ResultType 'ParameterValue' -ToolTip 'Pipe delimiter.'
        )
    }

    return @()
}

function Get-PastePathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-PasteOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-PasteQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-PasteCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-PasteCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Complete-Paste {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-PasteCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        $valueCompletions = Get-PasteValueCompletions -commandAst $commandAst -CurrentWord $wordToComplete
        if ($valueCompletions.Count -gt 0) {
            return $valueCompletions
        }

        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-PasteCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-PasteCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'Option for paste.'
                }
            }
        )
    }

    Get-PastePathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'paste', 'paste.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Paste -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
