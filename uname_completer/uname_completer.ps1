# uname tab completion for PowerShell
# Static option completion for uname.exe and uname.

Set-StrictMode -Version 2.0

function Get-UnameCompletionOptions {
    $cache = Get-Variable -Name 'UnameCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-a', '--all', '-s', '--kernel-name', '-n', '--nodename', '-r', '--kernel-release', '-v', '--kernel-version', '-m', '--machine', '-p', '--processor', '-i', '--hardware-platform', '-o', '--operating-system', '--help', '--version')
    $commandCandidates = @('uname.exe', 'uname')
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
            Set-Variable -Name 'UnameCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'UnameCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'UnameCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'UnameCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'UnameCompletionOptions' -Scope Script).Value
}

function New-UnameCompletionResult {
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

function Get-UnameCurrentToken {
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

function Get-UnameShortFlagClusterCompletions {
    param([string]$CurrentWord)

    # uname parses with getopt_long, so '-sn' is '-s -n'; extend a cluster of known short flags
    # with each flag not yet in it.
    if ($CurrentWord -notmatch '^-[A-Za-z]{2,}$') {
        return @()
    }

    $shortFlags = @(Get-UnameCompletionOptions | Where-Object { $_ -cmatch '^-[A-Za-z]$' })
    $usedLetters = @($CurrentWord.Substring(1).ToCharArray() | ForEach-Object { [string]$_ })
    foreach ($letter in $usedLetters) {
        if (('-' + $letter) -cnotin $shortFlags) {
            return @()
        }
    }

    @(
        foreach ($flag in $shortFlags) {
            $letter = $flag.Substring(1)
            if ($letter -cin $usedLetters) {
                continue
            }

            $clustered = $CurrentWord + $letter
            New-UnameCompletionResult -CompletionText $clustered -ListItemText $clustered -ResultType 'ParameterName' -ToolTip ('{0}: {1}' -f $flag, (Get-UnameOptionDescription -Option $flag))
        }
    )
}

function Get-UnameOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'UnameCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for uname.'
}

function Complete-Uname {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-UnameCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    # uname takes no operands ('Usage: uname [OPTION]...'), so the empty slot offers the option
    # catalog and a typed non-option word gets nothing from this completer.
    if ([string]::IsNullOrEmpty($currentWord) -or $currentWord.StartsWith('-')) {
        $optionMatches = @(
            foreach ($option in Get-UnameCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-UnameCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-UnameOptionDescription -Option $option)
                }
            }
        )
        if ($optionMatches.Count -gt 0) {
            return $optionMatches
        }

        return Get-UnameShortFlagClusterCompletions -CurrentWord $currentWord
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'uname', 'uname.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Uname -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
