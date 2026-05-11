Set-StrictMode -Version 2.0

function Get-GoCompletionCache {
    $existing = Get-Variable -Name GoCompletionCache -Scope Script -ErrorAction Ignore
    if ($existing) {
        return $existing.Value
    }

    $cache = @{
        ExecutableResolved = $false
        ExecutablePath     = $null
        TextByKey          = @{}
        RootCommands       = $null
        HelpTopics         = $null
        NestedCommands     = @{}
        BuildFlags         = $null
        EnvFlags           = $null
        TestFlags          = $null
        ToolNames          = $null
        BuildModes         = $null
    }

    Set-Variable -Name GoCompletionCache -Scope Script -Value $cache
    $cache
}

function New-GoCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ListItemText = $CompletionText,
        [System.Management.Automation.CompletionResultType]$ResultType = [System.Management.Automation.CompletionResultType]::ParameterValue,
        [string]$ToolTip = $CompletionText
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

function Get-GoRootCommandMetadata {
    [ordered]@{
        'bug'       = 'start a bug report'
        'help'      = 'show help for commands and topics'
        'build'     = 'compile packages and dependencies'
        'clean'     = 'remove object files and cached files'
        'doc'       = 'show documentation for package or symbol'
        'env'       = 'print Go environment information'
        'fix'       = 'apply fixes suggested by static checkers'
        'fmt'       = 'gofmt (reformat) package sources'
        'generate'  = 'generate Go files by processing source'
        'get'       = 'add dependencies to current module and install them'
        'install'   = 'compile and install packages and dependencies'
        'list'      = 'list packages or modules'
        'mod'       = 'module maintenance'
        'work'      = 'workspace maintenance'
        'run'       = 'compile and run Go program'
        'telemetry' = 'manage telemetry data and settings'
        'test'      = 'test packages'
        'tool'      = 'run specified go tool'
        'version'   = 'print Go version'
        'vet'       = 'report likely mistakes in packages'
    }
}

function Get-GoHelpTopicMetadata {
    [ordered]@{
        'buildconstraint' = 'build constraints'
        'buildjson'       = 'build -json encoding'
        'buildmode'       = 'build modes'
        'c'               = 'calling between Go and C'
        'cache'           = 'build and test caching'
        'environment'     = 'environment variables'
        'filetype'        = 'file types'
        'goauth'          = 'GOAUTH environment variable'
        'go.mod'          = 'the go.mod file'
        'gopath'          = 'GOPATH environment variable'
        'goproxy'         = 'module proxy protocol'
        'importpath'      = 'import path syntax'
        'modules'         = 'modules, module versions, and more'
        'module-auth'     = 'module authentication using go.sum'
        'packages'        = 'package lists and patterns'
        'private'         = 'configuration for downloading non-public code'
        'testflag'        = 'testing flags'
        'testfunc'        = 'testing functions'
        'vcs'             = 'controlling version control with GOVCS'
    }
}

function Get-GoNestedCommandMetadata {
    param([string]$CommandName)

    switch ($CommandName) {
        'mod' {
            return [ordered]@{
                'download' = 'download modules to local cache'
                'edit'     = 'edit go.mod from tools or scripts'
                'graph'    = 'print module requirement graph'
                'init'     = 'initialize new module in current directory'
                'tidy'     = 'add missing and remove unused modules'
                'vendor'   = 'make vendored copy of dependencies'
                'verify'   = 'verify dependencies have expected content'
                'why'      = 'explain why packages or modules are needed'
            }
        }
        'work' {
            return [ordered]@{
                'edit'   = 'edit go.work from tools or scripts'
                'init'   = 'initialize workspace file'
                'sync'   = 'sync workspace build list to modules'
                'use'    = 'add modules to workspace file'
                'vendor' = 'make vendored copy of dependencies'
            }
        }
        'telemetry' {
            return [ordered]@{
                'off'   = 'disable telemetry collection and upload'
                'local' = 'keep telemetry locally without uploading'
                'on'    = 'enable telemetry collection and upload'
            }
        }
    }

    [ordered]@{}
}

function Get-GoFallbackToolNames {
    @(
        'asm', 'cgo', 'compile', 'covdata', 'cover', 'doc', 'fix', 'link',
        'nm', 'objdump', 'pack', 'pprof', 'preprofile', 'test2json', 'trace', 'vet'
    )
}

function Get-GoKnownItemsFromText {
    param(
        [string]$Text,
        [string[]]$KnownItems
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-Output -NoEnumerate ([string[]]@())
        return
    }

    $results = New-Object System.Collections.Generic.List[string]
    foreach ($item in $KnownItems) {
        $escaped = [regex]::Escape($item)
        $pattern = if ($item.StartsWith('-', [System.StringComparison]::Ordinal)) {
            "(?<![A-Za-z0-9_.-])$escaped(?![A-Za-z0-9_.-])"
        } else {
            "(?<![A-Za-z0-9_.-])$escaped(?![A-Za-z0-9_.-])"
        }

        if ([regex]::IsMatch($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            [void]$results.Add($item)
        }
    }

    Write-Output -NoEnumerate ($results.ToArray())
}

function Resolve-GoExecutablePath {
    $cache = Get-GoCompletionCache
    if ($cache.ExecutableResolved) {
        return $cache.ExecutablePath
    }

    $cache.ExecutableResolved = $true

    $command = Get-Command -Name go.exe -ErrorAction Ignore | Select-Object -First 1
    if (-not $command) {
        $command = Get-Command -Name go -ErrorAction Ignore | Select-Object -First 1
    }
    if ($command) {
        $cache.ExecutablePath = if ($command.Path) {
            $command.Path
        } elseif ($command.Source) {
            $command.Source
        } else {
            $command.Name
        }

        return $cache.ExecutablePath
    }

    $fallbackPath = 'C:\Program Files\Go\bin\go.exe'
    if (Test-Path -LiteralPath $fallbackPath) {
        $cache.ExecutablePath = $fallbackPath
    }

    $cache.ExecutablePath
}

function Get-GoText {
    param(
        [string]$CacheKey,
        [string[]]$Arguments
    )

    $cache = Get-GoCompletionCache
    if ($cache.TextByKey.ContainsKey($CacheKey)) {
        return $cache.TextByKey[$CacheKey]
    }

    $goPath = Resolve-GoExecutablePath
    if ([string]::IsNullOrWhiteSpace($goPath)) {
        $cache.TextByKey[$CacheKey] = ''
        return ''
    }

    try {
        $text = (& $goPath @Arguments 2>&1 | Out-String -Width 4096)
    } catch {
        $text = ''
    }

    if ($null -eq $text) {
        $text = ''
    }

    $cache.TextByKey[$CacheKey] = $text
    $text
}

function Get-GoRootCommands {
    $cache = Get-GoCompletionCache
    if ($null -ne $cache.RootCommands) {
        return $cache.RootCommands
    }

    $metadata = Get-GoRootCommandMetadata
    $text = Get-GoText -CacheKey 'help' -Arguments @('help')
    $commands = Get-GoKnownItemsFromText -Text $text -KnownItems @($metadata.Keys)
    if ($commands.Count -eq 0) {
        $commands = @($metadata.Keys)
    }

    $cache.RootCommands = $commands
    $commands
}

function Get-GoHelpTopics {
    $cache = Get-GoCompletionCache
    if ($null -ne $cache.HelpTopics) {
        return $cache.HelpTopics
    }

    $metadata = Get-GoHelpTopicMetadata
    $text = Get-GoText -CacheKey 'help' -Arguments @('help')
    $topics = Get-GoKnownItemsFromText -Text $text -KnownItems @($metadata.Keys)
    if ($topics.Count -eq 0) {
        $topics = @($metadata.Keys)
    }

    $cache.HelpTopics = $topics
    $topics
}

function Get-GoNestedCommands {
    param([string]$CommandName)

    $cache = Get-GoCompletionCache
    if ($cache.NestedCommands.ContainsKey($CommandName)) {
        return $cache.NestedCommands[$CommandName]
    }

    $metadata = Get-GoNestedCommandMetadata -CommandName $CommandName
    $text = Get-GoText -CacheKey "help:$CommandName" -Arguments @('help', $CommandName)
    $nested = Get-GoKnownItemsFromText -Text $text -KnownItems @($metadata.Keys)
    if ($nested.Count -eq 0) {
        $nested = @($metadata.Keys)
    }

    $cache.NestedCommands[$CommandName] = $nested
    $nested
}

function Get-GoBuildFlags {
    $cache = Get-GoCompletionCache
    if ($null -ne $cache.BuildFlags) {
        return $cache.BuildFlags
    }

    $knownFlags = @(
        '-C', '-a', '-n', '-p', '-race', '-msan', '-asan', '-cover', '-v', '-work', '-x',
        '-asmflags', '-buildmode', '-buildvcs', '-compiler', '-gccgoflags', '-gcflags',
        '-installsuffix', '-json', '-ldflags', '-linkshared', '-mod', '-modcacherw',
        '-modfile', '-overlay', '-pgo', '-pkgdir', '-tags', '-trimpath', '-toolexec',
        '-covermode', '-coverpkg'
    )

    $text = Get-GoText -CacheKey 'help:build' -Arguments @('help', 'build')
    $flags = Get-GoKnownItemsFromText -Text $text -KnownItems $knownFlags
    if ($flags.Count -eq 0) {
        $flags = $knownFlags
    }

    $cache.BuildFlags = $flags
    $flags
}

function Get-GoEnvFlags {
    $cache = Get-GoCompletionCache
    if ($null -ne $cache.EnvFlags) {
        return $cache.EnvFlags
    }

    $knownFlags = @('-json', '-changed', '-u', '-w')
    $text = Get-GoText -CacheKey 'help:env' -Arguments @('help', 'env')
    $flags = Get-GoKnownItemsFromText -Text $text -KnownItems $knownFlags
    if ($flags.Count -eq 0) {
        $flags = $knownFlags
    }

    $cache.EnvFlags = $flags
    $flags
}

function Get-GoTestFlags {
    $cache = Get-GoCompletionCache
    if ($null -ne $cache.TestFlags) {
        return $cache.TestFlags
    }

    $knownFlags = @(
        '-args', '-c', '-exec', '-json', '-o', '-bench', '-benchtime', '-count',
        '-coverprofile', '-cpu', '-failfast', '-fullpath', '-list', '-outputdir',
        '-parallel', '-run', '-short', '-skip', '-timeout', '-v', '-vet'
    )

    $text = (Get-GoText -CacheKey 'help:test' -Arguments @('help', 'test')) +
        (Get-GoText -CacheKey 'help:testflag' -Arguments @('help', 'testflag'))

    $flags = Get-GoKnownItemsFromText -Text $text -KnownItems $knownFlags
    if ($flags.Count -eq 0) {
        $flags = $knownFlags
    }

    $cache.TestFlags = $flags
    $flags
}

function Get-GoBuildModeValues {
    $cache = Get-GoCompletionCache
    if ($null -ne $cache.BuildModes) {
        return $cache.BuildModes
    }

    $knownValues = @('archive', 'c-archive', 'c-shared', 'default', 'shared', 'exe', 'pie', 'plugin')
    $text = Get-GoText -CacheKey 'help:buildmode' -Arguments @('help', 'buildmode')
    $values = Get-GoKnownItemsFromText -Text $text -KnownItems $knownValues
    if ($values.Count -eq 0) {
        $values = $knownValues
    }

    $cache.BuildModes = $values
    $values
}

function Get-GoToolNames {
    $cache = Get-GoCompletionCache
    if ($null -ne $cache.ToolNames) {
        return $cache.ToolNames
    }

    $knownNames = Get-GoFallbackToolNames
    $text = Get-GoText -CacheKey 'tool' -Arguments @('tool')
    $names = Get-GoKnownItemsFromText -Text $text -KnownItems $knownNames
    if ($names.Count -eq 0) {
        $names = $knownNames
    }

    $cache.ToolNames = $names
    $names
}

function Test-GoBuildFamilyCommand {
    param([string]$CommandName)

    @('build', 'clean', 'get', 'install', 'list', 'run', 'test') -contains $CommandName
}

function Get-GoCommandFlags {
    param([string]$CommandName)

    switch ($CommandName) {
        'env' {
            return Get-GoEnvFlags
        }
        'test' {
            return @(
                @(Get-GoBuildFlags | Where-Object { $_ -ne '-C' }) +
                @(Get-GoTestFlags)
            ) | Select-Object -Unique
        }
        'build' {
            return @(
                @(Get-GoBuildFlags | Where-Object { $_ -ne '-C' }) +
                @('-o')
            ) | Select-Object -Unique
        }
        default {
            if (Test-GoBuildFamilyCommand -CommandName $CommandName) {
                return @(Get-GoBuildFlags | Where-Object { $_ -ne '-C' })
            }
        }
    }

    return ,@()
}

function Get-GoOptionBaseName {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    if ($Token -match '^(?<name>-[^=]+)=') {
        return $matches['name']
    }

    $Token
}

function Get-GoEnumValues {
    param([string]$OptionName)

    switch ($OptionName) {
        '-buildmode' {
            return Get-GoBuildModeValues
        }
        '-buildvcs' {
            return @('auto', 'true', 'false')
        }
        '-compiler' {
            return @('gc', 'gccgo')
        }
        '-covermode' {
            return @('set', 'count', 'atomic')
        }
        '-mod' {
            return @('readonly', 'vendor', 'mod')
        }
    }

    return ,@()
}

function Get-GoValuePlaceholder {
    param([string]$OptionName)

    switch ($OptionName) {
        '-asmflags'      { return '<pattern=arg list>' }
        '-coverpkg'      { return '<pattern[,pattern]>' }
        '-exec'          { return '<command>' }
        '-gccgoflags'    { return '<pattern=arg list>' }
        '-gcflags'       { return '<pattern=arg list>' }
        '-installsuffix' { return '<suffix>' }
        '-ldflags'       { return '<pattern=arg list>' }
        '-outputdir'     { return '<directory>' }
        '-p'             { return '<n>' }
        '-parallel'      { return '<n>' }
        '-tags'          { return '<tag,list>' }
        '-timeout'       { return '<duration>' }
        '-toolexec'      { return '<cmd args>' }
        '-vet'           { return '<list|off>' }
        default          { return '<value>' }
    }
}

function Test-GoOptionRequiresValue {
    param(
        [string]$CommandName,
        [string]$OptionName
    )

    if ([string]::IsNullOrWhiteSpace($OptionName)) {
        return $false
    }

    switch ($CommandName) {
        $null {
            return $OptionName -eq '-C'
        }
        'env' {
            return @('-u', '-w') -contains $OptionName
        }
        'test' {
            return @(
                '-p', '-asmflags', '-buildmode', '-buildvcs', '-compiler', '-gccgoflags',
                '-gcflags', '-installsuffix', '-ldflags', '-mod', '-modfile', '-overlay',
                '-pgo', '-pkgdir', '-tags', '-toolexec', '-covermode', '-coverpkg',
                '-o', '-exec', '-bench', '-benchtime', '-count', '-coverprofile',
                '-cpu', '-list', '-outputdir', '-parallel', '-run', '-skip', '-timeout',
                '-vet'
            ) -contains $OptionName
        }
        default {
            if (Test-GoBuildFamilyCommand -CommandName $CommandName) {
                return @(
                    '-p', '-asmflags', '-buildmode', '-buildvcs', '-compiler', '-gccgoflags',
                    '-gcflags', '-installsuffix', '-ldflags', '-mod', '-modfile', '-overlay',
                    '-pgo', '-pkgdir', '-tags', '-toolexec', '-covermode', '-coverpkg', '-o'
                ) -contains $OptionName
            }
        }
    }

    $false
}

function Get-GoQuoteCharacter {
    param([string]$InputText)

    if ([string]::IsNullOrEmpty($InputText)) {
        return $null
    }

    if ($InputText.StartsWith("'", [System.StringComparison]::Ordinal)) {
        return "'"
    }

    if ($InputText.StartsWith('"', [System.StringComparison]::Ordinal)) {
        return '"'
    }

    $null
}

function Remove-GoOuterQuotes {
    param([string]$InputText)

    if ([string]::IsNullOrEmpty($InputText)) {
        return ''
    }

    $quoteCharacter = Get-GoQuoteCharacter -InputText $InputText
    if ($null -eq $quoteCharacter) {
        return $InputText
    }

    $unquoted = $InputText.Substring(1)
    if ($unquoted.EndsWith($quoteCharacter, [System.StringComparison]::Ordinal)) {
        $unquoted = $unquoted.Substring(0, $unquoted.Length - 1)
    }

    if ($quoteCharacter -eq "'") {
        return $unquoted.Replace("''", "'")
    }

    $unquoted.Replace('`"', '"')
}

function ConvertTo-GoQuotedValue {
    param(
        [string]$Value,
        [string]$QuoteCharacter
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if ([string]::IsNullOrWhiteSpace($QuoteCharacter)) {
        if ($Value -notmatch '\s') {
            return $Value
        }

        $QuoteCharacter = '"'
    }

    if (($QuoteCharacter -eq "'") -and $Value.Contains("'")) {
        $QuoteCharacter = '"'
    }

    if ($QuoteCharacter -eq '"') {
        return '"' + $Value.Replace('`', '``').Replace('"', '`"') + '"'
    }

    "'" + $Value.Replace("'", "''") + "'"
}

function Get-GoPathCompletions {
    param(
        [string]$InputText,
        [string]$InlinePrefix = '',
        [bool]$DirectoryOnly = $false
    )

    $quoteCharacter = Get-GoQuoteCharacter -InputText $InputText
    $cleanInput = Remove-GoOuterQuotes -InputText $InputText

    $completions =
        [System.Management.Automation.CompletionCompleters]::CompleteFilename($cleanInput) |
        Where-Object {
            -not $DirectoryOnly -or
            $_.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer
        } |
        ForEach-Object {
            $completionText = ConvertTo-GoQuotedValue -Value $_.CompletionText -QuoteCharacter $quoteCharacter
            if ($InlinePrefix) {
                $completionText = $InlinePrefix + $completionText
            }

            New-GoCompletionResult -CompletionText $completionText -ListItemText $_.ListItemText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }

    Write-Output -NoEnumerate @($completions)
}

function Get-GoCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback = ''
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') {
        return ''
    }

    $tokenStart = 0
    $inSingleQuote = $false
    $inDoubleQuote = $false

    for ($index = 0; $index -lt $prefix.Length; $index++) {
        $character = $prefix[$index]

        if (($character -eq '`') -and $inDoubleQuote -and (($index + 1) -lt $prefix.Length)) {
            $index++
            continue
        }

        if (($character -eq "'") -and -not $inDoubleQuote) {
            if ($inSingleQuote -and (($index + 1) -lt $prefix.Length) -and ($prefix[$index + 1] -eq "'")) {
                $index++
                continue
            }

            $inSingleQuote = -not $inSingleQuote
            continue
        }

        if (($character -eq '"') -and -not $inSingleQuote) {
            $inDoubleQuote = -not $inDoubleQuote
            continue
        }

        if ([char]::IsWhiteSpace($character) -and -not $inSingleQuote -and -not $inDoubleQuote) {
            $tokenStart = $index + 1
        }
    }

    if ($tokenStart -lt $prefix.Length) {
        return $prefix.Substring($tokenStart)
    }

    $Fallback
}

function Get-GoCommandState {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$FallbackWordToComplete
    )

    $line = if ($CommandAst.Extent -and $CommandAst.Extent.Text) {
        $CommandAst.Extent.Text
    } else {
        ''
    }

    $relativeCursor = if ($CommandAst.Extent) {
        $CursorPosition - $CommandAst.Extent.StartOffset
    } else {
        $CursorPosition
    }

    $safeCursor = [Math]::Min([Math]::Max($relativeCursor, 0), $line.Length)
    $prefix = $line.Substring(0, $safeCursor)
    $hasTrailingSpace = ($prefix -match '\s$') -or ($CommandAst.Extent -and $CursorPosition -gt $CommandAst.Extent.EndOffset)
    $tokenMatches = [regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+')
    $allTokens = @($tokenMatches | ForEach-Object { $_.Value })

    if ($hasTrailingSpace) {
        $currentWord = ''
        $priorTokens = if ($allTokens.Count -gt 1) {
            @($allTokens[1..($allTokens.Count - 1)])
        } else {
            @()
        }
    } else {
        $currentWord = if ($allTokens.Count -gt 0) {
            $allTokens[-1]
        } else {
            Get-GoCurrentToken -Line $line -CursorPosition $safeCursor -Fallback $FallbackWordToComplete
        }

        $priorTokens = if ($allTokens.Count -gt 2) {
            @($allTokens[1..($allTokens.Count - 2)])
        } else {
            @()
        }
    }

    [pscustomobject]@{
        CurrentWord = $currentWord
        PriorTokens = $priorTokens
    }
}

function Get-GoCommandContext {
    param([string[]]$Tokens)

    $rootCommands = Get-GoRootCommands
    $pendingOption = $null
    $commandName = $null
    $subcommandName = $null
    $envMode = $null
    $testArgsSeen = $false

    foreach ($token in $Tokens) {
        if ($pendingOption) {
            $pendingOption = $null
            continue
        }

        $baseName = Get-GoOptionBaseName -Token $token

        if (-not $commandName) {
            if ($baseName -eq '-C') {
                if ($token -notlike '*=*') {
                    $pendingOption = '-C'
                }

                continue
            }

            if ($token.StartsWith('-', [System.StringComparison]::Ordinal)) {
                continue
            }

            if ($rootCommands -contains $token) {
                $commandName = $token
            }

            continue
        }

        switch ($commandName) {
            'env' {
                if ($baseName -eq '-w') {
                    $envMode = 'w'
                    if ($token -notlike '*=*') {
                        $pendingOption = '-w'
                    }

                    continue
                }

                if ($baseName -eq '-u') {
                    $envMode = 'u'
                    if ($token -notlike '*=*') {
                        $pendingOption = '-u'
                    }

                    continue
                }

                if ($token.StartsWith('-', [System.StringComparison]::Ordinal)) {
                    continue
                }

                continue
            }
            'help' {
                if (-not $subcommandName -and -not $token.StartsWith('-', [System.StringComparison]::Ordinal)) {
                    $subcommandName = $token
                }

                continue
            }
            'mod' {
                if (-not $subcommandName -and -not $token.StartsWith('-', [System.StringComparison]::Ordinal)) {
                    $subcommandName = $token
                }

                continue
            }
            'telemetry' {
                if (-not $subcommandName -and -not $token.StartsWith('-', [System.StringComparison]::Ordinal)) {
                    $subcommandName = $token
                }

                continue
            }
            'tool' {
                if (-not $subcommandName -and -not $token.StartsWith('-', [System.StringComparison]::Ordinal)) {
                    $subcommandName = $token
                }

                continue
            }
            'work' {
                if (-not $subcommandName -and -not $token.StartsWith('-', [System.StringComparison]::Ordinal)) {
                    $subcommandName = $token
                }

                continue
            }
            'test' {
                if ($testArgsSeen) {
                    continue
                }

                if ($baseName -eq '-args') {
                    $testArgsSeen = $true
                    continue
                }

                if (Test-GoOptionRequiresValue -CommandName $commandName -OptionName $baseName) {
                    if ($token -notlike '*=*') {
                        $pendingOption = $baseName
                    }

                    continue
                }

                continue
            }
            default {
                if (Test-GoBuildFamilyCommand -CommandName $commandName) {
                    if (Test-GoOptionRequiresValue -CommandName $commandName -OptionName $baseName) {
                        if ($token -notlike '*=*') {
                            $pendingOption = $baseName
                        }

                        continue
                    }

                    continue
                }
            }
        }
    }

    [pscustomobject]@{
        Command       = $commandName
        Subcommand    = $subcommandName
        PendingOption = $pendingOption
        EnvMode       = $envMode
        TestArgsSeen  = $testArgsSeen
    }
}

function Get-GoUniqueCompletions {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )

    begin {
        $seen = @{}
    }

    process {
        foreach ($result in @($InputObject)) {
            if ($null -eq $result) {
                continue
            }

            if ($seen.ContainsKey($result.CompletionText)) {
                continue
            }

            $seen[$result.CompletionText] = $true
            $result
        }
    }
}

function Get-GoOptionCompletions {
    param(
        [string[]]$Options,
        [string]$WordToComplete
    )

    return ,@(
        foreach ($option in $Options) {
            if ([string]::IsNullOrEmpty($WordToComplete) -or $option -like "$WordToComplete*") {
                New-GoCompletionResult -CompletionText $option -ResultType ([System.Management.Automation.CompletionResultType]::ParameterName) -ToolTip "Go option $option"
            }
        }
    )
}

function Get-GoCommandCompletions {
    param(
        [string[]]$Commands,
        [string]$WordToComplete
    )

    $metadata = Get-GoRootCommandMetadata
    return ,@(
        foreach ($command in $Commands) {
            if ([string]::IsNullOrEmpty($WordToComplete) -or $command -like "$WordToComplete*") {
                New-GoCompletionResult -CompletionText $command -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip $metadata[$command]
            }
        }
    )
}

function Get-GoTopicCompletions {
    param(
        [string[]]$Topics,
        [string]$WordToComplete
    )

    $metadata = Get-GoHelpTopicMetadata
    return ,@(
        foreach ($topic in $Topics) {
            if ([string]::IsNullOrEmpty($WordToComplete) -or $topic -like "$WordToComplete*") {
                New-GoCompletionResult -CompletionText $topic -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip $metadata[$topic]
            }
        }
    )
}

function Get-GoNestedCommandCompletions {
    param(
        [string]$CommandName,
        [string[]]$NestedCommands,
        [string]$WordToComplete
    )

    $metadata = Get-GoNestedCommandMetadata -CommandName $CommandName
    return ,@(
        foreach ($name in $NestedCommands) {
            if ([string]::IsNullOrEmpty($WordToComplete) -or $name -like "$WordToComplete*") {
                New-GoCompletionResult -CompletionText $name -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip $metadata[$name]
            }
        }
    )
}

function Get-GoEnvNames {
    @(
        'CGO_ENABLED', 'GO111MODULE', 'GOARCH', 'GOAUTH', 'GOBIN', 'GOCACHE', 'GOCOVERDIR',
        'GOENV', 'GOEXE', 'GOFLAGS', 'GOHOSTARCH', 'GOHOSTOS', 'GOINSECURE', 'GOMOD',
        'GOMODCACHE', 'GONOPROXY', 'GONOSUMDB', 'GOOS', 'GOPATH', 'GOPRIVATE', 'GOPROXY',
        'GOROOT', 'GOSUMDB', 'GOTELEMETRY', 'GOTELEMETRYDIR', 'GOTOOLCHAIN', 'GOWORK'
    )
}

function Get-GoEnvWriteCompletions {
    param([string]$WordToComplete)

    $envNames = Get-GoEnvNames

    if ($WordToComplete -like '*=*') {
        $equalsIndex = $WordToComplete.IndexOf('=')
        $namePart = $WordToComplete.Substring(0, $equalsIndex)
        if ([string]::IsNullOrWhiteSpace($namePart)) {
            return New-GoCompletionResult -CompletionText '<NAME=VALUE>' -ToolTip 'Environment assignment for go env -w'
        }

        return New-GoCompletionResult -CompletionText "$namePart=<value>" -ToolTip "Set $namePart with go env -w"
    }

    $results = foreach ($name in $envNames) {
        if ([string]::IsNullOrEmpty($WordToComplete) -or $name -like "$WordToComplete*") {
            New-GoCompletionResult -CompletionText "$name=<value>" -ToolTip "Set $name with go env -w"
        }
    }

    if ($results) {
        return $results
    }

    New-GoCompletionResult -CompletionText '<NAME=VALUE>' -ToolTip 'Environment assignment for go env -w'
}

function Get-GoEnvUnsetCompletions {
    param([string]$WordToComplete)

    $results = foreach ($name in (Get-GoEnvNames)) {
        if ([string]::IsNullOrEmpty($WordToComplete) -or $name -like "$WordToComplete*") {
            New-GoCompletionResult -CompletionText $name -ToolTip "Unset $name with go env -u"
        }
    }

    if ($results) {
        return $results
    }

    New-GoCompletionResult -CompletionText '<NAME>' -ToolTip 'Environment name for go env -u'
}

function Get-GoValueCompletions {
    param(
        [string]$CommandName,
        [string]$OptionName,
        [string]$WordToComplete,
        [string]$InlinePrefix = ''
    )

    $enumValues = Get-GoEnumValues -OptionName $OptionName
    if ($enumValues.Count -gt 0) {
        return ,@(
            foreach ($value in $enumValues) {
                if ([string]::IsNullOrEmpty($WordToComplete) -or $value -like "$WordToComplete*") {
                    $completionText = if ($InlinePrefix) { $InlinePrefix + $value } else { $value }
                    New-GoCompletionResult -CompletionText $completionText -ListItemText $value -ToolTip "Value for $OptionName"
                }
            }
        )
    }

    switch ($OptionName) {
        '-C' {
            return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix -DirectoryOnly $true)
        }
        '-exec' {
            return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix)
        }
        '-modfile' {
            return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix)
        }
        '-o' {
            return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix)
        }
        '-overlay' {
            return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix)
        }
        '-pgo' {
            return ,@(
                foreach ($special in @('auto', 'off')) {
                    if ([string]::IsNullOrEmpty($WordToComplete) -or $special -like "$WordToComplete*") {
                        $completionText = if ($InlinePrefix) { $InlinePrefix + $special } else { $special }
                        New-GoCompletionResult -CompletionText $completionText -ListItemText $special -ToolTip 'Value for -pgo'
                    }
                }

                Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix
            )
        }
        '-pkgdir' {
            return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix -DirectoryOnly $true)
        }
    }

    $placeholder = Get-GoValuePlaceholder -OptionName $OptionName
    if ($InlinePrefix) {
        return ,@(New-GoCompletionResult -CompletionText ($InlinePrefix + $placeholder) -ListItemText $placeholder -ToolTip "Value for $OptionName")
    }

    return ,@(New-GoCompletionResult -CompletionText $placeholder -ToolTip "Value for $OptionName")
}

Register-ArgumentCompleter -Native -CommandName @('go', 'go.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $state = Get-GoCommandState -CommandAst $commandAst -CursorPosition $cursorPosition -FallbackWordToComplete $wordToComplete
    $currentWord = $state.CurrentWord
    $priorTokens = $state.PriorTokens
    $context = Get-GoCommandContext -Tokens $priorTokens

    if ($context.Command -eq 'test' -and $context.TestArgsSeen) {
        New-GoCompletionResult -CompletionText '<test-binary-arg>' -ToolTip 'Argument passed through after go test -args'
        return
    }

    if ($currentWord -like '-*=*') {
        $equalsIndex = $currentWord.IndexOf('=')
        $flagPart = $currentWord.Substring(0, $equalsIndex)
        $valuePart = $currentWord.Substring($equalsIndex + 1)

        if (-not $context.Command -and $flagPart -eq '-C') {
            Get-GoPathCompletions -InputText $valuePart -InlinePrefix '-C=' -DirectoryOnly $true | Get-GoUniqueCompletions
            return
        }

        Get-GoValueCompletions -CommandName $context.Command -OptionName $flagPart -WordToComplete $valuePart -InlinePrefix ($flagPart + '=') |
            Get-GoUniqueCompletions
        return
    }

    if (-not $context.Command) {
        if ($context.PendingOption -eq '-C') {
            Get-GoPathCompletions -InputText $currentWord -DirectoryOnly $true | Get-GoUniqueCompletions
            return
        }

        $rootResults = New-Object System.Collections.Generic.List[object]
        if ([string]::IsNullOrEmpty($currentWord) -or $currentWord -like '-*') {
            foreach ($item in @(Get-GoOptionCompletions -Options @('-C') -WordToComplete $currentWord)) {
                [void]$rootResults.Add($item)
            }
        }

        if (-not ($currentWord -like '-*')) {
            foreach ($item in @(Get-GoCommandCompletions -Commands (Get-GoRootCommands) -WordToComplete $currentWord)) {
                [void]$rootResults.Add($item)
            }
        }

        $rootResults | Get-GoUniqueCompletions

        return
    }

    switch ($context.Command) {
        'env' {
            if ($context.EnvMode -eq 'w' -or $context.PendingOption -eq '-w') {
                Get-GoEnvWriteCompletions -WordToComplete $currentWord | Get-GoUniqueCompletions
                return
            }

            if ($context.EnvMode -eq 'u' -or $context.PendingOption -eq '-u') {
                Get-GoEnvUnsetCompletions -WordToComplete $currentWord | Get-GoUniqueCompletions
                return
            }

            if ([string]::IsNullOrEmpty($currentWord) -or $currentWord -like '-*') {
                Get-GoOptionCompletions -Options (Get-GoCommandFlags -CommandName 'env') -WordToComplete $currentWord |
                    Get-GoUniqueCompletions
            }

            return
        }
        'help' {
            if (-not $context.Subcommand) {
                $helpResults = New-Object System.Collections.Generic.List[object]
                foreach ($item in @(Get-GoCommandCompletions -Commands (Get-GoRootCommands) -WordToComplete $currentWord)) {
                    [void]$helpResults.Add($item)
                }

                foreach ($item in @(Get-GoTopicCompletions -Topics (Get-GoHelpTopics) -WordToComplete $currentWord)) {
                    [void]$helpResults.Add($item)
                }

                $helpResults | Get-GoUniqueCompletions
            }

            return
        }
        'mod' {
            if (-not $context.Subcommand) {
                Get-GoNestedCommandCompletions -CommandName 'mod' -NestedCommands (Get-GoNestedCommands -CommandName 'mod') -WordToComplete $currentWord |
                    Get-GoUniqueCompletions
            }

            return
        }
        'telemetry' {
            if (-not $context.Subcommand) {
                Get-GoNestedCommandCompletions -CommandName 'telemetry' -NestedCommands (Get-GoNestedCommands -CommandName 'telemetry') -WordToComplete $currentWord |
                    Get-GoUniqueCompletions
            }

            return
        }
        'tool' {
            if (-not $context.Subcommand) {
                $tools = Get-GoToolNames
                if ($tools.Count -gt 0) {
                    foreach ($toolName in $tools) {
                        if ([string]::IsNullOrEmpty($currentWord) -or $toolName -like "$currentWord*") {
                            New-GoCompletionResult -CompletionText $toolName -ToolTip 'Installed go tool'
                        }
                    }
                } else {
                    New-GoCompletionResult -CompletionText '<tool-name>' -ToolTip 'go tool name'
                }
            }

            return
        }
        'work' {
            if (-not $context.Subcommand) {
                Get-GoNestedCommandCompletions -CommandName 'work' -NestedCommands (Get-GoNestedCommands -CommandName 'work') -WordToComplete $currentWord |
                    Get-GoUniqueCompletions
            }

            return
        }
        default {
            if ($context.PendingOption) {
                Get-GoValueCompletions -CommandName $context.Command -OptionName $context.PendingOption -WordToComplete $currentWord |
                    Get-GoUniqueCompletions
                return
            }

            if ([string]::IsNullOrEmpty($currentWord) -or $currentWord -like '-*') {
                Get-GoOptionCompletions -Options (Get-GoCommandFlags -CommandName $context.Command) -WordToComplete $currentWord |
                    Get-GoUniqueCompletions
            }

            return
        }
    }
}
