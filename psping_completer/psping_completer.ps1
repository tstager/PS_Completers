# psping tab completion for PowerShell
# Hybrid completer for PsPing modes, switches, and value-aware placeholders.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name PsPingCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PsPingCompletionCatalog = @{
        Initialized       = $false
        CommandName       = $null
        RootHelpText      = $null
        RootHelpValidated = $false
        HelpModes         = @()
        HelpModeLookup    = @{}
        SwitchOrder       = @()
        SwitchInfo        = @{}
    }
}

function New-PsPingCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Remove-PsPingOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function Get-PsPingCurrentToken {
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

function Resolve-PsPingCommandName {
    if ($script:PsPingCompletionCatalog.CommandName) {
        return $script:PsPingCompletionCatalog.CommandName
    }

    foreach ($candidate in @('psping.exe', 'psping')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            continue
        }

        $resolvedName = if ($command.Path) {
            $command.Path
        } elseif ($command.Source) {
            $command.Source
        } else {
            $command.Name
        }

        if (-not [string]::IsNullOrWhiteSpace($resolvedName)) {
            $script:PsPingCompletionCatalog.CommandName = $resolvedName
            return $script:PsPingCompletionCatalog.CommandName
        }
    }

    $null
}

function Get-PsPingRootHelpText {
    if ($script:PsPingCompletionCatalog.RootHelpText) {
        return $script:PsPingCompletionCatalog.RootHelpText
    }

    $commandName = Resolve-PsPingCommandName
    if ([string]::IsNullOrWhiteSpace($commandName)) {
        return $null
    }

    try {
        $script:PsPingCompletionCatalog.RootHelpText = ((& $commandName -? 2>&1) -join [Environment]::NewLine)
    } catch {
        $script:PsPingCompletionCatalog.RootHelpText = ''
    }

    $script:PsPingCompletionCatalog.RootHelpText
}

function Initialize-PsPingCompletionCatalog {
    if ($script:PsPingCompletionCatalog.Initialized) {
        return
    }

    $script:PsPingCompletionCatalog.HelpModes = @(
        [pscustomobject]@{ Token = 'i'; Description = 'Usage for ICMP ping.' }
        [pscustomobject]@{ Token = 't'; Description = 'Usage for TCP ping.' }
        [pscustomobject]@{ Token = 'l'; Description = 'Usage for latency test.' }
        [pscustomobject]@{ Token = 'b'; Description = 'Usage for bandwidth test.' }
    )

    $script:PsPingCompletionCatalog.HelpModeLookup = @{}
    foreach ($helpMode in $script:PsPingCompletionCatalog.HelpModes) {
        $script:PsPingCompletionCatalog.HelpModeLookup[$helpMode.Token] = $helpMode
    }

    $script:PsPingCompletionCatalog.SwitchOrder = @(
        '-?',
        '-b',
        '-s',
        '-u',
        '-r',
        '-f',
        '-h',
        '-i',
        '-l',
        '-q',
        '-t',
        '-n',
        '-w',
        '-4',
        '-6',
        '-nobanner'
    )

    $script:PsPingCompletionCatalog.SwitchInfo = @{
        '-?'        = @{ Description = 'Display usage. Accepts i, t, l, or b.' }
        '-b'        = @{ Description = 'Bandwidth test mode.' }
        '-s'        = @{ Description = 'Server listening address and port.' }
        '-u'        = @{ Description = 'UDP mode. In bandwidth mode it can take an optional target MB/s value.' }
        '-r'        = @{ Description = 'Receive from the server instead of sending.' }
        '-f'        = @{ Description = 'Open the source firewall port during the run.' }
        '-h'        = @{ Description = 'Print a histogram. Accepts a bucket count or comma-separated thresholds.' }
        '-i'        = @{ Description = 'Interval seconds for ping modes, or outstanding I/Os for bandwidth mode.' }
        '-l'        = @{ Description = 'Request size. Append k for kilobytes or m for megabytes.' }
        '-q'        = @{ Description = 'Do not output during ping tests.' }
        '-t'        = @{ Description = 'Run until stopped with Ctrl+C.' }
        '-n'        = @{ Description = 'Count of pings/sends/receives, or append s for seconds.' }
        '-w'        = @{ Description = 'Warmup iteration count.' }
        '-4'        = @{ Description = 'Force using IPv4.' }
        '-6'        = @{ Description = 'Force using IPv6.' }
        '-nobanner' = @{ Description = 'Do not display the startup banner and copyright message.' }
    }

    $rootHelpText = Get-PsPingRootHelpText
    if (-not [string]::IsNullOrWhiteSpace($rootHelpText) -and
        $rootHelpText -match 'psping\s+-\?\s+\[i\|t\|l\|b\]') {
        $script:PsPingCompletionCatalog.RootHelpValidated = $true
    }

    $script:PsPingCompletionCatalog.Initialized = $true
}

function Test-PsPingEndpointToken {
    param([string]$Value)

    $trimmedValue = Remove-PsPingOuterQuotes -Value $Value
    if ([string]::IsNullOrWhiteSpace($trimmedValue)) {
        return $false
    }

    if ($trimmedValue -match '^\[[^\]]+\]:\d+$') {
        return $true
    }

    $trimmedValue -match '^[^:\s]+:\d+$'
}

function Get-PsPingResolvedMode {
    param(
        [hashtable]$UsedSwitchLookup,
        [string[]]$Positionals
    )

    if ($UsedSwitchLookup.ContainsKey('-?')) {
        return 'help'
    }

    if ($UsedSwitchLookup.ContainsKey('-s')) {
        return 'server'
    }

    if ($UsedSwitchLookup.ContainsKey('-b')) {
        return 'bandwidth-client'
    }

    if ($UsedSwitchLookup.ContainsKey('-r')) {
        return 'latency-client'
    }

    if ($UsedSwitchLookup.ContainsKey('-u')) {
        return 'latency-client'
    }

    if ($Positionals.Count -gt 0) {
        $lastPositional = $Positionals[-1]
        if (Test-PsPingEndpointToken -Value $lastPositional) {
            return 'tcp-ping'
        }

        return 'icmp-ping'
    }

    'generic'
}

function Get-PsPingCommandState {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $usedSwitchLookup = @{}
    $valuesBySwitch = @{}
    $positionals = New-Object System.Collections.Generic.List[string]
    $valueContext = $null
    $mandatoryValueSwitches = @{
        '-i' = $true
        '-l' = $true
        '-n' = $true
        '-w' = $true
        '-s' = $true
    }

    for ($i = 0; $i -lt $TokensBeforeCurrent.Count; $i++) {
        $token = $TokensBeforeCurrent[$i]
        $lookup = $token.ToLowerInvariant()
        $nextToken = if ($i + 1 -lt $TokensBeforeCurrent.Count) { $TokensBeforeCurrent[$i + 1] } else { $null }

        if (-not $script:PsPingCompletionCatalog.SwitchInfo.ContainsKey($lookup)) {
            [void]$positionals.Add($token)
            continue
        }

        $usedSwitchLookup[$lookup] = $true

        switch ($lookup) {
            '-?' {
                if ($null -eq $nextToken) {
                    $valueContext = '-?'
                    break
                }

                if (-not $nextToken.StartsWith('-')) {
                    $valuesBySwitch[$lookup] = $nextToken
                    $i++
                    continue
                }

                $valueContext = '-?'
                break
            }
            '-h' {
                if ($null -ne $nextToken -and -not $nextToken.StartsWith('-')) {
                    $valuesBySwitch[$lookup] = $nextToken
                    $i++
                }
                continue
            }
            '-u' {
                if ($usedSwitchLookup.ContainsKey('-b') -and $null -ne $nextToken -and -not $nextToken.StartsWith('-')) {
                    $valuesBySwitch[$lookup] = $nextToken
                    $i++
                }
                continue
            }
        }

        if ($mandatoryValueSwitches.ContainsKey($lookup)) {
            if ($null -eq $nextToken) {
                $valueContext = $lookup
                break
            }

            if (-not $nextToken.StartsWith('-')) {
                $valuesBySwitch[$lookup] = $nextToken
                $i++
                continue
            }

            $valueContext = $lookup
            break
        }
    }

    $mode = Get-PsPingResolvedMode -UsedSwitchLookup $usedSwitchLookup -Positionals @($positionals.ToArray())
    $currentStartsWithDash = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('-')

    if (-not $valueContext -and $TokensBeforeCurrent.Count -gt 0 -and -not $currentStartsWithDash) {
        $lastToken = $TokensBeforeCurrent[-1].ToLowerInvariant()
        switch ($lastToken) {
            '-?' {
                $valueContext = '-?'
            }
            '-h' {
                $valueContext = '-h'
            }
            '-u' {
                if ($mode -eq 'bandwidth-client') {
                    $valueContext = '-u'
                }
            }
        }
    }

    [pscustomobject]@{
        UsedSwitchLookup = $usedSwitchLookup
        ValuesBySwitch   = $valuesBySwitch
        Positionals      = @($positionals.ToArray())
        ValueContext     = $valueContext
        Mode             = $mode
    }
}

function Get-PsPingSwitchDescription {
    param(
        [string]$Token,
        [string]$Mode
    )

    switch ($Token.ToLowerInvariant()) {
        '-i' {
            if ($Mode -eq 'bandwidth-client') {
                return 'Number of outstanding I/Os (default is min of 16 and 2x CPU cores).'
            }

            return 'Interval in seconds. Specify 0 for fast ping.'
        }
        '-u' {
            if ($Mode -eq 'bandwidth-client') {
                return 'UDP (default is TCP). Optionally specify target bandwidth in MB/s.'
            }

            return 'UDP (default is TCP).'
        }
        '-w' {
            switch ($Mode) {
                'bandwidth-client' { return 'Warmup for the specified iterations (default is 2x CPU cores).' }
                'latency-client' { return 'Warmup with the specified number of iterations (default is 5).' }
                default { return 'Warmup with the specified number of iterations (default is 1).' }
            }
        }
        '-n' {
            if ($Mode -eq 'icmp-ping' -or $Mode -eq 'tcp-ping') {
                return 'Number of pings, or append s to specify seconds.'
            }

            return 'Number of sends/receives, or append s to specify seconds.'
        }
        default {
            return $script:PsPingCompletionCatalog.SwitchInfo[$Token.ToLowerInvariant()].Description
        }
    }
}

function Get-PsPingModeSwitchTokens {
    param([string]$Mode)

    switch ($Mode) {
        'server' {
            @('-?', '-s', '-f', '-4', '-6', '-nobanner')
        }
        'bandwidth-client' {
            @('-?', '-b', '-u', '-i', '-l', '-n', '-w', '-h', '-r', '-f', '-4', '-6', '-nobanner')
        }
        'latency-client' {
            @('-?', '-u', '-l', '-n', '-w', '-h', '-r', '-f', '-4', '-6', '-nobanner')
        }
        'tcp-ping' {
            @('-?', '-h', '-i', '-l', '-q', '-t', '-n', '-w', '-4', '-6', '-nobanner')
        }
        'icmp-ping' {
            @('-?', '-h', '-i', '-l', '-q', '-t', '-n', '-w', '-4', '-6', '-nobanner')
        }
        default {
            @($script:PsPingCompletionCatalog.SwitchOrder)
        }
    }
}

function Get-PsPingStaticValueResults {
    param(
        [string]$CurrentWord,
        [object[]]$Candidates,
        [string]$FallbackToolTip
    )

    $typedValue = Remove-PsPingOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($candidate in $Candidates) {
        $completionText = $candidate.CompletionText
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $completionText.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((
            New-PsPingCompletionResult `
                -CompletionText $completionText `
                -ListItemText $candidate.ListItemText `
                -ResultType 'ParameterValue' `
                -ToolTip $candidate.ToolTip
        ))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        [void]$results.Add((
            New-PsPingCompletionResult `
                -CompletionText $CurrentWord `
                -ListItemText $CurrentWord `
                -ResultType 'ParameterValue' `
                -ToolTip $FallbackToolTip
        ))
    }

    @($results.ToArray())
}

function Get-PsPingHelpModeCompletions {
    param([string]$CurrentWord)

    $typedValue = Remove-PsPingOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($helpMode in $script:PsPingCompletionCatalog.HelpModes) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $helpMode.Token.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((
            New-PsPingCompletionResult `
                -CompletionText $helpMode.Token `
                -ListItemText $helpMode.Token `
                -ResultType 'ParameterValue' `
                -ToolTip $helpMode.Description
        ))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        [void]$results.Add((
            New-PsPingCompletionResult `
                -CompletionText $CurrentWord `
                -ListItemText $CurrentWord `
                -ResultType 'ParameterValue' `
                -ToolTip 'Usage topic for PsPing help.'
        ))
    }

    @($results.ToArray())
}

function Get-PsPingValueCompletions {
    param(
        [string]$SwitchToken,
        [string]$CurrentWord,
        [string]$Mode
    )

    switch ($SwitchToken.ToLowerInvariant()) {
        '-?' {
            return @(Get-PsPingHelpModeCompletions -CurrentWord $CurrentWord)
        }
        '-h' {
            return @(Get-PsPingStaticValueResults -CurrentWord $CurrentWord -FallbackToolTip 'Histogram bucket count or comma-separated thresholds.' -Candidates @(
                    [pscustomobject]@{ CompletionText = '20'; ListItemText = '20'; ToolTip = 'Histogram with 20 buckets.' }
                    [pscustomobject]@{ CompletionText = '100'; ListItemText = '100'; ToolTip = 'Histogram with 100 buckets.' }
                    [pscustomobject]@{ CompletionText = '0.01,0.05,1,5,10'; ListItemText = '0.01,0.05,1,5,10'; ToolTip = 'Custom histogram thresholds.' }
                    [pscustomobject]@{ CompletionText = '<buckets|comma-separated thresholds>'; ListItemText = '<buckets|thresholds>'; ToolTip = 'Histogram bucket count or comma-separated thresholds.' }
                ))
        }
        '-i' {
            if ($Mode -eq 'bandwidth-client') {
                return @(Get-PsPingStaticValueResults -CurrentWord $CurrentWord -FallbackToolTip 'Outstanding I/O count.' -Candidates @(
                        [pscustomobject]@{ CompletionText = '1'; ListItemText = '1'; ToolTip = 'Single outstanding I/O.' }
                        [pscustomobject]@{ CompletionText = '4'; ListItemText = '4'; ToolTip = 'Four outstanding I/Os.' }
                        [pscustomobject]@{ CompletionText = '8'; ListItemText = '8'; ToolTip = 'Eight outstanding I/Os.' }
                        [pscustomobject]@{ CompletionText = '16'; ListItemText = '16'; ToolTip = 'Sixteen outstanding I/Os.' }
                        [pscustomobject]@{ CompletionText = '<outstanding I/Os>'; ListItemText = '<outstanding I/Os>'; ToolTip = 'Outstanding I/O count.' }
                    ))
            }

            return @(Get-PsPingStaticValueResults -CurrentWord $CurrentWord -FallbackToolTip 'Interval in seconds.' -Candidates @(
                    [pscustomobject]@{ CompletionText = '0'; ListItemText = '0'; ToolTip = 'Fast ping with no delay.' }
                    [pscustomobject]@{ CompletionText = '0.1'; ListItemText = '0.1'; ToolTip = 'Interval of one tenth of a second.' }
                    [pscustomobject]@{ CompletionText = '1'; ListItemText = '1'; ToolTip = 'Interval of one second.' }
                    [pscustomobject]@{ CompletionText = '<seconds>'; ListItemText = '<seconds>'; ToolTip = 'Interval in seconds.' }
                ))
        }
        '-l' {
            return @(Get-PsPingStaticValueResults -CurrentWord $CurrentWord -FallbackToolTip 'Request size with optional k or m suffix.' -Candidates @(
                    [pscustomobject]@{ CompletionText = '64'; ListItemText = '64'; ToolTip = '64-byte request size.' }
                    [pscustomobject]@{ CompletionText = '1k'; ListItemText = '1k'; ToolTip = '1 KB request size.' }
                    [pscustomobject]@{ CompletionText = '8k'; ListItemText = '8k'; ToolTip = '8 KB request size.' }
                    [pscustomobject]@{ CompletionText = '64k'; ListItemText = '64k'; ToolTip = '64 KB request size.' }
                    [pscustomobject]@{ CompletionText = '1m'; ListItemText = '1m'; ToolTip = '1 MB request size.' }
                    [pscustomobject]@{ CompletionText = '<requestsize[k|m]>'; ListItemText = '<requestsize[k|m]>'; ToolTip = 'Request size with optional k or m suffix.' }
                ))
        }
        '-n' {
            return @(Get-PsPingStaticValueResults -CurrentWord $CurrentWord -FallbackToolTip 'Iteration count, or append s for seconds.' -Candidates @(
                    [pscustomobject]@{ CompletionText = '10'; ListItemText = '10'; ToolTip = 'Run 10 iterations.' }
                    [pscustomobject]@{ CompletionText = '100'; ListItemText = '100'; ToolTip = 'Run 100 iterations.' }
                    [pscustomobject]@{ CompletionText = '1000'; ListItemText = '1000'; ToolTip = 'Run 1000 iterations.' }
                    [pscustomobject]@{ CompletionText = '10s'; ListItemText = '10s'; ToolTip = 'Run for 10 seconds.' }
                    [pscustomobject]@{ CompletionText = '<count[s]>'; ListItemText = '<count[s]>'; ToolTip = 'Iteration count, or append s for seconds.' }
                ))
        }
        '-w' {
            return @(Get-PsPingStaticValueResults -CurrentWord $CurrentWord -FallbackToolTip 'Warmup iteration count.' -Candidates @(
                    [pscustomobject]@{ CompletionText = '1'; ListItemText = '1'; ToolTip = 'Warm up once.' }
                    [pscustomobject]@{ CompletionText = '3'; ListItemText = '3'; ToolTip = 'Warm up three times.' }
                    [pscustomobject]@{ CompletionText = '5'; ListItemText = '5'; ToolTip = 'Warm up five times.' }
                    [pscustomobject]@{ CompletionText = '10'; ListItemText = '10'; ToolTip = 'Warm up ten times.' }
                    [pscustomobject]@{ CompletionText = '<count>'; ListItemText = '<count>'; ToolTip = 'Warmup iteration count.' }
                ))
        }
        '-s' {
            return @(Get-PsPingStaticValueResults -CurrentWord $CurrentWord -FallbackToolTip 'Server bind address and port.' -Candidates @(
                    [pscustomobject]@{ CompletionText = '<address:port>'; ListItemText = '<address:port>'; ToolTip = 'Server listening address and port.' }
                    [pscustomobject]@{ CompletionText = '0.0.0.0:5000'; ListItemText = '0.0.0.0:5000'; ToolTip = 'Listen on all IPv4 interfaces on port 5000.' }
                    [pscustomobject]@{ CompletionText = '127.0.0.1:5000'; ListItemText = '127.0.0.1:5000'; ToolTip = 'Listen on loopback port 5000.' }
                ))
        }
        '-u' {
            return @(Get-PsPingStaticValueResults -CurrentWord $CurrentWord -FallbackToolTip 'Target UDP bandwidth in MB/s.' -Candidates @(
                    [pscustomobject]@{ CompletionText = '10'; ListItemText = '10'; ToolTip = 'Target 10 MB/s UDP bandwidth.' }
                    [pscustomobject]@{ CompletionText = '100'; ListItemText = '100'; ToolTip = 'Target 100 MB/s UDP bandwidth.' }
                    [pscustomobject]@{ CompletionText = '1000'; ListItemText = '1000'; ToolTip = 'Target 1000 MB/s UDP bandwidth.' }
                    [pscustomobject]@{ CompletionText = '<target MB/s>'; ListItemText = '<target MB/s>'; ToolTip = 'Target UDP bandwidth in MB/s.' }
                ))
        }
    }

    @()
}

function Get-PsPingPositionalCompletions {
    param(
        [string]$CurrentWord,
        [string]$Mode
    )

    $candidates = switch ($Mode) {
        'server' {
            @(
                [pscustomobject]@{ CompletionText = '<address:port>'; ListItemText = '<address:port>'; ToolTip = 'Server listening address and port.' }
                [pscustomobject]@{ CompletionText = '0.0.0.0:5000'; ListItemText = '0.0.0.0:5000'; ToolTip = 'Listen on all IPv4 interfaces on port 5000.' }
                [pscustomobject]@{ CompletionText = '127.0.0.1:5000'; ListItemText = '127.0.0.1:5000'; ToolTip = 'Listen on loopback port 5000.' }
            )
        }
        'bandwidth-client' {
            @(
                [pscustomobject]@{ CompletionText = '<destination:port>'; ListItemText = '<destination:port>'; ToolTip = 'Destination endpoint for a bandwidth test.' }
                [pscustomobject]@{ CompletionText = 'localhost:80'; ListItemText = 'localhost:80'; ToolTip = 'Loopback endpoint example.' }
                [pscustomobject]@{ CompletionText = '127.0.0.1:443'; ListItemText = '127.0.0.1:443'; ToolTip = 'IPv4 loopback endpoint example.' }
            )
        }
        'latency-client' {
            @(
                [pscustomobject]@{ CompletionText = '<destination:port>'; ListItemText = '<destination:port>'; ToolTip = 'Destination endpoint for a latency test.' }
                [pscustomobject]@{ CompletionText = 'localhost:80'; ListItemText = 'localhost:80'; ToolTip = 'Loopback endpoint example.' }
                [pscustomobject]@{ CompletionText = '127.0.0.1:443'; ListItemText = '127.0.0.1:443'; ToolTip = 'IPv4 loopback endpoint example.' }
            )
        }
        'tcp-ping' {
            @(
                [pscustomobject]@{ CompletionText = '<destination:port>'; ListItemText = '<destination:port>'; ToolTip = 'Destination endpoint for TCP ping.' }
                [pscustomobject]@{ CompletionText = 'localhost:80'; ListItemText = 'localhost:80'; ToolTip = 'Loopback endpoint example.' }
                [pscustomobject]@{ CompletionText = '127.0.0.1:443'; ListItemText = '127.0.0.1:443'; ToolTip = 'IPv4 loopback endpoint example.' }
            )
        }
        'icmp-ping' {
            @(
                [pscustomobject]@{ CompletionText = '<destination>'; ListItemText = '<destination>'; ToolTip = 'Destination host name or address.' }
                [pscustomobject]@{ CompletionText = 'localhost'; ListItemText = 'localhost'; ToolTip = 'Loopback host name.' }
                [pscustomobject]@{ CompletionText = '127.0.0.1'; ListItemText = '127.0.0.1'; ToolTip = 'IPv4 loopback address.' }
                [pscustomobject]@{ CompletionText = '::1'; ListItemText = '::1'; ToolTip = 'IPv6 loopback address.' }
            )
        }
        default {
            if ((Remove-PsPingOuterQuotes -Value $CurrentWord).Contains(':')) {
                @(
                    [pscustomobject]@{ CompletionText = '<destination:port>'; ListItemText = '<destination:port>'; ToolTip = 'Destination endpoint.' }
                    [pscustomobject]@{ CompletionText = 'localhost:80'; ListItemText = 'localhost:80'; ToolTip = 'Loopback endpoint example.' }
                    [pscustomobject]@{ CompletionText = '127.0.0.1:443'; ListItemText = '127.0.0.1:443'; ToolTip = 'IPv4 loopback endpoint example.' }
                )
            } else {
                @(
                    [pscustomobject]@{ CompletionText = '<destination>'; ListItemText = '<destination>'; ToolTip = 'Destination host name or address.' }
                    [pscustomobject]@{ CompletionText = 'localhost'; ListItemText = 'localhost'; ToolTip = 'Loopback host name.' }
                    [pscustomobject]@{ CompletionText = '127.0.0.1'; ListItemText = '127.0.0.1'; ToolTip = 'IPv4 loopback address.' }
                    [pscustomobject]@{ CompletionText = '::1'; ListItemText = '::1'; ToolTip = 'IPv6 loopback address.' }
                    [pscustomobject]@{ CompletionText = '<destination:port>'; ListItemText = '<destination:port>'; ToolTip = 'Destination endpoint for TCP, latency, or bandwidth tests.' }
                    [pscustomobject]@{ CompletionText = 'localhost:80'; ListItemText = 'localhost:80'; ToolTip = 'Loopback endpoint example.' }
                    [pscustomobject]@{ CompletionText = '127.0.0.1:443'; ListItemText = '127.0.0.1:443'; ToolTip = 'IPv4 loopback endpoint example.' }
                )
            }
        }
    }

    @(Get-PsPingStaticValueResults -CurrentWord $CurrentWord -Candidates $candidates -FallbackToolTip 'Destination or endpoint value.')
}

function Get-PsPingSwitchCompletions {
    param(
        [string]$CurrentWord,
        [string]$Mode,
        [hashtable]$UsedSwitchLookup
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($switchToken in (Get-PsPingModeSwitchTokens -Mode $Mode)) {
        $lookup = $switchToken.ToLowerInvariant()

        if ($UsedSwitchLookup.ContainsKey($lookup)) {
            continue
        }

        if (($lookup -eq '-t' -and $UsedSwitchLookup.ContainsKey('-n')) -or
            ($lookup -eq '-n' -and $UsedSwitchLookup.ContainsKey('-t')) -or
            ($lookup -eq '-4' -and $UsedSwitchLookup.ContainsKey('-6')) -or
            ($lookup -eq '-6' -and $UsedSwitchLookup.ContainsKey('-4'))) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            -not $switchToken.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((
            New-PsPingCompletionResult `
                -CompletionText $switchToken `
                -ListItemText $switchToken `
                -ResultType 'ParameterName' `
                -ToolTip (Get-PsPingSwitchDescription -Token $switchToken -Mode $Mode)
        ))
    }

    @($results.ToArray())
}

function Complete-PsPing {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-PsPingCompletionCatalog

    $line = $commandAst.Extent.Text
    $currentWord = if ($null -ne $wordToComplete) {
        $wordToComplete
    } else {
        Get-PsPingCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback ''
    }

    $commandTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokensBeforeCurrent = @(
        if ($commandTokens.Count -gt 0) {
            $commandTokens | Select-Object -Skip 1
        } else {
            @()
        }
    )

    if (-not [string]::IsNullOrEmpty($currentWord) -and $tokensBeforeCurrent.Count -gt 0) {
        $lastToken = $tokensBeforeCurrent[-1]
        if ($lastToken.Equals($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($tokensBeforeCurrent.Count -eq 1) {
                $tokensBeforeCurrent = @()
            } else {
                $tokensBeforeCurrent = $tokensBeforeCurrent[0..($tokensBeforeCurrent.Count - 2)]
            }
        }
    }

    $state = Get-PsPingCommandState -TokensBeforeCurrent $tokensBeforeCurrent -CurrentWord $currentWord
    $results = New-Object System.Collections.Generic.List[object]
    $seenCompletions = @{}

    if ($state.ValueContext) {
        foreach ($result in (Get-PsPingValueCompletions -SwitchToken $state.ValueContext -CurrentWord $currentWord -Mode $state.Mode)) {
            if (-not $seenCompletions.ContainsKey($result.CompletionText)) {
                $seenCompletions[$result.CompletionText] = $true
                [void]$results.Add($result)
            }
        }

        return @($results.ToArray())
    }

    if ($state.UsedSwitchLookup.ContainsKey('-?')) {
        foreach ($result in (Get-PsPingHelpModeCompletions -CurrentWord $currentWord)) {
            if (-not $seenCompletions.ContainsKey($result.CompletionText)) {
                $seenCompletions[$result.CompletionText] = $true
                [void]$results.Add($result)
            }
        }

        return @($results.ToArray())
    }

    if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('-')) {
        foreach ($result in (Get-PsPingSwitchCompletions -CurrentWord $currentWord -Mode $state.Mode -UsedSwitchLookup $state.UsedSwitchLookup)) {
            if (-not $seenCompletions.ContainsKey($result.CompletionText)) {
                $seenCompletions[$result.CompletionText] = $true
                [void]$results.Add($result)
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($currentWord) -or -not $currentWord.StartsWith('-')) {
        foreach ($result in (Get-PsPingPositionalCompletions -CurrentWord $currentWord -Mode $state.Mode)) {
            if (-not $seenCompletions.ContainsKey($result.CompletionText)) {
                $seenCompletions[$result.CompletionText] = $true
                [void]$results.Add($result)
            }
        }
    }

    @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName 'psping', 'psping.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsPing -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
