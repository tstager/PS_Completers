<#
.SYNOPSIS
    Registers a native PowerShell argument completer for pi.

.DESCRIPTION
    Provides a hybrid, static-first native argument completer for `pi`,
    `pi.cmd`, and `pi.ps1`.

    The completer covers:
    - top-level `pi` subcommands and global options
    - command-specific options for install/remove/uninstall/update/list/config
    - inline `--option=value` completion
    - path-aware completion for session, export, extension, skill, prompt, and theme paths
    - `@file` root-argument completion
    - enums for mode, thinking level, tools, and provider names
    - local custom provider/model discovery from `models.json`
    - source-scheme and local-path hints for install/remove/update

    The script is safe to dot-source multiple times and keeps its top level
    compatible with `Import-CompleterScript`.
#>

Set-StrictMode -Version Latest

function New-PiCompletionResult {
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

function New-PiOptionSpec {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [string]$ValueKind,
        [switch]$OptionalValue,
        [string]$CompletionText
    )

    foreach ($token in @($Tokens)) {
        [pscustomobject]@{
            Token          = $token
            Description    = $Description
            ValueKind      = $ValueKind
            OptionalValue  = [bool]$OptionalValue
            CompletionText = if ([string]::IsNullOrWhiteSpace($CompletionText)) { $token } else { $CompletionText }
        }
    }
}

function New-PiCommandSpec {
    param(
        [string]$Name,
        [string]$Description,
        [string[]]$Positionals,
        [object[]]$Options
    )

    [pscustomobject]@{
        Name        = $Name
        Description = $Description
        Positionals = @($Positionals)
        Options     = @($Options)
    }
}

function Test-PiCacheFresh {
    param(
        [datetime]$LoadedAt,
        [int]$TtlSeconds
    )

    if ($LoadedAt -eq [datetime]::MinValue) {
        return $false
    }

    ((Get-Date) - $LoadedAt).TotalSeconds -lt $TtlSeconds
}

function Get-PiUniqueStrings {
    param([string[]]$Items)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $results = New-Object System.Collections.Generic.List[string]

    foreach ($item in @($Items)) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        if ($seen.Add($item)) {
            [void]$results.Add($item)
        }
    }

    @($results.ToArray())
}

function Get-PiCompletionCache {
    if (-not (Get-Variable -Name PiCompletionCache -Scope Script -ErrorAction SilentlyContinue)) {
        $installLikeOptions = @(
            New-PiOptionSpec -Tokens @('-l', '--local') -Description 'Use project-local .pi/settings.json.'
            New-PiOptionSpec -Tokens @('--help', '-h') -Description 'Show subcommand help.'
        )

        $globalOptions = @(
            New-PiOptionSpec -Tokens @('--provider') -Description 'Provider name.' -ValueKind 'Provider'
            New-PiOptionSpec -Tokens @('--model') -Description 'Model pattern or ID.' -ValueKind 'ModelPattern'
            New-PiOptionSpec -Tokens @('--api-key') -Description 'API key override.' -ValueKind 'ApiKey'
            New-PiOptionSpec -Tokens @('--system-prompt') -Description 'Replace the default system prompt.' -ValueKind 'SystemPrompt'
            New-PiOptionSpec -Tokens @('--append-system-prompt') -Description 'Append text or file contents to the system prompt.' -ValueKind 'TextOrFile'
            New-PiOptionSpec -Tokens @('--mode') -Description 'Output mode.' -ValueKind 'Mode'
            New-PiOptionSpec -Tokens @('--print', '-p') -Description 'Run in non-interactive mode and exit.'
            New-PiOptionSpec -Tokens @('--continue', '-c') -Description 'Continue the previous session.'
            New-PiOptionSpec -Tokens @('--resume', '-r') -Description 'Select a session to resume.'
            New-PiOptionSpec -Tokens @('--session') -Description 'Use a specific session file.' -ValueKind 'SessionPathOrId'
            New-PiOptionSpec -Tokens @('--fork') -Description 'Fork a session file or partial UUID into a new session.' -ValueKind 'SessionPathOrId'
            New-PiOptionSpec -Tokens @('--session-dir') -Description 'Directory for session storage and lookup.' -ValueKind 'DirectoryPath'
            New-PiOptionSpec -Tokens @('--no-session') -Description 'Do not save the session.'
            New-PiOptionSpec -Tokens @('--models') -Description 'Comma-separated model patterns for Ctrl+P cycling.' -ValueKind 'ModelPatternList'
            New-PiOptionSpec -Tokens @('--no-tools', '-nt') -Description 'Disable all built-in and extension tools.'
            New-PiOptionSpec -Tokens @('--no-builtin-tools', '-nbt') -Description 'Disable built-in tools but keep extension/custom tools enabled.'
            New-PiOptionSpec -Tokens @('--tools', '-t') -Description 'Comma-separated list of tool names to enable.' -ValueKind 'ToolList'
            New-PiOptionSpec -Tokens @('--thinking') -Description 'Set the thinking level.' -ValueKind 'Thinking'
            New-PiOptionSpec -Tokens @('--extension', '-e') -Description 'Load an extension file or directory.' -ValueKind 'ExtensionPath'
            New-PiOptionSpec -Tokens @('--no-extensions', '-ne') -Description 'Disable extension discovery.'
            New-PiOptionSpec -Tokens @('--skill') -Description 'Load a skill file or directory.' -ValueKind 'SkillPath'
            New-PiOptionSpec -Tokens @('--no-skills', '-ns') -Description 'Disable skill discovery and loading.'
            New-PiOptionSpec -Tokens @('--prompt-template') -Description 'Load a prompt template file or directory.' -ValueKind 'PromptTemplatePath'
            New-PiOptionSpec -Tokens @('--no-prompt-templates', '-np') -Description 'Disable prompt template discovery and loading.'
            New-PiOptionSpec -Tokens @('--theme') -Description 'Load a theme file or directory.' -ValueKind 'ThemePath'
            New-PiOptionSpec -Tokens @('--no-themes') -Description 'Disable theme discovery and loading.'
            New-PiOptionSpec -Tokens @('--no-context-files', '-nc') -Description 'Disable AGENTS.md and CLAUDE.md discovery and loading.'
            New-PiOptionSpec -Tokens @('--export') -Description 'Export a session to HTML.' -ValueKind 'ExportInputPath'
            New-PiOptionSpec -Tokens @('--list-models') -Description 'List available models, optionally filtered by search text.' -ValueKind 'ModelSearch' -OptionalValue
            New-PiOptionSpec -Tokens @('--verbose') -Description 'Force verbose startup.'
            New-PiOptionSpec -Tokens @('--offline') -Description 'Disable startup network operations.'
            New-PiOptionSpec -Tokens @('--help', '-h') -Description 'Show help.'
            New-PiOptionSpec -Tokens @('--version', '-v') -Description 'Show version.'
        )

        $commandSpecs = @(
            New-PiCommandSpec -Name 'install' -Description 'Install extension source and add to settings.' -Positionals @('PackageSource') -Options $installLikeOptions
            New-PiCommandSpec -Name 'remove' -Description 'Remove extension source from settings.' -Positionals @('InstalledPackageSource') -Options $installLikeOptions
            New-PiCommandSpec -Name 'uninstall' -Description 'Alias for remove.' -Positionals @('InstalledPackageSource') -Options $installLikeOptions
            New-PiCommandSpec -Name 'update' -Description 'Update pi and installed extensions.' -Positionals @('UpdateTarget') -Options @(
                New-PiOptionSpec -Tokens @('--self') -Description 'Update pi only.'
                New-PiOptionSpec -Tokens @('--extensions') -Description 'Update installed extensions only.'
                New-PiOptionSpec -Tokens @('--extension') -Description 'Update one installed extension only.' -ValueKind 'InstalledPackageSource'
                New-PiOptionSpec -Tokens @('--force') -Description 'Reinstall pi even if already current.'
                New-PiOptionSpec -Tokens @('--help', '-h') -Description 'Show subcommand help.'
            )
            New-PiCommandSpec -Name 'list' -Description 'List installed extensions from settings.' -Positionals @() -Options @(
                New-PiOptionSpec -Tokens @('--help', '-h') -Description 'Show subcommand help.'
            )
            New-PiCommandSpec -Name 'config' -Description 'Open package-resource TUI.' -Positionals @() -Options @(
                New-PiOptionSpec -Tokens @('--help', '-h') -Description 'Show subcommand help if supported.'
            )
        )

        $commandLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($commandSpec in $commandSpecs) {
            $commandLookup[$commandSpec.Name] = $commandSpec
        }

        $staticCommandLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($commandSpec in $commandSpecs) {
            $staticCommandLookup[$commandSpec.Name] = $commandSpec
        }

        $script:PiCompletionCache = @{
            RootCommands = $commandSpecs
            CommandLookup = $commandLookup
            GlobalOptions = $globalOptions
            StaticRootCommands = $commandSpecs
            StaticCommandLookup = $staticCommandLookup
            StaticGlobalOptions = $globalOptions
            BuiltInProviders = @(
                'anthropic',
                'openai',
                'github-copilot',
                'google',
                'antigravity',
                'azure-openai-responses',
                'google-vertex',
                'amazon-bedrock',
                'mistral',
                'groq',
                'cerebras',
                'xai',
                'openrouter',
                'vercel-ai-gateway',
                'zai',
                'opencode',
                'opencode-go',
                'huggingface',
                'kimi-coding',
                'minimax',
                'minimax-cn'
            )
            BuiltInTools = @('read', 'bash', 'edit', 'write', 'grep', 'find', 'ls')
            ThinkingLevels = @('off', 'minimal', 'low', 'medium', 'high', 'xhigh')
            OutputModes = @('text', 'json', 'rpc')
            ExecutablePath = $null
            ExecutablePathProbed = $false
            CustomModelDataLoadedAt = [datetime]::MinValue
            CustomModelDataTtlSeconds = 120
            CustomProviderNames = @()
            CustomModelCandidates = @()
            RootHelpLoadedAt = [datetime]::MinValue
            RootHelpTtlSeconds = 60
            CommandHelpLoadedAt = @{
                install   = [datetime]::MinValue
                remove    = [datetime]::MinValue
                uninstall = [datetime]::MinValue
                update    = [datetime]::MinValue
                list      = [datetime]::MinValue
            }
            CommandHelpTtlSeconds = 60
            InstalledPackageSourcesLoadedAt = [datetime]::MinValue
            InstalledPackageSourcesTtlSeconds = 60
            InstalledPackageSources = @()
            SessionFilesLoadedAt = [datetime]::MinValue
            SessionFilesTtlSeconds = 60
            SessionFiles = @()
            ResourcePathsLoadedAt = @{
                extension       = [datetime]::MinValue
                skill           = [datetime]::MinValue
                'prompt-template' = [datetime]::MinValue
                theme           = [datetime]::MinValue
            }
            ResourcePathsTtlSeconds = 60
            ResourcePaths = @{
                extension       = @()
                skill           = @()
                'prompt-template' = @()
                theme           = @()
            }
        }
    }

    $script:PiCompletionCache
}

function Resolve-PiExecutablePath {
    $cache = Get-PiCompletionCache
    if ($cache.ExecutablePathProbed) {
        return $cache.ExecutablePath
    }

    $cache.ExecutablePathProbed = $true
    $cache.ExecutablePath = $null

    foreach ($commandName in @('pi.ps1', 'pi.cmd', 'pi')) {
        $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            $cache.ExecutablePath = if ($command.Source) { $command.Source } else { $command.Name }
            break
        }
    }

    $cache.ExecutablePath
}

function ConvertTo-PiCommandLineArgument {
    param([string]$Argument)

    if ($null -eq $Argument) {
        return '""'
    }

    if ($Argument -notmatch '[\s"&]') {
        return $Argument
    }

    '"' + ($Argument -replace '"', '\"') + '"'
}

function Invoke-PiCapture {
    param([string[]]$Arguments)

    $executablePath = Resolve-PiExecutablePath
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        return @()
    }

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.Environment['PI_OFFLINE'] = '1'
        $startInfo.Environment['FORCE_COLOR'] = '0'
        $startInfo.Environment['NO_COLOR'] = '1'

        if ($executablePath.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
            $startInfo.FileName = (Get-Command -Name pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
            if ([string]::IsNullOrWhiteSpace($startInfo.FileName)) {
                return @()
            }

            [void]$startInfo.ArgumentList.Add('-NoProfile')
            [void]$startInfo.ArgumentList.Add('-File')
            [void]$startInfo.ArgumentList.Add($executablePath)
            foreach ($argument in @($Arguments)) {
                [void]$startInfo.ArgumentList.Add($argument)
            }
        } elseif ($executablePath.EndsWith('.cmd', [System.StringComparison]::OrdinalIgnoreCase)) {
            $startInfo.FileName = $env:ComSpec
            if ([string]::IsNullOrWhiteSpace($startInfo.FileName)) {
                return @()
            }

            $cmdArguments = @(
                ConvertTo-PiCommandLineArgument -Argument $executablePath
            ) + @(
                foreach ($argument in @($Arguments)) {
                    ConvertTo-PiCommandLineArgument -Argument $argument
                }
            )

            [void]$startInfo.ArgumentList.Add('/d')
            [void]$startInfo.ArgumentList.Add('/c')
            [void]$startInfo.ArgumentList.Add(($cmdArguments -join ' '))
        } else {
            $startInfo.FileName = $executablePath
            foreach ($argument in @($Arguments)) {
                [void]$startInfo.ArgumentList.Add($argument)
            }
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $standardOutput = $process.StandardOutput.ReadToEnd()
        $null = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        if ([string]::IsNullOrWhiteSpace($standardOutput)) {
            return @()
        }

        @($standardOutput -split "`r?`n")
    } catch {
        @()
    }
}

function ConvertTo-PiPlainText {
    param([string[]]$InputLines)

    $text = [string]::Join("`n", @(
            foreach ($line in @($InputLines)) {
                if ($null -eq $line) {
                    continue
                }

                $line.ToString()
            }
        ))

    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    $text = [regex]::Replace($text, '\x1b\[[0-9;?]*[ -/]*[@-~]', '')
    $text = $text -replace "`a", ''
    $text = $text -replace "`r`n?", "`n"

    foreach ($heading in @(
            'Usage:',
            'Commands:',
            'Options:',
            'Extension CLI Flags:',
            'Short forms:',
            'Examples:',
            'Environment Variables:',
            'Built-in Tool Names:'
        )) {
        $text = $text -replace "(?<!`n)$([regex]::Escape($heading))", "`n$heading"
    }

    $text.Trim("`r", "`n")
}

function Get-PiHelpSectionText {
    param(
        [string]$Text,
        [string]$Heading,
        [string[]]$NextHeadings
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $escapedHeading = [regex]::Escape($Heading)
    $escapedNextHeadings = @(
        foreach ($nextHeading in @($NextHeadings)) {
            if ([string]::IsNullOrWhiteSpace($nextHeading)) {
                continue
            }

            [regex]::Escape($nextHeading)
        }
    )

    $terminatorPattern = if ($escapedNextHeadings.Count -gt 0) {
        "(?=`n(?:$($escapedNextHeadings -join '|'))|\z)"
    } else {
        '\z'
    }

    $match = [regex]::Match($Text, "(?ms)`n?$escapedHeading[ \t]*`n?(?<body>.*?)$terminatorPattern")
    if (-not $match.Success) {
        return ''
    }

    $match.Groups['body'].Value.Trim("`r", "`n")
}

function Remove-PiJsonComments {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $Content
    }

    $builder = [System.Text.StringBuilder]::new($Content.Length)
    $inString = $false
    $escaped = $false
    $inLineComment = $false
    $inBlockComment = $false

    for ($index = 0; $index -lt $Content.Length; $index++) {
        $character = $Content[$index]
        $nextCharacter = if (($index + 1) -lt $Content.Length) { $Content[$index + 1] } else { [char]0 }

        if ($inLineComment) {
            if ($character -eq "`r" -or $character -eq "`n") {
                $inLineComment = $false
                [void]$builder.Append($character)
            }

            continue
        }

        if ($inBlockComment) {
            if ($character -eq '*' -and $nextCharacter -eq '/') {
                $inBlockComment = $false
                $index++
                continue
            }

            if ($character -eq "`r" -or $character -eq "`n") {
                [void]$builder.Append($character)
            }

            continue
        }

        if ($inString) {
            [void]$builder.Append($character)

            if ($escaped) {
                $escaped = $false
                continue
            }

            if ($character -eq '\') {
                $escaped = $true
                continue
            }

            if ($character -eq '"') {
                $inString = $false
            }

            continue
        }

        if ($character -eq '"') {
            $inString = $true
            [void]$builder.Append($character)
            continue
        }

        if ($character -eq '/' -and $nextCharacter -eq '/') {
            $inLineComment = $true
            $index++
            continue
        }

        if ($character -eq '/' -and $nextCharacter -eq '*') {
            $inBlockComment = $true
            $index++
            continue
        }

        [void]$builder.Append($character)
    }

    $builder.ToString()
}

function ConvertFrom-PiJsonConfig {
    param(
        [string]$Path,
        [string]$Content
    )

    if ([System.IO.Path]::GetExtension($Path).Equals('.jsonc', [System.StringComparison]::OrdinalIgnoreCase)) {
        $documentOptions = [System.Text.Json.JsonDocumentOptions]::new()
        $documentOptions.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
        $documentOptions.AllowTrailingCommas = $true
        $document = [System.Text.Json.JsonDocument]::Parse($Content, $documentOptions)

        try {
            return ($document.RootElement.GetRawText() | ConvertFrom-Json -ErrorAction Stop)
        } finally {
            $document.Dispose()
        }
    }

    $Content | ConvertFrom-Json -ErrorAction Stop
}

function Get-PiValueKindForOption {
    param(
        [string[]]$Tokens,
        [string]$Placeholder,
        [string]$Description,
        [string]$CommandName
    )

    $primaryToken = $Tokens | Where-Object { $_ -like '--*' } | Select-Object -First 1
    if (-not $primaryToken) {
        $primaryToken = $Tokens | Select-Object -First 1
    }

    switch ($primaryToken) {
        '--provider' { return 'Provider' }
        '--model' { return 'ModelPattern' }
        '--api-key' { return 'ApiKey' }
        '--system-prompt' { return 'SystemPrompt' }
        '--append-system-prompt' { return 'TextOrFile' }
        '--mode' { return 'Mode' }
        '--session' { return 'SessionPathOrId' }
        '--fork' { return 'SessionPathOrId' }
        '--session-dir' { return 'DirectoryPath' }
        '--models' { return 'ModelPatternList' }
        '--tools' { return 'ToolList' }
        '--thinking' { return 'Thinking' }
        '--extension' {
            if ($CommandName -eq 'update') {
                return 'InstalledPackageSource'
            }

            return 'ExtensionPath'
        }
        '--skill' { return 'SkillPath' }
        '--prompt-template' { return 'PromptTemplatePath' }
        '--theme' { return 'ThemePath' }
        '--export' { return 'ExportInputPath' }
        '--list-models' { return 'ModelSearch' }
        '--mcp-config' { return 'FilePath' }
    }

    if (-not [string]::IsNullOrWhiteSpace($Placeholder)) {
        $placeholderText = $Placeholder.Trim('<>[]')
        if ($placeholderText -match 'dir') {
            return 'DirectoryPath'
        }

        if ($placeholderText -match 'path|file|config') {
            return 'FilePath'
        }
    }

    if ($Description -match '\b(path|file|config)\b') {
        return 'FilePath'
    }

    $null
}

function ConvertFrom-PiHelpOptionSection {
    param(
        [string]$SectionText,
        [string]$CommandName
    )

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($line in @($SectionText -split "`n")) {
        if ($line -notmatch '^\s{2,}(?<spec>--[A-Za-z0-9][A-Za-z0-9-]*(?:,\s*-[A-Za-z0-9]+)?(?:\s+(?:<[^>]+>|\[[^\]]+\]))?|-[A-Za-z0-9]+(?:,\s*--[A-Za-z0-9][A-Za-z0-9-]*)?(?:\s+(?:<[^>]+>|\[[^\]]+\]))?)\s{2,}(?<description>.+)$') {
            continue
        }

        $specText = $Matches.spec.Trim()
        $description = $Matches.description.Trim()
        $optionalValue = $false
        $placeholder = $null

        if ($specText -match '\s+(?<placeholder><[^>]+>|\[[^\]]+\])$') {
            $placeholder = $Matches.placeholder
            $optionalValue = $placeholder.StartsWith('[')
            $specText = $specText.Substring(0, $specText.Length - $placeholder.Length).TrimEnd()
        }

        $tokens = @(
            foreach ($token in @($specText -split '\s*,\s*')) {
                if ([string]::IsNullOrWhiteSpace($token)) {
                    continue
                }

                $token.Trim()
            }
        )

        if ($tokens.Count -eq 0) {
            continue
        }

        $valueKind = Get-PiValueKindForOption -Tokens $tokens -Placeholder $placeholder -Description $description -CommandName $CommandName
        foreach ($item in @(New-PiOptionSpec -Tokens $tokens -Description $description -ValueKind $valueKind -OptionalValue:$optionalValue)) {
            [void]$results.Add($item)
        }
    }

    @($results.ToArray())
}

function Merge-PiOptionSpecs {
    param(
        [object[]]$BaseOptions,
        [object[]]$OverrideOptions
    )

    $lookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $order = New-Object System.Collections.Generic.List[string]

    foreach ($option in @($BaseOptions + $OverrideOptions)) {
        if ($null -eq $option -or [string]::IsNullOrWhiteSpace($option.Token)) {
            continue
        }

        if (-not $lookup.ContainsKey($option.Token)) {
            [void]$order.Add($option.Token)
        }

        $lookup[$option.Token] = $option
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($token in @($order)) {
        [void]$results.Add($lookup[$token])
    }

    @($results.ToArray())
}

function Set-PiCommandSpec {
    param([object]$CommandSpec)

    if ($null -eq $CommandSpec -or [string]::IsNullOrWhiteSpace($CommandSpec.Name)) {
        return
    }

    $cache = Get-PiCompletionCache
    $cache.CommandLookup[$CommandSpec.Name] = $CommandSpec

    $updatedCommands = New-Object System.Collections.Generic.List[object]
    $replaced = $false
    foreach ($existingCommand in @($cache.RootCommands)) {
        if ($existingCommand.Name.Equals($CommandSpec.Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$updatedCommands.Add($CommandSpec)
            $replaced = $true
        } else {
            [void]$updatedCommands.Add($existingCommand)
        }
    }

    if (-not $replaced) {
        [void]$updatedCommands.Add($CommandSpec)
    }

    $cache.RootCommands = @($updatedCommands.ToArray())
}

function Update-PiRootHelpData {
    $cache = Get-PiCompletionCache
    if (Test-PiCacheFresh -LoadedAt $cache.RootHelpLoadedAt -TtlSeconds $cache.RootHelpTtlSeconds) {
        return
    }

    $cache.RootHelpLoadedAt = Get-Date

    $text = ConvertTo-PiPlainText -InputLines (Invoke-PiCapture -Arguments @('--help'))
    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    $commandSpecs = @($cache.StaticRootCommands)
    $commandLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($commandSpec in @($commandSpecs)) {
        $commandLookup[$commandSpec.Name] = $commandSpec
    }

    $commandsSection = Get-PiHelpSectionText -Text $text -Heading 'Commands:' -NextHeadings @('Options:')
    foreach ($line in @($commandsSection -split "`n")) {
        if ($line -notmatch '^\s*pi\s+(?<name>[A-Za-z0-9-]+)(?:\s+(?<usage>.*?))?\s{2,}(?<description>.+)$') {
            continue
        }

        $commandName = $Matches.name
        $description = $Matches.description.Trim()
        $existingCommand = if ($commandLookup.ContainsKey($commandName)) { $commandLookup[$commandName] } else { $null }
        if ($existingCommand) {
            $commandLookup[$commandName] = New-PiCommandSpec -Name $existingCommand.Name -Description $description -Positionals $existingCommand.Positionals -Options $existingCommand.Options
        }
    }

    $globalOptions = Merge-PiOptionSpecs `
        -BaseOptions $cache.StaticGlobalOptions `
        -OverrideOptions (ConvertFrom-PiHelpOptionSection -SectionText (Get-PiHelpSectionText -Text $text -Heading 'Options:' -NextHeadings @('Extension CLI Flags:', 'Examples:', 'Environment Variables:', 'Built-in Tool Names:')) -CommandName '')

    $globalOptions = Merge-PiOptionSpecs `
        -BaseOptions $globalOptions `
        -OverrideOptions (ConvertFrom-PiHelpOptionSection -SectionText (Get-PiHelpSectionText -Text $text -Heading 'Extension CLI Flags:' -NextHeadings @('Examples:', 'Environment Variables:', 'Built-in Tool Names:')) -CommandName '')

    $builtInTools = New-Object System.Collections.Generic.List[string]
    $builtInToolSection = Get-PiHelpSectionText -Text $text -Heading 'Built-in Tool Names:' -NextHeadings @()
    foreach ($line in @($builtInToolSection -split "`n")) {
        if ($line -match '^\s*(?<tool>[A-Za-z0-9-]+)\s+-') {
            [void]$builtInTools.Add($Matches.tool)
        }
    }

    $cache.CommandLookup = $commandLookup
    $cache.RootCommands = @($commandLookup.Values | Sort-Object {
            $index = [array]::IndexOf(@($cache.StaticRootCommands.Name), $_.Name)
            if ($index -lt 0) { [int]::MaxValue } else { $index }
        })
    $cache.GlobalOptions = $globalOptions
    if ($builtInTools.Count -gt 0) {
        $cache.BuiltInTools = Get-PiUniqueStrings -Items @($builtInTools.ToArray())
    }
}

function Update-PiCommandHelpData {
    param([string]$CommandName)

    if ([string]::IsNullOrWhiteSpace($CommandName) -or $CommandName -eq 'config') {
        return
    }

    $cache = Get-PiCompletionCache
    if (-not $cache.CommandHelpLoadedAt.ContainsKey($CommandName)) {
        return
    }

    if (Test-PiCacheFresh -LoadedAt $cache.CommandHelpLoadedAt[$CommandName] -TtlSeconds $cache.CommandHelpTtlSeconds) {
        return
    }

    $cache.CommandHelpLoadedAt[$CommandName] = Get-Date

    $text = ConvertTo-PiPlainText -InputLines (Invoke-PiCapture -Arguments @($CommandName, '--help'))
    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    $baseCommandSpec = if ($cache.CommandLookup.ContainsKey($CommandName)) {
        $cache.CommandLookup[$CommandName]
    } elseif ($cache.StaticCommandLookup.ContainsKey($CommandName)) {
        $cache.StaticCommandLookup[$CommandName]
    } else {
        $null
    }

    if (-not $baseCommandSpec) {
        return
    }

    $description = $baseCommandSpec.Description
    $lines = @($text -split "`n")
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -ne 'Usage:') {
            continue
        }

        $usageLineSeen = $false
        for ($bodyIndex = $index + 1; $bodyIndex -lt $lines.Count; $bodyIndex++) {
            $bodyLine = $lines[$bodyIndex].Trim()
            if ([string]::IsNullOrWhiteSpace($bodyLine)) {
                continue
            }

            if ($bodyLine -like 'Options:*' -or $bodyLine -like 'Short forms:*' -or $bodyLine -like 'Examples:*') {
                break
            }

            if (-not $usageLineSeen) {
                $usageLineSeen = $true
                continue
            }

            $description = $bodyLine
            break
        }

        break
    }

    $positionals = switch ($CommandName) {
        'install' { @('PackageSource') }
        'remove' { @('InstalledPackageSource') }
        'uninstall' { @('InstalledPackageSource') }
        'update' { @('UpdateTarget') }
        default { @() }
    }

    $optionSection = Get-PiHelpSectionText -Text $text -Heading 'Options:' -NextHeadings @('Short forms:', 'Examples:')
    $options = Merge-PiOptionSpecs -BaseOptions $baseCommandSpec.Options -OverrideOptions (ConvertFrom-PiHelpOptionSection -SectionText $optionSection -CommandName $CommandName)

    Set-PiCommandSpec -CommandSpec (New-PiCommandSpec -Name $CommandName -Description $description -Positionals $positionals -Options $options)
}

function Get-PiRootCommands {
    Update-PiRootHelpData
    (Get-PiCompletionCache).RootCommands
}

function Get-PiGlobalOptions {
    Update-PiRootHelpData
    (Get-PiCompletionCache).GlobalOptions
}

function Get-PiInstalledPackageSources {
    $cache = Get-PiCompletionCache
    if (Test-PiCacheFresh -LoadedAt $cache.InstalledPackageSourcesLoadedAt -TtlSeconds $cache.InstalledPackageSourcesTtlSeconds) {
        return $cache.InstalledPackageSources
    }

    $sources = New-Object System.Collections.Generic.List[string]
    $text = ConvertTo-PiPlainText -InputLines (Invoke-PiCapture -Arguments @('list'))
    foreach ($line in @($text -split "`n")) {
        if ($line -notmatch '^\s{2}(?!\s)(?<source>.+)$') {
            continue
        }

        $source = $Matches.source.Trim()
        if ([string]::IsNullOrWhiteSpace($source) -or
            $source -like 'User packages:' -or
            $source -like 'Project packages:' -or
            $source -like 'No packages installed.*' -or
            $source -match '^[A-Za-z]:[\\/]' -or
            $source -like ':*') {
            continue
        }

        [void]$sources.Add($source)
    }

    $cache.InstalledPackageSources = Get-PiUniqueStrings -Items @($sources.ToArray())
    $cache.InstalledPackageSourcesLoadedAt = Get-Date
    $cache.InstalledPackageSources
}

function Get-PiTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-PiProcessedTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [string]$WordToComplete
    )

    if ($CommandAst.CommandElements.Count -le 1) {
        return @()
    }

    $tokens = @(
        foreach ($element in @($CommandAst.CommandElements)[1..($CommandAst.CommandElements.Count - 1)]) {
            if ($null -eq $element) {
                continue
            }

            Get-PiTokenText -Element $element
        }
    )

    if ($tokens.Count -gt 0 -and -not [string]::IsNullOrEmpty($WordToComplete) -and $tokens[-1] -eq $WordToComplete) {
        if ($tokens.Count -eq 1) {
            return @()
        }

        return @($tokens[0..($tokens.Count - 2)])
    }

    @($tokens)
}

function Get-PiCommandSpec {
    param([string]$CommandName)

    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        return $null
    }

    Update-PiRootHelpData
    Update-PiCommandHelpData -CommandName $CommandName
    $cache = Get-PiCompletionCache
    if ($cache.CommandLookup.ContainsKey($CommandName)) {
        return $cache.CommandLookup[$CommandName]
    }

    $null
}

function Find-PiOptionSpec {
    param(
        [string]$Token,
        [object[]]$Options
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $normalizedToken = if ($Token.Contains('=')) {
        $Token.Substring(0, $Token.IndexOf('='))
    } else {
        $Token
    }

    foreach ($option in @($Options)) {
        if ($option.Token.TrimEnd('=').Equals($normalizedToken, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $option
        }
    }

    $null
}

function Test-PiPathLike {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $Value -match '^(?:\.{1,2}[\\/]|~[\\/]|[A-Za-z]:[\\/]|\\\\|/)' -or
        $Value.Contains('\') -or
        $Value.Contains('/')
}

function Get-PiPathCompletions {
    param(
        [string]$PathPrefix,
        [switch]$DirectoriesOnly,
        [string]$CompletionPrefix = ''
    )

    $items = [System.Management.Automation.CompletionCompleters]::CompleteFilename($PathPrefix)
    foreach ($item in @($items)) {
        if ($DirectoriesOnly -and -not (Test-Path -LiteralPath $item.CompletionText -PathType Container)) {
            continue
        }

        if ([string]::IsNullOrEmpty($CompletionPrefix)) {
            $item
            continue
        }

        New-PiCompletionResult `
            -CompletionText "$CompletionPrefix$($item.CompletionText)" `
            -ListItemText $item.ListItemText `
            -ResultType $item.ResultType `
            -ToolTip $item.ToolTip
    }
}

function Get-PiAtFileCompletions {
    param([string]$WordToComplete)

    $pathPrefix = if ($WordToComplete.Length -gt 1) { $WordToComplete.Substring(1) } else { '' }
    Get-PiPathCompletions -PathPrefix $pathPrefix -CompletionPrefix '@'
}

function Get-PiModelsJsonPaths {
    $paths = New-Object System.Collections.Generic.List[string]
    $homePath = [Environment]::GetFolderPath('UserProfile')
    if (-not [string]::IsNullOrWhiteSpace($homePath)) {
        [void]$paths.Add((Join-Path $homePath '.pi\agent\models.json'))
        [void]$paths.Add((Join-Path $homePath '.pi\agent\models.jsonc'))
    }

    [void]$paths.Add((Join-Path (Get-Location) '.pi\models.json'))
    [void]$paths.Add((Join-Path (Get-Location) '.pi\models.jsonc'))

    Get-PiUniqueStrings -Items $paths
}

function Update-PiCustomModelData {
    $cache = Get-PiCompletionCache
    if (Test-PiCacheFresh -LoadedAt $cache.CustomModelDataLoadedAt -TtlSeconds $cache.CustomModelDataTtlSeconds) {
        return
    }

    $providerNames = New-Object System.Collections.Generic.List[string]
    $modelCandidates = New-Object System.Collections.Generic.List[string]

    foreach ($path in @(Get-PiModelsJsonPaths)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        try {
            $content = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            $config = ConvertFrom-PiJsonConfig -Path $path -Content $content
        } catch {
            continue
        }

        if (-not $config.providers) {
            continue
        }

        $providersObject = $config.providers.PSObject
        foreach ($providerProperty in @($providersObject.Properties)) {
            $providerName = $providerProperty.Name
            if ([string]::IsNullOrWhiteSpace($providerName)) {
                continue
            }

            [void]$providerNames.Add($providerName)

            $providerValue = $providerProperty.Value
            if ($providerValue -and $providerValue.models) {
                foreach ($model in @($providerValue.models)) {
                    $modelId = $model.id
                    if ([string]::IsNullOrWhiteSpace($modelId)) {
                        continue
                    }

                    [void]$modelCandidates.Add($modelId)
                    if ($modelId -notmatch '/') {
                        [void]$modelCandidates.Add("$providerName/$modelId")
                    }
                }
            }
        }
    }

    $cache.CustomProviderNames = Get-PiUniqueStrings -Items @($providerNames.ToArray())
    $cache.CustomModelCandidates = Get-PiUniqueStrings -Items @($modelCandidates.ToArray())
    $cache.CustomModelDataLoadedAt = Get-Date
}

function Get-PiProviderNames {
    Update-PiCustomModelData
    $cache = Get-PiCompletionCache
    Get-PiUniqueStrings -Items @($cache.BuiltInProviders + $cache.CustomProviderNames)
}

function Get-PiModelCandidates {
    Update-PiCustomModelData
    $cache = Get-PiCompletionCache

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($providerName in @(Get-PiProviderNames)) {
        [void]$candidates.Add("$providerName/*")
        [void]$candidates.Add("$providerName/")
    }

    [void]$candidates.Add('*sonnet*')
    [void]$candidates.Add('openai/gpt-4o')
    [void]$candidates.Add('sonnet:high')
    foreach ($customCandidate in @($cache.CustomModelCandidates)) {
        [void]$candidates.Add($customCandidate)
    }

    Get-PiUniqueStrings -Items @($candidates.ToArray())
}

function Get-PiSessionFileSuggestions {
    $cache = Get-PiCompletionCache
    if (Test-PiCacheFresh -LoadedAt $cache.SessionFilesLoadedAt -TtlSeconds $cache.SessionFilesTtlSeconds) {
        return $cache.SessionFiles
    }

    $homePath = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrWhiteSpace($homePath)) {
        $cache.SessionFiles = @()
        $cache.SessionFilesLoadedAt = Get-Date
        return $cache.SessionFiles
    }

    $sessionRoot = Join-Path $homePath '.pi\agent\sessions'
    if (-not (Test-Path -LiteralPath $sessionRoot -PathType Container)) {
        $cache.SessionFiles = @()
        $cache.SessionFilesLoadedAt = Get-Date
        return $cache.SessionFiles
    }

    $files = @(Get-ChildItem -LiteralPath $sessionRoot -File -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 30 -ExpandProperty FullName)

    $cache.SessionFiles = Get-PiUniqueStrings -Items $files
    $cache.SessionFilesLoadedAt = Get-Date
    $cache.SessionFiles
}

function Get-PiKnownResourceRoots {
    param([string]$Kind)

    $homePath = [Environment]::GetFolderPath('UserProfile')
    $roots = New-Object System.Collections.Generic.List[string]

    switch ($Kind) {
        'extension' {
            if (-not [string]::IsNullOrWhiteSpace($homePath)) { [void]$roots.Add((Join-Path $homePath '.pi\agent\extensions')) }
            [void]$roots.Add((Join-Path (Get-Location) '.pi\extensions'))
        }
        'skill' {
            if (-not [string]::IsNullOrWhiteSpace($homePath)) { [void]$roots.Add((Join-Path $homePath '.pi\agent\skills')) }
            [void]$roots.Add((Join-Path (Get-Location) '.pi\skills'))
        }
        'prompt-template' {
            if (-not [string]::IsNullOrWhiteSpace($homePath)) { [void]$roots.Add((Join-Path $homePath '.pi\agent\prompts')) }
            [void]$roots.Add((Join-Path (Get-Location) '.pi\prompts'))
        }
        'theme' {
            if (-not [string]::IsNullOrWhiteSpace($homePath)) { [void]$roots.Add((Join-Path $homePath '.pi\agent\themes')) }
            [void]$roots.Add((Join-Path (Get-Location) '.pi\themes'))
        }
    }

    Get-PiUniqueStrings -Items $roots
}

function Get-PiKnownResourcePaths {
    param([string]$Kind)

    $cache = Get-PiCompletionCache
    if (Test-PiCacheFresh -LoadedAt $cache.ResourcePathsLoadedAt[$Kind] -TtlSeconds $cache.ResourcePathsTtlSeconds) {
        return $cache.ResourcePaths[$Kind]
    }

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($root in @(Get-PiKnownResourceRoots -Kind $Kind)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }

        foreach ($item in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            [void]$paths.Add($item.FullName)
        }
    }

    $cache.ResourcePaths[$Kind] = Get-PiUniqueStrings -Items @($paths.ToArray())
    $cache.ResourcePathsLoadedAt[$Kind] = Get-Date
    $cache.ResourcePaths[$Kind]
}

function Get-PiResourcePathCompletions {
    param(
        [string]$Kind,
        [string]$WordToComplete
    )

    if (Test-PiPathLike -Value $WordToComplete) {
        Get-PiPathCompletions -PathPrefix $WordToComplete
        return
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in @(Get-PiKnownResourcePaths -Kind $Kind)) {
        if ($path -notlike "$WordToComplete*") {
            continue
        }

        if ($seen.Add($path)) {
            New-PiCompletionResult -CompletionText $path -ToolTip "$Kind path"
        }
    }

    if ([string]::IsNullOrEmpty($WordToComplete)) {
        foreach ($hint in @('.\', '..\')) {
            New-PiCompletionResult -CompletionText $hint -ToolTip "$Kind path"
        }
    }
}

function Get-PiCommaSeparatedCompletions {
    param(
        [string[]]$Candidates,
        [string]$WordToComplete,
        [string]$ToolTip
    )

    $prefix = ''
    $segmentPrefix = $WordToComplete

    if ($WordToComplete -like '*,*') {
        $lastComma = $WordToComplete.LastIndexOf(',')
        $prefix = $WordToComplete.Substring(0, $lastComma + 1)
        $segmentPrefix = $WordToComplete.Substring($lastComma + 1)
    }

    foreach ($candidate in @(Get-PiUniqueStrings -Items $Candidates)) {
        if ($candidate -notlike "$segmentPrefix*") {
            continue
        }

        New-PiCompletionResult -CompletionText "$prefix$candidate" -ToolTip $ToolTip
    }
}

function Get-PiModelValueCompletions {
    param(
        [string]$WordToComplete,
        [string]$InlinePrefix
    )

    $finalWord = if ($null -eq $WordToComplete) { '' } else { $WordToComplete }
    $thinkingLevels = (Get-PiCompletionCache).ThinkingLevels

    $addCompletion = {
        param([string]$value, [string]$toolTip)

        if ([string]::IsNullOrWhiteSpace($value)) {
            return
        }

        if ($value -notlike "$finalWord*") {
            return
        }

        $completionText = if ([string]::IsNullOrEmpty($InlinePrefix)) { $value } else { "$InlinePrefix$value" }
        $listText = if ([string]::IsNullOrEmpty($InlinePrefix)) { $value } else { $value }
        New-PiCompletionResult -CompletionText $completionText -ListItemText $listText -ToolTip $toolTip
    }

    if ($finalWord -like '*:*') {
        $colonIndex = $finalWord.LastIndexOf(':')
        $basePart = $finalWord.Substring(0, $colonIndex)
        $thinkingPrefix = $finalWord.Substring($colonIndex + 1)
        foreach ($level in @($thinkingLevels)) {
            if ($level -notlike "$thinkingPrefix*") {
                continue
            }

            & $addCompletion "${basePart}:$level" 'Model with thinking level'
        }

        return
    }

    foreach ($candidate in @(Get-PiModelCandidates)) {
        & $addCompletion $candidate 'Model pattern or ID'
    }

    if ([string]::IsNullOrEmpty($finalWord)) {
        & $addCompletion '<provider/model[:thinking]>' 'Model pattern or ID'
    }
}

function Get-PiValueCompletions {
    param(
        [string]$ValueKind,
        [string]$WordToComplete,
        [string]$ContextToken,
        [string]$InlinePrefix
    )

    $cache = Get-PiCompletionCache
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    $addResult = {
        param(
            [string]$completionText,
            [string]$toolTip,
            [string]$resultType = 'ParameterValue',
            [string]$listItemText = $completionText
        )

        if ([string]::IsNullOrWhiteSpace($completionText)) {
            return
        }

        if ($completionText -notlike "$WordToComplete*") {
            return
        }

        $finalCompletion = if ([string]::IsNullOrEmpty($InlinePrefix)) {
            $completionText
        } else {
            "$InlinePrefix$completionText"
        }

        $finalListItemText = if ([string]::IsNullOrEmpty($InlinePrefix)) {
            $listItemText
        } else {
            $completionText
        }

        [void]$results.Add(
            (New-PiCompletionResult -CompletionText $finalCompletion -ListItemText $finalListItemText -ResultType $resultType -ToolTip $toolTip)
        )
    }

    switch ($ValueKind) {
        'Provider' {
            foreach ($providerName in @(Get-PiProviderNames)) {
                & $addResult $providerName 'Provider name'
            }
        }
        'Mode' {
            foreach ($mode in @($cache.OutputModes)) {
                & $addResult $mode 'Output mode'
            }
        }
        'Thinking' {
            foreach ($level in @($cache.ThinkingLevels)) {
                & $addResult $level 'Thinking level'
            }
        }
        'ToolList' {
            $prefix = ''
            $segmentPrefix = $WordToComplete
            $selectedTools = @()

            if ($WordToComplete -like '*,*') {
                $lastComma = $WordToComplete.LastIndexOf(',')
                $prefix = $WordToComplete.Substring(0, $lastComma + 1)
                $segmentPrefix = $WordToComplete.Substring($lastComma + 1)
                $selectedTools = @($prefix.TrimEnd(',').Split(',') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }

            foreach ($toolName in @($cache.BuiltInTools)) {
                if ($selectedTools -contains $toolName) {
                    continue
                }

                if ($toolName -notlike "$segmentPrefix*") {
                    continue
                }

                & $addResult "$prefix$toolName" 'Built-in tool'
            }
        }
        'ModelPattern' {
            foreach ($item in @(Get-PiModelValueCompletions -WordToComplete $WordToComplete -InlinePrefix $InlinePrefix)) {
                [void]$results.Add($item)
            }
        }
        'ModelPatternList' {
            $prefix = ''
            $segment = $WordToComplete
            $selectedPatterns = @()
            if ($WordToComplete -like '*,*') {
                $lastComma = $WordToComplete.LastIndexOf(',')
                $prefix = $WordToComplete.Substring(0, $lastComma + 1)
                $segment = $WordToComplete.Substring($lastComma + 1)
                $selectedPatterns = @($prefix.TrimEnd(',').Split(',') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }

            foreach ($item in @(Get-PiModelValueCompletions -WordToComplete $segment)) {
                if ($selectedPatterns -contains $item.CompletionText) {
                    continue
                }

                $completionText = "$prefix$($item.CompletionText)"
                if (-not [string]::IsNullOrEmpty($InlinePrefix)) {
                    $completionText = "$InlinePrefix$completionText"
                }

                [void]$results.Add(
                    (New-PiCompletionResult -CompletionText $completionText -ListItemText $item.ListItemText -ToolTip $item.ToolTip)
                )
            }
        }
        'ApiKey' {
            & $addResult '<api-key>' 'API key value'
        }
        'SystemPrompt' {
            & $addResult '<text>' 'System prompt text'
        }
        'TextOrFile' {
            if (Test-PiPathLike -Value $WordToComplete) {
                foreach ($item in @(Get-PiPathCompletions -PathPrefix $WordToComplete -CompletionPrefix $InlinePrefix)) {
                    [void]$results.Add($item)
                }
            }

            & $addResult '<text-or-file>' 'Text or a file path'
        }
        'ModelSearch' {
            & $addResult '<search>' 'Optional model search text'
        }
        'DirectoryPath' {
            foreach ($item in @(Get-PiPathCompletions -PathPrefix $WordToComplete -DirectoriesOnly -CompletionPrefix $InlinePrefix)) {
                [void]$results.Add($item)
            }

            if ([string]::IsNullOrEmpty($WordToComplete)) {
                & $addResult '.\' 'Directory path'
                & $addResult '..\' 'Directory path'
            }
        }
        'FilePath' {
            foreach ($item in @(Get-PiPathCompletions -PathPrefix $WordToComplete -CompletionPrefix $InlinePrefix)) {
                [void]$results.Add($item)
            }

            if ([string]::IsNullOrEmpty($WordToComplete)) {
                & $addResult '.\' 'File path'
                & $addResult '..\' 'File path'
                & $addResult '<path>' 'File path'
            }
        }
        'ExtensionPath' {
            foreach ($item in @(Get-PiResourcePathCompletions -Kind 'extension' -WordToComplete $WordToComplete)) {
                [void]$results.Add($item)
            }
        }
        'SkillPath' {
            foreach ($item in @(Get-PiResourcePathCompletions -Kind 'skill' -WordToComplete $WordToComplete)) {
                [void]$results.Add($item)
            }
        }
        'PromptTemplatePath' {
            foreach ($item in @(Get-PiResourcePathCompletions -Kind 'prompt-template' -WordToComplete $WordToComplete)) {
                [void]$results.Add($item)
            }
        }
        'ThemePath' {
            foreach ($item in @(Get-PiResourcePathCompletions -Kind 'theme' -WordToComplete $WordToComplete)) {
                [void]$results.Add($item)
            }
        }
        'ExportInputPath' {
            foreach ($item in @(Get-PiPathCompletions -PathPrefix $WordToComplete -CompletionPrefix $InlinePrefix)) {
                [void]$results.Add($item)
            }

            foreach ($sessionFile in @(Get-PiSessionFileSuggestions)) {
                & $addResult $sessionFile 'Session file to export'
            }

            & $addResult '<session.jsonl>' 'Session file to export'
        }
        'ExportOutputPath' {
            foreach ($item in @(Get-PiPathCompletions -PathPrefix $WordToComplete -CompletionPrefix $InlinePrefix)) {
                [void]$results.Add($item)
            }

            if ([string]::IsNullOrEmpty($WordToComplete) -or 'output.html' -like "$WordToComplete*") {
                & $addResult 'output.html' 'Output HTML file'
            }
        }
        'SessionPathOrId' {
            if (Test-PiPathLike -Value $WordToComplete) {
                foreach ($item in @(Get-PiPathCompletions -PathPrefix $WordToComplete -CompletionPrefix $InlinePrefix)) {
                    [void]$results.Add($item)
                }
            } else {
                foreach ($sessionFile in @(Get-PiSessionFileSuggestions)) {
                    & $addResult $sessionFile 'Session file'
                }

                & $addResult '<session-path-or-id>' 'Session path or partial UUID'
            }
        }
        'PackageSource' {
            $sourcePrefixes = @('npm:', 'git:', 'https://', 'ssh://git@github.com/', '.\', '..\')
            foreach ($source in @($sourcePrefixes)) {
                & $addResult $source 'Package source'
            }

            if (Test-PiPathLike -Value $WordToComplete) {
                foreach ($item in @(Get-PiPathCompletions -PathPrefix $WordToComplete -CompletionPrefix $InlinePrefix)) {
                    [void]$results.Add($item)
                }
            }

            & $addResult '<source>' 'Extension source (npm, git, https, ssh, or local path)'
        }
        'InstalledPackageSource' {
            foreach ($source in @('npm:', 'git:', 'https://', 'ssh://git@github.com/', '.\', '..\')) {
                & $addResult $source 'Package source'
            }

            foreach ($source in @(Get-PiInstalledPackageSources)) {
                & $addResult $source 'Installed package source'
            }

            if (Test-PiPathLike -Value $WordToComplete) {
                foreach ($item in @(Get-PiPathCompletions -PathPrefix $WordToComplete -CompletionPrefix $InlinePrefix)) {
                    [void]$results.Add($item)
                }
            }

            & $addResult '<source>' 'Installed package source'
        }
        'UpdateTarget' {
            foreach ($target in @('self', 'pi')) {
                & $addResult $target 'Update target'
            }

            foreach ($source in @(Get-PiInstalledPackageSources)) {
                & $addResult $source 'Installed package source'
            }

            foreach ($source in @('npm:', 'git:', 'https://', 'ssh://git@github.com/', '.\', '..\')) {
                & $addResult $source 'Package source'
            }

            if (Test-PiPathLike -Value $WordToComplete) {
                foreach ($item in @(Get-PiPathCompletions -PathPrefix $WordToComplete -CompletionPrefix $InlinePrefix)) {
                    [void]$results.Add($item)
                }
            }

            & $addResult '<source>' 'Installed package source or self target'
        }
        'MessageFile' {
            foreach ($item in @(Get-PiAtFileCompletions -WordToComplete $WordToComplete)) {
                [void]$results.Add($item)
            }
        }
        'Message' {
            & $addResult '<message>' 'Prompt text'
        }
        default {
            & $addResult '<value>' "Value for $ContextToken"
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($results)) {
        if ($seen.Add($item.CompletionText)) {
            $item
        }
    }
}

function Get-PiOptionCompletions {
    param(
        [object[]]$Options,
        [string]$WordToComplete
    )

    foreach ($option in @($Options)) {
        $completionText = $option.CompletionText
        if ($completionText -notlike "$WordToComplete*") {
            continue
        }

        $toolTip = if ($option.ValueKind) {
            "$($option.Token): $($option.Description)"
        } else {
            $option.Description
        }

        New-PiCompletionResult -CompletionText $completionText -ResultType 'ParameterName' -ToolTip $toolTip
    }
}

function Complete-Pi {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $null = $CursorPosition
    $cache = Get-PiCompletionCache
    $globalOptions = @(Get-PiGlobalOptions)
    $tokens = @(Get-PiProcessedTokens -CommandAst $CommandAst -WordToComplete $WordToComplete)
    $commandSpec = $null
    $positionalsConsumed = 0
    $expectingValue = $null
    $rootMessageMode = $false
    $exportInputConsumed = $false
    $exportOutputConsumed = $false
    $selectedUpdateTarget = $false

    foreach ($token in @($tokens)) {
        if ($expectingValue) {
            $consumeAsValue = $true

            if ($expectingValue.OptionalValue) {
                if ($token.StartsWith('-')) {
                    $consumeAsValue = $false
                } elseif (-not $commandSpec -and -not $rootMessageMode -and (Get-PiCommandSpec -CommandName $token)) {
                    $consumeAsValue = $false
                }
            }

            if ($consumeAsValue) {
                if ($expectingValue.ValueKind -eq 'ExportInputPath' -and -not $commandSpec) {
                    $exportInputConsumed = $true
                }

                if ($commandSpec -and $commandSpec.Name -eq 'update' -and $expectingValue.Token -eq '--extension') {
                    $selectedUpdateTarget = $true
                }

                $expectingValue = $null
                continue
            }

            $expectingValue = $null
        }

        if ($rootMessageMode) {
            continue
        }

        if (-not $commandSpec) {
            if ($token.StartsWith('-')) {
                $globalOption = Find-PiOptionSpec -Token $token -Options $globalOptions
                if ($globalOption) {
                    if ($globalOption.ValueKind) {
                        if ($token.Contains('=')) {
                            $equalsIndex = $token.IndexOf('=')
                            $inlineValue = $token.Substring($equalsIndex + 1)
                            if (-not [string]::IsNullOrWhiteSpace($inlineValue) -and $globalOption.ValueKind -eq 'ExportInputPath') {
                                $exportInputConsumed = $true
                            }
                        } else {
                            $expectingValue = $globalOption
                        }
                    }

                    continue
                }

                continue
            }

            if ((-not $exportInputConsumed) -and (Get-PiCommandSpec -CommandName $token)) {
                $commandSpec = Get-PiCommandSpec -CommandName $token
                continue
            }

            if ($exportInputConsumed -and -not $exportOutputConsumed) {
                $exportOutputConsumed = $true
                continue
            }

            if ($token.StartsWith('@')) {
                continue
            }

            $rootMessageMode = $true
            continue
        }

        if ($token.StartsWith('-')) {
            $commandOption = Find-PiOptionSpec -Token $token -Options $commandSpec.Options
            if ($commandOption) {
                if ($commandSpec.Name -eq 'update' -and $commandOption.Token -in @('--self', '--extensions')) {
                    $selectedUpdateTarget = $true
                }

                if ($commandOption.ValueKind) {
                    if ($token.Contains('=')) {
                        $equalsIndex = $token.IndexOf('=')
                        $inlineValue = $token.Substring($equalsIndex + 1)
                        if ($commandSpec.Name -eq 'update' -and
                            $commandOption.Token -eq '--extension' -and
                            -not [string]::IsNullOrWhiteSpace($inlineValue)) {
                            $selectedUpdateTarget = $true
                        }
                    } else {
                        $expectingValue = $commandOption
                    }
                } elseif ($commandSpec.Name -eq 'update' -and $commandOption.Token -eq '--extension') {
                    $selectedUpdateTarget = $true
                }

                continue
            }

            continue
        }

        $positionalsConsumed++
        if ($commandSpec.Name -eq 'update') {
            $selectedUpdateTarget = $true
        }
    }

    if ($expectingValue -and $expectingValue.OptionalValue) {
        if ($WordToComplete -like '-*') {
            $expectingValue = $null
        }
    }

    if ([string]::IsNullOrEmpty($WordToComplete) -and $tokens.Count -gt 0 -and $tokens[-1].Contains('=')) {
        $options = if ($commandSpec) { $commandSpec.Options } else { $globalOptions }
        $inlineEmptyOption = Find-PiOptionSpec -Token $tokens[-1] -Options $options
        if ($inlineEmptyOption -and $inlineEmptyOption.ValueKind) {
            $equalsIndex = $tokens[-1].IndexOf('=')
            $flagPart = $tokens[-1].Substring(0, $equalsIndex)
            $valuePrefix = $tokens[-1].Substring($equalsIndex + 1)
            if ([string]::IsNullOrEmpty($valuePrefix)) {
                Get-PiValueCompletions -ValueKind $inlineEmptyOption.ValueKind -WordToComplete $valuePrefix -ContextToken $inlineEmptyOption.Token -InlinePrefix "$flagPart="
                return
            }
        }
    }

    if ($WordToComplete -like '*=*') {
        $equalsIndex = $WordToComplete.IndexOf('=')
        $flagPart = $WordToComplete.Substring(0, $equalsIndex)
        $valuePrefix = $WordToComplete.Substring($equalsIndex + 1)
        $options = if ($commandSpec) { $commandSpec.Options } else { $globalOptions }
        $inlineOption = Find-PiOptionSpec -Token $flagPart -Options $options
        if ($inlineOption -and $inlineOption.ValueKind) {
            Get-PiValueCompletions -ValueKind $inlineOption.ValueKind -WordToComplete $valuePrefix -ContextToken $inlineOption.Token -InlinePrefix "$flagPart="
            return
        }
    }

    if ($expectingValue) {
        Get-PiValueCompletions -ValueKind $expectingValue.ValueKind -WordToComplete $WordToComplete -ContextToken $expectingValue.Token
        return
    }

    if ($WordToComplete -like '-*') {
        if ($commandSpec) {
            Get-PiOptionCompletions -Options $commandSpec.Options -WordToComplete $WordToComplete
        } elseif (-not $rootMessageMode) {
            Get-PiOptionCompletions -Options $globalOptions -WordToComplete $WordToComplete
        }
        return
    }

    if ($rootMessageMode) {
        if ($WordToComplete.StartsWith('@')) {
            Get-PiAtFileCompletions -WordToComplete $WordToComplete
            return
        }

        if ([string]::IsNullOrEmpty($WordToComplete)) {
            New-PiCompletionResult -CompletionText '<message>' -ToolTip 'Prompt text'
        }
        return
    }

    if (-not $commandSpec) {
        if ($exportInputConsumed -and -not $exportOutputConsumed) {
            Get-PiValueCompletions -ValueKind 'ExportOutputPath' -WordToComplete $WordToComplete -ContextToken '--export'
            return
        }

        if ($WordToComplete.StartsWith('@')) {
            Get-PiAtFileCompletions -WordToComplete $WordToComplete
            return
        }

        $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

        foreach ($command in @(Get-PiRootCommands)) {
            if ($command.Name -like "$WordToComplete*") {
                [void]$results.Add(
                    (New-PiCompletionResult -CompletionText $command.Name -ToolTip $command.Description)
                )
            }
        }

        if ([string]::IsNullOrEmpty($WordToComplete)) {
            foreach ($option in @(Get-PiOptionCompletions -Options $globalOptions -WordToComplete '')) {
                [void]$results.Add($option)
            }

            [void]$results.Add((New-PiCompletionResult -CompletionText '@' -ToolTip 'Prefix a file path with @ to include it in the message'))
        }

        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in @($results)) {
            if ($seen.Add($item.CompletionText)) {
                $item
            }
        }
        return
    }

    $valueKind = if ($commandSpec.Name -eq 'update' -and $selectedUpdateTarget -and $positionalsConsumed -eq 0) {
        $null
    } elseif ($positionalsConsumed -lt $commandSpec.Positionals.Count) {
        $commandSpec.Positionals[$positionalsConsumed]
    } else {
        $null
    }

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    if ($valueKind) {
        foreach ($item in @(Get-PiValueCompletions -ValueKind $valueKind -WordToComplete $WordToComplete -ContextToken $commandSpec.Name)) {
            [void]$results.Add($item)
        }
    }

    if ([string]::IsNullOrEmpty($WordToComplete)) {
        foreach ($option in @(Get-PiOptionCompletions -Options $commandSpec.Options -WordToComplete '')) {
            [void]$results.Add($option)
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($results)) {
        if ($seen.Add($item.CompletionText)) {
            $item
        }
    }
}

Register-ArgumentCompleter -Native -CommandName @('pi', 'pi.cmd', 'pi.ps1') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pi -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
