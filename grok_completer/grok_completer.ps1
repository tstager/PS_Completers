# grok tab completion for PowerShell
# Help-driven native completer for grok and grok.exe.

Set-StrictMode -Version 2.0

function New-GrokCompletionResult {
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

function Get-GrokCommandPath {
    foreach ($candidate in @('grok', 'grok.exe')) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -ne $command) {
            return $command.Source
        }
    }
}

function Get-GrokRootHelpOutput {
    $commandPath = Get-GrokCommandPath
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return ''
    }

    try {
        return (& $commandPath --help 2>&1 | Out-String)
    } catch {
        return ''
    }
}

function Get-GrokSubcommandHelpOutput {
    param([string]$SubcommandName)

    $commandPath = Get-GrokCommandPath
    if ([string]::IsNullOrWhiteSpace($commandPath) -or [string]::IsNullOrWhiteSpace($SubcommandName)) {
        return ''
    }

    try {
        return (& $commandPath help $SubcommandName 2>&1 | Out-String)
    } catch {
        return ''
    }
}

function ConvertFrom-GrokHelp {
    param([string]$HelpText)

    $lines = @([regex]::Split($HelpText, '\r?\n'))
    $options = New-Object System.Collections.Generic.List[object]
    $subcommands = New-Object System.Collections.Generic.List[string]
    $arguments = New-Object System.Collections.Generic.List[object]
    $optionByName = @{}

    $inCommands = $false
    $inOptions = $false
    $inArguments = $false

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $trimmed = $line.Trim()

        if ($trimmed -eq 'Commands:') {
            $inCommands = $true
            $inOptions = $false
            $inArguments = $false
            continue
        }

        if ($trimmed -eq 'Arguments:') {
            $inCommands = $false
            $inOptions = $false
            $inArguments = $true
            continue
        }

        if ($trimmed -eq 'Options:') {
            $inCommands = $false
            $inOptions = $true
            $inArguments = $false
            continue
        }

        if ($inCommands) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            if ($trimmed -match '^\s*([A-Za-z0-9][A-Za-z0-9-]*)\s{2,}') {
                $subName = $matches[1]
                if ($subName -notin @('help')) {
                    [void]$subcommands.Add($subName)
                }
            }

            continue
        }

        if ($inArguments) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            if ($trimmed -match '^\s*(<[^>]+>|\[[^]]+\])\s{2,}(.*)$') {
                $argName = $matches[1]
                $description = $matches[2]

                if ([string]::IsNullOrWhiteSpace($description) -and $index + 1 -lt $lines.Count) {
                    $nextLine = $lines[$index + 1].Trim()
                    if (-not [string]::IsNullOrWhiteSpace($nextLine)) {
                        $description = $nextLine
                    }
                }

                $values = @()
                if ($description -match '\[possible values:\s*(.+?)\]') {
                    $values = @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                }

                $entry = [pscustomobject]@{
                    Name = $argName
                    Values = @($values)
                    Description = $description
                }

                [void]$arguments.Add($entry)
            }

            continue
        }

        if ($inOptions) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            $optionNames = New-Object System.Collections.Generic.List[string]
            $parseLine = $trimmed
            while ($parseLine -match '^(?<option>--?[A-Za-z0-9][A-Za-z0-9-]*)(?<rest>.*)$') {
                [void]$optionNames.Add($matches.option)
                $parseLine = $matches.rest

                if ($parseLine -match '^\s*$') {
                    break
                }

                if ($parseLine -match '^\s*,\s*') {
                    $parseLine = $parseLine -replace '^\s*,\s*', ''
                    continue
                }

                if ($parseLine -match '^\s+') {
                    $parseLine = $parseLine.TrimStart()
                    continue
                }

                break
            }

            if ($optionNames.Count -eq 0) {
                continue
            }

            $description = ''
            $nextLine = $null
            if ($index + 1 -lt $lines.Count) {
                $nextLine = $lines[$index + 1].Trim()
                if (-not [string]::IsNullOrWhiteSpace($nextLine)) {
                    $description = $nextLine
                }
            }

            $hasValue = $line -match '<[^>]+>' -or $line -match '\[[^]]*<[^>]+>'
            $values = @()
            if ($description -match '\[possible values:\s*(.+?)\]') {
                $values = @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }

            foreach ($optionName in $optionNames) {
                $entry = [pscustomobject]@{
                    Name = $optionName
                    TakesValue = $hasValue
                    Values = @($values)
                    Description = $description
                }

                [void]$options.Add($entry)
                $optionByName[$optionName] = $entry
            }
        }
    }

    [pscustomobject]@{
        Options = (ConvertTo-GrokArray -Value $options)
        Subcommands = (ConvertTo-GrokArray -Value ($subcommands.ToArray() | Sort-Object -Unique))
        Arguments = (ConvertTo-GrokArray -Value $arguments)
        OptionByName = $optionByName
    }
}

function Get-GrokCompletionCatalog {
    $catalog = Get-Variable -Name 'GrokCompletionCatalog' -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $catalog -and $null -ne $catalog.Value) {
        return $catalog.Value
    }

    $newCatalog = [ordered]@{
        Initialized = $false
        CommandPath = $null
        RootHelpText = ''
        RootSubcommands = @()
        RootOptions = @()
        RootArguments = @()
        RootOptionByName = @{}
        SubcommandCatalogs = @{}
    }

    Set-Variable -Name 'GrokCompletionCatalog' -Value $newCatalog -Scope Script
    return (Get-Variable -Name 'GrokCompletionCatalog' -Scope Script).Value
}

function Initialize-GrokCompletionCatalog {
    $catalog = Get-GrokCompletionCatalog
    if ($catalog.Initialized) {
        return $catalog
    }

    $catalog.CommandPath = Get-GrokCommandPath
    $catalog.RootHelpText = Get-GrokRootHelpOutput

    $rootHelp = ConvertFrom-GrokHelp -HelpText $catalog.RootHelpText
    $catalog.RootSubcommands = (ConvertTo-GrokArray -Value $rootHelp.Subcommands)
    $catalog.RootOptions = (ConvertTo-GrokArray -Value $rootHelp.Options)
    $catalog.RootArguments = (ConvertTo-GrokArray -Value $rootHelp.Arguments)
    $catalog.RootOptionByName = $rootHelp.OptionByName

    $catalog.Initialized = $true
    Set-Variable -Name 'GrokCompletionCatalog' -Value $catalog -Scope Script
    return (Get-Variable -Name 'GrokCompletionCatalog' -Scope Script).Value
}

function Get-GrokSubcommandCatalog {
    param([string]$SubcommandName)

    if ([string]::IsNullOrWhiteSpace($SubcommandName)) {
        return [pscustomobject]@{
            Options = @()
            Subcommands = @()
            Arguments = @()
            OptionByName = @{}
        }
    }

    $catalog = Initialize-GrokCompletionCatalog
    if ($catalog.SubcommandCatalogs.ContainsKey($SubcommandName)) {
        return $catalog.SubcommandCatalogs[$SubcommandName]
    }

    $helpOutput = Get-GrokSubcommandHelpOutput -SubcommandName $SubcommandName
    $parsed = ConvertFrom-GrokHelp -HelpText $helpOutput
    $parsedObject = [pscustomobject]@{
        Options = (ConvertTo-GrokArray -Value $parsed.Options)
        Subcommands = (ConvertTo-GrokArray -Value $parsed.Subcommands)
        Arguments = (ConvertTo-GrokArray -Value $parsed.Arguments)
        OptionByName = $parsed.OptionByName
    }

    $catalog.SubcommandCatalogs[$SubcommandName] = $parsedObject
    Set-Variable -Name 'GrokCompletionCatalog' -Value $catalog -Scope Script
    return $catalog.SubcommandCatalogs[$SubcommandName]
}

function ConvertTo-GrokArray {
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

function Get-GrokCurrentToken {
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

function Get-GrokCommandTokens {
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

    return (ConvertTo-GrokArray -Value $tokens)
}

function Get-GrokPathCompletions {
    param([string]$InputPath)

    $cleanInput = $InputPath
    if ($null -eq $cleanInput) {
        $cleanInput = ''
    }

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
            New-GrokCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-GrokCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-GrokOptionSpec {
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

function Complete-Grok {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $catalog = Initialize-GrokCompletionCatalog
    $currentWord = if ($null -eq $wordToComplete) { '' } else { $wordToComplete }
    $tokensBeforeCurrent = @(Get-GrokCommandTokens -CommandAst $commandAst -CursorPosition $cursorPosition)
    $currentToken = $currentWord

    $subcommandName = $null
    if ($tokensBeforeCurrent.Count -gt 0) {
        $firstToken = $tokensBeforeCurrent[0]
        if ($firstToken -and -not $firstToken.StartsWith('-') -and $catalog.RootSubcommands -contains $firstToken) {
            $subcommandName = $firstToken
        }
    }

    $activeCatalog = if ($subcommandName) { Get-GrokSubcommandCatalog -SubcommandName $subcommandName } else { [pscustomobject]@{ Options = (ConvertTo-GrokArray -Value $catalog.RootOptions); Subcommands = (ConvertTo-GrokArray -Value $catalog.RootSubcommands); Arguments = (ConvertTo-GrokArray -Value $catalog.RootArguments); OptionByName = $catalog.RootOptionByName } }

    if ($tokensBeforeCurrent.Count -gt 0) {
        $candidateOption = $tokensBeforeCurrent[-1]
        if ($candidateOption -and $candidateOption.StartsWith('-')) {
            $optionSpec = Get-GrokOptionSpec -Catalog $activeCatalog -OptionName $candidateOption
            if ($null -ne $optionSpec -and $optionSpec.TakesValue) {
                if ($optionSpec.Values.Count -gt 0) {
                    return @(
                        foreach ($value in $optionSpec.Values) {
                            if ($value -like "$currentToken*") {
                                New-GrokCompletionResult -CompletionText $value -ListItemText $value -ResultType 'ParameterValue' -ToolTip $optionSpec.Description
                            }
                        }
                    )
                }

                $pathLikeOptions = @('cwd', 'agent-profile', 'prompt-file', 'debug-file', 'leader-socket', 'worktree-ref')
                if ($optionSpec.Name -in $pathLikeOptions -or $optionSpec.Name -in @('--cwd', '--agent-profile', '--prompt-file', '--debug-file', '--leader-socket', '--worktree-ref')) {
                    return @(Get-GrokPathCompletions -InputPath $currentToken)
                }

                return @(
                    New-GrokCompletionResult -CompletionText '<value>' -ListItemText '<value>' -ResultType 'ParameterValue' -ToolTip $optionSpec.Description
                )
            }
        }
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ($subcommandName -eq 'completions' -and $tokensBeforeCurrent.Count -eq 1 -and -not $currentWord.StartsWith('-')) {
        $argumentSpec = $null
        foreach ($argument in @($activeCatalog.Arguments)) {
            if ($argument.Name -match '^<') {
                $argumentSpec = $argument
                break
            }
        }

        if ($null -ne $argumentSpec -and $argumentSpec.Values.Count -gt 0) {
            foreach ($value in $argumentSpec.Values) {
                if ($value -like "$currentToken*") {
                    [void]$results.Add((New-GrokCompletionResult -CompletionText $value -ListItemText $value -ResultType 'ParameterValue' -ToolTip 'Shell for grok completions'))
                }
            }

            return (ConvertTo-GrokArray -Value $results)
        }
    }

    if ($currentWord.StartsWith('-')) {
        foreach ($option in @($activeCatalog.Options)) {
            if ($option.Name -like "$currentWord*") {
                [void]$results.Add((New-GrokCompletionResult -CompletionText $option.Name -ListItemText $option.Name -ResultType 'ParameterName' -ToolTip $option.Description))
            }
        }
    } else {
        # When not starting with '-', offer both subcommands and options at the command level
        foreach ($subcommand in @($activeCatalog.Subcommands)) {
            if ($subcommand -like "$currentWord*") {
                [void]$results.Add((New-GrokCompletionResult -CompletionText $subcommand -ListItemText $subcommand -ResultType 'ParameterValue' -ToolTip 'grok subcommand'))
            }
        }

        # Also offer options at the command level (with '-' prefix)
        foreach ($option in @($activeCatalog.Options)) {
            if ($option.Name -like "-$currentWord*") {
                [void]$results.Add((New-GrokCompletionResult -CompletionText $option.Name -ListItemText $option.Name -ResultType 'ParameterName' -ToolTip $option.Description))
            }
        }
    }

    return (ConvertTo-GrokArray -Value $results)
}

Register-ArgumentCompleter -Native -CommandName @('grok', 'grok.exe', 'agent') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Grok -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
