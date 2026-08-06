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
            $resultText = (& $resolvedCommandPath --help 2>&1 | Out-String)
            if (-not [string]::IsNullOrWhiteSpace($resultText)) {
                return $resultText
            }

            return (& $resolvedCommandPath help 2>&1 | Out-String)
        }

        $resultText = (& $resolvedCommandPath help $subcommandPath[0] 2>&1 | Out-String)
        if (-not [string]::IsNullOrWhiteSpace($resultText)) {
            return $resultText
        }

        return (& $resolvedCommandPath $subcommandPath[0] --help 2>&1 | Out-String)
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

function ConvertFrom-OnemdHelp {
    param([string]$HelpText)

    $lines = @([regex]::Split($HelpText, '\r?\n'))
    $commands = New-Object System.Collections.Generic.List[string]
    $options = New-Object System.Collections.Generic.List[object]
    $arguments = New-Object System.Collections.Generic.List[object]

    $inCommands = $false
    $inArguments = $false
    $inOptions = $false
    $sectionName = ''

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $trimmed = $line.Trim()

        if ($trimmed -eq 'Commands:') {
            $inCommands = $true
            $inArguments = $false
            $inOptions = $false
            $sectionName = 'commands'
            continue
        }

        if ($trimmed -eq 'Arguments:') {
            $inCommands = $false
            $inArguments = $true
            $inOptions = $false
            $sectionName = 'arguments'
            continue
        }

        if ($trimmed -eq 'Options:' -or $trimmed -eq 'Global options:') {
            $inCommands = $false
            $inArguments = $false
            $inOptions = $true
            $sectionName = 'options'
            continue
        }

        if ($inCommands) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            if ($trimmed -match '^(?<name>[A-Za-z0-9][A-Za-z0-9-]*)\s{2,}(?<description>.+)$') {
                $name = $matches.name
                [void]$commands.Add($name)
            }

            continue
        }

        if ($inArguments) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            if ($trimmed -match '^(?<name><[^>]+>|\[[^]]+\]|[^\s][^\s]*)\s{2,}(?<description>.+)$') {
                $argumentName = $matches.name
                $description = $matches.description
                $values = @()
                if ($description -match '\((?<values>[^)]+)\)') {
                    $candidate = $matches.values
                    if ($candidate -match '\|') {
                        $values = @($candidate -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    }
                }

                [void]$arguments.Add([pscustomobject]@{
                    Name = $argumentName
                    Description = $description
                    Values = @($values)
                    PathLike = (Test-OnemdPathLikeSlot -Name $argumentName -Description $description)
                })
            }

            continue
        }

        if ($inOptions) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            if ($trimmed -match '^(?<optionText>.+?)(\s{2,}|\s*$)(?<description>.+)$') {
                $optionText = $matches.optionText.Trim()
                $optionDescription = $matches.description
                if ($optionText -notmatch '^[A-Za-z0-9-]') {
                    continue
                }

                $optionNames = @([regex]::Matches($optionText, '--?[A-Za-z0-9][A-Za-z0-9-]*') | ForEach-Object { $_.Value })
                if ($optionNames.Count -eq 0) {
                    continue
                }

                $values = @()
                if ($optionDescription -match '\((?<values>[^)]+)\)') {
                    $candidate = $matches.values
                    if ($candidate -match '\|') {
                        $values = @($candidate -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    }
                }

                $takesValue = $optionText -match '<[^>]+>' -or $optionText -match '\[[^]]*<[^>]+>'
                [void]$options.Add([pscustomobject]@{
                    Names = @($optionNames)
                    TakesValue = $takesValue
                    Values = @($values)
                    Description = $optionDescription
                    PathLike = (Test-OnemdPathLikeSlot -Name ($optionNames -join ',') -Description $optionDescription)
                })
            }
        }
    }

    [pscustomobject]@{
        Commands = (ConvertTo-OnemdArray -Value ($commands.ToArray() | Sort-Object -Unique))
        Options = (ConvertTo-OnemdArray -Value $options)
        Arguments = (ConvertTo-OnemdArray -Value $arguments)
    }
}

function Test-OnemdPathLikeSlot {
    param([string]$Name, [string]$Description)

    $text = "$Name $Description"
    if ($text -match 'path|file|folder|directory|output|attachments-dir|base-dir|config-dir|report|exclude') {
        return $true
    }

    return $false
}

function Get-OnemdCompletionCatalog {
    $catalog = Get-Variable -Name 'OnemdCompletionCatalog' -Scope Script -ErrorAction SilentlyContinue
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

function Get-OnemdCurrentToken {
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    return $Fallback
}

function Get-OnemdCommandTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    if ($null -eq $CommandAst) {
        return @()
    }

    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.EndOffset -le $CursorPosition) {
            $text = $element.Extent.Text.Trim()
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                [void]$tokens.Add($text)
            }
        }
    }

    return (ConvertTo-OnemdArray -Value $tokens)
}

function Get-OnemdPathCompletions {
    param([string]$InputPath, [bool]$DirectoryOnly)

    $cleanInput = if ($null -eq $InputPath) { '' } else { $InputPath }
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

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
    $items = $items | Where-Object { $_.Name -like "$leaf*" } | Sort-Object -Property Name

    foreach ($item in $items) {
        if ($DirectoryOnly -and -not $item.PSIsContainer) {
            continue
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
            New-OnemdCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-OnemdCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
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
        [string]$Name,
        [string]$Description
    )

    if ($null -eq $OptionSpec) {
        return @()
    }

    if ($OptionSpec.Values.Count -gt 0) {
        return @(
            foreach ($value in $OptionSpec.Values) {
                if ($value -like "$CurrentWord*") {
                    New-OnemdCompletionResult -CompletionText $value -ListItemText $value -ResultType 'ParameterValue' -ToolTip $OptionSpec.Description
                }
            }
        )
    }

    if ($OptionSpec.PathLike) {
        $directoryOnly = $Name -match 'dir|folder|path|output' -and $Name -notmatch 'file'
        return @(Get-OnemdPathCompletions -InputPath $CurrentWord -DirectoryOnly:$directoryOnly)
    }

    return @(
        New-OnemdCompletionResult -CompletionText '<value>' -ListItemText '<value>' -ResultType 'ParameterValue' -ToolTip $OptionSpec.Description
    )
}

function Complete-Onemd {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($null -eq $wordToComplete) { '' } else { $wordToComplete }
    $tokensBeforeCurrent = @(Get-OnemdCommandTokens -CommandAst $commandAst -CursorPosition $cursorPosition)
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
        $activeCatalog = $catalog
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ($tokensBeforeCurrent.Count -gt 0) {
        $lastToken = $tokensBeforeCurrent[-1]
        if ($lastToken -and $lastToken.StartsWith('-')) {
            $optionSpec = Get-OnemdOptionSpec -Catalog $activeCatalog -OptionName $lastToken
            if ($null -ne $optionSpec -and $optionSpec.TakesValue) {
                return @(Get-OnemdValueCompletions -OptionSpec $optionSpec -CurrentWord $currentWord -Name ($lastToken) -Description $optionSpec.Description)
            }
        }
    }

    if ($currentWord.StartsWith('-')) {
        foreach ($option in @($activeCatalog.Options)) {
            foreach ($name in @($option.Names)) {
                if ($name -like "$currentWord*") {
                    [void]$results.Add((New-OnemdCompletionResult -CompletionText $name -ListItemText $name -ResultType 'ParameterName' -ToolTip $option.Description))
                }
            }
        }

        return (ConvertTo-OnemdArray -Value $results)
    }

    $rootCommands = @($catalog.Commands)
    $activeCommands = @($activeCatalog.Commands)
    $activeArguments = @($activeCatalog.Arguments)

    if ($rootCommands.Count -gt 0 -and ($activePath.Count -eq 0 -or ($activePath.Count -eq 1 -and $activePath[0] -eq 'help'))) {
        foreach ($commandName in $rootCommands) {
            if ($commandName -like "$currentWord*") {
                [void]$results.Add((New-OnemdCompletionResult -CompletionText $commandName -ListItemText $commandName -ResultType 'ParameterValue' -ToolTip 'onemd subcommand'))
            }
        }
    }

    if ($activeCommands.Count -gt 0 -and $activePath.Count -gt 0) {
        foreach ($commandName in $activeCommands) {
            if ($commandName -like "$currentWord*") {
                [void]$results.Add((New-OnemdCompletionResult -CompletionText $commandName -ListItemText $commandName -ResultType 'ParameterValue' -ToolTip 'onemd subcommand'))
            }
        }
    }

    foreach ($option in @($activeCatalog.Options)) {
        if ($currentWord -eq '') {
            foreach ($name in @($option.Names)) {
                [void]$results.Add((New-OnemdCompletionResult -CompletionText $name -ListItemText $name -ResultType 'ParameterName' -ToolTip $option.Description))
            }
        } else {
            foreach ($name in @($option.Names)) {
                if ($name -like "$currentWord*") {
                    [void]$results.Add((New-OnemdCompletionResult -CompletionText $name -ListItemText $name -ResultType 'ParameterName' -ToolTip $option.Description))
                }
            }
        }
    }

    $positionalTokens = @()
    foreach ($token in $tokensBeforeCurrent) {
        if ($token.StartsWith('-')) {
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
        $argumentSpec = $activeArguments[$positionalTokens.Count]
        if ($argumentSpec.PathLike) {
            $directoryOnly = $argumentSpec.Name -match 'folder|dir|path' -and $argumentSpec.Name -notmatch 'file'
            return @(Get-OnemdPathCompletions -InputPath $currentWord -DirectoryOnly:$directoryOnly)
        }

        return @(
            New-OnemdCompletionResult -CompletionText '<value>' -ListItemText '<value>' -ResultType 'ParameterValue' -ToolTip $argumentSpec.Description
        )
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
