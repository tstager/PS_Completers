# accesschk tab completion for PowerShell
# Native completer for AccessChk with safe mode-aware values and local hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name AccessChkCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:AccessChkCompletionCatalog = @{
        Switches            = @(
            [pscustomobject]@{ Token = '-a'; Description = 'Treat the name as a Windows account right.' }
            [pscustomobject]@{ Token = '-c'; Description = 'Treat the name as a Windows service.' }
            [pscustomobject]@{ Token = '-d'; Description = 'Only process directories or top-level keys.' }
            [pscustomobject]@{ Token = '-e'; Description = 'Only show explicitly set integrity levels.' }
            [pscustomobject]@{ Token = '-f'; Description = 'After -p, show full token details; otherwise filter by comma-separated accounts.' }
            [pscustomobject]@{ Token = '-h'; Description = 'Treat the name as a file or printer share.' }
            [pscustomobject]@{ Token = '-i'; Description = 'Ignore inherited ACE-only objects when showing full descriptors.' }
            [pscustomobject]@{ Token = '-k'; Description = 'Treat the name as a registry key.' }
            [pscustomobject]@{ Token = '-l'; Description = 'Show the full security descriptor.' }
            [pscustomobject]@{ Token = '-L'; Description = 'Show the full security descriptor in SDDL format.' }
            [pscustomobject]@{ Token = '-m'; Description = 'Treat the name as an event log.' }
            [pscustomobject]@{ Token = '-n'; Description = 'Show only objects that have no access.' }
            [pscustomobject]@{ Token = '-o'; Description = 'Treat the name as an Object Manager namespace object.' }
            [pscustomobject]@{ Token = '-p'; Description = 'Treat the name as a process name or PID.' }
            [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner.' }
            [pscustomobject]@{ Token = '-r'; Description = 'Show only objects that have read access.' }
            [pscustomobject]@{ Token = '-s'; Description = 'Recurse.' }
            [pscustomobject]@{ Token = '-t'; Description = 'After -o, filter by object type; after -p, show threads.' }
            [pscustomobject]@{ Token = '-u'; Description = 'Suppress errors.' }
            [pscustomobject]@{ Token = '-v'; Description = 'Verbose output.' }
            [pscustomobject]@{ Token = '-w'; Description = 'Show only objects that have write access.' }
            [pscustomobject]@{ Token = '-?'; Description = 'Show AccessChk help.' }
            [pscustomobject]@{ Token = '/?'; Description = 'Show AccessChk help.' }
        )
        ModeTokens          = @('-a', '-c', '-h', '-k', '-m', '-o', '-p')
        ProcessCache        = @()
        ProcessCacheUpdated = [datetime]::MinValue
        ProcessCacheTtl     = 5
        ServiceCache        = @()
        ServiceCacheUpdated = [datetime]::MinValue
        ServiceCacheTtl     = 30
        RegistryRoots       = @(
            [pscustomobject]@{ Token = 'HKLM\'; ProviderPath = 'Registry::HKEY_LOCAL_MACHINE'; Description = 'HKEY_LOCAL_MACHINE' }
            [pscustomobject]@{ Token = 'HKCU\'; ProviderPath = 'Registry::HKEY_CURRENT_USER'; Description = 'HKEY_CURRENT_USER' }
            [pscustomobject]@{ Token = 'HKCR\'; ProviderPath = 'Registry::HKEY_CLASSES_ROOT'; Description = 'HKEY_CLASSES_ROOT' }
            [pscustomobject]@{ Token = 'HKU\'; ProviderPath = 'Registry::HKEY_USERS'; Description = 'HKEY_USERS' }
            [pscustomobject]@{ Token = 'HKCC\'; ProviderPath = 'Registry::HKEY_CURRENT_CONFIG'; Description = 'HKEY_CURRENT_CONFIG' }
        )
        EventLogNames       = @('Application', 'System', 'Security', 'Setup', 'ForwardedEvents', '*')
        ShareNames          = @('*', 'ADMIN$', 'C$', 'IPC$', '<share>')
        AccountRights       = @('*', 'SeBackupPrivilege', 'SeDebugPrivilege', 'SeServiceLogonRight', 'SeShutdownPrivilege', '<account-right>')
        ObjectTypes         = @('Section', 'Directory', 'Event', 'File', 'Key', 'Mutant', 'Semaphore', 'SymbolicLink', 'Type', 'WindowStation')
        ObjectRoots         = @('\', '\BaseNamedObjects', '\KnownDlls', '\RPC Control', '\Sessions\', '<object-path>')
        AccountSamples      = @('Everyone', 'Users', 'Administrators', 'SYSTEM', '<username>')
    }
}

function New-AccessChkCompletionResult {
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

function Remove-AccessChkOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function ConvertTo-AccessChkQuotedValue {
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

function Get-AccessChkTokenState {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    if ($null -eq $Line) {
        $Line = ''
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    $tokens = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    $quoteChar = [char]0

    foreach ($character in $prefix.ToCharArray()) {
        if (($character -eq [char]34) -or ($character -eq [char]39)) {
            if ($quoteChar -eq [char]0) {
                $quoteChar = $character
            } elseif ($quoteChar -eq $character) {
                $quoteChar = [char]0
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and $quoteChar -eq [char]0) {
            if ($builder.Length -gt 0) {
                $tokens.Add($builder.ToString())
                [void]$builder.Clear()
            }

            continue
        }

        [void]$builder.Append($character)
    }

    $hasTrailingSpace = $prefix -match '\s$'
    if ($builder.Length -gt 0) {
        $tokens.Add($builder.ToString())
    }

    if ($hasTrailingSpace) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens)
            CurrentToken        = ''
        }
    }

    if ($tokens.Count -gt 0) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
            CurrentToken        = $tokens[$tokens.Count - 1]
        }
    }

    [pscustomobject]@{
        TokensBeforeCurrent = @()
        CurrentToken        = ''
    }
}

function Get-AccessChkArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    if (-not $TokenState) {
        return [pscustomobject]@{
            ArgumentsBeforeCurrent = @()
            CurrentArgument        = ''
        }
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = @($TokenState.TokensBeforeCurrent | Select-Object -Skip 1)
        CurrentArgument        = $TokenState.CurrentToken
    }
}

function Get-AccessChkUniqueCompletions {
    param([object[]]$Results)

    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[object]

    foreach ($result in $Results) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.ContainsKey($result.CompletionText)) {
            continue
        }

        $seen[$result.CompletionText] = $true
        [void]$unique.Add($result)
    }

    @($unique.ToArray())
}

function Get-AccessChkStaticValueResults {
    param(
        [string]$CurrentValue,
        [string[]]$Values,
        [string]$ToolTip
    )

    $typedValue = Remove-AccessChkOuterQuotes -Value $CurrentValue
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $value.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-AccessChkCompletionResult -CompletionText $value -ListItemText $value -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        [void]$results.Add((New-AccessChkCompletionResult -CompletionText $CurrentValue -ListItemText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    @($results.ToArray())
}

function Get-AccessChkPathCompletions {
    param(
        [string]$CurrentWord,
        [string]$ToolTip,
        [string]$Placeholder = '<path>'
    )

    $typedValue = Remove-AccessChkOuterQuotes -Value $CurrentWord
    $alwaysQuote = $CurrentWord.StartsWith('"')
    $results = New-Object System.Collections.Generic.List[object]

    $parentPath = '.'
    $leaf = ''
    if (-not [string]::IsNullOrWhiteSpace($typedValue)) {
        if ($typedValue.EndsWith('\') -or $typedValue.EndsWith('/')) {
            $parentPath = $typedValue
        } else {
            $candidateParent = Split-Path -Path $typedValue -Parent
            if ([string]::IsNullOrWhiteSpace($candidateParent)) {
                $parentPath = '.'
                $leaf = $typedValue
            } else {
                $parentPath = $candidateParent
                $leaf = Split-Path -Path $typedValue -Leaf
            }
        }
    }

    try {
        $items = @(Get-ChildItem -LiteralPath $parentPath -ErrorAction Stop)
    } catch {
        $items = @()
    }

    foreach ($item in $items) {
        if (-not [string]::IsNullOrWhiteSpace($leaf) -and
            -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidatePath = if ($parentPath -eq '.') {
            $item.Name
        } else {
            Join-Path -Path $parentPath -ChildPath $item.Name
        }

        if ($item.PSIsContainer) {
            $candidatePath += '\'
        }

        $completionText = ConvertTo-AccessChkQuotedValue -Value $candidatePath -AlwaysQuote $alwaysQuote
        $itemToolTip = if ($item.PSIsContainer) { 'Directory path.' } else { 'File path.' }
        [void]$results.Add((New-AccessChkCompletionResult -CompletionText $completionText -ListItemText $completionText -ResultType 'ParameterValue' -ToolTip $itemToolTip))
    }

    if ($results.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
            [void]$results.Add((New-AccessChkCompletionResult -CompletionText $Placeholder -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip))
        } else {
            [void]$results.Add((New-AccessChkCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip $ToolTip))
        }
    }

    @($results.ToArray())
}

function Update-AccessChkProcessCache {
    $age = (Get-Date) - $script:AccessChkCompletionCatalog.ProcessCacheUpdated
    if ($script:AccessChkCompletionCatalog.ProcessCache.Count -gt 0 -and $age.TotalSeconds -lt $script:AccessChkCompletionCatalog.ProcessCacheTtl) {
        return
    }

    try {
        $entries = New-Object System.Collections.Generic.List[string]
        foreach ($process in (Get-Process -ErrorAction Stop | Sort-Object -Property ProcessName)) {
            if (-not [string]::IsNullOrWhiteSpace($process.ProcessName)) {
                [void]$entries.Add($process.ProcessName)
            }
            [void]$entries.Add($process.Id.ToString())
        }

        $script:AccessChkCompletionCatalog.ProcessCache = @($entries | Sort-Object -Unique)
        $script:AccessChkCompletionCatalog.ProcessCacheUpdated = Get-Date
    } catch {
        $script:AccessChkCompletionCatalog.ProcessCache = @()
    }
}

function Update-AccessChkServiceCache {
    $age = (Get-Date) - $script:AccessChkCompletionCatalog.ServiceCacheUpdated
    if ($script:AccessChkCompletionCatalog.ServiceCache.Count -gt 0 -and $age.TotalSeconds -lt $script:AccessChkCompletionCatalog.ServiceCacheTtl) {
        return
    }

    try {
        $script:AccessChkCompletionCatalog.ServiceCache = @(
            Get-Service -ErrorAction Stop |
                Select-Object -ExpandProperty Name |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        $script:AccessChkCompletionCatalog.ServiceCacheUpdated = Get-Date
    } catch {
        $script:AccessChkCompletionCatalog.ServiceCache = @()
    }
}

function Get-AccessChkRegistryCompletions {
    param([string]$CurrentWord)

    $typedValue = Remove-AccessChkOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($root in $script:AccessChkCompletionCatalog.RegistryRoots) {
        if ([string]::IsNullOrWhiteSpace($typedValue) -or
            $root.Token.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-AccessChkCompletionResult -CompletionText $root.Token -ListItemText $root.Token -ResultType 'ParameterValue' -ToolTip $root.Description))
        }
    }

    $rootMatch = $null
    foreach ($root in $script:AccessChkCompletionCatalog.RegistryRoots) {
        if ($typedValue.StartsWith($root.Token, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rootMatch = $root
            break
        }
    }

    if ($rootMatch) {
        $relativePath = $typedValue.Substring($rootMatch.Token.Length)
        $relativeParent = ''
        $leaf = ''

        if (-not [string]::IsNullOrWhiteSpace($relativePath)) {
            if ($relativePath.EndsWith('\')) {
                $relativeParent = $relativePath.TrimEnd('\')
            } else {
                $candidateParent = Split-Path -Path $relativePath -Parent
                if ([string]::IsNullOrWhiteSpace($candidateParent)) {
                    $leaf = $relativePath
                } else {
                    $relativeParent = $candidateParent
                    $leaf = Split-Path -Path $relativePath -Leaf
                }
            }
        }

        $providerParent = $rootMatch.ProviderPath
        if (-not [string]::IsNullOrWhiteSpace($relativeParent)) {
            $providerParent = Join-Path -Path $providerParent -ChildPath $relativeParent
        }

        try {
            $children = @(Get-ChildItem -LiteralPath $providerParent -ErrorAction Stop)
        } catch {
            $children = @()
        }

        foreach ($child in $children) {
            if (-not $child.PSIsContainer) {
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($leaf) -and
                -not $child.PSChildName.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $baseToken = $rootMatch.Token
            if (-not [string]::IsNullOrWhiteSpace($relativeParent)) {
                $baseToken += ($relativeParent.TrimEnd('\') + '\')
            }

            $candidate = $baseToken + $child.PSChildName
            [void]$results.Add((New-AccessChkCompletionResult -CompletionText $candidate -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip 'Registry key path.'))
        }
    }

    if ($results.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
            [void]$results.Add((New-AccessChkCompletionResult -CompletionText 'HKLM\' -ListItemText 'HKLM\' -ResultType 'ParameterValue' -ToolTip 'Registry key path.'))
        } else {
            [void]$results.Add((New-AccessChkCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip 'Registry key path.'))
        }
    }

    @($results.ToArray())
}

function Get-AccessChkCommandState {
    param([string[]]$ArgumentsBeforeCurrent)

    $usedTokens = @{}
    $positionals = New-Object System.Collections.Generic.List[string]
    $mode = $null
    $valueContext = $null

    for ($index = 0; $index -lt $ArgumentsBeforeCurrent.Count; $index++) {
        $token = $ArgumentsBeforeCurrent[$index]
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        $lookup = $token.ToLowerInvariant()
        $usedTokens[$lookup] = $true

        if ($lookup -in @('-?', '/?')) {
            continue
        }

        if ($lookup -in $script:AccessChkCompletionCatalog.ModeTokens -and -not $mode) {
            $mode = $lookup
            continue
        }

        if ($lookup -eq '-f') {
            if ($mode -ne '-p') {
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = '-f'
                    break
                }

                $index++
            }

            continue
        }

        if ($lookup -eq '-t') {
            if ($mode -eq '-o') {
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = '-t'
                    break
                }

                $index++
            }

            continue
        }

        if ($lookup.StartsWith('-') -or $lookup.StartsWith('/')) {
            continue
        }

        $positionals.Add($token)
    }

    [pscustomobject]@{
        UsedTokens   = $usedTokens
        Mode         = $mode
        ValueContext = $valueContext
        Positionals  = @($positionals.ToArray())
    }
}

function Test-AccessChkPathLikeValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $trimmedValue = Remove-AccessChkOuterQuotes -Value $Value
    $trimmedValue -match '^[A-Za-z]:\\|^[.]{1,2}(\\|/)|^[\\/]|[*?]'
}

function Complete-AccessChk {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $line = if ($CommandAst.Extent -and $null -ne $CommandAst.Extent.Text) { $CommandAst.Extent.Text } else { $CommandAst.ToString() }
    if ($cursorPosition -gt $line.Length) {
        $line = $line.PadRight($cursorPosition)
    }
    $tokenState = Get-AccessChkTokenState -Line $line -CursorPosition $CursorPosition
    $argumentsState = Get-AccessChkArgumentsFromTokenState -TokenState $tokenState
    $state = Get-AccessChkCommandState -ArgumentsBeforeCurrent $argumentsState.ArgumentsBeforeCurrent
    $currentWord = $argumentsState.CurrentArgument
    $currentValue = Remove-AccessChkOuterQuotes -Value $currentWord

    if ($state.ValueContext) {
        switch ($state.ValueContext) {
            '-f' { return Get-AccessChkStaticValueResults -CurrentValue $currentWord -Values @('Everyone', 'Users', 'Administrators', 'SYSTEM', '<account[,account...]>') -ToolTip 'Comma-separated account filter.' }
            '-t' { return Get-AccessChkStaticValueResults -CurrentValue $currentWord -Values $script:AccessChkCompletionCatalog.ObjectTypes -ToolTip 'Object Manager object type filter.' }
        }
    }

    $results = New-Object System.Collections.Generic.List[object]

    if (-not $currentWord.StartsWith('-') -and -not $currentWord.StartsWith('/')) {
        switch ($state.Mode) {
            '-a' {
                $results.AddRange((Get-AccessChkStaticValueResults -CurrentValue $currentWord -Values $script:AccessChkCompletionCatalog.AccountRights -ToolTip 'Account right name or * for all rights.'))
            }
            '-c' {
                Update-AccessChkServiceCache
                $serviceValues = @('*', 'scmanager') + $script:AccessChkCompletionCatalog.ServiceCache
                $results.AddRange((Get-AccessChkStaticValueResults -CurrentValue $currentWord -Values $serviceValues -ToolTip 'Service name, scmanager, or * for all services.'))
            }
            '-h' {
                $results.AddRange((Get-AccessChkStaticValueResults -CurrentValue $currentWord -Values $script:AccessChkCompletionCatalog.ShareNames -ToolTip 'Share name or * for all shares.'))
            }
            '-k' {
                $results.AddRange((Get-AccessChkRegistryCompletions -CurrentWord $currentWord))
            }
            '-m' {
                $results.AddRange((Get-AccessChkStaticValueResults -CurrentValue $currentWord -Values $script:AccessChkCompletionCatalog.EventLogNames -ToolTip 'Event log name or * for all event logs.'))
            }
            '-o' {
                $results.AddRange((Get-AccessChkStaticValueResults -CurrentValue $currentWord -Values $script:AccessChkCompletionCatalog.ObjectRoots -ToolTip 'Object Manager namespace path.'))
            }
            '-p' {
                Update-AccessChkProcessCache
                $processValues = @('*') + $script:AccessChkCompletionCatalog.ProcessCache + @('<process-or-pid>')
                $results.AddRange((Get-AccessChkStaticValueResults -CurrentValue $currentWord -Values $processValues -ToolTip 'Process name, PID, or * for all processes.'))
            }
            default {
                if ($state.Positionals.Count -eq 0) {
                    $results.AddRange((Get-AccessChkStaticValueResults -CurrentValue $currentWord -Values $script:AccessChkCompletionCatalog.AccountSamples -ToolTip 'User or group name for effective-permission calculation.'))
                    $results.AddRange((Get-AccessChkPathCompletions -CurrentWord $currentWord -ToolTip 'File system path, named pipe path, or other securable object path.' -Placeholder '<path>'))
                } elseif (($state.Positionals.Count -eq 1) -and -not (Test-AccessChkPathLikeValue -Value $state.Positionals[0])) {
                    $results.AddRange((Get-AccessChkPathCompletions -CurrentWord $currentWord -ToolTip 'File system path, named pipe path, or other securable object path.' -Placeholder '<path>'))
                } else {
                    $results.AddRange((Get-AccessChkPathCompletions -CurrentWord $currentWord -ToolTip 'File system path, named pipe path, or other securable object path.' -Placeholder '<path>'))
                }
            }
        }
    }

    $wantsSwitches = [string]::IsNullOrEmpty($currentWord) -or $currentWord.StartsWith('-') -or $currentWord.StartsWith('/')
    if ($wantsSwitches) {
        foreach ($switchSpec in $script:AccessChkCompletionCatalog.Switches) {
            if (-not $switchSpec.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $lowerToken = $switchSpec.Token.ToLowerInvariant()
            if (($lowerToken -eq '-t') -and -not ($state.Mode -in @('-o', '-p'))) {
                continue
            }

            if (($lowerToken -eq '-f') -and $state.UsedTokens.ContainsKey('-f')) {
                continue
            }

            if (($lowerToken -eq '-?' -or $lowerToken -eq '/?') -and $state.UsedTokens.Count -gt 0 -and -not [string]::IsNullOrEmpty($currentWord)) {
                continue
            }

            [void]$results.Add((New-AccessChkCompletionResult -CompletionText $switchSpec.Token -ListItemText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description))
        }
    }

    Get-AccessChkUniqueCompletions -Results @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('accesschk', 'accesschk.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-AccessChk -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
