# factor tab completion for PowerShell
# Static option completion for factor.exe and factor.

Set-StrictMode -Version 2.0

function Get-FactorCompletionOptions {
    $cache = Get-Variable -Name 'FactorCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('--help', '--version')
    $commandCandidates = @('factor.exe', 'factor')
    foreach ($candidate in $commandCandidates) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            continue
        }

        try {
            $helpOutput = $null | & $command.Source --help 2>&1 | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String
        } catch {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($helpOutput)) {
            continue
        }

        $options = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $descriptions = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
        foreach ($line in ([regex]::Split($helpOutput, '\r?\n'))) {
            foreach ($match in [regex]::Matches($line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|=|\[|$))')) {
                $rawOption = $match.Groups[1].Value
                $normalized = $rawOption.Trim()
                if ($normalized.StartsWith('--')) {
                    $normalized = $normalized -replace '\[.*$', ''
                    $normalized = $normalized -replace '=.*$', ''
                }
                if ($normalized -match '^-{1,2}[A-Za-z0-9][A-Za-z0-9-]*$') {
                    [void]$options.Add($normalized)
                if (-not $descriptions.ContainsKey($normalized)) {
                    $description = ($line -replace '^\s*(?:-{1,2}[A-Za-z0-9][A-Za-z0-9-]*(?:[=\[]\S*)?[,\s]+)+', '').Trim()
                    if ($description -and $description -ne $line.Trim()) {
                        $descriptions[$normalized] = $description
                    }
                }
                }
            }
        }

        if ($options.Count -gt 0) {
            Set-Variable -Name 'FactorCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'FactorCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'FactorCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'FactorCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'FactorCompletionOptions' -Scope Script).Value
}

function New-FactorCompletionResult {
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

function Get-FactorCurrentToken {
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

function Get-FactorValueCompletions {
    param([string]$WordToComplete)

    # The placeholder is only safe in an empty slot; returned against a typed prefix it would
    # replace the user's digits with the literal '<number>'.
    if (-not [string]::IsNullOrEmpty($WordToComplete)) {
        return @()
    }

    @(
        New-FactorCompletionResult -CompletionText '<number>' -ListItemText '<number>' -ResultType 'ParameterValue' -ToolTip 'Integer operand for factor.'
    )
}

function Get-FactorOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'FactorCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for factor.'
}

function Complete-Factor {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $commandText = $commandAst.ToString()
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-FactorCurrentToken -Line $commandText -CursorPosition $relativeCursor -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        # An empty word with a token starting right at the cursor ('factor --version |1') is not a
        # free slot; inserting the placeholder there would corrupt that token.
        if ($relativeCursor -lt $commandText.Length -and -not [char]::IsWhiteSpace($commandText[$relativeCursor])) {
            return @()
        }

        return Get-FactorValueCompletions -WordToComplete ''
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-FactorCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-FactorCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-FactorOptionDescription -Option $option)
                }
            }
        )
    }

    Get-FactorValueCompletions -WordToComplete $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'factor', 'factor.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Factor -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
