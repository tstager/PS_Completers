# onemd tab completion for PowerShell
# Help-driven native completer for onemd and onemd.exe.

Set-StrictMode -Version 2.0

function New-OnemdCompletionResult {
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

function Get-OnemdCommandPath {
    foreach ($candidate in @('onemd', 'onemd.cmd', 'onemd.ps1', 'onemd.exe')) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandType -in @('Application', 'ExternalScript', 'Script') } |
            Select-Object -First 1

        if ($null -ne $command) {
            return $command.Source
        }
    }

    return $null
}

function Get-OnemdHelpOutput {
    param([string[]]$CommandPath)

    $resolvedCommandPath = Get-OnemdCommandPath
    if ([string]::IsNullOrWhiteSpace($resolvedCommandPath)) {
        return ''
    }

    $subcommandPath = @($CommandPath)

    try {
        if ($subcommandPath.Count -eq 0) {
            $resultText = ($null | & $resolvedCommandPath --help 2>&1 | Out-String)
            if (-not [string]::IsNullOrWhiteSpace($resultText)) {
                return $resultText
            }

            return ($null | & $resolvedCommandPath help 2>&1 | Out-String)
        }

        $resultText = ($null | & $resolvedCommandPath help $subcommandPath[0] 2>&1 | Out-String)
        if (-not [string]::IsNullOrWhiteSpace($resultText)) {
            return $resultText
        }

        return ($null | & $resolvedCommandPath $subcommandPath[0] --help 2>&1 | Out-String)
    } catch {
        return ''
    }
}

function ConvertTo-OnemdArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $fullName = $Value.GetType().FullName
        if ($fullName -like 'System.Collections.Generic.List*' -or $fullName -like 'System.Collections.Generic.IReadOnlyList*') {
            return @($Value.ToArray())
        }
    }

    return @($Value)
}

function Get-OnemdSlotShape {
    param([string]$MetaVariable)

    # The metavariable in the help row decides the slot kind: <path>/<file>/<folder> are filesystem slots, everything
    # else (<n>, <seconds>, <guid>, <id|name>, <mode>, ...) is a typed value.
    $meta = if ($null -eq $MetaVariable) { '' } else { $MetaVariable.Trim('<', '>', '[', ']').ToLowerInvariant() }
    $pathLike = $false
    $directoryOnly = $false
    $extension = ''

    switch -Regex ($meta) {
        '^(folder|dir|directory)$' { $pathLike = $true; $directoryOnly = $true }
        '^(path|file)$' { $pathLike = $true }
        '^file\.([a-z0-9]+)$' { $pathLike = $true; $extension = '.' + $matches[1] }
    }

    [pscustomobject]@{
        PathLike      = $pathLike
        DirectoryOnly = $directoryOnly
        Extension     = $extension
    }
}

function Get-OnemdDescriptionValues {
    param([string]$Description)

    # Values stated in prose rather than in a (a|b|c) list: an "x, y, z" word list after a colon, small numeric
    # ranges, defaults, minimums and ceilings, and the literal "-" for stdin/stdout.
    $values = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Description)) {
        return @()
    }

    if ($Description -match '\((?<values>[^)]+)\)') {
        $candidate = $matches.values
        if ($candidate -match '\|') {
            foreach ($value in @($candidate -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                [void]$values.Add($value)
            }
        }
    }

    if ($values.Count -eq 0) {
        if ($Description -match ':\s*(?<list>[a-z]{3,}(?:,\s*[a-z]{3,})+)') {
            foreach ($value in @($matches.list -split ',\s*')) {
                [void]$values.Add($value)
            }
        }

        if ($Description -match '(?<!\w)(?<low>\d+)-(?<high>\d+)(?!\w)') {
            $low = [int]$matches.low
            $high = [int]$matches.high
            if ($high -gt $low -and ($high - $low) -le 10) {
                foreach ($number in $low..$high) { [void]$values.Add([string]$number) }
            } elseif ($high -gt $low) {
                [void]$values.Add([string]$low)
                [void]$values.Add([string]$high)
            }
        }

        foreach ($pattern in @('\bDefault:?\s+(\d+)', '\bminimum\s+(\d+)', '\bceiling\s+(\d+)')) {
            if ($Description -match $pattern -and -not $values.Contains($matches[1])) {
                [void]$values.Add($matches[1])
            }
        }

        if ($Description -match '"-"\s+(writes|reads)' -or $Description -match '\bor - to\b') {
            [void]$values.Add('-')
        }
    }

    @($values.ToArray())
}

function ConvertFrom-OnemdHelp {
    param([string]$HelpText)

    $lines = @([regex]::Split($HelpText, '\r?\n'))
    $commands = New-Object System.Collections.Generic.List[string]
    $options = New-Object System.Collections.Generic.List[object]
    $arguments = New-Object System.Collections.Generic.List[object]
    # Ordinal: -v (verbose) and -V (version) are different options.
    $seenOptionNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    $inCommands = $false
    $inArguments = $false
    $inOptions = $false

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $trimmed = $line.Trim()

        if ($trimmed -eq 'Commands:') {
            $inCommands = $true
            $inArguments = $false
            $inOptions = $false
            continue
        }

        if ($trimmed -eq 'Arguments:') {
            $inCommands = $false
            $inArguments = $true
            $inOptions = $false
            continue
        }

        if ($trimmed -eq 'Options:' -or $trimmed -eq 'Global options:') {
            $inCommands = $false
            $inArguments = $false
            $inOptions = $true
            continue
        }

        if ($inCommands) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            if ($trimmed -match '^(?<name>[A-Za-z0-9][A-Za-z0-9-]*)\s{2,}(?<description>.+)$') {
                [void]$commands.Add($matches.name)
            }

            continue
        }

        if ($inArguments) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            if ($line -notmatch '^\s+\S') {
                $inArguments = $false
                continue
            }

            if ($trimmed -match '^(?<name><[^>]+>|\[[^]]+\]|[^\s][^\s]*)\s{2,}(?<description>.+)$') {
                $argumentName = $matches.name
                $description = $matches.description
                $shape = Get-OnemdSlotShape -MetaVariable $argumentName

                [void]$arguments.Add([pscustomobject]@{
                    Name = $argumentName
                    Description = $description
                    Values = @(Get-OnemdDescriptionValues -Description $description)
                    PathLike = $shape.PathLike
                    DirectoryOnly = $shape.DirectoryOnly
                    Extension = $shape.Extension
                })
            }

            continue
        }

        if ($inOptions) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            # An option row is an indented line starting with '-'; anything else (a prose heading at the left
            # margin, a paragraph) ends the section so trailing prose is never parsed as more options.
            if ($line -notmatch '^\s+-') {
                $inOptions = $false
                continue
            }

            if ($trimmed -match '^(?<optionText>.+?)(\s{2,}|\s*$)(?<description>.+)$') {
                $optionText = $matches.optionText.Trim()
                $optionDescription = $matches.description

                $optionNames = @([regex]::Matches($optionText, '--?[A-Za-z0-9][A-Za-z0-9-]*') | ForEach-Object { $_.Value })
                if ($optionNames.Count -eq 0 -or $seenOptionNames.Contains($optionNames[0])) {
                    continue
                }
                foreach ($name in $optionNames) { [void]$seenOptionNames.Add($name) }

                $metaVariable = ''
                if ($optionText -match '(<[^>]+>)') {
                    $metaVariable = $matches[1]
                }
                $shape = Get-OnemdSlotShape -MetaVariable $metaVariable

                [void]$options.Add([pscustomobject]@{
                    Names = @($optionNames)
                    TakesValue = ($metaVariable -ne '')
                    MetaVariable = $metaVariable
                    Values = @(Get-OnemdDescriptionValues -Description $optionDescription)
                    Description = $optionDescription
                    PathLike = $shape.PathLike
                    DirectoryOnly = $shape.DirectoryOnly
                    Extension = $shape.Extension
                })
            }
        }
    }

    # Negated --no-* flags live in usage lines and descriptions, never in the left column.
    foreach ($match in [regex]::Matches($HelpText, '(?m)^.*?(--no-[a-z0-9-]+).*$')) {
        $name = $match.Groups[1].Value
        if (-not $seenOptionNames.Add($name)) {
            continue
        }
        [void]$options.Add([pscustomobject]@{
            Names = @($name)
            TakesValue = $false
            MetaVariable = ''
            Values = @()
            Description = $match.Value.Trim()
            PathLike = $false
            DirectoryOnly = $false
            Extension = ''
        })
    }

    [pscustomobject]@{
        Commands = (ConvertTo-OnemdArray -Value ($commands.ToArray() | Sort-Object -Unique))
        Options = (ConvertTo-OnemdArray -Value $options)
        Arguments = (ConvertTo-OnemdArray -Value $arguments)
    }
}

function Get-OnemdCompletionCatalog {
    $catalog = Get-Variable -Name 'OnemdCompletionCatalog' -Scope Script -ErrorAction Ignore
    if ($null -ne $catalog -and $null -ne $catalog.Value) {
        return $catalog.Value
    }

    $newCatalog = [ordered]@{
        Initialized = $false
        RootHelpText = ''
        RootHelp = $null
        CommandCatalogs = @{}
    }

    Set-Variable -Name 'OnemdCompletionCatalog' -Value $newCatalog -Scope Script
    return (Get-Variable -Name 'OnemdCompletionCatalog' -Scope Script).Value
}

function Initialize-OnemdCompletionCatalog {
    $catalog = Get-OnemdCompletionCatalog
    if ($catalog.Initialized) {
        return $catalog
    }

    $catalog.RootHelpText = Get-OnemdHelpOutput -CommandPath @()
    $catalog.RootHelp = ConvertFrom-OnemdHelp -HelpText $catalog.RootHelpText
    $catalog.CommandCatalogs[''] = [pscustomobject]@{
        Path = @()
        Commands = (ConvertTo-OnemdArray -Value $catalog.RootHelp.Commands)
        Options = (ConvertTo-OnemdArray -Value $catalog.RootHelp.Options)
        Arguments = (ConvertTo-OnemdArray -Value $catalog.RootHelp.Arguments)
    }

    $catalog.Initialized = $true
    Set-Variable -Name 'OnemdCompletionCatalog' -Value $catalog -Scope Script
    return (Get-Variable -Name 'OnemdCompletionCatalog' -Scope Script).Value
}

function Get-OnemdCatalog {
    param([string[]]$CommandPath)

    $catalog = Initialize-OnemdCompletionCatalog
    $key = if ($null -eq $CommandPath -or $CommandPath.Count -eq 0) { '' } else { $CommandPath -join "`u{1f}" }

    if ($catalog.CommandCatalogs.ContainsKey($key)) {
        return $catalog.CommandCatalogs[$key]
    }

    $helpText = Get-OnemdHelpOutput -CommandPath $CommandPath
    $parsed = ConvertFrom-OnemdHelp -HelpText $helpText
    $parsedCatalog = [pscustomobject]@{
        Path = @($CommandPath)
        Commands = (ConvertTo-OnemdArray -Value $parsed.Commands)
        Options = (ConvertTo-OnemdArray -Value $parsed.Options)
        Arguments = (ConvertTo-OnemdArray -Value $parsed.Arguments)
    }

    $catalog.CommandCatalogs[$key] = $parsedCatalog
    Set-Variable -Name 'OnemdCompletionCatalog' -Value $catalog -Scope Script
    return $catalog.CommandCatalogs[$key]
}

function Get-OnemdCommandTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$WordToComplete
    )

    # Elements that end before the cursor are completed tokens; the element under the cursor is the word being
    # typed (cut at the cursor); anything to the right of the cursor is ignored.
    $tokens = New-Object System.Collections.Generic.List[string]
    $currentWord = ''
    if ($null -ne $CommandAst) {
        foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
            $extent = $element.Extent
            if ($extent.EndOffset -lt $CursorPosition) {
                $text = $extent.Text.Trim()
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    [void]$tokens.Add($text)
                }
                continue
            }

            if ($extent.StartOffset -le $CursorPosition) {
                $currentWord = $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
            }
            break
        }
    }

    if ([string]::IsNullOrEmpty($currentWord) -and -not [string]::IsNullOrEmpty($WordToComplete)) {
        $currentWord = $WordToComplete
    }

    [pscustomobject]@{
        CurrentWord = $currentWord
        Tokens = (ConvertTo-OnemdArray -Value $tokens)
    }
}

function Get-OnemdPathCompletions {
    param([string]$InputPath, [bool]$DirectoryOnly, [string]$Extension = '', [string]$InlinePrefix = '')

    $cleanInput = if ($null -eq $InputPath) { '' } else { $InputPath }
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))
    $cleanInput = $cleanInput.Trim('"', "'")

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]+$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        if (-not $item.PSIsContainer) {
            if ($DirectoryOnly) {
                continue
            }

            if ($Extension -and -not $item.Name.EndsWith($Extension, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
        }

        $pathText = if ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = $pathText
        if (($alwaysQuote -or $pathText -match '\s') -and -not ($pathText.StartsWith('"') -and $pathText.EndsWith('"'))) {
            $escaped = $pathText.Replace('`', '``').Replace('"', '`"')
            $quotedPath = '"' + $escaped + '"'
        }

        if ($item.PSIsContainer) {
            New-OnemdCompletionResult -CompletionText ($InlinePrefix + $quotedPath) -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-OnemdCompletionResult -CompletionText ($InlinePrefix + $quotedPath) -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-OnemdOptionSpec {
    param(
        [psobject]$Catalog,
        [string]$OptionName
    )

    if ($null -eq $Catalog -or [string]::IsNullOrWhiteSpace($OptionName)) {
        return $null
    }

    foreach ($option in @($Catalog.Options)) {
        if ($option.Names -contains $OptionName) {
            return $option
        }
    }

    return $null
}

function Get-OnemdValueCompletions {
    param(
        [psobject]$OptionSpec,
        [string]$CurrentWord,
        [string]$InlinePrefix = ''
    )

    if ($null -eq $OptionSpec) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($value in @($OptionSpec.Values)) {
        if ($value -like ([System.Management.Automation.WildcardPattern]::Escape($CurrentWord) + '*')) {
            [void]$results.Add((New-OnemdCompletionResult -CompletionText ($InlinePrefix + $value) -ListItemText $value -ResultType 'ParameterValue' -ToolTip $OptionSpec.Description))
        }
    }

    if ($OptionSpec.PathLike) {
        foreach ($item in @(Get-OnemdPathCompletions -InputPath $CurrentWord -DirectoryOnly:$OptionSpec.DirectoryOnly -Extension $OptionSpec.Extension -InlinePrefix $InlinePrefix)) {
            [void]$results.Add($item)
        }
    }

    if ($results.Count -gt 0 -or $OptionSpec.PathLike) {
        return (ConvertTo-OnemdArray -Value $results)
    }

    if (-not [string]::IsNullOrEmpty($CurrentWord)) {
        return @()
    }

    $hint = if ($OptionSpec.PSObject.Properties['MetaVariable'] -and $OptionSpec.MetaVariable) { $OptionSpec.MetaVariable } else { '<value>' }
    return @(
        New-OnemdCompletionResult -CompletionText ($InlinePrefix + $hint) -ListItemText $hint -ResultType 'ParameterValue' -ToolTip $OptionSpec.Description
    )
}

function Complete-Onemd {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $tokenState = Get-OnemdCommandTokens -CommandAst $commandAst -CursorPosition $cursorPosition -WordToComplete $wordToComplete
    $currentWord = $tokenState.CurrentWord
    $tokensBeforeCurrent = @($tokenState.Tokens)
    $catalog = Get-OnemdCatalog -CommandPath @()
    $activePath = @()
    $activeCatalog = $catalog

    foreach ($token in $tokensBeforeCurrent) {
        if ($token.StartsWith('-')) {
            break
        }

        if ($activeCatalog.Commands -contains $token) {
            $activePath += $token
            $activeCatalog = Get-OnemdCatalog -CommandPath $activePath
            continue
        }

        break
    }

    if ($activePath.Count -eq 1 -and $activePath[0] -eq 'help') {
        # 'help' takes a command name: complete the root command list exactly once.
        $activeCatalog = [pscustomobject]@{
            Path = @('help')
            Commands = @($catalog.Commands)
            Options = @($activeCatalog.Options)
            Arguments = @()
        }
    }

    # Attached --option=value form.
    if ($currentWord -match '^(?<name>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $optionSpec = Get-OnemdOptionSpec -Catalog $activeCatalog -OptionName $matches.name
        if ($null -ne $optionSpec -and $optionSpec.TakesValue) {
            return @(Get-OnemdValueCompletions -OptionSpec $optionSpec -CurrentWord $matches.value -InlinePrefix ($matches.name + '='))
        }

        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ($tokensBeforeCurrent.Count -gt 0) {
        $lastToken = $tokensBeforeCurrent[-1]
        if ($lastToken -and $lastToken.StartsWith('-')) {
            $optionSpec = Get-OnemdOptionSpec -Catalog $activeCatalog -OptionName $lastToken
            if ($null -ne $optionSpec -and $optionSpec.TakesValue) {
                return @(Get-OnemdValueCompletions -OptionSpec $optionSpec -CurrentWord $currentWord)
            }
        }
    }

    if ($currentWord.StartsWith('-')) {
        foreach ($option in @($activeCatalog.Options)) {
            foreach ($name in @($option.Names)) {
                if ($name -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*')) {
                    [void]$results.Add((New-OnemdCompletionResult -CompletionText $name -ListItemText $name -ResultType 'ParameterName' -ToolTip $option.Description))
                }
            }
        }

        return (ConvertTo-OnemdArray -Value $results)
    }

    $activeCommands = @($activeCatalog.Commands)
    $activeArguments = @($activeCatalog.Arguments)

    if ($activeCommands.Count -gt 0) {
        foreach ($commandName in $activeCommands) {
            if ($commandName -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*')) {
                [void]$results.Add((New-OnemdCompletionResult -CompletionText $commandName -ListItemText $commandName -ResultType 'ParameterValue' -ToolTip 'onemd subcommand'))
            }
        }
    }

    foreach ($option in @($activeCatalog.Options)) {
        foreach ($name in @($option.Names)) {
            if ($currentWord -eq '' -or $name -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*')) {
                [void]$results.Add((New-OnemdCompletionResult -CompletionText $name -ListItemText $name -ResultType 'ParameterName' -ToolTip $option.Description))
            }
        }
    }

    $positionalTokens = @()
    $pendingValue = $false
    foreach ($token in $tokensBeforeCurrent) {
        if ($pendingValue) {
            $pendingValue = $false
            continue
        }

        if ($token.StartsWith('-')) {
            $spec = Get-OnemdOptionSpec -Catalog $activeCatalog -OptionName $token
            if ($null -ne $spec -and $spec.TakesValue) {
                $pendingValue = $true
            }
            continue
        }

        $matchesSubcommand = $false
        foreach ($pathToken in $activePath) {
            if ($token -eq $pathToken) {
                $matchesSubcommand = $true
                break
            }
        }

        if ($matchesSubcommand) {
            continue
        }

        $positionalTokens += $token
    }

    if ($activeArguments.Count -gt 0 -and $positionalTokens.Count -lt $activeArguments.Count) {
        # Operand candidates come first, then the option names already collected, so flags stay discoverable.
        $argumentSpec = $activeArguments[$positionalTokens.Count]
        $argumentResults = New-Object System.Collections.Generic.List[object]
        foreach ($value in @($argumentSpec.Values)) {
            if ($value -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*')) {
                [void]$argumentResults.Add((New-OnemdCompletionResult -CompletionText $value -ListItemText $value -ResultType 'ParameterValue' -ToolTip $argumentSpec.Description))
            }
        }

        if ($argumentSpec.PathLike) {
            foreach ($item in @(Get-OnemdPathCompletions -InputPath $currentWord -DirectoryOnly:$argumentSpec.DirectoryOnly -Extension $argumentSpec.Extension)) {
                [void]$argumentResults.Add($item)
            }
        } elseif ($argumentResults.Count -eq 0 -and $currentWord -eq '') {
            [void]$argumentResults.Add((New-OnemdCompletionResult -CompletionText $argumentSpec.Name -ListItemText $argumentSpec.Name -ResultType 'ParameterValue' -ToolTip $argumentSpec.Description))
        }

        return @(ConvertTo-OnemdArray -Value $argumentResults) + @(ConvertTo-OnemdArray -Value $results)
    }

    if ($results.Count -eq 0 -and $currentWord -ne '') {
        return @(
            New-OnemdCompletionResult -CompletionText $currentWord -ListItemText $currentWord -ResultType 'ParameterValue' -ToolTip 'onemd value'
        )
    }

    return (ConvertTo-OnemdArray -Value $results)
}

Register-ArgumentCompleter -Native -CommandName @('onemd', 'onemd.cmd', 'onemd.ps1', 'onemd.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Onemd -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
