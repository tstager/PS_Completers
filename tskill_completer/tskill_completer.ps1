# tskill.exe tab completion for PowerShell
# Provides lightweight native argument completion for process targets and documented switches.
# Usage: . .\tskill_completer.ps1

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name TskillCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:TskillCompletionCatalog = @{
        SwitchTokens             = @('/SERVER:', '/ID:', '/A', '/V', '/?')
        ProcessEntries           = @()
        ProcessCacheUpdated      = [datetime]::MinValue
        ProcessCacheTtlSeconds   = 2
        SessionIds               = @()
        SessionCacheUpdated      = [datetime]::MinValue
        SessionCacheTtlSeconds   = 20
    }
}

function Test-TskillCommandAvailable {
    if (Get-Command -Name tskill.exe -ErrorAction SilentlyContinue) {
        return $true
    }

    if (Get-Command -Name tskill -ErrorAction SilentlyContinue) {
        return $true
    }

    $false
}

function New-TskillCompletionResult {
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

function Get-TskillCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrEmpty($Line)) {
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

function Update-TskillProcessCache {
    $cacheAge = (Get-Date) - $script:TskillCompletionCatalog.ProcessCacheUpdated
    if ($cacheAge.TotalSeconds -lt $script:TskillCompletionCatalog.ProcessCacheTtlSeconds) {
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
                ToolTip        = "Process name $processName"
            })
    }

    foreach ($processId in @($processIds | Sort-Object)) {
        $processIdText = [string]$processId
        $entries.Add([pscustomobject]@{
                CompletionText = $processIdText
                ResultType     = 'ParameterValue'
                ToolTip        = "Process ID $processIdText"
            })
    }

    $script:TskillCompletionCatalog.ProcessEntries = @($entries)
    $script:TskillCompletionCatalog.ProcessCacheUpdated = Get-Date
}

function Update-TskillSessionIdCache {
    $cacheAge = (Get-Date) - $script:TskillCompletionCatalog.SessionCacheUpdated
    if ($cacheAge.TotalSeconds -lt $script:TskillCompletionCatalog.SessionCacheTtlSeconds) {
        return
    }

    $lines = @()
    if (Get-Command -Name qwinsta.exe -ErrorAction SilentlyContinue) {
        $lines = @(& qwinsta.exe 2>$null)
    } elseif (Get-Command -Name query.exe -ErrorAction SilentlyContinue) {
        $lines = @(& query.exe session 2>$null)
    }

    $sessionIds = foreach ($line in $lines) {
        foreach ($match in [regex]::Matches(
                $line,
                '(?<=\s)(\d+)(?=\s+(?:Active|Disc|Conn|Listen|Idle|Down|Reset|Init|Disconnected)\b)'
            )) {
            $match.Groups[1].Value
        }
    }

    $script:TskillCompletionCatalog.SessionIds = @($sessionIds | Sort-Object -Unique)
    $script:TskillCompletionCatalog.SessionCacheUpdated = Get-Date
}

function Get-TskillExpectedInlineValueOption {
    param([string]$CurrentWord)

    if ([string]::IsNullOrEmpty($CurrentWord)) {
        return $null
    }

    if ($CurrentWord.StartsWith('/ID:', [System.StringComparison]::OrdinalIgnoreCase)) {
        return '/ID:'
    }

    if ($CurrentWord.StartsWith('/SERVER:', [System.StringComparison]::OrdinalIgnoreCase)) {
        return '/SERVER:'
    }

    $null
}

function Get-TskillProcessCompletions {
    param([string]$CurrentWord)

    Update-TskillProcessCache

    $prefix = if ([string]::IsNullOrEmpty($CurrentWord)) { '' } else { $CurrentWord.Trim('"') }
    $script:TskillCompletionCatalog.ProcessEntries |
        Where-Object { $_.CompletionText -like "$prefix*" } |
        ForEach-Object {
            New-TskillCompletionResult -CompletionText $_.CompletionText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }
}

function Get-TskillSessionIdCompletions {
    param([string]$CurrentWord)

    Update-TskillSessionIdCache

    $typedValue = $CurrentWord.Substring(4)
    $script:TskillCompletionCatalog.SessionIds |
        Where-Object { $_ -like "$typedValue*" } |
        ForEach-Object {
            $completionText = "/ID:$_"
            New-TskillCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip "Session ID $_"
        }
}

function Get-TskillServerValueCompletions {
    param([string]$CurrentWord)

    $typedValue = $CurrentWord.Substring(8)
    if ([string]::IsNullOrEmpty($typedValue)) {
        return @(New-TskillCompletionResult -CompletionText '/SERVER:' -ResultType 'ParameterName' -ToolTip 'Remote server name')
    }

    @()
}

function Complete-Tskill {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if (-not (Test-TskillCommandAvailable)) {
        return @()
    }

    $line = $commandAst.ToString()
    $safeCursor = [Math]::Min([Math]::Max($cursorPosition, 0), $line.Length)
    $linePrefix = $line.Substring(0, $safeCursor)
    $commandTokens = @([regex]::Matches($linePrefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    [object[]]$argumentTokens = if ($commandTokens.Count -gt 1) {
        @($commandTokens | Select-Object -Skip 1)
    } else {
        @()
    }

    $currentWord = if ([string]::IsNullOrEmpty($wordToComplete)) {
        Get-TskillCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
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

    $expectedInlineValueOption = Get-TskillExpectedInlineValueOption -CurrentWord $currentWord
    switch ($expectedInlineValueOption) {
        '/ID:' {
            return @(Get-TskillSessionIdCompletions -CurrentWord $currentWord)
        }
        '/SERVER:' {
            return @(Get-TskillServerValueCompletions -CurrentWord $currentWord)
        }
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('/')) {
        return @(
            $script:TskillCompletionCatalog.SwitchTokens |
                Where-Object { $_ -like "$currentWord*" } |
                ForEach-Object {
                    New-TskillCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
                }
        )
    }

    $hasCompletedPositional = $false
    foreach ($token in $tokensBeforeCurrent) {
        if (-not [string]::IsNullOrWhiteSpace($token) -and -not $token.StartsWith('/')) {
            $hasCompletedPositional = $true
            break
        }
    }

    if (-not $hasCompletedPositional) {
        return @(Get-TskillProcessCompletions -CurrentWord $currentWord)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('tskill', 'tskill.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Tskill -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
