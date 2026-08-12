# docker tab completion for PowerShell
# Help-driven completer for the Docker CLI, including nested subcommands such as compose.

Set-StrictMode -Version 2.0

function New-DockerCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip = '',
        [string]$ListItemText = ''
    )

    if ([string]::IsNullOrWhiteSpace($CompletionText)) {
        return $null
    }

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

function Get-DockerExecutablePath {
    foreach ($candidate in @('docker', 'docker.exe')) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -ne $command) {
            return $command.Source
        }
    }

    return ''
}

function Get-DockerCatalogCache {
    $cache = Get-Variable -Name 'DockerCatalogCache' -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $cache -or $null -eq $cache.Value) {
        Set-Variable -Name 'DockerCatalogCache' -Value @{} -Scope Script
    }

    return (Get-Variable -Name 'DockerCatalogCache' -Scope Script).Value
}

function Get-DockerHelpText {
    param([string[]]$Segments)

    $commandPath = Get-DockerExecutablePath
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return ''
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    foreach ($segment in @($Segments)) {
        if (-not [string]::IsNullOrWhiteSpace($segment)) {
            [void]$arguments.Add($segment)
        }
    }

    [void]$arguments.Add('--help')

    try {
        return (& $commandPath @arguments 2>&1 | Out-String)
    } catch {
        return ''
    }
}

function ConvertFrom-DockerHelp {
    param([string]$HelpText)

    $lines = @([regex]::Split($HelpText, '\r?\n'))
    $options = New-Object System.Collections.Generic.List[object]
    $commands = New-Object System.Collections.Generic.List[string]
    $optionByName = @{}

    $inOptions = $false
    $inCommands = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($trimmed -match '^(?:Options|Flags|Global Options):$') {
            $inOptions = $true
            $inCommands = $false
            continue
        }

        if ($trimmed -match '^(?:Commands|Common Commands|Management Commands|Available Commands|Additional Commands|Swarm Commands):$') {
            $inOptions = $false
            $inCommands = $true
            continue
        }

        if ($inOptions) {
            $optionMatches = [regex]::Matches($trimmed, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(?:\s|,|$))')
            if ($optionMatches.Count -eq 0) {
                continue
            }

            $names = New-Object System.Collections.Generic.List[string]
            foreach ($match in $optionMatches) {
                $value = $match.Value.Trim()
                if (-not [string]::IsNullOrWhiteSpace($value) -and -not $names.Contains($value)) {
                    [void]$names.Add($value)
                }
            }

            if ($names.Count -eq 0) {
                continue
            }

            $lastName = $names[$names.Count - 1]
            $suffix = $trimmed.Substring($trimmed.IndexOf($lastName) + $lastName.Length).Trim()
            $takesValue = $false
            if ($suffix -match '^(?:\s+|,\s*)(?:string(?:Array)?|int|bytes|float|bool(?:ean)?|duration|path|directory|value|list)') {
                $takesValue = $true
            }

            $entry = [pscustomobject]@{
                Name = $lastName
                Names = @($names)
                TakesValue = $takesValue
                Description = $trimmed
            }

            [void]$options.Add($entry)
            foreach ($name in $entry.Names) {
                if (-not $optionByName.ContainsKey($name)) {
                    $optionByName[$name] = $entry
                }
            }
        }
        elseif ($inCommands) {
            if ($line -match '^\s{2,}(?<command>[A-Za-z0-9][A-Za-z0-9-]*)\*?(?:\s{2,}|$)') {
                $commandName = $matches.command.Trim('*')
                if (-not [string]::IsNullOrWhiteSpace($commandName)) {
                    [void]$commands.Add($commandName)
                }
            }
        }
    }

    if (-not $optionByName.ContainsKey('-h')) {
        $optionByName['-h'] = [pscustomobject]@{
            Name = '-h'
            Names = @('-h', '--help')
            TakesValue = $false
            Description = 'Show help'
        }
    }

    if (-not $optionByName.ContainsKey('--help')) {
        $optionByName['--help'] = [pscustomobject]@{
            Name = '--help'
            Names = @('-h', '--help')
            TakesValue = $false
            Description = 'Show help'
        }
    }

    $uniqueCommands = @($commands.ToArray() | Sort-Object -Unique)

    return [pscustomobject]@{
        Commands = $uniqueCommands
        Options = @($options.ToArray())
        OptionByName = $optionByName
    }
}

function Get-DockerCommandCatalog {
    param([string[]]$Segments)

    $cache = Get-DockerCatalogCache
    $cacheKey = if ($Segments.Count -gt 0) { ($Segments | Where-Object { $_ } | ForEach-Object { $_ }) -join ' ' } else { '<root>' }
    if ($cache.ContainsKey($cacheKey)) {
        return $cache[$cacheKey]
    }

    $helpText = Get-DockerHelpText -Segments $Segments
    $catalog = ConvertFrom-DockerHelp -HelpText $helpText
    $cache[$cacheKey] = $catalog
    return $catalog
}

function Get-DockerCommandTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = New-Object System.Collections.Generic.List[string]

    if ($null -eq $CommandAst) {
        return @()
    }

    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($null -eq $element) {
            continue
        }

        $extent = $element.Extent
        if ($extent -and $extent.EndOffset -le $CursorPosition) {
            $text = $extent.Text.Trim()
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                [void]$tokens.Add($text)
            }
        }
    }

    return $tokens.ToArray()
}

function Get-DockerCompletionContext {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    if ($null -eq $CommandAst) {
        return $null
    }

    $elements = @($CommandAst.CommandElements)
    if ($elements.Count -lt 1) {
        return $null
    }

    $commandName = $elements[0].Extent.Text.Trim()
    if ($commandName -notin @('docker', 'docker.exe')) {
        return $null
    }

    $catalog = Get-DockerCommandCatalog -Segments @()
    $path = New-Object System.Collections.Generic.List[string]
    $tokens = @(Get-DockerCommandTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)

    foreach ($token in $tokens) {
        if ($token -eq 'docker' -or $token -eq 'docker.exe') {
            continue
        }

        if ($token -match '^-') {
            break
        }

        $subcommands = @($catalog.Commands)
        if ($token -in $subcommands) {
            [void]$path.Add($token)
            $catalog = Get-DockerCommandCatalog -Segments @($path.ToArray())
            continue
        }

        break
    }

    return [pscustomobject]@{
        CommandName = $commandName
        Tokens = $tokens
        Path = $path.ToArray()
        Catalog = $catalog
    }
}

function Complete-DockerCommand {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $context = Get-DockerCompletionContext -CommandAst $commandAst -CursorPosition $cursorPosition
    if ($null -eq $context) {
        return @()
    }

    $prefix = if ($null -eq $wordToComplete) { '' } else { $wordToComplete }
    $results = New-Object System.Collections.Generic.List[object]

    if ($prefix -match '^-') {
        foreach ($option in @($context.Catalog.Options)) {
            foreach ($optionName in @($option.Names)) {
                if ($optionName -like "$prefix*") {
                    [void]$results.Add((New-DockerCompletionResult -CompletionText $optionName -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $optionName))
                }
            }
        }

        return [object[]]$results
    }

    foreach ($command in @($context.Catalog.Commands)) {
        if ($command -like "$prefix*") {
            $toolTip = "docker $($context.Path -join ' ') $command"
            [void]$results.Add((New-DockerCompletionResult -CompletionText $command -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $command))
        }
    }

    foreach ($option in @($context.Catalog.Options)) {
        foreach ($optionName in @($option.Names)) {
            if ($optionName -like "$prefix*") {
                [void]$results.Add((New-DockerCompletionResult -CompletionText $optionName -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $optionName))
            }
        }
    }

    return [object[]]$results
}

Register-ArgumentCompleter -Native -CommandName @('docker', 'docker.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-DockerCommand -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
