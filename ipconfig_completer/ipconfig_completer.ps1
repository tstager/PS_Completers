# ipconfig tab completion for PowerShell
# Builds a help-driven switch catalog and adapter-name cache for ipconfig.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name IpconfigCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:IpconfigCompletionCatalog = @{
        Initialized           = $false
        Switches              = @()
        SwitchInfo            = @{}
        AdapterValueOptions   = @('/renew', '/release', '/renew6', '/release6', '/showclassid', '/setclassid', '/showclassid6', '/setclassid6')
        FreeFormClassIdOptions = @('/setclassid', '/setclassid6')
        AdapterCache          = @()
        AdapterCacheUpdated   = $null
        AdapterCacheTtlSeconds = 30
    }
}

function New-IpconfigCompletionResult {
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

function ConvertTo-IpconfigQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        $escaped = $Value.Replace('`', '``').Replace('"', '`"')
        return '"' + $escaped + '"'
    }

    $Value
}

function Remove-IpconfigOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function Test-IpconfigCommandAvailable {
    [bool](Get-Command -Name ipconfig.exe -ErrorAction SilentlyContinue)
}

function Invoke-IpconfigHelpText {
    if (-not (Test-IpconfigCommandAvailable)) {
        return @()
    }

    try {
        @(& ipconfig.exe '/?' 2>$null)
    } catch {
        @()
    }
}

function Get-IpconfigCurrentToken {
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
    if (([regex]::Matches($prefix, '"').Count % 2) -eq 1) {
        # Inside an unterminated quote: the token runs from that quote to the cursor.
        return $prefix.Substring($prefix.LastIndexOf('"'))
    }

    if ($prefix -match '\s$') {
        return ''
    }

    $parts = @([regex]::Matches($prefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-IpconfigFallbackSwitchInfo {
    @{
        '/?'               = 'Display this help message.'
        '/allcompartments' = 'Display configuration information for all network compartments.'
        '/all'             = 'Display full configuration information.'
        '/renew'           = 'Renew the IPv4 address for the specified adapter.'
        '/release'         = 'Release the IPv4 address for the specified adapter.'
        '/renew6'          = 'Renew the IPv6 address for the specified adapter.'
        '/release6'        = 'Release the IPv6 address for the specified adapter.'
        '/flushdns'        = 'Purges the DNS Resolver cache.'
        '/displaydns'      = 'Display the contents of the DNS Resolver Cache.'
        '/registerdns'     = 'Refresh all DHCP leases and re-register DNS names.'
        '/showclassid'     = 'Displays all the DHCP class IDs allowed for the adapter.'
        '/setclassid'      = 'Modifies the DHCP class ID.'
        '/showclassid6'    = 'Displays all the IPv6 DHCP class IDs allowed for the adapter.'
        '/setclassid6'     = 'Modifies the IPv6 DHCP class ID.'
    }
}

function Initialize-IpconfigCompletionCatalog {
    if ($script:IpconfigCompletionCatalog.Initialized) {
        return
    }

    $switchInfo = [ordered]@{}
    $helpLines = Invoke-IpconfigHelpText

    if ($helpLines -and $helpLines.Count -gt 0) {
        $inOptions = $false

        foreach ($line in $helpLines) {
            if ($line -match '^\s*Options:\s*$') {
                $inOptions = $true
                continue
            }

            if (-not $inOptions) {
                continue
            }

            if ($line -match '^\s*Examples:\s*$') {
                break
            }

            if ($line -match '^\s*(/[A-Za-z0-9?]+)\s{2,}(.+?)\s*$') {
                $switchInfo[$matches[1].ToLowerInvariant()] = $matches[2].Trim()
            }
        }

        $helpText = $helpLines -join [Environment]::NewLine
        foreach ($match in [regex]::Matches($helpText, '(?<!\w)/(?:\?|[A-Za-z][A-Za-z0-9]*)')) {
            $token = $match.Value.ToLowerInvariant()
            if (-not $switchInfo.Contains($token)) {
                $switchInfo[$token] = $match.Value
            }
        }
    }

    foreach ($entry in (Get-IpconfigFallbackSwitchInfo).GetEnumerator()) {
        $key = $entry.Key.ToLowerInvariant()
        if (-not $switchInfo.Contains($key) -or
            [string]::IsNullOrWhiteSpace($switchInfo[$key]) -or
            $switchInfo[$key].Equals($key, [System.StringComparison]::OrdinalIgnoreCase)) {
            $switchInfo[$key] = $entry.Value
        }
    }

    $script:IpconfigCompletionCatalog.SwitchInfo = @{}
    foreach ($entry in $switchInfo.GetEnumerator()) {
        $script:IpconfigCompletionCatalog.SwitchInfo[$entry.Key] = $entry.Value
    }

    $script:IpconfigCompletionCatalog.Switches = @(
        $script:IpconfigCompletionCatalog.SwitchInfo.Keys |
            Sort-Object
    )
    $script:IpconfigCompletionCatalog.Initialized = $true
}

function Get-IpconfigAdapterNames {
    $now = Get-Date
    if ($null -ne $script:IpconfigCompletionCatalog.AdapterCacheUpdated -and
        $now -lt $script:IpconfigCompletionCatalog.AdapterCacheUpdated.AddSeconds($script:IpconfigCompletionCatalog.AdapterCacheTtlSeconds)) {
        return @($script:IpconfigCompletionCatalog.AdapterCache)
    }

    $adapterNames = New-Object System.Collections.Generic.List[string]

    if (Get-Command -Name Get-NetAdapter -ErrorAction SilentlyContinue) {
        try {
            # ipconfig addresses adapters by connection name, and it prints and
            # accepts the hidden tunnel and pseudo-interface names too.
            foreach ($name in (Get-NetAdapter -IncludeHidden -ErrorAction Stop | Select-Object -ExpandProperty Name)) {
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $adapterNames.Add($name)
                }
            }
        } catch {
        }
    }

    if ($adapterNames.Count -eq 0 -and (Test-IpconfigCommandAvailable)) {
        try {
            $output = @(& ipconfig.exe 2>$null)
            $text = $output -join [Environment]::NewLine
            foreach ($match in [regex]::Matches($text, '(?im)^[^\r\n:]* adapter (.+?):\s*$')) {
                $name = $match.Groups[1].Value.Trim()
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $adapterNames.Add($name)
                }
            }
        } catch {
        }
    }

    $script:IpconfigCompletionCatalog.AdapterCache = @($adapterNames.ToArray() | Sort-Object -Unique)
    $script:IpconfigCompletionCatalog.AdapterCacheUpdated = $now
    @($script:IpconfigCompletionCatalog.AdapterCache)
}

function Get-IpconfigValueContext {
    param([string[]]$TokensBeforeCurrent)

    $switchIndexes = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $TokensBeforeCurrent.Count; $i++) {
        if ($TokensBeforeCurrent[$i].StartsWith('/')) {
            $switchIndexes.Add($i)
        }
    }

    if ($switchIndexes.Count -eq 0) {
        return $null
    }

    $lastSwitchIndex = $switchIndexes[$switchIndexes.Count - 1]
    $switchToken = $TokensBeforeCurrent[$lastSwitchIndex].ToLowerInvariant()
    $values = @()
    if ($lastSwitchIndex -lt ($TokensBeforeCurrent.Count - 1)) {
        $values = @($TokensBeforeCurrent[($lastSwitchIndex + 1)..($TokensBeforeCurrent.Count - 1)])
    }

    switch ($switchToken) {
        '/renew' { if ($values.Count -eq 0) { return 'adapter' } }
        '/release' { if ($values.Count -eq 0) { return 'adapter' } }
        '/renew6' { if ($values.Count -eq 0) { return 'adapter' } }
        '/release6' { if ($values.Count -eq 0) { return 'adapter' } }
        '/showclassid' { if ($values.Count -eq 0) { return 'adapter' } }
        '/showclassid6' { if ($values.Count -eq 0) { return 'adapter' } }
        '/setclassid' {
            if ($values.Count -eq 0) {
                return 'adapter'
            }

            if ($values.Count -eq 1) {
                return 'classid'
            }
        }
        '/setclassid6' {
            if ($values.Count -eq 0) {
                return 'adapter'
            }

            if ($values.Count -eq 1) {
                return 'classid'
            }
        }
    }

    $null
}

function Get-IpconfigAdapterCompletions {
    param([string]$CurrentWord)

    $adapterNames = Get-IpconfigAdapterNames
    $typedValue = Remove-IpconfigOuterQuotes -Value $CurrentWord
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('"')
    $suggestions = New-Object System.Collections.Generic.List[object]

    # ipconfig accepts * and ? in the adapter operand ('/renew EL*'), so a typed
    # wildcard matches adapter names as a pattern and is itself a valid value.
    $hasWildcard = $typedValue.IndexOfAny([char[]]@('*', '?')) -ge 0
    if ($hasWildcard) {
        $matched = New-Object System.Collections.Generic.List[string]
        foreach ($name in $adapterNames) {
            if ($name -like $typedValue) {
                $matched.Add($name)
            }
        }

        $suggestions.Add((New-IpconfigCompletionResult `
                -CompletionText (ConvertTo-IpconfigQuotedValue -Value $typedValue -AlwaysQuote:$alwaysQuote) `
                -ResultType 'ParameterValue' `
                -ToolTip ('Wildcard adapter selector matching ' + $matched.Count + ' adapter(s).')))
        foreach ($name in $matched) {
            $suggestions.Add((New-IpconfigCompletionResult `
                    -CompletionText (ConvertTo-IpconfigQuotedValue -Value $name -AlwaysQuote:$alwaysQuote) `
                    -ResultType 'ParameterValue' `
                    -ToolTip 'Adapter name.'))
        }

        return @($suggestions.ToArray())
    }

    $candidates = @('*') + $adapterNames
    foreach ($candidate in ($candidates | Sort-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $candidate.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $toolTip = if ($candidate -eq '*') {
            'Wildcard adapter selector.'
        } else {
            'Adapter name.'
        }

        $suggestions.Add((New-IpconfigCompletionResult `
                -CompletionText (ConvertTo-IpconfigQuotedValue -Value $candidate -AlwaysQuote:$alwaysQuote) `
                -ResultType 'ParameterValue' `
                -ToolTip $toolTip))
    }

    @($suggestions.ToArray())
}

function Get-IpconfigSwitchCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$UsedSwitches
    )

    $switches = @(
        $script:IpconfigCompletionCatalog.Switches |
            Where-Object { $UsedSwitches -notcontains $_ }
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $prefix = $CurrentWord.ToLowerInvariant()
        $switches = @($switches | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) })
    }

    $switches | ForEach-Object {
        $toolTip = $script:IpconfigCompletionCatalog.SwitchInfo[$_.ToLowerInvariant()]
        New-IpconfigCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $toolTip
    }
}

function Complete-Ipconfig {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-IpconfigCompletionCatalog

    # Tokens are split at the cursor rather than at the end of the line, so a
    # cursor inside an earlier token completes that token and ignores the rest.
    $line = $commandAst.ToString()
    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-IpconfigCurrentToken -Line $line -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $tokensBeforeCurrent = @(
        $commandAst.CommandElements |
            Select-Object -Skip 1 |
            Where-Object { $_.Extent.EndOffset -lt $cursorPosition } |
            ForEach-Object { $_.Extent.Text }
    )

    $valueContext = Get-IpconfigValueContext -TokensBeforeCurrent $tokensBeforeCurrent
    if ($valueContext -eq 'adapter') {
        return @(Get-IpconfigAdapterCompletions -CurrentWord $currentWord)
    }

    if ($valueContext -eq 'classid') {
        if ([string]::IsNullOrEmpty($currentWord)) {
            return @(New-IpconfigCompletionResult -CompletionText '<class-id>' -ResultType 'ParameterValue' -ToolTip 'DHCP class ID value; omit it to clear the class ID.')
        }

        return @(New-IpconfigCompletionResult -CompletionText $currentWord -ResultType 'ParameterValue' -ToolTip 'Class ID value.')
    }

    $usedSwitches = @(
        $tokensBeforeCurrent |
            Where-Object { $_.StartsWith('/') } |
            ForEach-Object { $_.ToLowerInvariant() } |
            Sort-Object -Unique
    )
    $terminalSwitches = @($usedSwitches | Where-Object { $_ -ne '/allcompartments' })
    if ($terminalSwitches.Count -gt 0) {
        return @()
    }

    if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('/')) {
        return @(Get-IpconfigSwitchCompletions -CurrentWord $currentWord -UsedSwitches $usedSwitches)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'ipconfig', 'ipconfig.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-Ipconfig -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
