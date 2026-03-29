# pskill.exe tab completion for PowerShell
# Native completer for PsKill with static switches, remote placeholders, and local process hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name PsKillCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PsKillCompletionCatalog = @{
        SwitchOrder             = @('-t', '-u', '-p', '-nobanner', '-?', '/?', '--help')
        SwitchInfo              = @{
            '-t'        = 'Kill the process and its descendants.'
            '-u'        = 'Optional user name for remote login.'
            '-p'        = 'Optional password for the remote login.'
            '-nobanner' = 'Do not display the startup banner and copyright message.'
            '-?'        = 'Display pskill help.'
            '/?'        = 'Display pskill help.'
            '--help'    = 'Display pskill help.'
        }
        ProcessEntries          = @()
        ProcessCacheUpdated     = [datetime]::MinValue
        ProcessCacheTtlSeconds  = 2
    }
}

function New-PsKillCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $CompletionText,
        $ResultType,
        $ToolTip
    )
}

function Get-PsKillCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    if ($CursorPosition -gt $Line.Length) {
        return ''
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') {
        return ''
    }

    $parts = @([regex]::Matches($prefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Remove-PsKillOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function Update-PsKillProcessCache {
    $cacheAge = (Get-Date) - $script:PsKillCompletionCatalog.ProcessCacheUpdated
    if ($cacheAge.TotalSeconds -lt $script:PsKillCompletionCatalog.ProcessCacheTtlSeconds) {
        return
    }

    $nameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $idSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $entries = [System.Collections.Generic.List[object]]::new()

    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($process.ProcessName -and $nameSet.Add($process.ProcessName)) {
            $entries.Add([pscustomobject]@{
                    CompletionText = $process.ProcessName
                    ResultType     = 'ParameterValue'
                    ToolTip        = "Process name $($process.ProcessName)"
                })
        }

        $processIdText = [string]$process.Id
        if ($processIdText -and $idSet.Add($processIdText)) {
            $entries.Add([pscustomobject]@{
                    CompletionText = $processIdText
                    ResultType     = 'ParameterValue'
                    ToolTip        = "Process ID $processIdText"
                })
        }
    }

    $script:PsKillCompletionCatalog.ProcessEntries = @(
        $entries |
            Sort-Object -Property CompletionText
    )
    $script:PsKillCompletionCatalog.ProcessCacheUpdated = Get-Date
}

function New-PsKillLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-PsKillCompletionResult -CompletionText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-PsKillCompletionResult -CompletionText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-PsKillProcessCompletions {
    param([string]$CurrentWord)

    Update-PsKillProcessCache

    $typedValue = Remove-PsKillOuterQuotes -Value $CurrentWord
    $results = $script:PsKillCompletionCatalog.ProcessEntries |
        Where-Object {
            [string]::IsNullOrWhiteSpace($typedValue) -or $_.CompletionText.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)
        } |
        ForEach-Object {
            New-PsKillCompletionResult -CompletionText $_.CompletionText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }

    if (@($results).Count -gt 0) {
        return @($results)
    }

    @(New-PsKillLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<process-or-pid>' -ToolTip 'Process name or PID.')
}

function Get-PsKillCommandState {
    param([object[]]$TokensBeforeCurrent)

    $TokensBeforeCurrent = @($TokensBeforeCurrent)

    $usedSwitchLookup = @{}
    $valueContext = $null
    $remoteTarget = $null
    $remoteUser = $null
    $remotePassword = $null
    $processTarget = $null
    $helpRequested = $false

    for ($index = 0; $index -lt $TokensBeforeCurrent.Count; $index++) {
        $token = [string]$TokensBeforeCurrent[$index]
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        $lookup = $token.ToLowerInvariant()

        if ($lookup -in @('-?', '/?', '--help')) {
            $helpRequested = $true
            $usedSwitchLookup[$lookup] = $true
            continue
        }

        if ($lookup -in @('-u', '-p')) {
            $usedSwitchLookup[$lookup] = $true
            if ($index -eq ($TokensBeforeCurrent.Count - 1)) {
                $valueContext = $lookup
                break
            }

            if ($lookup -eq '-u') {
                $remoteUser = [string]$TokensBeforeCurrent[$index + 1]
            } else {
                $remotePassword = [string]$TokensBeforeCurrent[$index + 1]
            }

            $index++
            continue
        }

        if ($lookup.StartsWith('-')) {
            $usedSwitchLookup[$lookup] = $true
            continue
        }

        if (-not $remoteTarget -and $token.StartsWith('\\')) {
            $remoteTarget = $token
            continue
        }

        if (-not $processTarget) {
            $processTarget = $token
        }
    }

    [pscustomobject]@{
        UsedSwitchLookup = $usedSwitchLookup
        ValueContext     = $valueContext
        RemoteTarget     = $remoteTarget
        RemoteUser       = $remoteUser
        RemotePassword   = $remotePassword
        ProcessTarget    = $processTarget
        HelpRequested    = $helpRequested
    }
}

function Get-PsKillSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State,
        [bool]$NoArgumentsYet
    )

    $prefix = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '' } else { $CurrentWord }
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($token in $script:PsKillCompletionCatalog.SwitchOrder) {
        if (-not [string]::IsNullOrWhiteSpace($prefix) -and
            -not $token.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ($token -in @('-?', '/?', '--help')) {
            if (-not $NoArgumentsYet) {
                continue
            }
        } elseif ($State.UsedSwitchLookup.ContainsKey($token)) {
            continue
        }

        $results.Add((New-PsKillCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $script:PsKillCompletionCatalog.SwitchInfo[$token]))
    }

    @($results.ToArray())
}

function Complete-PsKill {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $line = $commandAst.ToString()
    $safeCursor = [Math]::Min([Math]::Max($cursorPosition, 0), $line.Length)
    $linePrefix = $line.Substring(0, $safeCursor)
    $commandTokens = @([regex]::Matches($linePrefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    [object[]]$argumentTokens = if ($commandTokens.Count -gt 1) {
        @($commandTokens | Select-Object -Skip 1)
    } else {
        @()
    }
    $argumentTokens = @($argumentTokens)

    $currentWord = if ([string]::IsNullOrEmpty($wordToComplete)) {
        Get-PsKillCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
    } else {
        $wordToComplete
    }

    $hasTrailingSpace = [string]::IsNullOrEmpty($currentWord) -and (($linePrefix -match '\s$') -or ($cursorPosition -gt $line.Length))
    [object[]]$tokensBeforeCurrent = if ($hasTrailingSpace) {
        @($argumentTokens)
    } elseif ($argumentTokens.Count -gt 0) {
        @($argumentTokens | Select-Object -First ($argumentTokens.Count - 1))
    } else {
        @()
    }
    $tokensBeforeCurrent = @($tokensBeforeCurrent)

    $state = Get-PsKillCommandState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.HelpRequested) {
        return @(
            New-PsKillCompletionResult -CompletionText '-?' -ResultType 'ParameterName' -ToolTip 'Display pskill help.'
        )
    }

    switch ($state.ValueContext) {
        '-u' {
            return @(New-PsKillLiteralValueResults -CurrentValue $currentWord -Placeholder '<username>' -ToolTip 'Remote user name.')
        }
        '-p' {
            return @(New-PsKillLiteralValueResults -CurrentValue $currentWord -Placeholder '<password>' -ToolTip 'Remote password.')
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('\\')) {
        return @(
            New-PsKillCompletionResult -CompletionText '\\computer' -ResultType 'ParameterValue' -ToolTip 'Remote computer placeholder.'
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-PsKillSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet:($tokensBeforeCurrent.Count -eq 0))
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @(Get-PsKillSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet:($tokensBeforeCurrent.Count -eq 0))) {
            $results.Add($item)
        }

        if (-not $state.ProcessTarget) {
            if ($state.RemoteTarget) {
                $results.Add((New-PsKillCompletionResult -CompletionText '<process-name>' -ResultType 'ParameterValue' -ToolTip 'Remote process name.'))
                $results.Add((New-PsKillCompletionResult -CompletionText '<pid>' -ResultType 'ParameterValue' -ToolTip 'Remote process ID.'))
            } else {
                $results.Add((New-PsKillCompletionResult -CompletionText '\\computer' -ResultType 'ParameterValue' -ToolTip 'Remote computer placeholder.'))
                foreach ($item in @(Get-PsKillProcessCompletions -CurrentWord '')) {
                    $results.Add($item)
                }
            }
        }

        return @($results.ToArray())
    }

    if (-not $state.ProcessTarget) {
        if ($state.RemoteTarget) {
            return @(
                New-PsKillLiteralValueResults -CurrentValue $currentWord -Placeholder '<process-or-pid>' -ToolTip 'Remote process name or PID.'
            )
        }

        return @(Get-PsKillProcessCompletions -CurrentWord $currentWord)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('pskill', 'pskill.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-PsKill -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
