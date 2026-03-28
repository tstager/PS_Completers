# psshutdown tab completion for PowerShell
# Native completer for PsShutdown actions, switches, and value-aware placeholders.

Set-StrictMode -Version Latest

function New-PsShutdownCompletionResult {
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

function Remove-PsShutdownOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function Get-PsShutdownCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrEmpty($Line)) {
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

function Get-PsShutdownActionSpecs {
    @(
        [pscustomobject]@{ Token = '-s'; Description = 'Shutdown without poweroff.' }
        [pscustomobject]@{ Token = '-r'; Description = 'Reboot after shutdown.' }
        [pscustomobject]@{ Token = '-h'; Description = 'Hibernate the computer.' }
        [pscustomobject]@{ Token = '-d'; Description = 'Suspend the computer.' }
        [pscustomobject]@{ Token = '-k'; Description = 'Power off the computer.' }
        [pscustomobject]@{ Token = '-a'; Description = 'Abort a shutdown already in progress.' }
        [pscustomobject]@{ Token = '-l'; Description = 'Lock the computer.' }
        [pscustomobject]@{ Token = '-o'; Description = 'Log off the console user.' }
        [pscustomobject]@{ Token = '-x'; Description = 'Turn the monitor off.' }
    )
}

function Get-PsShutdownSwitchSpecs {
    @(
        [pscustomobject]@{ Token = '-f'; Description = 'Force running applications to close.'; TakesValue = $false }
        [pscustomobject]@{ Token = '-c'; Description = 'Allow the shutdown to be aborted by the interactive user.'; TakesValue = $false }
        [pscustomobject]@{ Token = '-t'; Description = 'Countdown seconds or shutdown time in h:m format.'; TakesValue = $true; ValueKind = 'Time' }
        [pscustomobject]@{ Token = '-v'; Description = 'Display the shutdown dialog for the specified number of seconds.'; TakesValue = $true; ValueKind = 'DisplaySeconds' }
        [pscustomobject]@{ Token = '-e'; Description = 'Shutdown reason code in [u|p]:xx:yy form.'; TakesValue = $true; ValueKind = 'ReasonCode' }
        [pscustomobject]@{ Token = '-m'; Description = 'Message shown to logged on users.'; TakesValue = $true; ValueKind = 'Message' }
        [pscustomobject]@{ Token = '-u'; Description = 'User name for the remote connection.'; TakesValue = $true; ValueKind = 'UserName' }
        [pscustomobject]@{ Token = '-p'; Description = 'Optional password for the remote connection user name.'; TakesValue = $true; ValueKind = 'Password' }
        [pscustomobject]@{ Token = '-n'; Description = 'Timeout in seconds for connecting to remote computers.'; TakesValue = $true; ValueKind = 'ConnectTimeout' }
        [pscustomobject]@{ Token = '-nobanner'; Description = 'Suppress the startup banner and copyright message.'; TakesValue = $false }
    )
}

if (-not (Get-Variable -Name PsShutdownCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PsShutdownCompletionCatalog = @{
        Actions             = @(Get-PsShutdownActionSpecs)
        ActionLookup        = @{}
        Switches            = @(Get-PsShutdownSwitchSpecs)
        SwitchLookup        = @{}
        ValueTakingSwitches = @{}
    }

    foreach ($action in $script:PsShutdownCompletionCatalog.Actions) {
        $script:PsShutdownCompletionCatalog.ActionLookup[$action.Token.ToLowerInvariant()] = $action
    }

    foreach ($switchSpec in $script:PsShutdownCompletionCatalog.Switches) {
        $lowerToken = $switchSpec.Token.ToLowerInvariant()
        $script:PsShutdownCompletionCatalog.SwitchLookup[$lowerToken] = $switchSpec
        if ($switchSpec.TakesValue) {
            $script:PsShutdownCompletionCatalog.ValueTakingSwitches[$lowerToken] = $switchSpec.ValueKind
        }
    }
}

function Get-PsShutdownCommandState {
    param([string[]]$TokensBeforeCurrent)

    $usedTokens = @{}
    $selectedAction = $null
    $valueContext = $null
    $hasRemoteTarget = $false
    $remoteTargetToken = $null

    for ($i = 0; $i -lt $TokensBeforeCurrent.Count; $i++) {
        $token = $TokensBeforeCurrent[$i]
        $lookup = $token.ToLowerInvariant()

        if ($script:PsShutdownCompletionCatalog.ActionLookup.ContainsKey($lookup)) {
            $usedTokens[$lookup] = $true
            if (-not $selectedAction) {
                $selectedAction = $lookup
            }
            continue
        }

        if ($script:PsShutdownCompletionCatalog.SwitchLookup.ContainsKey($lookup)) {
            $usedTokens[$lookup] = $true
            if ($script:PsShutdownCompletionCatalog.ValueTakingSwitches.ContainsKey($lookup)) {
                if ($i -eq ($TokensBeforeCurrent.Count - 1)) {
                    $valueContext = $lookup
                    break
                }

                $i++
            }
            continue
        }

        if (-not $hasRemoteTarget) {
            $hasRemoteTarget = $true
            $remoteTargetToken = $token
        }
    }

    [pscustomobject]@{
        UsedTokens        = $usedTokens
        SelectedAction    = $selectedAction
        ValueContext      = $valueContext
        HasRemoteTarget   = $hasRemoteTarget
        RemoteTargetToken = $remoteTargetToken
    }
}

function New-PsShutdownLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-PsShutdownCompletionResult -CompletionText $Placeholder -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-PsShutdownCompletionResult -CompletionText $CurrentValue -ListItemText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-PsShutdownSampleValueResults {
    param(
        [string]$CurrentValue,
        [object[]]$Samples,
        [string]$Placeholder,
        [string]$PlaceholderToolTip
    )

    $typedValue = Remove-PsShutdownOuterQuotes -Value $CurrentValue
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($sample in $Samples) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $sample.CompletionText.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $sample.CompletionText `
                -ListItemText $sample.ListItemText `
                -ResultType 'ParameterValue' `
                -ToolTip $sample.ToolTip
        ))
    }

    if ([string]::IsNullOrWhiteSpace($typedValue) -or
        $Placeholder.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $Placeholder `
                -ListItemText $Placeholder `
                -ResultType 'ParameterValue' `
                -ToolTip $PlaceholderToolTip
        ))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $CurrentValue `
                -ListItemText $CurrentValue `
                -ResultType 'ParameterValue' `
                -ToolTip $PlaceholderToolTip
        ))
    }

    @($results.ToArray())
}

function ConvertTo-PsShutdownQuotedTarget {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + $Value + '"'
    }

    $Value
}

function Get-PsShutdownAtFileCompletions {
    param([string]$CurrentWord)

    $rawValue = if ([string]::IsNullOrEmpty($CurrentWord)) { '@' } else { $CurrentWord }
    $startedQuoted = $rawValue.StartsWith('"')
    $trimmedValue = Remove-PsShutdownOuterQuotes -Value $rawValue
    if (-not $trimmedValue.StartsWith('@')) {
        return @()
    }

    $inputPath = $trimmedValue.Substring(1)
    $cleanInput = $inputPath
    $parent = Split-Path -Path $cleanInput -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) {
        $parent = '.'
    }

    $leaf = Split-Path -Path $cleanInput -Leaf
    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $items = @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($item in $items) {
        $pathText = if ($cleanInput -and -not [System.IO.Path]::IsPathRooted($cleanInput)) {
            if ($parent -eq '.') {
                $item.Name
            } else {
                Join-Path -Path $parent -ChildPath $item.Name
            }
        } else {
            $item.FullName
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $completionText = ConvertTo-PsShutdownQuotedTarget -Value ('@' + $pathText) -AlwaysQuote $startedQuoted
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $completionText `
                -ListItemText ('@' + $item.Name) `
                -ResultType 'ParameterValue' `
                -ToolTip 'Path to a file containing remote computer names.'
        ))
    }

    if ([string]::IsNullOrWhiteSpace($inputPath) -or
        '@file'.StartsWith($trimmedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText '@file' `
                -ListItemText '@file' `
                -ResultType 'ParameterValue' `
                -ToolTip 'Path to a file containing remote computer names.'
        ))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $CurrentWord `
                -ListItemText $CurrentWord `
                -ResultType 'ParameterValue' `
                -ToolTip 'Remote target file in @file form.'
        ))
    }

    @($results.ToArray())
}

function Get-PsShutdownRemoteTargetCompletions {
    param([string]$CurrentWord)

    $typedValue = if ($null -eq $CurrentWord) { '' } else { Remove-PsShutdownOuterQuotes -Value $CurrentWord }
    if ($typedValue.StartsWith('@') -or ($CurrentWord -and $CurrentWord.StartsWith('"@'))) {
        return @(Get-PsShutdownAtFileCompletions -CurrentWord $CurrentWord)
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ($typedValue.Contains(',')) {
        $commaIndex = $typedValue.LastIndexOf(',')
        $prefix = $typedValue.Substring(0, $commaIndex + 1)
        $segment = $typedValue.Substring($commaIndex + 1)
        $candidate = 'computer'

        if ([string]::IsNullOrWhiteSpace($segment) -or
            $candidate.StartsWith($segment, [System.StringComparison]::OrdinalIgnoreCase)) {
            $completionText = $prefix + $candidate
            [void]$results.Add((
                New-PsShutdownCompletionResult `
                    -CompletionText $completionText `
                    -ListItemText $completionText `
                    -ResultType 'ParameterValue' `
                    -ToolTip 'Additional remote computer name in a comma-separated target list.'
            ))
        }

        if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
            [void]$results.Add((
                New-PsShutdownCompletionResult `
                    -CompletionText $CurrentWord `
                    -ListItemText $CurrentWord `
                    -ResultType 'ParameterValue' `
                    -ToolTip 'Remote target list in \\computer[,computer[,...]] form.'
            ))
        }

        return @($results.ToArray())
    }

    $candidates = @(
        [pscustomobject]@{ CompletionText = '\\computer'; ToolTip = 'Remote computer target in \\computer form.' }
        [pscustomobject]@{ CompletionText = '\\*'; ToolTip = 'Broadcast shutdown target placeholder.' }
        [pscustomobject]@{ CompletionText = '@file'; ToolTip = 'Path to a file containing remote computer names.' }
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $candidate.CompletionText.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $candidate.CompletionText `
                -ListItemText $candidate.CompletionText `
                -ResultType 'ParameterValue' `
                -ToolTip $candidate.ToolTip
        ))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $CurrentWord `
                -ListItemText $CurrentWord `
                -ResultType 'ParameterValue' `
                -ToolTip 'Remote target in \\computer[,computer[,...]] or @file form.'
        ))
    }

    @($results.ToArray())
}

function Get-PsShutdownOptionCompletions {
    param(
        [string]$CurrentWord,
        [psobject]$State
    )

    $prefix = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }
    $results = New-Object System.Collections.Generic.List[object]

    if (-not $State.SelectedAction) {
        foreach ($action in $script:PsShutdownCompletionCatalog.Actions) {
            if ($State.UsedTokens.ContainsKey($action.Token.ToLowerInvariant())) {
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($prefix) -and
                -not $action.Token.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            [void]$results.Add((
                New-PsShutdownCompletionResult `
                    -CompletionText $action.Token `
                    -ListItemText $action.Token `
                    -ResultType 'ParameterName' `
                    -ToolTip $action.Description
            ))
        }
    }

    foreach ($switchSpec in $script:PsShutdownCompletionCatalog.Switches) {
        $lowerToken = $switchSpec.Token.ToLowerInvariant()
        if ($State.UsedTokens.ContainsKey($lowerToken)) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($prefix) -and
            -not $switchSpec.Token.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $switchSpec.Token `
                -ListItemText $switchSpec.Token `
                -ResultType 'ParameterName' `
                -ToolTip $switchSpec.Description
        ))
    }

    @($results.ToArray())
}

function Get-PsShutdownValueCompletions {
    param(
        [string]$OptionToken,
        [string]$CurrentWord
    )

    switch ($OptionToken.ToLowerInvariant()) {
        '-t' {
            return @(Get-PsShutdownSampleValueResults -CurrentValue $CurrentWord -Placeholder '<seconds-or-h:mm>' -PlaceholderToolTip 'Countdown seconds or shutdown time in h:m format.' -Samples @(
                    [pscustomobject]@{ CompletionText = '20'; ListItemText = '20'; ToolTip = 'Default countdown in seconds.' }
                    [pscustomobject]@{ CompletionText = '30'; ListItemText = '30'; ToolTip = 'Thirty-second countdown.' }
                    [pscustomobject]@{ CompletionText = '60'; ListItemText = '60'; ToolTip = 'One-minute countdown.' }
                    [pscustomobject]@{ CompletionText = '300'; ListItemText = '300'; ToolTip = 'Five-minute countdown.' }
                    [pscustomobject]@{ CompletionText = '1:00'; ListItemText = '1:00'; ToolTip = 'Shutdown time in 24-hour notation.' }
                    [pscustomobject]@{ CompletionText = '23:00'; ListItemText = '23:00'; ToolTip = 'Shutdown time in 24-hour notation.' }
                ))
        }
        '-v' {
            return @(Get-PsShutdownSampleValueResults -CurrentValue $CurrentWord -Placeholder '<seconds>' -PlaceholderToolTip 'Seconds to display the shutdown dialog.' -Samples @(
                    [pscustomobject]@{ CompletionText = '0'; ListItemText = '0'; ToolTip = 'Skip the shutdown notification dialog.' }
                    [pscustomobject]@{ CompletionText = '5'; ListItemText = '5'; ToolTip = 'Display the shutdown dialog for 5 seconds.' }
                    [pscustomobject]@{ CompletionText = '10'; ListItemText = '10'; ToolTip = 'Display the shutdown dialog for 10 seconds.' }
                    [pscustomobject]@{ CompletionText = '30'; ListItemText = '30'; ToolTip = 'Display the shutdown dialog for 30 seconds.' }
                ))
        }
        '-e' {
            return @(Get-PsShutdownSampleValueResults -CurrentValue $CurrentWord -Placeholder '[u|p]:xx:yy' -PlaceholderToolTip 'Shutdown reason code in planned/unplanned major:minor form.' -Samples @(
                    [pscustomobject]@{ CompletionText = 'u:0:0'; ListItemText = 'u:0:0'; ToolTip = 'Other (Unplanned).' }
                    [pscustomobject]@{ CompletionText = 'p:0:0'; ListItemText = 'p:0:0'; ToolTip = 'Other (Planned).' }
                    [pscustomobject]@{ CompletionText = 'u:2:18'; ListItemText = 'u:2:18'; ToolTip = 'Operating System: Security fix (Unplanned).' }
                    [pscustomobject]@{ CompletionText = 'p:2:17'; ListItemText = 'p:2:17'; ToolTip = 'Operating System: Hot fix (Planned).' }
                    [pscustomobject]@{ CompletionText = 'p:4:2'; ListItemText = 'p:4:2'; ToolTip = 'Application: Installation (Planned).' }
                ))
        }
        '-m' {
            return @(New-PsShutdownLiteralValueResults -CurrentValue $CurrentWord -Placeholder '"<message>"' -ToolTip 'Message text shown to logged on users.')
        }
        '-u' {
            return @(Get-PsShutdownSampleValueResults -CurrentValue $CurrentWord -Placeholder '<username>' -PlaceholderToolTip 'Remote credentials user name.' -Samples @(
                    [pscustomobject]@{ CompletionText = '<domain\user>'; ListItemText = '<domain\user>'; ToolTip = 'Domain-qualified user name.' }
                    [pscustomobject]@{ CompletionText = '.\Administrator'; ListItemText = '.\Administrator'; ToolTip = 'Local Administrator account example.' }
                    [pscustomobject]@{ CompletionText = 'Administrator'; ListItemText = 'Administrator'; ToolTip = 'Simple user name example.' }
                ))
        }
        '-p' {
            return @(New-PsShutdownLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<password>' -ToolTip 'Remote credentials password.')
        }
        '-n' {
            return @(Get-PsShutdownSampleValueResults -CurrentValue $CurrentWord -Placeholder '<seconds>' -PlaceholderToolTip 'Connection timeout in seconds for remote computers.' -Samples @(
                    [pscustomobject]@{ CompletionText = '5'; ListItemText = '5'; ToolTip = 'Five-second connection timeout.' }
                    [pscustomobject]@{ CompletionText = '10'; ListItemText = '10'; ToolTip = 'Ten-second connection timeout.' }
                    [pscustomobject]@{ CompletionText = '30'; ListItemText = '30'; ToolTip = 'Thirty-second connection timeout.' }
                    [pscustomobject]@{ CompletionText = '60'; ListItemText = '60'; ToolTip = 'One-minute connection timeout.' }
                ))
        }
    }

    @()
}

function Complete-PsShutdown {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokens = @($allTokens | Select-Object -Skip 1)
    $line = $commandAst.ToString()
    $currentWord = if ($null -eq $wordToComplete) {
        Get-PsShutdownCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback ''
    } elseif ($wordToComplete.Length -eq 0) {
        ''
    } elseif ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        Get-PsShutdownCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
    } else {
        $wordToComplete
    }

    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)
    if ($hasTrailingSpace) {
        $tokensBeforeCurrent = @($tokens)
    } elseif ($tokens.Count -gt 1) {
        $tokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
    } else {
        $tokensBeforeCurrent = @()
    }

    $state = Get-PsShutdownCommandState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.ValueContext) {
        return @(Get-PsShutdownValueCompletions -OptionToken $state.ValueContext -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord)) {
        if ($currentWord.StartsWith('-')) {
            return @(Get-PsShutdownOptionCompletions -CurrentWord $currentWord -State $state)
        }

        if ($currentWord.StartsWith('\') -or $currentWord.StartsWith('@') -or $currentWord.StartsWith('"@')) {
            return @(Get-PsShutdownRemoteTargetCompletions -CurrentWord $currentWord)
        }

        if ($state.HasRemoteTarget) {
            return @()
        }

        return @(Get-PsShutdownRemoteTargetCompletions -CurrentWord $currentWord)
    }

    if ($state.HasRemoteTarget) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($result in @(Get-PsShutdownOptionCompletions -CurrentWord $currentWord -State $state)) {
        [void]$results.Add($result)
    }

    foreach ($result in @(Get-PsShutdownRemoteTargetCompletions -CurrentWord $currentWord)) {
        [void]$results.Add($result)
    }

    @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName 'psshutdown', 'psshutdown.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsShutdown -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
