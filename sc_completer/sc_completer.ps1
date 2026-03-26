# sc.exe tab completion for PowerShell
# Builds a help-seeded command catalog and value-aware completion for sc.exe.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name ScCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ScCompletionCatalog = @{
        Initialized          = $false
        CommandName          = $null
        TopLevelCommands     = @()
        CommandInfoByKey     = @{}
        BufferSizeHints      = @('256', '1024', '4096', '8192', '16384')
        NodeNumberHints      = @('0', '1', '2', '3', '4', '5', '6', '7')
        FailureFlagHints     = @('0', '1')
        ManagedBoolHints     = @('true', 'false')
        SidTypeHints         = @('none', 'unrestricted', 'restricted')
        BootHints            = @('bad', 'ok')
        ControlHints         = @('paramchange', 'netbindadd', 'netbindremove', 'netbindenable', 'netbinddisable')
        StopReasonHints      = @('0:0:0', '1:0:0')
        FailureActionHints   = @('run/5000', 'restart/5000', 'reboot/60000')
        FailureResetHints    = @('0', '60', '300', '3600', 'INFINITE')
        TriggerTemplates     = @(
            'start/device/UUID/HwId1/...'
            'start/custom/UUID/data0/...'
            'stop/custom/UUID/data0/...'
            'start/strcustom/UUID/data0/...'
            'stop/strcustom/UUID/data0/...'
            'start/lvlcustom/UUID/data0/...'
            'stop/lvlcustom/UUID/data0/...'
            'start/kwanycustom/UUID/data0/...'
            'stop/kwanycustom/UUID/data0/...'
            'start/kwallcustom/UUID/data0/...'
            'stop/kwallcustom/UUID/data0/...'
            'start/networkon'
            'stop/networkoff'
            'start/domainjoin'
            'stop/domainleave'
            'start/portopen/parameter'
            'stop/portclose/parameter'
            'start/machinepolicy'
            'start/userpolicy'
            'start/rpcinterface/UUID'
            'start/namedpipe/pipename'
            'delete'
        )
        QueryOptions         = @()
        CreateOptions        = @()
        ConfigOptions        = @()
        FailureOptions       = @()
    }
}

if (-not (Get-Variable -Name ScServiceCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ScServiceCache = @{
        LastUpdated  = [datetime]::MinValue
        TtlSeconds   = 30
        ServiceNames = @()
        DisplayNames = @()
    }
}

function Resolve-ScCommandName {
    if ($script:ScCompletionCatalog.CommandName) {
        return $script:ScCompletionCatalog.CommandName
    }

    $command = Get-Command -Name 'sc.exe', 'sc' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $script:ScCompletionCatalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $script:ScCompletionCatalog.CommandName
}

function Test-ScCommandAvailable {
    [bool](Resolve-ScCommandName)
}

function Invoke-ScHelpText {
    param([string[]]$Arguments)

    $commandName = Resolve-ScCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>$null)
    } catch {
        @()
    }
}

function New-ScCompletionResult {
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

function New-ScLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$ToolTip,
        [string]$Placeholder = '<value>'
    )

    if ([string]::IsNullOrEmpty($CurrentValue)) {
        return @(
            New-ScCompletionResult -CompletionText ' ' -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-ScCompletionResult -CompletionText $CurrentValue -ListItemText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-ScStaticCommandSpecs {
    $specs = @(
        @{ Name = 'query'; Description = 'Queries the status for a service, or enumerates the status for types of services.' }
        @{ Name = 'queryex'; Description = 'Queries the extended status for a service, or enumerates the status for types of services.' }
        @{ Name = 'start'; Description = 'Starts a service.' }
        @{ Name = 'pause'; Description = 'Sends a PAUSE control request to a service.' }
        @{ Name = 'interrogate'; Description = 'Sends an INTERROGATE control request to a service.' }
        @{ Name = 'continue'; Description = 'Sends a CONTINUE control request to a service.' }
        @{ Name = 'stop'; Description = 'Sends a STOP request to a service.' }
        @{ Name = 'config'; Description = 'Changes the configuration of a service (persistent).' }
        @{ Name = 'description'; Description = 'Changes the description of a service.' }
        @{ Name = 'failure'; Description = 'Changes the actions taken by a service upon failure.' }
        @{ Name = 'failureflag'; Description = 'Changes the failure actions flag of a service.' }
        @{ Name = 'sidtype'; Description = 'Changes the service SID type of a service.' }
        @{ Name = 'privs'; Description = 'Changes the required privileges of a service.' }
        @{ Name = 'managedaccount'; Description = 'Changes whether the service account password is managed by LSA.' }
        @{ Name = 'qc'; Description = 'Queries the configuration information for a service.' }
        @{ Name = 'qdescription'; Description = 'Queries the description for a service.' }
        @{ Name = 'qfailure'; Description = 'Queries the actions taken by a service upon failure.' }
        @{ Name = 'qfailureflag'; Description = 'Queries the failure actions flag of a service.' }
        @{ Name = 'qsidtype'; Description = 'Queries the service SID type of a service.' }
        @{ Name = 'qprivs'; Description = 'Queries the required privileges of a service.' }
        @{ Name = 'qtriggerinfo'; Description = 'Queries the trigger parameters of a service.' }
        @{ Name = 'qpreferrednode'; Description = 'Queries the preferred NUMA node of a service.' }
        @{ Name = 'qmanagedaccount'; Description = 'Queries whether a service uses an account with a password managed by LSA.' }
        @{ Name = 'qprotection'; Description = 'Queries the process protection level of a service.' }
        @{ Name = 'quserservice'; Description = 'Queries for a local instance of a user service template.' }
        @{ Name = 'delete'; Description = 'Deletes a service.' }
        @{ Name = 'create'; Description = 'Creates a service.' }
        @{ Name = 'control'; Description = 'Sends a control to a service.' }
        @{ Name = 'sdshow'; Description = 'Displays a service security descriptor.' }
        @{ Name = 'sdset'; Description = 'Sets a service security descriptor.' }
        @{ Name = 'showsid'; Description = 'Displays the service SID string corresponding to an arbitrary name.' }
        @{ Name = 'triggerinfo'; Description = 'Configures the trigger parameters of a service.' }
        @{ Name = 'preferrednode'; Description = 'Sets the preferred NUMA node of a service.' }
        @{ Name = 'GetDisplayName'; Description = 'Gets the DisplayName for a service.' }
        @{ Name = 'GetKeyName'; Description = 'Gets the ServiceKeyName for a service.' }
        @{ Name = 'EnumDepend'; Description = 'Enumerates service dependencies.' }
        @{ Name = 'boot'; Description = 'Sets whether the last boot is treated as bad or ok.' }
        @{ Name = 'Lock'; Description = 'Locks the Service Database.' }
        @{ Name = 'QueryLock'; Description = 'Queries the lock status for the Service Control Manager database.' }
    )

    @(
        foreach ($spec in $specs) {
            [pscustomobject]$spec
        }
    )
}

function Get-ScStaticQueryOptions {
    @(
        [pscustomobject]@{ Key = 'type='; CanonicalToken = 'type= '; Description = 'Type of services to enumerate.'; ValueKind = 'QueryType' }
        [pscustomobject]@{ Key = 'state='; CanonicalToken = 'state= '; Description = 'State of services to enumerate.'; ValueKind = 'QueryState' }
        [pscustomobject]@{ Key = 'bufsize='; CanonicalToken = 'bufsize= '; Description = 'Enumeration buffer size in bytes.'; ValueKind = 'BufferSize' }
        [pscustomobject]@{ Key = 'ri='; CanonicalToken = 'ri= '; Description = 'Resume index number.'; ValueKind = 'ResumeIndex' }
        [pscustomobject]@{ Key = 'group='; CanonicalToken = 'group= '; Description = 'Service group to enumerate.'; ValueKind = 'FreeText' }
    )
}

function Get-ScStaticConfigOptions {
    param([bool]$IncludeAdapt)

    $typeValues = @('own', 'share', 'interact', 'kernel', 'filesys', 'rec', 'userown', 'usershare')
    if ($IncludeAdapt) {
        $typeValues = @('own', 'share', 'interact', 'kernel', 'filesys', 'rec', 'adapt', 'userown', 'usershare')
    }

    @(
        [pscustomobject]@{ Key = 'type='; CanonicalToken = 'type= '; Description = 'Service type.'; ValueKind = 'StaticList'; Values = $typeValues }
        [pscustomobject]@{ Key = 'start='; CanonicalToken = 'start= '; Description = 'Service start mode.'; ValueKind = 'StaticList'; Values = @('boot', 'system', 'auto', 'demand', 'disabled', 'delayed-auto') }
        [pscustomobject]@{ Key = 'error='; CanonicalToken = 'error= '; Description = 'Error severity.'; ValueKind = 'StaticList'; Values = @('normal', 'severe', 'critical', 'ignore') }
        [pscustomobject]@{ Key = 'binpath='; CanonicalToken = 'binPath= '; Description = 'Binary path for the service executable.'; ValueKind = 'FreeText'; Placeholder = '<binary path>' }
        [pscustomobject]@{ Key = 'group='; CanonicalToken = 'group= '; Description = 'Load order group.'; ValueKind = 'FreeText'; Placeholder = '<load order group>' }
        [pscustomobject]@{ Key = 'tag='; CanonicalToken = 'tag= '; Description = 'Whether to obtain a TagID.'; ValueKind = 'StaticList'; Values = @('yes', 'no') }
        [pscustomobject]@{ Key = 'depend='; CanonicalToken = 'depend= '; Description = 'Dependencies separated by forward slashes.'; ValueKind = 'FreeText'; Placeholder = '<dependency1/dependency2>' }
        [pscustomobject]@{ Key = 'obj='; CanonicalToken = 'obj= '; Description = 'Account name or object name.'; ValueKind = 'FreeText'; Placeholder = '<account name>' }
        [pscustomobject]@{ Key = 'displayname='; CanonicalToken = 'DisplayName= '; Description = 'Display name.'; ValueKind = 'FreeText'; Placeholder = '<display name>' }
        [pscustomobject]@{ Key = 'password='; CanonicalToken = 'password= '; Description = 'Account password.'; ValueKind = 'FreeText'; Placeholder = '<password>' }
    )
}

function Get-ScStaticFailureOptions {
    @(
        [pscustomobject]@{ Key = 'reset='; CanonicalToken = 'reset= '; Description = 'Length of period after which to reset the failure count.'; ValueKind = 'FailureReset' }
        [pscustomobject]@{ Key = 'reboot='; CanonicalToken = 'reboot= '; Description = 'Message broadcast before rebooting on failure.'; ValueKind = 'FreeText'; Placeholder = '<reboot message>' }
        [pscustomobject]@{ Key = 'command='; CanonicalToken = 'command= '; Description = 'Command line to run on failure.'; ValueKind = 'FreeText'; Placeholder = '<command line>' }
        [pscustomobject]@{ Key = 'actions='; CanonicalToken = 'actions= '; Description = 'Failure actions with delay times separated by forward slashes.'; ValueKind = 'FailureActions' }
    )
}

function Initialize-ScCompletionCatalog {
    if ($script:ScCompletionCatalog.Initialized) {
        return
    }

    $commandInfoByKey = @{}
    foreach ($commandSpec in (Get-ScStaticCommandSpecs)) {
        $commandInfoByKey[$commandSpec.Name.ToLowerInvariant()] = $commandSpec
    }

    $helpLines = Invoke-ScHelpText
    $orderedKeys = New-Object System.Collections.Generic.List[string]
    $currentKey = $null

    foreach ($line in $helpLines) {
        $match = [regex]::Match($line, '^\s+(?<name>[A-Za-z][A-Za-z0-9]*?)-+(?<description>\S.*)$')
        if ($match.Success) {
            $commandName = $match.Groups['name'].Value
            $currentKey = $commandName.ToLowerInvariant()

            if ($commandInfoByKey.ContainsKey($currentKey)) {
                $commandInfoByKey[$currentKey] = [pscustomobject]@{
                    Name        = $commandInfoByKey[$currentKey].Name
                    Description = $match.Groups['description'].Value.Trim()
                }
            } else {
                $commandInfoByKey[$currentKey] = [pscustomobject]@{
                    Name        = $commandName
                    Description = $match.Groups['description'].Value.Trim()
                }
            }

            if (-not $orderedKeys.Contains($currentKey)) {
                $orderedKeys.Add($currentKey)
            }

            continue
        }

        if ($currentKey -and $line -match '^\s{20,}(?<continuation>\S.*)$') {
            $currentInfo = $commandInfoByKey[$currentKey]
            $commandInfoByKey[$currentKey] = [pscustomobject]@{
                Name        = $currentInfo.Name
                Description = ($currentInfo.Description + ' ' + $matches['continuation'].Trim())
            }

            continue
        }

        $currentKey = $null
    }

    if ($orderedKeys.Count -eq 0) {
        foreach ($entry in $commandInfoByKey.GetEnumerator() | Sort-Object { $_.Value.Name }) {
            $orderedKeys.Add($entry.Key)
        }
    }

    $script:ScCompletionCatalog.TopLevelCommands = @(
        foreach ($key in $orderedKeys) {
            $commandInfoByKey[$key]
        }
    )
    $script:ScCompletionCatalog.CommandInfoByKey = $commandInfoByKey
    $script:ScCompletionCatalog.QueryOptions = @(Get-ScStaticQueryOptions)
    $script:ScCompletionCatalog.ConfigOptions = @(Get-ScStaticConfigOptions -IncludeAdapt $true)
    $script:ScCompletionCatalog.CreateOptions = @(Get-ScStaticConfigOptions -IncludeAdapt $false)
    $script:ScCompletionCatalog.FailureOptions = @(Get-ScStaticFailureOptions)
    $script:ScCompletionCatalog.Initialized = $true
}

function Update-ScServiceCache {
    $age = (Get-Date) - $script:ScServiceCache.LastUpdated
    if ($script:ScServiceCache.ServiceNames.Count -gt 0 -and $age.TotalSeconds -lt $script:ScServiceCache.TtlSeconds) {
        return
    }

    try {
        $services = @(Get-Service -ErrorAction Stop | Sort-Object -Property Name)
        $script:ScServiceCache.ServiceNames = @(
            $services |
                Select-Object -ExpandProperty Name |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        $script:ScServiceCache.DisplayNames = @(
            $services |
                Select-Object -ExpandProperty DisplayName |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        $script:ScServiceCache.LastUpdated = Get-Date
    } catch {
        if (-not $script:ScServiceCache.ServiceNames) {
            $script:ScServiceCache.ServiceNames = @()
        }
        if (-not $script:ScServiceCache.DisplayNames) {
            $script:ScServiceCache.DisplayNames = @()
        }
    }
}

function Get-ScCurrentTokenState {
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
        if (($character -eq [char]34 -or $character -eq [char]39)) {
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

function Get-ScArgumentsFromTokenState {
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

function Get-ScCommandContext {
    param([string[]]$ArgumentsBeforeCurrent)

    $args = @($ArgumentsBeforeCurrent)
    $server = $null
    if ($args.Count -gt 0 -and $args[0] -like '\\*') {
        $server = $args[0]
        if ($args.Count -gt 1) {
            $args = @($args | Select-Object -Skip 1)
        } else {
            $args = @()
        }
    }

    $command = $null
    $commandKey = $null
    $commandArguments = @()
    if ($args.Count -gt 0) {
        $command = $args[0]
        $commandKey = $command.ToLowerInvariant()
        if ($args.Count -gt 1) {
            $commandArguments = @($args | Select-Object -Skip 1)
        }
    }

    [pscustomobject]@{
        Server           = $server
        Command          = $command
        CommandKey       = $commandKey
        CommandArguments = $commandArguments
    }
}

function Get-ScUniqueCompletions {
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

function Test-ScStartsWith {
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

function Get-ScCommandCompletions {
    param([string]$CurrentWord)

    $results = @()
    foreach ($command in $script:ScCompletionCatalog.TopLevelCommands) {
        if (Test-ScStartsWith -Value $command.Name -Prefix $CurrentWord) {
            $results += New-ScCompletionResult -CompletionText $command.Name -ListItemText $command.Name -ResultType 'ParameterValue' -ToolTip $command.Description
        }
    }

    $results
}

function Get-ScServerPlaceholderCompletions {
    param([string]$CurrentWord)

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        return @(
            New-ScCompletionResult -CompletionText '\\ServerName' -ListItemText '\\ServerName' -ResultType 'ParameterValue' -ToolTip 'Remote server name in \\ServerName form.'
        )
    }

    if ('\\ServerName'.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
        return @(
            New-ScCompletionResult -CompletionText '\\ServerName' -ListItemText '\\ServerName' -ResultType 'ParameterValue' -ToolTip 'Remote server name in \\ServerName form.'
        )
    }

    @(
        New-ScCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip 'Remote server name in \\ServerName form.'
    )
}

function Get-ScStringValueCompletions {
    param(
        [string[]]$Values,
        [string]$CurrentWord,
        [string]$ToolTip,
        [string]$Prefix = '',
        [bool]$QuoteWhitespace = $false
    )

    $matchPrefix = $CurrentWord
    if ($matchPrefix.Length -gt 0 -and ($matchPrefix[0] -eq [char]34 -or $matchPrefix[0] -eq [char]39)) {
        $matchPrefix = $matchPrefix.Substring(1)
    }

    $results = @()
    foreach ($value in ($Values | Sort-Object -Unique)) {
        if (Test-ScStartsWith -Value $value -Prefix $matchPrefix) {
            $completionText = $value
            if ($QuoteWhitespace -and ($value -match '\s' -or ($CurrentWord.Length -gt 0 -and ($CurrentWord[0] -eq [char]34 -or $CurrentWord[0] -eq [char]39)))) {
                $quoteCharacter = if ($CurrentWord.Length -gt 0 -and $CurrentWord[0] -eq [char]34) { '"' } else { "'" }
                $escapedValue = if ($quoteCharacter -eq "'") {
                    $value -replace "'", "''"
                } else {
                    $value -replace '"', '`"'
                }

                $completionText = '{0}{1}{0}' -f $quoteCharacter, $escapedValue
            }

            $results += New-ScCompletionResult -CompletionText ($Prefix + $completionText) -ListItemText $value -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }

    $results
}

function Get-ScServiceNameCompletions {
    param([string]$CurrentWord)

    Update-ScServiceCache
    Get-ScStringValueCompletions -Values $script:ScServiceCache.ServiceNames -CurrentWord $CurrentWord -ToolTip 'Local service name.' -QuoteWhitespace $true
}

function Get-ScDisplayNameCompletions {
    param([string]$CurrentWord)

    Update-ScServiceCache
    Get-ScStringValueCompletions -Values $script:ScServiceCache.DisplayNames -CurrentWord $CurrentWord -ToolTip 'Local service display name.' -QuoteWhitespace $true
}

function Get-ScCombinedNameCompletions {
    param([string]$CurrentWord)

    $results = @()
    $results += @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
    $results += @(Get-ScDisplayNameCompletions -CurrentWord $CurrentWord)
    Get-ScUniqueCompletions -Results $results
}

function Get-ScNumericCompletions {
    param(
        [string[]]$Hints,
        [string]$CurrentWord,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    Get-ScStringValueCompletions -Values $Hints -CurrentWord $CurrentWord -ToolTip $ToolTip -Prefix $Prefix
}

function Get-ScOptionKeyFromToken {
    param(
        [string]$Token,
        [bool]$AllowInlineValue = $true
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $match = [regex]::Match($Token, '^(?<name>[A-Za-z][A-Za-z0-9]*=)(?<value>.*)$')
    if (-not $match.Success) {
        return $null
    }

    $valuePortion = $match.Groups['value'].Value
    if (-not $AllowInlineValue -and -not [string]::IsNullOrEmpty($valuePortion)) {
        return $null
    }

    $match.Groups['name'].Value.ToLowerInvariant()
}

function Get-ScTagArgumentState {
    param(
        [string[]]$Arguments,
        [object[]]$OptionMetadata
    )

    $optionMap = @{}
    foreach ($option in $OptionMetadata) {
        $optionMap[$option.Key.ToLowerInvariant()] = $option
    }

    $pendingKey = $null
    $positionals = New-Object System.Collections.Generic.List[string]
    $optionCounts = @{}

    foreach ($argument in $Arguments) {
        if ($pendingKey) {
            $pendingKey = $null
            continue
        }

        $inlineKey = Get-ScOptionKeyFromToken -Token $argument -AllowInlineValue $true
        if ($inlineKey -and $optionMap.ContainsKey($inlineKey)) {
            if (-not $optionCounts.ContainsKey($inlineKey)) {
                $optionCounts[$inlineKey] = 0
            }

            $optionCounts[$inlineKey]++
            if ($argument.TrimEnd().Equals($inlineKey, [System.StringComparison]::OrdinalIgnoreCase)) {
                $pendingKey = $inlineKey
            }

            continue
        }

        $positionals.Add($argument)
    }

    [pscustomobject]@{
        PendingKey  = $pendingKey
        Positionals = @($positionals)
        OptionCounts = $optionCounts
        OptionMap   = $optionMap
    }
}

function Get-ScOptionMetadataByInlineToken {
    param(
        [string]$CurrentWord,
        [hashtable]$OptionMap
    )

    $key = Get-ScOptionKeyFromToken -Token $CurrentWord -AllowInlineValue $true
    if ($key -and $OptionMap.ContainsKey($key)) {
        return $OptionMap[$key]
    }

    $null
}

function Get-ScOptionTokenCompletions {
    param(
        [object[]]$OptionMetadata,
        [string]$CurrentWord
    )

    $results = @()
    foreach ($option in $OptionMetadata) {
        if (Test-ScStartsWith -Value $option.CanonicalToken -Prefix $CurrentWord) {
            $results += New-ScCompletionResult -CompletionText $option.CanonicalToken -ListItemText $option.CanonicalToken.TrimEnd() -ResultType 'ParameterName' -ToolTip $option.Description
        }
    }

    $results
}

function Get-ScQueryTypeValues {
    param([hashtable]$OptionCounts)

    $typeCount = 0
    if ($OptionCounts -and $OptionCounts.ContainsKey('type=')) {
        $typeCount = [int]$OptionCounts['type=']
    }

    if ($typeCount -ge 1) {
        return @('own', 'share', 'interact', 'kernel', 'filesys', 'rec', 'adapt')
    }

    @('driver', 'service', 'userservice', 'all')
}

function Get-ScOptionValueCompletions {
    param(
        [pscustomobject]$Option,
        [string]$CurrentWord,
        [hashtable]$OptionCounts,
        [string]$InlinePrefix = ''
    )

    $prefixWord = $CurrentWord
    if (-not [string]::IsNullOrEmpty($InlinePrefix)) {
        $prefixWord = $CurrentWord
    }

    switch ($Option.ValueKind) {
        'StaticList' {
            return @(Get-ScStringValueCompletions -Values $Option.Values -CurrentWord $prefixWord -ToolTip $Option.Description -Prefix $InlinePrefix)
        }
        'QueryType' {
            return @(Get-ScStringValueCompletions -Values (Get-ScQueryTypeValues -OptionCounts $OptionCounts) -CurrentWord $prefixWord -ToolTip $Option.Description -Prefix $InlinePrefix)
        }
        'QueryState' {
            return @(Get-ScStringValueCompletions -Values @('inactive', 'all') -CurrentWord $prefixWord -ToolTip $Option.Description -Prefix $InlinePrefix)
        }
        'BufferSize' {
            return @(Get-ScNumericCompletions -Hints $script:ScCompletionCatalog.BufferSizeHints -CurrentWord $prefixWord -ToolTip $Option.Description -Prefix $InlinePrefix)
        }
        'ResumeIndex' {
            return @(Get-ScNumericCompletions -Hints @('0', '10', '100', '1000') -CurrentWord $prefixWord -ToolTip $Option.Description -Prefix $InlinePrefix)
        }
        'FailureReset' {
            return @(Get-ScStringValueCompletions -Values $script:ScCompletionCatalog.FailureResetHints -CurrentWord $prefixWord -ToolTip $Option.Description -Prefix $InlinePrefix)
        }
        'FailureActions' {
            return @(Get-ScStringValueCompletions -Values $script:ScCompletionCatalog.FailureActionHints -CurrentWord $prefixWord -ToolTip $Option.Description -Prefix $InlinePrefix)
        }
        'FreeText' {
            $placeholder = if ($Option.PSObject.Properties.Name -contains 'Placeholder') { $Option.Placeholder } else { '<value>' }
            if ([string]::IsNullOrEmpty($InlinePrefix)) {
                return @(New-ScLiteralValueResults -CurrentValue $CurrentWord -Placeholder $placeholder -ToolTip $Option.Description)
            }

            if ([string]::IsNullOrEmpty($CurrentWord)) {
                return @(
                    New-ScCompletionResult -CompletionText $InlinePrefix -ListItemText $placeholder -ResultType 'ParameterValue' -ToolTip $Option.Description
                )
            }

            return @(
                New-ScCompletionResult -CompletionText ($InlinePrefix + $CurrentWord) -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip $Option.Description
            )
        }
    }

    @()
}

function Get-ScAdjustedOptionCounts {
    param(
        [hashtable]$OptionCounts,
        [string]$CurrentOptionKey
    )

    $adjusted = @{}
    if ($OptionCounts) {
        foreach ($entry in $OptionCounts.GetEnumerator()) {
            $adjusted[$entry.Key] = $entry.Value
        }
    }

    if ($CurrentOptionKey -and $adjusted.ContainsKey($CurrentOptionKey) -and [int]$adjusted[$CurrentOptionKey] -gt 0) {
        $adjusted[$CurrentOptionKey] = [int]$adjusted[$CurrentOptionKey] - 1
    }

    $adjusted
}

function Complete-ScTaggedCommand {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent,
        [object[]]$OptionMetadata,
        [string]$FirstPositionalKind,
        [string]$FirstPositionalToolTip,
        [string]$FirstPositionalPlaceholder
    )

    $state = Get-ScTagArgumentState -Arguments $ArgumentsBeforeCurrent -OptionMetadata $OptionMetadata
    if ($state.Positionals.Count -eq 0) {
        switch ($FirstPositionalKind) {
            'ServiceName' {
                return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
            }
            'Literal' {
                return @(New-ScLiteralValueResults -CurrentValue $CurrentWord -Placeholder $FirstPositionalPlaceholder -ToolTip $FirstPositionalToolTip)
            }
        }
    }

    if ($state.PendingKey) {
        return @(Get-ScOptionValueCompletions -Option $state.OptionMap[$state.PendingKey] -CurrentWord $CurrentWord -OptionCounts (Get-ScAdjustedOptionCounts -OptionCounts $state.OptionCounts -CurrentOptionKey $state.PendingKey))
    }

    $inlineOption = Get-ScOptionMetadataByInlineToken -CurrentWord $CurrentWord -OptionMap $state.OptionMap
    if ($inlineOption) {
        $inlineMatch = [regex]::Match($CurrentWord, '^(?<name>[A-Za-z][A-Za-z0-9]*=\s?)(?<value>.*)$')
        if ($inlineMatch.Success) {
            return @(Get-ScOptionValueCompletions -Option $inlineOption -CurrentWord $inlineMatch.Groups['value'].Value.TrimStart() -OptionCounts $state.OptionCounts -InlinePrefix $inlineOption.CanonicalToken)
        }
    }

    if ([string]::IsNullOrWhiteSpace($CurrentWord) -or $CurrentWord -match '^[A-Za-z]') {
        return @(Get-ScOptionTokenCompletions -OptionMetadata $OptionMetadata -CurrentWord $CurrentWord)
    }

    @()
}

function Complete-ScQueryLikeCommand {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent
    )

    $state = Get-ScTagArgumentState -Arguments $ArgumentsBeforeCurrent -OptionMetadata $script:ScCompletionCatalog.QueryOptions
    if ($state.PendingKey) {
        return @(Get-ScOptionValueCompletions -Option $state.OptionMap[$state.PendingKey] -CurrentWord $CurrentWord -OptionCounts (Get-ScAdjustedOptionCounts -OptionCounts $state.OptionCounts -CurrentOptionKey $state.PendingKey))
    }

    $inlineOption = Get-ScOptionMetadataByInlineToken -CurrentWord $CurrentWord -OptionMap $state.OptionMap
    if ($inlineOption) {
        $inlineMatch = [regex]::Match($CurrentWord, '^(?<name>[A-Za-z][A-Za-z0-9]*=\s?)(?<value>.*)$')
        if ($inlineMatch.Success) {
            return @(Get-ScOptionValueCompletions -Option $inlineOption -CurrentWord $inlineMatch.Groups['value'].Value.TrimStart() -OptionCounts $state.OptionCounts -InlinePrefix $inlineOption.CanonicalToken)
        }
    }

    if ($state.Positionals.Count -gt 0) {
        return @()
    }

    $results = @()
    $results += @(Get-ScOptionTokenCompletions -OptionMetadata $script:ScCompletionCatalog.QueryOptions -CurrentWord $CurrentWord)
    $results += @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
    Get-ScUniqueCompletions -Results $results
}

function Complete-ScServiceThenLiteral {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent,
        [string]$Placeholder,
        [string]$ToolTip
    )

    if ($ArgumentsBeforeCurrent.Count -eq 0) {
        return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
    }

    @(New-ScLiteralValueResults -CurrentValue $CurrentWord -Placeholder $Placeholder -ToolTip $ToolTip)
}

function Complete-ScServiceThenNumeric {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent,
        [string[]]$Hints,
        [string]$ToolTip
    )

    if ($ArgumentsBeforeCurrent.Count -eq 0) {
        return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
    }

    if ($ArgumentsBeforeCurrent.Count -eq 1) {
        return @(Get-ScNumericCompletions -Hints $Hints -CurrentWord $CurrentWord -ToolTip $ToolTip)
    }

    @()
}

function Complete-ScSingleServiceName {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent
    )

    if ($ArgumentsBeforeCurrent.Count -eq 0) {
        return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
    }

    @()
}

function Complete-ScStart {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent
    )

    if ($ArgumentsBeforeCurrent.Count -eq 0) {
        return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
    }

    @(New-ScLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<service argument>' -ToolTip 'Additional argument passed to the service start request.')
}

function Complete-ScStop {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent
    )

    if ($ArgumentsBeforeCurrent.Count -eq 0) {
        return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
    }

    if ($ArgumentsBeforeCurrent.Count -eq 1) {
        $results = @()
        $results += @(Get-ScStringValueCompletions -Values $script:ScCompletionCatalog.StopReasonHints -CurrentWord $CurrentWord -ToolTip 'Stop reason in flag:major:minor form.')
        $results += @(New-ScLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<flag:major:minor>' -ToolTip 'Stop reason in flag:major:minor form.')
        return @(Get-ScUniqueCompletions -Results $results)
    }

    @(New-ScLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<comment>' -ToolTip 'Optional stop comment.')
}

function Complete-ScControl {
    param(
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent
    )

    if ($ArgumentsBeforeCurrent.Count -eq 0) {
        return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
    }

    if ($ArgumentsBeforeCurrent.Count -eq 1) {
        $results = @()
        $results += @(Get-ScStringValueCompletions -Values $script:ScCompletionCatalog.ControlHints -CurrentWord $CurrentWord -ToolTip 'Named control value.')
        $results += @(Get-ScNumericCompletions -Hints @('128', '129', '130', '200') -CurrentWord $CurrentWord -ToolTip 'User-defined control code.')
        return @(Get-ScUniqueCompletions -Results $results)
    }

    @()
}

function Complete-ScValueOnly {
    param(
        [string]$CurrentWord,
        [string[]]$Values,
        [string]$ToolTip
    )

    Get-ScStringValueCompletions -Values $Values -CurrentWord $CurrentWord -ToolTip $ToolTip
}

function Complete-ScByCommand {
    param(
        [string]$CommandKey,
        [string]$CurrentWord,
        [string[]]$ArgumentsBeforeCurrent
    )

    switch ($CommandKey) {
        'query' { return @(Complete-ScQueryLikeCommand -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'queryex' { return @(Complete-ScQueryLikeCommand -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'start' { return @(Complete-ScStart -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'pause' { return @(Complete-ScSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'interrogate' { return @(Complete-ScSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'continue' { return @(Complete-ScSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'stop' { return @(Complete-ScStop -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'config' {
            return @(Complete-ScTaggedCommand -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -OptionMetadata $script:ScCompletionCatalog.ConfigOptions -FirstPositionalKind 'ServiceName' -FirstPositionalToolTip 'Service name.' -FirstPositionalPlaceholder '<service name>')
        }
        'create' {
            return @(Complete-ScTaggedCommand -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -OptionMetadata $script:ScCompletionCatalog.CreateOptions -FirstPositionalKind 'Literal' -FirstPositionalToolTip 'New service name.' -FirstPositionalPlaceholder '<service name>')
        }
        'description' { return @(Complete-ScServiceThenLiteral -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -Placeholder '<description>' -ToolTip 'Service description text.') }
        'failure' {
            return @(Complete-ScTaggedCommand -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -OptionMetadata $script:ScCompletionCatalog.FailureOptions -FirstPositionalKind 'ServiceName' -FirstPositionalToolTip 'Service name.' -FirstPositionalPlaceholder '<service name>')
        }
        'failureflag' {
            if ($ArgumentsBeforeCurrent.Count -eq 0) {
                return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
            }

            return @(Get-ScStringValueCompletions -Values $script:ScCompletionCatalog.FailureFlagHints -CurrentWord $CurrentWord -ToolTip 'Failure actions flag value.')
        }
        'sidtype' {
            if ($ArgumentsBeforeCurrent.Count -eq 0) {
                return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
            }

            return @(Get-ScStringValueCompletions -Values $script:ScCompletionCatalog.SidTypeHints -CurrentWord $CurrentWord -ToolTip 'Service SID type.')
        }
        'privs' { return @(Complete-ScServiceThenLiteral -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -Placeholder '<privilege list>' -ToolTip 'Required privileges separated by forward slashes.') }
        'managedaccount' {
            if ($ArgumentsBeforeCurrent.Count -eq 0) {
                return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
            }

            return @(Get-ScStringValueCompletions -Values $script:ScCompletionCatalog.ManagedBoolHints -CurrentWord $CurrentWord -ToolTip 'Whether the password is managed by LSA.')
        }
        'qc' { return @(Complete-ScServiceThenNumeric -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -Hints $script:ScCompletionCatalog.BufferSizeHints -ToolTip 'Optional buffer size.') }
        'qdescription' { return @(Complete-ScServiceThenNumeric -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -Hints $script:ScCompletionCatalog.BufferSizeHints -ToolTip 'Optional buffer size.') }
        'qfailure' { return @(Complete-ScServiceThenNumeric -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -Hints $script:ScCompletionCatalog.BufferSizeHints -ToolTip 'Optional buffer size.') }
        'qfailureflag' { return @(Complete-ScSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'qsidtype' { return @(Complete-ScSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'qprivs' { return @(Complete-ScServiceThenNumeric -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -Hints $script:ScCompletionCatalog.BufferSizeHints -ToolTip 'Optional buffer size.') }
        'qtriggerinfo' { return @(Complete-ScServiceThenNumeric -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -Hints $script:ScCompletionCatalog.BufferSizeHints -ToolTip 'Optional buffer size.') }
        'qpreferrednode' { return @(Complete-ScSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'qmanagedaccount' { return @(Complete-ScSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'qprotection' { return @(Complete-ScSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'quserservice' { return @(Complete-ScSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'delete' { return @(Complete-ScSingleServiceName -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'control' { return @(Complete-ScControl -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent) }
        'sdshow' { return @(Complete-ScServiceThenLiteral -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -Placeholder '<showrights>' -ToolTip 'showrights argument.') }
        'sdset' { return @(Complete-ScServiceThenLiteral -CurrentWord $CurrentWord -ArgumentsBeforeCurrent $ArgumentsBeforeCurrent -Placeholder '<SDDL>' -ToolTip 'Security descriptor in SDDL format.') }
        'showsid' { return @(Get-ScCombinedNameCompletions -CurrentWord $CurrentWord) }
        'triggerinfo' {
            if ($ArgumentsBeforeCurrent.Count -eq 0) {
                return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
            }

            return @(Get-ScStringValueCompletions -Values $script:ScCompletionCatalog.TriggerTemplates -CurrentWord $CurrentWord -ToolTip 'Trigger template from sc triggerinfo help.')
        }
        'preferrednode' {
            if ($ArgumentsBeforeCurrent.Count -eq 0) {
                return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
            }

            return @(Get-ScNumericCompletions -Hints $script:ScCompletionCatalog.NodeNumberHints -CurrentWord $CurrentWord -ToolTip 'Preferred NUMA node number.')
        }
        'getdisplayname' {
            if ($ArgumentsBeforeCurrent.Count -eq 0) {
                return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
            }

            return @(Get-ScNumericCompletions -Hints $script:ScCompletionCatalog.BufferSizeHints -CurrentWord $CurrentWord -ToolTip 'Buffer size.')
        }
        'getkeyname' {
            if ($ArgumentsBeforeCurrent.Count -eq 0) {
                return @(Get-ScDisplayNameCompletions -CurrentWord $CurrentWord)
            }

            return @(Get-ScNumericCompletions -Hints $script:ScCompletionCatalog.BufferSizeHints -CurrentWord $CurrentWord -ToolTip 'Buffer size.')
        }
        'enumdepend' {
            if ($ArgumentsBeforeCurrent.Count -eq 0) {
                return @(Get-ScServiceNameCompletions -CurrentWord $CurrentWord)
            }

            return @(Get-ScNumericCompletions -Hints $script:ScCompletionCatalog.BufferSizeHints -CurrentWord $CurrentWord -ToolTip 'Buffer size.')
        }
        'boot' { return @(Complete-ScValueOnly -CurrentWord $CurrentWord -Values $script:ScCompletionCatalog.BootHints -ToolTip 'Boot state value.') }
        'lock' { return @() }
        'querylock' { return @() }
    }

    @()
}

function Complete-Sc {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if (-not (Test-ScCommandAvailable)) {
        return @()
    }

    Initialize-ScCompletionCatalog

    $tokenState = Get-ScCurrentTokenState -Line $commandAst.Extent.Text -CursorPosition $cursorPosition
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

    $commandContext = Get-ScCommandContext -ArgumentsBeforeCurrent (Get-ScArgumentsFromTokenState -TokenState $tokenState).ArgumentsBeforeCurrent
    $currentWord = (Get-ScArgumentsFromTokenState -TokenState $tokenState).CurrentWord

    if (-not $commandContext.Command) {
        $results = @()
        $results += @(Get-ScCommandCompletions -CurrentWord $currentWord)

        if ($null -eq $commandContext.Server) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord -like '\\*') {
                $results += @(Get-ScServerPlaceholderCompletions -CurrentWord $currentWord)
            }
        }

        return @(Get-ScUniqueCompletions -Results $results)
    }

    if (-not $script:ScCompletionCatalog.CommandInfoByKey.ContainsKey($commandContext.CommandKey)) {
        return @(Get-ScCommandCompletions -CurrentWord $currentWord)
    }

    @(Get-ScUniqueCompletions -Results (Complete-ScByCommand -CommandKey $commandContext.CommandKey -CurrentWord $currentWord -ArgumentsBeforeCurrent $commandContext.CommandArguments))
}

Register-ArgumentCompleter -Native -CommandName 'sc', 'sc.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Sc -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
