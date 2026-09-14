# listdlls.exe tab completion for PowerShell
# Static-first native completer for Sysinternals Listdlls with safe help parsing and local process hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name ListdllsCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:ListdllsCompletionCatalog = @{
        Initialized             = $false
        SwitchOrder             = @('-r', '-v', '-u', '-d', '-accepteula', '-nobanner', '-?', '/?', '--help')
        SwitchInfo              = @{}
        ProcessEntries          = @()
        ProcessCacheUpdated     = $null
        ProcessCacheTtlSeconds  = 15
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
        '-accepteula' = 'Accept the Sysinternals EULA (suppresses the first-run dialog).'
        '-nobanner'   = 'Do not display the startup banner and copyright message.'
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
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $commandPath
        foreach ($argument in @('-accepteula', '-nobanner', '/?')) {
            $startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $process.StandardInput.Close()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) {
                $process.Kill()
                return @()
            }

            $text = $outputTask.Result + $errorTask.Result
            return @($text -split '\r?\n')
        } finally {
            $process.Dispose()
        }
    } catch {
        Write-Debug "listdlls help unavailable: $($_.Exception.Message)"
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
    $lastUpdated = $script:ListdllsCompletionCatalog.ProcessCacheUpdated
    if ($null -ne $lastUpdated) {
        $cacheAge = (Get-Date) - $lastUpdated
        if ($cacheAge.TotalSeconds -lt $script:ListdllsCompletionCatalog.ProcessCacheTtlSeconds) {
            return
        }
    }

    $nameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $nameEntries = [System.Collections.Generic.List[object]]::new()
    $idEntries = [System.Collections.Generic.List[object]]::new()

    foreach ($process in @(Get-Process -ErrorAction Ignore)) {
        if ($process.ProcessName -and $nameSet.Add($process.ProcessName)) {
            $nameEntries.Add([pscustomobject]@{
                    CompletionText = $process.ProcessName
                    Kind           = 'Name'
                    ToolTip        = "Process name $($process.ProcessName)"
                })
        }

        # PIDs 0 (Idle) and 4 (System) cannot be opened by listdlls.
        if ($process.Id -gt 4) {
            $idEntries.Add([pscustomobject]@{
                    CompletionText = [string]$process.Id
                    Kind           = 'Pid'
                    SortKey        = [int]$process.Id
                    ToolTip        = "Process ID $($process.Id) ($($process.ProcessName))"
                })
        }
    }

    $script:ListdllsCompletionCatalog.ProcessEntries = @(
        @($nameEntries | Sort-Object -Property CompletionText) +
        @($idEntries | Sort-Object -Property SortKey)
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
    # PIDs are only useful once the user starts typing digits; otherwise they bury the process names.
    $wantsPids = $typedValue -match '^\d+$'
    $results = $script:ListdllsCompletionCatalog.ProcessEntries |
        Where-Object {
            ($_.Kind -eq 'Name' -or $wantsPids) -and
            ([string]::IsNullOrWhiteSpace($typedValue) -or $_.CompletionText.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase))
        } |
        ForEach-Object {
            New-ListdllsCompletionResult -CompletionText $_.CompletionText -ResultType 'ParameterValue' -ToolTip $_.ToolTip
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
    $verboseUsed = $false
    $unsignedUsed = $false
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
            if ($lookup -eq '-v') { $verboseUsed = $true }
            if ($lookup -eq '-u') { $unsignedUsed = $true }
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
        VerboseUsed      = $verboseUsed
        UnsignedUsed     = $unsignedUsed
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

        # usage: listdlls [-r] [-v | -u] [processname|pid]
        # usage: listdlls [-r] [-v] [-d dllname]
        if ($token -eq '-u' -and ($State.DllMode -or $State.VerboseUsed)) {
            continue
        }

        if ($token -eq '-v' -and $State.UnsignedUsed) {
            continue
        }

        if ($token -eq '-d' -and ($State.ProcessTarget -or $State.UnsignedUsed)) {
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
    $safeCursor = [Math]::Min([Math]::Max($cursorPosition - $commandAst.Extent.StartOffset, 0), $line.Length)
    $linePrefix = $line.Substring(0, $safeCursor)
    $commandTokens = @([regex]::Matches($linePrefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    # Assign only in the non-empty branches: an empty @() flowing through an if-expression
    # collapses to $null, and @($null) is a one-element array.
    $argumentTokens = [object[]]@()
    if ($commandTokens.Count -gt 1) {
        $argumentTokens = [object[]]@($commandTokens | Select-Object -Skip 1)
    }

    $currentWord = if ([string]::IsNullOrEmpty($wordToComplete)) {
        Get-ListdllsCurrentToken -Line $line -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    } else {
        $wordToComplete
    }

    $hasTrailingSpace = [string]::IsNullOrEmpty($currentWord) -and (($linePrefix -match '\s$') -or (($cursorPosition - $commandAst.Extent.StartOffset) -gt $line.Length))
    $tokensBeforeCurrent = [object[]]@()
    if ($hasTrailingSpace) {
        $tokensBeforeCurrent = [object[]]@($argumentTokens)
    } elseif ($argumentTokens.Count -gt 1) {
        $tokensBeforeCurrent = [object[]]@($argumentTokens | Select-Object -First ($argumentTokens.Count - 1))
    }

    $state = Get-ListdllsCommandState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.HelpRequested) {
        return @(
            New-ListdllsCompletionResult -CompletionText '-?' -ResultType 'ParameterName' -ToolTip 'Display listdlls help.'
        )
    }

    if ($state.ValueContext -eq '-d') {
        return @(New-ListdllsLiteralValueResults -CurrentValue $currentWord -Placeholder $script:ListdllsCompletionCatalog.DllPlaceholder -ToolTip 'DLL name to search for.')
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and ($currentWord.StartsWith('-') -or $currentWord.StartsWith('/'))) {
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
