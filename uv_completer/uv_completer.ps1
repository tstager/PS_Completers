Set-StrictMode -Version Latest

if (-not (Get-Variable -Name UvCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:UvCompletionCache = @{
        ExecutablePaths = @{}
        ProbedPaths     = @{}
        PathData        = @{}
        StaticTree     = @{
            ''          = @('auth', 'run', 'init', 'add', 'remove', 'version', 'sync', 'lock', 'export', 'tree', 'format', 'check', 'audit', 'tool', 'python', 'pip', 'venv', 'build', 'publish', 'workspace', 'cache', 'self', 'help')
            'auth'      = @('login', 'logout', 'token', 'dir')
            'tool'      = @('run', 'install', 'upgrade', 'list', 'audit', 'uninstall', 'update-shell', 'dir')
            'python'    = @('list', 'install', 'upgrade', 'find', 'pin', 'dir', 'uninstall', 'update-shell')
            'pip'       = @('compile', 'sync', 'install', 'uninstall', 'freeze', 'list', 'show', 'tree', 'check')
            'workspace' = @('metadata', 'dir', 'list')
            'cache'     = @('clean', 'prune', 'dir', 'size')
            'self'      = @('update', 'version')
        }
    }
}

function Get-UvCacheKey {
    param([string[]]$Path)

    $pathItems = @($Path)
    if ($null -eq $Path) {
        $pathItems = @()
    }
    $pathItems = @($pathItems | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    ($pathItems | ForEach-Object { $_.ToLowerInvariant() }) -join ' '
}

function Get-UvPathDataCacheKey {
    param(
        [string]$SourceName = 'uv',
        [string[]]$Path
    )

    $sourceKey = if ([string]::IsNullOrWhiteSpace($SourceName)) {
        'uv'
    } else {
        $SourceName.ToLowerInvariant()
    }

    $pathKey = Get-UvCacheKey -Path $Path
    if ([string]::IsNullOrWhiteSpace($pathKey)) {
        return $sourceKey
    }

    '{0}|{1}' -f $sourceKey, $pathKey
}

function Get-UvSourceName {
    param([string]$CommandName)

    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        return 'uv'
    }

    $leafName = Split-Path -Leaf $CommandName
    if ($leafName.Equals('uvx', [System.StringComparison]::OrdinalIgnoreCase) -or
        $leafName.Equals('uvx.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'uvx'
    }

    'uv'
}

function Get-UvSyntheticRootPath {
    param([string]$SourceName)

    if ($SourceName -eq 'uvx') {
        return @('tool', 'run')
    }

    @()
}

function Get-UvExecutablePath {
    param([string]$CommandName = 'uv')

    $sourceName = Get-UvSourceName -CommandName $CommandName
    if ($script:UvCompletionCache.ProbedPaths.ContainsKey($sourceName)) {
        return $script:UvCompletionCache.ExecutablePaths[$sourceName]
    }

    $script:UvCompletionCache.ProbedPaths[$sourceName] = $true

    $script:UvCompletionCache.ExecutablePaths[$sourceName] = $null
    $candidateNames = if ($sourceName -eq 'uvx') {
        @('uvx.exe', 'uvx')
    } else {
        @('uv.exe', 'uv')
    }

    foreach ($name in $candidateNames) {
        $command = Get-Command $name -ErrorAction Ignore
        if ($command) {
            $script:UvCompletionCache.ExecutablePaths[$sourceName] = $command.Source
            break
        }
    }

    $script:UvCompletionCache.ExecutablePaths[$sourceName]
}

function New-UvPathData {
    param(
        [string[]]$Commands = @(),
        [hashtable]$CommandDescriptions = @{},
        [string[]]$Options = @(),
        [hashtable]$ValuesByOption = @{},
        [hashtable]$MetavarByOption = @{},
        [string[]]$PositionalValues = @()
    )

    @{
        Commands            = @(@($Commands) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        CommandDescriptions = $CommandDescriptions
        Options             = @(@($Options) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        ValuesByOption      = $ValuesByOption
        MetavarByOption     = $MetavarByOption
        PositionalValues    = @(@($PositionalValues) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
}

function Get-UvTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-UvUniqueStrings {
    param([string[]]$Items)

    $seen = @{}
    $result = New-Object System.Collections.Generic.List[string]

    foreach ($item in @($Items)) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        $key = $item.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        [void]$result.Add($item)
    }

    @($result.ToArray())
}

function Get-UvOptionTokensFromLine {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return @()
    }

    $tokens = foreach ($match in [regex]::Matches($Line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9\-]*)(?=[\s,<\[]|\.\.\.|$|,)')) {
        $match.Groups[1].Value
    }

    Get-UvUniqueStrings -Items $tokens
}

function Get-UvCanonicalOption {
    param([string[]]$Tokens)

    foreach ($token in @($Tokens)) {
        if ($token.StartsWith('--')) {
            return $token.ToLowerInvariant()
        }
    }

    if ($Tokens.Count -gt 0) {
        return $Tokens[0].ToLowerInvariant()
    }

    $null
}

function Add-UvPossibleValues {
    param(
        [hashtable]$ValueMap,
        [string]$OptionKey,
        [string]$RawValueText
    )

    if ([string]::IsNullOrWhiteSpace($OptionKey) -or [string]::IsNullOrWhiteSpace($RawValueText)) {
        return
    }

    $valueText = $RawValueText
    if ($valueText -match '^(.*?)]') {
        $valueText = $matches[1]
    }
    $valueText = $valueText -replace '^(?:possible\s+values:|values:)\s*', ''

    $values = $valueText -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if (-not $ValueMap.ContainsKey($OptionKey)) {
        $ValueMap[$OptionKey] = @()
    }

    $ValueMap[$OptionKey] = Get-UvUniqueStrings -Items ($ValueMap[$OptionKey] + $values)
}

function Get-UvParsedHelpData {
    param([string[]]$HelpLines)

    $commands = New-Object System.Collections.Generic.List[string]
    $commandDescriptions = @{}
    $options = New-Object System.Collections.Generic.List[string]
    $valuesByOption = @{}
    $metavarByOption = @{}
    $positionalValues = New-Object System.Collections.Generic.List[string]
    $positionalKey = $null
    $section = ''
    $currentOption = $null
    $collectingValuesFor = $null
    $collectingValueListFor = $null
    $valueBuffer = ''

    foreach ($line in @($HelpLines)) {
        if ($collectingValuesFor) {
            $trimmed = $line.Trim()
            if ($trimmed) {
                if ($valueBuffer) {
                    $valueBuffer += ' '
                }
                $valueBuffer += $trimmed
            }

            if ($trimmed -match '\]') {
                Add-UvPossibleValues -ValueMap $valuesByOption -OptionKey $collectingValuesFor -RawValueText $valueBuffer
                $collectingValuesFor = $null
                $valueBuffer = ''
            }

            continue
        }

        if ($collectingValueListFor) {
            if ($line -match '^\s*$') {
                $collectingValueListFor = $null
            } elseif ($line -match '^\s*-\s+(.+?)(?:\s*:|\s*$)') {
                Add-UvPossibleValues -ValueMap $valuesByOption -OptionKey $collectingValueListFor -RawValueText $matches[1].Trim()
                continue
            } elseif ((@(Get-UvOptionTokensFromLine -Line $line)).Count -gt 0 -or
                $line -match '^\s*(Commands|Arguments|Examples?|Options|[A-Za-z][A-Za-z ]+ options):\s*$') {
                $collectingValueListFor = $null
            } elseif (-not ($line -match '^\s+')) {
                $collectingValueListFor = $null
            } else {
                continue
            }
        }

        if ($line -match '^\s*$') {
            $currentOption = $null
            continue
        }

        if ($line -match '^\s*(Commands|Arguments|Examples?|Options|[A-Za-z][A-Za-z ]+ options):\s*$') {
            $section = $matches[1].ToLowerInvariant()
            $currentOption = $null
            continue
        }

        if ($section -eq 'commands' -and $line -match '^\s{2,}([a-z][a-z0-9\-]*)\s{2,}(.+)$') {
            $command = $matches[1]
            [void]$commands.Add($command)
            $commandDescriptions[$command.ToLowerInvariant()] = $matches[2].Trim()
            continue
        }

        if ($section -eq 'arguments') {
            # Only the first positional's closed value set is modelled; the
            # existing wrapped '[possible values: ...]' collector handles the
            # continuation lines for it.
            if ($line -match '^\s{2,}(?:<([A-Z_]+)>|\[([A-Z_]+)\])') {
                $currentOption = $null
                $positionalKey = if ($positionalValues.Count -eq 0 -and $null -eq $positionalKey) { '<positional>' } else { $null }
            }

            if ($positionalKey -and $line -match '\[possible values:\s*(.+)$') {
                $valueBuffer = $matches[1].Trim()
                if ($valueBuffer -match '\]') {
                    Add-UvPossibleValues -ValueMap $valuesByOption -OptionKey $positionalKey -RawValueText $valueBuffer
                    $valueBuffer = ''
                } else {
                    $collectingValuesFor = $positionalKey
                }
            }

            continue
        }

        if ($section -like '*options') {
            $tokens = @(Get-UvOptionTokensFromLine -Line $line)
            if ($tokens.Count -gt 0) {
                foreach ($token in $tokens) {
                    [void]$options.Add($token)
                }

                $currentOption = Get-UvCanonicalOption -Tokens $tokens

                # A metavariable after the option names marks a value-bearing
                # option; its absence marks a switch.
                $metavar = if ($line -match '^\s*-[^\s]+(?:,\s*-[^\s]+)*(?:\.\.\.)?\s+(?:\[=)?<([A-Z][A-Z0-9_]*)>') { $matches[1] } else { '' }
                foreach ($token in $tokens) {
                    $metavarByOption[$token.ToLowerInvariant()] = $metavar
                }
            }

            if ($currentOption -and $line -match '\[possible values:\s*(.+)$') {
                $valueBuffer = $matches[1].Trim()
                if ($valueBuffer -match '\]') {
                    Add-UvPossibleValues -ValueMap $valuesByOption -OptionKey $currentOption -RawValueText $valueBuffer
                    $valueBuffer = ''
                } else {
                    $collectingValuesFor = $currentOption
                }
            } elseif ($currentOption -and $line -match '\[possible\s*$') {
                $valueBuffer = ''
                $collectingValuesFor = $currentOption
            } elseif ($currentOption -and $line -match '^\s*Possible values:\s*$') {
                $collectingValueListFor = $currentOption
            }
        }
    }

    if ($collectingValuesFor -and $valueBuffer) {
        Add-UvPossibleValues -ValueMap $valuesByOption -OptionKey $collectingValuesFor -RawValueText $valueBuffer
    }

    if ($valuesByOption.ContainsKey('<positional>')) {
        foreach ($value in @($valuesByOption['<positional>'])) {
            [void]$positionalValues.Add($value)
        }
        $valuesByOption.Remove('<positional>')
    }

    @{
        Commands            = Get-UvUniqueStrings -Items $commands.ToArray()
        CommandDescriptions = $commandDescriptions
        Options             = Get-UvUniqueStrings -Items $options.ToArray()
        ValuesByOption      = $valuesByOption
        MetavarByOption     = $metavarByOption
        PositionalValues    = Get-UvUniqueStrings -Items $positionalValues.ToArray()
    }
}

function Invoke-UvHelp {
    param(
        [string]$CommandName = 'uv',
        [string[]]$Path
    )

    $uvPath = Get-UvExecutablePath -CommandName $CommandName
    if (-not $uvPath) {
        return @()
    }

    $pathItems = @($Path)
    if ($null -eq $Path) {
        $pathItems = @()
    }
    $pathItems = @($pathItems | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $arguments = @()
    if (@($pathItems).Count -gt 0) {
        $arguments += $pathItems
    }
    $arguments += '--help'

    try {
        @(& $uvPath @arguments 2>$null)
    } catch {
        @()
    }
}

function Get-UvStaticSubcommands {
    param([string[]]$Path)

    $key = Get-UvCacheKey -Path $Path
    if ($script:UvCompletionCache.StaticTree.ContainsKey($key)) {
        return $script:UvCompletionCache.StaticTree[$key]
    }

    @()
}

function Get-UvPathData {
    param(
        [string]$SourceName = 'uv',
        [string[]]$Path
    )

    $path = @($Path)
    if ($null -eq $Path) {
        $path = @()
    }
    $path = @($path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $key = Get-UvPathDataCacheKey -SourceName $SourceName -Path $path
    if ($script:UvCompletionCache.PathData.ContainsKey($key)) {
        return $script:UvCompletionCache.PathData[$key]
    }

    $helpLines = @()
    $pathKey = Get-UvCacheKey -Path $path
    $uvxRootKey = Get-UvCacheKey -Path @('tool', 'run')
    if ($SourceName -eq 'uvx' -and $pathKey -eq $uvxRootKey) {
        $helpLines += @(Invoke-UvHelp -CommandName 'uvx')
        $helpLines += ''
        $helpLines += @(Invoke-UvHelp -CommandName 'uv' -Path $path)
    } else {
        $helpLines += @(Invoke-UvHelp -CommandName $SourceName -Path $path)
    }

    $parsed = if ($helpLines.Count -gt 0) {
        Get-UvParsedHelpData -HelpLines $helpLines
    } else {
        New-UvPathData
    }

    $staticCommands = Get-UvStaticSubcommands -Path $path
    $data = New-UvPathData `
        -Commands (Get-UvUniqueStrings -Items ($staticCommands + $parsed.Commands)) `
        -CommandDescriptions $parsed.CommandDescriptions `
        -Options $parsed.Options `
        -ValuesByOption $parsed.ValuesByOption `
        -MetavarByOption $parsed.MetavarByOption `
        -PositionalValues $parsed.PositionalValues

    $script:UvCompletionCache.PathData[$key] = $data
    $data
}

function Find-UvSubcommand {
    param(
        [string]$SourceName = 'uv',
        [string[]]$Path,
        [string]$Token
    )

    foreach ($command in (Get-UvPathData -SourceName $SourceName -Path $Path).Commands) {
        if ($command.Equals($Token, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $command
        }
    }

    $null
}

function Get-UvCommandContext {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$SourceName = 'uv',
        [string[]]$RootPath = @(),
        [bool]$SupportsHelpCommand = $true
    )

    $tokens = New-Object System.Collections.Generic.List[string]
    $lastElementBeforeCursor = $null

    for ($index = 1; $index -lt $CommandAst.CommandElements.Count; $index++) {
        $element = $CommandAst.CommandElements[$index]
        if ($element.Extent.StartOffset -ge $CursorPosition) {
            continue
        }

        $lastElementBeforeCursor = $element
        $token = Get-UvTokenText -Element $element
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        [void]$tokens.Add($token)
    }

    # Trailing whitespace is judged against the last element BEFORE the
    # cursor, so text after the cursor does not shift the command path.
    $hasTrailingSpace = $false
    if ([string]::IsNullOrEmpty($WordToComplete)) {
        $hasTrailingSpace = if ($null -ne $lastElementBeforeCursor) {
            $CursorPosition -gt $lastElementBeforeCursor.Extent.EndOffset
        } else {
            $CursorPosition -gt $CommandAst.CommandElements[0].Extent.EndOffset
        }
    }

    $previousToken = $null
    if ($tokens.Count -gt 0) {
        if ($hasTrailingSpace) {
            $previousToken = $tokens[$tokens.Count - 1]
        } elseif ($tokens.Count -gt 1) {
            $previousToken = $tokens[$tokens.Count - 2]
        }
    }

    $pathTokens = @()
    if ($hasTrailingSpace) {
        $pathTokens = $tokens.ToArray()
    } elseif ($tokens.Count -gt 1) {
        $pathTokens = $tokens.GetRange(0, $tokens.Count - 1).ToArray()
    }

    # An empty synthetic root arrives as $null once unrolled, so filter
    # blank segments before they can become a bogus path element.
    $commandPath = New-Object System.Collections.Generic.List[string]
    foreach ($token in @($RootPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        [void]$commandPath.Add($token)
    }
    $rootPathCount = $commandPath.Count

    $helpMode = $false
    $operandSeen = $false
    $pendingValueOption = $null

    foreach ($token in @($pathTokens)) {
        if ($null -ne $pendingValueOption) {
            $pendingValueOption = $null
            continue
        }

        if ($token.StartsWith('-')) {
            if (-not $token.Contains('=') -and (Get-UvOptionValueKind -SourceName $SourceName -Path $commandPath.ToArray() -Option $token) -ne 'switch') {
                $pendingValueOption = $token
            }

            continue
        }

        if ($operandSeen) {
            continue
        }

        if ($SupportsHelpCommand -and
            $commandPath.Count -eq $rootPathCount -and
            -not $helpMode -and
            $token.Equals('help', [System.StringComparison]::OrdinalIgnoreCase)) {
            $helpMode = $true
            continue
        }

        $nextCommand = Find-UvSubcommand -SourceName $SourceName -Path $commandPath.ToArray() -Token $token
        if (-not $nextCommand -and
            $SourceName -eq 'uv' -and
            $commandPath.Count -eq 0 -and
            -not $helpMode -and
            $token -match '^[a-z][a-z0-9-]*$') {
            # Hidden root commands (generate-shell-completion) are absent from
            # `uv --help`; `uv <token> --help` is safe at the root because uv
            # rejects unknown subcommands instead of running anything.
            $probe = Get-UvPathData -SourceName $SourceName -Path @($token)
            if (@($probe.Commands).Count -gt 0 -or @($probe.Options).Count -gt 0) {
                $nextCommand = $token
            }
        }

        if ($nextCommand) {
            [void]$commandPath.Add($nextCommand)
        } else {
            $operandSeen = $true
        }
    }

    @{
        Path            = if ($commandPath.Count -gt 0) { @($commandPath.ToArray()) } else { @() }
        PreviousToken   = $previousToken
        HelpMode        = $helpMode
        HasTrailingSpace = $hasTrailingSpace
        OperandSeen     = $operandSeen
    }
}

function Get-UvOptionValues {
    param(
        [string]$SourceName = 'uv',
        [string[]]$Path,
        [string]$Option
    )

    if ([string]::IsNullOrWhiteSpace($Option) -or -not $Option.StartsWith('-')) {
        return @()
    }

    $optionKey = $Option.ToLowerInvariant()
    $values = @()

    $pathData = Get-UvPathData -SourceName $SourceName -Path $Path
    if ($pathData.ValuesByOption.ContainsKey($optionKey)) {
        $values += $pathData.ValuesByOption[$optionKey]
    }

    if (@($values).Count -eq 0) {
        $rootData = Get-UvPathData -SourceName $SourceName -Path @()
        if ($rootData.ValuesByOption.ContainsKey($optionKey)) {
            $values += $rootData.ValuesByOption[$optionKey]
        }
    }

    Get-UvUniqueStrings -Items $values
}

function Get-UvOptionMetavar {
    param(
        [string]$SourceName = 'uv',
        [string[]]$Path,
        [string]$Option
    )

    $optionKey = $Option.ToLowerInvariant()
    foreach ($data in @((Get-UvPathData -SourceName $SourceName -Path $Path), (Get-UvPathData -SourceName $SourceName -Path @()))) {
        if ($data.MetavarByOption.ContainsKey($optionKey)) {
            return [string]$data.MetavarByOption[$optionKey]
        }
    }

    $null
}

function Get-UvOptionValueKind {
    param(
        [string]$SourceName = 'uv',
        [string[]]$Path,
        [string]$Option
    )

    # 'switch' for options without a metavariable (or unknown options),
    # 'path' for file/directory metavariables, otherwise 'value'.
    if ([string]::IsNullOrWhiteSpace($Option) -or -not $Option.StartsWith('-')) {
        return 'switch'
    }

    $metavar = Get-UvOptionMetavar -SourceName $SourceName -Path $Path -Option $Option
    if ([string]::IsNullOrEmpty($metavar)) {
        return 'switch'
    }

    if ($metavar -match '(^|_)(DIR|DIRECTORY|FILE|PATH|REQUIREMENTS|CONSTRAINTS|OVERRIDES|SCRIPT|PROJECT|CACHE_DIR|OUTPUT_FILE)$') {
        return 'path'
    }

    'value'
}

function Get-UvOptionAssignmentContext {
    param([string]$WordToComplete)

    if ($WordToComplete -match '^(--?[A-Za-z0-9][A-Za-z0-9\-]*)=(.*)$') {
        return @{
            Option      = $matches[1]
            ValuePrefix = $matches[2]
        }
    }

    $null
}

function Get-UvEffectiveWordToComplete {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    if (-not [string]::IsNullOrEmpty($WordToComplete)) {
        return $WordToComplete
    }

    if ($CommandAst.CommandElements.Count -eq 0) {
        return $WordToComplete
    }

    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.EndOffset -eq $CursorPosition) {
            return Get-UvTokenText -Element $element
        }
    }

    $WordToComplete
}

function New-UvCompletionResults {
    param(
        [string[]]$Items,
        [System.Management.Automation.CompletionResultType]$ResultType,
        [string]$WordToComplete,
        [hashtable]$Tooltips
    )

    foreach ($item in @($Items | Where-Object { -not [string]::IsNullOrEmpty($_) })) {
        if ($item -notlike ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
            continue
        }

        $tooltip = if ($Tooltips -and $Tooltips.ContainsKey($item.ToLowerInvariant())) {
            $Tooltips[$item.ToLowerInvariant()]
        } else {
            $item
        }

        [System.Management.Automation.CompletionResult]::new($item, $item, $ResultType, $tooltip)
    }
}

function New-UvAssignedValueCompletionResults {
    param(
        [string]$Option,
        [string[]]$Items,
        [string]$ValuePrefix
    )

    foreach ($item in @($Items | Where-Object { -not [string]::IsNullOrEmpty($_) })) {
        if ($item -notlike ([System.Management.Automation.WildcardPattern]::Escape($ValuePrefix) + '*')) {
            continue
        }

        $completionText = '{0}={1}' -f $Option, $item
        [System.Management.Automation.CompletionResult]::new(
            $completionText,
            $completionText,
            [System.Management.Automation.CompletionResultType]::ParameterValue,
            $completionText
        )
    }
}

function Complete-Uv {
    param($wordToComplete, $commandAst, $cursorPosition)

    $sourceName = 'uv'
    if ($commandAst.CommandElements.Count -gt 0) {
        $sourceName = Get-UvSourceName -CommandName (Get-UvTokenText -Element $commandAst.CommandElements[0])
    }

    $effectiveWordToComplete = Get-UvEffectiveWordToComplete `
        -WordToComplete $wordToComplete `
        -CommandAst $commandAst `
        -CursorPosition $cursorPosition

    $context = Get-UvCommandContext `
        -WordToComplete $effectiveWordToComplete `
        -CommandAst $commandAst `
        -CursorPosition $cursorPosition `
        -SourceName $sourceName `
        -RootPath (Get-UvSyntheticRootPath -SourceName $sourceName) `
        -SupportsHelpCommand ($sourceName -ne 'uvx')
    $path = $context.Path
    $previousToken = $context.PreviousToken
    $pathData = Get-UvPathData -SourceName $sourceName -Path $path
    $assignmentContext = Get-UvOptionAssignmentContext -WordToComplete $effectiveWordToComplete

    if ($assignmentContext) {
        New-UvAssignedValueCompletionResults `
            -Option $assignmentContext.Option `
            -Items (Get-UvOptionValues -SourceName $sourceName -Path $path -Option $assignmentContext.Option) `
            -ValuePrefix $assignmentContext.ValuePrefix
        return
    }

    if ($previousToken -and $previousToken.StartsWith('-') -and -not $previousToken.Contains('=')) {
        $valueKind = Get-UvOptionValueKind -SourceName $sourceName -Path $path -Option $previousToken
        if ($valueKind -eq 'path') {
            # A path-typed option: the engine's own filesystem completion is
            # the intended answer, so return nothing on purpose.
            return @()
        }

        if ($valueKind -eq 'value') {
            $values = @(Get-UvOptionValues -SourceName $sourceName -Path $path -Option $previousToken)
            if ($values.Count -eq 0) {
                $metavar = Get-UvOptionMetavar -SourceName $sourceName -Path $path -Option $previousToken
                $values = @('<' + $metavar.ToLowerInvariant() + '>')
            }

            New-UvCompletionResults -Items $values -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -WordToComplete $wordToComplete -Tooltips @{}
            return
        }
    }

    if ($context.HelpMode) {
        New-UvCompletionResults -Items $pathData.Commands -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -WordToComplete $wordToComplete -Tooltips $pathData.CommandDescriptions
        return
    }

    if ($effectiveWordToComplete.StartsWith('-')) {
        New-UvCompletionResults -Items $pathData.Options -ResultType ([System.Management.Automation.CompletionResultType]::ParameterName) -WordToComplete $effectiveWordToComplete -Tooltips @{}
        return
    }

    if (-not $context.OperandSeen -and @($pathData.PositionalValues).Count -gt 0) {
        New-UvCompletionResults -Items $pathData.PositionalValues -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -WordToComplete $effectiveWordToComplete -Tooltips @{}
        return
    }

    if (-not $context.OperandSeen) {
        New-UvCompletionResults -Items $pathData.Commands -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -WordToComplete $effectiveWordToComplete -Tooltips $pathData.CommandDescriptions
    }

    New-UvCompletionResults -Items $pathData.Options -ResultType ([System.Management.Automation.CompletionResultType]::ParameterName) -WordToComplete $effectiveWordToComplete -Tooltips @{}
}

Register-ArgumentCompleter -Native -CommandName 'uv', 'uv.exe', 'uvx', 'uvx.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Uv -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
