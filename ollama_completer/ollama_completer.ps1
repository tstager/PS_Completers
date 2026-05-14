Set-StrictMode -Version Latest

function New-OllamaCompletionResult {
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
        $ToolTip = $ListItemText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function New-OllamaOptionSpec {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [string]$ValueKind,
        [switch]$OptionalValue
    )

    foreach ($token in @($Tokens)) {
        [pscustomobject]@{
            Token         = $token
            Description   = $Description
            ValueKind     = $ValueKind
            OptionalValue = [bool]$OptionalValue
        }
    }
}

function New-OllamaCommandSpec {
    param(
        [string]$Name,
        [string]$Description,
        [string[]]$Positionals,
        [object[]]$Options,
        [string[]]$Aliases
    )

    [pscustomobject]@{
        Name        = $Name
        Description = $Description
        Positionals = @($Positionals)
        Options     = @($Options)
        Aliases     = @($Aliases)
    }
}

function Get-OllamaCompletionCatalog {
    $existing = Get-Variable -Name OllamaCompletionCatalog -Scope Script -ErrorAction Ignore
    if ($existing) {
        return $existing.Value
    }

    $defaultHelpOptions = @(
        New-OllamaOptionSpec -Tokens @('-h', '--help') -Description 'Show help.'
    )

    $commands = @(
        New-OllamaCommandSpec -Name 'serve' -Description 'Start Ollama.' -Positionals @() -Options $defaultHelpOptions -Aliases @('start')
        New-OllamaCommandSpec -Name 'create' -Description 'Create a model.' -Positionals @('Model') -Options @(
            New-OllamaOptionSpec -Tokens @('--draft-quantize') -Description 'Quantize draft model to this level.' -ValueKind 'Quantization'
            New-OllamaOptionSpec -Tokens @('--experimental') -Description 'Enable experimental safetensors model creation.'
            New-OllamaOptionSpec -Tokens @('-f', '--file') -Description 'Name of the Modelfile.' -ValueKind 'FilePath'
            New-OllamaOptionSpec -Tokens @('-q', '--quantize') -Description 'Quantize model to this level.' -ValueKind 'Quantization'
            $defaultHelpOptions
        ) -Aliases @()
        New-OllamaCommandSpec -Name 'show' -Description 'Show information for a model.' -Positionals @('Model') -Options @(
            New-OllamaOptionSpec -Tokens @('--license') -Description 'Show license of a model.'
            New-OllamaOptionSpec -Tokens @('--modelfile') -Description 'Show Modelfile of a model.'
            New-OllamaOptionSpec -Tokens @('--parameters') -Description 'Show parameters of a model.'
            New-OllamaOptionSpec -Tokens @('--system') -Description 'Show system message of a model.'
            New-OllamaOptionSpec -Tokens @('--template') -Description 'Show template of a model.'
            New-OllamaOptionSpec -Tokens @('-v', '--verbose') -Description 'Show detailed model information.'
            $defaultHelpOptions
        ) -Aliases @()
        New-OllamaCommandSpec -Name 'run' -Description 'Run a model.' -Positionals @('Model', 'Prompt') -Options @(
            New-OllamaOptionSpec -Tokens @('--dimensions') -Description 'Truncate output embeddings to specified dimension.' -ValueKind 'Number'
            New-OllamaOptionSpec -Tokens @('--experimental') -Description 'Enable experimental agent loop with tools.'
            New-OllamaOptionSpec -Tokens @('--experimental-websearch') -Description 'Enable web search tool in experimental mode.'
            New-OllamaOptionSpec -Tokens @('--experimental-yolo') -Description 'Skip all tool approval prompts.'
            New-OllamaOptionSpec -Tokens @('--format') -Description 'Response format.' -ValueKind 'Format'
            New-OllamaOptionSpec -Tokens @('--hidethinking') -Description 'Hide thinking output.'
            New-OllamaOptionSpec -Tokens @('--insecure') -Description 'Use an insecure registry.'
            New-OllamaOptionSpec -Tokens @('--keepalive') -Description 'Duration to keep a model loaded.' -ValueKind 'Duration'
            New-OllamaOptionSpec -Tokens @('--nowordwrap') -Description 'Don''t wrap words to the next line automatically.'
            New-OllamaOptionSpec -Tokens @('--think') -Description 'Enable thinking mode.' -ValueKind 'Think' -OptionalValue
            New-OllamaOptionSpec -Tokens @('--truncate') -Description 'Control truncate behavior.' -ValueKind 'Boolean' -OptionalValue
            New-OllamaOptionSpec -Tokens @('--verbose') -Description 'Show timings for response.'
            New-OllamaOptionSpec -Tokens @('--width') -Description 'Image width.' -ValueKind 'Number'
            New-OllamaOptionSpec -Tokens @('--height') -Description 'Image height.' -ValueKind 'Number'
            New-OllamaOptionSpec -Tokens @('--steps') -Description 'Denoising steps.' -ValueKind 'Number'
            New-OllamaOptionSpec -Tokens @('--seed') -Description 'Random seed.' -ValueKind 'Number'
            New-OllamaOptionSpec -Tokens @('--negative') -Description 'Negative prompt.' -ValueKind 'NegativePrompt'
            $defaultHelpOptions
        ) -Aliases @()
        New-OllamaCommandSpec -Name 'stop' -Description 'Stop a running model.' -Positionals @('Model') -Options $defaultHelpOptions -Aliases @()
        New-OllamaCommandSpec -Name 'pull' -Description 'Pull a model from a registry.' -Positionals @('Model') -Options @(
            New-OllamaOptionSpec -Tokens @('--insecure') -Description 'Use an insecure registry.'
            $defaultHelpOptions
        ) -Aliases @()
        New-OllamaCommandSpec -Name 'push' -Description 'Push a model to a registry.' -Positionals @('Model') -Options @(
            New-OllamaOptionSpec -Tokens @('--insecure') -Description 'Use an insecure registry.'
            $defaultHelpOptions
        ) -Aliases @()
        New-OllamaCommandSpec -Name 'signin' -Description 'Sign in to ollama.com.' -Positionals @() -Options $defaultHelpOptions -Aliases @()
        New-OllamaCommandSpec -Name 'signout' -Description 'Sign out from ollama.com.' -Positionals @() -Options $defaultHelpOptions -Aliases @()
        New-OllamaCommandSpec -Name 'list' -Description 'List models.' -Positionals @() -Options $defaultHelpOptions -Aliases @('ls')
        New-OllamaCommandSpec -Name 'ps' -Description 'List running models.' -Positionals @() -Options $defaultHelpOptions -Aliases @()
        New-OllamaCommandSpec -Name 'cp' -Description 'Copy a model.' -Positionals @('SourceModel', 'DestinationModel') -Options $defaultHelpOptions -Aliases @()
        New-OllamaCommandSpec -Name 'rm' -Description 'Remove a model.' -Positionals @('Model') -Options $defaultHelpOptions -Aliases @()
        New-OllamaCommandSpec -Name 'launch' -Description 'Launch the Ollama menu or an integration.' -Positionals @('Integration') -Options @(
            New-OllamaOptionSpec -Tokens @('--config') -Description 'Configuration file or configure-without-launch mode.' -ValueKind 'ConfigPath' -OptionalValue
            New-OllamaOptionSpec -Tokens @('--model') -Description 'Model to use.' -ValueKind 'Model'
            New-OllamaOptionSpec -Tokens @('--restore') -Description 'Restore an integration to its default profile.'
            New-OllamaOptionSpec -Tokens @('-y', '--yes') -Description 'Automatically answer yes to confirmation prompts.'
            $defaultHelpOptions
        ) -Aliases @()
        New-OllamaCommandSpec -Name 'help' -Description 'Help about any command.' -Positionals @('CommandName') -Options $defaultHelpOptions -Aliases @()
    )

    $commandMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($command in $commands) {
        $commandMap[$command.Name] = $command
    }

    $catalog = @{
        Initialized         = $false
        CommandPath         = $null
        Commands            = $commands
        CommandMap          = $commandMap
        AliasMap            = @{
            'ls'    = 'list'
            'start' = 'serve'
        }
        RootOptions         = @(
            New-OllamaOptionSpec -Tokens @('-h', '--help') -Description 'Help for ollama.'
            New-OllamaOptionSpec -Tokens @('--nowordwrap') -Description 'Don''t wrap words to the next line automatically.'
            New-OllamaOptionSpec -Tokens @('--verbose') -Description 'Show timings for response.'
            New-OllamaOptionSpec -Tokens @('-v', '--version') -Description 'Show version information.'
        )
        LaunchIntegrations  = @(
            [pscustomobject]@{ Name = 'claude'; Description = 'Claude Code' }
            [pscustomobject]@{ Name = 'cline'; Description = 'Cline' }
            [pscustomobject]@{ Name = 'codex'; Description = 'Codex' }
            [pscustomobject]@{ Name = 'copilot'; Description = 'Copilot CLI' }
            [pscustomobject]@{ Name = 'droid'; Description = 'Droid' }
            [pscustomobject]@{ Name = 'hermes'; Description = 'Hermes Agent' }
            [pscustomobject]@{ Name = 'kimi'; Description = 'Kimi Code CLI' }
            [pscustomobject]@{ Name = 'opencode'; Description = 'OpenCode' }
            [pscustomobject]@{ Name = 'openclaw'; Description = 'OpenClaw' }
            [pscustomobject]@{ Name = 'pi'; Description = 'Pi' }
            [pscustomobject]@{ Name = 'pool'; Description = 'Pool' }
            [pscustomobject]@{ Name = 'vscode'; Description = 'VS Code' }
        )
        LaunchIntegrationAliases = @{
            'copilot-cli' = 'copilot'
            'clawdbot'    = 'openclaw'
            'moltbot'     = 'openclaw'
            'code'        = 'vscode'
        }
        EnumValues          = @{
            'run.--think'    = @('true', 'false', 'high', 'medium', 'low')
            'run.--format'   = @('json')
            'run.--truncate' = @('true', 'false')
        }
        Placeholders        = @{
            'Model'            = @('<model>')
            'SourceModel'      = @('<source-model>')
            'DestinationModel' = @('<destination-model>')
            'Prompt'           = @('<prompt>')
            'ExtraArgs'        = @('<extra-args>')
            'Duration'         = @('<duration>')
            'Quantization'     = @('<quantization>')
            'NegativePrompt'   = @('<negative-prompt>')
            'Number'           = @('<number>')
            'ConfigPath'       = @('<config-path>')
            'FilePath'         = @('<path>')
            'CommandName'      = @('<command>')
        }
    }

    Set-Variable -Name OllamaCompletionCatalog -Scope Script -Value $catalog
    $catalog
}

function Resolve-OllamaCommandPath {
    $catalog = Get-OllamaCompletionCatalog
    if (-not [string]::IsNullOrWhiteSpace($catalog.CommandPath)) {
        return $catalog.CommandPath
    }

    $command = Get-Command -Name 'ollama.exe', 'ollama' -ErrorAction Ignore | Select-Object -First 1
    if (-not $command) {
        return $null
    }

    $catalog.CommandPath = if ($command.Source) {
        $command.Source
    } elseif ($command.Path) {
        $command.Path
    } else {
        $command.Name
    }

    $catalog.CommandPath
}

function Invoke-OllamaCaptureText {
    param([string[]]$Arguments)

    $commandPath = Resolve-OllamaCommandPath
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return ''
    }

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $commandPath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.Environment['NO_COLOR'] = '1'
        $startInfo.Environment['TERM'] = 'dumb'

        foreach ($argument in @($Arguments)) {
            [void]$startInfo.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()

        $standardOutput = $process.StandardOutput.ReadToEnd()
        $standardError = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        $text = ($standardOutput + [Environment]::NewLine + $standardError).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            return ''
        }

        $text
    } catch {
        ''
    }
}

function Split-OllamaLines {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $Text -split '\r?\n'
}

function Get-OllamaSectionLines {
    param(
        [string]$Text,
        [string]$SectionHeader,
        [string[]]$StopHeaders
    )

    $lines = Split-OllamaLines -Text $Text
    $results = New-Object System.Collections.Generic.List[string]
    $inSection = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        if (-not $inSection) {
            if ($trimmed -eq $SectionHeader.Trim()) {
                $inSection = $true
            }

            continue
        }

        if (($StopHeaders -contains $trimmed) -or
            (($trimmed -match '^[A-Za-z].*:$') -and ($trimmed -ne $SectionHeader.Trim()))) {
            break
        }

        [void]$results.Add($line)
    }

    @($results.ToArray())
}

function Get-OllamaCommandEntriesFromLines {
    param([string[]]$Lines)

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($line in @($Lines)) {
        if ($line -match '^\s{2,}([a-z][a-z0-9-]+)\s{2,}(.+?)\s*$') {
            [void]$results.Add([pscustomobject]@{
                Name        = $matches[1]
                Description = $matches[2]
            })
        }
    }

    @($results.ToArray())
}

function Get-OllamaFlagEntriesFromLines {
    param([string[]]$Lines)

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($line in @($Lines)) {
        if ($line -match '^\s*(-[A-Za-z])\s*,\s*(--[a-z][a-z0-9-]*)(?:\s+\S+)?\s+(.+?)\s*$') {
            [void]$results.Add([pscustomobject]@{ Token = $matches[1]; Description = $matches[3] })
            [void]$results.Add([pscustomobject]@{ Token = $matches[2]; Description = $matches[3] })
            continue
        }

        if ($line -match '^\s*(--[a-z][a-z0-9-]*)(?:\s+\S+)?\s+(.+?)\s*$') {
            [void]$results.Add([pscustomobject]@{ Token = $matches[1]; Description = $matches[2] })
        }
    }

    @($results.ToArray())
}

function Merge-OllamaOptionOverlay {
    param(
        [object[]]$OverlayOptions,
        [object[]]$ParsedOptions
    )

    $results = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($parsed in @($ParsedOptions)) {
        $matched = $null
        foreach ($overlay in @($OverlayOptions)) {
            if ($overlay.Token.Equals($parsed.Token, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matched = $overlay
                break
            }
        }

        if ($matched) {
            if (-not [string]::IsNullOrWhiteSpace($parsed.Description)) {
                $matched.Description = $parsed.Description
            }

            if ($seen.Add($matched.Token)) {
                [void]$results.Add($matched)
            }

            continue
        }

        if ($seen.Add($parsed.Token)) {
            [void]$results.Add((New-OllamaOptionSpec -Tokens @($parsed.Token) -Description $parsed.Description))
        }
    }

    foreach ($overlay in @($OverlayOptions)) {
        if ($seen.Add($overlay.Token)) {
            [void]$results.Add($overlay)
        }
    }

    @($results.ToArray())
}

function Initialize-OllamaCompletionCatalog {
    $catalog = Get-OllamaCompletionCatalog
    if ($catalog.Initialized) {
        return
    }

    $rootHelpText = Invoke-OllamaCaptureText -Arguments @('--help')
    if (-not [string]::IsNullOrWhiteSpace($rootHelpText)) {
        $rootCommandEntries = Get-OllamaCommandEntriesFromLines -Lines (Get-OllamaSectionLines -Text $rootHelpText -SectionHeader 'Available Commands:' -StopHeaders @('Flags:'))
        if ($rootCommandEntries.Count -gt 0) {
            $parsedCommands = New-Object System.Collections.Generic.List[object]
            foreach ($entry in @($rootCommandEntries)) {
                if ($catalog.CommandMap.ContainsKey($entry.Name)) {
                    $spec = $catalog.CommandMap[$entry.Name]
                    $spec.Description = $entry.Description
                    [void]$parsedCommands.Add($spec)
                } else {
                    [void]$parsedCommands.Add((New-OllamaCommandSpec -Name $entry.Name -Description $entry.Description -Positionals @() -Options @() -Aliases @()))
                }
            }

            $catalog.Commands = @($parsedCommands.ToArray())
        }

        $rootFlagEntries = Get-OllamaFlagEntriesFromLines -Lines (Get-OllamaSectionLines -Text $rootHelpText -SectionHeader 'Flags:' -StopHeaders @('Use "ollama [command] --help" for more information about a command.'))
        if ($rootFlagEntries.Count -gt 0) {
            $catalog.RootOptions = Merge-OllamaOptionOverlay -OverlayOptions $catalog.RootOptions -ParsedOptions $rootFlagEntries
        }
    }

    foreach ($commandName in @('serve', 'create', 'show', 'run', 'stop', 'pull', 'push', 'signin', 'signout', 'list', 'ps', 'cp', 'rm', 'launch', 'help')) {
        if (-not $catalog.CommandMap.ContainsKey($commandName)) {
            continue
        }

        $helpText = Invoke-OllamaCaptureText -Arguments @($commandName, '--help')
        if ([string]::IsNullOrWhiteSpace($helpText)) {
            continue
        }

        $flagEntries = New-Object System.Collections.Generic.List[object]
        foreach ($entry in @(Get-OllamaFlagEntriesFromLines -Lines (Get-OllamaSectionLines -Text $helpText -SectionHeader 'Flags:' -StopHeaders @('Image Generation Flags (experimental):', 'Environment Variables:', 'Examples:')))) {
            [void]$flagEntries.Add($entry)
        }

        foreach ($entry in @(Get-OllamaFlagEntriesFromLines -Lines (Get-OllamaSectionLines -Text $helpText -SectionHeader 'Image Generation Flags (experimental):' -StopHeaders @('Environment Variables:', 'Examples:')))) {
            [void]$flagEntries.Add($entry)
        }

        if ($flagEntries.Count -gt 0) {
            $catalog.CommandMap[$commandName].Options =
                Merge-OllamaOptionOverlay -OverlayOptions $catalog.CommandMap[$commandName].Options -ParsedOptions @($flagEntries.ToArray())
        }

        if ($commandName -eq 'launch') {
            $integrationEntries = Get-OllamaCommandEntriesFromLines -Lines (Get-OllamaSectionLines -Text $helpText -SectionHeader 'Supported integrations:' -StopHeaders @('Examples:'))
            if ($integrationEntries.Count -gt 0) {
                $catalog.LaunchIntegrations = @($integrationEntries)
            }
        }
    }

    $catalog.Initialized = $true
}

function Resolve-OllamaCommandAlias {
    param([string]$Token)

    $catalog = Get-OllamaCompletionCatalog
    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $Token
    }

    if ($catalog.AliasMap.ContainsKey($Token)) {
        return $catalog.AliasMap[$Token]
    }

    $Token
}

function Resolve-OllamaIntegrationAlias {
    param([string]$Token)

    $catalog = Get-OllamaCompletionCatalog
    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $Token
    }

    if ($catalog.LaunchIntegrationAliases.ContainsKey($Token)) {
        return $catalog.LaunchIntegrationAliases[$Token]
    }

    $Token
}

function Get-OllamaQuoteCharacter {
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

function Remove-OllamaOuterQuotes {
    param([string]$InputText)

    if ([string]::IsNullOrEmpty($InputText)) {
        return ''
    }

    $quoteCharacter = Get-OllamaQuoteCharacter -InputText $InputText
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

function ConvertTo-OllamaQuotedValue {
    param(
        [string]$Value,
        [string]$QuoteCharacter
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    $effectiveQuote = $QuoteCharacter
    if ([string]::IsNullOrEmpty($effectiveQuote)) {
        $effectiveQuote = if ($Value -match '\s') { '"' } else { '' }
    }

    if ([string]::IsNullOrEmpty($effectiveQuote)) {
        return $Value
    }

    if (($effectiveQuote -eq "'") -and $Value.Contains("'")) {
        $effectiveQuote = '"'
    }

    if ($effectiveQuote -eq '"') {
        return '"' + $Value.Replace('`', '``').Replace('$', '`$').Replace('"', '`"') + '"'
    }

    "'" + $Value.Replace("'", "''") + "'"
}

function Get-OllamaPathCompletions {
    param(
        [string]$InputText,
        [string]$InlinePrefix = '',
        [string]$Placeholder = '<path>'
    )

    $quoteCharacter = Get-OllamaQuoteCharacter -InputText $InputText
    $cleanInput = Remove-OllamaOuterQuotes -InputText $InputText

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($cleanInput)) {
        $completionText = ConvertTo-OllamaQuotedValue -Value $item.CompletionText -QuoteCharacter $quoteCharacter
        if (-not [string]::IsNullOrEmpty($InlinePrefix)) {
            $completionText = $InlinePrefix + $completionText
        }

        [void]$results.Add((
            New-OllamaCompletionResult -CompletionText $completionText -ListItemText $item.ListItemText -ResultType $item.ResultType -ToolTip $item.ToolTip
        ))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Placeholder)) {
        [void]$results.AddRange(@(
            Get-OllamaPlaceholderCompletions -Values @($Placeholder) -CurrentWord $InputText -InlinePrefix $InlinePrefix
        ))
    }

    @($results.ToArray())
}

function Get-OllamaPlaceholderCompletions {
    param(
        [string[]]$Values,
        [string]$CurrentWord,
        [string]$InlinePrefix = ''
    )

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($value in @($Values)) {
        $completionText = if ([string]::IsNullOrEmpty($InlinePrefix)) { $value } else { $InlinePrefix + $value }
        $matchPrefix = if ([string]::IsNullOrEmpty($InlinePrefix)) { $CurrentWord } else { $InlinePrefix + $CurrentWord }
        if (-not [string]::IsNullOrEmpty($matchPrefix) -and
            -not $completionText.StartsWith($matchPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-OllamaCompletionResult -CompletionText $completionText -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip $value))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $typedValue = if ([string]::IsNullOrEmpty($InlinePrefix)) { $CurrentWord } else { $InlinePrefix + $CurrentWord }
        [void]$results.Add((New-OllamaCompletionResult -CompletionText $typedValue -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip $typedValue))
    }

    @($results.ToArray())
}

function Get-OllamaEnumCompletions {
    param(
        [string[]]$Values,
        [string]$CurrentWord,
        [string]$InlinePrefix = ''
    )

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($value in @($Values)) {
        $completionText = if ([string]::IsNullOrEmpty($InlinePrefix)) { $value } else { $InlinePrefix + $value }
        $matchPrefix = if ([string]::IsNullOrEmpty($InlinePrefix)) { $CurrentWord } else { $InlinePrefix + $CurrentWord }
        if (-not [string]::IsNullOrEmpty($matchPrefix) -and
            -not $completionText.StartsWith($matchPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-OllamaCompletionResult -CompletionText $completionText -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip $value))
    }

    @($results.ToArray())
}

function Get-OllamaCompletionLine {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $line = if ($CommandAst.Extent -and $null -ne $CommandAst.Extent.Text) {
        $CommandAst.Extent.Text
    } else {
        ''
    }

    $relativeCursor = if ($CommandAst.Extent) {
        $CursorPosition - $CommandAst.Extent.StartOffset
    } else {
        $CursorPosition
    }

    $line + (' ' * [Math]::Max(0, $relativeCursor - $line.Length))
}

function Get-OllamaTokenState {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback = ''
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return [pscustomobject]@{
            CurrentWord        = $Fallback
            TokensBeforeCurrent = @()
            AllTokens          = @()
        }
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    $hasTrailingSpace = $prefix -match '\s$'
    $allTokens = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })

    if ($hasTrailingSpace) {
        return [pscustomobject]@{
            CurrentWord         = ''
            TokensBeforeCurrent = if ($allTokens.Count -gt 1) { @($allTokens[1..($allTokens.Count - 1)]) } else { @() }
            AllTokens           = $allTokens
        }
    }

    $currentWord = if ($allTokens.Count -gt 0) {
        $allTokens[-1]
    } else {
        $Fallback
    }

    [pscustomobject]@{
        CurrentWord         = $currentWord
        TokensBeforeCurrent = if ($allTokens.Count -gt 2) { @($allTokens[1..($allTokens.Count - 2)]) } else { @() }
        AllTokens           = $allTokens
    }
}

function Get-OllamaCommandSpec {
    param([string]$CommandName)

    $catalog = Get-OllamaCompletionCatalog
    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        return $null
    }

    $canonicalName = Resolve-OllamaCommandAlias -Token $CommandName
    if ($catalog.CommandMap.ContainsKey($canonicalName)) {
        return $catalog.CommandMap[$canonicalName]
    }

    $null
}

function Get-OllamaOptionSpec {
    param(
        [string]$CommandName,
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $optionSet = if ([string]::IsNullOrWhiteSpace($CommandName)) {
        (Get-OllamaCompletionCatalog).RootOptions
    } else {
        $commandSpec = Get-OllamaCommandSpec -CommandName $CommandName
        if ($null -eq $commandSpec) {
            @()
        } else {
            $commandSpec.Options
        }
    }

    foreach ($option in @($optionSet)) {
        if ($option.Token.Equals($Token, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $option
        }
    }

    $null
}

function Get-OllamaCommandContext {
    param([string[]]$TokensBeforeCurrent)

    $commandName = $null
    $pendingOption = $null
    $positionals = New-Object System.Collections.Generic.List[string]
    $integration = $null
    $afterDoubleDash = $false
    $helpTarget = $null

    foreach ($token in @($TokensBeforeCurrent)) {
        if ($pendingOption) {
            if ($pendingOption.OptionalValue -and (($token -eq '--') -or $token.StartsWith('-'))) {
                $pendingOption = $null
            } else {
                $pendingOption = $null
                continue
            }
        }

        if (-not $commandName) {
            if ($token -eq '--') {
                continue
            }

            if ($token -match '^(--[^=]+)=') {
                continue
            }

            if ($token.StartsWith('-')) {
                $rootOption = Get-OllamaOptionSpec -CommandName $null -Token $token
                if ($rootOption -and $rootOption.ValueKind -and ($token -notlike '*=*')) {
                    $pendingOption = $rootOption
                }

                continue
            }

            $commandName = Resolve-OllamaCommandAlias -Token $token
            continue
        }

        if ($commandName -eq 'launch' -and $token -eq '--') {
            $afterDoubleDash = $true
            break
        }

        $inlineToken = $null
        if ($token -match '^(--[^=]+)=') {
            $inlineToken = $matches[1]
        }

        $optionToken = if ($inlineToken) { $inlineToken } else { $token }
        $optionSpec = Get-OllamaOptionSpec -CommandName $commandName -Token $optionToken
        if ($optionSpec) {
            if (($null -eq $inlineToken) -and $optionSpec.ValueKind) {
                $pendingOption = $optionSpec
            }

            continue
        }

        if ($token.StartsWith('-')) {
            continue
        }

        switch ($commandName) {
            'help' {
                if (-not $helpTarget) {
                    $helpTarget = Resolve-OllamaCommandAlias -Token $token
                }
            }
            'launch' {
                if (-not $integration) {
                    $integration = Resolve-OllamaIntegrationAlias -Token $token
                }
            }
            default {
                [void]$positionals.Add($token)
            }
        }
    }

    [pscustomobject]@{
        CommandName      = $commandName
        PendingOption    = $pendingOption
        Positionals      = @($positionals.ToArray())
        Integration      = $integration
        AfterDoubleDash  = $afterDoubleDash
        HelpTarget       = $helpTarget
    }
}

function Add-OllamaUniqueResults {
    param(
        [System.Collections.Generic.List[object]]$Target,
        [object[]]$Items
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($existing in @($Target.ToArray())) {
        [void]$seen.Add($existing.CompletionText)
    }

    foreach ($item in @($Items)) {
        if ($null -eq $item) {
            continue
        }

        if ($seen.Add($item.CompletionText)) {
            [void]$Target.Add($item)
        }
    }
}

function Get-OllamaOptionCompletions {
    param(
        [string]$CommandName,
        [string]$CurrentWord
    )

    $optionSet = if ([string]::IsNullOrWhiteSpace($CommandName)) {
        (Get-OllamaCompletionCatalog).RootOptions
    } else {
        $commandSpec = Get-OllamaCommandSpec -CommandName $CommandName
        if ($null -eq $commandSpec) {
            @()
        } else {
            $commandSpec.Options
        }
    }

    foreach ($option in @($optionSet)) {
        if (-not [string]::IsNullOrEmpty($CurrentWord) -and
            -not $option.Token.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        New-OllamaCompletionResult -CompletionText $option.Token -ResultType ([System.Management.Automation.CompletionResultType]::ParameterName) -ToolTip $option.Description
    }
}

function Get-OllamaRootCommandCompletions {
    param([string]$CurrentWord)

    $catalog = Get-OllamaCompletionCatalog
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($command in @($catalog.Commands)) {
        if ([string]::IsNullOrEmpty($CurrentWord) -or
            $command.Name.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((
                New-OllamaCompletionResult -CompletionText $command.Name -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip $command.Description
            ))
        }

        foreach ($alias in @($command.Aliases)) {
            if (-not [string]::IsNullOrEmpty($CurrentWord) -and
                -not $alias.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            [void]$results.Add((
                New-OllamaCompletionResult -CompletionText $alias -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip ('Alias for {0} - {1}' -f $command.Name, $command.Description)
            ))
        }
    }

    @($results.ToArray())
}

function Get-OllamaLaunchIntegrationCompletions {
    param([string]$CurrentWord)

    foreach ($integration in @((Get-OllamaCompletionCatalog).LaunchIntegrations)) {
        if (-not [string]::IsNullOrEmpty($CurrentWord) -and
            -not $integration.Name.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        New-OllamaCompletionResult -CompletionText $integration.Name -ResultType ([System.Management.Automation.CompletionResultType]::ParameterValue) -ToolTip $integration.Description
    }
}

function Get-OllamaValueCompletions {
    param(
        [string]$CommandName,
        [string]$ValueKind,
        [string]$CurrentWord,
        [string]$InlinePrefix = ''
    )

    $catalog = Get-OllamaCompletionCatalog

    switch ($ValueKind) {
        'Think' {
            return @(Get-OllamaEnumCompletions -Values $catalog.EnumValues['run.--think'] -CurrentWord $CurrentWord -InlinePrefix $InlinePrefix)
        }
        'Format' {
            return @(Get-OllamaEnumCompletions -Values $catalog.EnumValues['run.--format'] -CurrentWord $CurrentWord -InlinePrefix $InlinePrefix)
        }
        'Boolean' {
            return @(Get-OllamaEnumCompletions -Values @('true', 'false') -CurrentWord $CurrentWord -InlinePrefix $InlinePrefix)
        }
        'FilePath' {
            return @(Get-OllamaPathCompletions -InputText $CurrentWord -InlinePrefix $InlinePrefix -Placeholder '<path>')
        }
        'ConfigPath' {
            return @(Get-OllamaPathCompletions -InputText $CurrentWord -InlinePrefix $InlinePrefix -Placeholder '<config-path>')
        }
        'Model' {
            return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Model'] -CurrentWord $CurrentWord -InlinePrefix $InlinePrefix)
        }
        'Duration' {
            return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Duration'] -CurrentWord $CurrentWord -InlinePrefix $InlinePrefix)
        }
        'Quantization' {
            return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Quantization'] -CurrentWord $CurrentWord -InlinePrefix $InlinePrefix)
        }
        'NegativePrompt' {
            return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['NegativePrompt'] -CurrentWord $CurrentWord -InlinePrefix $InlinePrefix)
        }
        'Number' {
            return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Number'] -CurrentWord $CurrentWord -InlinePrefix $InlinePrefix)
        }
    }

    @()
}

function Get-OllamaPositionalCompletions {
    param(
        [string]$CommandName,
        [string]$CurrentWord,
        [string[]]$Positionals,
        [string]$Integration
    )

    $catalog = Get-OllamaCompletionCatalog

    switch ($CommandName) {
        'run' {
            if ($Positionals.Count -eq 0) {
                return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Model'] -CurrentWord $CurrentWord)
            }

            if ($Positionals.Count -eq 1) {
                return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Prompt'] -CurrentWord $CurrentWord)
            }
        }
        'create' {
            if ($Positionals.Count -eq 0) {
                return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Model'] -CurrentWord $CurrentWord)
            }
        }
        'show' {
            if ($Positionals.Count -eq 0) {
                return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Model'] -CurrentWord $CurrentWord)
            }
        }
        'stop' {
            if ($Positionals.Count -eq 0) {
                return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Model'] -CurrentWord $CurrentWord)
            }
        }
        'pull' {
            if ($Positionals.Count -eq 0) {
                return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Model'] -CurrentWord $CurrentWord)
            }
        }
        'push' {
            if ($Positionals.Count -eq 0) {
                return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Model'] -CurrentWord $CurrentWord)
            }
        }
        'cp' {
            if ($Positionals.Count -eq 0) {
                return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['SourceModel'] -CurrentWord $CurrentWord)
            }

            if ($Positionals.Count -eq 1) {
                return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['DestinationModel'] -CurrentWord $CurrentWord)
            }
        }
        'rm' {
            if ($Positionals.Count -eq 0) {
                return @(Get-OllamaPlaceholderCompletions -Values $catalog.Placeholders['Model'] -CurrentWord $CurrentWord)
            }
        }
        'help' {
            return @(Get-OllamaRootCommandCompletions -CurrentWord $CurrentWord)
        }
        'launch' {
            if (-not $Integration) {
                return @(Get-OllamaLaunchIntegrationCompletions -CurrentWord $CurrentWord)
            }
        }
    }

    @()
}

function Complete-Ollama {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-OllamaCompletionCatalog

    $completionLine = Get-OllamaCompletionLine -CommandAst $commandAst -CursorPosition $cursorPosition
    $relativeCursor = if ($commandAst.Extent) {
        $cursorPosition - $commandAst.Extent.StartOffset
    } else {
        $cursorPosition
    }

    $tokenState = Get-OllamaTokenState -Line $completionLine -CursorPosition $relativeCursor -Fallback $wordToComplete
    $currentWord = $tokenState.CurrentWord
    $tokensBeforeCurrent = @($tokenState.TokensBeforeCurrent)

    if (($tokensBeforeCurrent.Count -eq 0) -and ($currentWord -match '^(?i)ollama(?:\.exe)?$')) {
        $currentWord = ''
    }

    $context = Get-OllamaCommandContext -TokensBeforeCurrent $tokensBeforeCurrent
    if ($context.AfterDoubleDash) {
        return @(Get-OllamaPlaceholderCompletions -Values (Get-OllamaCompletionCatalog).Placeholders['ExtraArgs'] -CurrentWord $currentWord)
    }

    if ($currentWord -match '^(--[^=]+)=(.*)$') {
        $optionToken = $matches[1]
        $valuePrefix = $matches[2]
        $optionSpec = Get-OllamaOptionSpec -CommandName $context.CommandName -Token $optionToken
        if ($optionSpec -and $optionSpec.ValueKind) {
            return @(Get-OllamaValueCompletions -CommandName $context.CommandName -ValueKind $optionSpec.ValueKind -CurrentWord $valuePrefix -InlinePrefix ($optionToken + '='))
        }
    }

    $currentWordStartsOption = (-not [string]::IsNullOrEmpty($currentWord)) -and $currentWord.StartsWith('-')
    if ($context.PendingOption -and -not ($context.PendingOption.OptionalValue -and $currentWordStartsOption)) {
        return @(Get-OllamaValueCompletions -CommandName $context.CommandName -ValueKind $context.PendingOption.ValueKind -CurrentWord $currentWord)
    }

    if ($currentWord -eq '--' -and $context.CommandName -eq 'launch') {
        return @()
    }

    if ($currentWordStartsOption) {
        return @(Get-OllamaOptionCompletions -CommandName $context.CommandName -CurrentWord $currentWord)
    }

    $results = New-Object System.Collections.Generic.List[object]

    if (-not $context.CommandName) {
        Add-OllamaUniqueResults -Target $results -Items @(Get-OllamaRootCommandCompletions -CurrentWord $currentWord)
        if ([string]::IsNullOrEmpty($currentWord)) {
            Add-OllamaUniqueResults -Target $results -Items @(Get-OllamaOptionCompletions -CommandName $null -CurrentWord '')
        }

        return @($results.ToArray())
    }

    Add-OllamaUniqueResults -Target $results -Items @(
        Get-OllamaPositionalCompletions -CommandName $context.CommandName -CurrentWord $currentWord -Positionals $context.Positionals -Integration $context.Integration
    )

    if ([string]::IsNullOrEmpty($currentWord)) {
        Add-OllamaUniqueResults -Target $results -Items @(Get-OllamaOptionCompletions -CommandName $context.CommandName -CurrentWord '')
    }

    @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('ollama', 'ollama.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Ollama -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
