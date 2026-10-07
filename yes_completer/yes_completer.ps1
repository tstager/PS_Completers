# yes tab completion for PowerShell
# Static option completion for yes.exe and yes.

Set-StrictMode -Version 2.0

function Get-YesCompletionOptions {
    $cache = Get-Variable -Name 'YesCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('--help', '--version')
    $commandCandidates = @('yes.exe', 'yes')
    foreach ($candidate in $commandCandidates) {
        $command = Get-Command -Name $candidate -ErrorAction Ignore
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
            Set-Variable -Name 'YesCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'YesCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'YesCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'YesCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'YesCompletionOptions' -Scope Script).Value
}

function New-YesCompletionResult {
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

function Get-YesCurrentToken {
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"?|''[^'']*''?|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-YesValueCompletions {
    param([string]$WordToComplete)

    # 'yes [STRING]...' repeats literal text ([default: y]), never a file. The placeholder only
    # describes the empty slot; against a typed prefix it would replace the user's text.
    $values = @(
        @{ Text = 'y'; Tip = 'Repeat y (the default when no STRING is given).' }
        @{ Text = 'n'; Tip = 'Repeat n, to answer no to every prompt.' }
    )

    @(
        if ([string]::IsNullOrEmpty($WordToComplete)) {
            New-YesCompletionResult -CompletionText '<string>' -ListItemText '<string>' -ResultType 'ParameterValue' -ToolTip 'Text to print repeatedly; default y.'
        }

        foreach ($value in $values) {
            if ($value.Text.StartsWith($WordToComplete, [System.StringComparison]::Ordinal)) {
                New-YesCompletionResult -CompletionText $value.Text -ListItemText $value.Text -ResultType 'ParameterValue' -ToolTip $value.Tip
            }
        }
    )
}

function Get-YesOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'YesCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for yes.'
}

function Complete-Yes {
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
        Get-YesCurrentToken -Line $commandText -CursorPosition $relativeCursor -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        # An empty word with a token starting right at the cursor ('yes |--help') is not a free
        # slot; inserting a value there would corrupt that token.
        if ($relativeCursor -lt $commandText.Length -and -not [char]::IsWhiteSpace($commandText[$relativeCursor])) {
            return @()
        }

        return Get-YesValueCompletions -WordToComplete ''
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-YesCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-YesCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-YesOptionDescription -Option $option)
                }
            }
        )
    }

    Get-YesValueCompletions -WordToComplete $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'yes', 'yes.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Yes -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
