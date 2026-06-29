# od tab completion for PowerShell
# Static option completion for od.exe and od.

Set-StrictMode -Version 2.0

function Get-OdCompletionOptions {
    @(
        '-A', '--address-radix', '-j', '--skip-bytes', '-N', '--read-bytes', '-S', '--strings', '-t', '--format', '-v', '--output-duplicates', '-An', '-w', '--width', '-x', '--hex', '-b', '--byte', '-c', '--char', '-d', '--decimal', '-o', '--octal', '-f', '--float', '--help', '--version'
    )
}

function New-OdCompletionResult {
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

function Remove-OdOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-OdQuotedValue {
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

function Get-OdCurrentToken {
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

function Get-OdPreviousToken {
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

function Get-OdValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $previousToken = Get-OdPreviousToken -commandAst $commandAst -CurrentWord $CurrentWord
    if ($null -eq $previousToken) {
        return @()
    }

    switch ($previousToken) {
        '--address-radix' { return @(
            New-OdCompletionResult -CompletionText 'd' -ListItemText 'd' -ResultType 'ParameterValue' -ToolTip 'Decimal address radix.'
            New-OdCompletionResult -CompletionText 'o' -ListItemText 'o' -ResultType 'ParameterValue' -ToolTip 'Octal address radix.'
            New-OdCompletionResult -CompletionText 'x' -ListItemText 'x' -ResultType 'ParameterValue' -ToolTip 'Hexadecimal address radix.'
        ) }
        '--format' { return @(
            New-OdCompletionResult -CompletionText 'd' -ListItemText 'd' -ResultType 'ParameterValue' -ToolTip 'Decimal output.'
            New-OdCompletionResult -CompletionText 'o' -ListItemText 'o' -ResultType 'ParameterValue' -ToolTip 'Octal output.'
            New-OdCompletionResult -CompletionText 'x' -ListItemText 'x' -ResultType 'ParameterValue' -ToolTip 'Hex output.'
        ) }
        '--skip-bytes' { return @(
            New-OdCompletionResult -CompletionText '<bytes>' -ListItemText '<bytes>' -ResultType 'ParameterValue' -ToolTip 'Number of bytes to skip.'
        ) }
        '--read-bytes' { return @(
            New-OdCompletionResult -CompletionText '<bytes>' -ListItemText '<bytes>' -ResultType 'ParameterValue' -ToolTip 'Number of bytes to read.'
        ) }
        '--strings' { return @(
            New-OdCompletionResult -CompletionText '<bytes>' -ListItemText '<bytes>' -ResultType 'ParameterValue' -ToolTip 'Minimum string length.'
        ) }
        '--width' { return @(
            New-OdCompletionResult -CompletionText '16' -ListItemText '16' -ResultType 'ParameterValue' -ToolTip '16-byte output width.'
            New-OdCompletionResult -CompletionText '<width>' -ListItemText '<width>' -ResultType 'ParameterValue' -ToolTip 'Output width.'
        ) }
    }

    return @()
}

function Get-OdPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-OdOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-OdQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-OdCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-OdCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Complete-Od {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-OdCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        $valueCompletions = Get-OdValueCompletions -commandAst $commandAst -CurrentWord $wordToComplete
        if ($valueCompletions.Count -gt 0) {
            return $valueCompletions
        }

        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-OdCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-OdCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'Option for od.'
                }
            }
        )
    }

    Get-OdPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'od', 'od.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Od -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
