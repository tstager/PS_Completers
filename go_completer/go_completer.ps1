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
        HelpModels         = @{}
        ToolNames          = $null
        EnvNames           = $null
        WorkingDirectory   = $null
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

function Get-GoFallbackToolNames {
    @(
        'asm', 'cgo', 'compile', 'covdata', 'cover', 'doc', 'fix', 'link',
        'nm', 'objdump', 'pack', 'pprof', 'preprofile', 'test2json', 'trace', 'vet'
    )
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

function Reset-GoCacheForLocation {
    # go tool output is module-scoped, so a cache built in one module must not be
    # reused in another.
    $cache = Get-GoCompletionCache
    $location = (Get-Location).Path
    if ($cache.WorkingDirectory -ne $location) {
        $cache.WorkingDirectory = $location
        $cache.TextByKey = @{}
        $cache.HelpModels = @{}
        $cache.ToolNames = $null
        $cache.EnvNames = $null
    }
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
        # Standard input is closed so a tool that reads it cannot hang the prompt.
        $text = ($null | & $goPath @Arguments 2>&1 | Out-String -Width 4096)
    } catch {
        $text = ''
    }

    if ($null -eq $text) {
        $text = ''
    }

    $cache.TextByKey[$CacheKey] = $text
    $text
}

function Get-GoBuildModeValues {
    $known = @('archive', 'c-archive', 'c-shared', 'default', 'shared', 'exe', 'pie', 'plugin')
    $text = Get-GoText -CacheKey 'help:buildmode' -Arguments @('help', 'buildmode')
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $known
    }

    $found = @($known | Where-Object { [regex]::IsMatch($text, "(?<![A-Za-z0-9_.-])$([regex]::Escape($_))(?![A-Za-z0-9_.-])") })
    if ($found.Count -eq 0) {
        return $known
    }

    $found
}

function Get-GoEnumValues {
    param([string]$OptionName)

    # go documents these value sets in prose rather than in a machine-readable
    # shape, so they stay explicit; the audit confirmed each one matches go1.27.
    switch ($OptionName) {
        '-buildmode' { return Get-GoBuildModeValues }
        '-buildvcs'  { return @('auto', 'true', 'false') }
        '-compiler'  { return @('gc', 'gccgo') }
        '-covermode' { return @('set', 'count', 'atomic') }
        '-mod'       { return @('readonly', 'vendor', 'mod') }
    }

    return ,@()
}

function Add-GoHelpFlag {
    param(
        [System.Collections.Specialized.OrderedDictionary]$Flags,
        [string]$Name,
        [string]$ValueName,
        [bool]$Authoritative
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return
    }

    # A value spec that is not a plain identifier (a quoted list, a bracketed
    # pattern) is still a value, but its name is not worth showing.
    if (-not [string]::IsNullOrWhiteSpace($ValueName) -and $ValueName -notmatch '^[A-Za-z][A-Za-z0-9_.,-]*$') {
        $ValueName = 'value'
    }

    $values = @(Get-GoEnumValues -OptionName $Name)

    if ($Flags.Contains($Name)) {
        if (-not $Authoritative) {
            return
        }

        $existing = $Flags[$Name]
        if ([string]::IsNullOrWhiteSpace($existing.ValueName) -and -not [string]::IsNullOrWhiteSpace($ValueName)) {
            $existing.ValueName = $ValueName
            $existing.TakesValue = $true
        }

        if (@($existing.Values).Count -eq 0 -and $values.Count -gt 0) {
            $existing.Values = $values
        }

        return
    }

    $Flags[$Name] = [pscustomobject]@{
        Name       = $Name
        TakesValue = (-not [string]::IsNullOrWhiteSpace($ValueName))
        ValueName  = $ValueName
        Values     = $values
    }
}

function ConvertFrom-GoHelpText {
    param(
        [string]$Text,
        [int]$CommandDepth = 0
    )

    $flags = [ordered]@{}
    $commands = [ordered]@{}
    $topics = [ordered]@{}
    $operands = New-Object System.Collections.Generic.List[string]
    $choices = New-Object System.Collections.Generic.List[string]
    $usage = ''
    $includesBuildFlags = $false

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [pscustomobject]@{
            Usage              = $usage
            IncludesBuildFlags = $includesBuildFlags
            Flags              = $flags
            Commands           = $commands
            Topics             = $topics
            Operands           = @()
            Choices            = @()
        }
    }

    $lines = @([regex]::Split($Text, '\r?\n'))
    $section = ''

    foreach ($line in $lines) {
        if ($line -match '^usage:\s+go\s+(?<rest>.*)$' -and [string]::IsNullOrEmpty($usage)) {
            $usage = $Matches.rest
            continue
        }

        if ($line -match '^The commands are:\s*$' -or $line -match '^The subcommands are:\s*$') {
            $section = 'Commands'
            continue
        }

        if ($line -match '^Additional help topics:\s*$') {
            $section = 'Topics'
            continue
        }

        if ($line -match '^\S' -and $line -notmatch '^usage:') {
            $section = ''
        }

        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($section -eq 'Commands' -or $section -eq 'Topics') {
            # The gap collapses to a single space when the name is the longest in
            # the table, as "buildconstraint" is under Additional help topics.
            if ($line -match '^\s+(?<name>[a-z][a-z0-9._-]*)\s+(?<description>\S.*)$') {
                if ($section -eq 'Commands') {
                    $commands[$Matches.name] = $Matches.description.Trim()
                } else {
                    $topics[$Matches.name] = $Matches.description.Trim()
                }
            }

            continue
        }

        # An indented flag definition ("\t-a", "\t-p n", "\t-ldflags '[pattern=]arg
        # list'"). go indents these by one tab or two spaces and indents their
        # description lines further, which is what separates them from prose.
        if ($line -match '^[ \t]{1,3}-{1,2}(?<name>[A-Za-z][A-Za-z0-9_-]*)(?<rest>([ =].*)?)$') {
            $flagName = '-' + $Matches.name
            $flagValue = $Matches.rest.Trim().TrimStart('=').Trim()
            if ($flagValue -match '^(?<first>\S+)') {
                $flagValue = $Matches.first
            }

            Add-GoHelpFlag -Flags $flags -Name $flagName -ValueName $flagValue -Authoritative $true
        }
    }

    if (-not [string]::IsNullOrEmpty($usage)) {
        $includesBuildFlags = $usage -match '\[build(?:/test)? flags'

        foreach ($group in [regex]::Matches($usage, '\[(?<body>[^\]]+)\]')) {
            $body = $group.Groups['body'].Value
            if ($body -notmatch '(?<!\S)-') {
                if ($body -match '^\s*flags?\s*$' -or $body -match 'flags\s*$') {
                    continue
                }

                $alternatives = @($body -split '\s*\|\s*' | ForEach-Object { $_.Trim() })
                if ($alternatives.Count -gt 1 -and @($alternatives | Where-Object { $_ -match '^[a-z][a-z0-9._-]*$' }).Count -eq $alternatives.Count) {
                    # A literal alternation such as "go telemetry [off|local|on]".
                    foreach ($choice in $alternatives) {
                        [void]$choices.Add($choice)
                    }

                    continue
                }

                foreach ($operand in $alternatives) {
                    [void]$operands.Add($operand)
                }

                continue
            }

            foreach ($alternative in ($body -split '\s*\|\s*')) {
                if ($alternative -notmatch '^\s*-{1,2}(?<name>[A-Za-z][A-Za-z0-9_-]*)(?<rest>.*)$') {
                    continue
                }

                $flagName = '-' + $Matches.name
                $rest = $Matches.rest.Trim().TrimStart('=').Trim()
                $valueName = ''
                if ($rest -match '^(?<value>\S+)') {
                    $valueName = $Matches.value
                }

                Add-GoHelpFlag -Flags $flags -Name $flagName -ValueName $valueName -Authoritative $false
            }
        }

        # Bare operands outside brackets, minus the command path itself:
        # "go run [build flags] [-exec xprog] package [arguments...]".
        $bare = @([regex]::Replace($usage, '\[[^\]]*\]', ' ') -split '\s+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        foreach ($token in ($bare | Select-Object -Skip $CommandDepth)) {
            if ($token -notmatch '^-') {
                [void]$operands.Add($token)
            }
        }
    }

    # Prose: "The -n flag prints commands that would be executed."
    foreach ($group in [regex]::Matches($Text, '(?<!\S)-{1,2}(?<name>[a-z][a-z0-9_-]*)(?:=(?<value>\S+?))?\s+flag')) {
        $valueName = if ($group.Groups['value'].Success) { $group.Groups['value'].Value } else { '' }
        Add-GoHelpFlag -Flags $flags -Name ('-' + $group.Groups['name'].Value) -ValueName $valueName -Authoritative $false
    }

    [pscustomobject]@{
        Usage              = $usage
        IncludesBuildFlags = $includesBuildFlags
        Flags              = $flags
        Commands           = $commands
        Topics             = $topics
        Operands           = @($operands.ToArray())
        Choices            = @($choices.ToArray())
    }
}

function Get-GoHelpModel {
    param([string[]]$Path)

    $cache = Get-GoCompletionCache
    $segments = @(@($Path) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $key = if ($segments.Count -gt 0) { $segments -join ' ' } else { '<root>' }

    if ($cache.HelpModels.ContainsKey($key)) {
        return $cache.HelpModels[$key]
    }

    $text = Get-GoText -CacheKey "help:$key" -Arguments (@('help') + $segments)
    if ($segments.Count -eq 1 -and $segments[0] -eq 'test') {
        # go test's own flags live in 'go help testflag', not in 'go help test'.
        $text += "`n" + (Get-GoText -CacheKey 'help:testflag' -Arguments @('help', 'testflag'))
    }

    $model = ConvertFrom-GoHelpText -Text $text -CommandDepth $segments.Count
    $cache.HelpModels[$key] = $model
    $model
}

function Get-GoRootCommands {
    $model = Get-GoHelpModel -Path @()
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($name in @($model.Commands.Keys)) {
        [void]$names.Add($name)
    }

    # 'go help' does not list 'help' itself.
    foreach ($name in @((Get-GoRootCommandMetadata).Keys)) {
        if (-not $names.Contains($name)) {
            [void]$names.Add($name)
        }
    }

    @($names.ToArray())
}

function Get-GoHelpTopics {
    $model = Get-GoHelpModel -Path @()
    $names = @($model.Topics.Keys)
    if ($names.Count -gt 0) {
        return $names
    }

    @((Get-GoHelpTopicMetadata).Keys)
}

function Get-GoCommandDescription {
    param([string]$Name)

    $model = Get-GoHelpModel -Path @()
    if ($model.Commands.Contains($Name)) {
        return $model.Commands[$Name]
    }

    $metadata = Get-GoRootCommandMetadata
    if ($metadata.Contains($Name)) {
        return $metadata[$Name]
    }

    "go $Name"
}

function Get-GoNestedCommands {
    param([string]$CommandName)

    @((Get-GoHelpModel -Path @($CommandName)).Commands.Keys)
}

function Get-GoNestedCommandDescription {
    param(
        [string]$CommandName,
        [string]$Name
    )

    $model = Get-GoHelpModel -Path @($CommandName)
    if ($model.Commands.Contains($Name)) {
        return $model.Commands[$Name]
    }

    "go $CommandName $Name"
}

function Get-GoBuildFlagModel {
    (Get-GoHelpModel -Path @('build')).Flags
}

function Get-GoToolNames {
    $cache = Get-GoCompletionCache
    if ($null -ne $cache.ToolNames) {
        return $cache.ToolNames
    }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($line in ([regex]::Split((Get-GoText -CacheKey 'tool' -Arguments @('tool')), '\r?\n'))) {
        $candidate = $line.Trim()
        if ($candidate -match '^[a-z][a-z0-9./_-]*$') {
            [void]$names.Add($candidate)
        }
    }

    if ($names.Count -eq 0) {
        $cache.ToolNames = Get-GoFallbackToolNames
    } else {
        $cache.ToolNames = @($names.ToArray())
    }

    $cache.ToolNames
}

function Get-GoEnvNames {
    $cache = Get-GoCompletionCache
    if ($null -ne $cache.EnvNames) {
        return $cache.EnvNames
    }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($line in ([regex]::Split((Get-GoText -CacheKey 'env' -Arguments @('env')), '\r?\n'))) {
        if ($line -match '^\s*(?:set\s+)?(?<name>[A-Z][A-Z0-9_]*)=') {
            [void]$names.Add($Matches.name)
        }
    }

    if ($names.Count -eq 0) {
        $cache.EnvNames = @(
            'CGO_ENABLED', 'GO111MODULE', 'GOARCH', 'GOAUTH', 'GOBIN', 'GOCACHE', 'GOCOVERDIR',
            'GOENV', 'GOEXE', 'GOFLAGS', 'GOHOSTARCH', 'GOHOSTOS', 'GOINSECURE', 'GOMOD',
            'GOMODCACHE', 'GONOPROXY', 'GONOSUMDB', 'GOOS', 'GOPATH', 'GOPRIVATE', 'GOPROXY',
            'GOROOT', 'GOSUMDB', 'GOTELEMETRY', 'GOTELEMETRYDIR', 'GOTOOLCHAIN', 'GOWORK'
        )
    } else {
        $cache.EnvNames = @($names.ToArray() | Sort-Object -Unique)
    }

    $cache.EnvNames
}

function Get-GoResolvedFlagModel {
    param([string[]]$Path)

    $model = Get-GoHelpModel -Path $Path
    $merged = [ordered]@{}

    foreach ($name in @($model.Flags.Keys)) {
        $merged[$name] = $model.Flags[$name]
    }

    if ($model.IncludesBuildFlags) {
        $buildFlags = Get-GoBuildFlagModel
        foreach ($name in @($buildFlags.Keys)) {
            # -C must be the first argument on the command line, so it belongs to
            # the root position rather than to a command's own flag set.
            if ($name -eq '-C' -or $merged.Contains($name)) {
                continue
            }

            $merged[$name] = $buildFlags[$name]
        }
    }

    $merged
}

function Get-GoOptionBaseName {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    # go's flag package accepts -flag and --flag interchangeably.
    $normalized = if ($Token -match '^--[^-]') { $Token.Substring(1) } else { $Token }

    if ($normalized -match '^(?<name>-[^=]+)=') {
        return $Matches['name']
    }

    $normalized
}

function Get-GoValuePlaceholder {
    param(
        [string]$OptionName,
        [object]$FlagSpec
    )

    if ($null -ne $FlagSpec -and -not [string]::IsNullOrWhiteSpace($FlagSpec.ValueName)) {
        return '<' + $FlagSpec.ValueName + '>'
    }

    switch ($OptionName) {
        '-exec'    { return '<command>' }
        '-timeout' { return '<duration>' }
        default    { return '<value>' }
    }
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
            # CompleteFilename applies its own quoting; strip it before applying
            # the quoting style the user actually typed.
            $completionText = ConvertTo-GoQuotedValue -Value (Remove-GoOuterQuotes -InputText $_.CompletionText) -QuoteCharacter $quoteCharacter
            if ($InlinePrefix) {
                $completionText = $InlinePrefix + $completionText
            }

            New-GoCompletionResult -CompletionText $completionText -ListItemText $_.ListItemText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }

    Write-Output -NoEnumerate @($completions)
}

function Split-GoCommandLine {
    param([string]$Text)

    # A quote-aware splitter. An unterminated quote runs to the end of the input,
    # which is exactly what happens while the user is still typing a quoted path
    # that contains a space.
    $tokens = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrEmpty($Text)) {
        return @()
    }

    $builder = New-Object System.Text.StringBuilder
    $started = $false
    $quote = [char]0

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]

        if ($quote -ne [char]0) {
            [void]$builder.Append($character)
            if ($character -eq $quote) {
                $quote = [char]0
            }

            continue
        }

        if ($character -eq '"' -or $character -eq "'") {
            $quote = $character
            $started = $true
            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character)) {
            if ($started) {
                [void]$tokens.Add($builder.ToString())
                [void]$builder.Clear()
                $started = $false
            }

            continue
        }

        $started = $true
        [void]$builder.Append($character)
    }

    if ($started) {
        [void]$tokens.Add($builder.ToString())
    }

    @($tokens.ToArray())
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

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $line.Length)
    $prefix = $line.Substring(0, $safeCursor)
    $hasTrailingSpace = ($prefix -match '\s$') -or ($CommandAst.Extent -and $CursorPosition -gt $line.Length)
    $allTokens = @(Split-GoCommandLine -Text $prefix)

    if ($hasTrailingSpace) {
        $currentWord = ''
        $priorTokens = if ($allTokens.Count -gt 1) {
            @($allTokens | Select-Object -Skip 1)
        } else {
            @()
        }
    } else {
        $currentWord = if ($allTokens.Count -gt 0) {
            $allTokens[$allTokens.Count - 1]
        } else {
            $FallbackWordToComplete
        }

        $priorTokens = if ($allTokens.Count -gt 2) {
            @($allTokens | Select-Object -Skip 1 -First ($allTokens.Count - 2))
        } else {
            @()
        }
    }

    [pscustomobject]@{
        CurrentWord = $currentWord
        PriorTokens = $priorTokens
    }
}

function Test-GoOptionRequiresValue {
    param(
        [System.Collections.Specialized.OrderedDictionary]$FlagModel,
        [string]$OptionName
    )

    if ([string]::IsNullOrWhiteSpace($OptionName) -or $null -eq $FlagModel) {
        return $false
    }

    if (-not $FlagModel.Contains($OptionName)) {
        return $false
    }

    [bool]$FlagModel[$OptionName].TakesValue
}

function Get-GoCommandContext {
    param([string[]]$Tokens)

    $rootCommands = Get-GoRootCommands
    $pendingOption = $null
    $commandName = $null
    $subcommandName = $null
    $envMode = $null
    $testArgsSeen = $false
    $operandCount = 0
    $flagModel = $null

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
                $flagModel = Get-GoResolvedFlagModel -Path @($commandName)
            }

            continue
        }

        if ($commandName -eq 'test' -and $testArgsSeen) {
            continue
        }

        if ($commandName -eq 'test' -and $baseName -eq '-args') {
            $testArgsSeen = $true
            continue
        }

        if ($token.StartsWith('-', [System.StringComparison]::Ordinal)) {
            if ($commandName -eq 'env') {
                if ($baseName -eq '-w') { $envMode = 'w' }
                if ($baseName -eq '-u') { $envMode = 'u' }
            }

            if (($token -notlike '*=*') -and (Test-GoOptionRequiresValue -FlagModel $flagModel -OptionName $baseName)) {
                $pendingOption = $baseName
            }

            continue
        }

        if (-not $subcommandName -and @((Get-GoHelpModel -Path @($commandName)).Commands.Keys).Count -gt 0) {
            $subcommandName = $token
            if ($commandName -ne 'help' -and $commandName -ne 'tool') {
                $flagModel = Get-GoResolvedFlagModel -Path @($commandName, $subcommandName)
            }

            continue
        }

        if (-not $subcommandName -and ($commandName -eq 'help' -or $commandName -eq 'tool')) {
            $subcommandName = $token
            continue
        }

        $operandCount++
    }

    if ($null -eq $flagModel) {
        $flagModel = [ordered]@{}
    }

    [pscustomobject]@{
        Command       = $commandName
        Subcommand    = $subcommandName
        PendingOption = $pendingOption
        EnvMode       = $envMode
        TestArgsSeen  = $testArgsSeen
        OperandCount  = $operandCount
        FlagModel     = $flagModel
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
        [System.Collections.Specialized.OrderedDictionary]$FlagModel,
        [string]$WordToComplete
    )

    # go accepts --flag as well as -flag, so a typed -- keeps the -- spelling.
    $doubleDash = $WordToComplete -match '^--[^-]|^--$'
    $needle = if ($WordToComplete -match '^--[^-]') { $WordToComplete.Substring(1) } elseif ($WordToComplete -eq '--') { '-' } else { $WordToComplete }

    return ,@(
        foreach ($name in @($FlagModel.Keys)) {
            if ([string]::IsNullOrEmpty($needle) -or $name -clike ([System.Management.Automation.WildcardPattern]::Escape($needle) + '*')) {
                $text = if ($doubleDash) { '-' + $name } else { $name }
                $spec = $FlagModel[$name]
                $toolTip = if ($spec.TakesValue) { "go option $name <$($spec.ValueName)>" } else { "go option $name" }
                New-GoCompletionResult -CompletionText $text -ListItemText $text -ResultType ([System.Management.Automation.CompletionResultType]::ParameterName) -ToolTip $toolTip
            }
        }
    )
}

function Get-GoCommandCompletions {
    param(
        [string[]]$Commands,
        [string]$WordToComplete
    )

    return ,@(
        foreach ($command in $Commands) {
            if ([string]::IsNullOrEmpty($WordToComplete) -or $command -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
                New-GoCompletionResult -CompletionText $command -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip (Get-GoCommandDescription -Name $command)
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
    $model = Get-GoHelpModel -Path @()
    return ,@(
        foreach ($topic in $Topics) {
            if ([string]::IsNullOrEmpty($WordToComplete) -or $topic -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
                $toolTip = if ($model.Topics.Contains($topic)) {
                    $model.Topics[$topic]
                } elseif ($metadata.Contains($topic)) {
                    $metadata[$topic]
                } else {
                    "go help $topic"
                }

                New-GoCompletionResult -CompletionText $topic -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip $toolTip
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

    return ,@(
        foreach ($name in $NestedCommands) {
            if ([string]::IsNullOrEmpty($WordToComplete) -or $name -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
                New-GoCompletionResult -CompletionText $name -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip (Get-GoNestedCommandDescription -CommandName $CommandName -Name $name)
            }
        }
    )
}

function Get-GoEnvWriteCompletions {
    param([string]$WordToComplete)

    if ($WordToComplete -like '*=*') {
        $equalsIndex = $WordToComplete.IndexOf('=')
        $namePart = $WordToComplete.Substring(0, $equalsIndex)
        if ([string]::IsNullOrWhiteSpace($namePart)) {
            return New-GoCompletionResult -CompletionText '<NAME=VALUE>' -ToolTip 'Environment assignment for go env -w'
        }

        return New-GoCompletionResult -CompletionText "$namePart=<value>" -ToolTip "Set $namePart with go env -w"
    }

    $results = foreach ($name in (Get-GoEnvNames)) {
        if ([string]::IsNullOrEmpty($WordToComplete) -or $name -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
            New-GoCompletionResult -CompletionText "$name=<value>" -ListItemText $name -ToolTip "Set $name with go env -w"
        }
    }

    if ($results) {
        return $results
    }

    New-GoCompletionResult -CompletionText '<NAME=VALUE>' -ToolTip 'Environment assignment for go env -w'
}

function Get-GoEnvNameCompletions {
    param(
        [string]$WordToComplete,
        [string]$ToolTipVerb = 'Read'
    )

    $results = foreach ($name in (Get-GoEnvNames)) {
        if ([string]::IsNullOrEmpty($WordToComplete) -or $name -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
            New-GoCompletionResult -CompletionText $name -ToolTip "$ToolTipVerb $name"
        }
    }

    if ($results) {
        return $results
    }

    New-GoCompletionResult -CompletionText '<NAME>' -ToolTip 'Go environment variable name'
}

function Get-GoPackagePatternCompletions {
    param([string]$WordToComplete)

    # 'go help packages' documents these reserved patterns; everything else is an
    # import path, for which the directory tree is the useful local source.
    $patterns = [ordered]@{
        './...' = 'the package in the current directory and all subdirectories'
        '.'     = 'the package in the current directory'
        'all'   = 'all packages in the main module and their dependencies'
        'std'   = 'the packages in the Go standard library'
        'cmd'   = 'the Go command and its internal packages'
        'tool'  = 'the tool dependencies of the main module'
    }

    return ,@(
        foreach ($pattern in @($patterns.Keys)) {
            if ([string]::IsNullOrEmpty($WordToComplete) -or $pattern -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
                New-GoCompletionResult -CompletionText $pattern -ToolTip $patterns[$pattern]
            }
        }
    )
}

function Get-GoModuleVersionCompletions {
    param([string]$WordToComplete)

    $atIndex = $WordToComplete.LastIndexOf('@')
    if ($atIndex -lt 0) {
        return ,@()
    }

    $prefix = $WordToComplete.Substring(0, $atIndex + 1)
    $typed = $WordToComplete.Substring($atIndex + 1)
    $queries = [ordered]@{
        'latest'  = 'the latest release version'
        'upgrade' = 'the latest version, or the current one if it is newer'
        'patch'   = 'the latest patch release of the current major.minor'
        'none'    = 'remove the dependency'
    }

    return ,@(
        foreach ($query in @($queries.Keys)) {
            if ([string]::IsNullOrEmpty($typed) -or $query -like ([System.Management.Automation.WildcardPattern]::Escape($typed) + '*')) {
                New-GoCompletionResult -CompletionText ($prefix + $query) -ListItemText $query -ToolTip $queries[$query]
            }
        }
    )
}

function Get-GoValueCompletions {
    param(
        [object]$FlagSpec,
        [string]$OptionName,
        [string]$WordToComplete,
        [string]$InlinePrefix = ''
    )

    $enumValues = if ($null -eq $FlagSpec) { @() } else { @($FlagSpec.Values) }
    if ($enumValues.Count -gt 0) {
        return ,@(
            foreach ($value in $enumValues) {
                if ([string]::IsNullOrEmpty($WordToComplete) -or $value -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
                    $completionText = if ($InlinePrefix) { $InlinePrefix + $value } else { $value }
                    New-GoCompletionResult -CompletionText $completionText -ListItemText $value -ToolTip "Value for $OptionName"
                }
            }
        )
    }

    switch ($OptionName) {
        '-C'       { return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix -DirectoryOnly $true) }
        '-exec'    { return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix) }
        '-modfile' { return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix) }
        '-o'       { return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix) }
        '-overlay' { return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix) }
        '-outputdir' { return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix -DirectoryOnly $true) }
        '-pkgdir'  { return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix -DirectoryOnly $true) }
        '-coverprofile' { return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix) }
        '-vettool' { return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix) }
        '-fixtool' { return ,@(Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix) }
        '-pgo' {
            return ,@(
                foreach ($special in @('auto', 'off')) {
                    if ([string]::IsNullOrEmpty($WordToComplete) -or $special -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
                        $completionText = if ($InlinePrefix) { $InlinePrefix + $special } else { $special }
                        New-GoCompletionResult -CompletionText $completionText -ListItemText $special -ToolTip 'Value for -pgo'
                    }
                }

                Get-GoPathCompletions -InputText $WordToComplete -InlinePrefix $InlinePrefix
            )
        }
        '-coverpkg' { return ,@(Get-GoPackagePatternCompletions -WordToComplete $WordToComplete) }
    }

    if (-not [string]::IsNullOrEmpty($WordToComplete)) {
        return ,@()
    }

    $placeholder = Get-GoValuePlaceholder -OptionName $OptionName -FlagSpec $FlagSpec
    if ($InlinePrefix) {
        return ,@(New-GoCompletionResult -CompletionText ($InlinePrefix + $placeholder) -ListItemText $placeholder -ToolTip "Value for $OptionName")
    }

    return ,@(New-GoCompletionResult -CompletionText $placeholder -ToolTip "Value for $OptionName")
}

function Get-GoOperandCompletions {
    param(
        [object]$Context,
        [string]$WordToComplete
    )

    $path = @($Context.Command)
    if ($Context.Subcommand -and $Context.Command -ne 'help' -and $Context.Command -ne 'tool') {
        $path = @($Context.Command, $Context.Subcommand)
    }

    $model = Get-GoHelpModel -Path $path
    $operands = @($model.Operands)
    $operandText = $operands -join ' '

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($choice in @($model.Choices)) {
        if ([string]::IsNullOrEmpty($WordToComplete) -or $choice -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
            [void]$results.Add((New-GoCompletionResult -CompletionText $choice -ToolTip "go $($path -join ' ') $choice"))
        }
    }

    if (@($model.Choices).Count -gt 0) {
        return $results.ToArray()
    }

    if ($WordToComplete.Contains('@') -and $operandText -match 'package') {
        foreach ($item in @(Get-GoModuleVersionCompletions -WordToComplete $WordToComplete)) {
            [void]$results.Add($item)
        }

        return $results.ToArray()
    }

    if ($operandText -match 'package') {
        foreach ($item in @(Get-GoPackagePatternCompletions -WordToComplete $WordToComplete)) {
            [void]$results.Add($item)
        }
    }

    if ($operandText -match 'var\b') {
        foreach ($item in @(Get-GoEnvNameCompletions -WordToComplete $WordToComplete)) {
            [void]$results.Add($item)
        }

        return $results.ToArray()
    }

    if ($operandText -match 'package|file|dir|moddirs|\.go') {
        foreach ($item in @(Get-GoPathCompletions -InputText $WordToComplete -DirectoryOnly ($operandText -match 'moddirs|dir\b'))) {
            [void]$results.Add($item)
        }
    }

    $results.ToArray()
}

Register-ArgumentCompleter -Native -CommandName @('go', 'go.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Reset-GoCacheForLocation

    # $cursorPosition is an offset into the whole input line; the extent text is
    # command-relative.
    $state = Get-GoCommandState -CommandAst $commandAst -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -FallbackWordToComplete $wordToComplete
    $currentWord = $state.CurrentWord
    $context = Get-GoCommandContext -Tokens $state.PriorTokens

    if ($context.Command -eq 'test' -and $context.TestArgsSeen) {
        New-GoCompletionResult -CompletionText '<test-binary-arg>' -ToolTip 'Argument passed through after go test -args'
        return
    }

    if ($currentWord -like '-*=*') {
        $equalsIndex = $currentWord.IndexOf('=')
        $flagPart = Get-GoOptionBaseName -Token $currentWord.Substring(0, $equalsIndex)
        $valuePart = $currentWord.Substring($equalsIndex + 1)
        $typedFlag = $currentWord.Substring(0, $equalsIndex)

        if (-not $context.Command -and $flagPart -eq '-C') {
            Get-GoPathCompletions -InputText $valuePart -InlinePrefix ($typedFlag + '=') -DirectoryOnly $true | Get-GoUniqueCompletions
            return
        }

        $spec = if ($context.FlagModel.Contains($flagPart)) { $context.FlagModel[$flagPart] } else { $null }
        Get-GoValueCompletions -FlagSpec $spec -OptionName $flagPart -WordToComplete $valuePart -InlinePrefix ($typedFlag + '=') |
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
            $rootFlags = [ordered]@{}
            $buildFlags = Get-GoBuildFlagModel
            if ($buildFlags.Contains('-C')) {
                $rootFlags['-C'] = $buildFlags['-C']
            } else {
                $rootFlags['-C'] = [pscustomobject]@{ Name = '-C'; TakesValue = $true; ValueName = 'dir'; Values = @() }
            }

            foreach ($item in @(Get-GoOptionCompletions -FlagModel $rootFlags -WordToComplete $currentWord)) {
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

    if ($context.PendingOption) {
        if ($context.Command -eq 'env' -and $context.EnvMode -eq 'w') {
            Get-GoEnvWriteCompletions -WordToComplete $currentWord | Get-GoUniqueCompletions
            return
        }

        if ($context.Command -eq 'env' -and $context.EnvMode -eq 'u') {
            Get-GoEnvNameCompletions -WordToComplete $currentWord -ToolTipVerb 'Unset' | Get-GoUniqueCompletions
            return
        }

        $spec = if ($context.FlagModel.Contains($context.PendingOption)) { $context.FlagModel[$context.PendingOption] } else { $null }
        Get-GoValueCompletions -FlagSpec $spec -OptionName $context.PendingOption -WordToComplete $currentWord |
            Get-GoUniqueCompletions
        return
    }

    if ($context.Command -eq 'env' -and $context.EnvMode -eq 'w' -and -not ($currentWord -like '-*')) {
        Get-GoEnvWriteCompletions -WordToComplete $currentWord | Get-GoUniqueCompletions
        return
    }

    if ($context.Command -eq 'env' -and $context.EnvMode -eq 'u' -and -not ($currentWord -like '-*')) {
        Get-GoEnvNameCompletions -WordToComplete $currentWord -ToolTipVerb 'Unset' | Get-GoUniqueCompletions
        return
    }

    if ($currentWord -like '-*') {
        Get-GoOptionCompletions -FlagModel $context.FlagModel -WordToComplete $currentWord | Get-GoUniqueCompletions
        return
    }

    if ($context.Command -eq 'help' -and -not $context.Subcommand) {
        $helpResults = New-Object System.Collections.Generic.List[object]
        foreach ($item in @(Get-GoCommandCompletions -Commands (Get-GoRootCommands) -WordToComplete $currentWord)) {
            [void]$helpResults.Add($item)
        }

        foreach ($item in @(Get-GoTopicCompletions -Topics (Get-GoHelpTopics) -WordToComplete $currentWord)) {
            [void]$helpResults.Add($item)
        }

        $helpResults | Get-GoUniqueCompletions
        return
    }

    if ($context.Command -eq 'tool' -and -not $context.Subcommand) {
        $tools = @(Get-GoToolNames)
        $toolResults = foreach ($toolName in $tools) {
            if ([string]::IsNullOrEmpty($currentWord) -or $toolName -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*')) {
                New-GoCompletionResult -CompletionText $toolName -ToolTip 'Installed go tool'
            }
        }

        if ($toolResults) {
            $toolResults | Get-GoUniqueCompletions
        } else {
            New-GoCompletionResult -CompletionText '<tool-name>' -ToolTip 'go tool name'
        }

        return
    }

    $nested = @(Get-GoNestedCommands -CommandName $context.Command)
    if ($nested.Count -gt 0 -and -not $context.Subcommand) {
        Get-GoNestedCommandCompletions -CommandName $context.Command -NestedCommands $nested -WordToComplete $currentWord |
            Get-GoUniqueCompletions
        return
    }

    $tailResults = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-GoOperandCompletions -Context $context -WordToComplete $currentWord)) {
        [void]$tailResults.Add($item)
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        foreach ($item in @(Get-GoOptionCompletions -FlagModel $context.FlagModel -WordToComplete $currentWord)) {
            [void]$tailResults.Add($item)
        }
    }

    $tailResults | Get-GoUniqueCompletions
}
