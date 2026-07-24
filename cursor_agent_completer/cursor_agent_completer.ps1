<#
.SYNOPSIS
Registers a native PowerShell argument completer for the Cursor Agent CLI.

.DESCRIPTION
Provides standalone completion for `cursor-agent`, `cursor-agent.cmd`, and
`cursor-agent.ps1` using live help output from the installed CLI.
#>

Set-StrictMode -Version 2.0

function New-CursorAgentCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
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

function Get-CursorAgentCommandPath {
    foreach ($candidate in @('cursor-agent.cmd', 'cursor-agent.ps1', 'cursor-agent')) {
        $command = Get-Command -Name $candidate -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -ne $command) {
            if ($command.Source) {
                return $command.Source
            }

            return $command.Name
        }
    }

    return $null
}

function Get-CursorAgentRootHelpOutput {
    $commandPath = Get-CursorAgentCommandPath
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return ''
    }

    try {
        return (& $commandPath --help 2>&1 | Out-String)
    } catch {
        return ''
    }
}

function Get-CursorAgentSubcommandHelpOutput {
    param([string]$SubcommandName)

    $commandPath = Get-CursorAgentCommandPath
    if ([string]::IsNullOrWhiteSpace($commandPath) -or [string]::IsNullOrWhiteSpace($SubcommandName)) {
        return ''
    }

    try {
        return (& $commandPath $SubcommandName --help 2>&1 | Out-String)
    } catch {
        return ''
    }
}

function ConvertFrom-CursorAgentHelpText {
    param([string]$HelpText)

    $lines = @([regex]::Split($HelpText, '\r?\n'))
    $options = New-Object System.Collections.Generic.List[object]
    $subcommands = New-Object System.Collections.Generic.List[string]
    $inOptions = $false
    $inCommands = $false

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $trimmed = $line.Trim()

        if ($trimmed -eq 'Options:') {
            $inOptions = $true
            $inCommands = $false
            continue
        }

        if ($trimmed -eq 'Commands:') {
            $inOptions = $false
            $inCommands = $true
            continue
        }

        if ($trimmed -eq 'Arguments:') {
            $inOptions = $false
            $inCommands = $false
            continue
        }

        if ($inOptions) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                $inOptions = $false
                continue
            }

            $contentLine = $line.TrimStart()
            $parts = [regex]::Split($contentLine, '\s{2,}', 2)
            if ($parts.Count -lt 2) {
                continue
            }

            $namesPart = $parts[0].Trim()
            $description = $parts[1].Trim()
            $optionNames = @([regex]::Matches($namesPart, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|$))') |
                ForEach-Object { $_.Value.Trim() })

            if ($optionNames.Count -eq 0) {
                continue
            }

            $takesValue = ($namesPart -match '<[^>]+>') -or ($namesPart -match '\[[^]]*\]')
            [void]$options.Add([pscustomobject]@{
                    Names        = @($optionNames)
                    TakesValue   = [bool]$takesValue
                    Description  = $description
                })

            continue
        }

        if ($inCommands) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                $inCommands = $false
                continue
            }

            $contentLine = $line.TrimStart()
            $parts = [regex]::Split($contentLine, '\s{2,}', 2)
            if ($parts.Count -lt 2) {
                continue
            }

            $commandToken = $parts[0].Trim()
            if ([string]::IsNullOrWhiteSpace($commandToken)) {
                continue
            }

            $commandToken = ($commandToken -split '\s', 2)[0]
            $commandToken = ($commandToken -split '<', 2)[0]
            $commandNames = @($commandToken.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            foreach ($commandName in $commandNames) {
                if ($commandName -match '^[A-Za-z0-9][A-Za-z0-9-]*$') {
                    [void]$subcommands.Add($commandName)
                }
            }
        }
    }

    [pscustomobject]@{
        Options     = @($options.ToArray())
        Subcommands = @($subcommands.ToArray() | Sort-Object -Unique)
    }
}

function Get-CursorAgentCompletionCatalog {
    $existing = Get-Variable -Name 'CursorAgentCompletionCatalog' -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $existing -and $null -ne $existing.Value) {
        return $existing.Value
    }

    $catalog = [ordered]@{
        Initialized       = $false
        CommandPath       = $null
        RootHelpText      = ''
        RootOptions       = @()
        RootSubcommands   = @()
        SubcommandCatalogs = @{}
    }

    Set-Variable -Name 'CursorAgentCompletionCatalog' -Value $catalog -Scope Script
    return (Get-Variable -Name 'CursorAgentCompletionCatalog' -Scope Script).Value
}

function Initialize-CursorAgentCompletionCatalog {
    $catalog = Get-CursorAgentCompletionCatalog
    if ($catalog.Initialized) {
        return $catalog
    }

    $catalog.CommandPath = Get-CursorAgentCommandPath
    $catalog.RootHelpText = Get-CursorAgentRootHelpOutput
    $rootHelp = ConvertFrom-CursorAgentHelpText -HelpText $catalog.RootHelpText
    $catalog.RootOptions = @($rootHelp.Options)
    $catalog.RootSubcommands = @($rootHelp.Subcommands)

    $mcpHelp = Get-CursorAgentSubcommandHelpOutput -SubcommandName 'mcp'
    if (-not [string]::IsNullOrWhiteSpace($mcpHelp)) {
        $catalog.SubcommandCatalogs['mcp'] = ConvertFrom-CursorAgentHelpText -HelpText $mcpHelp
    }

    $catalog.Initialized = $true
    Set-Variable -Name 'CursorAgentCompletionCatalog' -Value $catalog -Scope Script
    return (Get-Variable -Name 'CursorAgentCompletionCatalog' -Scope Script).Value
}

function Get-CursorAgentValueHints {
    @{ 
        '--mode' = @('plan', 'ask')
        '--output-format' = @('text', 'json', 'stream-json')
        '--sandbox' = @('enabled', 'disabled')
    }
}

function Get-CursorAgentPathOptions {
    @('--workspace', '--add-dir', '--plugin-dir')
}

function Get-CursorAgentPlaceholderValue {
    param([string]$OptionName)

    switch ($OptionName) {
        '--api-key' { return '<key>' }
        '--header' { return '<header>' }
        '--model' { return '<model>' }
        '--resume' { return '<chatId>' }
        '--worktree' { return '<name>' }
        '--worktree-base' { return '<branch>' }
        default { return '<value>' }
    }
}

function Get-CursorAgentPathCompletions {
    param([string]$WordToComplete)

    if ([string]::IsNullOrWhiteSpace($WordToComplete) -or $WordToComplete -eq '.') {
        $WordToComplete = ''
    }

    $prefix = $WordToComplete
    if ($prefix.StartsWith('~')) {
        $prefix = $prefix -replace '^~', $HOME
    }

    $basePath = Split-Path -Path $prefix -Parent
    $leafName = Split-Path -Path $prefix -Leaf

    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = (Get-Location).Path
    }

    if (-not (Test-Path -LiteralPath $basePath)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $basePath -Force -ErrorAction SilentlyContinue)
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($item in $items) {
        if (-not [string]::IsNullOrWhiteSpace($leafName) -and $item.Name -notlike "$leafName*") {
            continue
        }

        $displayText = $item.Name
        if ($item.PSIsContainer) {
            $displayText = $displayText + [System.IO.Path]::DirectorySeparatorChar
        }

        $displayPath = $displayText
        if ($prefix -match '[\\/]' -or $prefix.StartsWith('~') -or $prefix.StartsWith('.')) {
            $displayPath = Join-Path -Path $basePath -ChildPath $item.Name
            if ($item.PSIsContainer) {
                $displayPath = $displayPath + [System.IO.Path]::DirectorySeparatorChar
            }
        }

        [void]$results.Add((New-CursorAgentCompletionResult -CompletionText $displayPath -ResultType 'ParameterValue' -ToolTip $item.FullName -ListItemText $displayText))
    }

    return @($results.ToArray())
}

function Complete-CursorAgent {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $catalog = Initialize-CursorAgentCompletionCatalog
    $results = New-Object System.Collections.Generic.List[object]

    $tokens = @()
    if ($null -ne $commandAst) {
        $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
        if ($elements.Count -gt 1) {
            $tokens = @($elements | Select-Object -Skip 1)
            if ($tokens.Count -gt 0 -and $tokens[-1] -eq $wordToComplete) {
                $tokens = @($tokens | Select-Object -First ($tokens.Count - 1))
            }
        }
    }

    $previousToken = if ($tokens.Count -gt 0) { $tokens[-1] } else { $null }
    $prefix = $wordToComplete

    if ($previousToken -and ($previousToken -match '^--') -and $previousToken -in @('--mode', '--output-format', '--sandbox')) {
        $valueHints = Get-CursorAgentValueHints
        foreach ($hint in @($valueHints[$previousToken])) {
            if ([string]::IsNullOrWhiteSpace($prefix) -or $hint -like "$prefix*") {
                [void]$results.Add((New-CursorAgentCompletionResult -CompletionText $hint -ResultType 'ParameterValue' -ToolTip $hint -ListItemText $hint))
            }
        }

        return @($results.ToArray())
    }

    if ($previousToken -and ($previousToken -match '^--') -and ($previousToken -in (Get-CursorAgentPathOptions))) {
        return Get-CursorAgentPathCompletions -WordToComplete $prefix
    }

    if ($previousToken -and ($previousToken -match '^--')) {
        $placeholder = Get-CursorAgentPlaceholderValue -OptionName $previousToken
        if ([string]::IsNullOrWhiteSpace($prefix) -or $placeholder -like "$prefix*") {
            [void]$results.Add((New-CursorAgentCompletionResult -CompletionText $placeholder -ResultType 'ParameterValue' -ToolTip $placeholder -ListItemText $placeholder))
        }

        return @($results.ToArray())
    }

    if ($tokens.Count -gt 0 -and $tokens[0] -eq 'mcp') {
        $mcpCatalog = $catalog.SubcommandCatalogs['mcp']
        if ($null -ne $mcpCatalog) {
            foreach ($subcommand in @($mcpCatalog.Subcommands)) {
                if ([string]::IsNullOrWhiteSpace($prefix) -or $subcommand -like "$prefix*") {
                    [void]$results.Add((New-CursorAgentCompletionResult -CompletionText $subcommand -ResultType 'ParameterValue' -ToolTip $subcommand -ListItemText $subcommand))
                }
            }
        }

        return @($results.ToArray())
    }

    foreach ($option in @($catalog.RootOptions)) {
        foreach ($optionName in @($option.Names)) {
            if ([string]::IsNullOrWhiteSpace($prefix) -or $optionName -like "$prefix*") {
                [void]$results.Add((New-CursorAgentCompletionResult -CompletionText $optionName -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $optionName))
            }
        }
    }

    foreach ($subcommand in @($catalog.RootSubcommands)) {
        if ([string]::IsNullOrWhiteSpace($prefix) -or $subcommand -like "$prefix*") {
            [void]$results.Add((New-CursorAgentCompletionResult -CompletionText $subcommand -ResultType 'ParameterValue' -ToolTip $subcommand -ListItemText $subcommand))
        }
    }

    return @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('cursor-agent', 'cursor-agent.cmd', 'cursor-agent.ps1') -ScriptBlock {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Complete-CursorAgent -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
