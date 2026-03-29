# listdlls.exe tab completion for PowerShell
# Static-first native completer for Sysinternals Listdlls with safe help parsing and local process hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name ListdllsCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ListdllsCompletionCatalog = @{
        Initialized             = $false
        SwitchOrder             = @('-r', '-v', '-u', '-d', '-?', '/?', '--help')
        SwitchInfo              = @{}
        ProcessEntries          = @()
        ProcessCacheUpdated     = [datetime]::MinValue
        ProcessCacheTtlSeconds  = 2
        DllPlaceholder          = '<dll-name>'
    }
}

function New-ListdllsCompletionResult {
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

function Get-ListdllsCurrentToken {
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

function Remove-ListdllsOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function Get-ListdllsStaticSwitchCatalog {
    [ordered]@{
        '-r'     = 'Flag relocated DLLs.'
        '-v'     = 'Show DLL version information.'
        '-u'     = 'Only list unsigned DLLs.'
        '-d'     = 'Show only processes that loaded the specified DLL.'
        '-?'     = 'Display listdlls help.'
        '/?'     = 'Display listdlls help.'
        '--help' = 'Display listdlls help.'
    }
}

function Get-ListdllsCommandPath {
    foreach ($candidate in @('Listdlls.exe', 'Listdlls', 'listdlls.exe', 'listdlls')) {
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

function Invoke-ListdllsHelpText {
    $commandPath = Get-ListdllsCommandPath
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

function Get-ListdllsHelpEntryMap {
    param([string[]]$Lines)

    $result = @{}
    $currentKey = $null

    foreach ($line in $Lines) {
        if ($line -match '^\s*(processname|pid|dllname|-r|-u|-v)\s{2,}(.*)$') {
            $currentKey = $matches[1].ToLowerInvariant()
            $result[$currentKey] = [System.Collections.Generic.List[string]]::new()

            if (-not [string]::IsNullOrWhiteSpace($matches[2])) {
                $result[$currentKey].Add($matches[2].Trim())
            }

            continue
        }

        if ($currentKey -and $line -match '^\s{12,}(\S.*)$') {
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

function Initialize-ListdllsCompletionCatalog {
    if ($script:ListdllsCompletionCatalog.Initialized) {
        return
    }

    $script:ListdllsCompletionCatalog.SwitchInfo = @{}
    foreach ($entry in (Get-ListdllsStaticSwitchCatalog).GetEnumerator()) {
        $script:ListdllsCompletionCatalog.SwitchInfo[$entry.Key] = $entry.Value
    }

    $helpEntryMap = Get-ListdllsHelpEntryMap -Lines (Invoke-ListdllsHelpText)
    foreach ($entry in $helpEntryMap.GetEnumerator()) {
        if ($script:ListdllsCompletionCatalog.SwitchInfo.ContainsKey($entry.Key)) {
            $script:ListdllsCompletionCatalog.SwitchInfo[$entry.Key] = $entry.Value
        }
    }

    $script:ListdllsCompletionCatalog.Initialized = $true
}

function Update-ListdllsProcessCache {
    $cacheAge = (Get-Date) - $script:ListdllsCompletionCatalog.ProcessCacheUpdated
    if ($cacheAge.TotalSeconds -lt $script:ListdllsCompletionCatalog.ProcessCacheTtlSeconds) {
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

    $script:ListdllsCompletionCatalog.ProcessEntries = @(
        $entries |
            Sort-Object -Property CompletionText
    )
    $script:ListdllsCompletionCatalog.ProcessCacheUpdated = Get-Date
}

function New-ListdllsLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-ListdllsCompletionResult -CompletionText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-ListdllsCompletionResult -CompletionText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-ListdllsProcessCompletions {
    param([string]$CurrentWord)

    Update-ListdllsProcessCache

    $typedValue = Remove-ListdllsOuterQuotes -Value $CurrentWord
    $results = $script:ListdllsCompletionCatalog.ProcessEntries |
        Where-Object {
            [string]::IsNullOrWhiteSpace($typedValue) -or $_.CompletionText.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)
        } |
        ForEach-Object {
            New-ListdllsCompletionResult -CompletionText $_.CompletionText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }

    if (@($results).Count -gt 0) {
        return @($results)
    }

    @(New-ListdllsLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<process-or-pid>' -ToolTip 'Process name or PID.')
}

function Get-ListdllsCommandState {
    param([object[]]$TokensBeforeCurrent)

    $TokensBeforeCurrent = @($TokensBeforeCurrent)

    $usedSwitchLookup = @{}
    $valueContext = $null
    $dllMode = $false
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

        if ($lookup -eq '-d') {
            $dllMode = $true
            $usedSwitchLookup[$lookup] = $true
            if ($index -eq ($TokensBeforeCurrent.Count - 1)) {
                $valueContext = '-d'
                break
            }

            $index++
            continue
        }

        if ($lookup.StartsWith('-')) {
            $usedSwitchLookup[$lookup] = $true
            continue
        }

        if (-not $processTarget) {
            $processTarget = $token
        }
    }

    [pscustomobject]@{
        UsedSwitchLookup = $usedSwitchLookup
        ValueContext     = $valueContext
        DllMode          = $dllMode
        ProcessTarget    = $processTarget
        HelpRequested    = $helpRequested
    }
}

function Get-ListdllsSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State,
        [bool]$NoArgumentsYet
    )

    $prefix = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '' } else { $CurrentWord }
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($token in $script:ListdllsCompletionCatalog.SwitchOrder) {
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

        if ($State.DllMode -and $token -eq '-u') {
            continue
        }

        if ($State.ProcessTarget -and $token -eq '-d') {
            continue
        }

        $results.Add((New-ListdllsCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $script:ListdllsCompletionCatalog.SwitchInfo[$token]))
    }

    @($results.ToArray())
}

function Complete-Listdlls {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-ListdllsCompletionCatalog

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
        Get-ListdllsCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
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

    $state = Get-ListdllsCommandState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.HelpRequested) {
        return @(
            New-ListdllsCompletionResult -CompletionText '-?' -ResultType 'ParameterName' -ToolTip 'Display listdlls help.'
        )
    }

    if ($state.ValueContext -eq '-d') {
        return @(New-ListdllsLiteralValueResults -CurrentValue $currentWord -Placeholder $script:ListdllsCompletionCatalog.DllPlaceholder -ToolTip 'DLL name to search for.')
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-ListdllsSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet:($tokensBeforeCurrent.Count -eq 0))
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @(Get-ListdllsSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet:($tokensBeforeCurrent.Count -eq 0))) {
            $results.Add($item)
        }

        if (-not $state.DllMode -and -not $state.ProcessTarget) {
            foreach ($item in @(Get-ListdllsProcessCompletions -CurrentWord '')) {
                $results.Add($item)
            }

            $results.Add((New-ListdllsCompletionResult -CompletionText $script:ListdllsCompletionCatalog.DllPlaceholder -ResultType 'ParameterValue' -ToolTip 'DLL name to search for with -d.'))
        }

        return @($results.ToArray())
    }

    if (-not $state.DllMode -and -not $state.ProcessTarget) {
        return @(Get-ListdllsProcessCompletions -CurrentWord $currentWord)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('listdlls', 'listdlls.exe', 'Listdlls', 'Listdlls.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Listdlls -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
