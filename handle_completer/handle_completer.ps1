# handle.exe tab completion for PowerShell
# Static-first native completer for Sysinternals Handle with safe help parsing and local process hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name HandleCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:HandleCompletionCatalog = @{
        Initialized             = $false
        SwitchOrder             = @('-a', '-l', '-c', '-y', '-s', '-g', '-u', '-v', '-vt', '-p', '-nobanner', '-?', '/?', '--help')
        SwitchInfo              = @{}
        SearchPlaceholder       = '<name-fragment>'
        HandleValuePlaceholder  = '<hex-handle>'
        ProcessEntries          = @()
        ProcessCacheUpdated     = [datetime]::MinValue
        ProcessCacheTtlSeconds  = 2
    }
}

function New-HandleCompletionResult {
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

function Get-HandleCurrentToken {
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

function Remove-HandleOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function Get-HandleStaticSwitchCatalog {
    [ordered]@{
        '-a'        = 'Dump all handle information.'
        '-l'        = 'Just show pagefile-backed section handles.'
        '-c'        = 'Close the specified handle. Requires -p with the owning PID.'
        '-y'        = 'Do not prompt for close handle confirmation.'
        '-s'        = 'Print counts by handle type.'
        '-g'        = 'Print granted access.'
        '-u'        = 'Show the owning user name.'
        '-v'        = 'CSV output with comma delimiter.'
        '-vt'       = 'CSV output with tab delimiter.'
        '-p'        = 'Dump handles belonging to a process (partial name accepted).'
        '-nobanner' = 'Do not display the startup banner and copyright message.'
        '-?'        = 'Display handle help.'
        '/?'        = 'Display handle help.'
        '--help'    = 'Display handle help.'
    }
}

function Get-HandleCommandPath {
    foreach ($candidate in @('handle.exe', 'handle')) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($command) {
            if ($command.Path) {
                return $command.Path
            }

            if ($command.Source) {
                return $command.Source
            }

            return $command.Name
        }
    }

    $null
}

function Invoke-HandleHelpText {
    $commandPath = Get-HandleCommandPath
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
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

function Get-HandleHelpEntryMap {
    param([string[]]$Lines)

    $result = @{}
    $currentKey = $null

    foreach ($line in $Lines) {
        if ($line -match '^\s*(-a|-l|-c|-g|-y|-s|-u|-v|-vt|-p|name|-nobanner)\s{2,}(.*)$') {
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

function Initialize-HandleCompletionCatalog {
    if ($script:HandleCompletionCatalog.Initialized) {
        return
    }

    $script:HandleCompletionCatalog.SwitchInfo = @{}
    foreach ($entry in (Get-HandleStaticSwitchCatalog).GetEnumerator()) {
        $script:HandleCompletionCatalog.SwitchInfo[$entry.Key] = $entry.Value
    }

    $helpEntryMap = Get-HandleHelpEntryMap -Lines (Invoke-HandleHelpText)
    foreach ($entry in $helpEntryMap.GetEnumerator()) {
        if ($entry.Key -eq 'name') {
            $script:HandleCompletionCatalog.SearchPlaceholder = '<name-fragment>'
            continue
        }

        if ($script:HandleCompletionCatalog.SwitchInfo.ContainsKey($entry.Key)) {
            $script:HandleCompletionCatalog.SwitchInfo[$entry.Key] = $entry.Value
        }
    }

    $script:HandleCompletionCatalog.Initialized = $true
}

function Update-HandleProcessCache {
    $cacheAge = (Get-Date) - $script:HandleCompletionCatalog.ProcessCacheUpdated
    if ($cacheAge.TotalSeconds -lt $script:HandleCompletionCatalog.ProcessCacheTtlSeconds) {
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

    $script:HandleCompletionCatalog.ProcessEntries = @(
        $entries |
            Sort-Object -Property CompletionText
    )
    $script:HandleCompletionCatalog.ProcessCacheUpdated = Get-Date
}

function New-HandleLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-HandleCompletionResult -CompletionText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-HandleCompletionResult -CompletionText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-HandleSampleValueResults {
    param(
        [string]$CurrentValue,
        [string[]]$Samples,
        [string]$Placeholder,
        [string]$ToolTip
    )

    $typedValue = Remove-HandleOuterQuotes -Value $CurrentValue
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($sample in $Samples) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $sample.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $results.Add((New-HandleCompletionResult -CompletionText $sample -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ([string]::IsNullOrWhiteSpace($typedValue) -or
        $Placeholder.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        $results.Add((New-HandleCompletionResult -CompletionText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0) {
        return @(New-HandleLiteralValueResults -CurrentValue $CurrentValue -Placeholder $Placeholder -ToolTip $ToolTip)
    }

    @($results.ToArray())
}

function Get-HandleProcessCompletions {
    param(
        [string]$CurrentWord,
        [bool]$IdsOnly = $false
    )

    Update-HandleProcessCache

    $typedValue = Remove-HandleOuterQuotes -Value $CurrentWord
    $results = $script:HandleCompletionCatalog.ProcessEntries |
        Where-Object {
            (-not $IdsOnly -or $_.CompletionText -match '^\d+$') -and
            ([string]::IsNullOrWhiteSpace($typedValue) -or $_.CompletionText.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase))
        } |
        ForEach-Object {
            New-HandleCompletionResult -CompletionText $_.CompletionText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }

    if (@($results).Count -gt 0) {
        return @($results)
    }

    if ($IdsOnly) {
        return @(New-HandleLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<pid>' -ToolTip 'Owning process ID required for -c close-handle workflow.')
    }

    @(
        New-HandleLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<process-or-pid>' -ToolTip 'Process name or PID.'
    )
}

function Get-HandleCommandState {
    param([object[]]$TokensBeforeCurrent)

    $TokensBeforeCurrent = @($TokensBeforeCurrent)

    $usedSwitchLookup = @{}
    $valueContext = $null
    $mode = 'search'
    $processTarget = $null
    $nameTarget = $null
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

        if ($lookup -eq '-a') {
            $mode = 'all'
            $usedSwitchLookup[$lookup] = $true
            continue
        }

        if ($lookup -eq '-c') {
            $mode = 'close'
            $usedSwitchLookup[$lookup] = $true
            if ($index -eq ($TokensBeforeCurrent.Count - 1)) {
                $valueContext = '-c'
                break
            }

            $index++
            continue
        }

        if ($lookup -eq '-p') {
            $usedSwitchLookup[$lookup] = $true
            if ($index -eq ($TokensBeforeCurrent.Count - 1)) {
                $valueContext = '-p'
                break
            }

            $processTarget = [string]$TokensBeforeCurrent[$index + 1]
            $index++
            continue
        }

        if ($lookup -eq '-s') {
            $mode = 'summary'
            $usedSwitchLookup[$lookup] = $true
            continue
        }

        if ($lookup.StartsWith('-')) {
            $usedSwitchLookup[$lookup] = $true
            continue
        }

        if (-not $nameTarget) {
            $nameTarget = $token
        }
    }

    [pscustomobject]@{
        UsedSwitchLookup = $usedSwitchLookup
        ValueContext     = $valueContext
        Mode             = $mode
        ProcessTarget    = $processTarget
        NameTarget       = $nameTarget
        HelpRequested    = $helpRequested
    }
}

function Get-HandleSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State,
        [bool]$NoArgumentsYet
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $currentPrefix = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '' } else { $CurrentWord }

    foreach ($token in $script:HandleCompletionCatalog.SwitchOrder) {
        if (-not [string]::IsNullOrWhiteSpace($currentPrefix) -and
            -not $token.StartsWith($currentPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ($token -in @('-?', '/?', '--help')) {
            if (-not $NoArgumentsYet) {
                continue
            }
        } elseif ($State.UsedSwitchLookup.ContainsKey($token)) {
            continue
        }

        if ($token -eq '-l' -and $State.Mode -ne 'all') {
            continue
        }

        if ($token -eq '-y' -and $State.Mode -ne 'close') {
            continue
        }

        if ($token -eq '-c' -and $State.Mode -eq 'all') {
            continue
        }

        if ($token -eq '-s' -and $State.Mode -eq 'all') {
            continue
        }

        if ($token -eq '-vt' -and $State.UsedSwitchLookup.ContainsKey('-v')) {
            continue
        }

        if ($token -eq '-v' -and $State.UsedSwitchLookup.ContainsKey('-vt')) {
            continue
        }

        $toolTip = $script:HandleCompletionCatalog.SwitchInfo[$token]
        $results.Add((New-HandleCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $toolTip))
    }

    @($results.ToArray())
}

function Complete-Handle {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-HandleCompletionCatalog

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
        Get-HandleCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
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

    $state = Get-HandleCommandState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.HelpRequested) {
        return @(
            New-HandleCompletionResult -CompletionText '-?' -ResultType 'ParameterName' -ToolTip 'Display handle help.'
        )
    }

    switch ($state.ValueContext) {
        '-c' {
            return @(Get-HandleSampleValueResults -CurrentValue $currentWord -Samples @('0000007c', '00000120', '000004b0') -Placeholder $script:HandleCompletionCatalog.HandleValuePlaceholder -ToolTip 'Handle value interpreted as hexadecimal.')
        }
        '-p' {
            $idsOnly = ($state.Mode -eq 'close')
            return @(Get-HandleProcessCompletions -CurrentWord $currentWord -IdsOnly:$idsOnly)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-HandleSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet:($tokensBeforeCurrent.Count -eq 0))
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @(Get-HandleSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet:($tokensBeforeCurrent.Count -eq 0))) {
            $results.Add($item)
        }

        if ($state.Mode -ne 'close' -and -not $state.NameTarget) {
            $results.Add((New-HandleCompletionResult -CompletionText $script:HandleCompletionCatalog.SearchPlaceholder -ResultType 'ParameterValue' -ToolTip 'Object name fragment to search for.'))
        }

        return @($results.ToArray())
    }

    if (-not $state.NameTarget -and $state.Mode -ne 'close') {
        return @(New-HandleLiteralValueResults -CurrentValue $currentWord -Placeholder $script:HandleCompletionCatalog.SearchPlaceholder -ToolTip 'Object name fragment to search for.')
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('handle', 'handle.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Handle -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
