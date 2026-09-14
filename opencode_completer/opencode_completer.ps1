# opencode_completer.ps1
# PowerShell argument completer for opencode and opencode.exe.
# Static-first: the command tree, per-command options and enum values are transcribed from the yargs help of
# opencode 1.18.30 ('opencode --help' and 'opencode <command> --help').

Set-StrictMode -Version Latest

function New-OpencodeOption {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [string]$Kind = 'Flag',
        [string[]]$Values = @(),
        [string]$Placeholder = ''
    )

    [pscustomobject]@{
        Tokens      = @($Tokens)
        Description = $Description
        Kind        = $Kind
        Values      = @($Values)
        Placeholder = $Placeholder
    }
}

function New-OpencodePositional {
    param(
        [string]$Name,
        [string]$Description,
        [string]$Kind = 'Placeholder',
        [string]$Placeholder = ''
    )

    [pscustomobject]@{
        Name        = $Name
        Description = $Description
        Kind        = $Kind
        Placeholder = if ($Placeholder) { $Placeholder } else { "<$Name>" }
    }
}

function New-OpencodeCommand {
    param(
        [string]$Name,
        [string]$Description,
        [string[]]$Aliases = @(),
        [object[]]$Options = @(),
        [object[]]$Positionals = @(),
        [object[]]$Subcommands = @()
    )

    [pscustomobject]@{
        Name        = $Name
        Description = $Description
        Aliases     = @($Aliases)
        Options     = @($Options)
        Positionals = @($Positionals)
        Subcommands = @($Subcommands)
    }
}

function Get-OpencodeCompletionCatalog {
    $existing = Get-Variable -Name OpencodeCompletionCatalog -Scope Script -ErrorAction Ignore
    if ($existing) {
        return $existing.Value
    }

    $logLevel = New-OpencodeOption -Tokens @('--log-level') -Description 'log level' -Kind 'Enum' -Values @('DEBUG', 'INFO', 'WARN', 'ERROR')
    $common = @(
        New-OpencodeOption -Tokens @('-h', '--help') -Description 'show help'
        New-OpencodeOption -Tokens @('-v', '--version') -Description 'show version number'
        New-OpencodeOption -Tokens @('--print-logs') -Description 'print logs to stderr'
        $logLevel
        New-OpencodeOption -Tokens @('--pure') -Description 'run without external plugins'
    )
    $server = @(
        New-OpencodeOption -Tokens @('--port') -Description 'port to listen on [default: 0]' -Kind 'Number' -Placeholder '<port>'
        New-OpencodeOption -Tokens @('--hostname') -Description 'hostname to listen on [default: "127.0.0.1"]' -Kind 'Enum' -Values @('127.0.0.1', '0.0.0.0', 'localhost')
        New-OpencodeOption -Tokens @('--mdns') -Description 'enable mDNS service discovery (defaults hostname to 0.0.0.0)'
        New-OpencodeOption -Tokens @('--mdns-domain') -Description 'custom domain name for mDNS service (default: opencode.local)' -Kind 'String' -Placeholder '<domain>'
        New-OpencodeOption -Tokens @('--cors') -Description 'additional domains to allow for CORS' -Kind 'String' -Placeholder '<domain>'
    )
    $session = @(
        New-OpencodeOption -Tokens @('-c', '--continue') -Description 'continue the last session'
        New-OpencodeOption -Tokens @('-s', '--session') -Description 'session id to continue' -Kind 'String' -Placeholder '<session-id>'
        New-OpencodeOption -Tokens @('--fork') -Description 'fork the session when continuing (use with --continue or --session)'
    )
    $model = New-OpencodeOption -Tokens @('-m', '--model') -Description 'model to use in the format of provider/model' -Kind 'String' -Placeholder '<provider/model>'
    $agent = New-OpencodeOption -Tokens @('--agent') -Description 'agent to use' -Kind 'String' -Placeholder '<agent>'
    $auto = New-OpencodeOption -Tokens @('--auto') -Description 'auto-approve permissions that are not explicitly denied (dangerous!)'
    $mini = @(
        New-OpencodeOption -Tokens @('--mini') -Description 'start the minimal interactive interface'
        New-OpencodeOption -Tokens @('--no-replay') -Description 'disable mini session history replay on resume and after resize'
        New-OpencodeOption -Tokens @('--replay-limit') -Description 'cap visible mini replay to the newest N messages' -Kind 'Number' -Placeholder '<n>'
    )
    $auth = @(
        New-OpencodeOption -Tokens @('-p', '--password') -Description 'basic auth password (defaults to OPENCODE_SERVER_PASSWORD)' -Kind 'String' -Placeholder '<password>'
        New-OpencodeOption -Tokens @('-u', '--username') -Description "basic auth username (defaults to OPENCODE_SERVER_USERNAME or 'opencode')" -Kind 'String' -Placeholder '<username>'
    )

    $rootOptions = @($common) + @($server) + @($model) + @($session) + @(
        New-OpencodeOption -Tokens @('--prompt') -Description 'prompt to use' -Kind 'String' -Placeholder '<prompt>'
        $agent
        $auto
    ) + @($mini)

    $commands = @(
        New-OpencodeCommand -Name 'completion' -Description 'generate shell completion script' -Options $common
        New-OpencodeCommand -Name 'acp' -Description 'start ACP (Agent Client Protocol) server' -Options (@($common) + @($server) + @(
            New-OpencodeOption -Tokens @('--cwd') -Description 'working directory' -Kind 'Directory'
        ))
        New-OpencodeCommand -Name 'mcp' -Description 'manage MCP (Model Context Protocol) servers' -Options $common -Subcommands @(
            New-OpencodeCommand -Name 'add' -Description 'add an MCP server' -Options (@($common) + @(
                New-OpencodeOption -Tokens @('--url') -Description 'URL for a remote MCP server' -Kind 'String' -Placeholder '<url>'
                New-OpencodeOption -Tokens @('--env') -Description 'environment variable for a local MCP server (KEY=VALUE)' -Kind 'String' -Placeholder '<KEY=VALUE>'
                New-OpencodeOption -Tokens @('--header') -Description 'HTTP header for a remote MCP server (KEY=VALUE)' -Kind 'String' -Placeholder '<KEY=VALUE>'
            )) -Positionals @(New-OpencodePositional -Name 'name' -Description 'name of the MCP server')
            New-OpencodeCommand -Name 'list' -Description 'list MCP servers and their status' -Aliases @('ls') -Options $common
            New-OpencodeCommand -Name 'auth' -Description 'authenticate with an OAuth-enabled MCP server' -Options $common -Positionals @(New-OpencodePositional -Name 'name' -Description 'name of the MCP server') -Subcommands @(
                New-OpencodeCommand -Name 'list' -Description 'list OAuth-capable MCP servers and their auth status' -Aliases @('ls') -Options $common
            )
            New-OpencodeCommand -Name 'logout' -Description 'remove OAuth credentials for an MCP server' -Options $common -Positionals @(New-OpencodePositional -Name 'name' -Description 'name of the MCP server')
            New-OpencodeCommand -Name 'debug' -Description 'debug OAuth connection for an MCP server' -Options $common -Positionals @(New-OpencodePositional -Name 'name' -Description 'name of the MCP server')
        )
        New-OpencodeCommand -Name 'attach' -Description 'attach to a running opencode server' -Options (@($common) + @(
            New-OpencodeOption -Tokens @('--dir') -Description 'directory to run in' -Kind 'Directory'
        ) + @($session) + @($auth) + @($mini)) -Positionals @(New-OpencodePositional -Name 'url' -Description 'http://localhost:4096' -Placeholder 'http://localhost:4096')
        New-OpencodeCommand -Name 'run' -Description 'run opencode with a message' -Options (@($common) + @(
            New-OpencodeOption -Tokens @('--command') -Description 'the command to run, use message for args' -Kind 'String' -Placeholder '<command>'
        ) + @($session) + @(
            New-OpencodeOption -Tokens @('--share') -Description 'share the session'
            $model
            $agent
            New-OpencodeOption -Tokens @('--format') -Description 'format: default (formatted) or json (raw JSON events)' -Kind 'Enum' -Values @('default', 'json')
            New-OpencodeOption -Tokens @('-f', '--file') -Description 'file(s) to attach to message' -Kind 'Path'
            New-OpencodeOption -Tokens @('--title') -Description 'title for the session (uses truncated prompt if no value provided)' -Kind 'String' -Placeholder '<title>'
            New-OpencodeOption -Tokens @('--attach') -Description 'attach to a running opencode server (e.g., http://localhost:4096)' -Kind 'String' -Placeholder 'http://localhost:4096'
        ) + @($auth) + @(
            New-OpencodeOption -Tokens @('--dir') -Description 'directory to run in, path on remote server if attaching' -Kind 'Directory'
            New-OpencodeOption -Tokens @('--port') -Description 'port for the local server (defaults to random port if no value provided)' -Kind 'Number' -Placeholder '<port>'
            New-OpencodeOption -Tokens @('--variant') -Description 'model variant (provider-specific reasoning effort, e.g., high, max, minimal)' -Kind 'Enum' -Values @('high', 'max', 'minimal')
            New-OpencodeOption -Tokens @('--thinking') -Description 'show thinking blocks'
            New-OpencodeOption -Tokens @('-i', '--interactive') -Description 'run in direct interactive split-footer mode'
            $auto
        )) -Positionals @(New-OpencodePositional -Name 'message' -Description 'message to send' -Kind 'Text' -Placeholder '<message>')
        New-OpencodeCommand -Name 'debug' -Description 'debugging and troubleshooting tools' -Options $common -Subcommands @(
            New-OpencodeCommand -Name 'config' -Description 'show resolved configuration' -Options $common
            New-OpencodeCommand -Name 'lsp' -Description 'LSP debugging utilities' -Options $common -Subcommands @(
                New-OpencodeCommand -Name 'diagnostics' -Description 'get diagnostics for a file' -Options $common -Positionals @(New-OpencodePositional -Name 'file' -Description 'file to diagnose' -Kind 'Path')
                New-OpencodeCommand -Name 'symbols' -Description 'search workspace symbols' -Options $common -Positionals @(New-OpencodePositional -Name 'query' -Description 'symbol query')
                New-OpencodeCommand -Name 'document-symbols' -Description 'get symbols from a document' -Options $common -Positionals @(New-OpencodePositional -Name 'uri' -Description 'document uri')
            )
            New-OpencodeCommand -Name 'rg' -Description 'ripgrep debugging utilities' -Options $common -Subcommands @(
                New-OpencodeCommand -Name 'files' -Description 'list files using ripgrep' -Options $common
                New-OpencodeCommand -Name 'search' -Description 'search file contents using ripgrep' -Options $common -Positionals @(New-OpencodePositional -Name 'pattern' -Description 'search pattern')
            )
            New-OpencodeCommand -Name 'file' -Description 'file system debugging utilities' -Options $common -Subcommands @(
                New-OpencodeCommand -Name 'read' -Description 'read file contents as JSON' -Options $common -Positionals @(New-OpencodePositional -Name 'path' -Description 'file to read' -Kind 'Path')
                New-OpencodeCommand -Name 'list' -Description 'list files in a directory' -Options $common -Positionals @(New-OpencodePositional -Name 'path' -Description 'directory to list' -Kind 'Directory')
                New-OpencodeCommand -Name 'search' -Description 'search files by query' -Options $common -Positionals @(New-OpencodePositional -Name 'query' -Description 'file query')
            )
            New-OpencodeCommand -Name 'scrap' -Description 'list all known projects' -Options $common
            New-OpencodeCommand -Name 'skill' -Description 'list all available skills' -Options $common
            New-OpencodeCommand -Name 'snapshot' -Description 'snapshot debugging utilities' -Options $common -Subcommands @(
                New-OpencodeCommand -Name 'track' -Description 'track current snapshot state' -Options $common
                New-OpencodeCommand -Name 'patch' -Description 'show patch for a snapshot hash' -Options $common -Positionals @(New-OpencodePositional -Name 'hash' -Description 'snapshot hash')
                New-OpencodeCommand -Name 'diff' -Description 'show diff for a snapshot hash' -Options $common -Positionals @(New-OpencodePositional -Name 'hash' -Description 'snapshot hash')
            )
            New-OpencodeCommand -Name 'startup' -Description 'print startup timing' -Options $common
            New-OpencodeCommand -Name 'agent' -Description 'show agent configuration details' -Options (@($common) + @(
                New-OpencodeOption -Tokens @('--tool') -Description 'Tool id to execute' -Kind 'String' -Placeholder '<tool-id>'
                New-OpencodeOption -Tokens @('--params') -Description 'Tool params as JSON or a JS object literal' -Kind 'String' -Placeholder '<json>'
            )) -Positionals @(New-OpencodePositional -Name 'name' -Description 'Agent name')
            New-OpencodeCommand -Name 'v2' -Description 'debug v2 catalog and built-in plugins' -Options $common
            New-OpencodeCommand -Name 'info' -Description 'show debug information' -Options $common
            New-OpencodeCommand -Name 'paths' -Description 'show global paths (data, config, cache, state)' -Options $common
            New-OpencodeCommand -Name 'wait' -Description 'wait indefinitely (for debugging)' -Options $common
        )
        New-OpencodeCommand -Name 'providers' -Description 'manage AI providers and credentials' -Aliases @('auth') -Options $common -Subcommands @(
            New-OpencodeCommand -Name 'list' -Description 'list providers and credentials' -Aliases @('ls') -Options $common
            New-OpencodeCommand -Name 'login' -Description 'log in to a provider' -Options (@($common) + @(
                New-OpencodeOption -Tokens @('-p', '--provider') -Description 'provider id or name to log in to (skips provider selection)' -Kind 'String' -Placeholder '<provider>'
                New-OpencodeOption -Tokens @('-m', '--method') -Description 'login method label (skips method selection)' -Kind 'String' -Placeholder '<method>'
            )) -Positionals @(New-OpencodePositional -Name 'url' -Description 'opencode auth provider')
            New-OpencodeCommand -Name 'logout' -Description 'log out from a configured provider' -Options $common -Positionals @(New-OpencodePositional -Name 'provider' -Description 'provider id or name to log out from')
        )
        New-OpencodeCommand -Name 'agent' -Description 'manage agents' -Options $common -Subcommands @(
            New-OpencodeCommand -Name 'create' -Description 'create a new agent' -Options (@($common) + @(
                New-OpencodeOption -Tokens @('--path') -Description 'directory path to generate the agent file' -Kind 'Directory'
                New-OpencodeOption -Tokens @('--description') -Description 'what the agent should do' -Kind 'String' -Placeholder '<description>'
                New-OpencodeOption -Tokens @('--mode') -Description 'agent mode' -Kind 'Enum' -Values @('all', 'primary', 'subagent')
                New-OpencodeOption -Tokens @('--permissions', '--tools') -Description 'comma-separated list of permissions to allow (default: all)' -Kind 'Enum' -Values @('bash', 'read', 'edit', 'glob', 'grep', 'webfetch', 'task', 'todowrite', 'websearch', 'lsp', 'skill')
                $model
            ))
            New-OpencodeCommand -Name 'list' -Description 'list all available agents' -Options $common
        )
        New-OpencodeCommand -Name 'upgrade' -Description 'upgrade opencode to the latest or a specific version' -Options (@($common) + @(
            New-OpencodeOption -Tokens @('-m', '--method') -Description 'installation method to use' -Kind 'Enum' -Values @('curl', 'npm', 'pnpm', 'bun', 'brew', 'choco', 'scoop')
        )) -Positionals @(New-OpencodePositional -Name 'target' -Description "version to upgrade to, for ex '0.1.48' or 'v0.1.48'" -Placeholder '<version>')
        New-OpencodeCommand -Name 'uninstall' -Description 'uninstall opencode and remove all related files' -Options (@($common) + @(
            New-OpencodeOption -Tokens @('-c', '--keep-config') -Description 'keep configuration files'
            New-OpencodeOption -Tokens @('-d', '--keep-data') -Description 'keep session data and snapshots'
            New-OpencodeOption -Tokens @('--dry-run') -Description 'show what would be removed without removing'
            New-OpencodeOption -Tokens @('-f', '--force') -Description 'skip confirmation prompts'
        ))
        New-OpencodeCommand -Name 'serve' -Description 'starts a headless opencode server' -Options (@($common) + @($server))
        New-OpencodeCommand -Name 'web' -Description 'start opencode server and open web interface' -Options (@($common) + @($server))
        New-OpencodeCommand -Name 'models' -Description 'list all available models' -Options (@($common) + @(
            New-OpencodeOption -Tokens @('--verbose') -Description 'use more verbose model output (includes metadata like costs)'
            New-OpencodeOption -Tokens @('--refresh') -Description 'refresh the models cache from models.dev'
        )) -Positionals @(New-OpencodePositional -Name 'provider' -Description 'provider ID to filter models by')
        New-OpencodeCommand -Name 'stats' -Description 'show token usage and cost statistics' -Options (@($common) + @(
            New-OpencodeOption -Tokens @('--days') -Description 'show stats for the last N days (default: all time)' -Kind 'Number' -Placeholder '<days>'
            New-OpencodeOption -Tokens @('--tools') -Description 'number of tools to show (default: all)' -Kind 'Number' -Placeholder '<n>'
            New-OpencodeOption -Tokens @('--models') -Description 'show model statistics (default: hidden). Pass a number to show top N, otherwise shows all'
            New-OpencodeOption -Tokens @('--project') -Description 'filter by project (default: all projects, empty string: current project)' -Kind 'String' -Placeholder '<project>'
        ))
        New-OpencodeCommand -Name 'export' -Description 'export session data as JSON' -Options (@($common) + @(
            New-OpencodeOption -Tokens @('--sanitize') -Description 'redact sensitive transcript and file data'
        )) -Positionals @(New-OpencodePositional -Name 'sessionID' -Description 'session id to export' -Placeholder '<session-id>')
        New-OpencodeCommand -Name 'import' -Description 'import session data from JSON file or URL' -Options $common -Positionals @(New-OpencodePositional -Name 'file' -Description 'path to JSON file or share URL' -Kind 'Path')
        New-OpencodeCommand -Name 'github' -Description 'manage GitHub agent' -Options $common -Subcommands @(
            New-OpencodeCommand -Name 'install' -Description 'install the GitHub agent' -Options $common
            New-OpencodeCommand -Name 'run' -Description 'run the GitHub agent' -Options (@($common) + @(
                New-OpencodeOption -Tokens @('--event') -Description 'GitHub mock event to run the agent for' -Kind 'String' -Placeholder '<event>'
                New-OpencodeOption -Tokens @('--token') -Description 'GitHub personal access token (github_pat_********)' -Kind 'String' -Placeholder '<token>'
            ))
        )
        New-OpencodeCommand -Name 'pr' -Description 'fetch and checkout a GitHub PR branch, then run opencode' -Options $common -Positionals @(New-OpencodePositional -Name 'number' -Description 'PR number to checkout')
        New-OpencodeCommand -Name 'session' -Description 'manage sessions' -Options $common -Subcommands @(
            New-OpencodeCommand -Name 'list' -Description 'list sessions' -Options (@($common) + @(
                New-OpencodeOption -Tokens @('-n', '--max-count') -Description 'limit to N most recent sessions' -Kind 'Number' -Placeholder '<n>'
                New-OpencodeOption -Tokens @('--format') -Description 'output format' -Kind 'Enum' -Values @('table', 'json')
            ))
            New-OpencodeCommand -Name 'delete' -Description 'delete a session' -Options $common -Positionals @(New-OpencodePositional -Name 'sessionID' -Description 'session ID to delete' -Placeholder '<session-id>')
        )
        New-OpencodeCommand -Name 'plugin' -Description 'install plugin and update config' -Aliases @('plug') -Options (@($common) + @(
            New-OpencodeOption -Tokens @('-g', '--global') -Description 'install in global config'
            New-OpencodeOption -Tokens @('-f', '--force') -Description 'replace existing plugin version'
        )) -Positionals @(New-OpencodePositional -Name 'module' -Description 'npm module name')
        New-OpencodeCommand -Name 'db' -Description 'database tools' -Options (@($common) + @(
            New-OpencodeOption -Tokens @('--format') -Description 'Output format [default: "tsv"]' -Kind 'Enum' -Values @('json', 'tsv')
        )) -Positionals @(New-OpencodePositional -Name 'query' -Description 'SQL query to execute' -Kind 'Text' -Placeholder '<query>') -Subcommands @(
            New-OpencodeCommand -Name 'path' -Description 'print the database path' -Options $common
        )
    )

    $root = New-OpencodeCommand -Name '' -Description 'start opencode tui' -Options $rootOptions -Positionals @(
        New-OpencodePositional -Name 'project' -Description 'path to start opencode in' -Kind 'Directory'
    ) -Subcommands $commands

    $catalog = @{ Root = $root }
    Set-Variable -Name OpencodeCompletionCatalog -Scope Script -Value $catalog
    $catalog
}

function New-OpencodeCompletionResult {
    param([string]$CompletionText, [string]$ListItemText, [string]$ResultType, [string]$ToolTip)

    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }
    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

function Find-OpencodeSubcommand {
    param([object]$Command, [string]$Token)

    foreach ($subcommand in @($Command.Subcommands)) {
        if ([string]::Equals($subcommand.Name, $Token, [System.StringComparison]::Ordinal)) {
            return $subcommand
        }
        foreach ($alias in @($subcommand.Aliases)) {
            if ([string]::Equals($alias, $Token, [System.StringComparison]::Ordinal)) {
                return $subcommand
            }
        }
    }

    $null
}

function Find-OpencodeOption {
    param([object]$Command, [string]$Token)

    foreach ($option in @($Command.Options)) {
        foreach ($optionToken in @($option.Tokens)) {
            if ([string]::Equals($optionToken, $Token, [System.StringComparison]::Ordinal)) {
                return $option
            }
        }
    }

    $null
}

function Get-OpencodeTokenState {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$WordToComplete
    )

    # Elements that end before the cursor are completed tokens; the element under the cursor is the word being
    # typed, cut at the cursor; anything to the right of the cursor is ignored.
    $tokens = New-Object System.Collections.Generic.List[string]
    $currentWord = ''
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.EndOffset -lt $CursorPosition) {
            $text = if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $element.Value } else { $extent.Text }
            [void]$tokens.Add($text)
            continue
        }

        if ($extent.StartOffset -le $CursorPosition) {
            $currentWord = $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
        break
    }

    if ([string]::IsNullOrEmpty($currentWord) -and -not [string]::IsNullOrEmpty($WordToComplete)) {
        $currentWord = $WordToComplete
    }

    [pscustomobject]@{
        CurrentWord = $currentWord
        Tokens      = @($tokens.ToArray())
    }
}

function Get-OpencodeContext {
    param([string[]]$Tokens)

    $catalog = Get-OpencodeCompletionCatalog
    $command = $catalog.Root
    $pendingOption = $null
    $positionalCount = 0

    foreach ($token in @($Tokens)) {
        if ($null -ne $pendingOption) {
            $pendingOption = $null
            continue
        }

        if ($token.StartsWith('-')) {
            $optionToken = $token
            $attached = $false
            if ($token -match '^(--?[A-Za-z0-9][A-Za-z0-9-]*)=') {
                $optionToken = $matches[1]
                $attached = $true
            }

            $option = Find-OpencodeOption -Command $command -Token $optionToken
            if ($option -and $option.Kind -ne 'Flag' -and -not $attached) {
                $pendingOption = $option
            }
            continue
        }

        if ($positionalCount -eq 0) {
            $subcommand = Find-OpencodeSubcommand -Command $command -Token $token
            if ($subcommand) {
                $command = $subcommand
                continue
            }
        }

        $positionalCount++
    }

    [pscustomobject]@{
        Command         = $command
        PendingOption   = $pendingOption
        PositionalCount = $positionalCount
    }
}

function Get-OpencodePathCompletions {
    param([string]$CurrentWord, [bool]$DirectoryOnly, [string]$InlinePrefix = '')

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($CurrentWord)) {
        if ($DirectoryOnly -and $item.ResultType -ne [System.Management.Automation.CompletionResultType]::ProviderContainer) {
            continue
        }

        [void]$results.Add((New-OpencodeCompletionResult -CompletionText ($InlinePrefix + $item.CompletionText) -ListItemText $item.ListItemText -ResultType $item.ResultType.ToString() -ToolTip $item.ToolTip))
    }

    @($results.ToArray())
}

function Get-OpencodeValueCompletions {
    param([object]$Option, [string]$CurrentWord, [string]$InlinePrefix = '')

    switch ($Option.Kind) {
        'Enum' {
            return @(foreach ($value in @($Option.Values)) {
                if ($value.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-OpencodeCompletionResult -CompletionText ($InlinePrefix + $value) -ListItemText $value -ResultType 'ParameterValue' -ToolTip $Option.Description
                }
            })
        }
        'Path' {
            return @(Get-OpencodePathCompletions -CurrentWord $CurrentWord -DirectoryOnly $false -InlinePrefix $InlinePrefix)
        }
        'Directory' {
            return @(Get-OpencodePathCompletions -CurrentWord $CurrentWord -DirectoryOnly $true -InlinePrefix $InlinePrefix)
        }
        default {
            if (-not [string]::IsNullOrEmpty($CurrentWord)) {
                return @()
            }

            $placeholder = if ($Option.Placeholder) { $Option.Placeholder } else { '<value>' }
            return @(New-OpencodeCompletionResult -CompletionText ($InlinePrefix + $placeholder) -ListItemText $placeholder -ResultType 'ParameterValue' -ToolTip $Option.Description)
        }
    }
}

function Get-OpencodeOptionCompletions {
    param([object]$Command, [string]$CurrentWord)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($option in @($Command.Options)) {
        foreach ($token in @($option.Tokens)) {
            if (-not $token.StartsWith($CurrentWord, [System.StringComparison]::Ordinal)) {
                continue
            }
            if ($seen.Add($token)) {
                New-OpencodeCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $option.Description
            }
        }
    }
}

function Get-OpencodeSubcommandCompletions {
    param([object]$Command, [string]$CurrentWord)

    foreach ($subcommand in @($Command.Subcommands)) {
        if ($subcommand.Name.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-OpencodeCompletionResult -CompletionText $subcommand.Name -ResultType 'ParameterValue' -ToolTip $subcommand.Description
        }
        foreach ($alias in @($subcommand.Aliases)) {
            if ($alias.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                New-OpencodeCompletionResult -CompletionText $alias -ResultType 'ParameterValue' -ToolTip ('alias of {0}: {1}' -f $subcommand.Name, $subcommand.Description)
            }
        }
    }
}

function Get-OpencodePositionalCompletions {
    param([object]$Positional, [string]$CurrentWord)

    switch ($Positional.Kind) {
        'Path' { return @(Get-OpencodePathCompletions -CurrentWord $CurrentWord -DirectoryOnly $false) }
        'Directory' { return @(Get-OpencodePathCompletions -CurrentWord $CurrentWord -DirectoryOnly $true) }
        default {
            if (-not [string]::IsNullOrEmpty($CurrentWord)) {
                return @()
            }

            return @(New-OpencodeCompletionResult -CompletionText $Positional.Placeholder -ResultType 'ParameterValue' -ToolTip $Positional.Description)
        }
    }
}

function Complete-Opencode {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $state = Get-OpencodeTokenState -CommandAst $CommandAst -CursorPosition $CursorPosition -WordToComplete $WordToComplete
    $currentWord = $state.CurrentWord
    $context = Get-OpencodeContext -Tokens $state.Tokens
    $command = $context.Command

    # Attached --option=value form.
    if ($currentWord -match '^(?<name>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = Find-OpencodeOption -Command $command -Token $matches.name
        if ($option -and $option.Kind -ne 'Flag') {
            return @(Get-OpencodeValueCompletions -Option $option -CurrentWord $matches.value -InlinePrefix ($matches.name + '='))
        }

        return @()
    }

    if ($null -ne $context.PendingOption) {
        return @(Get-OpencodeValueCompletions -Option $context.PendingOption -CurrentWord $currentWord)
    }

    if ($currentWord.StartsWith('-')) {
        return @(Get-OpencodeOptionCompletions -Command $command -CurrentWord $currentWord)
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ($context.PositionalCount -eq 0) {
        foreach ($item in @(Get-OpencodeSubcommandCompletions -Command $command -CurrentWord $currentWord)) {
            [void]$results.Add($item)
        }
    }

    $positionals = @($command.Positionals)
    if ($context.PositionalCount -lt $positionals.Count) {
        $positional = $positionals[$context.PositionalCount]
        # The root [project] operand is only offered once a partial path is typed, so a bare 'opencode ' shows commands.
        if (-not ($command.Name -eq '' -and [string]::IsNullOrEmpty($currentWord))) {
            foreach ($item in @(Get-OpencodePositionalCompletions -Positional $positional -CurrentWord $currentWord)) {
                [void]$results.Add($item)
            }
        }
    } elseif ($positionals.Count -gt 0 -and $positionals[-1].Kind -eq 'Text' -and [string]::IsNullOrEmpty($currentWord)) {
        # Variadic free text (run [message..]) keeps accepting words.
        [void]$results.Add((New-OpencodeCompletionResult -CompletionText $positionals[-1].Placeholder -ResultType 'ParameterValue' -ToolTip $positionals[-1].Description))
    }

    if ([string]::IsNullOrEmpty($currentWord) -and $command.Name -ne '') {
        foreach ($item in @(Get-OpencodeOptionCompletions -Command $command -CurrentWord '')) {
            [void]$results.Add($item)
        }
    }

    @($results.ToArray())
}

# Register the completer for both opencode and opencode.exe
# Using a literal script block to satisfy Import-CompleterScript requirements
Register-ArgumentCompleter -Native -CommandName 'opencode', 'opencode.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Opencode -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
