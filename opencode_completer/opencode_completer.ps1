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
        New-OpencodeOption -Tokens @('-s', '--session') -Description 'session id to continue' -Kind 'Session' -Placeholder '<session-id>'
        New-OpencodeOption -Tokens @('--fork') -Description 'fork the session when continuing (use with --continue or --session)'
    )
    $model = New-OpencodeOption -Tokens @('-m', '--model') -Description 'model to use in the format of provider/model' -Kind 'Model' -Placeholder '<provider/model>'
    $agent = New-OpencodeOption -Tokens @('--agent') -Description 'agent to use' -Kind 'Agent' -Placeholder '<agent>'
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
            New-OpencodeCommand -Name 'auth' -Description 'authenticate with an OAuth-enabled MCP server' -Options $common -Positionals @(New-OpencodePositional -Name 'name' -Description 'name of the MCP server' -Kind 'Mcp') -Subcommands @(
                New-OpencodeCommand -Name 'list' -Description 'list OAuth-capable MCP servers and their auth status' -Aliases @('ls') -Options $common
            )
            New-OpencodeCommand -Name 'logout' -Description 'remove OAuth credentials for an MCP server' -Options $common -Positionals @(New-OpencodePositional -Name 'name' -Description 'name of the MCP server' -Kind 'McpCredential')
            New-OpencodeCommand -Name 'debug' -Description 'debug OAuth connection for an MCP server' -Options $common -Positionals @(New-OpencodePositional -Name 'name' -Description 'name of the MCP server' -Kind 'Mcp')
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
            )) -Positionals @(New-OpencodePositional -Name 'name' -Description 'Agent name' -Kind 'Agent')
            New-OpencodeCommand -Name 'v2' -Description 'debug v2 catalog and built-in plugins' -Options $common
            New-OpencodeCommand -Name 'info' -Description 'show debug information' -Options $common
            New-OpencodeCommand -Name 'paths' -Description 'show global paths (data, config, cache, state)' -Options $common
            New-OpencodeCommand -Name 'wait' -Description 'wait indefinitely (for debugging)' -Options $common
        )
        New-OpencodeCommand -Name 'providers' -Description 'manage AI providers and credentials' -Aliases @('auth') -Options $common -Subcommands @(
            New-OpencodeCommand -Name 'list' -Description 'list providers and credentials' -Aliases @('ls') -Options $common
            New-OpencodeCommand -Name 'login' -Description 'log in to a provider' -Options (@($common) + @(
                New-OpencodeOption -Tokens @('-p', '--provider') -Description 'provider id or name to log in to (skips provider selection)' -Kind 'ProviderAll' -Placeholder '<provider>'
                New-OpencodeOption -Tokens @('-m', '--method') -Description 'login method label (skips method selection)' -Kind 'String' -Placeholder '<method>'
            )) -Positionals @(New-OpencodePositional -Name 'url' -Description 'opencode auth provider')
            New-OpencodeCommand -Name 'logout' -Description 'log out from a configured provider' -Options $common -Positionals @(New-OpencodePositional -Name 'provider' -Description 'provider id or name to log out from' -Kind 'Credential')
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
        )) -Positionals @(New-OpencodePositional -Name 'provider' -Description 'provider ID to filter models by' -Kind 'Provider')
        New-OpencodeCommand -Name 'stats' -Description 'show token usage and cost statistics' -Options (@($common) + @(
            New-OpencodeOption -Tokens @('--days') -Description 'show stats for the last N days (default: all time)' -Kind 'Number' -Placeholder '<days>'
            New-OpencodeOption -Tokens @('--tools') -Description 'number of tools to show (default: all)' -Kind 'Number' -Placeholder '<n>'
            New-OpencodeOption -Tokens @('--models') -Description 'show model statistics (default: hidden). Pass a number to show top N, otherwise shows all'
            New-OpencodeOption -Tokens @('--project') -Description 'filter by project (default: all projects, empty string: current project)' -Kind 'String' -Placeholder '<project>'
        ))
        New-OpencodeCommand -Name 'export' -Description 'export session data as JSON' -Options (@($common) + @(
            New-OpencodeOption -Tokens @('--sanitize') -Description 'redact sensitive transcript and file data'
        )) -Positionals @(New-OpencodePositional -Name 'sessionID' -Description 'session id to export' -Kind 'Session' -Placeholder '<session-id>')
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
            New-OpencodeCommand -Name 'delete' -Description 'delete a session' -Options $common -Positionals @(New-OpencodePositional -Name 'sessionID' -Description 'session ID to delete' -Kind 'Session' -Placeholder '<session-id>')
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

# Live identifier sources. Everything except session IDs is read passively from opencode's own files; session IDs
# live only in its SQLite database, which is queried through 'opencode db' (no instance bootstrap, so no project
# registration or plugin load) with models.dev fetching and auto-update disabled.
function Get-OpencodeDynamicCache {
    $existing = Get-Variable -Name OpencodeDynamicCache -Scope Script -ErrorAction Ignore
    if ($existing) {
        return $existing.Value
    }

    $cache = @{}
    Set-Variable -Name OpencodeDynamicCache -Scope Script -Value $cache
    $cache
}

function Get-OpencodeBaseDirectory {
    param([ValidateSet('config', 'data', 'cache')][string]$Kind)

    # opencode follows the XDG base directories on every platform, defaulting under the user profile.
    $variable, $default = switch ($Kind) {
        'config' { 'XDG_CONFIG_HOME', '.config' }
        'data' { 'XDG_DATA_HOME', [System.IO.Path]::Combine('.local', 'share') }
        'cache' { 'XDG_CACHE_HOME', '.cache' }
    }
    $base = [System.Environment]::GetEnvironmentVariable($variable)
    if ([string]::IsNullOrEmpty($base)) {
        $base = [System.IO.Path]::Combine([System.Environment]::GetFolderPath('UserProfile'), $default)
    }

    [System.IO.Path]::Combine($base, 'opencode')
}

function Get-OpencodeFileStamp {
    param([string[]]$Path)

    @(foreach ($item in $Path) {
        $info = [System.IO.FileInfo]::new($item)
        if ($info.Exists) { '{0}:{1}' -f $info.LastWriteTimeUtc.Ticks, $info.Length } else { '-' }
    }) -join '|'
}

function ConvertFrom-OpencodeJson {
    param([string]$Text, [string]$Path)

    if (-not $Path -and [string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
    $options.AllowTrailingCommas = $true
    $errorCountBefore = $Error.Count
    try {
        $document = if ($Path) {
            # UTF-8 bytes parse several times faster than a string; skip a BOM, which the byte parser rejects.
            $bytes = [System.IO.File]::ReadAllBytes($Path)
            $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
            [System.Text.Json.JsonDocument]::Parse([System.ReadOnlyMemory[byte]]::new($bytes, $offset, $bytes.Length - $offset), $options)
        } else {
            [System.Text.Json.JsonDocument]::Parse($Text, $options)
        }
        try {
            return $document.RootElement.Clone()
        } finally {
            $document.Dispose()
        }
    } catch {
        return $null
    } finally {
        # A config file mid-edit or locked is an expected miss, not a fault to leave in $Error.
        while ($Error.Count -gt $errorCountBefore) {
            $Error.RemoveAt(0)
        }
    }
}

function Read-OpencodeJsonFile {
    param([string]$Path)

    $stamp = Get-OpencodeFileStamp -Path $Path
    if ($stamp -eq '-') {
        return $null
    }

    $cache = Get-OpencodeDynamicCache
    $key = 'json|' + $Path
    $entry = $cache[$key]
    if ($null -eq $entry -or $entry.Stamp -ne $stamp) {
        $entry = @{ Stamp = $stamp; Root = (ConvertFrom-OpencodeJson -Path $Path) }
        $cache[$key] = $entry
    }

    $entry.Root
}

function Get-OpencodeJsonMember {
    param([object]$Element, [string]$Name)

    if ($null -eq $Element -or $Element.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
        return $null
    }

    $value = [System.Text.Json.JsonElement]::new()
    if ($Element.TryGetProperty($Name, [ref]$value)) {
        return $value
    }

    $null
}

function Get-OpencodeJsonName {
    param([object]$Element)

    if ($null -eq $Element -or $Element.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
        return
    }

    foreach ($property in $Element.EnumerateObject()) {
        $property.Name
    }
}

function Get-OpencodeJsonString {
    param([object]$Element)

    if ($null -eq $Element) {
        return
    }

    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
        return $Element.GetString()
    }

    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) {
            if ($item.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
                $item.GetString()
            }
        }
    }
}

function Test-OpencodeJsonTrue {
    param([object]$Element, [string]$Name)

    $value = Get-OpencodeJsonMember -Element $Element -Name $Name
    $null -ne $value -and $value.ValueKind -eq [System.Text.Json.JsonValueKind]::True
}

function Get-OpencodeProjectInfo {
    # Directories from the current location up to the git worktree root (or the drive root outside git), nearest first.
    $location = (Get-Location -PSProvider FileSystem).ProviderPath
    $directories = New-Object System.Collections.Generic.List[string]
    $root = ''
    $directory = $location
    while (-not [string]::IsNullOrEmpty($directory)) {
        [void]$directories.Add($directory)
        $gitPath = [System.IO.Path]::Combine($directory, '.git')
        if ([System.IO.Directory]::Exists($gitPath) -or [System.IO.File]::Exists($gitPath)) {
            $root = $directory
            break
        }
        $directory = [System.IO.Path]::GetDirectoryName($directory)
    }

    [pscustomobject]@{
        Root        = $root
        Directories = @($directories.ToArray())
    }
}

function Get-OpencodeConfigSource {
    # Config directories (agent/mode markdown) and config files, lowest precedence first, as opencode resolves them.
    $project = Get-OpencodeProjectInfo
    $globalDirectory = Get-OpencodeBaseDirectory -Kind config
    $directories = New-Object System.Collections.Generic.List[string]
    $files = New-Object System.Collections.Generic.List[string]

    [void]$directories.Add($globalDirectory)
    foreach ($name in @('config.json', 'opencode.json', 'opencode.jsonc')) {
        [void]$files.Add([System.IO.Path]::Combine($globalDirectory, $name))
    }
    if ($env:OPENCODE_CONFIG) {
        [void]$files.Add($env:OPENCODE_CONFIG)
    }

    if (-not $env:OPENCODE_DISABLE_PROJECT_CONFIG) {
        $rootFirst = @($project.Directories)
        [array]::Reverse($rootFirst)
        foreach ($directory in $rootFirst) {
            foreach ($name in @('opencode.json', 'opencode.jsonc')) {
                [void]$files.Add([System.IO.Path]::Combine($directory, $name))
            }
        }
        foreach ($directory in $rootFirst) {
            $dotDirectory = [System.IO.Path]::Combine($directory, '.opencode')
            if ([System.IO.Directory]::Exists($dotDirectory)) {
                [void]$directories.Add($dotDirectory)
            }
        }
    }

    $homeDirectory = [System.IO.Path]::Combine([System.Environment]::GetFolderPath('UserProfile'), '.opencode')
    if ([System.IO.Directory]::Exists($homeDirectory) -and -not $directories.Contains($homeDirectory)) {
        [void]$directories.Add($homeDirectory)
    }
    if ($env:OPENCODE_CONFIG_DIR -and [System.IO.Directory]::Exists($env:OPENCODE_CONFIG_DIR)) {
        [void]$directories.Add($env:OPENCODE_CONFIG_DIR)
    }

    foreach ($directory in @($directories.ToArray() | Select-Object -Skip 1)) {
        foreach ($name in @('opencode.json', 'opencode.jsonc')) {
            [void]$files.Add([System.IO.Path]::Combine($directory, $name))
        }
    }

    [pscustomobject]@{
        Project     = $project
        Directories = @($directories.ToArray())
        Stamp       = ($files -join '|') + '#' + (Get-OpencodeFileStamp -Path $files.ToArray())
        Configs     = @(foreach ($file in $files) {
            $root = Read-OpencodeJsonFile -Path $file
            if ($null -ne $root -and $root.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) { $root }
        })
    }
}

function ConvertFrom-OpencodeTypedWord {
    # The value of a typed word and the quote it opens with ('' when bare). A word opened with a quote (ASCII or
    # typographic) is read by the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Word)

    if ($Word -notmatch '^[''"\u2018-\u201E]') {
        return [pscustomobject]@{ Value = $Word; Quote = '' }
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Word, [ref]$tokens, [ref]$parseErrors)
    [pscustomobject]@{ Value = $tokens[0].Value; Quote = $Word.Substring(0, 1) }
}

function ConvertTo-OpencodeQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed, otherwise in the quote the
    # user typed (single by default). PowerShell reads ' and U+2018-U+201B as single quotes and " and U+201C-U+201E
    # as double quotes.
    param([string]$Value, [string]$QuoteCharacter)

    if (-not $QuoteCharacter) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }

        $QuoteCharacter = "'"
    }

    if ($QuoteCharacter -match '^[''\u2018-\u201B]$') {
        return $QuoteCharacter + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteCharacter
    }

    $QuoteCharacter + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteCharacter
}

function Get-OpencodeAgentValue {
    $source = Get-OpencodeConfigSource
    $agents = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($builtIn in @(
            @('build', 'built-in primary agent (default)'), @('plan', 'built-in primary agent (read-only planning)'),
            @('general', 'built-in subagent'), @('explore', 'built-in subagent'),
            @('compaction', 'built-in hidden agent'), @('summary', 'built-in hidden agent'), @('title', 'built-in hidden agent'))) {
        $agents[$builtIn[0]] = [pscustomobject]@{ Value = $builtIn[0]; ToolTip = $builtIn[1] }
    }

    # Markdown agents: {agent,agents}/**/*.md named by their relative path, {mode,modes}/*.md as primary agents.
    foreach ($directory in $source.Directories) {
        foreach ($folder in @('agent', 'agents', 'mode', 'modes')) {
            $folderPath = [System.IO.Path]::Combine($directory, $folder)
            if (-not [System.IO.Directory]::Exists($folderPath)) {
                continue
            }

            $recurse = $folder -like 'agent*'
            foreach ($file in @(Get-ChildItem -LiteralPath $folderPath -Filter '*.md' -File -Recurse:$recurse -ErrorAction Ignore)) {
                $relative = [System.IO.Path]::GetRelativePath($folderPath, $file.FullName).Replace('\', '/')
                $name = $relative.Substring(0, $relative.Length - $file.Extension.Length)
                $head = @(Get-Content -LiteralPath $file.FullName -TotalCount 40 -ErrorAction Ignore)
                $disabled = $false
                if ($head.Count -gt 0 -and $head[0].Trim() -eq '---') {
                    foreach ($line in @($head | Select-Object -Skip 1)) {
                        if ($line.Trim() -eq '---') { break }
                        if ($line -match '^\s*disable\s*:\s*true\s*$') { $disabled = $true }
                    }
                }

                if ($disabled) {
                    [void]$agents.Remove($name)
                } else {
                    $agents[$name] = [pscustomobject]@{ Value = $name; ToolTip = "agent from $($file.FullName)" }
                }
            }
        }
    }

    foreach ($config in $source.Configs) {
        foreach ($section in @('mode', 'agent')) {
            $block = Get-OpencodeJsonMember -Element $config -Name $section
            foreach ($name in @(Get-OpencodeJsonName -Element $block)) {
                if (Test-OpencodeJsonTrue -Element (Get-OpencodeJsonMember -Element $block -Name $name) -Name 'disable') {
                    [void]$agents.Remove($name)
                } elseif (-not $agents.ContainsKey($name)) {
                    $agents[$name] = [pscustomobject]@{ Value = $name; ToolTip = "agent from the '$section' config block" }
                }
            }
        }
    }

    @($agents.Values | Sort-Object -Property Value)
}

function Get-OpencodeCatalogIndex {
    # models.dev providers from opencode's on-disk cache, re-indexed only when the file changes.
    $path = [System.IO.Path]::Combine((Get-OpencodeBaseDirectory -Kind cache), 'models.json')
    $stamp = Get-OpencodeFileStamp -Path $path
    $cache = Get-OpencodeDynamicCache
    $entry = $cache['catalog']
    if ($null -eq $entry -or $entry.Stamp -ne $stamp) {
        $catalog = Read-OpencodeJsonFile -Path $path
        $entry = @{
            Stamp     = $stamp
            Providers = @(foreach ($id in @(Get-OpencodeJsonName -Element $catalog)) {
                $provider = Get-OpencodeJsonMember -Element $catalog -Name $id
                [pscustomobject]@{
                    Id     = $id
                    Name   = @(Get-OpencodeJsonString -Element (Get-OpencodeJsonMember -Element $provider -Name 'name')) | Select-Object -First 1
                    Env    = @(Get-OpencodeJsonString -Element (Get-OpencodeJsonMember -Element $provider -Name 'env'))
                    Models = Get-OpencodeJsonMember -Element $provider -Name 'models'
                }
            })
        }
        $cache['catalog'] = $entry
    }

    $entry
}

function Get-OpencodeProviderState {
    # Mirrors opencode's provider loading: a models.dev provider is usable when one of its env vars is set, it has
    # stored credentials or a config block; 'opencode' is always usable (only its free models without a key).
    $source = Get-OpencodeConfigSource
    $index = Get-OpencodeCatalogIndex
    $authPath = [System.IO.Path]::Combine((Get-OpencodeBaseDirectory -Kind data), 'auth.json')
    $setVariables = @(foreach ($provider in $index.Providers) {
        foreach ($variable in $provider.Env) {
            if ([System.Environment]::GetEnvironmentVariable($variable)) { $variable }
        }
    })
    $signature = @($source.Stamp, $index.Stamp, (Get-OpencodeFileStamp -Path $authPath), ($setVariables -join ','), [string]$env:OPENCODE_ENABLE_EXPERIMENTAL_MODELS) -join '#'
    $cache = Get-OpencodeDynamicCache
    $entry = $cache['providers']
    if ($null -ne $entry -and $entry.Signature -eq $signature) {
        return $entry
    }

    $credentials = [System.Collections.Generic.HashSet[string]]::new([string[]]@(Get-OpencodeCredentialName -Store 'auth.json'), [System.StringComparer]::Ordinal)
    $variablesSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$setVariables, [System.StringComparer]::Ordinal)
    $disabled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $enabled = $null
    $configured = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($config in $source.Configs) {
        foreach ($id in @(Get-OpencodeJsonString -Element (Get-OpencodeJsonMember -Element $config -Name 'disabled_providers'))) {
            [void]$disabled.Add($id)
        }
        $enabledList = Get-OpencodeJsonMember -Element $config -Name 'enabled_providers'
        if ($null -ne $enabledList) {
            $enabled = [System.Collections.Generic.HashSet[string]]::new([string[]]@(Get-OpencodeJsonString -Element $enabledList), [System.StringComparer]::Ordinal)
        }
        $providerBlock = Get-OpencodeJsonMember -Element $config -Name 'provider'
        foreach ($id in @(Get-OpencodeJsonName -Element $providerBlock)) {
            $configured[$id] = Get-OpencodeJsonMember -Element $providerBlock -Name $id
        }
    }

    $providers = [System.Collections.Generic.SortedDictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($provider in $index.Providers) {
        $hasEnv = @($provider.Env | Where-Object { $variablesSet.Contains($_) }).Count -gt 0
        $providers[$provider.Id] = [pscustomobject]@{ Id = $provider.Id; Name = $provider.Name; Models = $provider.Models; HasEnv = $hasEnv; Config = $null }
    }
    foreach ($id in $configured.Keys) {
        if (-not $providers.ContainsKey($id)) {
            $name = @(Get-OpencodeJsonString -Element (Get-OpencodeJsonMember -Element $configured[$id] -Name 'name')) | Select-Object -First 1
            $providers[$id] = [pscustomobject]@{ Id = $id; Name = $name; Models = $null; HasEnv = $false; Config = $null }
        }
        $providers[$id].Config = $configured[$id]
    }

    $experimental = [bool]$env:OPENCODE_ENABLE_EXPERIMENTAL_MODELS
    $providerValues = New-Object System.Collections.Generic.List[object]
    $connectedValues = New-Object System.Collections.Generic.List[object]
    $modelValues = New-Object System.Collections.Generic.List[object]
    foreach ($provider in $providers.Values) {
        $label = if ($provider.Name) { "$($provider.Name) ($($provider.Id))" } else { $provider.Id }
        $value = [pscustomobject]@{ Value = $provider.Id; ToolTip = $label }
        [void]$providerValues.Add($value)

        $allowed = -not $disabled.Contains($provider.Id) -and ($null -eq $enabled -or $enabled.Contains($provider.Id))
        $apiKey = Get-OpencodeJsonMember -Element (Get-OpencodeJsonMember -Element $provider.Config -Name 'options') -Name 'apiKey'
        $hasKey = $provider.HasEnv -or $credentials.Contains($provider.Id) -or $null -ne $apiKey
        if (-not ($allowed -and ($hasKey -or $null -ne $provider.Config -or $provider.Id -eq 'opencode'))) {
            continue
        }
        [void]$connectedValues.Add($value)

        $freeOnly = $provider.Id -eq 'opencode' -and -not $hasKey
        $models = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
        foreach ($id in @(Get-OpencodeJsonName -Element $provider.Models)) {
            $model = Get-OpencodeJsonMember -Element $provider.Models -Name $id
            $status = @(Get-OpencodeJsonString -Element (Get-OpencodeJsonMember -Element $model -Name 'status')) | Select-Object -First 1
            if ($status -eq 'deprecated' -or ($status -eq 'alpha' -and -not $experimental)) {
                continue
            }
            if ($freeOnly) {
                $inputCost = Get-OpencodeJsonMember -Element (Get-OpencodeJsonMember -Element $model -Name 'cost') -Name 'input'
                if ($null -ne $inputCost -and $inputCost.ValueKind -eq [System.Text.Json.JsonValueKind]::Number -and $inputCost.GetDouble() -gt 0) {
                    continue
                }
            }
            $models[$id] = @(Get-OpencodeJsonString -Element (Get-OpencodeJsonMember -Element $model -Name 'name')) | Select-Object -First 1
        }

        $configModels = Get-OpencodeJsonMember -Element $provider.Config -Name 'models'
        foreach ($id in @(Get-OpencodeJsonName -Element $configModels)) {
            $models[$id] = @(Get-OpencodeJsonString -Element (Get-OpencodeJsonMember -Element (Get-OpencodeJsonMember -Element $configModels -Name $id) -Name 'name')) | Select-Object -First 1
        }

        $whitelist = Get-OpencodeJsonMember -Element $provider.Config -Name 'whitelist'
        $allowList = @(Get-OpencodeJsonString -Element $whitelist)
        $blockList = @(Get-OpencodeJsonString -Element (Get-OpencodeJsonMember -Element $provider.Config -Name 'blacklist'))
        foreach ($id in $models.Keys) {
            if ($blockList -ccontains $id -or ($null -ne $whitelist -and $allowList -cnotcontains $id)) {
                continue
            }
            $modelLabel = if ($models[$id]) { $models[$id] } else { $id }
            [void]$modelValues.Add([pscustomobject]@{ Value = "$($provider.Id)/$id"; ToolTip = "$modelLabel ($($provider.Id))" })
        }
    }

    $entry = @{
        Signature = $signature
        All       = @($providerValues.ToArray())
        Connected = @($connectedValues.ToArray())
        Models    = @($modelValues.ToArray())
    }
    $cache['providers'] = $entry
    $entry
}

function Get-OpencodeCredentialName {
    param([ValidateSet('auth.json', 'mcp-auth.json')][string]$Store)

    # Only the top-level names are kept; the parsed document (with the secrets) is dropped right away.
    $path = [System.IO.Path]::Combine((Get-OpencodeBaseDirectory -Kind data), $Store)
    $stamp = Get-OpencodeFileStamp -Path $path
    $cache = Get-OpencodeDynamicCache
    $key = 'credential|' + $path
    $entry = $cache[$key]
    if ($null -eq $entry -or $entry.Stamp -ne $stamp) {
        $root = if ($stamp -ne '-') { ConvertFrom-OpencodeJson -Path $path }
        $entry = @{ Stamp = $stamp; Names = @(Get-OpencodeJsonName -Element $root | Sort-Object) }
        $cache[$key] = $entry
    }

    $entry.Names
}

function Get-OpencodeCredentialValue {
    param([ValidateSet('auth.json', 'mcp-auth.json')][string]$Store)

    foreach ($name in @(Get-OpencodeCredentialName -Store $Store)) {
        [pscustomobject]@{ Value = $name; ToolTip = "stored credentials ($Store)" }
    }
}

function Get-OpencodeMcpValue {
    $servers = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($config in (Get-OpencodeConfigSource).Configs) {
        $block = Get-OpencodeJsonMember -Element $config -Name 'mcp'
        foreach ($name in @(Get-OpencodeJsonName -Element $block)) {
            $type = @(Get-OpencodeJsonString -Element (Get-OpencodeJsonMember -Element (Get-OpencodeJsonMember -Element $block -Name $name) -Name 'type')) | Select-Object -First 1
            $servers[$name] = if ($type) { "$type MCP server" } else { 'MCP server' }
        }
    }

    foreach ($name in $servers.Keys) {
        [pscustomobject]@{ Value = $name; ToolTip = $servers[$name] }
    }
}

function Get-OpencodeExecutable {
    $cache = Get-OpencodeDynamicCache
    $key = 'exe|' + $env:PATH
    if (-not $cache.ContainsKey($key)) {
        # The engine API resolves in ~50 ms; the first Get-Command of a session costs about a second.
        $command = $ExecutionContext.InvokeCommand.GetCommand('opencode', [System.Management.Automation.CommandTypes]::Application)
        $cache[$key] = if ($command) { $command.Source } else { '' }
    }

    $cache[$key]
}

function Invoke-OpencodeDatabaseQuery {
    param([string]$Executable, [string]$Query)

    # 'opencode db <query>' only opens the database; a missing query would start an interactive sqlite3 shell.
    $output = ''
    $process = [System.Diagnostics.Process]::new()
    $errorCountBefore = $Error.Count
    try {
        $info = [System.Diagnostics.ProcessStartInfo]::new($Executable)
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $info.Environment['NO_COLOR'] = '1'
        $info.Environment['OPENCODE_DISABLE_MODELS_FETCH'] = '1'
        $info.Environment['OPENCODE_DISABLE_AUTOUPDATE'] = '1'
        foreach ($argument in @('db', $Query, '--format', 'json')) {
            [void]$info.ArgumentList.Add($argument)
        }
        $process.StartInfo = $info
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        [void]$process.StandardError.ReadToEndAsync()
        if ($process.WaitForExit(5000)) {
            $output = $stdout.GetAwaiter().GetResult()
        } else {
            $process.Kill($true)
        }
    } catch {
        $output = ''
    } finally {
        $process.Dispose()
        while ($Error.Count -gt $errorCountBefore) {
            $Error.RemoveAt(0)
        }
    }

    [regex]::Replace($output, '\x1b\[[0-9;?]*[ -/]*[@-~]', '')
}

function Get-OpencodeSessionValue {
    $executable = Get-OpencodeExecutable
    $database = [System.IO.Path]::Combine((Get-OpencodeBaseDirectory -Kind data), 'opencode.db')
    if ([string]::IsNullOrEmpty($executable) -or -not [System.IO.File]::Exists($database)) {
        return
    }

    # Same set as 'opencode session list': root sessions of the current project, newest first. Inside git the
    # project is the one whose worktree is the repository root; outside git it is the shared 'global' project.
    $root = (Get-OpencodeProjectInfo).Root
    $cache = Get-OpencodeDynamicCache
    $key = 'session|' + $executable + '|' + $root
    $stampPaths = @($database, ($database + '-wal'))
    $entry = $cache[$key]
    if ($null -ne $entry -and ($entry.Stamp -eq (Get-OpencodeFileStamp -Path $stampPaths) -or ([datetime]::UtcNow - $entry.Time).TotalSeconds -lt 30)) {
        return $entry.Values
    }

    $projectFilter = if ($root) {
        "project_id in (select id from project where lower(worktree) = lower('{0}'))" -f $root.Replace('\', '/').Replace("'", "''")
    } else {
        "project_id = 'global'"
    }
    $query = "select id, title, time_updated from session where parent_id is null and $projectFilter order by time_updated desc limit 50"
    $rows = ConvertFrom-OpencodeJson -Text (Invoke-OpencodeDatabaseQuery -Executable $executable -Query $query)
    $values = @(if ($null -ne $rows -and $rows.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($row in $rows.EnumerateArray()) {
            $id = @(Get-OpencodeJsonString -Element (Get-OpencodeJsonMember -Element $row -Name 'id')) | Select-Object -First 1
            if ([string]::IsNullOrEmpty($id)) {
                continue
            }
            $title = @(Get-OpencodeJsonString -Element (Get-OpencodeJsonMember -Element $row -Name 'title')) | Select-Object -First 1
            $updated = Get-OpencodeJsonMember -Element $row -Name 'time_updated'
            $when = if ($null -ne $updated -and $updated.ValueKind -eq [System.Text.Json.JsonValueKind]::Number) {
                [System.DateTimeOffset]::FromUnixTimeMilliseconds($updated.GetInt64()).LocalDateTime.ToString('yyyy-MM-dd HH:mm')
            }
            [pscustomobject]@{ Value = $id; ToolTip = (@($title, $when) | Where-Object { $_ }) -join ' - ' }
        }
    })

    # The stamp is taken after the query: opening the database touches its timestamp.
    $cache[$key] = @{ Stamp = (Get-OpencodeFileStamp -Path $stampPaths); Time = [datetime]::UtcNow; Values = $values }
    $values
}

function Get-OpencodeDynamicCompletion {
    param([string]$Kind, [string]$CurrentWord, [string]$InlinePrefix = '')

    $values = switch ($Kind) {
        'Session' { Get-OpencodeSessionValue }
        'Agent' { Get-OpencodeAgentValue }
        'Model' { (Get-OpencodeProviderState).Models }
        'Provider' { (Get-OpencodeProviderState).Connected }
        'ProviderAll' { (Get-OpencodeProviderState).All }
        'Credential' { Get-OpencodeCredentialValue -Store 'auth.json' }
        'McpCredential' { Get-OpencodeCredentialValue -Store 'mcp-auth.json' }
        'Mcp' { Get-OpencodeMcpValue }
        default { return }
    }

    # Match on the typed word's value and keep the user's opening quote character when emitting.
    $typed = ConvertFrom-OpencodeTypedWord -Word $CurrentWord
    $quote = $typed.Quote
    $prefix = $typed.Value

    foreach ($value in @($values)) {
        if ($value.Value.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-OpencodeCompletionResult -CompletionText ($InlinePrefix + (ConvertTo-OpencodeQuotedValue -Value $value.Value -QuoteCharacter $quote)) -ListItemText $value.Value -ResultType 'ParameterValue' -ToolTip $value.ToolTip
        }
    }
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

    # CompleteFilename quotes for PowerShell and wildcard-escapes for -Path parameters (tick````x.txt inside single
    # quotes). opencode takes literal paths, so each result is unwrapped by the parser and unescaped, then quoted once
    # in the style the user typed.
    $quote = (ConvertFrom-OpencodeTypedWord -Word $CurrentWord).Quote
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($CurrentWord)) {
        if ($DirectoryOnly -and $item.ResultType -ne [System.Management.Automation.CompletionResultType]::ProviderContainer) {
            continue
        }

        $path = $item.CompletionText
        if ($path -match '^[''"\u2018-\u201E]') {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($path, [ref]$null, [ref]$null)
            $constant = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
            if ($constant) {
                $path = $constant.Value
            }
        }

        $path = [System.Management.Automation.WildcardPattern]::Unescape($path)
        $completionText = $InlinePrefix + (ConvertTo-OpencodeQuotedValue -Value $path -QuoteCharacter $quote)
        [void]$results.Add((New-OpencodeCompletionResult -CompletionText $completionText -ListItemText $item.ListItemText -ResultType $item.ResultType.ToString() -ToolTip $item.ToolTip))
    }

    @($results.ToArray())
}

function Get-OpencodeValueCompletions {
    param([object]$Option, [string]$CurrentWord, [string]$InlinePrefix = '')

    $dynamic = @(Get-OpencodeDynamicCompletion -Kind $Option.Kind -CurrentWord $CurrentWord -InlinePrefix $InlinePrefix)
    if ($dynamic.Count -gt 0) {
        return $dynamic
    }

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

    $dynamic = @(Get-OpencodeDynamicCompletion -Kind $Positional.Kind -CurrentWord $CurrentWord)
    if ($dynamic.Count -gt 0) {
        return $dynamic
    }

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
