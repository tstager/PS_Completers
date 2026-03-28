<#
.SYNOPSIS
Registers a native PowerShell argument completer for GitHub Copilot CLI.

.DESCRIPTION
Provides standalone completion for `copilot` and `copilot.exe` using a hybrid
model:

- static command, subcommand, and option metadata
- dynamic model discovery from `copilot help config`
- dynamic marketplace and installed-plugin discovery from local plugin commands
- path completion for directory and file-bearing values
- placeholder completions for freeform values to avoid irrelevant filesystem fallback

Load this script once per session, or dot-source it from your PowerShell profile.
#>

Set-StrictMode -Version Latest

if (-not (Get-Variable -Name CopilotCompletionCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CopilotCompletionCache = @{
        ExecutablePath             = $null
        ExecutablePathProbed       = $false
        Models                     = @()
        ModelsLoadedAt             = [datetime]::MinValue
        Marketplaces               = @()
        MarketplacesLoadedAt       = [datetime]::MinValue
        InstalledPlugins           = @()
        InstalledPluginsLoadedAt   = [datetime]::MinValue
        ModelCacheTtlSeconds       = 300
        RuntimeCacheTtlSeconds     = 60
        HelpTopics                 = @('commands', 'config', 'environment', 'logging', 'permissions', 'providers')
        GlobalOptions              = $null
        CommandSpecs               = $null
    }
}

function New-CopilotCompletionResult {
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

function Get-CopilotUniqueStrings {
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

function New-CopilotOptionSpec {
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

function ConvertTo-CopilotQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + ($Value.Replace('`', '``').Replace('"', '`"')) + '"'
    }

    $Value
}

function Get-CopilotTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Resolve-CopilotExecutablePath {
    if ($script:CopilotCompletionCache.ExecutablePathProbed) {
        return $script:CopilotCompletionCache.ExecutablePath
    }

    $script:CopilotCompletionCache.ExecutablePathProbed = $true
    $script:CopilotCompletionCache.ExecutablePath = $null

    foreach ($commandName in @('copilot.exe', 'copilot')) {
        $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            $script:CopilotCompletionCache.ExecutablePath = if ($command.Source) { $command.Source } else { $command.Name }
            break
        }
    }

    $script:CopilotCompletionCache.ExecutablePath
}

function Invoke-CopilotCapture {
    param([string[]]$Arguments)

    $executablePath = Resolve-CopilotExecutablePath
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        return @()
    }

    try {
        @(& $executablePath @Arguments 2>$null)
    } catch {
        @()
    }
}

function Test-CopilotCacheFresh {
    param(
        [datetime]$LoadedAt,
        [int]$TtlSeconds
    )

    if ($LoadedAt -eq [datetime]::MinValue) {
        return $false
    }

    ((Get-Date) - $LoadedAt).TotalSeconds -lt $TtlSeconds
}

function Get-CopilotModels {
    if (Test-CopilotCacheFresh -LoadedAt $script:CopilotCompletionCache.ModelsLoadedAt -TtlSeconds $script:CopilotCompletionCache.ModelCacheTtlSeconds) {
        return $script:CopilotCompletionCache.Models
    }

    $lines = Invoke-CopilotCapture -Arguments @('help', 'config')
    $models = New-Object System.Collections.Generic.List[string]
    $inModelSection = $false

    foreach ($line in @($lines)) {
        if ($line -match '^\s*`model`:\s') {
            $inModelSection = $true
            continue
        }

        if ($inModelSection -and $line -match '^\s*`[^`]+`:\s') {
            break
        }

        if ($inModelSection -and $line -match '^\s*-\s+"([^"]+)"') {
            [void]$models.Add($matches[1])
        }
    }

    $script:CopilotCompletionCache.Models = Get-CopilotUniqueStrings -Items @($models.ToArray())
    $script:CopilotCompletionCache.ModelsLoadedAt = Get-Date
    $script:CopilotCompletionCache.Models
}

function Get-CopilotMarketplaceNames {
    if (Test-CopilotCacheFresh -LoadedAt $script:CopilotCompletionCache.MarketplacesLoadedAt -TtlSeconds $script:CopilotCompletionCache.RuntimeCacheTtlSeconds) {
        return $script:CopilotCompletionCache.Marketplaces
    }

    $lines = Invoke-CopilotCapture -Arguments @('plugin', 'marketplace', 'list')
    $names = foreach ($line in @($lines)) {
        if ($line -match '^\s+\S+\s+([A-Za-z0-9._-]+)(?:\s+\(|$)') {
            $matches[1]
        }
    }

    $script:CopilotCompletionCache.Marketplaces = Get-CopilotUniqueStrings -Items $names
    $script:CopilotCompletionCache.MarketplacesLoadedAt = Get-Date
    $script:CopilotCompletionCache.Marketplaces
}

function Get-CopilotInstalledPluginNames {
    if (Test-CopilotCacheFresh -LoadedAt $script:CopilotCompletionCache.InstalledPluginsLoadedAt -TtlSeconds $script:CopilotCompletionCache.RuntimeCacheTtlSeconds) {
        return $script:CopilotCompletionCache.InstalledPlugins
    }

    $lines = Invoke-CopilotCapture -Arguments @('plugin', 'list')
    $names = foreach ($line in @($lines)) {
        if ($line -match '^\s+\S+\s+(.+?)(?:\s+\(.*\))?$') {
            $matches[1]
        }
    }

    $script:CopilotCompletionCache.InstalledPlugins = Get-CopilotUniqueStrings -Items $names
    $script:CopilotCompletionCache.InstalledPluginsLoadedAt = Get-Date
    $script:CopilotCompletionCache.InstalledPlugins
}

function Initialize-CopilotStaticMetadata {
    if ($script:CopilotCompletionCache.GlobalOptions -and $script:CopilotCompletionCache.CommandSpecs) {
        return
    }

    $script:CopilotCompletionCache.GlobalOptions = @(
        New-CopilotOptionSpec -Tokens @('--effort', '--reasoning-effort') -Description 'Set the reasoning effort level.' -ValueKind 'ReasoningEffort'
        New-CopilotOptionSpec -Tokens @('--acp') -Description 'Start as Agent Client Protocol server.'
        New-CopilotOptionSpec -Tokens @('--add-dir') -Description 'Add a directory to the allowed list for file access.' -ValueKind 'DirectoryPath'
        New-CopilotOptionSpec -Tokens @('--add-github-mcp-tool') -Description 'Enable an additional GitHub MCP tool.' -ValueKind 'GithubMcpTool'
        New-CopilotOptionSpec -Tokens @('--add-github-mcp-toolset') -Description 'Enable an additional GitHub MCP toolset.' -ValueKind 'GithubMcpToolset'
        New-CopilotOptionSpec -Tokens @('--additional-mcp-config') -Description 'Additional MCP config JSON or @file path.' -ValueKind 'AdditionalMcpConfig'
        New-CopilotOptionSpec -Tokens @('--agent') -Description 'Specify a custom agent to use.' -ValueKind 'AgentName'
        New-CopilotOptionSpec -Tokens @('--allow-all') -Description 'Enable all permissions.'
        New-CopilotOptionSpec -Tokens @('--allow-all-paths') -Description 'Allow access to any file path.'
        New-CopilotOptionSpec -Tokens @('--allow-all-tools') -Description 'Allow all tools to run automatically.'
        New-CopilotOptionSpec -Tokens @('--allow-all-urls') -Description 'Allow access to all URLs without confirmation.'
        New-CopilotOptionSpec -Tokens @('--allow-tool') -Description 'Grant permission to a specific tool or tool pattern.' -ValueKind 'ToolPattern' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--allow-url') -Description 'Grant permission to a specific URL or domain.' -ValueKind 'UrlPattern' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--autopilot') -Description 'Enable autopilot continuation in prompt mode.'
        New-CopilotOptionSpec -Tokens @('--available-tools') -Description 'Only these tools will be available to the model.' -ValueKind 'ToolPattern' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--banner') -Description 'Show the startup banner.'
        New-CopilotOptionSpec -Tokens @('--bash-env') -Description 'Enable BASH_ENV support for bash shells.' -ValueKind 'OnOff' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--config-dir') -Description 'Set the configuration directory.' -ValueKind 'DirectoryPath'
        New-CopilotOptionSpec -Tokens @('--continue') -Description 'Resume the most recent session.'
        New-CopilotOptionSpec -Tokens @('--deny-tool') -Description 'Deny a tool or tool pattern.' -ValueKind 'ToolPattern' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--deny-url') -Description 'Deny a URL or domain.' -ValueKind 'UrlPattern' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--disable-builtin-mcps') -Description 'Disable all built-in MCP servers.'
        New-CopilotOptionSpec -Tokens @('--disable-mcp-server') -Description 'Disable a specific MCP server.' -ValueKind 'ServerName'
        New-CopilotOptionSpec -Tokens @('--disallow-temp-dir') -Description 'Prevent automatic access to the system temp directory.'
        New-CopilotOptionSpec -Tokens @('--enable-all-github-mcp-tools') -Description 'Enable all GitHub MCP server tools.'
        New-CopilotOptionSpec -Tokens @('--enable-reasoning-summaries') -Description 'Request reasoning summaries for OpenAI models.'
        New-CopilotOptionSpec -Tokens @('--excluded-tools') -Description 'These tools will not be available to the model.' -ValueKind 'ToolPattern' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--experimental') -Description 'Enable experimental features.'
        New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
        New-CopilotOptionSpec -Tokens @('-i', '--interactive') -Description 'Start interactive mode and execute this prompt.' -ValueKind 'PromptText'
        New-CopilotOptionSpec -Tokens @('--log-dir') -Description 'Set the log file directory.' -ValueKind 'DirectoryPath'
        New-CopilotOptionSpec -Tokens @('--log-level') -Description 'Set the log level.' -ValueKind 'LogLevel'
        New-CopilotOptionSpec -Tokens @('--max-autopilot-continues') -Description 'Maximum continuation count in autopilot mode.' -ValueKind 'Count'
        New-CopilotOptionSpec -Tokens @('--model') -Description 'Set the AI model to use.' -ValueKind 'Model'
        New-CopilotOptionSpec -Tokens @('--mouse') -Description 'Enable mouse support in alt screen mode.' -ValueKind 'OnOff' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--no-ask-user') -Description 'Disable the ask_user tool.'
        New-CopilotOptionSpec -Tokens @('--no-auto-update') -Description 'Disable automatic update downloads.'
        New-CopilotOptionSpec -Tokens @('--no-bash-env') -Description 'Disable BASH_ENV support for bash shells.'
        New-CopilotOptionSpec -Tokens @('--no-color') -Description 'Disable all color output.'
        New-CopilotOptionSpec -Tokens @('--no-custom-instructions') -Description 'Disable loading custom instructions files.'
        New-CopilotOptionSpec -Tokens @('--no-experimental') -Description 'Disable experimental features.'
        New-CopilotOptionSpec -Tokens @('--no-mouse') -Description 'Disable mouse support in alt screen mode.'
        New-CopilotOptionSpec -Tokens @('--output-format') -Description 'Set output format.' -ValueKind 'OutputFormat'
        New-CopilotOptionSpec -Tokens @('-p', '--prompt') -Description 'Execute a prompt in non-interactive mode.' -ValueKind 'PromptText'
        New-CopilotOptionSpec -Tokens @('--plain-diff') -Description 'Disable rich diff rendering.'
        New-CopilotOptionSpec -Tokens @('--plugin-dir') -Description 'Load a plugin from a local directory.' -ValueKind 'DirectoryPath'
        New-CopilotOptionSpec -Tokens @('--resume') -Description 'Resume from a previous session or task ID.' -ValueKind 'ResumeSession' -OptionalValue
        New-CopilotOptionSpec -Tokens @('-s', '--silent') -Description 'Output only the agent response.'
        New-CopilotOptionSpec -Tokens @('--screen-reader') -Description 'Enable screen reader optimizations.'
        New-CopilotOptionSpec -Tokens @('--secret-env-vars') -Description 'Strip and redact selected environment variable values.' -ValueKind 'EnvVarList' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--share') -Description 'Share session to a markdown file after completion.' -ValueKind 'SharePath' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--share-gist') -Description 'Share session to a secret GitHub gist after completion.'
        New-CopilotOptionSpec -Tokens @('--stream') -Description 'Enable or disable streaming mode.' -ValueKind 'OnOff'
        New-CopilotOptionSpec -Tokens @('-v', '--version') -Description 'Show version information.'
        New-CopilotOptionSpec -Tokens @('--yolo') -Description 'Enable all permissions.'
    )

    $script:CopilotCompletionCache.CommandSpecs = @{
        ''                           = @{
            Commands   = [ordered]@{
                'help'    = 'Display help information.'
                'init'    = 'Initialize Copilot instructions.'
                'login'   = 'Authenticate with Copilot.'
                'plugin'  = 'Manage plugins.'
                'update'  = 'Download the latest version.'
                'version' = 'Display version information.'
            }
            Options    = @()
            Positionals = @()
        }
        'help'                       = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @(
                @{ Name = 'topic'; ValueKind = 'HelpTopic'; Description = 'Help topic (e.g. environment).' }
            )
        }
        'init'                       = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @()
        }
        'login'                      = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('--config-dir') -Description 'Set the configuration directory.' -ValueKind 'DirectoryPath'
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
                New-CopilotOptionSpec -Tokens @('--host') -Description 'GitHub host URL.' -ValueKind 'Host'
            )
            Positionals = @()
        }
        'plugin'                     = @{
            Commands   = [ordered]@{
                'install'     = 'Install a plugin.'
                'list'        = 'List installed plugins.'
                'marketplace' = 'Manage plugin marketplaces.'
                'uninstall'   = 'Uninstall a plugin.'
                'update'      = 'Update a plugin.'
            }
            Options    = @(
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @()
        }
        'plugin install'             = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('--config-dir') -Description 'Path to the configuration directory.' -ValueKind 'DirectoryPath'
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @(
                @{ Name = 'source'; ValueKind = 'PluginSource'; Description = 'Plugin source: plugin@marketplace, owner/repo, owner/repo:path, URL, or local path.' }
            )
        }
        'plugin list'                = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('--config-dir') -Description 'Path to the configuration directory.' -ValueKind 'DirectoryPath'
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @()
        }
        'plugin uninstall'           = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('--config-dir') -Description 'Path to the configuration directory.' -ValueKind 'DirectoryPath'
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @(
                @{ Name = 'name'; ValueKind = 'InstalledPlugin'; Description = 'Installed plugin name.' }
            )
        }
        'plugin update'              = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('--config-dir') -Description 'Path to the configuration directory.' -ValueKind 'DirectoryPath'
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @(
                @{ Name = 'name'; ValueKind = 'InstalledPlugin'; Description = 'Installed plugin name.' }
            )
        }
        'plugin marketplace'         = @{
            Commands   = [ordered]@{
                'add'    = 'Add a marketplace.'
                'browse' = 'Browse plugins in a marketplace.'
                'list'   = 'List registered marketplaces.'
                'remove' = 'Remove a marketplace.'
            }
            Options    = @(
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @()
        }
        'plugin marketplace add'     = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('--config-dir') -Description 'Path to the configuration directory.' -ValueKind 'DirectoryPath'
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @(
                @{ Name = 'source'; ValueKind = 'MarketplaceSource'; Description = 'Marketplace source: owner/repo, URL, or local path.' }
            )
        }
        'plugin marketplace browse'  = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('--config-dir') -Description 'Path to the configuration directory.' -ValueKind 'DirectoryPath'
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @(
                @{ Name = 'name'; ValueKind = 'MarketplaceName'; Description = 'Registered marketplace name.' }
            )
        }
        'plugin marketplace list'    = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('--config-dir') -Description 'Path to the configuration directory.' -ValueKind 'DirectoryPath'
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @()
        }
        'plugin marketplace remove'  = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('--config-dir') -Description 'Path to the configuration directory.' -ValueKind 'DirectoryPath'
                New-CopilotOptionSpec -Tokens @('-f', '--force') -Description 'Force removal even if plugins are installed.'
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @(
                @{ Name = 'name'; ValueKind = 'MarketplaceName'; Description = 'Registered marketplace name.' }
            )
        }
        'update'                     = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @()
        }
        'version'                    = @{
            Commands   = [ordered]@{}
            Options    = @(
                New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
            )
            Positionals = @()
        }
    }
}

function Get-CopilotPathKey {
    param([string[]]$Path)

    (($Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ')
}

function Get-CopilotCommandSpec {
    param([string[]]$Path)

    Initialize-CopilotStaticMetadata

    $key = Get-CopilotPathKey -Path $Path
    if ($script:CopilotCompletionCache.CommandSpecs.ContainsKey($key)) {
        return $script:CopilotCompletionCache.CommandSpecs[$key]
    }

    $script:CopilotCompletionCache.CommandSpecs['']
}

function Get-CopilotMergedOptionSpecs {
    param([object[]]$Options)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($option in @($Options)) {
        if ($null -eq $option -or [string]::IsNullOrWhiteSpace($option.Token)) {
            continue
        }

        if ($seen.Add([string]$option.Token)) {
            [void]$results.Add($option)
        }
    }

    @($results.ToArray())
}

function Get-CopilotOptionsForPath {
    param([string[]]$Path)

    Initialize-CopilotStaticMetadata

    if (@($Path).Count -eq 0) {
        return $script:CopilotCompletionCache.GlobalOptions
    }

    $localOptions = @((Get-CopilotCommandSpec -Path $Path).Options)
    @(Get-CopilotMergedOptionSpecs -Options @($script:CopilotCompletionCache.GlobalOptions + $localOptions))
}

function Get-CopilotCommandsForPath {
    param([string[]]$Path)

    (Get-CopilotCommandSpec -Path $Path).Commands
}

function Find-CopilotExactOptionSpec {
    param(
        [string]$Token,
        [string[]]$Path
    )

    foreach ($option in @(Get-CopilotOptionsForPath -Path $Path)) {
        if ($option.Token.Equals($Token, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $option
        }
    }

    $null
}

function Find-CopilotInlineOptionSpec {
    param(
        [string]$Token,
        [string[]]$Path
    )

    $candidates = @(Get-CopilotOptionsForPath -Path $Path) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.ValueKind) } |
        Sort-Object { $_.Token.Length } -Descending

    foreach ($option in $candidates) {
        $prefix = $option.Token + '='
        if ($Token.Length -ge $prefix.Length -and $Token.Substring(0, $prefix.Length).Equals($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $option
        }
    }

    $null
}

function Test-CopilotLooksLikeOption {
    param([string]$Token)

    -not [string]::IsNullOrWhiteSpace($Token) -and $Token.StartsWith('-')
}

function Test-CopilotLooksLikePath {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    $cleanToken = $Token.Trim([char[]]@([char]34, [char]39))
    $cleanToken.StartsWith('.') -or
    $cleanToken.StartsWith('~') -or
    $cleanToken.StartsWith('\') -or
    $cleanToken.Contains('\') -or
    $cleanToken -match '^[A-Za-z]:'
}

function Get-CopilotPathCompletions {
    param(
        [string]$InputPath,
        [string]$Prefix = '',
        [switch]$DirectoriesOnly
    )

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and $InputPath.StartsWith('"')

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $items = @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)
    if ($DirectoriesOnly) {
        $items = @($items | Where-Object { $_.PSIsContainer })
    }

    foreach ($item in $items) {
        $completionText = if ($cleanInput -and -not [System.IO.Path]::IsPathRooted($cleanInput)) {
            if ($parent -eq '.') {
                $item.Name
            } else {
                Join-Path -Path $parent -ChildPath $item.Name
            }
        } else {
            $item.FullName
        }

        if ($item.PSIsContainer -and -not $completionText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionText += [System.IO.Path]::DirectorySeparatorChar
        }

        $completionText = ConvertTo-CopilotQuotedValue -Value $completionText -AlwaysQuote $alwaysQuote
        $completionText = $Prefix + $completionText

        New-CopilotCompletionResult -CompletionText $completionText -ToolTip $item.FullName -ListItemText $item.Name
    }
}

function New-CopilotLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-CopilotCompletionResult -CompletionText $Placeholder -ToolTip $ToolTip -ListItemText $Placeholder
        )
    }

    @(
        New-CopilotCompletionResult -CompletionText $CurrentValue -ToolTip $ToolTip -ListItemText $CurrentValue
    )
}

function Get-CopilotValueResults {
    param(
        [string]$ValueKind,
        [string]$CurrentValue,
        [string]$Prefix = ''
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }

    switch ($ValueKind) {
        'Model' {
            $models = @(Get-CopilotModels)
            if ($models.Count -eq 0) {
                return New-CopilotLiteralValueResults -CurrentValue $typedValue -Placeholder '<model>' -ToolTip 'Model name from `copilot help config`.'
            }

            return $models |
                Where-Object { $_ -like "$typedValue*" } |
                ForEach-Object {
                    New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Model name discovered from `copilot help config`.'
                }
        }
        'ReasoningEffort' {
            return @('low', 'medium', 'high', 'xhigh') |
                Where-Object { $_ -like "$typedValue*" } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Reasoning effort level.' }
        }
        'OutputFormat' {
            return @('text', 'json') |
                Where-Object { $_ -like "$typedValue*" } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Output format.' }
        }
        'OnOff' {
            return @('on', 'off') |
                Where-Object { $_ -like "$typedValue*" } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Boolean on/off value.' }
        }
        'LogLevel' {
            return @('none', 'error', 'warning', 'info', 'debug', 'all', 'default') |
                Where-Object { $_ -like "$typedValue*" } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'CLI log level.' }
        }
        'DirectoryPath' {
            return @(Get-CopilotPathCompletions -InputPath $typedValue -Prefix $Prefix -DirectoriesOnly)
        }
        'SharePath' {
            $results = New-Object System.Collections.Generic.List[object]
            foreach ($result in @(Get-CopilotPathCompletions -InputPath $typedValue -Prefix $Prefix)) {
                [void]$results.Add($result)
            }

            if ([string]::IsNullOrWhiteSpace($typedValue)) {
                [void]$results.Add((New-CopilotCompletionResult -CompletionText ($Prefix + '.\copilot-session-<id>.md') -ToolTip 'Default markdown share path pattern.'))
            }

            return @($results.ToArray())
        }
        'AdditionalMcpConfig' {
            if ($typedValue.StartsWith('@')) {
                return @(Get-CopilotPathCompletions -InputPath $typedValue.Substring(1) -Prefix ($Prefix + '@'))
            }

            $results = New-Object System.Collections.Generic.List[object]
            if ([string]::IsNullOrWhiteSpace($typedValue) -or '@' -like "$typedValue*") {
                [void]$results.Add((New-CopilotCompletionResult -CompletionText ($Prefix + '@') -ToolTip 'Prefix a file path with @ to load JSON from disk.'))
            }

            foreach ($result in @(New-CopilotLiteralValueResults -CurrentValue $typedValue -Placeholder '<json-or-@file>' -ToolTip 'Inline JSON string or @file path.')) {
                [void]$results.Add($result)
            }

            return @($results.ToArray())
        }
        'HelpTopic' {
            return $script:CopilotCompletionCache.HelpTopics |
                Where-Object { $_ -like "$typedValue*" } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Copilot help topic.' }
        }
        'InstalledPlugin' {
            $plugins = @(Get-CopilotInstalledPluginNames)
            if ($plugins.Count -eq 0) {
                return New-CopilotLiteralValueResults -CurrentValue $typedValue -Placeholder '<plugin-name>' -ToolTip 'Installed plugin name.'
            }

            return $plugins |
                Where-Object { $_ -like "$typedValue*" } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Installed plugin.' }
        }
        'MarketplaceName' {
            $marketplaces = @(Get-CopilotMarketplaceNames)
            if ($marketplaces.Count -eq 0) {
                return New-CopilotLiteralValueResults -CurrentValue $typedValue -Placeholder '<marketplace-name>' -ToolTip 'Registered marketplace name.'
            }

            return $marketplaces |
                Where-Object { $_ -like "$typedValue*" } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Registered marketplace.' }
        }
        'PluginSource' {
            if (Test-CopilotLooksLikePath -Token $typedValue) {
                return @(Get-CopilotPathCompletions -InputPath $typedValue -Prefix $Prefix)
            }

            return @(
                New-CopilotCompletionResult -CompletionText ($Prefix + 'plugin-name@marketplace') -ToolTip 'Install from a registered marketplace.'
                New-CopilotCompletionResult -CompletionText ($Prefix + 'owner/repo') -ToolTip 'Install directly from a GitHub repository.'
                New-CopilotCompletionResult -CompletionText ($Prefix + 'owner/repo:path/to/plugin') -ToolTip 'Install from a repository subdirectory.'
                New-CopilotCompletionResult -CompletionText ($Prefix + 'https://example.com/plugin.git') -ToolTip 'Install from a git URL.'
            ) | Where-Object { $_.CompletionText -like "$Prefix$typedValue*" }
        }
        'MarketplaceSource' {
            if (Test-CopilotLooksLikePath -Token $typedValue) {
                return @(Get-CopilotPathCompletions -InputPath $typedValue -Prefix $Prefix)
            }

            return @(
                New-CopilotCompletionResult -CompletionText ($Prefix + 'owner/repo') -ToolTip 'Add a marketplace from a GitHub repository.'
                New-CopilotCompletionResult -CompletionText ($Prefix + 'https://example.com/marketplace.git') -ToolTip 'Add a marketplace from a URL.'
                New-CopilotCompletionResult -CompletionText ($Prefix + '.\path\to\marketplace') -ToolTip 'Add a marketplace from a local path.'
            ) | Where-Object { $_.CompletionText -like "$Prefix$typedValue*" }
        }
        'Host' {
            $results = @(
                New-CopilotCompletionResult -CompletionText ($Prefix + 'https://github.com') -ToolTip 'Default GitHub host.'
                New-CopilotCompletionResult -CompletionText ($Prefix + 'https://example.ghe.com') -ToolTip 'Example GitHub Enterprise Cloud data residency host.'
            ) | Where-Object { $_.CompletionText -like "$Prefix$typedValue*" }

            if (@($results).Count -gt 0) {
                return $results
            }

            return New-CopilotLiteralValueResults -CurrentValue ($Prefix + $typedValue) -Placeholder ($Prefix + 'https://example.ghe.com') -ToolTip 'GitHub host URL.'
        }
        'ResumeSession' {
            return New-CopilotLiteralValueResults -CurrentValue ($Prefix + $typedValue) -Placeholder ($Prefix + '<session-id>') -ToolTip 'Session ID or task ID.'
        }
        'AgentName' {
            return New-CopilotLiteralValueResults -CurrentValue ($Prefix + $typedValue) -Placeholder ($Prefix + '<agent>') -ToolTip 'Custom agent name.'
        }
        'PromptText' {
            return New-CopilotLiteralValueResults -CurrentValue ($Prefix + $typedValue) -Placeholder ($Prefix + '"<prompt>"') -ToolTip 'Prompt text.'
        }
        'ToolPattern' {
            return New-CopilotLiteralValueResults -CurrentValue ($Prefix + $typedValue) -Placeholder ($Prefix + 'shell(git:*)') -ToolTip 'Tool name or permission pattern.'
        }
        'UrlPattern' {
            return New-CopilotLiteralValueResults -CurrentValue ($Prefix + $typedValue) -Placeholder ($Prefix + 'github.com') -ToolTip 'URL, domain, or wildcard domain.'
        }
        'ServerName' {
            return New-CopilotLiteralValueResults -CurrentValue ($Prefix + $typedValue) -Placeholder ($Prefix + '<server-name>') -ToolTip 'MCP server name.'
        }
        'EnvVarList' {
            return New-CopilotLiteralValueResults -CurrentValue ($Prefix + $typedValue) -Placeholder ($Prefix + 'MY_KEY,OTHER_KEY') -ToolTip 'Comma-separated environment variable names.'
        }
        'GithubMcpTool' {
            return New-CopilotLiteralValueResults -CurrentValue ($Prefix + $typedValue) -Placeholder ($Prefix + '*') -ToolTip 'GitHub MCP tool name or "*".'
        }
        'GithubMcpToolset' {
            return New-CopilotLiteralValueResults -CurrentValue ($Prefix + $typedValue) -Placeholder ($Prefix + 'all') -ToolTip 'GitHub MCP toolset name or "all".'
        }
        'Count' {
            return New-CopilotLiteralValueResults -CurrentValue ($Prefix + $typedValue) -Placeholder ($Prefix + '<count>') -ToolTip 'Numeric count.'
        }
        default {
            return @()
        }
    }
}

function Resolve-CopilotParseState {
    param([string[]]$Tokens)

    $state = @{
        Path              = @()
        PendingOption     = $null
        PositionalsConsumed = 0
    }

    $index = 0
    while ($index -lt @($Tokens).Count) {
        $token = $Tokens[$index]

        if ($state.PendingOption) {
            if ($state.PendingOption.OptionalValue) {
                $commands = Get-CopilotCommandsForPath -Path $state.Path
                $isCommand = $commands.Contains($token.ToLowerInvariant())
                if ((Test-CopilotLooksLikeOption -Token $token) -or $isCommand) {
                    $state.PendingOption = $null
                    continue
                }
            }

            $state.PendingOption = $null
            $index++
            continue
        }

        $inlineOption = Find-CopilotInlineOptionSpec -Token $token -Path $state.Path
        if ($inlineOption) {
            $index++
            continue
        }

        $exactOption = Find-CopilotExactOptionSpec -Token $token -Path $state.Path
        if ($exactOption) {
            if (-not [string]::IsNullOrWhiteSpace($exactOption.ValueKind)) {
                $state.PendingOption = $exactOption
            }

            $index++
            continue
        }

        $commandsForPath = Get-CopilotCommandsForPath -Path $state.Path
        $commandMatch = $null
        foreach ($commandName in $commandsForPath.Keys) {
            if ($commandName.Equals($token, [System.StringComparison]::OrdinalIgnoreCase)) {
                $commandMatch = $commandName
                break
            }
        }

        if ($commandMatch) {
            $state.Path = @($state.Path + $commandMatch)
            $index++
            continue
        }

        $state.PositionalsConsumed++
        $index++
    }

    $state
}

function Get-CopilotSuggestions {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    Initialize-CopilotStaticMetadata

    $allTokens = @($CommandAst.CommandElements | ForEach-Object { Get-CopilotTokenText -Element $_ })
    $tokens = @($allTokens | Select-Object -Skip 1)
    $line = $CommandAst.ToString()
    $hasTrailingSpace = ([string]::IsNullOrEmpty($WordToComplete) -and $CursorPosition -ge $line.Length) -or ($line -match '\s$')

    if ($hasTrailingSpace) {
        $currentWord = ''
        $tokensBeforeCurrent = @($tokens)
    } else {
        $currentWord = if ($null -eq $WordToComplete) { '' } else { $WordToComplete }
        if ($tokens.Count -gt 0) {
            $tokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
        } else {
            $tokensBeforeCurrent = @()
        }
    }

    $state = Resolve-CopilotParseState -Tokens $tokensBeforeCurrent
    $spec = Get-CopilotCommandSpec -Path $state.Path

    $inlineOption = $null
    if (-not [string]::IsNullOrWhiteSpace($currentWord)) {
        $inlineOption = Find-CopilotInlineOptionSpec -Token $currentWord -Path $state.Path
    }

    if ($inlineOption) {
        $prefix = $inlineOption.Token + '='
        $typedValue = $currentWord.Substring($prefix.Length)
        return @(Get-CopilotValueResults -ValueKind $inlineOption.ValueKind -CurrentValue $typedValue -Prefix $prefix)
    }

    if ($state.PendingOption) {
        return @(Get-CopilotValueResults -ValueKind $state.PendingOption.ValueKind -CurrentValue $currentWord)
    }

    if ($currentWord.StartsWith('-')) {
        return @(Get-CopilotOptionsForPath -Path $state.Path) |
            Where-Object { $_.Token -like "$currentWord*" } |
            ForEach-Object {
                New-CopilotCompletionResult -CompletionText $_.Token -ResultType 'ParameterName' -ToolTip $_.Description
            }
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ($state.PositionalsConsumed -lt @($spec.Positionals).Count) {
        $positional = $spec.Positionals[$state.PositionalsConsumed]
        foreach ($result in @(Get-CopilotValueResults -ValueKind $positional.ValueKind -CurrentValue $currentWord)) {
            [void]$results.Add($result)
        }
    }

    foreach ($commandName in $spec.Commands.Keys) {
        if ($commandName -like "$currentWord*") {
            [void]$results.Add((New-CopilotCompletionResult -CompletionText $commandName -ToolTip $spec.Commands[$commandName]))
        }
    }

    if ([string]::IsNullOrEmpty($currentWord) -or $currentWord.StartsWith('-')) {
        foreach ($option in @(Get-CopilotOptionsForPath -Path $state.Path)) {
            if ($option.Token -like "$currentWord*") {
                [void]$results.Add((New-CopilotCompletionResult -CompletionText $option.Token -ResultType 'ParameterName' -ToolTip $option.Description))
            }
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($result in @($results.ToArray())) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.Add($result.CompletionText)) {
            $result
        }
    }
}

Register-ArgumentCompleter -Native -CommandName @('copilot', 'copilot.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Get-CopilotSuggestions -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
