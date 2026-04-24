<#
.SYNOPSIS
    Registers a native PowerShell argument completer for wpr.

.DESCRIPTION
    Provides a static-first native completer for `wpr` and `wpr.exe` using the
    local help surface and safe local discovery for profile names and process data.

    The completer covers:
    - top-level WPR commands
    - `-help` topic completion
    - profile-name completion for profile-bearing commands
    - local file and directory completion for path-bearing commands
    - process name and PID completion for heap and snapshot commands
    - enum and placeholder values for common non-path slots

    The script keeps its top level compatible with `Import-CompleterScript`.
#>

Set-StrictMode -Version Latest

function New-WprCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $ListItemText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Get-WprCommandSpecs {
    if (Get-Variable -Name WprCommandSpecs -Scope Script -ErrorAction SilentlyContinue) {
        return $script:WprCommandSpecs
    }

    $script:WprCommandSpecs = @(
        [pscustomobject]@{ Token='/?'; Description='Show WPR help.'; Options=@(); ValueKind=$null }
        [pscustomobject]@{ Token='-?'; Description='Show WPR help.'; Options=@(); ValueKind=$null }
        [pscustomobject]@{ Token='-help'; Description='Show WPR help for a specific topic.'; Options=@(); ValueKind='HelpTopic' }
        [pscustomobject]@{ Token='-start'; Description='Start WPR recording with one or more profiles.'; Options=@('-start','-shutdown','-filemode','-recordtempto','-container','-host','-instancename'); ValueKind='Start' }
        [pscustomobject]@{ Token='-stop'; Description='Stop WPR recording and merge it into the given file.'; Options=@('-skipPdbGen','-force','-compress','-container','-host','-instancename'); ValueKind='Stop' }
        [pscustomobject]@{ Token='-cancel'; Description='Cancel the recording initiated through WPR.'; Options=@('-container','-host','-instancename'); ValueKind='Cancel' }
        [pscustomobject]@{ Token='-merge'; Description='Merge one or more ETL files into the given file.'; Options=@('-skipPdbGen','-compress','-supresspii','-mergeonly','-injectonly'); ValueKind='Merge' }
        [pscustomobject]@{ Token='-status'; Description='Display the status of the active WPR recording.'; Options=@('-details','-container','-host','-instancename'); ValueKind='Status' }
        [pscustomobject]@{ Token='-profiles'; Description='Enumerate built-in or custom profile names.'; Options=@(); ValueKind='Profiles' }
        [pscustomobject]@{ Token='-profiledetails'; Description='Display details about one or more profiles.'; Options=@('-filemode'); ValueKind='ProfileDetails' }
        [pscustomobject]@{ Token='-exportprofile'; Description='Export one or more built-in profiles to a .wprp file.'; Options=@('-filemode'); ValueKind='ExportProfile' }
        [pscustomobject]@{ Token='-providers'; Description='Display provider information.'; Options=@(); ValueKind='Providers' }
        [pscustomobject]@{ Token='-marker'; Description='Fire an event marker.'; Options=@('-flush'); ValueKind='Marker' }
        [pscustomobject]@{ Token='-flush'; Description='Flush logging sessions initiated through WPR.'; Options=@('-container','-host','-instancename'); ValueKind='Flush' }
        [pscustomobject]@{ Token='-capturestateondemand'; Description='Capture provider states in the current recording.'; Options=@('-instancename'); ValueKind='CaptureStateOnDemand' }
        [pscustomobject]@{ Token='-addboot'; Description='Enable Autologger for the given profile.'; Options=@('-addboot','-filemode','-recordtempto','-export'); ValueKind='AddBoot' }
        [pscustomobject]@{ Token='-stopboot'; Description='Stop boot recording and merge it into the given file.'; Options=@(); ValueKind='StopBoot' }
        [pscustomobject]@{ Token='-cancelboot'; Description='Cancel boot recording configured by addboot.'; Options=@(); ValueKind='CancelBoot' }
        [pscustomobject]@{ Token='-heaptracingconfig'; Description='Enable, disable, or query heap tracing for a process or store app.'; Options=@(); ValueKind='HeapTracingConfig' }
        [pscustomobject]@{ Token='-snapshotconfig'; Description='Enable, disable, or query snapshot capture for a process.'; Options=@('-name','-pid'); ValueKind='SnapshotConfig' }
        [pscustomobject]@{ Token='-enableperiodicsnapshot'; Description='Enable periodic snapshot for specified PIDs.'; Options=@(); ValueKind='EnablePeriodicSnapshot' }
        [pscustomobject]@{ Token='-disableperiodicsnapshot'; Description='Disable periodic snapshot.'; Options=@(); ValueKind='DisablePeriodicSnapshot' }
        [pscustomobject]@{ Token='-singlesnapshot'; Description='Take an on-demand snapshot for specified PIDs.'; Options=@(); ValueKind='SingleSnapshot' }
        [pscustomobject]@{ Token='-pmcsources'; Description='Query hardware counters available on the system.'; Options=@(); ValueKind='None' }
        [pscustomobject]@{ Token='-pmcsessions'; Description='Query sessions using hardware counters.'; Options=@(); ValueKind='None' }
        [pscustomobject]@{ Token='-setprofint'; Description='Set sampled profile interval.'; Options=@(); ValueKind='ProfileInterval' }
        [pscustomobject]@{ Token='-profint'; Description='Query the current profile interval.'; Options=@(); ValueKind='None' }
        [pscustomobject]@{ Token='-resetprofint'; Description='Reset profile interval to its default value.'; Options=@(); ValueKind='ResetProfileInterval' }
        [pscustomobject]@{ Token='-purgecache'; Description='Purge the dynamic symbols cache.'; Options=@(); ValueKind='None' }
        [pscustomobject]@{ Token='-log'; Description='Configure WPR debug logging to the event log.'; Options=@(); ValueKind='LogMode' }
        [pscustomobject]@{ Token='-disablepagingexecutive'; Description='Turn Disable Paging Executive on or off.'; Options=@(); ValueKind='PagingExecutive' }
    )

    $script:WprCommandSpecs
}

function Get-WprCommandLookup {
    if (Get-Variable -Name WprCommandLookup -Scope Script -ErrorAction SilentlyContinue) {
        return $script:WprCommandLookup
    }

    $lookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($spec in @(Get-WprCommandSpecs)) {
        $lookup[$spec.Token] = $spec
    }

    $script:WprCommandLookup = $lookup
    $script:WprCommandLookup
}

function Get-WprHelpTopics {
    @('start', 'stop', 'status', 'profiles', 'providers', 'tracing', 'boottrace', 'heap', 'hardwarecounter', 'advanced')
}

function Get-WprStatusTerms {
    @('profiles', 'collectors')
}

function Get-WprProviderSelectors {
    @('Installed', 'I', 'PerfTrack', 'PT', 'UTC')
}

function Get-WprSnapshotOptions {
    @('Heap')
}

function Get-WprLogModes {
    @('enabled', 'disabled', 'remove')
}

function Get-WprPagingModes {
    @('on', 'off')
}

function Get-WprEnableDisableValues {
    @('enable', 'disable')
}

function Get-WprTokenState {
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
        return [pscustomobject]@{ TokensBeforeCurrent = @($tokens); CurrentToken = '' }
    }

    if ($tokens.Count -gt 0) {
        return [pscustomobject]@{ TokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1)); CurrentToken = $tokens[$tokens.Count - 1] }
    }

    [pscustomobject]@{ TokensBeforeCurrent = @(); CurrentToken = '' }
}

function Get-WprArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    $tokensBeforeCurrent = @($TokenState.TokensBeforeCurrent)
    $currentArgument = if ($null -eq $TokenState.CurrentToken) { '' } else { $TokenState.CurrentToken }

    if ($tokensBeforeCurrent.Count -gt 0) {
        $argumentsBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip 1)
    } else {
        $argumentsBeforeCurrent = @()
    }

    if ($tokensBeforeCurrent.Count -eq 0 -and $currentArgument -match '^(?i)wpr(?:\.exe)?$') {
        $currentArgument = ''
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = $argumentsBeforeCurrent
        CurrentArgument        = $currentArgument
    }
}

function Remove-WprOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and (($Value.StartsWith('"') -and $Value.EndsWith('"')) -or ($Value.StartsWith("'") -and $Value.EndsWith("'")))) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"', "'")
}

function ConvertTo-WprQuotedValue {
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

function Get-WprPathCompletions {
    param(
        [string]$CurrentWord,
        [ValidateSet('File','Directory','Any')]
        [string]$Kind = 'Any',
        [string]$ToolTip = 'Path value.',
        [string]$Placeholder = '<path>'
    )

    $typedValue = Remove-WprOuterQuotes -Value $CurrentWord
    $alwaysQuote = $CurrentWord.StartsWith('"')
    $results = New-Object System.Collections.Generic.List[object]

    $parentPath = '.'
    $leaf = ''
    if (-not [string]::IsNullOrWhiteSpace($typedValue)) {
        if ($typedValue.EndsWith('\') -or $typedValue.EndsWith('/')) {
            $parentPath = $typedValue
        } else {
            try {
                $candidateParent = Split-Path -Path $typedValue -Parent
            } catch {
                $candidateParent = ''
            }

            if ([string]::IsNullOrWhiteSpace($candidateParent)) {
                $leaf = $typedValue
            } else {
                $parentPath = $candidateParent
                try {
                    $leaf = Split-Path -Path $typedValue -Leaf
                } catch {
                    $leaf = $typedValue
                }
            }
        }
    }

    try {
        $items = @(Get-ChildItem -LiteralPath $parentPath -ErrorAction Stop)
    } catch {
        $items = @()
    }

    foreach ($item in $items) {
        if ($Kind -eq 'Directory' -and -not $item.PSIsContainer) {
            continue
        }

        if ($Kind -eq 'File' -and $item.PSIsContainer) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($leaf) -and -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidate = if ($parentPath -eq '.') { $item.Name } else { Join-Path -Path $parentPath -ChildPath $item.Name }
        if ($item.PSIsContainer -and -not ($candidate.EndsWith('\') -or $candidate.EndsWith('/'))) {
            $candidate += '\'
        }

        $completionText = ConvertTo-WprQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        [void]$results.Add((New-WprCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $item.FullName))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { $Placeholder } else { $CurrentWord }
        [void]$results.Add((New-WprCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    @($results.ToArray())
}

function Get-WprPlaceholderCompletions {
    param(
        [string]$CurrentWord,
        [string]$Placeholder,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        return @(
            New-WprCompletionResult -CompletionText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-WprCompletionResult -CompletionText $CurrentWord -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-WprEnumCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$Values,
        [string]$ToolTip
    )

    $typedValue = Remove-WprOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($value in @($Values)) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and -not $value.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-WprCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '<value>' } else { $CurrentWord }
        [void]$results.Add((New-WprCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    @($results.ToArray())
}

function Get-WprUniqueResults {
    param([object[]]$Results)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $output = New-Object System.Collections.Generic.List[object]
    foreach ($result in @($Results)) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.Add($result.CompletionText)) {
            [void]$output.Add($result)
        }
    }

    @($output.ToArray())
}

function Get-WprCommandCompletions {
    param([string]$CurrentWord)

    foreach ($command in @(Get-WprCommandSpecs)) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $command.Token.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        New-WprCompletionResult -CompletionText $command.Token -ResultType 'ParameterName' -ToolTip $command.Description
    }
}

function Get-WprProfileNames {
    if (Get-Variable -Name WprProfileCache -Scope Script -ErrorAction SilentlyContinue) {
        $cache = $script:WprProfileCache
        if (((Get-Date) - $cache.UpdatedAt).TotalSeconds -lt 30) {
            return $cache.Values
        }
    }

    $values = New-Object System.Collections.Generic.List[string]
    if (Get-Command -Name wpr.exe -ErrorAction SilentlyContinue) {
        try {
            foreach ($line in @(& wpr.exe -profiles 2>$null)) {
                $text = [string]$line
                $match = [regex]::Match($text, '^\s*(?<name>\S+)\s{2,}.+$')
                if (-not $match.Success) {
                    continue
                }

                $name = $match.Groups['name'].Value
                if ([string]::IsNullOrWhiteSpace($name)) {
                    continue
                }

                [void]$values.Add($name)
                [void]$values.Add($name + '.light')
                [void]$values.Add($name + '.verbose')
            }
        } catch {
        }
    }

    $result = @($values | Sort-Object -Unique)
    $script:WprProfileCache = [pscustomobject]@{ UpdatedAt = Get-Date; Values = $result }
    @($result)
}

function Get-WprProfileSpecCompletions {
    param([string]$CurrentWord)

    $typedValue = Remove-WprOuterQuotes -Value $CurrentWord
    if ($typedValue -match '^(?<path>.+!)(?<profile>[^!]*)$') {
        $prefix = $matches['path']
        $profilePrefix = $matches['profile']
        $results = New-Object System.Collections.Generic.List[object]
        foreach ($profile in @(Get-WprProfileNames)) {
            if (-not [string]::IsNullOrWhiteSpace($profilePrefix) -and -not $profile.StartsWith($profilePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            [void]$results.Add((New-WprCompletionResult -CompletionText ($prefix + $profile) -ResultType 'ParameterValue' -ToolTip 'WPR profile specification.'))
        }

        if ($results.Count -gt 0) {
            return @($results.ToArray())
        }
    }

    if ($typedValue -match '[\\/]' -or $typedValue.EndsWith('.wprp', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @(Get-WprPathCompletions -CurrentWord $CurrentWord -Kind 'File' -ToolTip 'Path to a .wprp profile definition file.' -Placeholder '<profile.wprp>')
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($profile in @(Get-WprProfileNames)) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and -not $profile.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-WprCompletionResult -CompletionText $profile -ResultType 'ParameterValue' -ToolTip 'WPR profile specification.'))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '<profile>' } else { $CurrentWord }
        [void]$results.Add((New-WprCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip 'WPR profile specification.'))
    }

    @($results.ToArray())
}

function Get-WprPlusListCompletions {
    param([string]$CurrentWord)

    $typedValue = Remove-WprOuterQuotes -Value $CurrentWord
    $prefix = ''
    $segment = $typedValue
    $lastPlus = if ([string]::IsNullOrEmpty($typedValue)) { -1 } else { $typedValue.LastIndexOf('+') }
    if ($lastPlus -ge 0) {
        $prefix = $typedValue.Substring(0, $lastPlus + 1)
        $segment = $typedValue.Substring($lastPlus + 1)
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($profile in @(Get-WprProfileNames)) {
        if (-not [string]::IsNullOrWhiteSpace($segment) -and -not $profile.StartsWith($segment, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-WprCompletionResult -CompletionText ($prefix + $profile) -ResultType 'ParameterValue' -ToolTip 'WPR profile list item.'))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '<profile[+profile...]>' } else { $CurrentWord }
        [void]$results.Add((New-WprCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip 'WPR profile list item.'))
    }

    @($results.ToArray())
}

function Get-WprProcessNames {
    if (Get-Variable -Name WprProcessNameCache -Scope Script -ErrorAction SilentlyContinue) {
        $cache = $script:WprProcessNameCache
        if (((Get-Date) - $cache.UpdatedAt).TotalSeconds -lt 10) {
            return $cache.Values
        }
    }

    $processes = @(Get-Process -ErrorAction SilentlyContinue)
    $values = @(
        @($processes | ForEach-Object { $_.ProcessName + '.exe' }) +
        @($processes | ForEach-Object { $_.ProcessName })
    ) | Sort-Object -Unique

    $script:WprProcessNameCache = [pscustomobject]@{ UpdatedAt = Get-Date; Values = $values }
    @($values)
}

function Get-WprProcessIds {
    if (Get-Variable -Name WprProcessIdCache -Scope Script -ErrorAction SilentlyContinue) {
        $cache = $script:WprProcessIdCache
        if (((Get-Date) - $cache.UpdatedAt).TotalSeconds -lt 10) {
            return $cache.Values
        }
    }

    $values = @(
        Get-Process -ErrorAction SilentlyContinue |
            ForEach-Object { [string]$_.Id }
    ) | Sort-Object -Unique

    $script:WprProcessIdCache = [pscustomobject]@{ UpdatedAt = Get-Date; Values = $values }
    @($values)
}

function Get-WprOptionCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$Options
    )

    foreach ($option in @($Options)) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $option.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        New-WprCompletionResult -CompletionText $option -ResultType 'ParameterName' -ToolTip $option
    }
}

function Get-WprEnumOrPlaceholderCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$EnumValues,
        [string]$Placeholder,
        [string]$ToolTip
    )

    $results = @(Get-WprEnumCompletions -CurrentWord $CurrentWord -Values $EnumValues -ToolTip $ToolTip)
    if ($results.Count -gt 0) {
        return $results
    }

    @(Get-WprPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder $Placeholder -ToolTip $ToolTip)
}

function Complete-Wpr {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $commandLookup = Get-WprCommandLookup
    $tokenState = Get-WprTokenState -Line $commandAst.ToString() -CursorPosition $cursorPosition
    $argumentState = Get-WprArgumentsFromTokenState -TokenState $tokenState
    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)

    if ($hasTrailingSpace -and -not [string]::IsNullOrEmpty($argumentState.CurrentArgument)) {
        $currentWord = ''
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent + $argumentState.CurrentArgument)
    } else {
        $currentWord = if ($null -eq $argumentState.CurrentArgument) { '' } else { $argumentState.CurrentArgument }
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent)
    }

    $activeCommand = $null
    foreach ($token in @($argumentsBeforeCurrent)) {
        if ($commandLookup.ContainsKey($token)) {
            $activeCommand = $commandLookup[$token]
            break
        }
    }

    if ($null -eq $activeCommand) {
        if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('-') -or $currentWord.StartsWith('/')) {
            return @(Get-WprCommandCompletions -CurrentWord $currentWord)
        }

        return @()
    }

    $commandIndex = [Array]::IndexOf($argumentsBeforeCurrent, $activeCommand.Token)
    $tokensAfterCommand = @(
        if ($commandIndex -ge 0 -and $commandIndex -lt ($argumentsBeforeCurrent.Count - 1)) {
            $argumentsBeforeCurrent[($commandIndex + 1)..($argumentsBeforeCurrent.Count - 1)]
        }
    )

    switch ($activeCommand.ValueKind) {
        'HelpTopic' {
            if ($tokensAfterCommand.Count -eq 0) {
                return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprHelpTopics) -ToolTip 'WPR help topic.')
            }

            return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder ' ' -ToolTip 'No further arguments are valid after -help <topic>.')
        }
        'Start' {
            if ($tokensAfterCommand.Count -gt 0) {
                $previousToken = $tokensAfterCommand[-1]
                if ($previousToken -in @('-start')) {
                    return @(Get-WprProfileSpecCompletions -CurrentWord $currentWord)
                }
                if ($previousToken -eq '-recordtempto') {
                    return @(Get-WprPathCompletions -CurrentWord $currentWord -Kind 'Directory' -ToolTip 'Temporary recording folder.' -Placeholder '<temp-folder>')
                }
                if ($previousToken -eq '-container') {
                    return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<container-id>' -ToolTip 'Container ID.')
                }
                if ($previousToken -eq '-instancename') {
                    return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<instance-name>' -ToolTip 'Unique WPR instance name.')
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
                return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
            }

            return @(Get-WprProfileSpecCompletions -CurrentWord $currentWord)
        }
        'AddBoot' {
            if ($tokensAfterCommand.Count -gt 0) {
                $previousToken = $tokensAfterCommand[-1]
                if ($previousToken -eq '-addboot') {
                    return @(Get-WprProfileSpecCompletions -CurrentWord $currentWord)
                }
                if ($previousToken -eq '-recordtempto') {
                    return @(Get-WprPathCompletions -CurrentWord $currentWord -Kind 'Directory' -ToolTip 'Temporary recording folder.' -Placeholder '<temp-folder>')
                }
                if ($previousToken -eq '-export') {
                    return @(Get-WprPathCompletions -CurrentWord $currentWord -Kind 'File' -ToolTip 'Registry export file path.' -Placeholder '<file>')
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
                return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
            }

            return @(Get-WprProfileSpecCompletions -CurrentWord $currentWord)
        }
        'Stop' {
            if ($tokensAfterCommand.Count -eq 0) {
                return @(Get-WprPathCompletions -CurrentWord $currentWord -Kind 'File' -ToolTip 'Recording output file.' -Placeholder '<recording.etl>')
            }

            if ($tokensAfterCommand.Count -eq 1 -and -not ($currentWord.StartsWith('-'))) {
                return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<problem-description>' -ToolTip 'Problem description.')
            }

            return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
        }
        'StopBoot' {
            if ($tokensAfterCommand.Count -eq 0) {
                return @(Get-WprPathCompletions -CurrentWord $currentWord -Kind 'File' -ToolTip 'Recording output file.' -Placeholder '<recording.etl>')
            }

            return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<problem-description>' -ToolTip 'Problem description.')
        }
        'Cancel' {
            if ($tokensAfterCommand.Count -gt 0) {
                $previousToken = $tokensAfterCommand[-1]
                if ($previousToken -eq '-container') {
                    return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<container-id>' -ToolTip 'Container ID.')
                }
                if ($previousToken -eq '-instancename') {
                    return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<instance-name>' -ToolTip 'Unique WPR instance name.')
                }
            }

            return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
        }
        'Merge' {
            if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
                return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
            }

            return @(Get-WprPathCompletions -CurrentWord $currentWord -Kind 'File' -ToolTip 'Trace file path.' -Placeholder '<trace.etl>')
        }
        'Status' {
            if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
                return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
            }

            $results = New-Object System.Collections.Generic.List[object]
            foreach ($value in @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprStatusTerms) -ToolTip 'WPR status detail selector.')) {
                [void]$results.Add($value)
            }
            foreach ($value in @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)) {
                [void]$results.Add($value)
            }
            return @(Get-WprUniqueResults -Results $results.ToArray())
        }
        'Profiles' {
            return @(Get-WprPathCompletions -CurrentWord $currentWord -Kind 'File' -ToolTip 'Optional .wprp profile definition file.' -Placeholder '<profile.wprp>')
        }
        'ProfileDetails' {
            if ($tokensAfterCommand.Count -eq 0 -or ($tokensAfterCommand.Count -gt 0 -and -not ($currentWord.StartsWith('-')))) {
                return @(Get-WprPlusListCompletions -CurrentWord $currentWord)
            }

            return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
        }
        'ExportProfile' {
            if ($tokensAfterCommand.Count -eq 0) {
                return @(Get-WprPlusListCompletions -CurrentWord $currentWord)
            }

            if ($tokensAfterCommand.Count -eq 1 -and -not ($currentWord.StartsWith('-'))) {
                return @(Get-WprPathCompletions -CurrentWord $currentWord -Kind 'File' -ToolTip 'Destination .wprp file.' -Placeholder '<file.wprp>')
            }

            return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
        }
        'Providers' {
            return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprProviderSelectors) -ToolTip 'Provider selector.')
        }
        'Marker' {
            if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
                return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
            }

            return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<scenario-name>' -ToolTip 'Scenario marker name.')
        }
        'Flush' {
            if ($tokensAfterCommand.Count -gt 0) {
                $previousToken = $tokensAfterCommand[-1]
                if ($previousToken -eq '-container') {
                    return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<container-id>' -ToolTip 'Container ID.')
                }
                if ($previousToken -eq '-instancename') {
                    return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<instance-name>' -ToolTip 'Unique WPR instance name.')
                }
            }

            return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
        }
        'CaptureStateOnDemand' {
            if ($tokensAfterCommand.Count -gt 0 -and $tokensAfterCommand[-1] -eq '-instancename') {
                return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<instance-name>' -ToolTip 'Unique WPR instance name.')
            }

            return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
        }
        'HeapTracingConfig' {
            if ($tokensAfterCommand.Count -eq 0) {
                return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprProcessNames) -ToolTip 'Process name.')
            }

            return @(Get-WprEnumOrPlaceholderCompletions -CurrentWord $currentWord -EnumValues (Get-WprEnableDisableValues) -Placeholder '<package-or-mode>' -ToolTip 'Enable/disable value or app package metadata.')
        }
        'SnapshotConfig' {
            if ($tokensAfterCommand.Count -eq 0) {
                return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprSnapshotOptions) -ToolTip 'Snapshot option.')
            }

            if ($tokensAfterCommand[-1] -eq '-name') {
                return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprProcessNames) -ToolTip 'Process name.')
            }

            if ($tokensAfterCommand[-1] -eq '-pid') {
                return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprProcessIds) -ToolTip 'Process ID.')
            }

            if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
                return @(Get-WprOptionCompletions -CurrentWord $currentWord -Options $activeCommand.Options)
            }

            return @(Get-WprEnumOrPlaceholderCompletions -CurrentWord $currentWord -EnumValues (Get-WprEnableDisableValues) -Placeholder '<mode>' -ToolTip 'Enable or disable snapshot capture.')
        }
        'EnablePeriodicSnapshot' {
            if ($tokensAfterCommand.Count -eq 0) {
                return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprSnapshotOptions) -ToolTip 'Snapshot option.')
            }
            if ($tokensAfterCommand.Count -eq 1) {
                return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<interval-seconds>' -ToolTip 'Periodic snapshot interval in seconds.')
            }

            return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprProcessIds) -ToolTip 'Process ID.')
        }
        'DisablePeriodicSnapshot' {
            return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprSnapshotOptions) -ToolTip 'Snapshot option.')
        }
        'SingleSnapshot' {
            if ($tokensAfterCommand.Count -eq 0) {
                return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprSnapshotOptions) -ToolTip 'Snapshot option.')
            }

            return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprProcessIds) -ToolTip 'Process ID.')
        }
        'ProfileInterval' {
            return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<profiling-interval>' -ToolTip 'Sampling profile interval.')
        }
        'ResetProfileInterval' {
            return @(Get-WprPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<profile-source-name>' -ToolTip 'Optional profile source name.')
        }
        'LogMode' {
            return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprLogModes) -ToolTip 'WPR debug logging mode.')
        }
        'PagingExecutive' {
            return @(Get-WprEnumCompletions -CurrentWord $currentWord -Values (Get-WprPagingModes) -ToolTip 'Disable Paging Executive mode.')
        }
        'None' {
            return @()
        }
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('wpr', 'wpr.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Wpr -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
