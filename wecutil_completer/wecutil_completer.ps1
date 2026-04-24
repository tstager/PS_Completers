<#
.SYNOPSIS
    Registers a native PowerShell argument completer for wecutil.

.DESCRIPTION
    Provides a help-driven native completer for `wecutil` and `wecutil.exe`.

    The completer covers:
    - top-level command aliases and long names
    - slash-style `/option:value` completion parsed from command help
    - dynamic local subscription-name completion when enumeration succeeds
    - XML/path completion for config-file slots
    - enum and placeholder value completion for selected high-value option slots

    The script keeps its top level compatible with `Import-CompleterScript`.
#>

Set-StrictMode -Version 2.0

function New-WecutilCompletionResult {
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
        $ToolTip = $ListItemText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Remove-WecutilOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-WecutilQuotedValue {
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

function Get-WecutilTokenState {
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

function Get-WecutilArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    $tokensBeforeCurrent = @($TokenState.TokensBeforeCurrent)
    $currentArgument = if ($null -eq $TokenState.CurrentToken) { '' } else { $TokenState.CurrentToken }

    if ($tokensBeforeCurrent.Count -gt 0) {
        $argumentsBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip 1)
    } else {
        $argumentsBeforeCurrent = @()
    }

    if ($tokensBeforeCurrent.Count -eq 0 -and $currentArgument -match '^(?i)wecutil(?:\.exe)?$') {
        $currentArgument = ''
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = $argumentsBeforeCurrent
        CurrentArgument        = $currentArgument
    }
}

function Get-WecutilCatalog {
    if (Get-Variable -Name WecutilCompletionCatalog -Scope Script -ErrorAction SilentlyContinue) {
        return $script:WecutilCompletionCatalog
    }

    $commands = @(
        [pscustomobject]@{ Canonical='es'; Long='enum-subscription'; Description='List existing subscriptions.'; Positional='None' }
        [pscustomobject]@{ Canonical='gs'; Long='get-subscription'; Description='Get subscription configuration.'; Positional='SubscriptionId' }
        [pscustomobject]@{ Canonical='gr'; Long='get-subscriptionruntimestatus'; Description='Get subscription runtime status.'; Positional='SubscriptionThenEventSource' }
        [pscustomobject]@{ Canonical='ss'; Long='set-subscription'; Description='Set subscription configuration.'; Positional='SubscriptionIdOrConfig' }
        [pscustomobject]@{ Canonical='cs'; Long='create-subscription'; Description='Create a subscription from an XML config file.'; Positional='ConfigFile' }
        [pscustomobject]@{ Canonical='ds'; Long='delete-subscription'; Description='Delete a subscription.'; Positional='SubscriptionId' }
        [pscustomobject]@{ Canonical='rs'; Long='retry-subscription'; Description='Retry one or more event sources for a subscription.'; Positional='SubscriptionThenEventSource' }
        [pscustomobject]@{ Canonical='qc'; Long='quick-config'; Description='Configure the Windows Event Collector service.'; Positional='None' }
    )

    $aliasLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $commandSuggestions = New-Object System.Collections.Generic.List[object]
    foreach ($command in $commands) {
        $aliasLookup[$command.Canonical] = $command
        $aliasLookup[$command.Long] = $command
        [void]$commandSuggestions.Add([pscustomobject]@{ CompletionText = $command.Canonical; ToolTip = $command.Description })
        [void]$commandSuggestions.Add([pscustomobject]@{ CompletionText = $command.Long; ToolTip = $command.Description })
    }

    $script:WecutilCompletionCatalog = [pscustomobject]@{
        Commands            = $commands
        CommandLookup       = $aliasLookup
        CommandSuggestions  = @($commandSuggestions.ToArray())
        HelpTokens          = @('/?', '-?', '-h', '-help')
        FallbackOptions     = @{
            'es' = @()
            'gs' = @('/f:', '/format:', '/u:', '/unicode:')
            'gr' = @('/PurgeInactiveES:')
            'ss' = @('/c:', '/config:', '/e', '/e:', '/enabled', '/enabled:', '/d:', '/description:', '/ex:', '/expires:', '/uri:', '/cm:', '/configurationmode:', '/q:', '/query:', '/dia:', '/dialect:', '/cf:', '/contentformat:', '/l:', '/locale:', '/ree', '/ree:', '/readexistingevents', '/readexistingevents:', '/lf:', '/logfile:', '/pn:', '/publishername:', '/dm:', '/deliverymode:', '/dmi:', '/deliverymaxitems:', '/dmlt:', '/deliverymaxlatencytime:', '/hi:', '/heartbeatinterval:', '/tn:', '/transportname:', '/esa:', '/eventsourceaddress:', '/ese', '/ese:', '/eventsourceenabled', '/eventsourceenabled:', '/un:', '/username:', '/up:', '/userpassword:', '/cun:', '/commonusername:', '/cup:', '/commonuserpassword:')
            'cs' = @('/cun:', '/commonusername:', '/cup:', '/commonuserpassword:')
            'ds' = @()
            'rs' = @()
            'qc' = @('/q', '/q:', '/quiet', '/quiet:')
        }
        EnumValues          = @{
            '/f:'                   = @('XML', 'Terse')
            '/format:'              = @('XML', 'Terse')
            '/u:'                   = @('true', 'false')
            '/unicode:'             = @('true', 'false')
            '/e:'                   = @('true', 'false')
            '/enabled:'             = @('true', 'false')
            '/cm:'                  = @('Normal', 'Custom', 'MinLatency', 'MinBandwidth')
            '/configurationmode:'   = @('Normal', 'Custom', 'MinLatency', 'MinBandwidth')
            '/cf:'                  = @('Events', 'RenderedText')
            '/contentformat:'       = @('Events', 'RenderedText')
            '/ree:'                 = @('true', 'false')
            '/readexistingevents:'  = @('true', 'false')
            '/dm:'                  = @('pull', 'push')
            '/deliverymode:'        = @('pull', 'push')
            '/tn:'                  = @('http', 'https')
            '/transportname:'       = @('http', 'https')
            '/ese:'                 = @('true', 'false')
            '/eventsourceenabled:'  = @('true', 'false')
            '/q:'                   = @('true', 'false')
            '/quiet:'               = @('true', 'false')
        }
        PathOptions         = @{
            '/c:'              = '.xml'
            '/config:'         = '.xml'
        }
        PlaceholderOptions  = @{
            '/d:'                    = '<description>'
            '/description:'          = '<description>'
            '/ex:'                   = '<iso8601-date>'
            '/expires:'              = '<iso8601-date>'
            '/uri:'                  = '<uri>'
            '/q:'                    = '<query>'
            '/query:'                = '<query>'
            '/dia:'                  = '<dialect>'
            '/dialect:'              = '<dialect>'
            '/l:'                    = '<locale>'
            '/locale:'               = '<locale>'
            '/lf:'                   = '<log-file>'
            '/logfile:'              = '<log-file>'
            '/pn:'                   = '<publisher-name>'
            '/publishername:'        = '<publisher-name>'
            '/dmi:'                  = '<number>'
            '/deliverymaxitems:'     = '<number>'
            '/dmlt:'                 = '<milliseconds>'
            '/deliverymaxlatencytime:' = '<milliseconds>'
            '/hi:'                   = '<milliseconds>'
            '/heartbeatinterval:'    = '<milliseconds>'
            '/esa:'                  = '<event-source>'
            '/eventsourceaddress:'   = '<event-source>'
            '/un:'                   = '<username>'
            '/username:'             = '<username>'
            '/up:'                   = '<password>'
            '/userpassword:'         = '<password>'
            '/cun:'                  = '<username>'
            '/commonusername:'       = '<username>'
            '/cup:'                  = '<password>'
            '/commonuserpassword:'   = '<password>'
            '/purgeinactivees:'      = '<days>'
        }
    }

    $script:WecutilCompletionCatalog
}

function Invoke-WecutilCommandHelp {
    param([string]$CommandName)

    if (-not (Get-Command -Name wecutil.exe -ErrorAction SilentlyContinue)) {
        return @()
    }

    try {
        @(& wecutil.exe $CommandName '-?' 2>&1)
    } catch {
        @()
    }
}

function ConvertFrom-WecutilOptionSpec {
    param(
        [string]$Spec,
        [string]$LongName,
        [string]$Description
    )

    $spec = $Spec.Trim()
    if ([string]::IsNullOrWhiteSpace($spec)) {
        return @()
    }

    $tokens = New-Object System.Collections.Generic.List[object]
    foreach ($part in @($spec -split '\|')) {
        $cleanPart = $part.Trim()
        if ([string]::IsNullOrWhiteSpace($cleanPart)) {
            continue
        }

        if ($cleanPart -eq '?') {
            continue
        }

        $completionTokens = New-Object System.Collections.Generic.List[string]
        if ($cleanPart -match '^(?<name>[^\[]+)\[:') {
            $root = '/' + $matches['name']
            $completionTokens.Add($root)
            $completionTokens.Add($root + ':')
        } elseif ($cleanPart.Contains(':')) {
            $root = '/' + $cleanPart.Split(':', 2)[0]
            $completionTokens.Add($root + ':')
        } else {
            $completionTokens.Add('/' + $cleanPart)
        }

        if (-not [string]::IsNullOrWhiteSpace($LongName)) {
            $longRoot = '/' + $LongName.Trim()
            if ($cleanPart -match '\[:' -or $cleanPart.Contains(':')) {
                if ($cleanPart -match '\[:') {
                    $completionTokens.Add($longRoot)
                }
                $completionTokens.Add($longRoot + ':')
            } else {
                $completionTokens.Add($longRoot)
            }
        }

        foreach ($token in @($completionTokens | Select-Object -Unique)) {
            $tokens.Add([pscustomobject]@{
                Token       = $token
                Description = $Description
            })
        }
    }

    @($tokens.ToArray())
}

function Get-WecutilParsedOptionsForCommand {
    param([string]$CanonicalCommand)

    $cacheName = 'WecutilParsedOptionCache'
    if (-not (Get-Variable -Name $cacheName -Scope Script -ErrorAction SilentlyContinue)) {
        $script:WecutilParsedOptionCache = @{}
    }

    if ($script:WecutilParsedOptionCache.ContainsKey($CanonicalCommand)) {
        return $script:WecutilParsedOptionCache[$CanonicalCommand]
    }

    $catalog = Get-WecutilCatalog
    $options = New-Object System.Collections.Generic.List[object]
    $helpLines = Invoke-WecutilCommandHelp -CommandName $CanonicalCommand
    $currentDescription = $null

    foreach ($line in @($helpLines)) {
        $text = [string]$line
        $match = [regex]::Match($text, '^\s*/(?<spec>[^\s]+)\s*(?:\((?<long>[^)]+)\))?\s*(?<rest>.*)$')
        if ($match.Success) {
            $spec = $match.Groups['spec'].Value
            $longName = $match.Groups['long'].Value
            $description = $match.Groups['rest'].Value.Trim()
            if ([string]::IsNullOrWhiteSpace($description)) {
                $description = $spec
            }

            foreach ($parsed in @(ConvertFrom-WecutilOptionSpec -Spec $spec -LongName $longName -Description $description)) {
                [void]$options.Add($parsed)
            }

            $currentDescription = $description
            continue
        }

        if ($currentDescription -and $text -match '^\s{2,}(?<continuation>\S.*)$') {
            continue
        }
    }

    if ($options.Count -eq 0) {
        foreach ($fallbackToken in @($catalog.FallbackOptions[$CanonicalCommand])) {
            [void]$options.Add([pscustomobject]@{ Token = $fallbackToken; Description = $fallbackToken })
        }
    }

    $unique = @($options | Group-Object Token | ForEach-Object { $_.Group[0] })
    $script:WecutilParsedOptionCache[$CanonicalCommand] = $unique
    @($unique)
}

function Get-WecutilCommandOptionLookup {
    param([string]$CanonicalCommand)

    $lookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($option in @(Get-WecutilParsedOptionsForCommand -CanonicalCommand $CanonicalCommand)) {
        $lookup[$option.Token] = $option
    }

    $lookup
}

function Get-WecutilSubscriptionNames {
    if (Get-Variable -Name WecutilSubscriptionCache -Scope Script -ErrorAction SilentlyContinue) {
        $cache = $script:WecutilSubscriptionCache
        if (((Get-Date) - $cache.UpdatedAt).TotalSeconds -lt 15) {
            return $cache.Values
        }
    }

    $values = @()
    if (Get-Command -Name wecutil.exe -ErrorAction SilentlyContinue) {
        try {
            $lines = @(& wecutil.exe es 2>$null)
            $values = @(
                $lines |
                    ForEach-Object { ([string]$_).Replace([string][char]65279, '').Replace([string][char]0, '').Trim() } |
                    Where-Object { $_ -and $_ -match '[A-Za-z0-9]' -and $_ -notmatch '^Failed to open' -and $_ -notmatch '^The RPC server is unavailable' }
            ) | Sort-Object -Unique
        } catch {
            $values = @()
        }
    }

    $script:WecutilSubscriptionCache = [pscustomobject]@{ UpdatedAt = Get-Date; Values = $values }
    @($values)
}

function Get-WecutilCommandCompletions {
    param([string]$CurrentWord)

    foreach ($suggestion in (Get-WecutilCatalog).CommandSuggestions) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $suggestion.CompletionText.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        New-WecutilCompletionResult -CompletionText $suggestion.CompletionText -ResultType 'ParameterValue' -ToolTip $suggestion.ToolTip -ListItemText $suggestion.CompletionText
    }
}

function Get-WecutilHelpCompletions {
    param([string]$CurrentWord)

    foreach ($token in (Get-WecutilCatalog).HelpTokens) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $token.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        New-WecutilCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip 'Show wecutil help.' -ListItemText $token
    }
}

function Get-WecutilOptionCompletions {
    param(
        [string]$CanonicalCommand,
        [string]$CurrentWord
    )

    foreach ($option in @(Get-WecutilParsedOptionsForCommand -CanonicalCommand $CanonicalCommand)) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $option.Token.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        New-WecutilCompletionResult -CompletionText $option.Token -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $option.Token
    }
}

function Get-WecutilEnumCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$Values,
        [string]$Prefix,
        [string]$ToolTip
    )

    $typed = Remove-WecutilOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($value in @($Values)) {
        if (-not [string]::IsNullOrWhiteSpace($typed) -and -not $value.StartsWith($typed, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-WecutilCompletionResult -CompletionText ($Prefix + $value) -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText ($Prefix + $value)))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { $Prefix + '<value>' } else { $Prefix + $CurrentWord }
        [void]$results.Add((New-WecutilCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText $fallback))
    }

    @($results.ToArray())
}

function Get-WecutilPathCompletions {
    param(
        [string]$CurrentWord,
        [string]$Prefix,
        [string]$ToolTip,
        [string]$Placeholder,
        [ValidateSet('File','Directory','Any')]
        [string]$Kind = 'File'
    )

    $typedValue = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }
    $cleanValue = Remove-WecutilOuterQuotes -Value $typedValue
    $alwaysQuote = $typedValue.StartsWith('"')
    $results = New-Object System.Collections.Generic.List[object]

    $parentPath = '.'
    $leaf = ''
    if (-not [string]::IsNullOrWhiteSpace($cleanValue)) {
        if ($cleanValue.EndsWith('\') -or $cleanValue.EndsWith('/')) {
            $parentPath = $cleanValue
        } else {
            try {
                $candidateParent = Split-Path -Path $cleanValue -Parent
            } catch {
                $candidateParent = ''
            }

            if ([string]::IsNullOrWhiteSpace($candidateParent)) {
                $leaf = $cleanValue
            } else {
                $parentPath = $candidateParent
                try {
                    $leaf = Split-Path -Path $cleanValue -Leaf
                } catch {
                    $leaf = $cleanValue
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

        $completionText = ConvertTo-WecutilQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        [void]$results.Add((New-WecutilCompletionResult -CompletionText ($Prefix + $completionText) -ResultType 'ParameterValue' -ToolTip $item.FullName -ListItemText ($Prefix + $completionText)))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { $Prefix + $Placeholder } else { $Prefix + $CurrentWord }
        [void]$results.Add((New-WecutilCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText $fallback))
    }

    @($results.ToArray())
}

function Get-WecutilPlaceholderCompletions {
    param(
        [string]$CurrentWord,
        [string]$Prefix,
        [string]$Placeholder,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        return @(
            New-WecutilCompletionResult -CompletionText ($Prefix + $Placeholder) -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText ($Prefix + $Placeholder)
        )
    }

    @(
        New-WecutilCompletionResult -CompletionText ($Prefix + $CurrentWord) -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText ($Prefix + $CurrentWord)
    )
}

function Get-WecutilInlineOptionInfo {
    param(
        [string]$Token,
        [string]$CanonicalCommand
    )

    if ([string]::IsNullOrWhiteSpace($Token) -or -not $Token.StartsWith('/')) {
        return $null
    }

    $match = [regex]::Match($Token, '^(?<name>/[^:]+:)(?<value>.*)$')
    if (-not $match.Success) {
        return $null
    }

    $lookup = Get-WecutilCommandOptionLookup -CanonicalCommand $CanonicalCommand
    $name = $match.Groups['name'].Value
    if (-not $lookup.ContainsKey($name)) {
        return $null
    }

    [pscustomobject]@{
        Prefix = $name
        Value  = $match.Groups['value'].Value
        Option = $lookup[$name]
    }
}

function Get-WecutilSubscriptionCompletions {
    param([string]$CurrentWord)

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($name in @(Get-WecutilSubscriptionNames)) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $name.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-WecutilCompletionResult -CompletionText $name -ResultType 'ParameterValue' -ToolTip 'Subscription ID.' -ListItemText $name))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '<subscription-id>' } else { $CurrentWord }
        [void]$results.Add((New-WecutilCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip 'Subscription ID.' -ListItemText $fallback))
    }

    @($results.ToArray())
}

function Get-WecutilTerminalCompletions {
    param([string]$CurrentWord)

    $completionText = if ([string]::IsNullOrEmpty($CurrentWord)) { ' ' } else { $CurrentWord }
    @(
        New-WecutilCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip 'No further arguments are valid after help.' -ListItemText $completionText
    )
}

function Complete-Wecutil {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $catalog = Get-WecutilCatalog
    $tokenState = Get-WecutilTokenState -Line $commandAst.ToString() -CursorPosition $cursorPosition
    $argumentState = Get-WecutilArgumentsFromTokenState -TokenState $tokenState
    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)

    if ($hasTrailingSpace -and -not [string]::IsNullOrEmpty($argumentState.CurrentArgument)) {
        $currentWord = ''
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent + $argumentState.CurrentArgument)
    } else {
        $currentWord = if ($null -eq $argumentState.CurrentArgument) { '' } else { $argumentState.CurrentArgument }
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent)
    }

    $activeCommand = $null
    $commandIndex = -1
    for ($i = 0; $i -lt $argumentsBeforeCurrent.Count; $i++) {
        $token = $argumentsBeforeCurrent[$i]
        if ($catalog.CommandLookup.ContainsKey($token)) {
            $activeCommand = $catalog.CommandLookup[$token]
            $commandIndex = $i
            break
        }
    }

    $helpRequested = @(($argumentsBeforeCurrent + $currentWord) | Where-Object { $_ -in $catalog.HelpTokens }).Count -gt 0
    if ($helpRequested) {
        return @(Get-WecutilTerminalCompletions -CurrentWord $currentWord)
    }

    if ($null -eq $activeCommand) {
        $results = New-Object System.Collections.Generic.List[object]
        if ([string]::IsNullOrWhiteSpace($currentWord) -or -not ($currentWord.StartsWith('-') -or $currentWord.StartsWith('/'))) {
            foreach ($commandCompletion in @(Get-WecutilCommandCompletions -CurrentWord $currentWord)) {
                [void]$results.Add($commandCompletion)
            }
        }
        foreach ($helpCompletion in @(Get-WecutilHelpCompletions -CurrentWord $currentWord)) {
            [void]$results.Add($helpCompletion)
        }
        @($results.ToArray()) | Group-Object CompletionText | ForEach-Object { $_.Group[0] }
        return
    }

    $tokensAfterCommand = @(
        if ($commandIndex -ge 0 -and $commandIndex -lt ($argumentsBeforeCurrent.Count - 1)) {
            $argumentsBeforeCurrent[($commandIndex + 1)..($argumentsBeforeCurrent.Count - 1)]
        }
    )

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('/')) {
        $inline = Get-WecutilInlineOptionInfo -Token $currentWord -CanonicalCommand $activeCommand.Canonical
        if ($null -ne $inline) {
            $key = $inline.Prefix.ToLowerInvariant()
            if ($catalog.EnumValues.ContainsKey($key)) {
                return @(Get-WecutilEnumCompletions -CurrentWord $inline.Value -Values $catalog.EnumValues[$key] -Prefix $inline.Prefix -ToolTip $inline.Option.Description)
            }
            if ($catalog.PathOptions.ContainsKey($key)) {
                return @(Get-WecutilPathCompletions -CurrentWord $inline.Value -Prefix $inline.Prefix -ToolTip $inline.Option.Description -Placeholder $catalog.PathOptions[$key] -Kind 'File')
            }
            if ($catalog.PlaceholderOptions.ContainsKey($key)) {
                return @(Get-WecutilPlaceholderCompletions -CurrentWord $inline.Value -Prefix $inline.Prefix -Placeholder $catalog.PlaceholderOptions[$key] -ToolTip $inline.Option.Description)
            }
        }

        return @(Get-WecutilOptionCompletions -CanonicalCommand $activeCommand.Canonical -CurrentWord $currentWord)
    }

    $positionals = @($tokensAfterCommand | Where-Object { -not ($_ -in $catalog.HelpTokens) -and -not $_.StartsWith('/') -and -not $_.StartsWith('-') })

    switch ($activeCommand.Positional) {
        'SubscriptionId' {
            if ($positionals.Count -eq 0) {
                return @(Get-WecutilSubscriptionCompletions -CurrentWord $currentWord)
            }
        }
        'SubscriptionThenEventSource' {
            if ($positionals.Count -eq 0) {
                return @(Get-WecutilSubscriptionCompletions -CurrentWord $currentWord)
            }

            return @(Get-WecutilPlaceholderCompletions -CurrentWord $currentWord -Prefix '' -Placeholder '<event-source>' -ToolTip 'Event source computer name or IP address.')
        }
        'SubscriptionIdOrConfig' {
            if ($positionals.Count -eq 0) {
                $results = New-Object System.Collections.Generic.List[object]
                foreach ($subscription in @(Get-WecutilSubscriptionCompletions -CurrentWord $currentWord)) {
                    [void]$results.Add($subscription)
                }
                foreach ($pathResult in @(Get-WecutilPathCompletions -CurrentWord $currentWord -Prefix '' -ToolTip 'Subscription XML config file.' -Placeholder '<config.xml>' -Kind 'File')) {
                    [void]$results.Add($pathResult)
                }
                return @($results.ToArray()) | Group-Object CompletionText | ForEach-Object { $_.Group[0] }
            }
        }
        'ConfigFile' {
            if ($positionals.Count -eq 0) {
                return @(Get-WecutilPathCompletions -CurrentWord $currentWord -Prefix '' -ToolTip 'Subscription XML config file.' -Placeholder '<config.xml>' -Kind 'File')
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-WecutilOptionCompletions -CanonicalCommand $activeCommand.Canonical -CurrentWord $currentWord)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('wecutil', 'wecutil.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Wecutil -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
