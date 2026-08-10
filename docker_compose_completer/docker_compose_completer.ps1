# docker compose tab completion for PowerShell
# Help-driven completer for docker compose and docker-compose.

Set-StrictMode -Version 2.0

function New-DockerComposeCompletionResult {
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

function Remove-DockerComposeOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-DockerComposeQuotedValue {
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

function Get-DockerComposeExecutablePath {
    param([string]$CommandName)

    foreach ($candidate in @($CommandName, "$CommandName.exe")) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -ne $command) {
            return $command.Source
        }
    }

    if ($CommandName -eq 'docker' -or $CommandName -eq 'docker.exe') {
        foreach ($candidate in @('docker-compose', 'docker-compose.exe')) {
            $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if ($null -ne $command) {
                return $command.Source
            }
        }
    }

    if ($CommandName -eq 'docker-compose' -or $CommandName -eq 'docker-compose.exe') {
        foreach ($candidate in @('docker', 'docker.exe')) {
            $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if ($null -ne $command) {
                return $command.Source
            }
        }
    }

    return ''
}

function Get-DockerComposeHelpOutput {
    param(
        [string]$CommandName,
        [string]$SubcommandName
    )

    $commandPath = Get-DockerComposeExecutablePath -CommandName $CommandName
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return ''
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    if ($CommandName -in @('docker', 'docker.exe')) {
        [void]$arguments.Add('compose')
        if (-not [string]::IsNullOrWhiteSpace($SubcommandName)) {
            [void]$arguments.Add($SubcommandName)
        }
        [void]$arguments.Add('--help')
    } else {
        if (-not [string]::IsNullOrWhiteSpace($SubcommandName)) {
            [void]$arguments.Add($SubcommandName)
        }
        [void]$arguments.Add('--help')
    }

    try {
        return (& $commandPath @arguments 2>&1 | Out-String)
    } catch {
        return ''
    }
}

function Get-DockerComposeCompletionCatalog {
    $catalog = Get-Variable -Name 'DockerComposeCompletionCatalog' -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $catalog -and $null -ne $catalog.Value) {
        return $catalog.Value
    }

    $newCatalog = [ordered]@{
        Initialized = $false
        CommandName = $null
        RootOptions = @()
        RootSubcommands = @()
        RootOptionByName = @{}
        SubcommandCatalogs = @{}
    }

    Set-Variable -Name 'DockerComposeCompletionCatalog' -Value $newCatalog -Scope Script
    return (Get-Variable -Name 'DockerComposeCompletionCatalog' -Scope Script).Value
}

function ConvertTo-DockerComposeArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $typeName = $Value.GetType().FullName
        if ($typeName -like 'System.Collections.Generic.List*' -or $typeName -like 'System.Collections.Generic.IReadOnlyList*') {
            return @($Value.ToArray())
        }
    }

    return @($Value)
}

function Get-DockerComposeValueHints {
    param([string]$Text)

    $values = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Text) {
        return @()
    }

    if ($Text -match '\[(?<items>[^\]]+)\]') {
        foreach ($item in ($Matches.items -split '\|')) {
            $trimmed = $item.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                [void]$values.Add($trimmed)
            }
        }
    }

    $quotedMatches = [regex]::Matches($Text, '"([^"]+)"')
    foreach ($match in $quotedMatches) {
        $trimmed = $match.Groups[1].Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not ($values -contains $trimmed)) {
            [void]$values.Add($trimmed)
        }
    }

    return (ConvertTo-DockerComposeArray -Value $values)
}

function Test-DockerComposeSectionHeading {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return $Text -match '^(?:Options|Flags|Global Options|Commands|Management Commands|Available Commands|Additional Commands):$'
}

function ConvertFrom-DockerComposeHelp {
    param([string]$HelpText)

    $lines = @([regex]::Split($HelpText, '\r?\n'))
    $options = New-Object System.Collections.Generic.List[object]
    $subcommands = New-Object System.Collections.Generic.List[string]
    $optionByName = @{}

    $inOptions = $false
    $inCommands = $false

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $trimmed = $line.Trim()

        if (Test-DockerComposeSectionHeading -Text $trimmed) {
            if ($trimmed -match '^(?:Options|Flags|Global Options):$') {
                $inOptions = $true
                $inCommands = $false
                continue
            }

            if ($trimmed -match '^(?:Commands|Management Commands|Available Commands|Additional Commands):$') {
                $inOptions = $false
                $inCommands = $true
                continue
            }
        }

        if ($inOptions) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            if ($trimmed -match '^(?:Commands|Management Commands|Available Commands|Additional Commands):$') {
                $inOptions = $false
                $inCommands = $true
                continue
            }

            if ($trimmed -match '^(?:Run|Examples?|Aliases?|See also):') {
                $inOptions = $false
                $inCommands = $false
                continue
            }

            $optionMatches = [regex]::Matches($trimmed, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|$))')
            if ($optionMatches.Count -eq 0) {
                continue
            }

            $lastMatch = $optionMatches[$optionMatches.Count - 1]
            $valueSuffix = $trimmed.Substring($lastMatch.Index + $lastMatch.Length).Trim()
            $valuePrefix = if ($valueSuffix -match '^(\S+)') { $matches[1] } else { '' }
            $takesValue = $false
            if ($valuePrefix -match '^(stringArray|string|int|bytes|duration|float|boolean|bool|uint)$') {
                $takesValue = $true
            }

            $optionNames = New-Object System.Collections.Generic.List[string]
            foreach ($match in $optionMatches) {
                [void]$optionNames.Add($match.Value)
            }

            $values = Get-DockerComposeValueHints -Text $trimmed
            foreach ($optionName in @($optionNames)) {
                $entry = [pscustomobject]@{
                    Name = $optionName
                    TakesValue = $takesValue
                    Values = (ConvertTo-DockerComposeArray -Value $values)
                    Description = $trimmed
                }

                [void]$options.Add($entry)
                $optionByName[$optionName] = $entry
            }

            continue
        }

        if ($inCommands) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            if ($trimmed -match '^(?:Run|Examples?|Aliases?|See also):') {
                $inCommands = $false
                continue
            }

            if ($line -match '^\s{2,}([A-Za-z0-9][A-Za-z0-9-]*)\s{1,}') {
                [void]$subcommands.Add($matches[1])
            }
        }
    }

    New-Object psobject -Property @{
        Options = (ConvertTo-DockerComposeArray -Value $options)
        Subcommands = (ConvertTo-DockerComposeArray -Value ($subcommands | Sort-Object -Unique))
        OptionByName = $optionByName
    }
}

function Initialize-DockerComposeCompletionCatalog {
    param([string]$CommandName)

    $catalog = Get-DockerComposeCompletionCatalog
    if ($catalog.Initialized -and $catalog.CommandName -eq $CommandName) {
        return $catalog
    }

    $rootHelpText = Get-DockerComposeHelpOutput -CommandName $CommandName -SubcommandName ''
    $parsedRoot = ConvertFrom-DockerComposeHelp -HelpText $rootHelpText

    $catalog.CommandName = $CommandName
    $catalog.RootOptions = @($parsedRoot.Options)
    $catalog.RootSubcommands = @($parsedRoot.Subcommands)
    $catalog.RootOptionByName = $parsedRoot.OptionByName
    $catalog.Initialized = $true

    Set-Variable -Name 'DockerComposeCompletionCatalog' -Value $catalog -Scope Script
    return (Get-Variable -Name 'DockerComposeCompletionCatalog' -Scope Script).Value
}

function Get-DockerComposeSubcommandCatalog {
    param(
        [string]$CommandName,
        [string]$SubcommandName
    )

    if ([string]::IsNullOrWhiteSpace($SubcommandName)) {
        return New-Object psobject -Property @{
            Options = @()
            Subcommands = @()
            OptionByName = @{}
        }
    }

    $catalog = Initialize-DockerComposeCompletionCatalog -CommandName $CommandName
    if ($catalog.SubcommandCatalogs.ContainsKey($SubcommandName)) {
        return $catalog.SubcommandCatalogs[$SubcommandName]
    }

    $helpOutput = Get-DockerComposeHelpOutput -CommandName $CommandName -SubcommandName $SubcommandName
    $parsed = ConvertFrom-DockerComposeHelp -HelpText $helpOutput
    $parsedObject = New-Object psobject -Property @{
        Options = (ConvertTo-DockerComposeArray -Value $parsed.Options)
        Subcommands = (ConvertTo-DockerComposeArray -Value $parsed.Subcommands)
        OptionByName = $parsed.OptionByName
    }

    $catalog.SubcommandCatalogs[$SubcommandName] = $parsedObject
    Set-Variable -Name 'DockerComposeCompletionCatalog' -Value $catalog -Scope Script
    return $catalog.SubcommandCatalogs[$SubcommandName]
}

function Get-DockerComposeOptionSpec {
    param(
        [psobject]$Catalog,
        [string]$OptionName
    )

    if ($null -eq $Catalog -or [string]::IsNullOrWhiteSpace($OptionName)) {
        return $null
    }

    $optionByName = $Catalog.OptionByName
    if ($null -eq $optionByName) {
        return $null
    }

    if ($optionByName.ContainsKey($OptionName)) {
        return $optionByName[$OptionName]
    }

    if ($optionByName.ContainsKey($OptionName.ToLowerInvariant())) {
        return $optionByName[$OptionName.ToLowerInvariant()]
    }

    return $null
}

function Get-DockerComposeTokens {
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
            [void]$tokens.Add($element.Extent.Text.Trim())
        }
    }

    return (ConvertTo-DockerComposeArray -Value $tokens)
}

function Get-DockerComposeCommandName {
    param([System.Management.Automation.Language.CommandAst]$CommandAst)

    if ($null -eq $CommandAst) {
        return ''
    }

    $firstElement = $CommandAst.CommandElements | Select-Object -First 1
    if ($null -eq $firstElement) {
        return ''
    }

    return $firstElement.Extent.Text.Trim()
}

function Get-DockerComposePathCompletions {
    param(
        [string]$InputPath,
        [bool]$DirectoryOnly = $false
    )

    $cleanInput = Remove-DockerComposeOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-DockerComposeQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-DockerComposeCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-DockerComposeCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Complete-DockerCompose {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $commandName = Get-DockerComposeCommandName -CommandAst $commandAst
    $currentWord = if ($null -eq $wordToComplete) { '' } else { $wordToComplete }
    $tokensBeforeCurrent = @(Get-DockerComposeTokens -CommandAst $commandAst -CursorPosition $cursorPosition)
    $catalog = Initialize-DockerComposeCompletionCatalog -CommandName $commandName

    $composeTokens = @()
    $isComposeSurface = $false

    if ($commandName -in @('docker', 'docker.exe')) {
        if ($tokensBeforeCurrent.Count -gt 0 -and $tokensBeforeCurrent[0] -eq 'compose') {
            $composeTokens = @($tokensBeforeCurrent | Select-Object -Skip 1)
            $isComposeSurface = $true
        } elseif ($tokensBeforeCurrent.Count -eq 0) {
            $isComposeSurface = $true
            $composeTokens = @()
        } elseif ($tokensBeforeCurrent.Count -gt 0 -and $tokensBeforeCurrent[0] -notin @('compose')) {
            $isComposeSurface = $false
            $composeTokens = @()
        }
    } elseif ($commandName -in @('docker-compose', 'docker-compose.exe')) {
        $composeTokens = $tokensBeforeCurrent
        $isComposeSurface = $true
    }

    if (-not $isComposeSurface) {
        return @()
    }

    $activeCatalog = New-Object psobject -Property @{
        Options = (ConvertTo-DockerComposeArray -Value $catalog.RootOptions)
        Subcommands = (ConvertTo-DockerComposeArray -Value $catalog.RootSubcommands)
        OptionByName = $catalog.RootOptionByName
    }
    $contextTokens = @($composeTokens)
    $subcommandName = $null

    if ($contextTokens.Count -gt 0) {
        $candidate = $contextTokens[0]
        if ($candidate -in @($catalog.RootSubcommands)) {
            $subcommandName = $candidate
            $contextTokens = @($contextTokens | Select-Object -Skip 1)
            $activeCatalog = Get-DockerComposeSubcommandCatalog -CommandName $commandName -SubcommandName $subcommandName
        }
    }

    if ($contextTokens.Count -gt 0) {
        $previousToken = $contextTokens[-1]
        if ($previousToken -and $previousToken.StartsWith('-')) {
            $optionSpec = Get-DockerComposeOptionSpec -Catalog $activeCatalog -OptionName $previousToken
            if ($null -ne $optionSpec -and $optionSpec.TakesValue) {
                $valueChoices = @($optionSpec.Values)
                if ($valueChoices.Count -gt 0) {
                    return @(
                        foreach ($value in $valueChoices) {
                            if ($value -like "$currentWord*") {
                                New-DockerComposeCompletionResult -CompletionText $value -ListItemText $value -ResultType 'ParameterValue' -ToolTip $optionSpec.Description
                            }
                        }
                    )
                }

                $pathLikeOptions = @('-f', '--file', '--env-file', '--project-directory', '--output')
                if ($optionSpec.Name -in $pathLikeOptions -or ($optionSpec.Name -and $optionSpec.Name.StartsWith('--') -and $optionSpec.Name -in @('--file', '--env-file', '--project-directory', '--output'))) {
                    return @(Get-DockerComposePathCompletions -InputPath $currentWord -DirectoryOnly ($optionSpec.Name -eq '--project-directory'))
                }

                return @(
                    New-DockerComposeCompletionResult -CompletionText '<value>' -ListItemText '<value>' -ResultType 'ParameterValue' -ToolTip $optionSpec.Description
                )
            }
        }
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in @($activeCatalog.Options)) {
                if ($option.Name -like "$currentWord*") {
                    New-DockerComposeCompletionResult -CompletionText $option.Name -ListItemText $option.Name -ResultType 'ParameterName' -ToolTip $option.Description
                }
            }
        )
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($subcommand in @($activeCatalog.Subcommands)) {
        if ($subcommand -like "$currentWord*") {
            [void]$results.Add((New-DockerComposeCompletionResult -CompletionText $subcommand -ListItemText $subcommand -ResultType 'ParameterValue' -ToolTip 'docker compose subcommand'))
        }
    }

    foreach ($option in @($activeCatalog.Options)) {
        if ($option.Name -like "$currentWord*" -or $option.Name.TrimStart('-') -like "$currentWord*") {
            [void]$results.Add((New-DockerComposeCompletionResult -CompletionText $option.Name -ListItemText $option.Name -ResultType 'ParameterName' -ToolTip $option.Description))
        }
    }

    if ($commandName -in @('docker', 'docker.exe') -and [string]::IsNullOrWhiteSpace($currentWord)) {
        [void]$results.Add((New-DockerComposeCompletionResult -CompletionText 'compose' -ListItemText 'compose' -ResultType 'ParameterValue' -ToolTip 'docker compose root command'))
    }

    return (ConvertTo-DockerComposeArray -Value $results)
}

Register-ArgumentCompleter -Native -CommandName @('docker', 'docker.exe', 'docker-compose', 'docker-compose.exe') -ScriptBlock {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Complete-DockerCompose -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
