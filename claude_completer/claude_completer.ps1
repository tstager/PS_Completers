<#
.SYNOPSIS
    Argument completer for claude / claude.exe (Claude Code CLI).
.DESCRIPTION
    Provides tab completion for claude subcommands, flags, flag values, and the
    --flag=value inline syntax.  Dot-source this file from your $PROFILE to
    enable completion for both invocation forms.

    Safe to source multiple times (idempotent registration via script-scoped guard).
.EXAMPLE
    . "$PSScriptRoot\claude_completer.ps1"
#>

Set-StrictMode -Version Latest

function Initialize-ClaudeCompleterData {
    if (Get-Variable -Name ClaudeTopCommands -Scope Script -ErrorAction SilentlyContinue) {
        return
    }

    # Top-level subcommands.
    $script:ClaudeTopCommands = @(
        'agents', 'auth', 'auto-mode', 'doctor', 'install', 'mcp',
        'plugin', 'project', 'setup-token', 'ultrareview', 'update'
    )

    # Command alias normalisation (alias -> canonical) applied when walking args.
    # Top-level: plugins == plugin, upgrade == update.
    $script:ClaudeCmdAliases = @{
        'plugins' = 'plugin'
        'upgrade' = 'update'
    }

    # Level-2 subcommand aliases keyed by "cmd": alias -> canonical.
    $script:ClaudeSubAliases = @{
        'plugin' = @{
            'i'          = 'install'
            'remove'     = 'uninstall'
            'autoremove' = 'prune'
        }
    }

    # Level-3 subcommand aliases keyed by "cmd.subcmd": alias -> canonical.
    $script:ClaudeL3Aliases = @{
        'plugin.marketplace' = @{
            'rm' = 'remove'
        }
    }

    # Level-2 subcommands per top-level command.
    $script:ClaudeSubSubcommands = @{
        'auth'      = @('login', 'logout', 'status', 'help')
        'auto-mode' = @('config', 'critique', 'defaults', 'help')
        'mcp'       = @('add', 'add-json', 'add-from-claude-desktop', 'get',
                         'list', 'remove', 'reset-project-choices', 'serve', 'help')
        'plugin'    = @('details', 'disable', 'enable', 'install', 'list',
                         'marketplace', 'prune', 'tag', 'uninstall', 'update', 'help')
        'project'   = @('purge', 'help')
        # Commands with no L2 subcommands (own options or positionals only).
        'agents'      = @()
        'doctor'      = @()
        'install'     = @()
        'setup-token' = @()
        'ultrareview' = @()
        'update'      = @()
    }

    # Level-3 subcommands: "cmd.subcmd" -> @(subsubcmds).
    $script:ClaudeL3Subcommands = @{
        'plugin.marketplace' = @('add', 'list', 'remove', 'update', 'help')
    }

    # ---- Flag categories -----------------------------------------------------------------------

    # Global enum flags with fixed choice sets.
    $script:ClaudeEnumFlags = @{
        '--effort'             = @('low', 'medium', 'high', 'xhigh', 'max')
        '--permission-mode'    = @('acceptEdits', 'auto', 'bypassPermissions',
                                    'default', 'dontAsk', 'plan')
        '--output-format'      = @('text', 'json', 'stream-json')
        '--input-format'       = @('text', 'stream-json')
        '--prompt-suggestions' = @('true', 'false', '1', '0', 'yes', 'no', 'on', 'off')
    }

    # Boolean / switch flags (accept no value).
    $script:ClaudeBoolFlags = @(
        '--allow-dangerously-skip-permissions'
        '--bare'
        '--brief'
        '--chrome'
        '--continue'
        '--dangerously-skip-permissions'
        '--disable-slash-commands'
        '--exclude-dynamic-system-prompt-sections'
        '--fork-session'
        '--help'
        '--ide'
        '--include-hook-events'
        '--include-partial-messages'
        '--mcp-debug'
        '--no-chrome'
        '--no-session-persistence'
        '--print'
        '--replay-user-messages'
        '--strict-mcp-config'
        '--tmux'
        '--verbose'
        '--version'
    )

    # Optional-value flags: behave like booleans for token-consumption purposes
    # (do NOT consume the next token as a value), but still offer enum/value
    # completion when the user explicitly types --flag=.
    $script:ClaudeOptionalValueFlags = @(
        '--debug'
        '--resume'
        '--worktree'
        '--remote-control'
        '--from-pr'
        '--prompt-suggestions'
    )

    # Free-form string flags (single value, no fixed choices).
    $script:ClaudeStringFlags = @(
        '--agent'
        '--agents'
        '--append-system-prompt'
        '--fallback-model'
        '--json-schema'
        '--name'
        '--remote-control-session-name-prefix'
        '--session-id'
        '--system-prompt'
    )

    # Numeric flags.
    $script:ClaudeNumberFlags = @(
        '--max-budget-usd'
    )

    # Array / multi-value flags.
    $script:ClaudeArrayFlags = @(
        '--add-dir'
        '--allowedTools'
        '--allowed-tools'
        '--betas'
        '--disallowedTools'
        '--disallowed-tools'
        '--file'
        '--mcp-config'
        '--plugin-dir'
        '--plugin-url'
        '--setting-sources'
        '--settings'
        '--tools'
    )

    # Flags whose value is a model name (free-form, but with hints).
    $script:ClaudeModelFlags = @('--model')
    $script:ClaudeModelHints = @(
        'opus', 'sonnet', 'haiku',
        'claude-opus-4-8', 'claude-sonnet-4-6', 'claude-haiku-4-5-20251001'
    )

    # Flags whose value has comma-separated hints (free-form).
    $script:ClaudeHintFlags = @{
        '--setting-sources' = @('user', 'project', 'local')
    }

    # Flags that produce file-path completion.
    $script:ClaudePathFlags = @(
        '--debug-file'
        '--mcp-config'
        '--settings'
    )

    # Flags that produce directory-path completion.
    $script:ClaudeDirFlags = @(
        '--add-dir'
        '--plugin-dir'
    )

    # ---- Context tables ------------------------------------------------------------------------

    # L2 context-specific flags (beyond the global set): "cmd.subcmd" -> @(flags).
    $script:ClaudeContextFlags = @{
        'auth.login'                  = @('--claudeai', '--console', '--email', '--sso')
        'auth.status'                 = @('--json', '--text')
        'auto-mode.critique'          = @('--model')
        'mcp.add'                     = @('--callback-port', '--client-id', '--client-secret',
                                           '--env', '--header', '--scope', '--transport')
        'mcp.add-json'                = @('--client-secret', '--scope')
        'mcp.add-from-claude-desktop' = @('--scope')
        'mcp.remove'                  = @('--scope')
        'mcp.serve'                   = @('--debug', '--verbose')
        'plugin.disable'              = @('--all', '--scope')
        'plugin.enable'               = @('--scope')
        'plugin.install'              = @('--config', '--scope')
        'plugin.list'                 = @('--available', '--json')
        'plugin.prune'                = @('--dry-run', '--scope', '--yes')
        'plugin.tag'                  = @('--dry-run', '--force', '--message', '--push', '--remote')
        'plugin.validate'             = @('--strict')
        'project.purge'               = @('--all', '--dry-run', '--interactive', '--yes')
    }

    # Flags for commands that take flags directly (no L2 subcommand): "cmd" -> @(flags).
    $script:ClaudeCmdContextFlags = @{
        'agents'      = @('--add-dir', '--allow-dangerously-skip-permissions', '--cwd',
                           '--dangerously-skip-permissions', '--effort', '--json',
                           '--mcp-config', '--model', '--permission-mode', '--plugin-dir',
                           '--setting-sources', '--settings')
        'install'     = @('--force')
        'ultrareview' = @('--json', '--timeout')
    }

    # Context-specific boolean flags (take no value when used in a subcommand).
    $script:ClaudeContextBoolFlagSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    @('--claudeai', '--console', '--sso', '--json', '--text', '--client-secret',
      '--verbose', '--debug', '--all', '--available', '--dry-run', '--yes',
      '--force', '--push', '--strict', '--interactive') |
        ForEach-Object { $null = $script:ClaudeContextBoolFlagSet.Add($_) }

    # Context-specific enum values: "cmd.subcmd.--flag" -> @(choices).
    $script:ClaudeContextEnumFlags = @{
        'mcp.add.--scope'                     = @('local', 'user', 'project')
        'mcp.add.--transport'                 = @('stdio', 'sse', 'http')
        'mcp.add-json.--scope'                = @('local', 'user', 'project')
        'mcp.add-from-claude-desktop.--scope' = @('local', 'user', 'project')
        'mcp.remove.--scope'                  = @('local', 'user', 'project')
        'plugin.disable.--scope'              = @('user', 'project', 'local')
        'plugin.enable.--scope'               = @('user', 'project', 'local')
        'plugin.install.--scope'              = @('user', 'project', 'local')
        'plugin.prune.--scope'                = @('user', 'project', 'local')
    }

    # Context-specific value-taking (string/number) flags.
    $script:ClaudeContextValueFlagSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    @('--callback-port', '--client-id', '--email', '--config', '--message',
      '--remote', '--timeout') |
        ForEach-Object { $null = $script:ClaudeContextValueFlagSet.Add($_) }

    # Context-specific numeric flags.
    $script:ClaudeContextNumberFlagSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    @('--callback-port', '--timeout', '--max-budget-usd') |
        ForEach-Object { $null = $script:ClaudeContextNumberFlagSet.Add($_) }

    # Context short aliases keyed by "cmd.subcmd" or "cmd".
    $script:ClaudeContextShortAliases = @{
        'mcp.add'      = @{ '-e' = '--env'; '-H' = '--header'; '-s' = '--scope'; '-t' = '--transport' }
        'mcp.add-json' = @{ '-s' = '--scope' }
        'mcp.add-from-claude-desktop' = @{ '-s' = '--scope' }
        'mcp.remove'   = @{ '-s' = '--scope' }
        'mcp.serve'    = @{ '-d' = '--debug' }
        'plugin.disable'  = @{ '-a' = '--all'; '-s' = '--scope' }
        'plugin.enable'   = @{ '-s' = '--scope' }
        'plugin.install'  = @{ '-s' = '--scope' }
        'plugin.prune'    = @{ '-s' = '--scope'; '-y' = '--yes' }
        'plugin.tag'      = @{ '-f' = '--force'; '-m' = '--message' }
        'project.purge'   = @{ '-i' = '--interactive'; '-y' = '--yes' }
    }

    # Positional path completion for specific subcommand paths (first positional).
    $script:ClaudePathPositionalL2 = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    @('plugin.tag', 'plugin.validate', 'project.purge') |
        ForEach-Object { $null = $script:ClaudePathPositionalL2.Add($_) }

    # Positional enum values for specific subcommand paths.
    $script:ClaudePositionalEnums = @{
        'install' = @('stable', 'latest')
    }

    # Placeholder values for free-form positional slots.
    $script:ClaudePositionalPlaceholders = @{
        'install'                       = @('<target>')
        'ultrareview'                   = @('<target>')
        'mcp.add'                       = @('<name>', '<commandOrUrl>', '<arg>')
        'mcp.add-json'                  = @('<name>', '<json>')
        'mcp.get'                       = @('<name>')
        'mcp.remove'                    = @('<name>')
        'plugin.details'                = @('<name>')
        'plugin.disable'                = @('<plugin>')
        'plugin.enable'                 = @('<plugin>')
        'plugin.install'                = @('<plugin>')
        'plugin.uninstall'              = @('<plugin>')
        'plugin.update'                 = @('<plugin>')
        'plugin.marketplace.add'        = @('<source>')
        'plugin.marketplace.remove'     = @('<name>')
        'plugin.marketplace.update'     = @('<name>')
    }

    # ---- Global short alias maps ---------------------------------------------------------------

    $script:ClaudeShortAliases = @{
        '-c' = '--continue'
        '-d' = '--debug'
        '-h' = '--help'
        '-n' = '--name'
        '-p' = '--print'
        '-r' = '--resume'
        '-v' = '--version'
        '-w' = '--worktree'
    }

    # Reverse map (long -> short) built once at load time.
    $script:ClaudeAliasReverse = @{}
    $script:ClaudeShortAliases.GetEnumerator() |
        ForEach-Object { $script:ClaudeAliasReverse[$_.Value] = $_.Key }

    $script:ClaudeContextAliasReverse = @{}
    foreach ($entry in $script:ClaudeContextShortAliases.GetEnumerator()) {
        $reverse = @{}
        foreach ($alias in $entry.Value.GetEnumerator()) {
            $reverse[$alias.Value] = $alias.Key
        }
        $script:ClaudeContextAliasReverse[$entry.Key] = $reverse
    }

    # ---- Descriptions --------------------------------------------------------------------------

    $script:ClaudeCmdDesc = @{
        'agents'      = 'Run and manage agents'
        'auth'        = 'Manage authentication'
        'auto-mode'   = 'Configure and run auto mode'
        'doctor'      = 'Diagnose and verify the installation'
        'install'     = 'Install the native Claude Code build'
        'mcp'         = 'Configure and manage MCP servers'
        'plugin'      = 'Manage plugins and marketplaces'
        'project'     = 'Manage project-level state'
        'setup-token' = 'Set up a long-lived authentication token'
        'ultrareview' = 'Run an ultra-deep code review'
        'update'      = 'Update Claude Code to the latest version'
    }

    $script:ClaudeSubcmdDesc = @{
        'auth.login'                  = 'Log in to Claude'
        'auth.logout'                 = 'Log out of Claude'
        'auth.status'                 = 'Show current authentication status'
        'auth.help'                   = 'Show help for auth'
        'auto-mode.config'            = 'Configure auto mode'
        'auto-mode.critique'          = 'Run an auto-mode critique'
        'auto-mode.defaults'          = 'Show or reset auto-mode defaults'
        'auto-mode.help'              = 'Show help for auto-mode'
        'mcp.add'                     = 'Add an MCP server'
        'mcp.add-json'                = 'Add an MCP server from a JSON definition'
        'mcp.add-from-claude-desktop' = 'Import MCP servers from Claude Desktop'
        'mcp.get'                     = 'Show details for an MCP server'
        'mcp.list'                    = 'List configured MCP servers'
        'mcp.remove'                  = 'Remove an MCP server'
        'mcp.reset-project-choices'   = 'Reset per-project MCP trust choices'
        'mcp.serve'                   = 'Run Claude Code as an MCP server'
        'mcp.help'                    = 'Show help for mcp'
        'plugin.details'              = 'Show details for a plugin'
        'plugin.disable'              = 'Disable a plugin'
        'plugin.enable'               = 'Enable a plugin'
        'plugin.install'              = 'Install a plugin (alias: i)'
        'plugin.list'                 = 'List plugins'
        'plugin.marketplace'          = 'Manage plugin marketplaces'
        'plugin.prune'                = 'Remove orphaned plugins (alias: autoremove)'
        'plugin.tag'                  = 'Tag a plugin release'
        'plugin.uninstall'            = 'Uninstall a plugin (alias: remove)'
        'plugin.update'               = 'Update a plugin'
        'plugin.help'                 = 'Show help for plugin'
        'project.purge'               = 'Purge project-level state'
        'project.help'                = 'Show help for project'
        'plugin.marketplace.add'      = 'Add a marketplace source'
        'plugin.marketplace.list'     = 'List configured marketplaces'
        'plugin.marketplace.remove'   = 'Remove a marketplace (alias: rm)'
        'plugin.marketplace.update'   = 'Update marketplace metadata'
        'plugin.marketplace.help'     = 'Show help for marketplace'
    }

    $script:ClaudeFlagDesc = @{
        # Global boolean flags
        '--allow-dangerously-skip-permissions'      = '[boolean] Allow bypassing all permission checks'
        '--bare'                                     = '[boolean] Minimal output mode'
        '--brief'                                    = '[boolean] Brief output mode'
        '--chrome'                                   = '[boolean] Use Chrome integration'
        '--continue'                                 = '[boolean] Continue the most recent conversation'
        '--dangerously-skip-permissions'            = '[boolean] Skip permission prompts (dangerous)'
        '--disable-slash-commands'                  = '[boolean] Disable slash commands'
        '--exclude-dynamic-system-prompt-sections'  = '[boolean] Exclude dynamic system prompt sections'
        '--fork-session'                            = '[boolean] Fork into a new session'
        '--help'                                     = '[boolean] Show help'
        '--ide'                                      = '[boolean] Connect to an IDE'
        '--include-hook-events'                     = '[boolean] Include hook events in output'
        '--include-partial-messages'                = '[boolean] Include partial assistant messages'
        '--mcp-debug'                                = '[boolean] Enable MCP debug logging (deprecated)'
        '--no-chrome'                                = '[boolean] Disable Chrome integration'
        '--no-session-persistence'                  = '[boolean] Do not persist the session'
        '--print'                                    = '[boolean] Print response and exit (-p)'
        '--replay-user-messages'                    = '[boolean] Replay user messages'
        '--strict-mcp-config'                       = '[boolean] Use only the specified MCP config'
        '--tmux'                                     = '[boolean] Use tmux integration'
        '--verbose'                                  = '[boolean] Verbose output'
        '--version'                                  = '[boolean] Show version'
        # Optional-value flags
        '--debug'                                    = '[optional] Enable debug mode (optional filter)'
        '--resume'                                   = '[optional] Resume a session (optional id)'
        '--worktree'                                 = '[optional] Use a git worktree (optional name)'
        '--remote-control'                          = '[optional] Enable remote control (optional name)'
        '--from-pr'                                  = '[optional] Start from a PR (optional value)'
        '--prompt-suggestions'                      = '[optional] Prompt suggestions: true|false|...'
        # Global enum flags
        '--effort'                                   = '[string]  Reasoning effort: low|medium|high|xhigh|max'
        '--permission-mode'                          = '[string]  Permission mode'
        '--output-format'                            = '[string]  Output format: text|json|stream-json'
        '--input-format'                             = '[string]  Input format: text|stream-json'
        # Global string flags
        '--agent'                                    = '[string]  Agent to run'
        '--agents'                                   = '[string]  Agents definition (json)'
        '--append-system-prompt'                    = '[string]  Append text to the system prompt'
        '--fallback-model'                           = '[string]  Fallback model name'
        '--json-schema'                              = '[string]  JSON schema for structured output'
        '--name'                                     = '[string]  Session or run name (-n)'
        '--remote-control-session-name-prefix'      = '[string]  Remote-control session name prefix'
        '--session-id'                               = '[string]  Session ID (uuid)'
        '--system-prompt'                            = '[string]  Override the system prompt'
        '--model'                                    = '[string]  Model to use'
        # Numeric flags
        '--max-budget-usd'                           = '[number]  Maximum budget in USD'
        # Array flags
        '--add-dir'                                  = '[array]   Additional working directory'
        '--allowedTools'                            = '[array]   Allowed tools'
        '--allowed-tools'                            = '[array]   Allowed tools'
        '--betas'                                    = '[array]   API beta features'
        '--disallowedTools'                         = '[array]   Disallowed tools'
        '--disallowed-tools'                        = '[array]   Disallowed tools'
        '--file'                                     = '[array]   Input file(s)'
        '--mcp-config'                               = '[array]   MCP config file or JSON'
        '--plugin-dir'                               = '[array]   Plugin directory'
        '--plugin-url'                               = '[array]   Plugin URL'
        '--setting-sources'                          = '[array]   Setting sources: user,project,local'
        '--settings'                                 = '[array]   Settings file or JSON'
        '--tools'                                    = '[array]   Tools definition'
        # Context-specific flags
        '--claudeai'                                 = '[boolean] Use claude.ai login'
        '--console'                                  = '[boolean] Use Anthropic Console login'
        '--email'                                    = '[string]  Email address for login'
        '--sso'                                      = '[boolean] Use SSO login'
        '--json'                                     = '[boolean] JSON output'
        '--text'                                     = '[boolean] Text output'
        '--callback-port'                            = '[number]  OAuth callback port'
        '--client-id'                                = '[string]  OAuth client ID'
        '--client-secret'                            = '[boolean] Prompt for an OAuth client secret'
        '--env'                                      = '[array]   Environment variable: KEY=value'
        '--header'                                   = '[array]   HTTP header'
        '--scope'                                    = '[string]  Configuration scope'
        '--transport'                                = '[string]  MCP transport: stdio|sse|http'
        '--all'                                      = '[boolean] Apply to all'
        '--available'                                = '[boolean] Show available plugins'
        '--config'                                   = '[string]  Plugin config: key=value'
        '--dry-run'                                  = '[boolean] Show what would happen without doing it'
        '--yes'                                      = '[boolean] Assume yes to prompts'
        '--force'                                    = '[boolean] Force the operation'
        '--message'                                  = '[string]  Tag message'
        '--push'                                     = '[boolean] Push the tag'
        '--remote'                                   = '[string]  Git remote name'
        '--strict'                                   = '[boolean] Strict validation'
        '--interactive'                              = '[boolean] Interactive mode'
        '--cwd'                                      = '[string]  Working directory'
        '--timeout'                                  = '[number]  Timeout in minutes'
    }
}

#region -- Helpers ------------------------------------------------------------------------------

function New-ClaudeCompletion {
    param(
        [Parameter(Mandatory)]
        [string]$CompletionText,

        [string]$ListItemText  = '',
        [string]$Tooltip       = '',

        [System.Management.Automation.CompletionResultType]
        $ResultType = [System.Management.Automation.CompletionResultType]::ParameterValue
    )
    if ([string]::IsNullOrEmpty($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrEmpty($Tooltip))      { $Tooltip      = $ListItemText  }
    [System.Management.Automation.CompletionResult]::new(
        $CompletionText, $ListItemText, $ResultType, $Tooltip
    )
}

# Normalises a command/subcommand alias to its canonical name.
function Resolve-ClaudeCmdAlias {
    param([string]$Token)
    $script:ClaudeCmdAliases[$Token] ?? $Token
}

function Resolve-ClaudeSubAlias {
    param([string]$Sub, [string]$Token)
    $map = $script:ClaudeSubAliases[$Sub]
    if ($map -and $map.ContainsKey($Token)) { return $map[$Token] }
    return $Token
}

function Resolve-ClaudeL3Alias {
    param([string]$Sub, [string]$SubSub, [string]$Token)
    $map = $script:ClaudeL3Aliases["$Sub.$SubSub"]
    if ($map -and $map.ContainsKey($Token)) { return $map[$Token] }
    return $Token
}

function Resolve-ClaudeFlagName {
    param(
        [string]$FlagName,
        [string]$Sub,
        [string]$SubSub
    )
    foreach ($ctxKey in @(
        if ($Sub -and $SubSub) { "$Sub.$SubSub" }
        if ($Sub) { $Sub }
    )) {
        $ctxMap = $script:ClaudeContextShortAliases[$ctxKey]
        if ($ctxMap -and $ctxMap.ContainsKey($FlagName)) {
            return $ctxMap[$FlagName]
        }
    }
    $script:ClaudeShortAliases[$FlagName] ?? $FlagName
}

function Get-ClaudeShortAlias {
    param(
        [string]$FlagName,
        [string]$Sub,
        [string]$SubSub
    )
    foreach ($ctxKey in @(
        if ($Sub -and $SubSub) { "$Sub.$SubSub" }
        if ($Sub) { $Sub }
    )) {
        $ctxReverse = $script:ClaudeContextAliasReverse[$ctxKey]
        if ($ctxReverse -and $ctxReverse.ContainsKey($FlagName)) {
            return $ctxReverse[$FlagName]
        }
    }
    return $script:ClaudeAliasReverse[$FlagName]
}

# Returns $true when the flag consumes the next token as its value.
function Test-ClaudeFlagTakesValue {
    param(
        [string]$FlagName,
        [string]$Sub,
        [string]$SubSub
    )
    $r = Resolve-ClaudeFlagName -FlagName $FlagName -Sub $Sub -SubSub $SubSub

    # Optional-value flags never consume the next token (conservative).
    if ($script:ClaudeOptionalValueFlags -contains $r) { return $false }

    # Global enum flags always take a value.
    if ($null -ne $script:ClaudeEnumFlags[$r]) { return $true }

    # Global value-taking flag categories.
    if ($script:ClaudeStringFlags -contains $r) { return $true }
    if ($script:ClaudeNumberFlags -contains $r) { return $true }
    if ($script:ClaudeArrayFlags  -contains $r) { return $true }
    if ($script:ClaudeModelFlags  -contains $r) { return $true }
    if ($script:ClaudePathFlags   -contains $r) { return $true }
    if ($script:ClaudeDirFlags    -contains $r) { return $true }

    # Global boolean flags never take a value.
    if ($script:ClaudeBoolFlags   -contains $r) { return $false }

    # Context-specific enum flags.
    if ($Sub -and $SubSub) {
        $k2 = "$Sub.$SubSub.$r"
        if ($null -ne $script:ClaudeContextEnumFlags[$k2]) { return $true }
    }

    # Context-specific value-taking (string/number) flags.
    if ($script:ClaudeContextValueFlagSet.Contains($r)) { return $true }

    # Context-specific boolean flags.
    if ($script:ClaudeContextBoolFlagSet.Contains($r)) { return $false }

    return $false
}

# Returns the known enum choices for a flag in the given context, or $null.
function Get-ClaudeEnumValues {
    param(
        [string]$FlagName,
        [string]$Sub,
        [string]$SubSub
    )
    $r = Resolve-ClaudeFlagName -FlagName $FlagName -Sub $Sub -SubSub $SubSub

    # Global enum first.
    $vals = $script:ClaudeEnumFlags[$r]
    if ($vals) { return $vals }

    # L2 context.
    if ($Sub -and $SubSub) {
        $vals = $script:ClaudeContextEnumFlags["$Sub.$SubSub.$r"]
        if ($vals) { return $vals }
    }

    return $null
}

# Builds the full flag set for the current command context.
function Get-ClaudeFlagSet {
    param([string]$Sub, [string]$SubSub)

    $set = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    # Global flags always available.
    $script:ClaudeEnumFlags.Keys      | ForEach-Object { $null = $set.Add($_) }
    $script:ClaudeBoolFlags            | ForEach-Object { $null = $set.Add($_) }
    $script:ClaudeOptionalValueFlags   | ForEach-Object { $null = $set.Add($_) }
    $script:ClaudeStringFlags          | ForEach-Object { $null = $set.Add($_) }
    $script:ClaudeNumberFlags          | ForEach-Object { $null = $set.Add($_) }
    $script:ClaudeArrayFlags           | ForEach-Object { $null = $set.Add($_) }
    $script:ClaudeModelFlags           | ForEach-Object { $null = $set.Add($_) }
    $script:ClaudePathFlags            | ForEach-Object { $null = $set.Add($_) }
    $script:ClaudeDirFlags             | ForEach-Object { $null = $set.Add($_) }

    # Command-only context flags (no L2 subcommand).
    if ($Sub) {
        $cmdFlags = $script:ClaudeCmdContextFlags[$Sub]
        if ($cmdFlags) { $cmdFlags | ForEach-Object { $null = $set.Add($_) } }
    }
    # L2 context flags.
    if ($Sub -and $SubSub) {
        $ctxFlags = $script:ClaudeContextFlags["$Sub.$SubSub"]
        if ($ctxFlags) { $ctxFlags | ForEach-Object { $null = $set.Add($_) } }
    }
    return $set
}

function Get-ClaudePositionalPlaceholder {
    param(
        [string]$ContextKey,
        [int]$PositionIndex
    )
    $placeholders = $script:ClaudePositionalPlaceholders[$ContextKey]
    if (-not $placeholders) { return $null }
    if ($PositionIndex -lt $placeholders.Count) {
        return $placeholders[$PositionIndex]
    }
    return $placeholders[-1]
}

function Write-ClaudeLongFlagResults {
    param(
        [string]$WordToComplete,
        [string]$Sub,
        [string]$SubSub
    )
    $flagSet = Get-ClaudeFlagSet -Sub $Sub -SubSub $SubSub
    foreach ($flag in $flagSet) {
        if ($flag -notlike "$WordToComplete*") { continue }
        $desc = $script:ClaudeFlagDesc[$flag] ?? ''
        $short = Get-ClaudeShortAlias -FlagName $flag -Sub $Sub -SubSub $SubSub
        $tip = if ($short) { "$flag (alias: $short): $desc" } else { "${flag}: $desc" }
        New-ClaudeCompletion $flag -ResultType ParameterName -Tooltip $tip
    }
}

# Emits value completion for a value-taking flag (enum / model / hint / path / number / generic).
function Write-ClaudeFlagValue {
    param(
        [string]$Flag,
        [string]$WordToComplete,
        [string]$Sub,
        [string]$SubSub,
        [string]$InlinePrefix = ''   # e.g. "--flag=" for inline syntax, '' for space-separated
    )
    $enumVals = Get-ClaudeEnumValues -FlagName $Flag -Sub $Sub -SubSub $SubSub
    if ($enumVals) {
        $enumVals | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
            $tip = ($script:ClaudeFlagDesc[$Flag] ?? $_)
            if ($InlinePrefix) {
                New-ClaudeCompletion "$InlinePrefix$_" -ListItemText $_ -Tooltip $tip
            } else {
                New-ClaudeCompletion $_ -Tooltip $tip
            }
        }
        return
    }

    # Model hints.
    if ($script:ClaudeModelFlags -contains $Flag) {
        $script:ClaudeModelHints | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
            if ($InlinePrefix) {
                New-ClaudeCompletion "$InlinePrefix$_" -ListItemText $_ -Tooltip "Model: $_"
            } else {
                New-ClaudeCompletion $_ -Tooltip "Model: $_"
            }
        }
        return
    }

    # Comma-separated hint flags.
    $hints = $script:ClaudeHintFlags[$Flag]
    if ($hints) {
        $hints | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
            if ($InlinePrefix) {
                New-ClaudeCompletion "$InlinePrefix$_" -ListItemText $_ -Tooltip "Value: $_"
            } else {
                New-ClaudeCompletion $_ -Tooltip "Value: $_"
            }
        }
        return
    }

    # Path / dir completion.
    if ($script:ClaudePathFlags -contains $Flag -or $script:ClaudeDirFlags -contains $Flag) {
        [System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete) |
            ForEach-Object {
                if ($InlinePrefix) {
                    New-ClaudeCompletion "$InlinePrefix$($_.CompletionText)" `
                        -ListItemText $_.ListItemText `
                        -ResultType   $_.ResultType `
                        -Tooltip      $_.ToolTip
                } else {
                    $_
                }
            }
        return
    }

    # Number placeholder.
    if ($script:ClaudeNumberFlags -contains $Flag -or
        $script:ClaudeContextNumberFlagSet.Contains($Flag)) {
        if ('' -like "$WordToComplete*") {
            New-ClaudeCompletion '<n>' -Tooltip "Numeric value for $Flag"
        }
        return
    }

    # Generic placeholder — suppresses filesystem fallback for string/array flags.
    if ('' -like "$WordToComplete*") {
        New-ClaudeCompletion '<value>' -Tooltip "Value for $Flag"
    }
}

#endregion

#region -- Completer scriptblock ----------------------------------------------------------------

function Complete-ClaudeNative {
    param(
        $CommandName,
        $ParameterName,
        $WordToComplete,
        $CommandAst,
        $FakeBoundParameter
    )

    Initialize-ClaudeCompleterData

    # -------------------------------------------------------------------------
    # Detect the native ReadLine calling convention vs TabExpansion2.
    #
    # Native convention (ReadLine):
    #   A) after trailing space: $CommandName='', $ParameterName='<full line>',
    #      $WordToComplete='<cursor col>'
    #   B) mid-token: $CommandName='<partial>', $ParameterName='<full line>',
    #      $WordToComplete='<cursor col>'
    #
    # TabExpansion2 native path:
    #   $CommandName='<wordToComplete>', $ParameterName=<CommandAst object>,
    #   $WordToComplete='<cursorPosition int>'
    #
    # Heuristic: $WordToComplete is a pure integer AND $ParameterName coerces
    # to something that looks like a command line (starts with a non-space word).
    # -------------------------------------------------------------------------
    $isNativeConvention = $WordToComplete -match '^\d+$' -and
                          $ParameterName  -match '^\s*\S+'

    if ($isNativeConvention) {
        $nativePartialWord = $CommandName
        $cursorCol         = [int]$WordToComplete

        # $ParameterName is a CommandAst (TabExpansion2) or a string (ReadLine).
        # In both cases we need a plain string for parsing and indexing.
        if ($ParameterName -is [System.Management.Automation.Language.CommandAst]) {
            # TabExpansion2: we already have the CommandAst — reuse it directly.
            $CommandAst = $ParameterName
            $line       = $CommandAst.Extent.Text
        } else {
            $line    = [string]$ParameterName
            $tokens  = $null
            $parseErrs = $null
            $parsedAst = [System.Management.Automation.Language.Parser]::ParseInput(
                             $line, [ref]$tokens, [ref]$parseErrs)
            if ($parsedAst.EndBlock.Statements.Count -gt 0) {
                $pipeline = $parsedAst.EndBlock.Statements[0]
                if ($pipeline -is [System.Management.Automation.Language.PipelineAst] -and
                    $pipeline.PipelineElements.Count -gt 0 -and
                    $pipeline.PipelineElements[0] -is [System.Management.Automation.Language.CommandAst]) {
                    $CommandAst = $pipeline.PipelineElements[0]
                }
            }
        }

        if ($null -ne $CommandAst -and $CommandAst.CommandElements.Count -gt 1) {
            $lastEl     = $CommandAst.CommandElements[-1]
            $lastEnd    = $lastEl.Extent.EndOffset
            # Use Extent.Text universally — works for both CommandParameterAst
            # and StringConstantExpressionAst, and is safe under StrictMode.
            $lastTokVal = $lastEl.Extent.Text
            $cursorPastEnd  = $cursorCol -ge $line.Length
            $cursorPastTok  = $cursorCol -gt $lastEnd -and
                              ($cursorCol -gt $line.Length -or
                               [char]::IsWhiteSpace($line[$cursorCol - 1]))
            $isCompleteTok  = ($script:ClaudeTopCommands -contains $lastTokVal) -or
                              (($lastTokVal -like '-*') -and
                               $lastTokVal -notlike '*=*' -and
                               $lastTokVal.Length -gt 1 -and
                               $lastTokVal -ne '-')
            $hasTrailingSpace = $cursorPastTok -or
                              # Cursor at line end with a recognizable complete token means the
                              # user pressed Tab after finishing that token (no space typed yet).
                              # Only treat as trailing-space when cursor is actually PAST the
                              # token's own end offset; when cursor == lastEnd the token is
                              # still being completed as a prefix.
                              ($cursorPastEnd -and $isCompleteTok -and $cursorCol -gt $lastEnd)

            if ($hasTrailingSpace) {
                $WordToComplete = ''
            } elseif (-not [string]::IsNullOrEmpty($nativePartialWord)) {
                $WordToComplete = $nativePartialWord
            } else {
                $pfx = if ($cursorCol -le $line.Length) {
                           $line.Substring(0, $cursorCol)
                       } else { $line }
                $trimmed = $pfx.TrimEnd()
                $spc     = $trimmed.LastIndexOf(' ')
                if ($spc -ge 0) {
                    $WordToComplete = $trimmed.Substring($spc + 1)
                } else {
                    $fspc = $trimmed.IndexOf(' ')
                    $WordToComplete = if ($fspc -ge 0) {
                                         $trimmed.Substring($fspc + 1)
                                     } else { '' }
                }
            }
        } else {
            $WordToComplete = ''
        }
    }

    if ($null -eq $WordToComplete) { $WordToComplete = '' }
    if ($null -eq $CommandAst)     { return }

    $allElements = @($CommandAst.CommandElements)
    if ($allElements.Count -eq 0) { return }

    # -------------------------------------------------------------------------
    # Build the committed argument list.  Use Extent.Text for all nodes to stay
    # safe under StrictMode (CommandParameterAst may lack a .Value property).
    # -------------------------------------------------------------------------
    function Get-ClaudeTokenText {
        param($el)
        $el.Extent.Text
    }

    $allArgs = @(foreach ($el in ($allElements | Select-Object -Skip 1)) {
        Get-ClaudeTokenText -el $el
    })

    # Exclude the word being completed from committed args (for positionals),
    # but keep it for flags so Test-ClaudeFlagTakesValue can set expectingValue.
    if ($allArgs.Count -gt 0 -and $allArgs[-1] -eq $WordToComplete) {
        if ($WordToComplete -like '-*') {
            $committedArgs = $allArgs
        } else {
            $cnt = $allArgs.Count - 2
            $committedArgs = if ($cnt -lt 0) { @() } else { $allArgs[0..$cnt] }
        }
    } else {
        $committedArgs = $allArgs
    }

    # -------------------------------------------------------------------------
    # State machine: walk committed args to determine context.
    # Tracks up to 3 command levels plus expectingValue / currentFlag.
    # Command aliases are normalised as they are matched.
    # -------------------------------------------------------------------------
    $sub    = $null   # e.g. 'mcp'
    $subsub = $null   # e.g. 'add'
    $sub3   = $null   # e.g. 'add' under plugin.marketplace
    $expectingValue  = $false
    $currentFlag     = $null
    $positionalCount = 0     # non-flag positionals seen after sub/subsub/sub3

    foreach ($token in $committedArgs) {
        if ($expectingValue) {
            $expectingValue = $false
            $currentFlag    = $null
            continue
        }

        if ($token -like '-*') {
            if ($token -like '*=*') { continue }    # inline --flag=value; value already consumed
            if (Test-ClaudeFlagTakesValue -FlagName $token -Sub $sub -SubSub $subsub) {
                $expectingValue = $true
                $currentFlag    = Resolve-ClaudeFlagName -FlagName $token -Sub $sub -SubSub $subsub
            }
            continue
        }

        # Positional token — try to match command levels first.
        $matched = $false

        if ($null -eq $sub) {
            $canon = Resolve-ClaudeCmdAlias -Token $token
            if ($script:ClaudeTopCommands -contains $canon) {
                $sub     = $canon
                $matched = $true
            }
        } elseif ($null -eq $subsub) {
            $subs = $script:ClaudeSubSubcommands[$sub]
            $canon = Resolve-ClaudeSubAlias -Sub $sub -Token $token
            if ($subs -and $subs -contains $canon) {
                $subsub  = $canon
                $matched = $true
            }
        } elseif ($null -eq $sub3) {
            $l3k  = "$sub.$subsub"
            $l3cs = $script:ClaudeL3Subcommands[$l3k]
            $canon = Resolve-ClaudeL3Alias -Sub $sub -SubSub $subsub -Token $token
            if ($l3cs -and $l3cs -contains $canon) {
                $sub3    = $canon
                $matched = $true
            }
        }

        if (-not $matched) { $positionalCount++ }
    }

    # =========================================================================
    # 1.  Inline --flag=value completion
    # =========================================================================
    if ($WordToComplete -like '*=*') {
        $eqIdx    = $WordToComplete.IndexOf('=')
        $flagPart = $WordToComplete.Substring(0, $eqIdx)
        $valPfx   = $WordToComplete.Substring($eqIdx + 1)
        $resolved = Resolve-ClaudeFlagName -FlagName $flagPart -Sub $sub -SubSub $subsub

        Write-ClaudeFlagValue -Flag $resolved -WordToComplete $valPfx `
            -Sub $sub -SubSub $subsub -InlinePrefix "$flagPart="
        return
    }

    # =========================================================================
    # 2.  Value completion after space-separated value-taking flag
    # =========================================================================
    if ($expectingValue) {
        Write-ClaudeFlagValue -Flag $currentFlag -WordToComplete $WordToComplete `
            -Sub $sub -SubSub $subsub
        return
    }

    # =========================================================================
    # 3.  Flag completion (word starts with - or --)
    # =========================================================================
    if ($WordToComplete -like '-*') {
        $flagSet = Get-ClaudeFlagSet -Sub $sub -SubSub $subsub
        $isShort = $WordToComplete -notlike '--*'

        foreach ($flag in $flagSet) {
            $desc  = $script:ClaudeFlagDesc[$flag] ?? ''
            $short = Get-ClaudeShortAlias -FlagName $flag -Sub $sub -SubSub $subsub

            if ($isShort) {
                if (-not $short) { continue }
                if ($short -notlike "$WordToComplete*") { continue }
                New-ClaudeCompletion $short `
                    -ResultType ParameterName `
                    -Tooltip    "$short -> ${flag}: $desc"
            } else {
                if ($flag -notlike "$WordToComplete*") { continue }
                $tip = if ($short) { "$flag (alias: $short): $desc" } else { "${flag}: $desc" }
                New-ClaudeCompletion $flag -ResultType ParameterName -Tooltip $tip
            }
        }
        return
    }

    # =========================================================================
    # 4.  Subcommand / positional completion
    # =========================================================================

    # --- 4a. Have sub + subsub → offer L3 subcommands (or positional values). ---
    if ($sub -and $subsub -and $null -eq $sub3) {
        $l3k  = "$sub.$subsub"
        $l3cs = $script:ClaudeL3Subcommands[$l3k]
        if ($l3cs) {
            $l3cs | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                $tip = $script:ClaudeSubcmdDesc["$sub.$subsub.$_"] ?? $_
                New-ClaudeCompletion $_ -Tooltip $tip
            }
            return
        }

        # No L3 commands → offer positional enum / path if applicable.
        $emitted = $false
        $posVals = $script:ClaudePositionalEnums[$l3k]
        if ($posVals) {
            $posVals | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                New-ClaudeCompletion $_ -Tooltip "Positional: $_"
                $emitted = $true
            }
        }
        if ($script:ClaudePathPositionalL2.Contains($l3k) -and $positionalCount -eq 0) {
            [System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete)
            $emitted = $true
        }

        $placeholder = Get-ClaudePositionalPlaceholder -ContextKey $l3k -PositionIndex $positionalCount
        if ($placeholder -and $placeholder -like "$WordToComplete*") {
            New-ClaudeCompletion $placeholder -Tooltip "Positional value for $l3k"
            $emitted = $true
        }

        if ([string]::IsNullOrEmpty($WordToComplete)) {
            Write-ClaudeLongFlagResults -WordToComplete '' -Sub $sub -SubSub $subsub
            return
        }

        if ($emitted) {
            return
        }
        return
    }

    # --- 4b. Have sub + subsub + sub3 → positional values only. ---
    if ($sub -and $subsub -and $sub3) {
        $posKey  = "$sub.$subsub.$sub3"
        $emitted = $false
        $posVals = $script:ClaudePositionalEnums[$posKey]
        if ($posVals) {
            $posVals | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                New-ClaudeCompletion $_ -Tooltip "Positional: $_"
                $emitted = $true
            }
        }
        $placeholder = Get-ClaudePositionalPlaceholder -ContextKey $posKey -PositionIndex $positionalCount
        if ($placeholder -and $placeholder -like "$WordToComplete*") {
            New-ClaudeCompletion $placeholder -Tooltip "Positional value for $posKey"
            $emitted = $true
        }
        if ([string]::IsNullOrEmpty($WordToComplete)) {
            Write-ClaudeLongFlagResults -WordToComplete '' -Sub $sub -SubSub $subsub
            return
        }
        if ($emitted) {
            return
        }
        return
    }

    # --- 4c. Have sub only → offer L2 subcommands (or positional / cmd flags). ---
    if ($sub -and $null -eq $subsub) {
        $subs = $script:ClaudeSubSubcommands[$sub]
        if ($subs -and $subs.Count -gt 0) {
            $subs | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                $tip = $script:ClaudeSubcmdDesc["$sub.$_"] ?? $_
                New-ClaudeCompletion $_ -Tooltip $tip
            }
            return
        }

        # Command with no L2 subcommands → positional enum / path / placeholder.
        $emitted = $false
        $posVals = $script:ClaudePositionalEnums[$sub]
        if ($posVals) {
            $posVals | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                New-ClaudeCompletion $_ -Tooltip "Positional: $_"
                $emitted = $true
            }
        }
        if ($script:ClaudePathPositionalL2.Contains($sub) -and $positionalCount -eq 0) {
            [System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete)
            $emitted = $true
        }
        $placeholder = Get-ClaudePositionalPlaceholder -ContextKey $sub -PositionIndex $positionalCount
        if ($placeholder -and $placeholder -like "$WordToComplete*") {
            New-ClaudeCompletion $placeholder -Tooltip "Positional value for $sub"
            $emitted = $true
        }

        if ([string]::IsNullOrEmpty($WordToComplete)) {
            Write-ClaudeLongFlagResults -WordToComplete '' -Sub $sub -SubSub $subsub
            return
        }
        if ($emitted) { return }
        return
    }

    # --- 4d. Top level → offer L1 subcommands. ---
    $script:ClaudeTopCommands | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
        $tip = $script:ClaudeCmdDesc[$_] ?? $_
        New-ClaudeCompletion $_ -Tooltip $tip
    }
}

#endregion

#region -- Registration -------------------------------------------------------------------------

if (-not ((Get-Variable -Name ClaudeCompleterRegistered -Scope Script -ErrorAction SilentlyContinue) -and $script:ClaudeCompleterRegistered)) {
    try {
        Register-ArgumentCompleter -CommandName @('claude', 'claude.exe') -Native -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
            Complete-ClaudeNative -CommandName $commandName -ParameterName $parameterName -WordToComplete $wordToComplete -CommandAst $commandAst -FakeBoundParameter $fakeBoundParameter
        }

        $script:ClaudeCompleterRegistered = $true
    }
    catch {
        $script:ClaudeCompleterRegistered = $false
        throw
    }
}

#endregion
