# Testlimit.exe tab completion for PowerShell
# Static native completer for Testlimit with numeric hints and placeholder-driven value completion.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name TestlimitCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:TestlimitCompletionCatalog = @{
        SwitchOrder = @('-a', '-c', '-d', '-e', '-g', '-h', '-i', '-l', '-m', '-n', '-p', '-r', '-s', '-t', '-u', '-v', '-w', '-?', '/?')
        SwitchInfo  = @{
            '-a' = 'Leak Address Windowing Extensions memory in MB.'
            '-c' = 'Count of objects to allocate. This must be the last option specified.'
            '-d' = 'Leak and touch memory in MB.'
            '-e' = 'Seconds elapsed between allocations.'
            '-g' = 'Create GDI handles of the specified size.'
            '-h' = 'Create handles. Add -u to also allocate file objects.'
            '-i' = 'Exhaust USER desktop heap.'
            '-l' = 'Allocate the specified amount of large pages.'
            '-m' = 'Leak memory in MB.'
            '-n' = 'Nested option for -p or -t. With -t it can take a stack reserve KB value.'
            '-p' = 'Create processes. Add -n to set min working set behavior.'
            '-r' = 'Reserve memory in MB.'
            '-s' = 'Leak shared memory in MB.'
            '-t' = 'Create threads. Add -n to specify minimum stack reserve in KB.'
            '-u' = 'Create USER handles to menus.'
            '-v' = 'VirtualLock memory in MB.'
            '-w' = 'Reset working set minimum to the highest possible value.'
            '-?' = 'Display Testlimit help.'
            '/?' = 'Display Testlimit help.'
        }
    }
}

function New-TestlimitCompletionResult {
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

function Get-TestlimitCurrentToken {
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

function New-TestlimitLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-TestlimitCompletionResult -CompletionText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-TestlimitCompletionResult -CompletionText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-TestlimitSampleValueResults {
    param(
        [string]$CurrentValue,
        [string[]]$Samples,
        [string]$Placeholder,
        [string]$ToolTip
    )

    $typedValue = if ([string]::IsNullOrWhiteSpace($CurrentValue)) { '' } else { $CurrentValue.Trim('"') }
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($sample in $Samples) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $sample.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $results.Add((New-TestlimitCompletionResult -CompletionText $sample -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ([string]::IsNullOrWhiteSpace($typedValue) -or
        $Placeholder.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        $results.Add((New-TestlimitCompletionResult -CompletionText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0) {
        return @(New-TestlimitLiteralValueResults -CurrentValue $CurrentValue -Placeholder $Placeholder -ToolTip $ToolTip)
    }

    @($results.ToArray())
}

function Get-TestlimitCommandState {
    param([object[]]$TokensBeforeCurrent)

    $TokensBeforeCurrent = @($TokensBeforeCurrent)

    $usedSwitchLookup = @{}
    $valueContext = $null
    $helpRequested = $false

    for ($index = 0; $index -lt $TokensBeforeCurrent.Count; $index++) {
        $token = [string]$TokensBeforeCurrent[$index]
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        $lookup = $token.ToLowerInvariant()
        if ($lookup -in @('-?', '/?')) {
            $helpRequested = $true
            $usedSwitchLookup[$lookup] = $true
            continue
        }

        if ($lookup -in @('-a', '-c', '-d', '-e', '-g', '-l', '-m', '-r', '-s', '-v')) {
            $usedSwitchLookup[$lookup] = $true
            if ($index -eq ($TokensBeforeCurrent.Count - 1)) {
                $valueContext = $lookup
                break
            }

            $nextToken = [string]$TokensBeforeCurrent[$index + 1]
            if (-not [string]::IsNullOrWhiteSpace($nextToken) -and -not $nextToken.StartsWith('-')) {
                $index++
            }

            continue
        }

        if ($lookup -eq '-n') {
            $usedSwitchLookup[$lookup] = $true
            if ($usedSwitchLookup.ContainsKey('-t')) {
                if ($index -eq ($TokensBeforeCurrent.Count - 1)) {
                    $valueContext = '-n'
                    break
                }

                $nextToken = [string]$TokensBeforeCurrent[$index + 1]
                if (-not [string]::IsNullOrWhiteSpace($nextToken) -and -not $nextToken.StartsWith('-')) {
                    $index++
                }
            }

            continue
        }

        if ($lookup.StartsWith('-')) {
            $usedSwitchLookup[$lookup] = $true
        }
    }

    [pscustomobject]@{
        UsedSwitchLookup = $usedSwitchLookup
        ValueContext     = $valueContext
        HelpRequested    = $helpRequested
    }
}

function Get-TestlimitSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State,
        [bool]$NoArgumentsYet
    )

    $prefix = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '' } else { $CurrentWord }
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($token in $script:TestlimitCompletionCatalog.SwitchOrder) {
        if (-not [string]::IsNullOrWhiteSpace($prefix) -and
            -not $token.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ($token -in @('-?', '/?')) {
            if (-not $NoArgumentsYet) {
                continue
            }
        } elseif ($State.UsedSwitchLookup.ContainsKey($token)) {
            continue
        }

        if ($token -eq '-n' -and -not ($State.UsedSwitchLookup.ContainsKey('-p') -or $State.UsedSwitchLookup.ContainsKey('-t'))) {
            continue
        }

        if ($token -eq '-i' -and -not $State.UsedSwitchLookup.ContainsKey('-u')) {
            continue
        }

        $results.Add((New-TestlimitCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $script:TestlimitCompletionCatalog.SwitchInfo[$token]))
    }

    @($results.ToArray())
}

function Complete-Testlimit {
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
        Get-TestlimitCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
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

    $state = Get-TestlimitCommandState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.HelpRequested) {
        return @(
            New-TestlimitCompletionResult -CompletionText '-?' -ResultType 'ParameterName' -ToolTip 'Display Testlimit help.'
        )
    }

    switch ($state.ValueContext) {
        '-a' { return @(Get-TestlimitSampleValueResults -CurrentValue $currentWord -Samples @('1', '16', '64', '256') -Placeholder '<mb>' -ToolTip 'AWE memory MB.') }
        '-d' { return @(Get-TestlimitSampleValueResults -CurrentValue $currentWord -Samples @('1', '16', '64', '256') -Placeholder '<mb>' -ToolTip 'Memory MB.') }
        '-l' { return @(Get-TestlimitSampleValueResults -CurrentValue $currentWord -Samples @('1', '16', '64', '256') -Placeholder '<mb>' -ToolTip 'Large pages MB.') }
        '-m' { return @(Get-TestlimitSampleValueResults -CurrentValue $currentWord -Samples @('1', '16', '64', '256') -Placeholder '<mb>' -ToolTip 'Memory MB.') }
        '-r' { return @(Get-TestlimitSampleValueResults -CurrentValue $currentWord -Samples @('1', '16', '64', '256') -Placeholder '<mb>' -ToolTip 'Reserved memory MB.') }
        '-s' { return @(Get-TestlimitSampleValueResults -CurrentValue $currentWord -Samples @('1', '16', '64', '256') -Placeholder '<mb>' -ToolTip 'Shared memory MB.') }
        '-v' { return @(Get-TestlimitSampleValueResults -CurrentValue $currentWord -Samples @('1', '16', '64', '256') -Placeholder '<mb>' -ToolTip 'VirtualLock memory MB.') }
        '-g' { return @(Get-TestlimitSampleValueResults -CurrentValue $currentWord -Samples @('0', '1', '256', '4096') -Placeholder '<object-size-bytes>' -ToolTip 'GDI object size in bytes.') }
        '-c' { return @(Get-TestlimitSampleValueResults -CurrentValue $currentWord -Samples @('1', '10', '100', '1000') -Placeholder '<count>' -ToolTip 'Object allocation count.') }
        '-e' { return @(Get-TestlimitSampleValueResults -CurrentValue $currentWord -Samples @('0', '1', '5', '10') -Placeholder '<seconds>' -ToolTip 'Seconds between allocations.') }
        '-n' { return @(Get-TestlimitSampleValueResults -CurrentValue $currentWord -Samples @('64', '128', '256', '1024') -Placeholder '<stack-kb>' -ToolTip 'Minimum stack reserve in KB for -t.') }
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-TestlimitSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet:($tokensBeforeCurrent.Count -eq 0))
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-TestlimitSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet:($tokensBeforeCurrent.Count -eq 0))
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('testlimit', 'testlimit.exe', 'Testlimit', 'Testlimit.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Testlimit -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
