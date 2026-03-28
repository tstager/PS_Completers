# PsService tab completion for PowerShell
# Provides standalone native completion for psservice.exe with local service hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name PsServiceCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PsServiceCompletionCatalog = @{
        CommandName      = $null
        TopLevelCommands = @(
            [pscustomobject]@{ Name = 'query'; Description = 'Queries the status of a service.' }
            [pscustomobject]@{ Name = 'config'; Description = 'Queries the configuration.' }
            [pscustomobject]@{ Name = 'setconfig'; Description = 'Sets the configuration.' }
            [pscustomobject]@{ Name = 'start'; Description = 'Starts a service.' }
            [pscustomobject]@{ Name = 'stop'; Description = 'Stops a service.' }
            [pscustomobject]@{ Name = 'restart'; Description = 'Stops and then restarts a service.' }
            [pscustomobject]@{ Name = 'pause'; Description = 'Pauses a service.' }
            [pscustomobject]@{ Name = 'cont'; Description = 'Continues a paused service.' }
            [pscustomobject]@{ Name = 'depend'; Description = 'Enumerates the services that depend on the specified service.' }
            [pscustomobject]@{ Name = 'find'; Description = 'Searches for an instance of a service on the network.' }
            [pscustomobject]@{ Name = 'security'; Description = 'Reports the security permissions assigned to a service.' }
        )
        RootSwitches     = @(
            [pscustomobject]@{ Name = '-?'; Description = 'Show help.' }
            [pscustomobject]@{ Name = '/?'; Description = 'Show help.' }
            [pscustomobject]@{ Name = '-nobanner'; Description = 'Suppress the startup banner and copyright message.' }
            [pscustomobject]@{ Name = '-u'; Description = 'Username for the remote-auth preamble.' }
            [pscustomobject]@{ Name = '-p'; Description = 'Password for the remote-auth preamble.' }
        )
        CommandSwitches  = @(
            [pscustomobject]@{ Name = '-?'; Description = 'Show help for the selected command.' }
            [pscustomobject]@{ Name = '/?'; Description = 'Show help for the selected command.' }
        )
        QuerySwitches    = @(
            [pscustomobject]@{ Name = '-g'; Description = 'Restrict query results to a load-order group.' }
            [pscustomobject]@{ Name = '-t'; Description = 'Restrict query results by type.' }
            [pscustomobject]@{ Name = '-s'; Description = 'Restrict query results by state.' }
        )
        QueryTypeValues  = @('driver', 'service', 'interactive', 'all')
        QueryStateValues = @('active', 'inactive', 'all')
        StartTypeValues  = @('auto', 'demand', 'disabled')
    }
}

if (-not (Get-Variable -Name PsServiceServiceCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PsServiceServiceCache = @{
        LastUpdated  = [datetime]::MinValue
        TtlSeconds   = 30
        ServiceNames = @()
        DisplayNames = @()
    }
}

function Resolve-PsServiceCommandName {
    if ($script:PsServiceCompletionCatalog.CommandName) {
        return $script:PsServiceCompletionCatalog.CommandName
    }

    $command = Get-Command -Name 'psservice.exe', 'psservice' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        if ($command.Source) {
            $script:PsServiceCompletionCatalog.CommandName = $command.Source
        } elseif ($command.Path) {
            $script:PsServiceCompletionCatalog.CommandName = $command.Path
        } else {
            $script:PsServiceCompletionCatalog.CommandName = $command.Name
        }
    }

    $script:PsServiceCompletionCatalog.CommandName
}

function Test-PsServiceCommandAvailable {
    [bool](Resolve-PsServiceCommandName)
}

function New-PsServiceCompletionResult {
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

function New-PsServiceLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$ToolTip,
        [string]$Placeholder = '<value>'
    )

    if ([string]::IsNullOrEmpty($CurrentValue)) {
        return @(
            New-PsServiceCompletionResult -CompletionText $Placeholder -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-PsServiceCompletionResult -CompletionText $CurrentValue -ListItemText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Test-PsServiceStartsWith {
    param(
        [string]$Value,
        [string]$Prefix
    )

    if ([string]::IsNullOrEmpty($Prefix)) {
        return $true
    }

    if ([string]::IsNullOrEmpty($Value)) {
        return $false
    }

    $Value.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-PsServiceUniqueCompletions {
    param([System.Management.Automation.CompletionResult[]]$Results)

    $seen = @{}
    $unique = @()
    foreach ($result in $Results) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.ContainsKey($result.CompletionText)) {
            continue
        }

        $seen[$result.CompletionText] = $true
        $unique += $result
    }

    $unique
}

function Update-PsServiceServiceCache {
    $age = (Get-Date) - $script:PsServiceServiceCache.LastUpdated
    if ($script:PsServiceServiceCache.ServiceNames.Count -gt 0 -and $age.TotalSeconds -lt $script:PsServiceServiceCache.TtlSeconds) {
        return
    }

    try {
        $services = @(Get-Service -ErrorAction Stop | Sort-Object -Property Name)
        $script:PsServiceServiceCache.ServiceNames = @(
            $services |
                Select-Object -ExpandProperty Name |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        $script:PsServiceServiceCache.DisplayNames = @(
            $services |
                Select-Object -ExpandProperty DisplayName |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        $script:PsServiceServiceCache.LastUpdated = Get-Date
    } catch {
        if (-not $script:PsServiceServiceCache.ServiceNames) {
            $script:PsServiceServiceCache.ServiceNames = @()
        }
        if (-not $script:PsServiceServiceCache.DisplayNames) {
            $script:PsServiceServiceCache.DisplayNames = @()
        }
    }
}

function Get-PsServiceCurrentTokenState {
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
            HasTrailingSpace    = $true
        }
    }

    if ($tokens.Count -gt 0) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
            CurrentToken        = $tokens[$tokens.Count - 1]
            HasTrailingSpace    = $false
        }
    }

    [pscustomobject]@{
        TokensBeforeCurrent = @()
        CurrentToken        = ''
        HasTrailingSpace    = $false
    }
}

function Get-PsServiceArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    if (-not $TokenState) {
        return [pscustomobject]@{
            ArgumentsBeforeCurrent = @()
            CurrentWord            = ''
        }
    }

    $tokensBeforeCurrent = @($TokenState.TokensBeforeCurrent)
    if ($tokensBeforeCurrent.Count -eq 0) {
        return [pscustomobject]@{
            ArgumentsBeforeCurrent = @()
            CurrentWord            = $TokenState.CurrentToken
        }
    }

    $arguments = @()
    if ($tokensBeforeCurrent.Count -gt 1) {
        $arguments = @($tokensBeforeCurrent | Select-Object -Skip 1)
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = $arguments
        CurrentWord            = $TokenState.CurrentToken
    }
}

function Get-PsServiceStringValueCompletions {
    param(
        [string[]]$Values,
        [string]$CurrentWord,
        [string]$ToolTip,
        [string]$Prefix = '',
        [bool]$QuoteWhitespace = $false
    )

    $matchPrefix = $CurrentWord
    if ($matchPrefix.Length -gt 0 -and (($matchPrefix[0] -eq [char]34) -or ($matchPrefix[0] -eq [char]39))) {
        $matchPrefix = $matchPrefix.Substring(1)
    }

    $results = @()
    foreach ($value in ($Values | Sort-Object -Unique)) {
        if (Test-PsServiceStartsWith -Value $value -Prefix $matchPrefix) {
            $completionText = $value
            if ($QuoteWhitespace -and ($value -match '\s' -or ($CurrentWord.Length -gt 0 -and (($CurrentWord[0] -eq [char]34) -or ($CurrentWord[0] -eq [char]39))))) {
                $quoteCharacter = if ($CurrentWord.Length -gt 0 -and $CurrentWord[0] -eq [char]34) { '"' } else { "'" }
                $escapedValue = if ($quoteCharacter -eq "'") {
                    $value -replace "'", "''"
                } else {
                    $value -replace '"', '`"'
                }

                $completionText = '{0}{1}{0}' -f $quoteCharacter, $escapedValue
            }

            $results += New-PsServiceCompletionResult -CompletionText ($Prefix + $completionText) -ListItemText $value -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }

    $results
}

function Get-PsServiceServiceNameCompletions {
    param([string]$CurrentWord)

    Update-PsServiceServiceCache
    Get-PsServiceStringValueCompletions -Values $script:PsServiceServiceCache.ServiceNames -CurrentWord $CurrentWord -ToolTip 'Local service name.' -QuoteWhitespace $true
}

function Get-PsServiceDisplayNameCompletions {
    param([string]$CurrentWord)

    Update-PsServiceServiceCache
    Get-PsServiceStringValueCompletions -Values $script:PsServiceServiceCache.DisplayNames -CurrentWord $CurrentWord -ToolTip 'Local service display name.' -QuoteWhitespace $true
}

function Get-PsServiceCombinedServiceCompletions {
    param([string]$CurrentWord)

    $results = @()
    $results += @(Get-PsServiceServiceNameCompletions -CurrentWord $CurrentWord)
    $results += @(Get-PsServiceDisplayNameCompletions -CurrentWord $CurrentWord)
    Get-PsServiceUniqueCompletions -Results $results
}

function Get-PsServiceServerPlaceholderCompletions {
    param([string]$CurrentWord)

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        return @(
            New-PsServiceCompletionResult -CompletionText '\\Computer' -ListItemText '\\Computer' -ResultType 'ParameterValue' -ToolTip 'Remote computer name in \\Computer form.'
        )
    }

    if ('\\Computer'.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
        return @(
            New-PsServiceCompletionResult -CompletionText '\\Computer' -ListItemText '\\Computer' -ResultType 'ParameterValue' -ToolTip 'Remote computer name in \\Computer form.'
        )
    }

    @(
        New-PsServiceCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip 'Remote computer name in \\Computer form.'
    )
}

function Get-PsServiceSwitchCompletions {
    param(
        [object[]]$Switches,
        [string]$CurrentWord
    )

    $results = @()
    foreach ($switchSpec in $Switches) {
        if (Test-PsServiceStartsWith -Value $switchSpec.Name -Prefix $CurrentWord) {
            $results += New-PsServiceCompletionResult -CompletionText $switchSpec.Name -ListItemText $switchSpec.Name -ResultType 'ParameterName' -ToolTip $switchSpec.Description
        }
    }

    $results
}

function Get-PsServiceCommandCompletions {
    param(
        [object[]]$Commands,
        [string]$CurrentWord
    )

    $results = @()
    foreach ($commandSpec in $Commands) {
        if (Test-PsServiceStartsWith -Value $commandSpec.Name -Prefix $CurrentWord) {
            $results += New-PsServiceCompletionResult -CompletionText $commandSpec.Name -ListItemText $commandSpec.Name -ResultType 'ParameterValue' -ToolTip $commandSpec.Description
        }
    }

    $results
}

function Get-PsServicePreambleContext {
    param([string[]]$ArgumentsBeforeCurrent)

    $args = @($ArgumentsBeforeCurrent)
    $index = 0
    $server = $null
    $pendingValueKind = $null
    $command = $null
    $commandArguments = @()
    $seenRootSwitches = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    if ($args.Count -gt 0 -and $args[0] -like '\\*') {
        $server = $args[0]
        $index++
    }

    while ($index -lt $args.Count) {
        $token = $args[$index]

        switch ($token.ToLowerInvariant()) {
            '-u' {
                if (($index + 1) -ge $args.Count) {
                    $pendingValueKind = 'Username'
                    $index = $args.Count
                    continue
                }

                $index += 2
                continue
            }
            '-p' {
                if (($index + 1) -ge $args.Count) {
                    $pendingValueKind = 'Password'
                    $index = $args.Count
                    continue
                }

                $index += 2
                continue
            }
            '-?' {
                [void]$seenRootSwitches.Add($token)
                $index++
                continue
            }
            '/?' {
                [void]$seenRootSwitches.Add($token)
                $index++
                continue
            }
            '-nobanner' {
                [void]$seenRootSwitches.Add($token)
                $index++
                continue
            }
            default {
                $command = $token
                if (($index + 1) -lt $args.Count) {
                    $commandArguments = @($args | Select-Object -Skip ($index + 1))
                }
                $index = $args.Count
            }
        }
    }

    [pscustomobject]@{
        Server            = $server
        PendingValueKind  = $pendingValueKind
        Command           = $command
        CommandKey        = if ($command) { $command.ToLowerInvariant() } else { $null }
        CommandArguments  = $commandArguments
        SeenRootSwitches  = @($seenRootSwitches)
    }
}

function Get-PsServiceQueryState {
    param([string[]]$ArgumentsBeforeCurrent)

    $positionals = New-Object System.Collections.Generic.List[string]
    $usedSwitches = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $pendingSwitch = $null

    foreach ($argument in $ArgumentsBeforeCurrent) {
        if ($pendingSwitch) {
            [void]$usedSwitches.Add($pendingSwitch)
            $pendingSwitch = $null
            continue
        }

        switch ($argument.ToLowerInvariant()) {
            '-g' {
                $pendingSwitch = '-g'
                continue
            }
            '-t' {
                $pendingSwitch = '-t'
                continue
            }
            '-s' {
                $pendingSwitch = '-s'
                continue
            }
            '-?' { continue }
            '/?' { continue }
            default {
                $positionals.Add($argument)
            }
        }
    }

    [pscustomobject]@{
        PendingSwitch = $pendingSwitch
        Positionals   = @($positionals)
        UsedSwitches  = @($usedSwitches)
    }
}

function Get-PsServiceUnusedSwitches {
    param(
        [object[]]$Switches,
        [string[]]$UsedNames
    )

    $used = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($usedName in $UsedNames) {
        [void]$used.Add($usedName)
    }

    @(
        foreach ($switchSpec in $Switches) {
            if (-not $used.Contains($switchSpec.Name)) {
                $switchSpec
            }
        }
    )
}

function Complete-PsServiceSingleServiceName {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent
    )

    if ($ArgumentsBeforeCurrent.Count -eq 0) {
        $results = @()
        $results += @(Get-PsServiceCombinedServiceCompletions -CurrentWord $CurrentWord)
        $results += @(Get-PsServiceSwitchCompletions -Switches $script:PsServiceCompletionCatalog.CommandSwitches -CurrentWord $CurrentWord)
        return @(Get-PsServiceUniqueCompletions -Results $results)
    }

    @()
}

function Complete-PsServiceQuery {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent
    )

    $state = Get-PsServiceQueryState -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent
    if ($state.PendingSwitch) {
        switch ($state.PendingSwitch) {
            '-t' {
                return @(Get-PsServiceStringValueCompletions -Values $script:PsServiceCompletionCatalog.QueryTypeValues -CurrentWord $CurrentWord -ToolTip 'Query type.')
            }
            '-s' {
                return @(Get-PsServiceStringValueCompletions -Values $script:PsServiceCompletionCatalog.QueryStateValues -CurrentWord $CurrentWord -ToolTip 'Query state.')
            }
            '-g' {
                return @(New-PsServiceLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<group>' -ToolTip 'Load-order group name.')
            }
        }
    }

    $availableSwitches = @(
        Get-PsServiceUnusedSwitches -Switches $script:PsServiceCompletionCatalog.QuerySwitches -UsedNames $state.UsedSwitches
    )

    $results = @()
    $results += @(Get-PsServiceSwitchCompletions -Switches $script:PsServiceCompletionCatalog.CommandSwitches -CurrentWord $CurrentWord)
    $results += @(Get-PsServiceSwitchCompletions -Switches $availableSwitches -CurrentWord $CurrentWord)

    if ($state.Positionals.Count -eq 0 -and -not (($CurrentWord -like '-*') -or ($CurrentWord -like '/*'))) {
        $results += @(Get-PsServiceCombinedServiceCompletions -CurrentWord $CurrentWord)
    }

    @(Get-PsServiceUniqueCompletions -Results $results)
}

function Complete-PsServiceSetConfig {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent
    )

    if ($ArgumentsBeforeCurrent.Count -eq 0) {
        $results = @()
        $results += @(Get-PsServiceCombinedServiceCompletions -CurrentWord $CurrentWord)
        $results += @(Get-PsServiceSwitchCompletions -Switches $script:PsServiceCompletionCatalog.CommandSwitches -CurrentWord $CurrentWord)
        return @(Get-PsServiceUniqueCompletions -Results $results)
    }

    if ($ArgumentsBeforeCurrent.Count -eq 1) {
        return @(Get-PsServiceStringValueCompletions -Values $script:PsServiceCompletionCatalog.StartTypeValues -CurrentWord $CurrentWord -ToolTip 'Service start type.')
    }

    @()
}

function Complete-PsServiceFind {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent
    )

    if ($ArgumentsBeforeCurrent.Count -eq 0) {
        $results = @()
        $results += @(Get-PsServiceCombinedServiceCompletions -CurrentWord $CurrentWord)
        $results += @(Get-PsServiceSwitchCompletions -Switches $script:PsServiceCompletionCatalog.CommandSwitches -CurrentWord $CurrentWord)
        return @(Get-PsServiceUniqueCompletions -Results $results)
    }

    if ($ArgumentsBeforeCurrent.Count -eq 1) {
        return @(Get-PsServiceStringValueCompletions -Values @('all') -CurrentWord $CurrentWord -ToolTip 'Search the entire network.')
    }

    @()
}

function Complete-PsServiceByCommand {
    param(
        [string]$CommandKey,
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent
    )

    switch ($CommandKey) {
        'query' { return @(Complete-PsServiceQuery -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'config' { return @(Complete-PsServiceSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'security' { return @(Complete-PsServiceSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'setconfig' { return @(Complete-PsServiceSetConfig -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'start' { return @(Complete-PsServiceSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'stop' { return @(Complete-PsServiceSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'restart' { return @(Complete-PsServiceSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'pause' { return @(Complete-PsServiceSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'cont' { return @(Complete-PsServiceSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'depend' { return @(Complete-PsServiceSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'find' { return @(Complete-PsServiceFind -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
    }

    @()
}

function Complete-PsService {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if (-not (Test-PsServiceCommandAvailable)) {
        return @()
    }

    $tokenState = Get-PsServiceCurrentTokenState -Line $commandAst.Extent.Text -CursorPosition $cursorPosition
    if ([string]::IsNullOrEmpty($wordToComplete) -and $cursorPosition -gt $commandAst.Extent.EndOffset) {
        $allTokens = @($tokenState.TokensBeforeCurrent)
        if (-not [string]::IsNullOrEmpty($tokenState.CurrentToken)) {
            $allTokens += $tokenState.CurrentToken
        }

        $tokenState = [pscustomobject]@{
            TokensBeforeCurrent = $allTokens
            CurrentToken        = ''
            HasTrailingSpace    = $true
        }
    } elseif (-not [string]::IsNullOrEmpty($wordToComplete)) {
        $tokenState = [pscustomobject]@{
            TokensBeforeCurrent = $tokenState.TokensBeforeCurrent
            CurrentToken        = $wordToComplete
            HasTrailingSpace    = $tokenState.HasTrailingSpace
        }
    }

    $argumentState = Get-PsServiceArgumentsFromTokenState -TokenState $tokenState
    $preambleContext = Get-PsServicePreambleContext -ArgumentsBeforeCurrent $argumentState.ArgumentsBeforeCurrent
    $currentWord = $argumentState.CurrentWord

    if ($preambleContext.PendingValueKind) {
        switch ($preambleContext.PendingValueKind) {
            'Username' { return @(New-PsServiceLiteralValueResults -CurrentValue $currentWord -Placeholder '<username>' -ToolTip 'Username for the remote-auth preamble.') }
            'Password' { return @(New-PsServiceLiteralValueResults -CurrentValue $currentWord -Placeholder '<password>' -ToolTip 'Password for the remote-auth preamble.') }
        }
    }

    if (-not $preambleContext.Command) {
        $results = @()
        $results += @(Get-PsServiceSwitchCompletions -Switches $script:PsServiceCompletionCatalog.RootSwitches -CurrentWord $currentWord)
        $results += @(Get-PsServiceCommandCompletions -Commands $script:PsServiceCompletionCatalog.TopLevelCommands -CurrentWord $currentWord)

        if (($null -eq $preambleContext.Server) -and ([string]::IsNullOrWhiteSpace($currentWord) -or ($currentWord -like '\\*'))) {
            $results += @(Get-PsServiceServerPlaceholderCompletions -CurrentWord $currentWord)
        }

        return @(Get-PsServiceUniqueCompletions -Results $results)
    }

    $knownCommand = $false
    foreach ($command in $script:PsServiceCompletionCatalog.TopLevelCommands) {
        if ($command.Name.Equals($preambleContext.Command, [System.StringComparison]::OrdinalIgnoreCase)) {
            $knownCommand = $true
            break
        }
    }

    if (-not $knownCommand) {
        return @(Get-PsServiceCommandCompletions -Commands $script:PsServiceCompletionCatalog.TopLevelCommands -CurrentWord $currentWord)
    }

    @(Get-PsServiceUniqueCompletions -Results (Complete-PsServiceByCommand -CommandKey $preambleContext.CommandKey -CurrentWord $currentWord -ArgumentsBeforeCurrent $preambleContext.CommandArguments))
}

Register-ArgumentCompleter -Native -CommandName 'psservice', 'psservice.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-PsService -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
