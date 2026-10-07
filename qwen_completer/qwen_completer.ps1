<#
.SYNOPSIS
    Argument completer for qwen / qwen.cmd / qwen.ps1.
.DESCRIPTION
    Provides tab completion for qwen subcommands, flags, flag values, and the
    --flag=value inline syntax.  Dot-source this file from your $PROFILE to
    enable completion for all three invocation forms.

    Safe to source multiple times (re-registration simply replaces the completer).
.EXAMPLE
    . "$PSScriptRoot\qwen_completer.ps1"
#>

Set-StrictMode -Version Latest

function Initialize-QwenCompleterData {
    if (Get-Variable -Name QwenTopCommands -Scope Script -ErrorAction Ignore) {
        return
    }

    # Top-level subcommands.
    $script:QwenTopCommands = @('mcp', 'extensions', 'hooks', 'hook', 'channel')

    # Level-2 subcommands per top-level command.
    $script:QwenSubSubcommands = @{
        mcp        = @('add', 'remove', 'list', 'reconnect')
        extensions = @('install', 'uninstall', 'list', 'update', 'disable', 'enable', 'link', 'new', 'settings')
        channel    = @('start', 'stop', 'status', 'pairing', 'configure-weixin')
        hooks      = @()
        hook       = @()
    }

    # Level-3 subcommands: "cmd.subcmd" -> @(subsubcmds).
    # Covers: extensions settings set|list  and  channel pairing list|approve.
    $script:QwenL3Subcommands = @{
        'extensions.settings' = @('set', 'list')
        'channel.pairing'     = @('list', 'approve')
    }

    # ---- Flag categories -----------------------------------------------------------------------

    # Global enum flags with fixed choice sets.
    $script:QwenEnumFlags = @{
        '--telemetry-target'        = @('local', 'gcp')
        '--telemetry-otlp-protocol' = @('grpc', 'http')
        # 'auto' precedes 'auto-edit' so Tab on a typed 'auto' keeps it.
        '--approval-mode'           = @('plan', 'default', 'auto', 'auto-edit', 'yolo')
        '--channel'                 = @('VSCode', 'ACP', 'SDK', 'CI', 'desktop', 'daemon')
        '--input-format'            = @('text', 'stream-json')
        '--output-format'           = @('text', 'json', 'stream-json')
        '--auth-type'               = @('openai', 'openai-responses', 'anthropic', 'qwen-oauth', 'gemini', 'vertex-ai')
        '--sandbox'                 = @('true', 'false', 'docker', 'podman', 'sandbox-exec')   # [string], NOT a switch
    }

    # Boolean / switch flags (accept no value).
    $script:QwenBoolFlags = @(
        '--telemetry'
        '--telemetry-log-prompts'
        '--debug'
        '--bare'
        '--safe-mode'
        '--insecure'
        '--chat-recording'
        '--yolo'
        '--acp'
        '--experimental-lsp'
        '--restore-ask-user-question'
        '--openai-logging'
        '--screen-reader'
        '--include-partial-messages'
        '--list-extensions'
        '--continue'
        '--fork-session'
        '--help'
        '--version'
    )

    # Free-form string flags (single value, no fixed choices).
    $script:QwenStringFlags = @(
        '--telemetry-otlp-endpoint'
        '--proxy'
        '--model'
        '--advisor'
        '--prompt'
        '--prompt-interactive'
        '--system-prompt'
        '--append-system-prompt'
        '--output-style'
        '--sandbox-image'
        '--openai-api-key'
        '--openai-base-url'
        '--json-schema'
        '--resume'
        '--session-id'
        '--worktree'
        '--max-wall-time'
    )

    # Numeric flags.
    $script:QwenNumberFlags = @(
        '--max-session-turns'
        '--json-fd'
        '--max-tool-calls'
        '--max-subagent-depth'
    )

    # Array / multi-value flags.
    $script:QwenArrayFlags = @(
        '--fallback-model'
        '--allowed-mcp-server-names'
        '--allowed-tools'
        '--extensions'
        '--include-directories'
        '--add-dir'          # alias for --include-directories (help: --include-directories, --add-dir)
        '--core-tools'
        '--exclude-tools'
        '--disabled-slash-commands'
    )

    # Flags that produce file-path completion.
    $script:QwenPathFlags = @(
        '--telemetry-outfile'
        '--mcp-config'
        '--json-file'
        '--input-file'
    )

    # Flags that produce directory-path completion.
    $script:QwenDirFlags = @(
        '--openai-logging-dir'
        '--include-directories'
        '--add-dir'
    )

    # ---- Context tables ------------------------------------------------------------------------

    # L2 context-specific flags (beyond the global set): "cmd.subcmd" -> @(flags).
    $script:QwenContextFlags = @{
        'mcp.add'            = @('--scope', '--transport', '--env', '--header',
                                  '--timeout', '--trust', '--description',
                                  '--include-tools', '--exclude-tools',
                                  '--oauth-client-id', '--oauth-client-secret',
                                  '--oauth-redirect-uri', '--oauth-authorization-url',
                                  '--oauth-token-url', '--oauth-scopes')
        'mcp.reconnect'      = @('--all')
        'extensions.install' = @('--ref', '--auto-update', '--pre-release',
                                  '--registry', '--consent', '--scope')
        'extensions.update'  = @('--all')
        'extensions.disable' = @('--scope')
        'extensions.enable'  = @('--scope')
    }

    # Context-specific boolean flags (take no value when used in a subcommand).
    # These are checked to avoid incorrectly treating them as value-taking flags.
    $script:QwenContextBoolFlagSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    @('--trust', '--all', '--auto-update', '--pre-release', '--consent') |
        ForEach-Object { $null = $script:QwenContextBoolFlagSet.Add($_) }

    # Context-specific enum values: "cmd.subcmd.--flag" or "cmd.subcmd.subsub.--flag" -> @(choices).
    $script:QwenContextEnumFlags = @{
        'mcp.add.--scope'                  = @('user', 'project')
        'mcp.add.--transport'              = @('stdio', 'sse', 'http')
        'extensions.install.--scope'       = @('user', 'project', 'workspace')
        'extensions.settings.set.--scope'  = @('user', 'workspace')
    }

    # L3 context-specific flags: "cmd.subcmd.subsubcmd" -> @(flags).
    $script:QwenL3ContextFlags = @{
        'extensions.settings.set' = @('--scope')
    }

    # Subcommand paths (L2) whose first positional argument accepts path completion.
    $script:QwenPathPositionalL2 = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    @('extensions.link', 'extensions.new', 'extensions.install') |
        ForEach-Object { $null = $script:QwenPathPositionalL2.Add($_) }

    # Positional enum values for specific subcommand paths.
    $script:QwenPositionalEnums = @{
        'channel.configure-weixin' = @('clear')
    }

    # Placeholder values for positional slots that are free-form and should not
    # fall back to noisy filesystem completion.
    $script:QwenPositionalPlaceholders = @{
        'mcp.add'                  = @('<name>', '<commandOrUrl>', '<arg>')
        'mcp.remove'               = @('<name>')
        'mcp.reconnect'            = @('<server-name>')
        'extensions.install'       = @('<source>')
        'extensions.uninstall'     = @('<name>')
        'extensions.update'        = @('<name>')
        'extensions.disable'       = @('<name>')
        'extensions.enable'        = @('<name>')
        'extensions.new'           = @('<path>', '<template>')
        'extensions.settings.set'  = @('<name>', '<setting>')
        'extensions.settings.list' = @('<name>')
        'channel.start'            = @('<name>')
        'channel.pairing.list'     = @('<name>')
        'channel.pairing.approve'  = @('<name>', '<code>')
    }

    # ---- Short alias maps -----------------------------------------------------------------------

    $script:QwenShortAliases = @{
        '-d' = '--debug'
        '-m' = '--model'
        '-p' = '--prompt'
        '-i' = '--prompt-interactive'
        '-s' = '--sandbox'
        '-y' = '--yolo'
        '-e' = '--extensions'
        '-l' = '--list-extensions'
        '-o' = '--output-format'
        '-c' = '--continue'
        '-r' = '--resume'
        '-v' = '--version'
        '-h' = '--help'
    }

    # --sandbox (-s) is declared by the default command ('$0') builder only: no subcommand
    # accepts it, so inside 'mcp', 'extensions', ... neither form means --sandbox.
    $script:QwenRootOnlyFlags = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('--sandbox'), [System.StringComparer]::Ordinal
    )

    $script:QwenContextShortAliases = @{
        'mcp.add'          = @{
            '-s' = '--scope'
            '-t' = '--transport'
            '-e' = '--env'
            '-H' = '--header'
        }
        'mcp.reconnect'    = @{
            '-a' = '--all'
        }
    }

    # Reverse map (long -> short) built once at load time.
    $script:QwenAliasReverse = @{}
    $script:QwenShortAliases.GetEnumerator() |
        ForEach-Object { $script:QwenAliasReverse[$_.Value] = $_.Key }

    $script:QwenContextAliasReverse = @{}
    foreach ($entry in $script:QwenContextShortAliases.GetEnumerator()) {
        $reverse = @{}
        foreach ($alias in $entry.Value.GetEnumerator()) {
            $reverse[$alias.Value] = $alias.Key
        }
        $script:QwenContextAliasReverse[$entry.Key] = $reverse
    }

    # ---- Descriptions --------------------------------------------------------------------------

    $script:QwenCmdDesc = @{
        mcp        = 'Manage MCP servers'
        extensions = 'Manage extensions'
        hooks      = 'Manage hooks (use /hooks in interactive mode)'
        hook       = 'Alias for hooks'
        channel    = 'Manage messaging channels (Telegram, Discord, etc.)'
    }

    $script:QwenSubcmdDesc = @{
        'mcp.add'                        = 'Add an MCP server'
        'mcp.remove'                     = 'Remove an MCP server'
        'mcp.list'                       = 'List configured MCP servers'
        'mcp.reconnect'                  = 'Reconnect MCP server(s)'
        'extensions.install'             = 'Install an extension (URL, local path, or npm package)'
        'extensions.uninstall'           = 'Uninstall an extension'
        'extensions.list'                = 'List installed extensions'
        'extensions.update'              = 'Update extensions'
        'extensions.disable'             = 'Disable an extension'
        'extensions.enable'              = 'Enable an extension'
        'extensions.link'                = 'Link a local development extension (live)'
        'extensions.new'                 = 'Scaffold a new extension from boilerplate'
        'extensions.settings'            = 'Manage extension settings'
        'channel.start'                  = 'Start channels (all or named)'
        'channel.stop'                   = 'Stop the channel service'
        'channel.status'                 = 'Show channel service status'
        'channel.pairing'                = 'Manage DM pairing requests'
        'channel.configure-weixin'       = 'Configure WeChat channel (login or "clear")'
        'extensions.settings.set'        = 'Set a specific extension setting'
        'extensions.settings.list'       = 'List all settings for an extension'
        'channel.pairing.list'           = 'List pending pairing requests for a channel'
        'channel.pairing.approve'        = 'Approve a pending pairing request'
    }

    $script:QwenFlagDesc = @{
        # Global flags
        '--telemetry'                = '[boolean] Enable telemetry (deprecated: use settings.json)'
        '--telemetry-target'         = '[string]  Telemetry target: local|gcp (deprecated)'
        '--telemetry-otlp-endpoint'  = '[string]  OTLP collector endpoint URL (deprecated)'
        '--telemetry-otlp-protocol'  = '[string]  OTLP protocol: grpc|http (deprecated)'
        '--telemetry-log-prompts'    = '[boolean] Log prompts for telemetry (deprecated)'
        '--telemetry-outfile'        = '[path]    Write telemetry to file (deprecated)'
        '--debug'                    = '[boolean] Run in debug mode'
        '--bare'                     = '[boolean] Minimal mode: skip startup auto-discovery'
        '--safe-mode'                = '[boolean] Disable all customizations for troubleshooting'
        '--insecure'                 = '[boolean] Skip TLS certificate verification for API connections'
        '--proxy'                    = '[string]  HTTP proxy URL (deprecated)'
        '--chat-recording'           = '[boolean] Enable chat recording to disk'
        '--model'                    = '[string]  Model to use'
        '--advisor'                  = '[string]  Advisor model selector ("off" disables)'
        '--fallback-model'           = '[array]   Fallback model(s) for capacity errors (max 3)'
        '--prompt'                   = '[string]  Prompt text (deprecated; use positional)'
        '--prompt-interactive'       = '[string]  Prompt and continue in interactive mode'
        '--system-prompt'            = '[string]  Override session system prompt'
        '--append-system-prompt'     = '[string]  Append to session system prompt'
        '--output-style'             = '[string]  Output style for this run (e.g. Concise, Explanatory)'
        '--sandbox'                  = '[string]  Run in a sandbox: true|false|docker|podman|sandbox-exec'
        '--sandbox-image'            = '[string]  Sandbox container image URI (deprecated)'
        '--yolo'                     = '[boolean] Auto-accept all actions (YOLO mode)'
        '--approval-mode'            = '[string]  Tool approval mode: plan|default|auto|auto-edit|yolo'
        '--acp'                      = '[boolean] Start in ACP mode'
        '--experimental-lsp'         = '[boolean] Enable experimental LSP support'
        '--restore-ask-user-question' = '[boolean] Re-hang an unanswered ask_user_question on daemon resume'
        '--channel'                  = '[string]  Channel identifier: VSCode|ACP|SDK|CI|desktop|daemon'
        '--allowed-mcp-server-names' = '[array]   Allowed MCP server names'
        '--mcp-config'               = '[path]    MCP server config: JSON file path or inline JSON'
        '--allowed-tools'            = '[array]   Tools to allow (bypass confirmation)'
        '--extensions'               = '[array]   Extensions to use (-e)'
        '--list-extensions'          = '[boolean] List available extensions and exit'
        '--include-directories'      = '[array]   Additional workspace directories (--add-dir)'
        '--add-dir'                  = '[array]   Additional workspace directories (--include-directories)'
        '--openai-logging'           = '[boolean] Enable OpenAI API call logging'
        '--openai-logging-dir'       = '[path]    Directory for OpenAI API logs'
        '--openai-api-key'           = '[string]  OpenAI API key'
        '--openai-base-url'          = '[string]  OpenAI base URL override'
        '--screen-reader'            = '[boolean] Enable screen reader accessibility mode'
        '--input-format'             = '[string]  Input format: text|stream-json'
        '--output-format'            = '[string]  Output format: text|json|stream-json'
        '--include-partial-messages' = '[boolean] Include partial assistant messages (stream-json)'
        '--json-fd'                  = '[number]  File descriptor for structured JSON event output'
        '--json-file'                = '[path]    File for structured JSON event output'
        '--json-schema'              = '[string]  JSON Schema for the final output (JSON or @path)'
        '--input-file'               = '[path]    File for receiving remote input commands (JSONL)'
        '--continue'                 = '[boolean] Resume the most recent session'
        '--resume'                   = '[string]  Resume a specific session by ID'
        '--session-id'               = '[string]  Specify session ID for this run'
        '--fork-session'             = '[boolean] Fork a new session from the resumed one'
        '--worktree'                 = '[string]  Start the session inside a git worktree (slug or PR)'
        '--max-session-turns'        = '[number]  Maximum session turns'
        '--max-wall-time'            = '[string]  Run-level wall-clock budget (e.g. 90, 30s, 5m, 1h)'
        '--max-tool-calls'           = '[number]  Maximum cumulative tool calls for the run'
        '--max-subagent-depth'       = '[number]  Maximum sub-agent nesting depth'
        '--core-tools'               = '[array]   Core tool paths'
        '--exclude-tools'            = '[array]   Tools to exclude'
        '--disabled-slash-commands'  = '[array]   Slash command names to hide/disable'
        '--auth-type'                = '[string]  Authentication type'
        '--help'                     = '[boolean] Show help'
        '--version'                  = '[boolean] Show version'
        # Context-specific flags (mcp add / mcp reconnect)
        '--scope'                    = '[string]  Configuration scope'
        '--transport'                = '[string]  MCP transport: stdio|sse|http'
        '--env'                      = '[array]   Environment variable: KEY=value'
        '--header'                   = '[array]   HTTP header: "Name: value"'
        '--timeout'                  = '[number]  Connection timeout in milliseconds'
        '--trust'                    = '[boolean] Trust server (bypass all tool confirmations)'
        '--description'              = '[string]  Server description'
        '--include-tools'            = '[array]   Tools to include (comma-separated)'
        '--oauth-client-id'          = '[string]  OAuth client ID for MCP server authentication'
        '--oauth-client-secret'      = '[string]  OAuth client secret for MCP server authentication'
        '--oauth-redirect-uri'       = '[string]  OAuth redirect URI'
        '--oauth-authorization-url'  = '[string]  OAuth authorization URL'
        '--oauth-token-url'          = '[string]  OAuth token URL'
        '--oauth-scopes'             = '[array]   OAuth scopes (comma-separated)'
        '--all'                      = '[boolean] Apply to all'
        # Context-specific flags (extensions)
        '--ref'                      = '[string]  Git ref to install from'
        '--auto-update'              = '[boolean] Enable auto-update for this extension'
        '--pre-release'              = '[boolean] Include pre-release versions'
        '--registry'                 = '[string]  Custom npm registry URL'
        '--consent'                  = '[boolean] Acknowledge risks and skip confirmation'
    }
}

#region -- Helpers ------------------------------------------------------------------------------

function New-QwenCompletion {
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

function Resolve-QwenFlagName {
    param(
        [string]$FlagName,
        [string]$Sub,
        [string]$SubSub,
        [string]$SubSubSub
    )
    foreach ($ctxKey in @(
        if ($Sub -and $SubSub -and $SubSubSub) { "$Sub.$SubSub.$SubSubSub" }
        if ($Sub -and $SubSub) { "$Sub.$SubSub" }
    )) {
        $ctxMap = $script:QwenContextShortAliases[$ctxKey]
        if ($ctxMap -and $ctxMap.ContainsKey($FlagName)) {
            return $ctxMap[$FlagName]
        }
    }
    $long = $script:QwenShortAliases[$FlagName]
    if (-not $long -or ($Sub -and $script:QwenRootOnlyFlags.Contains($long))) {
        return $FlagName
    }
    $long
}

function Get-QwenShortAlias {
    param(
        [string]$FlagName,
        [string]$Sub,
        [string]$SubSub,
        [string]$SubSubSub
    )
    foreach ($ctxKey in @(
        if ($Sub -and $SubSub -and $SubSubSub) { "$Sub.$SubSub.$SubSubSub" }
        if ($Sub -and $SubSub) { "$Sub.$SubSub" }
    )) {
        $ctxReverse = $script:QwenContextAliasReverse[$ctxKey]
        if ($ctxReverse -and $ctxReverse.ContainsKey($FlagName)) {
            return $ctxReverse[$FlagName]
        }
    }
    return $script:QwenAliasReverse[$FlagName]
}

# Returns $true when the flag consumes the next token as its value.
function Test-QwenFlagTakesValue {
    param(
        [string]$FlagName,
        [string]$Sub,
        [string]$SubSub,
        [string]$SubSubSub
    )
    $r = Resolve-QwenFlagName -FlagName $FlagName -Sub $Sub -SubSub $SubSub -SubSubSub $SubSubSub
    if ($Sub -and $script:QwenRootOnlyFlags.Contains($r)) { return $false }

    # Global enum flags always take a value.
    if ($null -ne $script:QwenEnumFlags[$r]) { return $true }

    # Global value-taking flag categories.
    if ($script:QwenStringFlags -contains $r) { return $true }
    if ($script:QwenNumberFlags -contains $r) { return $true }
    if ($script:QwenArrayFlags  -contains $r) { return $true }
    if ($script:QwenPathFlags   -contains $r) { return $true }
    if ($script:QwenDirFlags    -contains $r) { return $true }

    # Global boolean flags never take a value.
    if ($script:QwenBoolFlags   -contains $r) { return $false }

    # Context-specific enum flags.
    if ($Sub -and $SubSubSub) {
        $k3 = "$Sub.$SubSub.$SubSubSub.$r"
        if ($null -ne $script:QwenContextEnumFlags[$k3]) { return $true }
    }
    if ($Sub -and $SubSub) {
        $k2 = "$Sub.$SubSub.$r"
        if ($null -ne $script:QwenContextEnumFlags[$k2]) { return $true }
    }

    # Context-specific boolean flags (trust, all, auto-update, pre-release, consent).
    if ($script:QwenContextBoolFlagSet.Contains($r)) { return $false }

    # Remaining context flags: treat as value-taking unless proven boolean above.
    if ($Sub -and $SubSub) {
        $ctxFlags = $script:QwenContextFlags["$Sub.$SubSub"]
        if ($ctxFlags -and $ctxFlags -contains $r) { return $true }
    }
    if ($Sub -and $SubSub -and $SubSubSub) {
        $l3Flags = $script:QwenL3ContextFlags["$Sub.$SubSub.$SubSubSub"]
        if ($l3Flags -and $l3Flags -contains $r) { return $true }
    }

    return $false
}

# Returns the known enum choices for a flag in the given context, or $null.
function Get-QwenEnumValues {
    param(
        [string]$FlagName,
        [string]$Sub,
        [string]$SubSub,
        [string]$SubSubSub
    )
    $r = Resolve-QwenFlagName -FlagName $FlagName -Sub $Sub -SubSub $SubSub -SubSubSub $SubSubSub
    if ($Sub -and $script:QwenRootOnlyFlags.Contains($r)) { return $null }

    # Global enum first.
    $vals = $script:QwenEnumFlags[$r]
    if ($vals) { return $vals }

    # L3 context (most specific).
    if ($Sub -and $SubSub -and $SubSubSub) {
        $vals = $script:QwenContextEnumFlags["$Sub.$SubSub.$SubSubSub.$r"]
        if ($vals) { return $vals }
    }

    # L2 context.
    if ($Sub -and $SubSub) {
        $vals = $script:QwenContextEnumFlags["$Sub.$SubSub.$r"]
        if ($vals) { return $vals }
    }

    return $null
}

# Builds the full flag set for the current command context.
function Get-QwenFlagSet {
    param([string]$Sub, [string]$SubSub, [string]$SubSubSub)

    $set = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $script:QwenEnumFlags.Keys  | ForEach-Object { $null = $set.Add($_) }
    $script:QwenBoolFlags        | ForEach-Object { $null = $set.Add($_) }
    $script:QwenStringFlags      | ForEach-Object { $null = $set.Add($_) }
    $script:QwenNumberFlags      | ForEach-Object { $null = $set.Add($_) }
    $script:QwenArrayFlags       | ForEach-Object { $null = $set.Add($_) }
    $script:QwenPathFlags        | ForEach-Object { $null = $set.Add($_) }
    $script:QwenDirFlags         | ForEach-Object { $null = $set.Add($_) }
    if ($Sub) { $set.ExceptWith($script:QwenRootOnlyFlags) }

    if ($Sub -and $SubSub) {
        $ctxFlags = $script:QwenContextFlags["$Sub.$SubSub"]
        if ($ctxFlags) { $ctxFlags | ForEach-Object { $null = $set.Add($_) } }
    }
    if ($Sub -and $SubSub -and $SubSubSub) {
        $l3Flags = $script:QwenL3ContextFlags["$Sub.$SubSub.$SubSubSub"]
        if ($l3Flags) { $l3Flags | ForEach-Object { $null = $set.Add($_) } }
    }
    return $set
}

function Get-QwenPositionalPlaceholder {
    param(
        [string]$ContextKey,
        [int]$PositionIndex
    )
    $placeholders = $script:QwenPositionalPlaceholders[$ContextKey]
    if (-not $placeholders) { return $null }
    if ($PositionIndex -lt $placeholders.Count) {
        return $placeholders[$PositionIndex]
    }
    return $placeholders[-1]
}

function Write-QwenLongFlagResults {
    param(
        [string]$WordToComplete,
        [string]$Sub,
        [string]$SubSub,
        [string]$SubSubSub
    )
    $flagSet = Get-QwenFlagSet -Sub $Sub -SubSub $SubSub -SubSubSub $SubSubSub
    foreach ($flag in $flagSet) {
        if ($flag -notlike "$WordToComplete*") { continue }
        $desc = $script:QwenFlagDesc[$flag] ?? ''
        $short = Get-QwenShortAlias -FlagName $flag -Sub $Sub -SubSub $SubSub -SubSubSub $SubSubSub
        $tip = if ($short) { "$flag (alias: $short): $desc" } else { "${flag}: $desc" }
        New-QwenCompletion $flag -ResultType ParameterName -Tooltip $tip
    }
}

#endregion

#region -- Completer scriptblock ----------------------------------------------------------------

function Complete-QwenNative {
    param(
        [string]$WordToComplete,
        $CommandAst,
        [int]$CursorPosition
    )

    Initialize-QwenCompleterData

    if ($null -eq $CommandAst) { return }

    $allElements = @($CommandAst.CommandElements)
    if ($allElements.Count -eq 0) { return }

    # -------------------------------------------------------------------------
    # The word under the cursor is the engine's $WordToComplete (empty in an
    # empty slot). Committed arguments are the elements that end before the
    # cursor; extents and the cursor are both absolute offsets in the input,
    # so this holds when the command follows another statement. Extent.Text
    # normalises CommandParameterAst (--flag) and StringConstantExpressionAst
    # tokens identically and is safe under StrictMode.
    # -------------------------------------------------------------------------
    $committedArgs = @(foreach ($el in ($allElements | Select-Object -Skip 1)) {
        if ($el.Extent.EndOffset -lt $CursorPosition) { $el.Extent.Text }
    })

    # -------------------------------------------------------------------------
    # State machine: walk committed args to determine context.
    # Tracks up to 3 command levels plus expectingValue / currentFlag.
    # -------------------------------------------------------------------------
    $sub    = $null   # e.g. 'mcp'
    $subsub = $null   # e.g. 'add'
    $sub3   = $null   # e.g. 'set'  (extensions settings set / channel pairing approve)
    $expectingValue  = $false
    $currentFlag     = $null
    $positionalCount = 0     # non-flag positionals seen after sub/subsub/sub3

    foreach ($token in $committedArgs) {
        if ($expectingValue) {
            $expectingValue = $false
            $currentFlag    = $null
            # yargs never takes a dash-led word other than a negative number as
            # a value, so in '--sandbox -p' the -p is a flag of its own.
            if ($token -notlike '-*' -or $token -match '^-\d') { continue }
        }

        if ($token -like '-*') {
            if ($token -like '*=*') { continue }    # inline --flag=value; value already consumed
            if (Test-QwenFlagTakesValue -FlagName $token -Sub $sub -SubSub $subsub -SubSubSub $sub3) {
                $expectingValue = $true
                $currentFlag    = Resolve-QwenFlagName -FlagName $token -Sub $sub -SubSub $subsub -SubSubSub $sub3
            }
            continue
        }

        # Positional token — try to match command levels first.
        $matched = $false

        if ($null -eq $sub -and $script:QwenTopCommands -contains $token) {
            $sub     = $token
            $matched = $true
        } elseif ($sub -and $null -eq $subsub) {
            $subs = $script:QwenSubSubcommands[$sub]
            if ($subs -and $subs -contains $token) {
                $subsub  = $token
                $matched = $true
            }
        } elseif ($sub -and $subsub -and $null -eq $sub3) {
            $l3k  = "$sub.$subsub"
            $l3cs = $script:QwenL3Subcommands[$l3k]
            if ($l3cs -and $l3cs -contains $token) {
                $sub3    = $token
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
        $resolved = Resolve-QwenFlagName -FlagName $flagPart -Sub $sub -SubSub $subsub -SubSubSub $sub3

        $enumVals = Get-QwenEnumValues -FlagName $resolved -Sub $sub -SubSub $subsub -SubSubSub $sub3
        if ($enumVals) {
            $enumVals | Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($valPfx) + '*') } | ForEach-Object {
                $tip = ($script:QwenFlagDesc[$resolved] ?? $_)
                New-QwenCompletion "$flagPart=$_" -ListItemText $_ -Tooltip $tip
            }
            return
        }

        # Path / dir flags with inline syntax.
        if ($script:QwenPathFlags -contains $resolved -or $script:QwenDirFlags -contains $resolved) {
            [System.Management.Automation.CompletionCompleters]::CompleteFilename($valPfx) |
                ForEach-Object {
                    New-QwenCompletion "$flagPart=$($_.CompletionText)" `
                        -ListItemText $_.ListItemText `
                        -ResultType   $_.ResultType `
                        -Tooltip      $_.ToolTip
                }
        }
        return
    }

    # =========================================================================
    # 2.  Value completion after space-separated value-taking flag
    # =========================================================================
    if ($expectingValue -and ($WordToComplete -notlike '-*' -or $WordToComplete -match '^-\d')) {
        $enumVals = Get-QwenEnumValues -FlagName $currentFlag -Sub $sub -SubSub $subsub -SubSubSub $sub3
        if ($enumVals) {
            $enumVals | Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*') } | ForEach-Object {
                $tip = ($script:QwenFlagDesc[$currentFlag] ?? $_)
                New-QwenCompletion $_ -Tooltip $tip
            }
            return
        }

        # Path / dir completion.
        if ($script:QwenPathFlags -contains $currentFlag -or
            $script:QwenDirFlags  -contains $currentFlag) {
            [System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete)
            return
        }

        # Number placeholder — suppresses filesystem fallback.
        if ($script:QwenNumberFlags -contains $currentFlag) {
            if ('' -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
                New-QwenCompletion '<n>' -Tooltip "Numeric value for $currentFlag"
            }
            return
        }

        # Generic placeholder — suppresses filesystem fallback for string/array flags.
        if ('' -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
            New-QwenCompletion '<value>' -Tooltip "Value for $currentFlag"
        }
        return
    }

    # =========================================================================
    # 3.  Flag completion (word starts with - or --)
    # =========================================================================
    if ($WordToComplete -like '-*') {
        $flagSet = Get-QwenFlagSet -Sub $sub -SubSub $subsub -SubSubSub $sub3
        $isShort = $WordToComplete -notlike '--*'

        foreach ($flag in $flagSet) {
            $desc  = $script:QwenFlagDesc[$flag] ?? ''
            $short = Get-QwenShortAlias -FlagName $flag -Sub $sub -SubSub $subsub -SubSubSub $sub3

            if ($isShort) {
                if (-not $short) { continue }
                if ($short -notlike "$WordToComplete*") { continue }
                New-QwenCompletion $short `
                    -ResultType ParameterName `
                    -Tooltip    "$short -> ${flag}: $desc"
            } else {
                if ($flag -notlike "$WordToComplete*") { continue }
                $tip = if ($short) { "$flag (alias: $short): $desc" } else { "${flag}: $desc" }
                New-QwenCompletion $flag -ResultType ParameterName -Tooltip $tip
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
        $l3cs = $script:QwenL3Subcommands[$l3k]
        if ($l3cs) {
            $l3cs | Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*') } | ForEach-Object {
                $tip = $script:QwenSubcmdDesc["$sub.$subsub.$_"] ?? $_
                New-QwenCompletion $_ -Tooltip $tip
            }
            return
        }

        # No L3 commands → offer positional enum / path if applicable.
        $emitted = $false
        $posVals = $script:QwenPositionalEnums[$l3k]
        if ($posVals) {
            $posVals | Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*') } | ForEach-Object {
                New-QwenCompletion $_ -Tooltip "Positional: $_"
                $emitted = $true
            }
        }
        if ($script:QwenPathPositionalL2.Contains($l3k) -and $positionalCount -eq 0) {
            [System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete)
            $emitted = $true
        }

        $placeholder = Get-QwenPositionalPlaceholder -ContextKey $l3k -PositionIndex $positionalCount
        if ($placeholder -and $placeholder -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
            New-QwenCompletion $placeholder -Tooltip "Positional value for $l3k"
            $emitted = $true
        }

        if ([string]::IsNullOrEmpty($WordToComplete)) {
            Write-QwenLongFlagResults -WordToComplete '' -Sub $sub -SubSub $subsub -SubSubSub $sub3
            return
        }

        if ($emitted) {
            return
        }
        return
    }

    # --- 4b. Have sub + subsub + sub3 → positional enum values only. ---
    if ($sub -and $subsub -and $sub3) {
        $posKey  = "$sub.$subsub.$sub3"
        $emitted = $false
        $posVals = $script:QwenPositionalEnums[$posKey]
        if ($posVals) {
            $posVals | Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*') } | ForEach-Object {
                New-QwenCompletion $_ -Tooltip "Positional: $_"
                $emitted = $true
            }
        }
        $placeholder = Get-QwenPositionalPlaceholder -ContextKey $posKey -PositionIndex $positionalCount
        if ($placeholder -and $placeholder -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
            New-QwenCompletion $placeholder -Tooltip "Positional value for $posKey"
            $emitted = $true
        }
        if ([string]::IsNullOrEmpty($WordToComplete)) {
            Write-QwenLongFlagResults -WordToComplete '' -Sub $sub -SubSub $subsub -SubSubSub $sub3
            return
        }
        if ($emitted) {
            return
        }
        return
    }

    # --- 4c. Have sub only → offer L2 subcommands. ---
    if ($sub -and $null -eq $subsub) {
        $subs = $script:QwenSubSubcommands[$sub]
        if ($subs) {
            $subs | Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*') } | ForEach-Object {
                $tip = $script:QwenSubcmdDesc["$sub.$_"] ?? $_
                New-QwenCompletion $_ -Tooltip $tip
            }
        } elseif ([string]::IsNullOrEmpty($WordToComplete)) {
            Write-QwenLongFlagResults -WordToComplete '' -Sub $sub -SubSub $subsub -SubSubSub $sub3
        }
        return
    }

    # --- 4d. Top level → offer L1 subcommands. ---
    $script:QwenTopCommands | Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*') } | ForEach-Object {
        $tip = $script:QwenCmdDesc[$_] ?? $_
        New-QwenCompletion $_ -Tooltip $tip
    }
}

#endregion

#region -- Registration -------------------------------------------------------------------------

Register-ArgumentCompleter -CommandName @('qwen', 'qwen.cmd', 'qwen.ps1') -Native -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-QwenNative -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}

#endregion
