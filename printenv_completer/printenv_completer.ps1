# printenv tab completion for PowerShell
# Static option completion for printenv.exe and printenv.

Set-StrictMode -Version 2.0

function Get-PrintenvCompletionOptions {
    $cache = Get-Variable -Name 'PrintenvCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-0', '--null', '--help', '--version')
    $options = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $descriptions = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)

    # Every distinct printenv on PATH contributes its options (Git for Windows GNU 8.32 and uutils
    # both ship one), so -h/-V from the second build are reachable even when the first resolves.
    $sources = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $commands = @(Get-Command -Name 'printenv.exe', 'printenv' -CommandType Application -All -ErrorAction Ignore)
    foreach ($command in $commands) {
        if ([string]::IsNullOrWhiteSpace($command.Source) -or -not $sources.Add($command.Source)) {
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
    }

    if ($options.Count -gt 0) {
        Set-Variable -Name 'PrintenvCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
        Set-Variable -Name 'PrintenvCompletionDescriptions' -Value $descriptions -Scope Script
        return (Get-Variable -Name 'PrintenvCompletionOptions' -Scope Script).Value
    }

    Set-Variable -Name 'PrintenvCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'PrintenvCompletionOptions' -Scope Script).Value
}

function New-PrintenvCompletionResult {
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

function Get-PrintenvCurrentToken {
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

function Get-PrintenvValueCompletions {
    param([string]$Prefix = '')

    # A quoted or half-quoted token ('"PA') is matched on its bare text and the completion is
    # re-quoted the same way so the replacement stays valid.
    $quote = ''
    $bare = $Prefix
    if ($bare.Length -gt 0 -and ($bare[0] -eq '"' -or $bare[0] -eq "'")) {
        $quote = [string]$bare[0]
        $bare = $bare.Substring(1)
        if ($bare.EndsWith($quote)) {
            $bare = $bare.Substring(0, $bare.Length - 1)
        }
    }

    $pattern = [System.Management.Automation.WildcardPattern]::Escape($bare) + '*'
    @(
        foreach ($entry in @(Get-ChildItem Env: | Sort-Object -Property Name)) {
            if ($entry.Name -like $pattern) {
                New-PrintenvCompletionResult -CompletionText ($quote + $entry.Name + $quote) -ListItemText $entry.Name -ResultType 'ParameterValue' -ToolTip $entry.Value
            }
        }
    )
}

function Get-PrintenvOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'PrintenvCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for printenv.'
}

function Complete-Printenv {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-PrintenvCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-PrintenvCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-PrintenvCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-PrintenvOptionDescription -Option $option)
                }
            }
        )
    }

    # printenv's only operand is an environment-variable name; the empty slot lists them all.
    Get-PrintenvValueCompletions -Prefix $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'printenv', 'printenv.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Printenv -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
