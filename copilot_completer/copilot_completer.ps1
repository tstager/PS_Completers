<#
.SYNOPSIS
Registers a native PowerShell argument completer for GitHub Copilot CLI.

.DESCRIPTION
Provides standalone completion for `copilot` and `copilot.exe` using a hybrid
model:

- static command, subcommand, and option metadata (copilot 1.0.92); root
  options are offered only before the first subcommand, as copilot requires
- dynamic model discovery from `copilot help config`
- dynamic `copilot config` keys and values from `copilot completion bash`
- dynamic marketplace and installed-plugin discovery from local plugin commands
- path completion for directory and file-bearing values
- placeholder completions for freeform values to avoid irrelevant filesystem fallback

Load this script once per session, or dot-source it from your PowerShell profile.
#>

Set-StrictMode -Version Latest

if (-not (Get-Variable -Name CopilotCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:CopilotCompletionCache = @{
        ExecutablePath             = $null
        ExecutablePathProbed       = $false
        Models                     = @()
        ModelsLoadedAt             = $null
        Marketplaces               = @()
        MarketplacesLoadedAt       = $null
        InstalledPlugins           = @()
        InstalledPluginsLoadedAt   = $null
        ConfigSchema               = $null
        ConfigSchemaLoadedAt       = $null
        ModelCacheTtlSeconds       = 300
        RuntimeCacheTtlSeconds     = 60
        HelpTopics                 = @('billing', 'commands', 'config', 'environment', 'limits', 'logging', 'monitoring', 'permissions', 'providers', 'sandbox')
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
        [switch]$OptionalValue,
        # [<x>...]: takes every following word up to the next option.
        [switch]$Variadic
    )

    foreach ($token in @($Tokens)) {
        [pscustomobject]@{
            Token         = $token
            Description   = $Description
            ValueKind     = $ValueKind
            OptionalValue = [bool]$OptionalValue
            Variadic      = [bool]$Variadic
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
        $command = Get-Command -Name $commandName -ErrorAction Ignore | Select-Object -First 1
        if ($command) {
            $script:CopilotCompletionCache.ExecutablePath = if ($command.Source) { $command.Source } else { $command.Name }
            break
        }
    }

    $script:CopilotCompletionCache.ExecutablePath
}

function Invoke-CopilotCapture {
    param(
        [string[]]$Arguments,
        [int]$TimeoutMs = 8000
    )

    $executablePath = Resolve-CopilotExecutablePath
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        return @()
    }

    # Stdin is closed so nothing can wait for input, and a hung child is killed.
    $process = [System.Diagnostics.Process]::new()
    try {
        $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($executablePath)
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        foreach ($argument in @($Arguments)) {
            [void]$process.StartInfo.ArgumentList.Add($argument)
        }

        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutMs)) {
            try { $process.Kill($true) } catch { Write-Verbose "copilot did not exit in $TimeoutMs ms and could not be killed: $_" }
            return @()
        }

        $text = $stdout.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', ''
        @($text -split '\r?\n')
    } catch {
        @()
    } finally {
        $process.Dispose()
    }
}

function Test-CopilotCacheFresh {
    param(
        [nullable[datetime]]$LoadedAt,
        [int]$TtlSeconds
    )

    if ($null -eq $LoadedAt) {
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

    $script:CopilotCompletionCache.Models = @(Get-CopilotUniqueStrings -Items @($models.ToArray()))
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

    $script:CopilotCompletionCache.Marketplaces = @(Get-CopilotUniqueStrings -Items $names)
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

    $script:CopilotCompletionCache.InstalledPlugins = @(Get-CopilotUniqueStrings -Items $names)
    $script:CopilotCompletionCache.InstalledPluginsLoadedAt = Get-Date
    $script:CopilotCompletionCache.InstalledPlugins
}

function Get-CopilotConfigSchema {
    if (Test-CopilotCacheFresh -LoadedAt $script:CopilotCompletionCache.ConfigSchemaLoadedAt -TtlSeconds $script:CopilotCompletionCache.ModelCacheTtlSeconds) {
        return $script:CopilotCompletionCache.ConfigSchema
    }

    # The generated bash script carries copilot's own `config` key and value tables:
    #   *:read) cfg_values='allowedUrls askUser ...' ;;
    #   'user:theme') cfg_values='default github ...' cfg_path='' cfg_list='' ;;
    $schema = @{
        ReadKeys   = @()
        RemoveKeys = @{ user = @(); repo = @() }
        Keys       = @{}
    }

    foreach ($line in @(Invoke-CopilotCapture -Arguments @('completion', 'bash'))) {
        if ($line -match "^\s*(\*|user|repo):(read|remove)\)\s+cfg_values='([^']*)'") {
            $keys = @($matches[3] -split '\s+' | Where-Object { $_ })
            if ($matches[2] -eq 'read') {
                $schema.ReadKeys = $keys
            } elseif ($matches[1] -ne '*') {
                $schema.RemoveKeys[$matches[1]] = $keys
            }

            continue
        }

        if ($line -match "^\s*((?:'(?:user|repo):[^']+'\|?)+)\)\s+cfg_values='([^']*)'\s+cfg_path='([^']*)'\s+cfg_list='([^']*)'") {
            $entry = @{
                Values = @($matches[2] -split '\s+' | Where-Object { $_ })
                Path   = $matches[3]
                List   = $matches[4] -eq 'yes'
            }

            foreach ($keyMatch in [regex]::Matches($matches[1], "'(?:user|repo):([^']+)'")) {
                $schema.Keys[$keyMatch.Groups[1].Value] = $entry
            }
        }
    }

    $script:CopilotCompletionCache.ConfigSchema = $schema
    $script:CopilotCompletionCache.ConfigSchemaLoadedAt = Get-Date
    $schema
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
        New-CopilotOptionSpec -Tokens @('--additional-mcp-config') -Description 'Additional MCP config JSON or @file path.' -ValueKind 'JsonOrFile'
        New-CopilotOptionSpec -Tokens @('--agent') -Description 'Specify a custom agent to use.' -ValueKind 'AgentName'
        New-CopilotOptionSpec -Tokens @('--allow-all') -Description 'Enable all permissions.'
        New-CopilotOptionSpec -Tokens @('--allow-all-mcp-server-instructions') -Description 'Include initialization instructions from all MCP servers in the system prompt.'
        New-CopilotOptionSpec -Tokens @('--allow-all-paths') -Description 'Allow access to any file path.'
        New-CopilotOptionSpec -Tokens @('--allow-all-tools') -Description 'Allow all tools to run automatically.'
        New-CopilotOptionSpec -Tokens @('--allow-all-urls') -Description 'Allow access to all URLs without confirmation.'
        New-CopilotOptionSpec -Tokens @('--allow-tool') -Description 'Grant permission to a specific tool or tool pattern.' -ValueKind 'ToolPattern' -OptionalValue -Variadic
        New-CopilotOptionSpec -Tokens @('--allow-url') -Description 'Grant permission to a specific URL or domain.' -ValueKind 'UrlPattern' -OptionalValue -Variadic
        New-CopilotOptionSpec -Tokens @('--assisted-approval') -Description 'Review tool permission requests with the assisted-approval safety judge instead of approving them outright.'
        New-CopilotOptionSpec -Tokens @('--attachment') -Description 'Attach a file (image or native document) to the initial prompt.' -ValueKind 'FilePath'
        New-CopilotOptionSpec -Tokens @('--auto-tier') -Description 'Set the Auto routing profile.' -ValueKind 'AutoTier'
        New-CopilotOptionSpec -Tokens @('--autopilot') -Description 'Enable autopilot continuation in prompt mode.'
        New-CopilotOptionSpec -Tokens @('--available-tools') -Description 'Only these tools will be available to the model.' -ValueKind 'ToolPattern' -OptionalValue -Variadic
        New-CopilotOptionSpec -Tokens @('--banner') -Description 'Show the startup banner.'
        New-CopilotOptionSpec -Tokens @('--bash-env') -Description 'Enable BASH_ENV support for bash shells.' -ValueKind 'OnOff' -OptionalValue
        New-CopilotOptionSpec -Tokens @('-C') -Description 'Change working directory before doing anything else.' -ValueKind 'DirectoryPath'
        New-CopilotOptionSpec -Tokens @('--connect') -Description 'Connect directly to a remote session (optional session or task ID).' -ValueKind 'ResumeSession' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--context') -Description 'Set the context window tier.' -ValueKind 'ContextTier'
        New-CopilotOptionSpec -Tokens @('--continue') -Description 'Resume the most recent session.'
        New-CopilotOptionSpec -Tokens @('--deny-tool') -Description 'Deny a tool or tool pattern.' -ValueKind 'ToolPattern' -OptionalValue -Variadic
        New-CopilotOptionSpec -Tokens @('--deny-url') -Description 'Deny a URL or domain.' -ValueKind 'UrlPattern' -OptionalValue -Variadic
        New-CopilotOptionSpec -Tokens @('--disable-builtin-mcps') -Description 'Disable all built-in MCP servers.'
        New-CopilotOptionSpec -Tokens @('--disable-mcp-server') -Description 'Disable a specific MCP server.' -ValueKind 'ServerName'
        New-CopilotOptionSpec -Tokens @('--disallow-temp-dir') -Description 'Prevent automatic access to the system temp directory.'
        New-CopilotOptionSpec -Tokens @('--dynamic-retrieval') -Description 'Enable or disable embeddings-based dynamic retrieval per category (repeatable).' -ValueKind 'DynamicRetrieval'
        New-CopilotOptionSpec -Tokens @('--enable-all-github-mcp-tools') -Description 'Enable all GitHub MCP server tools.'
        New-CopilotOptionSpec -Tokens @('--enable-mcp-server') -Description 'Enable an MCP server disabled in settings for this run only (can be used multiple times).' -ValueKind 'ServerName'
        New-CopilotOptionSpec -Tokens @('--enable-memory') -Description 'Enable memory in prompt mode.'
        New-CopilotOptionSpec -Tokens @('--excluded-tools') -Description 'These tools will not be available to the model.' -ValueKind 'ToolPattern' -OptionalValue -Variadic
        New-CopilotOptionSpec -Tokens @('--experimental') -Description 'Enable experimental features.'
        New-CopilotOptionSpec -Tokens @('--extension-sdk-path') -Description 'Override the bundled @github/copilot-sdk with a local copilot-sdk/ folder.' -ValueKind 'DirectoryPath'
        New-CopilotOptionSpec -Tokens @('--fleet') -Description 'Run the prompt in fleet mode (parallel subagent orchestration).'
        New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Display help for command.'
        New-CopilotOptionSpec -Tokens @('-i', '--interactive') -Description 'Start interactive mode and execute this prompt.' -ValueKind 'PromptText'
        New-CopilotOptionSpec -Tokens @('--log-dir') -Description 'Set the log file directory.' -ValueKind 'DirectoryPath'
        New-CopilotOptionSpec -Tokens @('--log-level') -Description 'Set the log level.' -ValueKind 'LogLevel'
        New-CopilotOptionSpec -Tokens @('--max-ai-credits') -Description 'Set max AI credits for this session.' -ValueKind 'Count'
        New-CopilotOptionSpec -Tokens @('--max-autopilot-continues') -Description 'Maximum continuation count in autopilot mode.' -ValueKind 'Count'
        New-CopilotOptionSpec -Tokens @('--mcp-github-auth') -Description 'Send the GitHub credential only to this --additional-mcp-config server and origin (repeatable).' -ValueKind 'McpGithubAuth'
        New-CopilotOptionSpec -Tokens @('--mode') -Description 'Set the initial agent mode.' -ValueKind 'AgentMode'
        New-CopilotOptionSpec -Tokens @('--model') -Description 'Set the AI model to use.' -ValueKind 'Model'
        New-CopilotOptionSpec -Tokens @('--mouse') -Description 'Enable mouse support in alt screen mode.' -ValueKind 'OnOff' -OptionalValue
        New-CopilotOptionSpec -Tokens @('-n', '--name') -Description 'Set a name for the new session.' -ValueKind 'SessionName'
        New-CopilotOptionSpec -Tokens @('--no-ask-user') -Description 'Disable the ask_user tool.'
        New-CopilotOptionSpec -Tokens @('--no-auto-update') -Description 'Disable automatic update downloads.'
        New-CopilotOptionSpec -Tokens @('--no-bash-env') -Description 'Disable BASH_ENV support for bash shells.'
        New-CopilotOptionSpec -Tokens @('--no-color') -Description 'Disable all color output.'
        New-CopilotOptionSpec -Tokens @('--no-custom-instructions') -Description 'Disable loading custom instructions files.'
        New-CopilotOptionSpec -Tokens @('--no-eager-powershell-resolution') -Description 'Disable background PowerShell prompt resolution on Windows.'
        New-CopilotOptionSpec -Tokens @('--no-experimental') -Description 'Disable experimental features.'
        New-CopilotOptionSpec -Tokens @('--no-mouse') -Description 'Disable mouse support in alt screen mode.'
        New-CopilotOptionSpec -Tokens @('--no-remote') -Description 'Disable remote control of your session from GitHub web and mobile.'
        New-CopilotOptionSpec -Tokens @('--no-remote-export') -Description 'Disable exporting your session to GitHub web and mobile.'
        New-CopilotOptionSpec -Tokens @('--output-format') -Description 'Set output format.' -ValueKind 'OutputFormat'
        New-CopilotOptionSpec -Tokens @('-p', '--prompt') -Description 'Execute a prompt in non-interactive mode.' -ValueKind 'PromptText'
        New-CopilotOptionSpec -Tokens @('--plain-diff') -Description 'Disable rich diff rendering.'
        New-CopilotOptionSpec -Tokens @('--plan') -Description 'Start in plan mode.'
        New-CopilotOptionSpec -Tokens @('--plugin-dir') -Description 'Load a plugin from a local directory.' -ValueKind 'DirectoryPath'
        New-CopilotOptionSpec -Tokens @('-r', '--resume') -Description 'Resume from a previous session or task ID.' -ValueKind 'ResumeSession' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--remote') -Description 'Enable remote control of your session from GitHub web and mobile.'
        New-CopilotOptionSpec -Tokens @('--remote-export') -Description 'Export your session to GitHub web and mobile (read-only).'
        New-CopilotOptionSpec -Tokens @('-s', '--silent') -Description 'Output only the agent response.'
        New-CopilotOptionSpec -Tokens @('--screen-reader') -Description 'Enable screen reader optimizations.'
        New-CopilotOptionSpec -Tokens @('--secret-env-vars') -Description 'Strip and redact selected environment variable values.' -ValueKind 'EnvVarList' -OptionalValue -Variadic
        New-CopilotOptionSpec -Tokens @('--session-id') -Description 'Resume an existing session or task by ID, or set the UUID for a new session.' -ValueKind 'ResumeSession'
        New-CopilotOptionSpec -Tokens @('--share') -Description 'Share session to a markdown file after completion.' -ValueKind 'SharePath' -OptionalValue
        New-CopilotOptionSpec -Tokens @('--share-gist') -Description 'Share session to a secret GitHub gist after completion.'
        New-CopilotOptionSpec -Tokens @('--stream') -Description 'Enable or disable streaming mode.' -ValueKind 'OnOff'
        New-CopilotOptionSpec -Tokens @('--usage-output-file') -Description 'Write final usage statistics as JSON to the specified file.' -ValueKind 'FilePath'
        New-CopilotOptionSpec -Tokens @('-v', '--version') -Description 'Show version information.'
        New-CopilotOptionSpec -Tokens @('--yolo') -Description 'Enable all permissions.'
    )

    # copilot 1.0.92 is a clap CLI: root options are accepted only before the first
    # subcommand, so every path below lists just the options its own --help prints.
    # Aliases are hidden spellings copilot accepts; they resolve to the canonical
    # command while parsing but are never offered.
    $helpOnly = @(New-CopilotOptionSpec -Tokens @('-h', '--help') -Description 'Print help.')
    $jsonAndHelp = @(
        New-CopilotOptionSpec -Tokens @('--json') -Description 'Output as JSON.'
        $helpOnly
    )

    $script:CopilotCompletionCache.CommandSpecs = @{
        ''                          = @{
            Commands    = [ordered]@{
                'app'         = 'Open the GitHub Copilot app.'
                'completion'  = 'Generate a shell completion script.'
                'config'      = 'Manage configuration settings.'
                'help'        = 'Display help information.'
                'init'        = 'Initialize Copilot instructions.'
                'instruction' = 'Inspect instruction sources.'
                'login'       = 'Authenticate with Copilot.'
                'lsp'         = 'Inspect language server configuration.'
                'mcp'         = 'Manage MCP servers.'
                'memories'    = 'Manage memories.'
                'plugin'      = 'Manage plugins.'
                'sandbox'     = 'Manage command sandboxing.'
                'sessions'    = 'Manage saved sessions.'
                'skill'       = 'Manage skills.'
                'update'      = 'Download the latest version.'
                'version'     = 'Display version information.'
                'workflow'    = 'Run dynamic workflows.'
            }
            Aliases     = @{ 'plugins' = 'plugin' }
            Options     = @()
            Positionals = @()
        }
        'app'                       = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @() }
        'completion'                = @{
            Commands    = [ordered]@{}
            Options     = $helpOnly
            Positionals = @(@{ Name = 'shell'; ValueKind = 'CompletionShell'; Description = 'Target shell.' })
        }
        'config'                    = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('--list') -Description 'List settings as key=value lines.'
                New-CopilotOptionSpec -Tokens @('--rm') -Description 'Remove the key, or only the given item from a list.'
                New-CopilotOptionSpec -Tokens @('--json') -Description 'Output --list as JSON.'
                New-CopilotOptionSpec -Tokens @('--global') -Description 'Use your user settings file (the default).'
                New-CopilotOptionSpec -Tokens @('--repo') -Description 'Use the repository''s .github/copilot/settings.json.'
                New-CopilotOptionSpec -Tokens @('--local') -Description 'Use the repository''s .github/copilot/settings.local.json.'
                $helpOnly
            )
            Positionals = @(
                @{ Name = 'key'; ValueKind = 'ConfigKey'; Description = 'Setting key in dot notation.' }
                @{ Name = 'value'; ValueKind = 'ConfigValue'; Description = 'Value to set, append, or remove from a list with --rm.' }
            )
        }
        'help'                      = @{
            Commands    = [ordered]@{}
            Options     = $helpOnly
            Positionals = @(@{ Name = 'topic'; ValueKind = 'HelpTopic'; Description = 'Help topic.' })
        }
        'init'                      = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('--no-experimental') -Description 'Disable experimental features.'
                New-CopilotOptionSpec -Tokens @('--no-eager-powershell-resolution') -Description 'Disable background PowerShell prompt resolution on Windows.'
                $helpOnly
            )
            Positionals = @()
        }
        'instruction'               = @{ Commands = [ordered]@{ 'list' = 'List discovered instruction sources.' }; Options = $helpOnly; Positionals = @() }
        'instruction list'          = @{ Commands = [ordered]@{}; Options = $jsonAndHelp; Positionals = @() }
        'login'                     = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('--host') -Description 'GitHub host URL.' -ValueKind 'Host'
                New-CopilotOptionSpec -Tokens @('--device-code') -Description 'Authenticate using the OAuth device code flow.'
                New-CopilotOptionSpec -Tokens @('--web-flow') -Description 'Authenticate using the browser (web) flow.'
                New-CopilotOptionSpec -Tokens @('--with-token') -Description 'Read an authentication token from standard input.'
                $helpOnly
            )
            Positionals = @()
        }
        'lsp'                       = @{ Commands = [ordered]@{ 'list' = 'List configured language servers.' }; Options = $helpOnly; Positionals = @() }
        'lsp list'                  = @{ Commands = [ordered]@{}; Options = $jsonAndHelp; Positionals = @() }
        'mcp'                       = @{
            Commands    = [ordered]@{
                'add'     = 'Add an MCP server.'
                'disable' = 'Disable an MCP server.'
                'enable'  = 'Enable an MCP server.'
                'get'     = 'Show server details.'
                'list'    = 'List configured MCP servers.'
                'remove'  = 'Remove an MCP server.'
            }
            Options     = $helpOnly
            Positionals = @()
        }
        'mcp add'                   = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('--transport') -Description 'Server transport.' -ValueKind 'McpTransport'
                New-CopilotOptionSpec -Tokens @('--env') -Description 'Environment variable (KEY=VALUE, can be repeated).' -ValueKind 'EnvAssignment'
                New-CopilotOptionSpec -Tokens @('--header') -Description 'HTTP header for remote servers, can be repeated.' -ValueKind 'HttpHeader'
                New-CopilotOptionSpec -Tokens @('--tools') -Description 'Tool filter: "*" for all, comma-separated list, or "" for none.' -ValueKind 'ToolPattern'
                New-CopilotOptionSpec -Tokens @('--timeout') -Description 'Timeout in milliseconds.' -ValueKind 'Count'
                New-CopilotOptionSpec -Tokens @('--json') -Description 'Output added config as JSON.'
                New-CopilotOptionSpec -Tokens @('--show-secrets') -Description 'Show full environment variable and header values in output.'
                $helpOnly
            )
            Positionals = @(@{ Name = 'name'; ValueKind = 'ServerName'; Description = 'Server name.' })
        }
        'mcp disable'               = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'name'; ValueKind = 'ServerName'; Description = 'MCP server name.' }) }
        'mcp enable'                = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'name'; ValueKind = 'ServerName'; Description = 'MCP server name.' }) }
        'mcp get'                   = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('--json') -Description 'Output as JSON.'
                New-CopilotOptionSpec -Tokens @('--show-secrets') -Description 'Show full environment variable and header values.'
                $helpOnly
            )
            Positionals = @(@{ Name = 'name'; ValueKind = 'ServerName'; Description = 'Server name.' })
        }
        'mcp list'                  = @{ Commands = [ordered]@{}; Options = $jsonAndHelp; Positionals = @() }
        'mcp remove'                = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'name'; ValueKind = 'ServerName'; Description = 'Server name.' }) }
        'memories'                  = @{ Commands = [ordered]@{ 'import' = 'Import semantic memories through the native memory service.' }; Options = $helpOnly; Positionals = @() }
        'memories import'           = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('--dry-run') -Description 'Validate without submitting memories.'
                New-CopilotOptionSpec -Tokens @('--output') -Description 'Output format.' -ValueKind 'ImportOutput'
                New-CopilotOptionSpec -Tokens @('--on-conflict') -Description 'Conflict behavior (default: error).' -ValueKind 'OnConflict'
                $helpOnly
            )
            Positionals = @(@{ Name = 'memories.jsonl'; ValueKind = 'FilePath'; Description = 'Semantic memory JSONL file.' })
        }
        'plugin'                    = @{
            Commands    = [ordered]@{
                'disable'     = 'Disable a plugin.'
                'enable'      = 'Enable a plugin.'
                'install'     = 'Install a plugin.'
                'list'        = 'List installed and --plugin-dir plugins.'
                'marketplace' = 'Manage plugin marketplaces.'
                'uninstall'   = 'Uninstall a plugin.'
                'update'      = 'Update a plugin.'
            }
            Aliases     = @{ 'add' = 'install'; 'remove' = 'uninstall'; 'rm' = 'uninstall'; 'marketplaces' = 'marketplace' }
            Options     = $helpOnly
            Positionals = @()
        }
        'plugin disable'            = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'name'; ValueKind = 'InstalledPlugin'; Description = 'Plugin name, name@marketplace, or direct-install source id.' }) }
        'plugin enable'             = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'name'; ValueKind = 'InstalledPlugin'; Description = 'Plugin name, name@marketplace, or direct-install source id.' }) }
        'plugin install'            = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'source'; ValueKind = 'PluginSource'; Description = 'Plugin source: plugin@marketplace, owner/repo, owner/repo:path, or URL.' }) }
        'plugin list'               = @{ Commands = [ordered]@{}; Options = $jsonAndHelp; Positionals = @() }
        'plugin uninstall'          = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'name'; ValueKind = 'InstalledPlugin'; Description = 'Plugin name (plugin-name or plugin-name@marketplace-name).' }) }
        'plugin update'             = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('--all') -Description 'Update all installed plugins.'
                $helpOnly
            )
            Positionals = @(@{ Name = 'name'; ValueKind = 'InstalledPlugin'; Description = 'Plugin name (plugin-name@marketplace-name).' })
        }
        'plugin marketplace'        = @{
            Commands    = [ordered]@{
                'add'    = 'Add a marketplace.'
                'browse' = 'Browse plugins in a marketplace.'
                'list'   = 'List registered marketplaces.'
                'remove' = 'Remove a marketplace.'
                'update' = 'Update marketplace plugin catalogs.'
            }
            Aliases     = @{ 'ls' = 'list'; 'rm' = 'remove'; 'refresh' = 'update' }
            Options     = $helpOnly
            Positionals = @()
        }
        'plugin marketplace add'    = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'source'; ValueKind = 'MarketplaceSource'; Description = 'Marketplace source: owner/repo, URL, or local path.' }) }
        'plugin marketplace browse' = @{ Commands = [ordered]@{}; Options = $jsonAndHelp; Positionals = @(@{ Name = 'name'; ValueKind = 'MarketplaceName'; Description = 'Marketplace name.' }) }
        'plugin marketplace list'   = @{ Commands = [ordered]@{}; Options = $jsonAndHelp; Positionals = @() }
        'plugin marketplace remove' = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('-f', '--force') -Description 'Force removal even if plugins are installed.'
                $helpOnly
            )
            Positionals = @(@{ Name = 'name'; ValueKind = 'MarketplaceName'; Description = 'Marketplace name.' })
        }
        'plugin marketplace update' = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'name'; ValueKind = 'MarketplaceName'; Description = 'Marketplace name (omit to update all).' }) }
        'sandbox'                   = @{ Commands = [ordered]@{ 'ca' = 'Manage the credential proxy certificate authority.' }; Options = $helpOnly; Positionals = @() }
        'sandbox ca'                = @{
            Commands    = [ordered]@{
                'create' = 'Create the certificate authority without trusting it.'
                'remove' = 'Remove the certificate authority from OS trust.'
                'rotate' = 'Replace the certificate authority.'
                'status' = 'Show whether the OS trusts the certificate authority.'
                'trust'  = 'Add the certificate authority to OS trust.'
            }
            Options     = $helpOnly
            Positionals = @()
        }
        'sandbox ca create'         = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @() }
        'sandbox ca remove'         = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @() }
        'sandbox ca rotate'         = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @() }
        'sandbox ca status'         = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @() }
        'sandbox ca trust'          = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('--allow-host') -Description 'Also allow a host the certificate may be constrained to (can be used multiple times).' -ValueKind 'HostName'
                $helpOnly
            )
            Positionals = @(@{ Name = 'certificate'; ValueKind = 'FilePath'; Description = 'Certificate file that `copilot sandbox ca create` printed.' })
        }
        'sessions'                  = @{ Commands = [ordered]@{ 'import' = 'Import a semantic session from JSONL.' }; Options = $helpOnly; Positionals = @() }
        'sessions import'           = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('--dry-run') -Description 'Validate without writing a session.'
                New-CopilotOptionSpec -Tokens @('--output') -Description 'Output format.' -ValueKind 'ImportOutput'
                New-CopilotOptionSpec -Tokens @('--working-directory') -Description 'Override the imported working directory.' -ValueKind 'DirectoryPath'
                New-CopilotOptionSpec -Tokens @('--name') -Description 'Override the imported session name.' -ValueKind 'SessionName'
                $helpOnly
            )
            Positionals = @(@{ Name = 'transcript.jsonl'; ValueKind = 'FilePath'; Description = 'Semantic session JSONL file.' })
        }
        'skill'                     = @{
            Commands    = [ordered]@{
                'add'     = 'Add a skill from a file, URL, or directory.'
                'disable' = 'Disable a skill.'
                'enable'  = 'Enable a skill.'
                'list'    = 'List available skills.'
                'remove'  = 'Remove a skill or custom skill directory.'
            }
            Options     = $helpOnly
            Positionals = @()
        }
        'skill add'                 = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('--project') -Description 'Install the skill into the project''s .github/skills directory.'
                $helpOnly
            )
            Positionals = @(@{ Name = 'source'; ValueKind = 'SkillSource'; Description = 'Skill source (file path, URL, or directory).' })
        }
        'skill disable'             = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'name'; ValueKind = 'SkillName'; Description = 'Skill name.' }) }
        'skill enable'              = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'name'; ValueKind = 'SkillName'; Description = 'Skill name.' }) }
        'skill list'                = @{ Commands = [ordered]@{}; Options = $jsonAndHelp; Positionals = @() }
        'skill remove'              = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @(@{ Name = 'name-or-directory'; ValueKind = 'SkillSource'; Description = 'Skill name or custom skill directory.' }) }
        'update'                    = @{
            Commands    = [ordered]@{}
            Options     = $helpOnly
            Positionals = @(@{ Name = 'channel'; ValueKind = 'UpdateChannel'; Description = 'Update channel.' })
        }
        'version'                   = @{ Commands = [ordered]@{}; Options = $helpOnly; Positionals = @() }
        'workflow'                  = @{ Commands = [ordered]@{ 'run' = 'Run a registered dynamic workflow.' }; Options = $helpOnly; Positionals = @() }
        'workflow run'              = @{
            Commands    = [ordered]@{}
            Options     = @(
                New-CopilotOptionSpec -Tokens @('--args') -Description 'Workflow arguments as inline JSON or an @-prefixed JSON file.' -ValueKind 'JsonOrFile'
                New-CopilotOptionSpec -Tokens @('--result-file') -Description 'Write only the workflow result to this JSON file.' -ValueKind 'FilePath'
                New-CopilotOptionSpec -Tokens @('-s', '--silent') -Description 'Suppress workflow progress output.'
                New-CopilotOptionSpec -Tokens @('--output-format') -Description 'Output format.' -ValueKind 'OutputFormat'
                $helpOnly
            )
            Positionals = @(@{ Name = 'name'; ValueKind = 'WorkflowName'; Description = 'Registered dynamic workflow name.' })
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

    # An unknown non-empty path must not inherit the root commands.
    @{
        Commands    = [ordered]@{}
        Options     = @()
        Positionals = @()
    }
}

function Get-CopilotOptionsForPath {
    param([string[]]$Path)

    Initialize-CopilotStaticMetadata

    # Root options are not global: copilot rejects them after a subcommand
    # ("error: unexpected argument '--model' found").
    if (@($Path).Count -eq 0) {
        return $script:CopilotCompletionCache.GlobalOptions
    }

    @((Get-CopilotCommandSpec -Path $Path).Options)
}

function Resolve-CopilotCommandName {
    param(
        [string]$Token,
        [string[]]$Path
    )

    $spec = Get-CopilotCommandSpec -Path $Path
    foreach ($commandName in $spec.Commands.Keys) {
        if ($commandName.Equals($Token, [System.StringComparison]::Ordinal)) {
            return $commandName
        }
    }

    if ($spec.ContainsKey('Aliases') -and $spec.Aliases.ContainsKey($Token)) {
        return $spec.Aliases[$Token]
    }

    $null
}

function Find-CopilotExactOptionSpec {
    param(
        [string]$Token,
        [string[]]$Path
    )

    foreach ($option in @(Get-CopilotOptionsForPath -Path $Path)) {
        if ($option.Token.Equals($Token, [System.StringComparison]::Ordinal)) {
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
        if ($Token.StartsWith($option.Token + '=', [System.StringComparison]::Ordinal)) {
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

    # Normalise before splitting: a trailing separator, '.', '..' and '~' all
    # name the parent directory; Split-Path would resolve '.\' to the cwd name.
    if ($cleanInput -eq '~' -or $cleanInput.StartsWith('~\') -or $cleanInput.StartsWith('~/')) {
        $cleanInput = $HOME + $cleanInput.Substring(1)
    }

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput.EndsWith('\') -or $cleanInput.EndsWith('/') -or $cleanInput -eq '.' -or $cleanInput -eq '..') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = [System.IO.Path]::GetDirectoryName($cleanInput)
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = [System.IO.Path]::GetFileName($cleanInput)
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore |
        Where-Object { [string]::IsNullOrEmpty($leaf) -or $_.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase) })
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
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    # $CurrentValue is the raw typed value; the '--option=' prefix is applied here so the
    # emptiness test still sees an empty value in the attached form.
    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-CopilotCompletionResult -CompletionText ($Prefix + $Placeholder) -ToolTip $ToolTip -ListItemText $Placeholder
        )
    }

    @(
        New-CopilotCompletionResult -CompletionText ($Prefix + $CurrentValue) -ToolTip $ToolTip -ListItemText $CurrentValue
    )
}

function Get-CopilotValueResults {
    param(
        [string]$ValueKind,
        [string]$CurrentValue,
        [string]$Prefix = '',
        [hashtable]$State
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }

    switch ($ValueKind) {
        'ConfigKey' {
            $seen = if ($State) { @($State.SeenOptions) } else { @() }
            if ($seen -contains '--list') {
                return @()
            }

            $schema = Get-CopilotConfigSchema
            $keys = if ($seen -contains '--rm') {
                $schema.RemoveKeys[$(if ($seen -contains '--repo' -or $seen -contains '--local') { 'repo' } else { 'user' })]
            } else {
                $schema.ReadKeys
            }

            if (@($keys).Count -eq 0) {
                return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder '<key>' -ToolTip 'Setting key in dot notation (see `copilot help config`).'
            }

            return @($keys) |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Copilot setting key.' }
        }
        'ConfigValue' {
            $seen = if ($State) { @($State.SeenOptions) } else { @() }
            $key = if ($State -and @($State.PositionalValues).Count -gt 0) { @($State.PositionalValues)[0] } else { '' }
            $entry = (Get-CopilotConfigSchema).Keys[$key]
            if ($seen -contains '--list' -or ($seen -contains '--rm' -and -not ($entry -and $entry.List))) {
                return @()
            }

            if ($entry -and @($entry.Values).Count -gt 0) {
                return @($entry.Values) |
                    Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                    ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip "Value for $key." }
            }

            if ($entry -and $entry.Path -eq 'directory') {
                return Get-CopilotValueResults -ValueKind 'DirectoryPath' -CurrentValue $typedValue -Prefix $Prefix
            }

            if ($entry -and $entry.Path -eq 'file') {
                return Get-CopilotValueResults -ValueKind 'FilePath' -CurrentValue $typedValue -Prefix $Prefix
            }

            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder '<value>' -ToolTip 'Setting value (put -- before a value that starts with -).'
        }
        'AutoTier' {
            return @('efficiency', 'balance', 'intelligence') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Auto routing profile.' }
        }
        'DynamicRetrieval' {
            return @('skills=on', 'skills=off') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Dynamic retrieval category=on|off.' }
        }
        'ImportOutput' {
            return @('json') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Import output format.' }
        }
        'OnConflict' {
            return @('skip', 'error') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Memory import conflict behavior.' }
        }
        'McpGithubAuth' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder '<server>=<origin>' -ToolTip 'An --additional-mcp-config server and the approved HTTPS origin.'
        }
        'WorkflowName' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder '<workflow>' -ToolTip 'Registered dynamic workflow name.'
        }
        'SkillName' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder '<skill-name>' -ToolTip 'Skill name.'
        }
        'HostName' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder '<host>' -ToolTip 'Credential host the certificate may be constrained to.'
        }
        'Model' {
            # 'auto' lets Copilot pick the model and is documented on --model but never listed
            # by 'copilot help config', so it leads the discovered ids.
            $models = @('auto') + @(Get-CopilotModels)
            if ($models.Count -eq 1) {
                $models += '<model>'
            }

            return $models |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object {
                    New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Model name (auto lets Copilot pick; others discovered from `copilot help config`).' -ListItemText $_
                }
        }
        'ReasoningEffort' {
            return @('none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Reasoning effort level.' }
        }
        'OutputFormat' {
            return @('text', 'json') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Output format.' }
        }
        'OnOff' {
            return @('on', 'off') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Boolean on/off value.' }
        }
        'LogLevel' {
            return @('none', 'error', 'warning', 'info', 'debug', 'all', 'default') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'CLI log level.' }
        }
        'DirectoryPath' {
            # A directory with no subdirectories must still yield something, or PowerShell's
            # filename fallback offers files in a directory-only slot.
            $paths = @(Get-CopilotPathCompletions -InputPath $typedValue -Prefix $Prefix -DirectoriesOnly)
            if ($paths.Count -eq 0) {
                return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder '<directory>' -ToolTip 'Directory path.'
            }

            return $paths
        }
        'FilePath' {
            $paths = @(Get-CopilotPathCompletions -InputPath $typedValue -Prefix $Prefix)
            if ($paths.Count -eq 0) {
                return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder '<file>' -ToolTip 'File path.'
            }

            return $paths
        }
        'CompletionShell' {
            return @('bash', 'zsh', 'fish') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Target shell for the completion script.' }
        }
        'UpdateChannel' {
            return @('stable', 'prerelease') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Update channel.' }
        }
        'McpTransport' {
            return @('stdio', 'http', 'sse') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'MCP server transport.' }
        }
        'AgentMode' {
            return @('interactive', 'plan', 'autopilot') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Initial agent mode.' }
        }
        'ContextTier' {
            return @('default', 'long_context') |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Context window tier.' }
        }
        'SkillSource' {
            if (Test-CopilotLooksLikePath -Token $typedValue) {
                return @(Get-CopilotPathCompletions -InputPath $typedValue -Prefix $Prefix)
            }

            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('<skill-name-or-path>') -ToolTip 'Skill name, SKILL.md path, URL, or skill directory.'
        }
        'SessionName' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('"<session name>"') -ToolTip 'Display name for the new session.'
        }
        'EnvAssignment' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('KEY=VALUE') -ToolTip 'Environment variable assignment.'
        }
        'HttpHeader' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('"Name: value"') -ToolTip 'HTTP header for remote servers.'
        }
        'SharePath' {
            $results = New-Object System.Collections.Generic.List[object]
            foreach ($result in @(Get-CopilotPathCompletions -InputPath $typedValue -Prefix $Prefix)) {
                [void]$results.Add($result)
            }

            if ($results.Count -eq 0 -or [string]::IsNullOrWhiteSpace($typedValue)) {
                [void]$results.Add((New-CopilotCompletionResult -CompletionText ($Prefix + '.\copilot-session-<id>.md') -ToolTip 'Default markdown share path pattern.' -ListItemText '.\copilot-session-<id>.md'))
            }

            return @($results.ToArray())
        }
        'JsonOrFile' {
            if ($typedValue.StartsWith('@')) {
                return @(Get-CopilotPathCompletions -InputPath $typedValue.Substring(1) -Prefix ($Prefix + '@'))
            }

            $results = New-Object System.Collections.Generic.List[object]
            if ([string]::IsNullOrWhiteSpace($typedValue) -or '@' -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*')) {
                [void]$results.Add((New-CopilotCompletionResult -CompletionText ($Prefix + '@') -ToolTip 'Prefix a file path with @ to load JSON from disk.'))
            }

            foreach ($result in @(New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder '<json-or-@file>' -ToolTip 'Inline JSON string or @file path.')) {
                [void]$results.Add($result)
            }

            return @($results.ToArray())
        }
        'HelpTopic' {
            return $script:CopilotCompletionCache.HelpTopics |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Copilot help topic.' }
        }
        'InstalledPlugin' {
            $plugins = @(Get-CopilotInstalledPluginNames)
            if ($plugins.Count -eq 0) {
                return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder '<plugin-name>' -ToolTip 'Installed plugin name.'
            }

            return $plugins |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                ForEach-Object { New-CopilotCompletionResult -CompletionText ($Prefix + $_) -ToolTip 'Installed plugin.' }
        }
        'MarketplaceName' {
            $marketplaces = @(Get-CopilotMarketplaceNames)
            if ($marketplaces.Count -eq 0) {
                return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder '<marketplace-name>' -ToolTip 'Registered marketplace name.'
            }

            return $marketplaces |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
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

            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('https://example.ghe.com') -ToolTip 'GitHub host URL.'
        }
        'ResumeSession' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('<session-id>') -ToolTip 'Session ID or task ID.'
        }
        'AgentName' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('<agent>') -ToolTip 'Custom agent name.'
        }
        'PromptText' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('"<prompt>"') -ToolTip 'Prompt text.'
        }
        'ToolPattern' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('shell(git:*)') -ToolTip 'Tool name or permission pattern.'
        }
        'UrlPattern' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('github.com') -ToolTip 'URL, domain, or wildcard domain.'
        }
        'ServerName' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('<server-name>') -ToolTip 'MCP server name.'
        }
        'EnvVarList' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('MY_KEY,OTHER_KEY') -ToolTip 'Comma-separated environment variable names.'
        }
        'GithubMcpTool' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('*') -ToolTip 'GitHub MCP tool name or "*".'
        }
        'GithubMcpToolset' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('all') -ToolTip 'GitHub MCP toolset name or "all".'
        }
        'Count' {
            return New-CopilotLiteralValueResults -CurrentValue $typedValue -Prefix $Prefix -Placeholder ('<count>') -ToolTip 'Numeric count.'
        }
        default {
            return @()
        }
    }
}

function Resolve-CopilotParseState {
    param([string[]]$Tokens)

    $state = @{
        Path             = @()
        PendingOption    = $null
        PendingValues    = 0
        PositionalValues = @()
        SeenOptions      = @()
        EndOfOptions     = $false
        UnknownCommand   = $false
    }

    $index = 0
    while ($index -lt @($Tokens).Count) {
        $token = $Tokens[$index]

        if ($state.PendingOption) {
            # Like clap, an optional value takes the next word unless it is an option,
            # even a command name ('--resume mcp list' resumes session "mcp"). A variadic
            # value ('--allow-tool a b mcp') keeps taking words until the next option.
            if ($state.PendingOption.OptionalValue -and (Test-CopilotLooksLikeOption -Token $token)) {
                $state.PendingOption = $null
                continue
            }

            $index++
            $state.PendingValues++
            if (-not $state.PendingOption.Variadic) {
                $state.PendingOption = $null
            }

            continue
        }

        $index++

        # After '--' every token is an operand (config values that start with '-',
        # the command line given to 'mcp add').
        if ($state.EndOfOptions) {
            $state.PositionalValues = @($state.PositionalValues + $token)
            continue
        }

        if ($token -eq '--') {
            $state.EndOfOptions = $true
            continue
        }

        $inlineOption = Find-CopilotInlineOptionSpec -Token $token -Path $state.Path
        if ($inlineOption) {
            $state.SeenOptions = @($state.SeenOptions + $inlineOption.Token)
            continue
        }

        $exactOption = Find-CopilotExactOptionSpec -Token $token -Path $state.Path
        if ($exactOption) {
            $state.SeenOptions = @($state.SeenOptions + $exactOption.Token)
            if (-not [string]::IsNullOrWhiteSpace($exactOption.ValueKind)) {
                $state.PendingOption = $exactOption
                $state.PendingValues = 0
            }

            continue
        }

        # An option this path does not know is not an operand; skip it.
        if (Test-CopilotLooksLikeOption -Token $token) {
            continue
        }

        $commandName = Resolve-CopilotCommandName -Token $token -Path $state.Path
        if ($commandName) {
            $state.Path = @($state.Path + $commandName)
            $state.PositionalValues = @()
            $state.SeenOptions = @()
            continue
        }

        # A word that is neither a command nor an operand of a command-only path is
        # an unknown command; nothing after it can be completed.
        $spec = Get-CopilotCommandSpec -Path $state.Path
        if ($spec.Commands.Count -gt 0 -and @($spec.Positionals).Count -eq 0) {
            $state.UnknownCommand = $true
            break
        }

        $state.PositionalValues = @($state.PositionalValues + $token)
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

    # Select tokens by extent (offsets are line-absolute, like $CursorPosition):
    # committed tokens end before the cursor, the current word contains it, and
    # anything to the right of the cursor is ignored.
    $elements = @($CommandAst.CommandElements | Select-Object -Skip 1)
    $tokensBeforeCurrent = @(
        $elements |
            Where-Object { $_.Extent.EndOffset -lt $CursorPosition } |
            ForEach-Object { Get-CopilotTokenText -Element $_ }
    )
    $currentElement = $elements |
        Where-Object { $_.Extent.StartOffset -lt $CursorPosition -and $_.Extent.EndOffset -ge $CursorPosition } |
        Select-Object -First 1

    $currentWord = if ($null -eq $currentElement) {
        ''
    } elseif (-not [string]::IsNullOrEmpty($WordToComplete)) {
        $WordToComplete
    } else {
        Get-CopilotTokenText -Element $currentElement
    }

    $state = Resolve-CopilotParseState -Tokens $tokensBeforeCurrent
    if ($state.UnknownCommand) {
        return
    }

    $spec = Get-CopilotCommandSpec -Path $state.Path

    if (-not $state.EndOfOptions) {
        $inlineOption = $null
        if (-not [string]::IsNullOrWhiteSpace($currentWord)) {
            $inlineOption = Find-CopilotInlineOptionSpec -Token $currentWord -Path $state.Path
        }

        if ($inlineOption) {
            $prefix = $inlineOption.Token + '='
            $typedValue = $currentWord.Substring($prefix.Length)
            return @(Get-CopilotValueResults -ValueKind $inlineOption.ValueKind -CurrentValue $typedValue -Prefix $prefix -State $state)
        }

        # An optional or variadic value ends at the next option, so a dash word there
        # completes options instead.
        if ($state.PendingOption -and -not ($state.PendingOption.OptionalValue -and $currentWord.StartsWith('-'))) {
            $valueResults = @(Get-CopilotValueResults -ValueKind $state.PendingOption.ValueKind -CurrentValue $currentWord -State $state)
            if (-not ($state.PendingOption.Variadic -and $state.PendingValues -gt 0 -and [string]::IsNullOrEmpty($currentWord))) {
                return $valueResults
            }

            # A variadic list that already has a value may also end here; commands are
            # not offered because copilot would take them as further values.
            return @(
                $valueResults
                Get-CopilotOptionsForPath -Path $state.Path |
                    ForEach-Object { New-CopilotCompletionResult -CompletionText $_.Token -ResultType 'ParameterName' -ToolTip $_.Description }
            )
        }

        if ($currentWord.StartsWith('-')) {
            $optionResults = @(
                Get-CopilotOptionsForPath -Path $state.Path |
                    Where-Object { $_.Token -clike ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*') } |
                    ForEach-Object {
                        New-CopilotCompletionResult -CompletionText $_.Token -ResultType 'ParameterName' -ToolTip $_.Description
                    }
            )

            # A combined short-flag cluster ('-sp') matches no single token; offer the option list
            # rather than nothing so the slot does not fall back to filenames.
            if ($optionResults.Count -eq 0 -and $currentWord -match '^-[A-Za-z]{2,}$') {
                $optionResults = @(
                    Get-CopilotOptionsForPath -Path $state.Path |
                        ForEach-Object {
                            New-CopilotCompletionResult -CompletionText $_.Token -ResultType 'ParameterName' -ToolTip $_.Description
                        }
                )
            }

            return $optionResults
        }
    }

    $results = New-Object System.Collections.Generic.List[object]

    $positionalIndex = @($state.PositionalValues).Count
    if ($positionalIndex -lt @($spec.Positionals).Count) {
        $positional = $spec.Positionals[$positionalIndex]
        foreach ($result in @(Get-CopilotValueResults -ValueKind $positional.ValueKind -CurrentValue $currentWord -State $state)) {
            [void]$results.Add($result)
        }
    }

    if (-not $state.EndOfOptions) {
        foreach ($commandName in $spec.Commands.Keys) {
            if ($commandName -clike ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*')) {
                [void]$results.Add((New-CopilotCompletionResult -CompletionText $commandName -ToolTip $spec.Commands[$commandName]))
            }
        }

        if ([string]::IsNullOrEmpty($currentWord)) {
            foreach ($option in @(Get-CopilotOptionsForPath -Path $state.Path)) {
                [void]$results.Add((New-CopilotCompletionResult -CompletionText $option.Token -ResultType 'ParameterName' -ToolTip $option.Description))
            }
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
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
