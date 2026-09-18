# printenv tab completion for PowerShell
# Static option completion for printenv.exe and printenv.

Set-StrictMode -Version 2.0

function Get-PrintenvCompletionOptions {
    $cache = Get-Variable -Name 'PrintenvCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-0', '--null', '--help', '--version')
    $commandCandidates = @('printenv.exe', 'printenv')
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
            Set-Variable -Name 'PrintenvCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'PrintenvCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'PrintenvCompletionOptions' -Scope Script).Value
        }
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-PrintenvValueCompletions {
    $envVars = @(Get-ChildItem Env: | Sort-Object -Property Name)
    $values = @()
    foreach ($entry in $envVars) {
        $values += New-PrintenvCompletionResult -CompletionText $entry.Name -ListItemText $entry.Name -ResultType 'ParameterValue' -ToolTip $entry.Value
    }

    $values
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

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-PrintenvCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-PrintenvCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-PrintenvOptionDescription -Option $option)
                }
            }
        )
    }

    $prefix = $currentWord
    $matches = @(Get-PrintenvValueCompletions | Where-Object { $_.CompletionText -like ([System.Management.Automation.WildcardPattern]::Escape($prefix) + '*') -or $_.ListItemText -like ([System.Management.Automation.WildcardPattern]::Escape($prefix) + '*') })
    if ($matches.Count -gt 0) {
        return $matches
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'printenv', 'printenv.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Printenv -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
