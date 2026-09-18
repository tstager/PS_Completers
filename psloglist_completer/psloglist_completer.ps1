# psloglist tab completion for PowerShell
# Static syntax completer with cached local-only event log and provider hints when not targeting a remote system.

Set-StrictMode -Version 2.0

function Initialize-PsLogListCompletionCatalog {
    if (-not (Get-Variable -Name PsLogListCompletionCatalog -Scope Script -ErrorAction Ignore)) {
        $script:PsLogListCompletionCatalog = @{
            Switches = @(
                [pscustomobject]@{ Token = '-u'; Description = 'Optional user name for remote login.'; TakesValue = $true; ValueKind = 'User' }
                [pscustomobject]@{ Token = '-p'; Description = 'Optional password for remote login.'; TakesValue = $true; ValueKind = 'Password' }
                [pscustomobject]@{ Token = '-a'; Description = 'Dump records timestamped after the specified date.'; TakesValue = $true; ValueKind = 'Date' }
                [pscustomobject]@{ Token = '-b'; Description = 'Dump records timestamped before the specified date.'; TakesValue = $true; ValueKind = 'Date' }
                [pscustomobject]@{ Token = '-c'; Description = 'Clear event log after displaying it.'; TakesValue = $false }
                [pscustomobject]@{ Token = '-d'; Description = 'Display only records from the previous n days.'; TakesValue = $true; ValueKind = 'Number' }
                [pscustomobject]@{ Token = '-e'; Description = 'Exclude the specified event IDs (up to 10; not combinable with -i).'; TakesValue = $true; ValueKind = 'Ids' }
                [pscustomobject]@{ Token = '-f'; Description = 'Filter event types by starting letter.'; TakesValue = $true; ValueKind = 'Filter' }
                [pscustomobject]@{ Token = '-g'; Description = 'Export an event log as an evt file.'; TakesValue = $true; ValueKind = 'ExportPath' }
                [pscustomobject]@{ Token = '-h'; Description = 'Display only records from the previous n hours.'; TakesValue = $true; ValueKind = 'Number' }
                [pscustomobject]@{ Token = '-i'; Description = 'Show only the specified event IDs (up to 10; not combinable with -e).'; TakesValue = $true; ValueKind = 'Ids' }
                [pscustomobject]@{ Token = '-l'; Description = 'Dump the contents of the specified saved event log file.'; TakesValue = $true; ValueKind = 'SavedLogPath' }
                [pscustomobject]@{ Token = '-m'; Description = 'Display only records from the previous n minutes.'; TakesValue = $true; ValueKind = 'Number' }
                [pscustomobject]@{ Token = '-n'; Description = 'Display only the n most recent records.'; TakesValue = $true; ValueKind = 'Number' }
                [pscustomobject]@{ Token = '-o'; Description = 'Show only records from the specified event sources. Append * for a substring match.'; TakesValue = $true; ValueKind = 'Sources' }
                [pscustomobject]@{ Token = '-q'; Description = 'Omit records from the specified event sources. Append * for a substring match.'; TakesValue = $true; ValueKind = 'Sources' }
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
            StaticSourceHints = @('Service Control Manager', 'Application Error')
            DynamicCache   = @{
                TtlSeconds      = 120
                LogNames        = @()
                LogNamesUpdated = [datetime]::MinValue
                SourcesByLog    = @{}
            }
        }
    }
}

function New-PsLogListCompletionResult {
    param([string]$CompletionText, [string]$ResultType, [string]$ToolTip, [string]$ListItemText)
    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }
    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
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
    # Tokens that end before the cursor are "before"; the element under the cursor is the current word, truncated at
    # the cursor; anything to the right of the cursor is ignored.
    $tokensBeforeCurrent = New-Object System.Collections.Generic.List[string]
    $currentWord = ''
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.EndOffset -lt $CursorPosition) {
            [void]$tokensBeforeCurrent.Add($extent.Text)
            continue
        }
        if ($extent.StartOffset -le $CursorPosition) {
            $currentWord = $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
        break
    }
    if ([string]::IsNullOrEmpty($currentWord) -and -not [string]::IsNullOrEmpty($WordToComplete)) { $currentWord = $WordToComplete }
    [pscustomobject]@{
        CurrentWord         = $currentWord
        TokensBeforeCurrent = @($tokensBeforeCurrent.ToArray())
    }
}

function Invoke-PsLogListCapture {
    param([string[]]$Arguments, [int]$TimeoutMilliseconds = 1500)
    # Only run the tool when its EULA has already been accepted, so completion can never pop the licence dialog.
    $eula = Get-ItemProperty -Path 'HKCU:\Software\Sysinternals\PsLoglist' -Name 'EulaAccepted' -ErrorAction Ignore
    if (-not $eula -or [int]$eula.EulaAccepted -ne 1) { return @() }
    $command = Get-Command -Name 'psloglist.exe', 'psloglist' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if (-not $command) { return @() }
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $command.Source
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        foreach ($argument in @($Arguments)) { [void]$startInfo.ArgumentList.Add($argument) }
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $process.StandardInput.Close()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            try { $process.Kill($true) } catch { Write-Debug -Message $_.Exception.Message }
            return @()
        }
        [void]$errorTask.Result
        @(($outputTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', '') -split '\r?\n')
    } catch {
        @()
    }
}

function Get-PsLogListLogNameList {
    # Local log names from the tool's own -z listing (about 40 ms, no elevation needed), cached behind a TTL that is
    # armed on every path so a failed harvest is not retried per keystroke.
    Initialize-PsLogListCompletionCatalog
    $cache = $script:PsLogListCompletionCatalog.DynamicCache
    $age = (Get-Date) - $cache.LogNamesUpdated
    if ($age.TotalSeconds -lt $cache.TtlSeconds) { return @($cache.LogNames) }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($line in @(Invoke-PsLogListCapture -Arguments @('-nobanner', '-z'))) {
        if ($line -match '^\s+(\S.*?)\s*$') { [void]$names.Add($matches[1]) }
    }
    if ($names.Count -eq 0) {
        foreach ($log in @(Get-WinEvent -ListLog * -ErrorAction Ignore)) {
            if (-not [string]::IsNullOrWhiteSpace($log.LogName)) { [void]$names.Add($log.LogName) }
        }
    }
    $cache.LogNames = @($names | Sort-Object -Unique)
    $cache.LogNamesUpdated = Get-Date
    @($cache.LogNames)
}

function Get-PsLogListSourceNameList {
    param([string]$LogName)
    # Provider names of the one log named on the line (default System) instead of a whole-machine sweep.
    Initialize-PsLogListCompletionCatalog
    $log = if ([string]::IsNullOrWhiteSpace($LogName)) { 'System' } else { $LogName }
    $key = $log.ToLowerInvariant()
    $cache = $script:PsLogListCompletionCatalog.DynamicCache
    if ($cache.SourcesByLog.ContainsKey($key)) { return @($cache.SourcesByLog[$key]) }

    $providers = @()
    try {
        $info = Get-WinEvent -ListLog $log -ErrorAction Ignore
        if ($info) {
            $providers = @($info.ProviderNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        }
    } catch {
        $providers = @()
    }
    $cache.SourcesByLog[$key] = $providers
    @($providers)
}

function Select-PsLogListPrefixMatch {
    param([string[]]$Values, [string]$CurrentWord)
    $typed = Remove-PsLogListOuterQuotes -Value $CurrentWord
    if ([string]::IsNullOrEmpty($typed)) { return @($Values) }
    @($Values | Where-Object { $_.StartsWith($typed, [System.StringComparison]::OrdinalIgnoreCase) })
}

function Get-PsLogListPathCompletions {
    param([string]$CurrentWord, [string[]]$Extensions, [string]$ToolTip, [string]$Prefix = '', [string]$Placeholder = '<path>')
    $trimmed = Remove-PsLogListOuterQuotes -Value $CurrentWord
    if ($Prefix -and $trimmed.StartsWith($Prefix)) { $trimmed = $trimmed.Substring($Prefix.Length) }

    # Split on the last separator instead of Split-Path: '' and '.\' must list the current directory, not throw or
    # resolve to the directory's own name.
    $separatorIndex = $trimmed.LastIndexOfAny([char[]]@('\', '/'))
    if ($separatorIndex -ge 0) {
        $parentText = $trimmed.Substring(0, $separatorIndex + 1)
        $leaf = $trimmed.Substring($separatorIndex + 1)
    } else {
        $parentText = ''
        $leaf = $trimmed
    }
    $parent = if ([string]::IsNullOrEmpty($parentText)) { '.' } else { $parentText }
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($leaf) + '*'
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('"')
    $allowedExtensions = @($Extensions | ForEach-Object { $_.ToLowerInvariant() })

    $results = foreach ($item in @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern } | Sort-Object -Property Name)) {
        if (-not $item.PSIsContainer -and $allowedExtensions.Count -gt 0 -and ($item.Extension.ToLowerInvariant() -notin $allowedExtensions)) { continue }
        $completionPath = $parentText + $item.Name
        if ($item.PSIsContainer) { $completionPath += [System.IO.Path]::DirectorySeparatorChar }
        New-PsLogListCompletionResult -CompletionText (ConvertTo-PsLogListQuotedValue -Value ($Prefix + $completionPath) -AlwaysQuote:$alwaysQuote) -ListItemText ($Prefix + $item.Name) -ResultType $(if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }) -ToolTip $(if ($ToolTip) { $ToolTip } else { $item.FullName })
    }

    if (@($results).Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            return @(New-PsLogListCompletionResult -CompletionText ($Prefix + $Placeholder) -ResultType 'ParameterValue' -ToolTip $ToolTip)
        }
        return @()
    }

    @($results)
}

function Get-PsLogListAtFileCompletions {
    param([string]$CurrentWord)
    $trimmed = Remove-PsLogListOuterQuotes -Value $CurrentWord
    if (-not $trimmed.StartsWith('@')) { return @() }
    Get-PsLogListPathCompletions -CurrentWord $CurrentWord -Extensions @() -ToolTip 'File containing remote computer names for @file syntax.' -Prefix '@' -Placeholder 'file'
}

function Get-PsLogListCsvValueCompletions {
    param([string]$CurrentWord, [string[]]$Values, [string]$ToolTip)
    $typed = Remove-PsLogListOuterQuotes -Value $CurrentWord
    $commaIndex = $typed.LastIndexOf(',')
    $prefix = if ($commaIndex -ge 0) { $typed.Substring(0, $commaIndex + 1) } else { '' }
    $currentSegment = if ($commaIndex -ge 0) { $typed.Substring($commaIndex + 1) } else { $typed }
    $results = foreach ($value in @($Values)) {
        if (-not [string]::IsNullOrWhiteSpace($currentSegment) -and -not $value.StartsWith($currentSegment, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        New-PsLogListCompletionResult -CompletionText ($prefix + $value) -ListItemText $value -ResultType 'ParameterValue' -ToolTip $ToolTip
    }
    @($results)
}

function Complete-PsLogList {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    Initialize-PsLogListCompletionCatalog

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

        if (-not $eventLog) { $eventLog = Remove-PsLogListOuterQuotes -Value $token }
    }

    $remoteMode = [bool]$remoteTarget

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
            return @(Select-PsLogListPrefixMatch -Values $script:PsLogListCompletionCatalog.DateHints -CurrentWord $currentWord | ForEach-Object { New-PsLogListCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Date in mm/dd/yy form.' })
        }
        'Number' {
            return @(Select-PsLogListPrefixMatch -Values $script:PsLogListCompletionCatalog.NumberHints -CurrentWord $currentWord | ForEach-Object { New-PsLogListCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Numeric PsLogList value.' })
        }
        'Ids' {
            return Get-PsLogListCsvValueCompletions -CurrentWord $currentWord -Values $script:PsLogListCompletionCatalog.EventIdHints -ToolTip 'Comma-separated event IDs (up to 10).'
        }
        'Filter' {
            return @(Select-PsLogListPrefixMatch -Values $script:PsLogListCompletionCatalog.FilterHints -CurrentWord $currentWord | ForEach-Object { New-PsLogListCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Event type filter letters, for example "we" for warning and error.' })
        }
        'ExportPath' {
            return Get-PsLogListPathCompletions -CurrentWord $currentWord -Extensions @('.evt', '.evtx') -ToolTip 'Path for exported event log output.'
        }
        'SavedLogPath' {
            return Get-PsLogListPathCompletions -CurrentWord $currentWord -Extensions @('.evt', '.evtx') -ToolTip 'Saved event log file path.'
        }
        'Delimiter' {
            return @(Select-PsLogListPrefixMatch -Values $script:PsLogListCompletionCatalog.DelimiterHints -CurrentWord $currentWord | ForEach-Object { New-PsLogListCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Delimiter used with -s.' })
        }
        'Sources' {
            $sourceValues = if ($remoteMode) {
                @('<event-source>') + $script:PsLogListCompletionCatalog.StaticSourceHints
            } else {
                @(@(Get-PsLogListSourceNameList -LogName $eventLog) + $script:PsLogListCompletionCatalog.StaticSourceHints | Sort-Object -Unique)
            }
            $sourceValues = @($sourceValues) + @('<source>*')
            return Get-PsLogListCsvValueCompletions -CurrentWord $currentWord -Values $sourceValues -ToolTip 'Comma-separated event source or publisher names; append * for a substring match.'
        }
    }

    if ($currentWord.StartsWith('@') -or $currentWord.StartsWith('"@')) {
        return Get-PsLogListAtFileCompletions -CurrentWord $currentWord
    }

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $remoteTarget) {
        foreach ($target in @('\\<computer>', '\\<computer>,<computer2>', '\\localhost', '\\*', '@file')) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $target.StartsWith((Remove-PsLogListOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsLogListCompletionResult -CompletionText $target -ResultType 'ParameterValue' -ToolTip 'Remote target placeholder for PsLogList (comma-separated list allowed).'))
            }
        }
    }

    foreach ($spec in $script:PsLogListCompletionCatalog.Switches) {
        $key = $spec.Token.ToLowerInvariant()
        if ($used.ContainsKey($key)) { continue }
        if (($key -in @('-u', '-p')) -and -not $remoteTarget) { continue }
        if ($key -eq '-t' -and -not $used.ContainsKey('-s')) { continue }
        if ($key -eq '-e' -and $used.ContainsKey('-i')) { continue }
        if ($key -eq '-i' -and $used.ContainsKey('-e')) { continue }
        $isTerminal = [bool]($spec.PSObject.Properties['Terminal'] -and $spec.Terminal)
        if ($isTerminal -and $tokensBeforeCurrent.Count -gt 0) { continue }
        if (-not [string]::IsNullOrWhiteSpace($currentWord) -and -not $spec.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        [void]$results.Add((New-PsLogListCompletionResult -CompletionText $spec.Token -ResultType 'ParameterName' -ToolTip $spec.Description))
    }

    if (-not $eventLog) {
        $logHints = @($script:PsLogListCompletionCatalog.StaticLogHints)
        if (-not $remoteMode) { $logHints += Get-PsLogListLogNameList }
        $logToolTip = if ($used.ContainsKey('-l')) {
            'Event log name that tells PsLogList how to interpret the saved log file.'
        } elseif ($remoteMode) {
            'Event log name hint.'
        } else {
            'Local event log name.'
        }
        $typedLog = Remove-PsLogListOuterQuotes -Value $currentWord
        foreach ($log in ($logHints | Sort-Object -Unique)) {
            if ([string]::IsNullOrWhiteSpace($typedLog) -or $log.StartsWith($typedLog, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsLogListCompletionResult -CompletionText (ConvertTo-PsLogListQuotedValue -Value $log) -ListItemText $log -ResultType 'ParameterValue' -ToolTip $logToolTip))
            }
        }
    }

    @($results.ToArray())
}


Register-ArgumentCompleter -Native -CommandName @('psloglist', 'psloglist.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsLogList -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
