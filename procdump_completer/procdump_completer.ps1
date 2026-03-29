# procdump.exe tab completion for PowerShell
# Static-first native completer for ProcDump with context-sensitive placeholders and safe local process hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name ProcDumpCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ProcDumpCompletionCatalog = @{
        SwitchOrder            = @(
            '-mm', '-ma', '-mac', '-mt', '-mp', '-mc', '-md', '-mk',
            '-n', '-s', '-c', '-cl', '-u', '-cp', '-m', '-ml', '-p', '-pl',
            '-h', '-e', '-g', '-b', '-ld', '-ud', '-ct', '-et', '-l',
            '-t', '-f', '-fx', '-dc', '-o', '-r', '-a', '-at', '-wer', '-64',
            '-w', '-x', '-i', '-k', '-cancel', '-accepteula', '-?', '/?'
        )
        SwitchInfo             = @{
            '-mm'        = 'Write a Mini dump file.'
            '-ma'        = 'Write a Full dump file.'
            '-mac'       = 'Write a Full dump file with memory compression.'
            '-mt'        = 'Write a Triage dump file.'
            '-mp'        = 'Write a MiniPlus dump file.'
            '-mc'        = 'Write a Custom dump using a MINIDUMP_TYPE mask.'
            '-md'        = 'Write a Callback dump using the specified callback DLL.'
            '-mk'        = 'Also write a Kernel dump.'
            '-n'         = 'Number of dumps to write before exiting.'
            '-s'         = 'Consecutive seconds before dump is written.'
            '-c'         = 'CPU threshold above which to create a dump.'
            '-cl'        = 'CPU threshold below which to create a dump.'
            '-u'         = 'Treat CPU usage relative to a single core, or uninstall in AeDebug mode when used alone.'
            '-cp'        = 'Number of compression workers to use.'
            '-m'         = 'Memory commit threshold in MB.'
            '-ml'        = 'Trigger when memory commit drops below the specified MB value.'
            '-p'         = 'Trigger when a performance counter meets or exceeds the threshold.'
            '-pl'        = 'Trigger when a performance counter falls below the threshold.'
            '-h'         = 'Write a dump if the process has a hung window.'
            '-e'         = 'Write a dump when the process encounters an exception.'
            '-g'         = 'Run as a native debugger in a managed process.'
            '-b'         = 'Treat debug breakpoints as exceptions.'
            '-ld'        = 'Trigger on module load. Valid with -e.'
            '-ud'        = 'Trigger on module unload. Valid with -e.'
            '-ct'        = 'Trigger on thread creation. Valid with -e.'
            '-et'        = 'Trigger on thread exit. Valid with -e.'
            '-l'         = 'Display the debug logging of the process.'
            '-t'         = 'Write a dump when the process terminates.'
            '-f'         = 'Include filter for exception, debug log, or DLL event text.'
            '-fx'        = 'Exclude filter for exception, debug log, or DLL event text.'
            '-dc'        = 'Add the specified string to the generated dump comment.'
            '-o'         = 'Overwrite an existing dump file.'
            '-r'         = 'Dump using a clone. Optional concurrent clone limit 1..5.'
            '-a'         = 'Avoid outage. Requires -r.'
            '-at'        = 'Avoid outage timeout in seconds.'
            '-wer'       = 'Queue the largest dump to Windows Error Reporting.'
            '-64'        = 'Capture a 64-bit dump for a WOW64 process.'
            '-w'         = 'Wait for the specified process to launch if it is not running.'
            '-x'         = 'Launch the specified image with optional arguments.'
            '-i'         = 'Install ProcDump as the AeDebug postmortem debugger.'
            '-k'         = 'Kill the process after cloning or after dump collection.'
            '-cancel'    = 'Gracefully terminate ProcDump monitoring for the target process PID.'
            '-accepteula' = 'Automatically accept the Sysinternals license agreement.'
            '-?'         = 'Display ProcDump help.'
            '/?'         = 'Display ProcDump help.'
        }
        ProcessEntries         = @()
        ProcessCacheUpdated    = [datetime]::MinValue
        ProcessCacheTtlSeconds = 2
    }
}

function New-ProcDumpCompletionResult {
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

function Get-ProcDumpCurrentToken {
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

function Remove-ProcDumpOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function Update-ProcDumpProcessCache {
    $cacheAge = (Get-Date) - $script:ProcDumpCompletionCatalog.ProcessCacheUpdated
    if ($cacheAge.TotalSeconds -lt $script:ProcDumpCompletionCatalog.ProcessCacheTtlSeconds) {
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

    $script:ProcDumpCompletionCatalog.ProcessEntries = @(
        $entries |
            Sort-Object -Property CompletionText
    )
    $script:ProcDumpCompletionCatalog.ProcessCacheUpdated = Get-Date
}

function New-ProcDumpLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-ProcDumpCompletionResult -CompletionText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-ProcDumpCompletionResult -CompletionText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-ProcDumpSampleValueResults {
    param(
        [string]$CurrentValue,
        [string[]]$Samples,
        [string]$Placeholder,
        [string]$ToolTip
    )

    $typedValue = Remove-ProcDumpOuterQuotes -Value $CurrentValue
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($sample in $Samples) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $sample.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $results.Add((New-ProcDumpCompletionResult -CompletionText $sample -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ([string]::IsNullOrWhiteSpace($typedValue) -or
        $Placeholder.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        $results.Add((New-ProcDumpCompletionResult -CompletionText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0) {
        return @(New-ProcDumpLiteralValueResults -CurrentValue $CurrentValue -Placeholder $Placeholder -ToolTip $ToolTip)
    }

    @($results.ToArray())
}

function Get-ProcDumpProcessCompletions {
    param(
        [string]$CurrentWord,
        [bool]$IdsOnly = $false
    )

    Update-ProcDumpProcessCache

    $typedValue = Remove-ProcDumpOuterQuotes -Value $CurrentWord
    $results = $script:ProcDumpCompletionCatalog.ProcessEntries |
        Where-Object {
            (-not $IdsOnly -or $_.CompletionText -match '^\d+$') -and
            ([string]::IsNullOrWhiteSpace($typedValue) -or $_.CompletionText.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase))
        } |
        ForEach-Object {
            New-ProcDumpCompletionResult -CompletionText $_.CompletionText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }

    if (@($results).Count -gt 0) {
        return @($results)
    }

    if ($IdsOnly) {
        return @(New-ProcDumpLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<pid>' -ToolTip 'Process ID.')
    }

    @(New-ProcDumpLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<process-name-or-pid>' -ToolTip 'Process name or PID.')
}

function Get-ProcDumpCommandState {
    param([object[]]$TokensBeforeCurrent)

    $TokensBeforeCurrent = @($TokensBeforeCurrent)

    $usedSwitchLookup = @{}
    $valueContext = $null
    $positionals = [System.Collections.Generic.List[string]]::new()
    $helpRequested = $false
    $mode = 'capture'

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

        if ($lookup -eq '-u' -and $TokensBeforeCurrent.Count -eq 1) {
            $usedSwitchLookup[$lookup] = $true
            $mode = 'uninstall'
            continue
        }

        if ($lookup -eq '-x') {
            $usedSwitchLookup[$lookup] = $true
            $mode = 'launch'
            $remaining = ($TokensBeforeCurrent.Count - 1) - $index
            if ($remaining -eq 0) {
                $valueContext = [pscustomobject]@{ Switch = '-x'; Position = 1 }
                break
            }

            $positionals.Add([string]$TokensBeforeCurrent[$index + 1])
            if ($remaining -eq 1) {
                $valueContext = [pscustomobject]@{ Switch = '-x'; Position = 2 }
                break
            }

            $positionals.Add([string]$TokensBeforeCurrent[$index + 2])
            for ($extra = $index + 3; $extra -lt $TokensBeforeCurrent.Count; $extra++) {
                $positionals.Add([string]$TokensBeforeCurrent[$extra])
            }
            break
        }

        if ($lookup -eq '-i') {
            $usedSwitchLookup[$lookup] = $true
            $mode = 'install'
            if ($index -eq ($TokensBeforeCurrent.Count - 1)) {
                $valueContext = [pscustomobject]@{ Switch = '-i'; Position = 1 }
                break
            }

            $nextToken = [string]$TokensBeforeCurrent[$index + 1]
            if (-not [string]::IsNullOrWhiteSpace($nextToken) -and -not $nextToken.StartsWith('-')) {
                $positionals.Add($nextToken)
                $index++
            }
            continue
        }

        if ($lookup -eq '-cancel') {
            $usedSwitchLookup[$lookup] = $true
            if ($index -eq ($TokensBeforeCurrent.Count - 1)) {
                $valueContext = [pscustomobject]@{ Switch = '-cancel'; Position = 1 }
                break
            }

            $index++
            continue
        }

        if ($lookup -in @('-mc', '-md', '-n', '-s', '-c', '-cl', '-cp', '-m', '-ml', '-f', '-fx', '-dc', '-at')) {
            $usedSwitchLookup[$lookup] = $true
            if ($index -eq ($TokensBeforeCurrent.Count - 1)) {
                $valueContext = [pscustomobject]@{ Switch = $lookup; Position = 1 }
                break
            }

            $index++
            continue
        }

        if ($lookup -in @('-p', '-pl')) {
            $usedSwitchLookup[$lookup] = $true
            $remaining = ($TokensBeforeCurrent.Count - 1) - $index
            if ($remaining -eq 0) {
                $valueContext = [pscustomobject]@{ Switch = $lookup; Position = 1 }
                break
            }

            if ($remaining -eq 1) {
                $valueContext = [pscustomobject]@{ Switch = $lookup; Position = 2 }
                break
            }

            $index += 2
            continue
        }

        if ($lookup -eq '-r') {
            $usedSwitchLookup[$lookup] = $true
            if ($index -eq ($TokensBeforeCurrent.Count - 1)) {
                $valueContext = [pscustomobject]@{ Switch = '-r'; Position = 1 }
                break
            }

            $nextToken = [string]$TokensBeforeCurrent[$index + 1]
            if (-not [string]::IsNullOrWhiteSpace($nextToken) -and -not $nextToken.StartsWith('-')) {
                $index++
            }

            continue
        }

        if ($lookup -eq '-e') {
            $usedSwitchLookup[$lookup] = $true
            if ($index -eq ($TokensBeforeCurrent.Count - 1)) {
                $valueContext = [pscustomobject]@{ Switch = '-e'; Position = 1 }
                break
            }

            $nextToken = [string]$TokensBeforeCurrent[$index + 1]
            if ($nextToken -eq '1') {
                $index++
            }

            continue
        }

        if ($lookup.StartsWith('-')) {
            $usedSwitchLookup[$lookup] = $true
            continue
        }

        $positionals.Add($token)
    }

    [pscustomobject]@{
        UsedSwitchLookup = $usedSwitchLookup
        ValueContext     = $valueContext
        Positionals      = @($positionals)
        HelpRequested    = $helpRequested
        Mode             = $mode
    }
}

function Get-ProcDumpSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State,
        [bool]$NoArgumentsYet
    )

    $prefix = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '' } else { $CurrentWord }
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($token in $script:ProcDumpCompletionCatalog.SwitchOrder) {
        if (-not [string]::IsNullOrWhiteSpace($prefix) -and
            -not $token.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ($token -in @('-?', '/?')) {
            if (-not $NoArgumentsYet) {
                continue
            }
        } elseif ($State.UsedSwitchLookup.ContainsKey($token) -and $token -notin @('-f', '-fx', '-dc')) {
            continue
        }

        if ($token -eq '-a' -and -not $State.UsedSwitchLookup.ContainsKey('-r')) {
            continue
        }

        if ($token -in @('-ld', '-ud', '-ct', '-et', '-b', '-g') -and -not $State.UsedSwitchLookup.ContainsKey('-e')) {
            if ($token -ne '-g') {
                continue
            }
        }

        $results.Add((New-ProcDumpCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $script:ProcDumpCompletionCatalog.SwitchInfo[$token]))
    }

    @($results.ToArray())
}

function Complete-ProcDump {
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
        Get-ProcDumpCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
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

    $state = Get-ProcDumpCommandState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.HelpRequested) {
        return @(
            New-ProcDumpCompletionResult -CompletionText '-?' -ResultType 'ParameterName' -ToolTip 'Display ProcDump help.'
        )
    }

    if ($state.ValueContext) {
        $switchName = [string]$state.ValueContext.Switch
        $position = [int]$state.ValueContext.Position

        switch ($switchName) {
            '-mc' { return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('0x00061907', '0x00000002') -Placeholder '<hex-mask>' -ToolTip 'MINIDUMP_TYPE mask in hexadecimal.') }
            '-md' { return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '"C:\path\MiniDumpCallback.dll"' -ToolTip 'Callback DLL path.') }
            '-n' { return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('1', '3', '5') -Placeholder '<count>' -ToolTip 'Number of dumps to write.') }
            '-s' { return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('5', '10', '30') -Placeholder '<seconds>' -ToolTip 'Consecutive seconds before dump is written.') }
            '-c' { return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('20', '50', '80') -Placeholder '<cpu-percent>' -ToolTip 'CPU threshold percent.') }
            '-cl' { return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('5', '10', '20') -Placeholder '<cpu-percent>' -ToolTip 'CPU threshold percent.') }
            '-cp' { return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('1', '2', '4') -Placeholder '<workers>' -ToolTip 'Compression worker count.') }
            '-m' { return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('512', '1024', '2048') -Placeholder '<commit-mb>' -ToolTip 'Commit threshold in MB.') }
            '-ml' { return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('256', '512', '1024') -Placeholder '<commit-mb>' -ToolTip 'Commit threshold in MB.') }
            '-p' {
                if ($position -eq 1) {
                    return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('\Processor(_Total)\% Processor Time', '\Process(*)\Handle Count') -Placeholder '<counter>' -ToolTip 'Performance counter path.')
                }

                return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('10', '50', '100') -Placeholder '<threshold>' -ToolTip 'Counter threshold.')
            }
            '-pl' {
                if ($position -eq 1) {
                    return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('\Processor(_Total)\% Processor Time', '\Process(*)\Handle Count') -Placeholder '<counter>' -ToolTip 'Performance counter path.')
                }

                return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('10', '50', '100') -Placeholder '<threshold>' -ToolTip 'Counter threshold.')
            }
            '-f' { return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '<include-filter>' -ToolTip 'Include filter text; wildcards are supported.') }
            '-fx' { return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '<exclude-filter>' -ToolTip 'Exclude filter text; wildcards are supported.') }
            '-dc' { return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '"<comment>"' -ToolTip 'Dump comment string.') }
            '-r' { return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('1', '2', '3', '5') -Placeholder '<concurrency>' -ToolTip 'Optional clone concurrency limit.') }
            '-at' { return @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('10', '30', '60') -Placeholder '<timeout-seconds>' -ToolTip 'Timeout for avoid-outage collection.') }
            '-cancel' { return @(Get-ProcDumpProcessCompletions -CurrentWord $currentWord -IdsOnly:$true) }
            '-i' { return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '"C:\Dumps"' -ToolTip 'Optional AeDebug dump folder.') }
            '-e' {
                $results = [System.Collections.Generic.List[object]]::new()
                foreach ($item in @(Get-ProcDumpSampleValueResults -CurrentValue $currentWord -Samples @('1') -Placeholder '1' -ToolTip 'Optional first-chance exception value.')) {
                    $results.Add($item)
                }
                foreach ($item in @(Get-ProcDumpSwitchCompletions -CurrentWord '-' -State $state -NoArgumentsYet:$false | Where-Object { $_.CompletionText -in @('-g', '-b', '-ld', '-ud', '-ct', '-et') })) {
                    $results.Add($item)
                }
                return @($results.ToArray())
            }
            '-x' {
                if ($position -eq 1) {
                    return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '"C:\Dumps"' -ToolTip 'Dump folder for -x launch mode.')
                }

                return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '"C:\path\image.exe"' -ToolTip 'Image path for -x launch mode.')
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-ProcDumpSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet:($tokensBeforeCurrent.Count -eq 0))
    }

    if ($state.Mode -eq 'launch') {
        if ($state.Positionals.Count -lt 2) {
            if ($state.Positionals.Count -eq 0) {
                return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '"C:\Dumps"' -ToolTip 'Dump folder for -x launch mode.')
            }

            return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '"C:\path\image.exe"' -ToolTip 'Image path for -x launch mode.')
        }

        return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '<argument>' -ToolTip 'Argument passed to the launched image.')
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @(Get-ProcDumpSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet:($tokensBeforeCurrent.Count -eq 0))) {
            $results.Add($item)
        }

        switch ($state.Mode) {
            'install' {
                if ($state.Positionals.Count -eq 0) {
                    $results.Add((New-ProcDumpCompletionResult -CompletionText '"C:\Dumps"' -ResultType 'ParameterValue' -ToolTip 'Optional AeDebug dump folder.'))
                }
            }
            'capture' {
                if ($state.Positionals.Count -eq 0) {
                    foreach ($item in @(Get-ProcDumpProcessCompletions -CurrentWord '')) {
                        $results.Add($item)
                    }
                    $results.Add((New-ProcDumpCompletionResult -CompletionText '<service-name>' -ResultType 'ParameterValue' -ToolTip 'Service name target.'))
                } elseif ($state.Positionals.Count -eq 1) {
                    $results.Add((New-ProcDumpCompletionResult -CompletionText '<dump-file-or-folder>' -ResultType 'ParameterValue' -ToolTip 'Dump file or dump folder path.'))
                }
            }
        }

        return @($results.ToArray())
    }

    switch ($state.Mode) {
        'install' {
            if ($state.Positionals.Count -eq 0) {
                return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '"C:\Dumps"' -ToolTip 'Optional AeDebug dump folder.')
            }
        }
        'capture' {
            if ($state.Positionals.Count -eq 0) {
                return @(Get-ProcDumpProcessCompletions -CurrentWord $currentWord)
            }

            if ($state.Positionals.Count -eq 1) {
                return @(New-ProcDumpLiteralValueResults -CurrentValue $currentWord -Placeholder '<dump-file-or-folder>' -ToolTip 'Dump file or dump folder path.')
            }
        }
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('procdump', 'procdump.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-ProcDump -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
