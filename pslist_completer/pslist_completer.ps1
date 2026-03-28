# pslist tab completion for PowerShell
# Builds a static-first native completer for pslist with safe help capture and local process hints.
# Usage: . .\pslist_completer.ps1

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name PslistCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PslistCompletionCatalog = @{
        Initialized             = $false
        SwitchOrder             = @('-d', '-m', '-x', '-t', '-s', '-r', '-nobanner', '-u', '-p', '-e', '-?', '/?')
        SwitchInfo              = @{}
        PositionalInfo          = @{}
        SampleSecondsHints      = @('1', '2', '5', '10')
        RefreshSecondsHints     = @('1', '2', '5', '10')
        ProcessEntries          = @()
        ProcessCacheUpdated     = [datetime]::MinValue
        ProcessCacheTtlSeconds  = 2
    }
}

function New-PslistCompletionResult {
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

function Get-PslistStaticSwitchCatalog {
    [ordered]@{
        '-d'        = 'Show thread detail.'
        '-m'        = 'Show memory detail.'
        '-x'        = 'Show processes, memory information, and threads.'
        '-t'        = 'Show process tree.'
        '-s'        = 'Run in task-manager mode, optionally specifying sample seconds.'
        '-r'        = 'Task-manager mode refresh rate in seconds (default is 1).'
        '-nobanner' = 'Do not display the startup banner and copyright message.'
        '-u'        = 'Optional user name for remote login.'
        '-p'        = 'Optional password for remote login. Prompts if omitted when needed.'
        '-e'        = 'Exact-match the process name. Valid only with a process name target.'
        '-?'        = 'Display pslist help.'
        '/?'        = 'Display pslist help.'
    }
}

function Get-PslistStaticPositionalCatalog {
    [ordered]@{
        '\\computer' = 'Remote computer placeholder.'
        'name'       = 'Process name prefix to query.'
        'pid'        = 'Process ID to query.'
    }
}

function Get-PslistCommandPath {
    $command = Get-Command -Name pslist.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $command = Get-Command -Name pslist -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $null
}

function Ensure-PslistCommandAlias {
    $existingAlias = Get-Alias -Name pslist -ErrorAction SilentlyContinue
    if ($existingAlias) {
        return
    }

    $pslistExeCommand = Get-Command -Name pslist.exe -ErrorAction SilentlyContinue
    if (-not $pslistExeCommand) {
        return
    }

    $pslistCommand = Get-Command -Name pslist -ErrorAction SilentlyContinue
    if ($pslistCommand -and
        ($pslistCommand.CommandType -ne 'Application' -or $pslistCommand.Name -ne 'pslist.exe')) {
        return
    }

    Set-Alias -Name pslist -Value pslist.exe -Option AllScope -Scope Global
}

function Invoke-PslistHelpText {
    $commandPath = Get-PslistCommandPath
    if (-not $commandPath) {
        return @()
    }

    try {
        @(
            & $commandPath '/?' 2>&1 |
                ForEach-Object { $_.ToString() }
        )
    } catch {
        @()
    }
}

function Get-PslistHelpEntryMap {
    param([string[]]$Lines)

    $result = @{}
    $currentKey = $null

    foreach ($line in $Lines) {
        if ($line -match '^\s*(-d|-m|-x|-t|-s|-r|-u|-p|-e|-nobanner|-\?|/\?|\\\\computer|name|pid)\s{2,}(.*)$') {
            $currentKey = $matches[1].ToLowerInvariant()
            $result[$currentKey] = [System.Collections.Generic.List[string]]::new()

            if (-not [string]::IsNullOrWhiteSpace($matches[2])) {
                $result[$currentKey].Add($matches[2].Trim())
            }

            continue
        }

        if ($currentKey -and $line -match '^\s{10,}(\S.*)$') {
            $result[$currentKey].Add($matches[1].Trim())
            continue
        }

        $currentKey = $null
    }

    $map = @{}
    foreach ($entry in $result.GetEnumerator()) {
        $map[$entry.Key] = ($entry.Value -join ' ')
    }

    $map
}

function Initialize-PslistCompletionCatalog {
    if ($script:PslistCompletionCatalog.Initialized) {
        return
    }

    $script:PslistCompletionCatalog.SwitchInfo = @{}
    foreach ($entry in (Get-PslistStaticSwitchCatalog).GetEnumerator()) {
        $script:PslistCompletionCatalog.SwitchInfo[$entry.Key] = $entry.Value
    }

    $script:PslistCompletionCatalog.PositionalInfo = @{}
    foreach ($entry in (Get-PslistStaticPositionalCatalog).GetEnumerator()) {
        $script:PslistCompletionCatalog.PositionalInfo[$entry.Key] = $entry.Value
    }

    $helpEntryMap = Get-PslistHelpEntryMap -Lines (Invoke-PslistHelpText)
    foreach ($entry in $helpEntryMap.GetEnumerator()) {
        if ($script:PslistCompletionCatalog.SwitchInfo.ContainsKey($entry.Key)) {
            $script:PslistCompletionCatalog.SwitchInfo[$entry.Key] = $entry.Value
            continue
        }

        if ($script:PslistCompletionCatalog.PositionalInfo.ContainsKey($entry.Key)) {
            $script:PslistCompletionCatalog.PositionalInfo[$entry.Key] = $entry.Value
        }
    }

    $script:PslistCompletionCatalog.Initialized = $true
}

function Get-PslistCurrentToken {
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Remove-PslistOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function Test-PslistNumericToken {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $Value -match '^\d+$'
}

function Test-PslistHelpAlias {
    param([string]$Value)

    $Value -in @('-?', '/?')
}

function Test-PslistSwitchLikeToken {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    if (Test-PslistHelpAlias -Value $Value) {
        return $true
    }

    $Value.StartsWith('-')
}

function Get-PslistCommandState {
    param([object[]]$TokensBeforeCurrent)

    $TokensBeforeCurrent = @($TokensBeforeCurrent)

    $usedSwitchLookup = @{}
    $valuesBySwitch = @{}
    $remoteTarget = $null
    $processTarget = $null

    for ($index = 0; $index -lt $TokensBeforeCurrent.Count; $index++) {
        $token = $TokensBeforeCurrent[$index]
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        if (Test-PslistSwitchLikeToken -Value $token) {
            $switchKey = $token.ToLowerInvariant()
            $usedSwitchLookup[$switchKey] = $true

            switch ($switchKey) {
                '-s' {
                    if ($index + 1 -lt $TokensBeforeCurrent.Count -and
                        (Test-PslistNumericToken -Value $TokensBeforeCurrent[$index + 1])) {
                        $valuesBySwitch[$switchKey] = $TokensBeforeCurrent[$index + 1]
                        $index++
                    }
                }
                '-r' {
                    if ($index + 1 -lt $TokensBeforeCurrent.Count -and
                        -not (Test-PslistSwitchLikeToken -Value $TokensBeforeCurrent[$index + 1])) {
                        $valuesBySwitch[$switchKey] = $TokensBeforeCurrent[$index + 1]
                        $index++
                    }
                }
                '-u' {
                    if ($index + 1 -lt $TokensBeforeCurrent.Count -and
                        -not (Test-PslistSwitchLikeToken -Value $TokensBeforeCurrent[$index + 1])) {
                        $valuesBySwitch[$switchKey] = $TokensBeforeCurrent[$index + 1]
                        $index++
                    }
                }
                '-p' {
                    if ($index + 1 -lt $TokensBeforeCurrent.Count -and
                        -not (Test-PslistSwitchLikeToken -Value $TokensBeforeCurrent[$index + 1])) {
                        $valuesBySwitch[$switchKey] = $TokensBeforeCurrent[$index + 1]
                        $index++
                    }
                }
            }

            continue
        }

        if ($token.StartsWith('\\')) {
            if (-not $remoteTarget) {
                $remoteTarget = $token
            }

            continue
        }

        if (-not $processTarget) {
            $processTarget = $token
        }
    }

    $valueContext = $null
    if ($TokensBeforeCurrent.Count -gt 0) {
        $lastToken = $TokensBeforeCurrent[-1]
        if (Test-PslistSwitchLikeToken -Value $lastToken) {
            $lastKey = $lastToken.ToLowerInvariant()
            if ($lastKey -in @('-s', '-r', '-u', '-p')) {
                $valueContext = $lastKey
            }
        }
    }

    $processTargetKind = $null
    if ($processTarget) {
        if (Test-PslistNumericToken -Value (Remove-PslistOuterQuotes -Value $processTarget)) {
            $processTargetKind = 'Pid'
        } else {
            $processTargetKind = 'Name'
        }
    }

    [pscustomobject]@{
        UsedSwitchLookup = $usedSwitchLookup
        ValuesBySwitch   = $valuesBySwitch
        ValueContext     = $valueContext
        RemoteTarget     = $remoteTarget
        ProcessTarget    = $processTarget
        ProcessTargetKind = $processTargetKind
        HasHelp          = ($usedSwitchLookup.ContainsKey('-?') -or $usedSwitchLookup.ContainsKey('/?'))
    }
}

function Get-PslistPlaceholderValueCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$Candidates,
        [string]$GenericToolTip
    )

    $typedValue = Remove-PslistOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $candidate.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $results.Add((New-PslistCompletionResult -CompletionText $candidate -ResultType 'ParameterValue' -ToolTip $GenericToolTip))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-PslistCompletionResult -CompletionText $CurrentWord -ResultType 'ParameterValue' -ToolTip $GenericToolTip))
    }

    @($results.ToArray())
}

function Get-PslistNumericValueCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$Candidates,
        [string]$ToolTip
    )

    if (Test-PslistSwitchLikeToken -Value $CurrentWord) {
        return @()
    }

    $typedValue = Remove-PslistOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $candidate.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $results.Add((New-PslistCompletionResult -CompletionText $candidate -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0 -and (Test-PslistNumericToken -Value $typedValue)) {
        $results.Add((New-PslistCompletionResult -CompletionText $typedValue -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    @($results.ToArray())
}

function Update-PslistProcessCache {
    $cacheAge = (Get-Date) - $script:PslistCompletionCatalog.ProcessCacheUpdated
    if ($cacheAge.TotalSeconds -lt $script:PslistCompletionCatalog.ProcessCacheTtlSeconds) {
        return
    }

    $nameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $idSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $processNames = [System.Collections.Generic.List[string]]::new()
    $processIds = [System.Collections.Generic.List[int]]::new()

    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($process.ProcessName -and $nameSet.Add($process.ProcessName)) {
            $processNames.Add($process.ProcessName)
        }

        $processIdText = [string]$process.Id
        if ($processIdText -and $idSet.Add($processIdText)) {
            $processIds.Add($process.Id)
        }
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($processName in @($processNames | Sort-Object)) {
        $entries.Add([pscustomobject]@{
                CompletionText = $processName
                ResultType     = 'ParameterValue'
                ToolTip        = "Local process name $processName"
            })
    }

    foreach ($processId in @($processIds | Sort-Object)) {
        $processIdText = [string]$processId
        $entries.Add([pscustomobject]@{
                CompletionText = $processIdText
                ResultType     = 'ParameterValue'
                ToolTip        = "Local process ID $processIdText"
            })
    }

    $script:PslistCompletionCatalog.ProcessEntries = @($entries)
    $script:PslistCompletionCatalog.ProcessCacheUpdated = Get-Date
}

function Get-PslistLocalProcessTargetCompletions {
    param([string]$CurrentWord)

    Update-PslistProcessCache

    $typedValue = Remove-PslistOuterQuotes -Value $CurrentWord
    $script:PslistCompletionCatalog.ProcessEntries |
        Where-Object {
            [string]::IsNullOrWhiteSpace($typedValue) -or
            $_.CompletionText.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)
        } |
        ForEach-Object {
            New-PslistCompletionResult -CompletionText $_.CompletionText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }
}

function Get-PslistRemoteProcessTargetCompletions {
    param([string]$CurrentWord)

    Get-PslistPlaceholderValueCompletions `
        -CurrentWord $CurrentWord `
        -Candidates @('<process-name>', '<pid>') `
        -GenericToolTip 'Remote process target. pslist completion does not enumerate remote process names or PIDs.'
}

function Get-PslistRemoteComputerCompletions {
    param([string]$CurrentWord)

    if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $CurrentWord.StartsWith('\')) {
        return @()
    }

    Get-PslistPlaceholderValueCompletions `
        -CurrentWord $CurrentWord `
        -Candidates @('\\computer') `
        -GenericToolTip $script:PslistCompletionCatalog.PositionalInfo['\\computer']
}

function Get-PslistSwitchCompletions {
    param(
        [string]$CurrentWord,
        [psobject]$State
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($switchText in $script:PslistCompletionCatalog.SwitchOrder) {
        $key = $switchText.ToLowerInvariant()
        if ($State.UsedSwitchLookup.ContainsKey($key)) {
            continue
        }

        $includeSwitch = $true
        switch ($key) {
            '-u' {
                if (-not $State.RemoteTarget) {
                    $includeSwitch = $false
                }
            }
            '-p' {
                if (-not $State.RemoteTarget) {
                    $includeSwitch = $false
                }
            }
            '-r' {
                if (-not $State.UsedSwitchLookup.ContainsKey('-s')) {
                    $includeSwitch = $false
                }
            }
            '-e' {
                if ($State.ProcessTargetKind -ne 'Name') {
                    $includeSwitch = $false
                }
            }
            '-?' {
                if ($State.UsedSwitchLookup.Count -gt 0 -or $State.RemoteTarget -or $State.ProcessTarget) {
                    $includeSwitch = $false
                }
            }
            '/?' {
                if ($State.UsedSwitchLookup.Count -gt 0 -or $State.RemoteTarget -or $State.ProcessTarget) {
                    $includeSwitch = $false
                }
            }
        }

        if (-not $includeSwitch) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            -not $switchText.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $results.Add((
                New-PslistCompletionResult `
                    -CompletionText $switchText `
                    -ResultType 'ParameterName' `
                    -ToolTip $script:PslistCompletionCatalog.SwitchInfo[$key]
            ))
    }

    @($results.ToArray())
}

function Get-PslistTerminalCompletions {
    param([string]$CurrentWord)

    $completionText = if ([string]::IsNullOrEmpty($CurrentWord)) { ' ' } else { $CurrentWord }
    @(
        New-PslistCompletionResult `
            -CompletionText $completionText `
            -ResultType 'ParameterValue' `
            -ToolTip 'No further arguments are valid after pslist help.'
    )
}

function Complete-Pslist {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-PslistCompletionCatalog

    [object[]]$allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    [object[]]$tokens = if ($allTokens.Count -gt 1) {
        @($allTokens | Select-Object -Skip 1)
    } else {
        @()
    }

    $line = $commandAst.ToString()
    $currentWord = if ($null -eq $wordToComplete) {
        Get-PslistCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback ''
    } elseif ($wordToComplete.Length -eq 0) {
        ''
    } elseif ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        Get-PslistCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
    } else {
        $wordToComplete
    }

    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)
    [object[]]$tokensBeforeCurrent = if ($hasTrailingSpace) {
        @($tokens)
    } elseif ($tokens.Count -gt 0) {
        @($tokens | Select-Object -First ($tokens.Count - 1))
    } else {
        @()
    }

    $state = Get-PslistCommandState -TokensBeforeCurrent $tokensBeforeCurrent
    if ($state.HasHelp) {
        return @(Get-PslistTerminalCompletions -CurrentWord $currentWord)
    }

    switch ($state.ValueContext) {
        '-s' {
            if (Test-PslistSwitchLikeToken -Value $currentWord) {
                return @(Get-PslistSwitchCompletions -CurrentWord $currentWord -State $state)
            }

            $numericResults = @(Get-PslistNumericValueCompletions -CurrentWord $currentWord -Candidates $script:PslistCompletionCatalog.SampleSecondsHints -ToolTip 'Optional task-manager mode sample interval in seconds.')
            if ([string]::IsNullOrWhiteSpace($currentWord)) {
                return @(
                    $numericResults
                    Get-PslistSwitchCompletions -CurrentWord '' -State $state
                )
            }

            return $numericResults
        }
        '-r' {
            if (Test-PslistSwitchLikeToken -Value $currentWord) {
                return @(Get-PslistSwitchCompletions -CurrentWord $currentWord -State $state)
            }

            return @(Get-PslistNumericValueCompletions -CurrentWord $currentWord -Candidates $script:PslistCompletionCatalog.RefreshSecondsHints -ToolTip 'Task-manager mode refresh rate in seconds.')
        }
        '-u' {
            if (Test-PslistSwitchLikeToken -Value $currentWord) {
                return @(Get-PslistSwitchCompletions -CurrentWord $currentWord -State $state)
            }

            return @(Get-PslistPlaceholderValueCompletions -CurrentWord $currentWord -Candidates @('<username>') -GenericToolTip 'Remote user name.')
        }
        '-p' {
            if (Test-PslistSwitchLikeToken -Value $currentWord) {
                return @(Get-PslistSwitchCompletions -CurrentWord $currentWord -State $state)
            }

            return @(Get-PslistPlaceholderValueCompletions -CurrentWord $currentWord -Candidates @('<password>') -GenericToolTip 'Remote password. If omitted, pslist may prompt interactively.')
        }
    }

    if (Test-PslistSwitchLikeToken -Value $currentWord) {
        return @(Get-PslistSwitchCompletions -CurrentWord $currentWord -State $state)
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($completion in @(Get-PslistSwitchCompletions -CurrentWord '' -State $state)) {
        $results.Add($completion)
    }

    if (-not $state.ProcessTarget) {
        if ($state.RemoteTarget) {
            foreach ($completion in @(Get-PslistRemoteProcessTargetCompletions -CurrentWord $currentWord)) {
                $results.Add($completion)
            }
        } else {
            foreach ($completion in @(Get-PslistRemoteComputerCompletions -CurrentWord $currentWord)) {
                $results.Add($completion)
            }

            if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('\')) {
                return @($results.ToArray())
            }

            foreach ($completion in @(Get-PslistLocalProcessTargetCompletions -CurrentWord $currentWord)) {
                $results.Add($completion)
            }
        }
    }

    @($results.ToArray())
}

Ensure-PslistCommandAlias

Register-ArgumentCompleter -Native -CommandName @('pslist', 'pslist.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pslist -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
