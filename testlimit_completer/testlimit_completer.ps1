# Testlimit.exe tab completion for PowerShell
# Static native completer for Testlimit modelled on the v5.24 usage grammar:
#   testlimit [[-h [-u]] | [-p [-n]] | [-t [-n [KB]]] | [-u [-i]] | [-g [object size]]
#             | [-a|-d|-l|-m|-r|-s|-v [MB]] | [-w]] [-c [count]] [-e [seconds]]
# Every numeric value is optional, the primary mode groups are mutually
# exclusive, and -c must be the last option specified.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name TestlimitCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:TestlimitCompletionCatalog = @{
        SwitchOrder = @('-a', '-c', '-d', '-e', '-g', '-h', '-i', '-l', '-m', '-n', '-p', '-r', '-s', '-t', '-u', '-v', '-w', '-accepteula', '-?', '/?', '/accepteula')
        SwitchInfo  = @{
            '-a'           = 'Leak Address Windowing Extensions (AWE) memory in specified MBs (default is 1).'
            '-c'           = 'Count of objects to allocate (default is as many as possible). This must be the last option specified.'
            '-d'           = 'Leak and touch memory in specified MBs (default is 1).'
            '-e'           = 'Seconds elapsed between allocations (default is 0).'
            '-g'           = 'Create GDI handles of specified size (default 1 byte). A size of 0 causes GDI object exhaustion.'
            '-h'           = 'Create handles. Specify -u to also allocate file objects.'
            '-i'           = 'Exhaust USER desktop heap.'
            '-l'           = 'Allocate the specified amount of large pages.'
            '-m'           = 'Leak memory in specified MBs (default is 1).'
            '-n'           = 'With -p set min working set; with -t specify minimum stack reserve in KB.'
            '-p'           = 'Create processes. Add -n to set min working set.'
            '-r'           = 'Reserve memory in specified MBs (default is 1).'
            '-s'           = 'Leak shared memory in specified MBs (default is 1).'
            '-t'           = 'Create threads. Add -n to specify minimum stack reserve in KB.'
            '-u'           = 'Create USER handles to menus.'
            '-v'           = 'VirtualLock memory in specified MBs (default is 1).'
            '-w'           = 'Reset working set minimum to the highest possible value.'
            '-accepteula'  = 'Silently accept the Sysinternals EULA (required for unattended use).'
            '-?'           = 'Display Testlimit help.'
            '/?'           = 'Display Testlimit help.'
            '/accepteula'  = 'Slash form of -accepteula.'
        }
        # Exactly one primary mode may be chosen; the '|' groups of the usage line.
        ModeGroups     = @{
            handles    = @('-h')
            processes  = @('-p')
            threads    = @('-t')
            user       = @('-u')
            gdi        = @('-g')
            memory     = @('-a', '-d', '-l', '-m', '-r', '-s', '-v')
            workingset = @('-w')
        }
        # Sub-options each mode still accepts once it has been chosen.
        GroupModifiers = @{
            handles    = @('-u')
            processes  = @('-n')
            threads    = @('-n')
            user       = @('-i')
            gdi        = @()
            memory     = @()
            workingset = @()
        }
        # Legal alongside any mode.
        GlobalSwitches = @('-c', '-e', '-accepteula', '/accepteula')
        SlashSwitches  = @('/?', '/accepteula')
        HelpSwitches   = @('-?', '/?')
        ValueSpec      = @{
            '-a' = @{ Samples = @('1', '16', '64', '256'); Placeholder = '<mb>'; ToolTip = 'AWE memory MB (optional, default 1).' }
            '-d' = @{ Samples = @('1', '16', '64', '256'); Placeholder = '<mb>'; ToolTip = 'Memory MB (optional, default 1).' }
            '-l' = @{ Samples = @('1', '16', '64', '256'); Placeholder = '<mb>'; ToolTip = 'Large pages MB (optional, default 1).' }
            '-m' = @{ Samples = @('1', '16', '64', '256'); Placeholder = '<mb>'; ToolTip = 'Memory MB (optional, default 1).' }
            '-r' = @{ Samples = @('1', '16', '64', '256'); Placeholder = '<mb>'; ToolTip = 'Reserved memory MB (optional, default 1).' }
            '-s' = @{ Samples = @('1', '16', '64', '256'); Placeholder = '<mb>'; ToolTip = 'Shared memory MB (optional, default 1).' }
            '-v' = @{ Samples = @('1', '16', '64', '256'); Placeholder = '<mb>'; ToolTip = 'VirtualLock memory MB (optional, default 1).' }
            '-g' = @{ Samples = @('0', '1', '256', '4096'); Placeholder = '<object-size-bytes>'; ToolTip = 'GDI object size in bytes (optional, default 1).' }
            '-c' = @{ Samples = @('1', '10', '100', '1000'); Placeholder = '<count>'; ToolTip = 'Object allocation count (optional, default as many as possible).' }
            '-e' = @{ Samples = @('0', '1', '5', '10'); Placeholder = '<seconds>'; ToolTip = 'Seconds between allocations (optional, default 0).' }
            '-n' = @{ Samples = @('64', '128', '256', '1024'); Placeholder = '<stack-kb>'; ToolTip = 'Minimum stack reserve in KB for -t (optional).' }
        }
    }
}

function New-TestlimitCompletionResult {
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

function Get-TestlimitCurrentToken {
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

function Get-TestlimitSwitchGroup {
    param([string]$Token)

    $groups = $script:TestlimitCompletionCatalog.ModeGroups
    foreach ($name in @($groups.Keys)) {
        if (@($groups[$name]) -contains $Token) {
            return $name
        }
    }

    $null
}

function Get-TestlimitCommandState {
    param([object[]]$TokensBeforeCurrent)

    $catalog = $script:TestlimitCompletionCatalog
    $tokens = @(@($TokensBeforeCurrent) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    $usedSwitchLookup = @{}
    $valueContext = $null
    $helpRequested = $false
    $activeGroup = $null

    for ($index = 0; $index -lt $tokens.Count; $index++) {
        $lookup = ([string]$tokens[$index]).ToLowerInvariant()
        if (-not ($lookup.StartsWith('-') -or $lookup.StartsWith('/'))) {
            continue
        }

        $usedSwitchLookup[$lookup] = $true
        if ($catalog.HelpSwitches -contains $lookup) {
            $helpRequested = $true
            continue
        }

        if ($null -eq $activeGroup) {
            $group = Get-TestlimitSwitchGroup -Token $lookup
            if ($group) {
                $activeGroup = $group
            }
        }

        # -n only carries a stack-reserve value after -t.
        $takesValue = $catalog.ValueSpec.ContainsKey($lookup)
        if ($lookup -eq '-n' -and -not $usedSwitchLookup.ContainsKey('-t')) {
            $takesValue = $false
        }

        if (-not $takesValue) {
            continue
        }

        if ($index -eq ($tokens.Count - 1)) {
            $valueContext = $lookup
            break
        }

        # The value is optional, so only an actual number consumes the slot.
        if (([string]$tokens[$index + 1]) -match '^\d+$') {
            $index++
        }
    }

    [pscustomobject]@{
        UsedSwitchLookup = $usedSwitchLookup
        ValueContext     = $valueContext
        HelpRequested    = $helpRequested
        ActiveGroup      = $activeGroup
    }
}

function Test-TestlimitSwitchAllowed {
    param(
        [string]$Token,
        [pscustomobject]$State,
        [bool]$NoArgumentsYet
    )

    $catalog = $script:TestlimitCompletionCatalog
    if ($State.UsedSwitchLookup.ContainsKey($Token)) {
        return $false
    }

    if ($catalog.HelpSwitches -contains $Token) {
        return $NoArgumentsYet
    }

    # '-c ... must be the last option specified.'
    if ($State.UsedSwitchLookup.ContainsKey('-c')) {
        return $false
    }

    if ($Token -in @('-accepteula', '/accepteula')) {
        return -not ($State.UsedSwitchLookup.ContainsKey('-accepteula') -or $State.UsedSwitchLookup.ContainsKey('/accepteula'))
    }

    if ($catalog.GlobalSwitches -contains $Token) {
        return $true
    }

    if ($null -eq $State.ActiveGroup) {
        # No primary mode chosen yet, so only a mode switch is legal.
        return ($null -ne (Get-TestlimitSwitchGroup -Token $Token))
    }

    @($catalog.GroupModifiers[$State.ActiveGroup]) -contains $Token
}

function Get-TestlimitSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State,
        [bool]$NoArgumentsYet
    )

    $catalog = $script:TestlimitCompletionCatalog
    $prefix = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '' } else { $CurrentWord }
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($token in $catalog.SwitchOrder) {
        if ($catalog.SlashSwitches -contains $token) {
            if (-not $prefix.StartsWith('/')) {
                continue
            }
        }

        if ($prefix -and -not $token.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if (-not (Test-TestlimitSwitchAllowed -Token $token -State $State -NoArgumentsYet $NoArgumentsYet)) {
            continue
        }

        $results.Add((New-TestlimitCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $catalog.SwitchInfo[$token]))
    }

    @($results.ToArray())
}

function Get-TestlimitValueCompletions {
    param(
        [string]$ValueContext,
        [string]$CurrentValue,
        [pscustomobject]$State,
        [bool]$NoArgumentsYet
    )

    $spec = $script:TestlimitCompletionCatalog.ValueSpec[$ValueContext]
    $typedValue = if ([string]::IsNullOrWhiteSpace($CurrentValue)) { '' } else { $CurrentValue.Trim('"') }
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($sample in $spec.Samples) {
        if ($typedValue -and -not $sample.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $results.Add((New-TestlimitCompletionResult -CompletionText $sample -ResultType 'ParameterValue' -ToolTip $spec.ToolTip))
    }

    if (-not $typedValue -or $spec.Placeholder.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        $results.Add((New-TestlimitCompletionResult -CompletionText $spec.Placeholder -ResultType 'ParameterValue' -ToolTip $spec.ToolTip))
    } elseif ($typedValue -match '^\d+$' -and @($spec.Samples) -notcontains $typedValue) {
        # A number the sample ladder does not list is still a valid value.
        $results.Add((New-TestlimitCompletionResult -CompletionText $typedValue -ResultType 'ParameterValue' -ToolTip $spec.ToolTip))
    }

    if ($results.Count -eq 0) {
        $results.Add((New-TestlimitCompletionResult -CompletionText $spec.Placeholder -ResultType 'ParameterValue' -ToolTip $spec.ToolTip))
    }

    # Every value is optional, so the still-legal switches remain reachable -
    # except after -c, which the tool requires to be the last option.
    if ($ValueContext -ne '-c') {
        foreach ($result in Get-TestlimitSwitchCompletions -CurrentWord $CurrentValue -State $State -NoArgumentsYet $NoArgumentsYet) {
            $results.Add($result)
        }
    }

    @($results.ToArray())
}

function Complete-Testlimit {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $line = $commandAst.ToString()
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    $safeCursor = [Math]::Min([Math]::Max($relativeCursor, 0), $line.Length)
    $linePrefix = $line.Substring(0, $safeCursor)
    $commandTokens = @([regex]::Matches($linePrefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })

    $argumentTokens = @()
    if ($commandTokens.Count -gt 1) {
        $argumentTokens = @($commandTokens | Select-Object -Skip 1)
    }

    $currentWord = if ([string]::IsNullOrEmpty($wordToComplete)) {
        Get-TestlimitCurrentToken -Line $line -CursorPosition $relativeCursor -Fallback $wordToComplete
    } else {
        $wordToComplete
    }

    $hasTrailingSpace = [string]::IsNullOrEmpty($currentWord) -and (($linePrefix -match '\s$') -or ($relativeCursor -gt $line.Length))
    $tokensBeforeCurrent = @()
    if ($hasTrailingSpace) {
        $tokensBeforeCurrent = @($argumentTokens)
    } elseif ($argumentTokens.Count -gt 1) {
        $tokensBeforeCurrent = @($argumentTokens | Select-Object -First ($argumentTokens.Count - 1))
    }

    $state = Get-TestlimitCommandState -TokensBeforeCurrent $tokensBeforeCurrent
    $noArgumentsYet = ($tokensBeforeCurrent.Count -eq 0)

    if ($state.HelpRequested) {
        return @(
            New-TestlimitCompletionResult -CompletionText '-?' -ResultType 'ParameterName' -ToolTip 'Display Testlimit help.'
        )
    }

    # A dash or slash always means a switch, even inside an optional value slot.
    if ($currentWord -and ($currentWord.StartsWith('-') -or $currentWord.StartsWith('/'))) {
        return @(Get-TestlimitSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet $noArgumentsYet)
    }

    if ($state.ValueContext) {
        return @(Get-TestlimitValueCompletions -ValueContext $state.ValueContext -CurrentValue $currentWord -State $state -NoArgumentsYet $noArgumentsYet)
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-TestlimitSwitchCompletions -CurrentWord $currentWord -State $state -NoArgumentsYet $noArgumentsYet)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('testlimit', 'testlimit.exe', 'Testlimit', 'Testlimit.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Testlimit -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
