# wevtutil tab completion for PowerShell
# Provides static and dynamic completion for wevtutil commands, options, and key values.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name WevtutilCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:WevtutilCompletionCatalog = @{
        Initialized                = $false
        CommandAliases             = @{}
        CommandSuggestions         = @()
        OptionsByCommand           = @{}
        ValueHintsByCommand        = @{}
        PathOptions                = @{}
        LogNamesCache              = @()
        LogNamesCacheUpdated       = [datetime]::MinValue
        PublisherNamesCache        = @()
        PublisherNamesCacheUpdated = [datetime]::MinValue
    }
}

function New-WevtutilCompletionResult {
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

function ConvertTo-WevtutilQuotedValue {
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

function Get-WevtutilCurrentToken {
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

function Test-WevtutilCommandAvailable {
    [bool](Get-Command -Name wevtutil.exe -ErrorAction SilentlyContinue)
}

function Initialize-WevtutilCompletionCatalog {
    if ($script:WevtutilCompletionCatalog.Initialized) {
        return
    }

    $remoteOptions = @('/r:', '/remote:', '/u:', '/username:', '/p:', '/password:', '/a:', '/authentication:')
    $unicodeOptions = @('/uni:', '/unicode:')
    $commonOptions = @($remoteOptions + $unicodeOptions)
    $commonWithHelp = @($commonOptions + '/?')
    $unicodeWithHelp = @($unicodeOptions + '/?')

    $commands = @(
        @{ Canonical = 'el';  Description = 'List log names.';                                                      Suggestions = @('el', 'enum-logs') },
        @{ Canonical = 'gl';  Description = 'Get log configuration information.';                                   Suggestions = @('gl', 'get-log') },
        @{ Canonical = 'sl';  Description = 'Modify configuration of a log.';                                       Suggestions = @('sl', 'set-log') },
        @{ Canonical = 'ep';  Description = 'List event publishers.';                                               Suggestions = @('ep', 'enum-publishers') },
        @{ Canonical = 'gp';  Description = 'Get configuration information for event publishers.';                  Suggestions = @('gp', 'get-publisher') },
        @{ Canonical = 'im';  Description = 'Install event publishers and logs from a manifest.';                   Suggestions = @('im', 'install-manifest') },
        @{ Canonical = 'um';  Description = 'Uninstall event publishers and logs from a manifest.';                 Suggestions = @('um', 'uninstall-manifest') },
        @{ Canonical = 'qe';  Description = 'Query events from a log, log file, or structured query.';             Suggestions = @('qe', 'query-events') },
        @{ Canonical = 'gli'; Description = 'Get log status information.';                                          Suggestions = @('gli', 'get-loginfo') },
        @{ Canonical = 'epl'; Description = 'Export events from a log.';                                            Suggestions = @('epl', 'export-log') },
        @{ Canonical = 'al';  Description = 'Archive a log file in a self-contained format.';                       Suggestions = @('al', 'archive-log') },
        @{ Canonical = 'cl';  Description = 'Clear a log and optionally back it up.';                               Suggestions = @('cl', 'clear-log') }
    )

    $commandAliases = @{}
    $commandSuggestions = New-Object System.Collections.Generic.List[object]

    foreach ($command in $commands) {
        foreach ($suggestion in $command.Suggestions) {
            $commandAliases[$suggestion.ToLowerInvariant()] = $command.Canonical
            $commandSuggestions.Add([pscustomobject]@{
                    CompletionText = $suggestion
                    ToolTip        = $command.Description
                })
        }
    }

    $script:WevtutilCompletionCatalog.CommandAliases = $commandAliases
    $script:WevtutilCompletionCatalog.CommandSuggestions = @($commandSuggestions.ToArray())

    $script:WevtutilCompletionCatalog.OptionsByCommand = @{
        'el'  = @($commonWithHelp)
        'gl'  = @('/f:', '/format:') + $commonWithHelp
        'sl'  = @('/e:', '/enabled:', '/q:', '/quiet:', '/fm:', '/filemax:', '/i:', '/isolation:', '/lfn:', '/logfilename:', '/rt:', '/retention:', '/ab:', '/autobackup:', '/ms:', '/maxsize:', '/l:', '/level:', '/k:', '/keywords:', '/ca:', '/channelaccess:', '/c:', '/config:') + $commonWithHelp
        'ep'  = @($commonWithHelp)
        'gp'  = @('/ge:', '/getevents:', '/gm:', '/getmessage:', '/f:', '/format:') + $commonWithHelp
        'im'  = @('/rf:', '/resourceFilePath:', '/mf:', '/messageFilePath:', '/pf:', '/parameterFilePath:') + $unicodeWithHelp
        'um'  = @($unicodeWithHelp)
        'qe'  = @('/lf:', '/logfile:', '/sq:', '/structuredquery:', '/q:', '/query:', '/bm:', '/bookmark:', '/sbm:', '/savebookmark:', '/rd:', '/reversedirection:', '/f:', '/format:', '/l:', '/locale:', '/c:', '/count:', '/e:', '/element:') + $commonWithHelp
        'gli' = @('/lf:', '/logfile:') + $commonWithHelp
        'epl' = @('/lf:', '/logfile:', '/sq:', '/structuredquery:', '/q:', '/query:', '/ow:', '/overwrite:') + $commonWithHelp
        'al'  = @('/l:', '/locale:') + $commonWithHelp
        'cl'  = @('/bu:', '/backup:') + $commonWithHelp
    }

    $script:WevtutilCompletionCatalog.ValueHintsByCommand = @{
        '__common__' = @{
            '/a:'               = @('Default', 'Negotiate', 'Kerberos', 'NTLM')
            '/authentication:'  = @('Default', 'Negotiate', 'Kerberos', 'NTLM')
            '/uni:'             = @('true', 'false')
            '/unicode:'         = @('true', 'false')
        }
        'gl' = @{
            '/f:'               = @('XML', 'Text')
            '/format:'          = @('XML', 'Text')
        }
        'sl' = @{
            '/e:'               = @('true', 'false')
            '/enabled:'         = @('true', 'false')
            '/q:'               = @('true', 'false')
            '/quiet:'           = @('true', 'false')
            '/i:'               = @('system', 'application', 'custom')
            '/isolation:'       = @('system', 'application', 'custom')
            '/rt:'              = @('true', 'false')
            '/retention:'       = @('true', 'false')
            '/ab:'              = @('true', 'false')
            '/autobackup:'      = @('true', 'false')
        }
        'gp' = @{
            '/ge:'              = @('true', 'false')
            '/getevents:'       = @('true', 'false')
            '/gm:'              = @('true', 'false')
            '/getmessage:'      = @('true', 'false')
            '/f:'               = @('XML', 'Text')
            '/format:'          = @('XML', 'Text')
        }
        'qe' = @{
            '/lf:'              = @('true', 'false')
            '/logfile:'         = @('true', 'false')
            '/sq:'              = @('true', 'false')
            '/structuredquery:' = @('true', 'false')
            '/rd:'              = @('true', 'false')
            '/reversedirection:' = @('true', 'false')
            '/f:'               = @('XML', 'Text', 'RenderedXml')
            '/format:'          = @('XML', 'Text', 'RenderedXml')
        }
        'gli' = @{
            '/lf:'              = @('true', 'false')
            '/logfile:'         = @('true', 'false')
        }
        'epl' = @{
            '/lf:'              = @('true', 'false')
            '/logfile:'         = @('true', 'false')
            '/sq:'              = @('true', 'false')
            '/structuredquery:' = @('true', 'false')
            '/ow:'              = @('true', 'false')
            '/overwrite:'       = @('true', 'false')
        }
    }

    $script:WevtutilCompletionCatalog.PathOptions = @{
        '/c:'                  = @('.xml')
        '/config:'             = @('.xml')
        '/lfn:'                = @('.etl', '.evt', '.evtx', '.log')
        '/logfilename:'        = @('.etl', '.evt', '.evtx', '.log')
        '/rf:'                 = @()
        '/resourcefilepath:'   = @()
        '/mf:'                 = @()
        '/messagefilepath:'    = @()
        '/pf:'                 = @()
        '/parameterfilepath:'  = @()
        '/bm:'                 = @('.xml')
        '/bookmark:'           = @('.xml')
        '/sbm:'                = @('.xml')
        '/savebookmark:'       = @('.xml')
        '/bu:'                 = @('.evtx')
        '/backup:'             = @('.evtx')
    }

    $script:WevtutilCompletionCatalog.Initialized = $true
}

function Resolve-WevtutilCommandAlias {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $key = $Token.ToLowerInvariant()
    if ($script:WevtutilCompletionCatalog.CommandAliases.ContainsKey($key)) {
        return $script:WevtutilCompletionCatalog.CommandAliases[$key]
    }

    $null
}

function Get-WevtutilActiveCommand {
    param([string[]]$Tokens)

    foreach ($token in $Tokens) {
        $resolved = Resolve-WevtutilCommandAlias -Token $token
        if ($resolved) {
            return $resolved
        }
    }

    $null
}

function Get-WevtutilTokensAfterCommand {
    param([string[]]$Tokens)

    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        if (Resolve-WevtutilCommandAlias -Token $Tokens[$i]) {
            if ($i -lt ($Tokens.Count - 1)) {
                return @($Tokens[($i + 1)..($Tokens.Count - 1)])
            }

            return @()
        }
    }

    @()
}

function Get-WevtutilOptionPrefixFromToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    if ($Token -match '^(/[A-Za-z][A-Za-z0-9\-]*:)') {
        return $matches[1]
    }

    $null
}

function Get-WevtutilValueHints {
    param(
        [string]$Command,
        [string]$OptionPrefix
    )

    if ([string]::IsNullOrWhiteSpace($OptionPrefix)) {
        return @()
    }

    $optionKey = $OptionPrefix.ToLowerInvariant()
    $values = @()

    if ($script:WevtutilCompletionCatalog.ValueHintsByCommand.ContainsKey('__common__')) {
        $commonMap = $script:WevtutilCompletionCatalog.ValueHintsByCommand['__common__']
        if ($commonMap.ContainsKey($optionKey)) {
            $values += $commonMap[$optionKey]
        }
    }

    if ($Command -and $script:WevtutilCompletionCatalog.ValueHintsByCommand.ContainsKey($Command)) {
        $commandMap = $script:WevtutilCompletionCatalog.ValueHintsByCommand[$Command]
        if ($commandMap.ContainsKey($optionKey)) {
            $values += $commandMap[$optionKey]
        }
    }

    @($values | Sort-Object -Unique)
}

function Test-WevtutilPathLikeOption {
    param([string]$OptionPrefix)

    if ([string]::IsNullOrWhiteSpace($OptionPrefix)) {
        return $false
    }

    $script:WevtutilCompletionCatalog.PathOptions.ContainsKey($OptionPrefix.ToLowerInvariant())
}

function Get-WevtutilAllowedExtensionsForOption {
    param([string]$OptionPrefix)

    if ([string]::IsNullOrWhiteSpace($OptionPrefix)) {
        return @()
    }

    $key = $OptionPrefix.ToLowerInvariant()
    if ($script:WevtutilCompletionCatalog.PathOptions.ContainsKey($key)) {
        return $script:WevtutilCompletionCatalog.PathOptions[$key]
    }

    @()
}

function Get-WevtutilPathCompletions {
    param(
        [string]$InputPath,
        [string[]]$AllowedExtensions
    )

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ([System.IO.Path]::GetPathRoot($cleanInput) -eq $cleanInput) {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and $InputPath.StartsWith('"')

    $items = Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue
    if ($AllowedExtensions -and $AllowedExtensions.Count -gt 0) {
        $items = $items | Where-Object {
            $_.PSIsContainer -or ($AllowedExtensions -contains $_.Extension.ToLowerInvariant())
        }
    }

    $items | ForEach-Object {
        ConvertTo-WevtutilQuotedValue -Value $_.FullName -AlwaysQuote $alwaysQuote
    }
}

function Test-WevtutilOptionPresent {
    param(
        [string[]]$Tokens,
        [string[]]$OptionNames
    )

    if (-not $Tokens -or -not $OptionNames) {
        return $false
    }

    $lookup = @{}
    foreach ($name in $OptionNames) {
        $lookup[$name.ToLowerInvariant()] = $true
    }

    foreach ($token in $Tokens) {
        if ($token -match '^(/[^:]+)(?::.*)?$') {
            $optionName = $matches[1].ToLowerInvariant()
            if ($lookup.ContainsKey($optionName)) {
                return $true
            }
        }
    }

    $false
}

function Get-WevtutilOptionValue {
    param(
        [string[]]$Tokens,
        [string[]]$OptionNames
    )

    if (-not $Tokens -or -not $OptionNames) {
        return $null
    }

    $lookup = @{}
    foreach ($name in $OptionNames) {
        $lookup[$name.ToLowerInvariant()] = $true
    }

    for ($i = $Tokens.Count - 1; $i -ge 0; $i--) {
        $token = $Tokens[$i]
        if ($token -match '^(/[^:]+):(.*)$') {
            $optionName = $matches[1].ToLowerInvariant()
            if ($lookup.ContainsKey($optionName)) {
                return $matches[2]
            }
        }
    }

    $null
}

function Test-WevtutilOptionTrue {
    param(
        [string[]]$Tokens,
        [string[]]$OptionNames
    )

    $value = Get-WevtutilOptionValue -Tokens $Tokens -OptionNames $OptionNames
    if ($null -eq $value) {
        return $false
    }

    $value.Equals('true', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-WevtutilPositionalArguments {
    param([string[]]$Tokens)

    @($Tokens | Where-Object { $_ -and -not $_.StartsWith('/') })
}

function Get-WevtutilExpectedPositionalKind {
    param(
        [string]$Command,
        [string[]]$TokensAfterCommand
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return $null
    }

    $positionalCount = @(Get-WevtutilPositionalArguments -Tokens $TokensAfterCommand).Count
    $usesConfig = Test-WevtutilOptionPresent -Tokens $TokensAfterCommand -OptionNames @('/c', '/config')
    $usesLogFile = Test-WevtutilOptionTrue -Tokens $TokensAfterCommand -OptionNames @('/lf', '/logfile')
    $usesStructuredQuery = Test-WevtutilOptionTrue -Tokens $TokensAfterCommand -OptionNames @('/sq', '/structuredquery')

    switch ($Command) {
        'gl' {
            if ($positionalCount -eq 0) { return 'logname' }
        }
        'sl' {
            if (-not $usesConfig -and $positionalCount -eq 0) { return 'logname' }
        }
        'gp' {
            if ($positionalCount -eq 0) { return 'publisher' }
        }
        'im' {
            if ($positionalCount -eq 0) { return 'manifest' }
        }
        'um' {
            if ($positionalCount -eq 0) { return 'manifest' }
        }
        'qe' {
            if ($positionalCount -eq 0) {
                if ($usesStructuredQuery) { return 'structuredquery' }
                if ($usesLogFile) { return 'logfile' }
                return 'logname'
            }
        }
        'gli' {
            if ($positionalCount -eq 0) {
                if ($usesLogFile) { return 'logfile' }
                return 'logname'
            }
        }
        'epl' {
            if ($positionalCount -eq 0) {
                if ($usesStructuredQuery) { return 'structuredquery' }
                if ($usesLogFile) { return 'logfile' }
                return 'logname'
            }

            if ($positionalCount -eq 1) {
                return 'targetfile'
            }
        }
        'al' {
            if ($positionalCount -eq 0) { return 'logfile' }
        }
        'cl' {
            if ($positionalCount -eq 0) { return 'logname' }
        }
    }

    $null
}

function Get-WevtutilAllowedExtensionsForPositionalKind {
    param([string]$Kind)

    switch ($Kind) {
        'manifest'        { return @('.man', '.xml') }
        'logfile'         { return @('.etl', '.evt', '.evtx') }
        'structuredquery' { return @('.xml') }
        'targetfile'      { return @('.evtx') }
        default           { return @() }
    }
}

function Update-WevtutilLogNameCache {
    $cacheAge = (Get-Date) - $script:WevtutilCompletionCatalog.LogNamesCacheUpdated
    if ($cacheAge.TotalSeconds -lt 120 -and $script:WevtutilCompletionCatalog.LogNamesCache.Count -gt 0) {
        return
    }

    if (-not (Test-WevtutilCommandAvailable)) {
        $script:WevtutilCompletionCatalog.LogNamesCache = @()
        $script:WevtutilCompletionCatalog.LogNamesCacheUpdated = Get-Date
        return
    }

    try {
        $logNames = @(& wevtutil.exe el 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $script:WevtutilCompletionCatalog.LogNamesCache = @($logNames | Sort-Object -Unique)
    } catch {
        $script:WevtutilCompletionCatalog.LogNamesCache = @()
    }

    $script:WevtutilCompletionCatalog.LogNamesCacheUpdated = Get-Date
}

function Get-WevtutilLogNameCompletions {
    param([string]$WordToComplete)

    Update-WevtutilLogNameCache

    $cleanPrefix = $WordToComplete.Trim('"')
    $alwaysQuote = $WordToComplete.StartsWith('"')

    $script:WevtutilCompletionCatalog.LogNamesCache |
        Where-Object { $_ -like "$cleanPrefix*" } |
        ForEach-Object { ConvertTo-WevtutilQuotedValue -Value $_ -AlwaysQuote $alwaysQuote }
}

function Update-WevtutilPublisherNameCache {
    $cacheAge = (Get-Date) - $script:WevtutilCompletionCatalog.PublisherNamesCacheUpdated
    if ($cacheAge.TotalSeconds -lt 120 -and $script:WevtutilCompletionCatalog.PublisherNamesCache.Count -gt 0) {
        return
    }

    if (-not (Test-WevtutilCommandAvailable)) {
        $script:WevtutilCompletionCatalog.PublisherNamesCache = @()
        $script:WevtutilCompletionCatalog.PublisherNamesCacheUpdated = Get-Date
        return
    }

    try {
        $publishers = @(& wevtutil.exe ep 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $script:WevtutilCompletionCatalog.PublisherNamesCache = @($publishers | Sort-Object -Unique)
    } catch {
        $script:WevtutilCompletionCatalog.PublisherNamesCache = @()
    }

    $script:WevtutilCompletionCatalog.PublisherNamesCacheUpdated = Get-Date
}

function Get-WevtutilPublisherNameCompletions {
    param([string]$WordToComplete)

    Update-WevtutilPublisherNameCache

    $cleanPrefix = $WordToComplete.Trim('"')
    $alwaysQuote = $WordToComplete.StartsWith('"')

    $script:WevtutilCompletionCatalog.PublisherNamesCache |
        Where-Object { $_ -like "$cleanPrefix*" } |
        ForEach-Object { ConvertTo-WevtutilQuotedValue -Value $_ -AlwaysQuote $alwaysQuote }
}

function Complete-Wevtutil {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-WevtutilCompletionCatalog

    $allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokens = @($allTokens | Select-Object -Skip 1)
    $line = $commandAst.ToString()
    $hasTrailingSpace = ([string]::IsNullOrEmpty($wordToComplete) -and $cursorPosition -ge $line.Length) -or ($line -match '\s$')
    $currentWord = if ($hasTrailingSpace) {
        ''
    } elseif ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        Get-WevtutilCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
    } else {
        $wordToComplete
    }

    if ($hasTrailingSpace) {
        $tokensBeforeCurrent = @($tokens)
    } elseif ($tokens.Count -gt 1) {
        $tokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
    } else {
        $tokensBeforeCurrent = @()
    }

    $activeCommand = Get-WevtutilActiveCommand -Tokens $tokensBeforeCurrent
    $tokensAfterCommand = Get-WevtutilTokensAfterCommand -Tokens $tokensBeforeCurrent
    $currentPrefix = Get-WevtutilOptionPrefixFromToken -Token $currentWord

    if ($currentPrefix) {
        $typedValue = $currentWord.Substring($currentPrefix.Length)
        $valueHints = Get-WevtutilValueHints -Command $activeCommand -OptionPrefix $currentPrefix

        if (@($valueHints).Count -gt 0) {
            return $valueHints |
                Where-Object { $_ -like "$typedValue*" } |
                ForEach-Object {
                    New-WevtutilCompletionResult -CompletionText "$currentPrefix$_" -ResultType 'ParameterValue' -ToolTip $_
                }
        }

        if (Test-WevtutilPathLikeOption -OptionPrefix $currentPrefix) {
            $allowedExtensions = Get-WevtutilAllowedExtensionsForOption -OptionPrefix $currentPrefix
            return Get-WevtutilPathCompletions -InputPath $typedValue -AllowedExtensions $allowedExtensions |
                ForEach-Object {
                    New-WevtutilCompletionResult -CompletionText "$currentPrefix$_" -ResultType 'ParameterValue' -ToolTip $_
                }
        }
    }

    if (-not $activeCommand) {
        if ([string]::IsNullOrWhiteSpace($currentWord) -or -not $currentWord.StartsWith('/')) {
            return $script:WevtutilCompletionCatalog.CommandSuggestions |
                Where-Object { $_.CompletionText -like "$currentWord*" } |
                ForEach-Object {
                    New-WevtutilCompletionResult -CompletionText $_.CompletionText -ResultType 'ParameterName' -ToolTip $_.ToolTip
                }
        }

        if ($currentWord.StartsWith('/')) {
            return @('/?') |
                Where-Object { $_ -like "$currentWord*" } |
                ForEach-Object {
                    New-WevtutilCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
                }
        }

        return @()
    }

    $expectedPositionalKind = Get-WevtutilExpectedPositionalKind -Command $activeCommand -TokensAfterCommand $tokensAfterCommand
    if ($expectedPositionalKind -and -not $currentWord.StartsWith('/')) {
        switch ($expectedPositionalKind) {
            'logname' {
                return Get-WevtutilLogNameCompletions -WordToComplete $currentWord |
                    ForEach-Object {
                        New-WevtutilCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                    }
            }
            'publisher' {
                return Get-WevtutilPublisherNameCompletions -WordToComplete $currentWord |
                    ForEach-Object {
                        New-WevtutilCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                    }
            }
            default {
                $allowedExtensions = Get-WevtutilAllowedExtensionsForPositionalKind -Kind $expectedPositionalKind
                return Get-WevtutilPathCompletions -InputPath $currentWord -AllowedExtensions $allowedExtensions |
                    ForEach-Object {
                        New-WevtutilCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                    }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('/')) {
        $suggestions = @()
        if ($script:WevtutilCompletionCatalog.OptionsByCommand.ContainsKey($activeCommand)) {
            $suggestions = @($script:WevtutilCompletionCatalog.OptionsByCommand[$activeCommand])
        }

        return $suggestions |
            Sort-Object -Unique |
            Where-Object { $_ -like "$currentWord*" } |
            ForEach-Object {
                New-WevtutilCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
            }
    }

    @()
}

# Register the completer
Register-ArgumentCompleter -Native -CommandName 'wevtutil', 'wevtutil.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Wevtutil -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
