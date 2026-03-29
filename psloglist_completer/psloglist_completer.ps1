# psloglist tab completion for PowerShell
# Static syntax completer with cached local-only event log and provider hints when not targeting a remote system.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name PsLogListCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PsLogListCompletionCatalog = @{
        Switches = @(
            [pscustomobject]@{ Token = '-u'; Description = 'Optional user name for remote login.'; TakesValue = $true; ValueKind = 'User' }
            [pscustomobject]@{ Token = '-p'; Description = 'Optional password for remote login.'; TakesValue = $true; ValueKind = 'Password' }
            [pscustomobject]@{ Token = '-a'; Description = 'Dump records timestamped after the specified date.'; TakesValue = $true; ValueKind = 'Date' }
            [pscustomobject]@{ Token = '-b'; Description = 'Dump records timestamped before the specified date.'; TakesValue = $true; ValueKind = 'Date' }
            [pscustomobject]@{ Token = '-c'; Description = 'Clear event log after displaying it.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-d'; Description = 'Display only records from the previous n days.'; TakesValue = $true; ValueKind = 'Number' }
            [pscustomobject]@{ Token = '-e'; Description = 'Exclude the specified event IDs.'; TakesValue = $true; ValueKind = 'Ids' }
            [pscustomobject]@{ Token = '-f'; Description = 'Filter event types by starting letter.'; TakesValue = $true; ValueKind = 'Filter' }
            [pscustomobject]@{ Token = '-g'; Description = 'Export an event log as an evt file.'; TakesValue = $true; ValueKind = 'ExportPath' }
            [pscustomobject]@{ Token = '-h'; Description = 'Display only records from the previous n hours.'; TakesValue = $true; ValueKind = 'Number' }
            [pscustomobject]@{ Token = '-i'; Description = 'Show only the specified event IDs.'; TakesValue = $true; ValueKind = 'Ids' }
            [pscustomobject]@{ Token = '-l'; Description = 'Dump the contents of the specified saved event log file.'; TakesValue = $true; ValueKind = 'SavedLogPath' }
            [pscustomobject]@{ Token = '-m'; Description = 'Display only records from the previous n minutes.'; TakesValue = $true; ValueKind = 'Number' }
            [pscustomobject]@{ Token = '-n'; Description = 'Display only the n most recent records.'; TakesValue = $true; ValueKind = 'Number' }
            [pscustomobject]@{ Token = '-o'; Description = 'Show only records from the specified event sources.'; TakesValue = $true; ValueKind = 'Sources' }
            [pscustomobject]@{ Token = '-q'; Description = 'Omit records from the specified event sources.'; TakesValue = $true; ValueKind = 'Sources' }
            [pscustomobject]@{ Token = '-r'; Description = 'Dump from least recent to most recent.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-s'; Description = 'List records on one line each with delimited fields.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-t'; Description = 'Delimiter used with -s. Use "\t" for tab.'; TakesValue = $true; ValueKind = 'Delimiter' }
            [pscustomobject]@{ Token = '-w'; Description = 'Wait for new events and dump them as they are generated (local only).'; TakesValue = $false }
            [pscustomobject]@{ Token = '-x'; Description = 'Dump extended data.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-z'; Description = 'List event logs registered on the specified system.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-?'; Description = 'Display PsLogList help.'; TakesValue = $false; Terminal = $true }
            [pscustomobject]@{ Token = '/?'; Description = 'Display PsLogList help.'; TakesValue = $false; Terminal = $true }
        )
        NumberHints    = @('1', '5', '10', '30', '60', '100')
        DateHints      = @('<mm/dd/yy>', '01/01/24', '12/31/24')
        FilterHints    = @('e', 'w', 'we', 'i', 's', 'se')
        DelimiterHints = @(',', ';', '|', ':', '\t')
        EventIdHints   = @('1000', '4624', '4625', '6005', '6006', '<event-id>')
        StaticLogHints = @('System', 'Application', 'Security')
        DynamicCache   = @{
            LastUpdated = [datetime]::MinValue
            TtlSeconds  = 120
            LogNames    = @()
            Sources     = @()
        }
    }
}

function New-PsLogListCompletionResult {
    param([string]$CompletionText, [string]$ResultType, [string]$ToolTip, [string]$ListItemText)
    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }
    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

function Get-PsLogListCurrentToken {
    param([string]$Line, [int]$CursorPosition, [string]$Fallback)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $Fallback }
    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') { return '' }
    $parts = @([regex]::Matches($prefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) { return $parts[-1] }
    $Fallback
}

function Remove-PsLogListOuterQuotes {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) { return $Value.Substring(1, $Value.Length - 2) }
    $Value.TrimStart('"')
}

function ConvertTo-PsLogListQuotedValue {
    param([string]$Value, [bool]$AlwaysQuote = $false)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + $Value.Replace('`', '``').Replace('"', '`"') + '"'
    }
    $Value
}

function Get-PsLogListArgumentState {
    param([System.Management.Automation.Language.CommandAst]$CommandAst, [string]$WordToComplete, [int]$CursorPosition)
    $currentWord = if ([string]::IsNullOrEmpty($WordToComplete)) {
        ''
    } else {
        Get-PsLogListCurrentToken -Line $CommandAst.Extent.Text -CursorPosition $CursorPosition -Fallback $WordToComplete
    }
    $tokens = @($CommandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text })
    $tokensBeforeCurrent = @($tokens)
    if (-not [string]::IsNullOrEmpty($currentWord) -and $tokensBeforeCurrent.Count -gt 0 -and $tokensBeforeCurrent[-1] -eq $currentWord) {
        if ($tokensBeforeCurrent.Count -gt 1) {
            $tokensBeforeCurrent = @($tokensBeforeCurrent[0..($tokensBeforeCurrent.Count - 2)])
        } else {
            $tokensBeforeCurrent = @()
        }
    }
    [pscustomobject]@{
        CurrentWord         = $currentWord
        TokensBeforeCurrent = $tokensBeforeCurrent
    }
}

function Update-PsLogListDynamicCache {
    $age = (Get-Date) - $script:PsLogListCompletionCatalog.DynamicCache.LastUpdated
    if ($script:PsLogListCompletionCatalog.DynamicCache.LogNames.Count -gt 0 -and $age.TotalSeconds -lt $script:PsLogListCompletionCatalog.DynamicCache.TtlSeconds) { return }

    try {
        $logs = @(Get-WinEvent -ListLog * -ErrorAction Stop)
        $script:PsLogListCompletionCatalog.DynamicCache.LogNames = @(
            $logs |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_.LogName) } |
                Select-Object -ExpandProperty LogName |
                Sort-Object -Unique
        )
        $providers = New-Object System.Collections.Generic.List[string]
        foreach ($log in $logs) {
            foreach ($provider in @($log.ProviderNames)) {
                if (-not [string]::IsNullOrWhiteSpace($provider)) { $providers.Add($provider) }
            }
        }
        $script:PsLogListCompletionCatalog.DynamicCache.Sources = @($providers | Sort-Object -Unique)
        $script:PsLogListCompletionCatalog.DynamicCache.LastUpdated = Get-Date
    } catch {
        if (-not $script:PsLogListCompletionCatalog.DynamicCache.LogNames) { $script:PsLogListCompletionCatalog.DynamicCache.LogNames = @() }
        if (-not $script:PsLogListCompletionCatalog.DynamicCache.Sources) { $script:PsLogListCompletionCatalog.DynamicCache.Sources = @() }
    }
}

function Get-PsLogListPathCompletions {
    param([string]$CurrentWord, [string[]]$Extensions, [string]$ToolTip)
    $trimmed = Remove-PsLogListOuterQuotes -Value $CurrentWord
    $parent = Split-Path -Path $trimmed -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) { $parent = '.' }
    $leaf = Split-Path -Path $trimmed -Leaf
    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('"')
    $allowedExtensions = @($Extensions | ForEach-Object { $_.ToLowerInvariant() })
    $results = foreach ($item in @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)) {
        if (-not $item.PSIsContainer -and $allowedExtensions.Count -gt 0 -and $item.Extension -and ($item.Extension.ToLowerInvariant() -notin $allowedExtensions)) { continue }
        $completionPath = if ($trimmed -and -not [System.IO.Path]::IsPathRooted($trimmed) -and $parent -ne '.') {
            Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($parent -eq '.') {
            $item.Name
        } else {
            $item.FullName
        }
        if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionPath += [System.IO.Path]::DirectorySeparatorChar
        }
        New-PsLogListCompletionResult -CompletionText (ConvertTo-PsLogListQuotedValue -Value $completionPath -AlwaysQuote:$alwaysQuote) -ResultType $(if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }) -ToolTip $item.FullName
    }

    if (@($results).Count -eq 0) {
        return @(New-PsLogListCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '<path>' } else { $CurrentWord }) -ResultType 'ParameterValue' -ToolTip $ToolTip)
    }

    @($results)
}

function Get-PsLogListAtFileCompletions {
    param([string]$CurrentWord)
    $trimmed = Remove-PsLogListOuterQuotes -Value $CurrentWord
    if (-not $trimmed.StartsWith('@')) { return @() }
    $pathPortion = $trimmed.Substring(1)
    if ([string]::IsNullOrWhiteSpace($pathPortion)) {
        $parent = '.'
        $leaf = ''
    } else {
        $parent = Split-Path -Path $pathPortion -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) { $parent = '.' }
        $leaf = Split-Path -Path $pathPortion -Leaf
    }
    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('"')
    $results = foreach ($item in @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)) {
        $completionPath = if ($pathPortion -and -not [System.IO.Path]::IsPathRooted($pathPortion) -and $parent -ne '.') {
            Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($parent -eq '.') {
            $item.Name
        } else {
            $item.FullName
        }
        if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionPath += [System.IO.Path]::DirectorySeparatorChar
        }
        New-PsLogListCompletionResult -CompletionText (ConvertTo-PsLogListQuotedValue -Value ('@' + $completionPath) -AlwaysQuote:$alwaysQuote) -ListItemText ('@' + $item.Name) -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.'
    }

    if (@($results).Count -eq 0) {
        return @(New-PsLogListCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '@file' } else { $CurrentWord }) -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.')
    }

    @($results)
}

function Get-PsLogListCsvValueCompletions {
    param([string]$CurrentWord, [string[]]$Values, [string]$ToolTip)
    $typed = Remove-PsLogListOuterQuotes -Value $CurrentWord
    $parts = if ([string]::IsNullOrWhiteSpace($typed)) { @('') } else { @($typed.Split(',')) }
    $currentSegment = $parts[-1]
    $partCount = @($parts).Count
    $prefix = if ($partCount -gt 1) { ($parts[0..($partCount - 2)] -join ',') + ',' } else { '' }
    $results = foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($currentSegment) -and -not $value.StartsWith($currentSegment, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        New-PsLogListCompletionResult -CompletionText ($prefix + $value) -ResultType 'ParameterValue' -ToolTip $ToolTip
    }
    if (@($results).Count -eq 0) {
        return @(New-PsLogListCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '<value>' } else { $CurrentWord }) -ResultType 'ParameterValue' -ToolTip $ToolTip)
    }
    @($results)
}

function Complete-PsLogList {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $state = Get-PsLogListArgumentState -CommandAst $CommandAst -WordToComplete $WordToComplete -CursorPosition $CursorPosition
    $currentWord = $state.CurrentWord
    $tokensBeforeCurrent = @($state.TokensBeforeCurrent)
    $switchLookup = @{}
    foreach ($spec in $script:PsLogListCompletionCatalog.Switches) { $switchLookup[$spec.Token.ToLowerInvariant()] = $spec }

    $used = @{}
    $valueContext = $null
    $remoteTarget = $null
    $eventLog = $null
    for ($i = 0; $i -lt $tokensBeforeCurrent.Count; $i++) {
        $token = $tokensBeforeCurrent[$i]
        $key = $token.ToLowerInvariant()
        if ($switchLookup.ContainsKey($key)) {
            $used[$key] = $true
            $spec = $switchLookup[$key]
            if ($spec.TakesValue) {
                if ($i -eq ($tokensBeforeCurrent.Count - 1)) { $valueContext = $spec.ValueKind; break }
                $i++
            }
            continue
        }

        if (-not $remoteTarget -and ((Remove-PsLogListOuterQuotes -Value $token).StartsWith('\\') -or (Remove-PsLogListOuterQuotes -Value $token).StartsWith('@'))) {
            $remoteTarget = $token
            continue
        }

        if (-not $eventLog) { $eventLog = $token }
    }

    $remoteMode = [bool]$remoteTarget
    if (-not $remoteMode) { Update-PsLogListDynamicCache }

    switch ($valueContext) {
        'User' {
            return @(
                New-PsLogListCompletionResult -CompletionText '<username>' -ResultType 'ParameterValue' -ToolTip 'Remote user name.'
                New-PsLogListCompletionResult -CompletionText '<domain\user>' -ResultType 'ParameterValue' -ToolTip 'Remote user name in Domain\User syntax.'
            )
        }
        'Password' {
            return @(New-PsLogListCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($currentWord)) { '<password>' } else { $currentWord }) -ResultType 'ParameterValue' -ToolTip 'Remote password value.')
        }
        'Date' {
            return @($script:PsLogListCompletionCatalog.DateHints | ForEach-Object { New-PsLogListCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Date in mm/dd/yy form.' })
        }
        'Number' {
            return @($script:PsLogListCompletionCatalog.NumberHints | ForEach-Object { New-PsLogListCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Numeric PsLogList value.' })
        }
        'Ids' {
            return Get-PsLogListCsvValueCompletions -CurrentWord $currentWord -Values $script:PsLogListCompletionCatalog.EventIdHints -ToolTip 'Comma-separated event IDs.'
        }
        'Filter' {
            return @($script:PsLogListCompletionCatalog.FilterHints | ForEach-Object { New-PsLogListCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Event type filter letters, for example "we" for warning and error.' })
        }
        'ExportPath' {
            return Get-PsLogListPathCompletions -CurrentWord $currentWord -Extensions @('.evt', '.evtx') -ToolTip 'Path for exported event log output.'
        }
        'SavedLogPath' {
            return Get-PsLogListPathCompletions -CurrentWord $currentWord -Extensions @('.evt', '.evtx') -ToolTip 'Saved event log file path.'
        }
        'Delimiter' {
            return @($script:PsLogListCompletionCatalog.DelimiterHints | ForEach-Object { New-PsLogListCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Delimiter used with -s.' })
        }
        'Sources' {
            $sourceValues = if ($remoteMode) {
                @('<event-source>', 'Service Control Manager', 'Application Error')
            } else {
                @($script:PsLogListCompletionCatalog.DynamicCache.Sources + @('Service Control Manager', 'Application Error')) | Sort-Object -Unique
            }
            return Get-PsLogListCsvValueCompletions -CurrentWord $currentWord -Values $sourceValues -ToolTip 'Comma-separated event source or publisher names.'
        }
    }

    if ($currentWord.StartsWith('@') -or $currentWord.StartsWith('"@')) {
        return Get-PsLogListAtFileCompletions -CurrentWord $currentWord
    }

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $remoteTarget) {
        foreach ($target in @('\\<computer>', '\\localhost', '\\*', '@file')) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $target.StartsWith((Remove-PsLogListOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsLogListCompletionResult -CompletionText $target -ResultType 'ParameterValue' -ToolTip 'Remote target placeholder for PsLogList.'))
            }
        }
    }

    foreach ($spec in $script:PsLogListCompletionCatalog.Switches) {
        $key = $spec.Token.ToLowerInvariant()
        if ($used.ContainsKey($key)) { continue }
        if (($key -in @('-u', '-p')) -and -not $remoteTarget) { continue }
        if ($key -eq '-t' -and -not $used.ContainsKey('-s')) { continue }
        $isTerminal = [bool]($spec.PSObject.Properties['Terminal'] -and $spec.Terminal)
        if ($isTerminal -and $tokensBeforeCurrent.Count -gt 0) { continue }
        if (-not [string]::IsNullOrWhiteSpace($currentWord) -and -not $spec.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        [void]$results.Add((New-PsLogListCompletionResult -CompletionText $spec.Token -ResultType 'ParameterName' -ToolTip $spec.Description))
    }

    if (-not $eventLog) {
        $logHints = @($script:PsLogListCompletionCatalog.StaticLogHints)
        if (-not $remoteMode) { $logHints += $script:PsLogListCompletionCatalog.DynamicCache.LogNames }
        foreach ($log in ($logHints | Sort-Object -Unique)) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $log.StartsWith((Remove-PsLogListOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsLogListCompletionResult -CompletionText $log -ResultType 'ParameterValue' -ToolTip $(if ($remoteMode) { 'Event log name hint.' } else { 'Local event log name hint.' })))
            }
        }
    }

    @($results.ToArray())
}

function Ensure-PsLogListCommandAlias {
    $existingAlias = Get-Alias -Name psloglist -ErrorAction SilentlyContinue
    if ($existingAlias) { return }

    $exeCommand = Get-Command -Name psloglist.exe -ErrorAction SilentlyContinue
    if (-not $exeCommand) { return }

    $bareCommand = Get-Command -Name psloglist -ErrorAction SilentlyContinue
    if ($bareCommand -and $bareCommand.CommandType -ne 'Application') { return }

    Set-Alias -Name psloglist -Value psloglist.exe -Option AllScope -Scope Global
}

Ensure-PsLogListCommandAlias

Register-ArgumentCompleter -Native -CommandName @('psloglist', 'psloglist.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsLogList -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
