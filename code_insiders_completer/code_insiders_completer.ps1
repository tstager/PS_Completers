<#
.SYNOPSIS
    Registers a native PowerShell argument completer for code-insiders.

.DESCRIPTION
    Provides a hybrid static-first native argument completer for
    `code-insiders` and `code-insiders.cmd`.

    The completer covers:
    - root `code-insiders` options and subcommands
    - nested `tunnel`, `tunnel user`, and `tunnel service` command routing
    - enum-aware value completion for `--log`, `--sync`, `--locate-shell-integration-path`, and `chat --mode`
    - cached local extension ID completion from `--list-extensions`
    - file and directory completion for path-bearing options
    - placeholder-oriented suggestions for free-form values like prompts, JSON, locales, and profiles

    The script is safe to dot-source multiple times and keeps its top level
    compatible with `Import-CompleterScript`.
#>

Set-StrictMode -Version Latest

function New-CodeInsidersCompletionResult {
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

function New-CodeInsidersOptionSpec {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [string[]]$ValueKinds,
        [switch]$OptionalValue
    )

    foreach ($token in @($Tokens)) {
        [pscustomobject]@{
            Token         = $token
            Description   = $Description
            ValueKinds    = @($ValueKinds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            OptionalValue = [bool]$OptionalValue
        }
    }
}

function New-CodeInsidersCommandSpec {
    param(
        [string]$Path,
        [string]$Description,
        [string[]]$Subcommands,
        [object[]]$Options,
        [string[]]$Positionals
    )

    [pscustomobject]@{
        Path        = if ($null -eq $Path) { '' } else { $Path }
        Description = $Description
        Subcommands = @($Subcommands)
        Options     = @($Options)
        Positionals = @($Positionals)
    }
}

function Test-CodeInsidersCacheFresh {
    param(
        [datetime]$LoadedAt,
        [int]$TtlSeconds
    )

    if ($LoadedAt -eq [datetime]::MinValue) {
        return $false
    }

    ((Get-Date) - $LoadedAt).TotalSeconds -lt $TtlSeconds
}

function Get-CodeInsidersUniqueStrings {
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

function Get-CodeInsidersCompletionCache {
    if (-not (Get-Variable -Name CodeInsidersCompletionCache -Scope Script -ErrorAction SilentlyContinue)) {
        $rootOptions = @(
            New-CodeInsidersOptionSpec -Tokens @('-d', '--diff') -Description 'Compare two files with each other.' -ValueKinds @('FilePath', 'FilePath')
            New-CodeInsidersOptionSpec -Tokens @('-m', '--merge') -Description 'Perform a three-way merge.' -ValueKinds @('FilePath', 'FilePath', 'FilePath', 'FilePath')
            New-CodeInsidersOptionSpec -Tokens @('-a', '--add') -Description 'Add folder(s) to the last active window.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--remove') -Description 'Remove folder(s) from the last active window.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('-g', '--goto') -Description 'Open a file at path:line[:character].' -ValueKinds @('GotoTarget')
            New-CodeInsidersOptionSpec -Tokens @('-n', '--new-window') -Description 'Force to open a new window.'
            New-CodeInsidersOptionSpec -Tokens @('-r', '--reuse-window') -Description 'Force to open in an already opened window.'
            New-CodeInsidersOptionSpec -Tokens @('--agents') -Description 'Open the agents window.'
            New-CodeInsidersOptionSpec -Tokens @('-w', '--wait') -Description 'Wait for files to be closed before returning.'
            New-CodeInsidersOptionSpec -Tokens @('--locale') -Description 'The locale to use.' -ValueKinds @('Locale')
            New-CodeInsidersOptionSpec -Tokens @('--user-data-dir') -Description 'Specifies the directory that user data is kept in.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--profile') -Description 'Open with the given profile.' -ValueKinds @('Profile')
            New-CodeInsidersOptionSpec -Tokens @('-h', '--help') -Description 'Print usage.'
            New-CodeInsidersOptionSpec -Tokens @('--extensions-dir') -Description 'Set the root path for extensions.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--list-extensions') -Description 'List the installed extensions.'
            New-CodeInsidersOptionSpec -Tokens @('--show-versions') -Description 'Show versions when using --list-extensions.'
            New-CodeInsidersOptionSpec -Tokens @('--category') -Description 'Filter installed extensions by category.' -ValueKinds @('Category')
            New-CodeInsidersOptionSpec -Tokens @('--install-extension') -Description 'Install or update an extension ID or VSIX path.' -ValueKinds @('InstallExtensionTarget')
            New-CodeInsidersOptionSpec -Tokens @('--pre-release') -Description 'Install the pre-release version when using --install-extension.'
            New-CodeInsidersOptionSpec -Tokens @('--uninstall-extension') -Description 'Uninstall an extension.' -ValueKinds @('InstalledExtensionId')
            New-CodeInsidersOptionSpec -Tokens @('--update-extensions') -Description 'Update installed extensions.'
            New-CodeInsidersOptionSpec -Tokens @('--enable-proposed-api') -Description 'Enable proposed API features for an extension.' -ValueKinds @('InstalledExtensionId')
            New-CodeInsidersOptionSpec -Tokens @('--add-mcp') -Description 'Add a Model Context Protocol server definition JSON.' -ValueKinds @('Json')
            New-CodeInsidersOptionSpec -Tokens @('-v', '--version') -Description 'Print version.'
            New-CodeInsidersOptionSpec -Tokens @('--verbose') -Description 'Print verbose output.'
            New-CodeInsidersOptionSpec -Tokens @('--log') -Description 'Log level to use.' -ValueKinds @('LogLevel')
            New-CodeInsidersOptionSpec -Tokens @('-s', '--status') -Description 'Print process usage and diagnostics information.'
            New-CodeInsidersOptionSpec -Tokens @('--prof-startup') -Description 'Run CPU profiler during startup.'
            New-CodeInsidersOptionSpec -Tokens @('--disable-extensions') -Description 'Disable all installed extensions.'
            New-CodeInsidersOptionSpec -Tokens @('--disable-extension') -Description 'Disable the provided extension.' -ValueKinds @('InstalledExtensionId')
            New-CodeInsidersOptionSpec -Tokens @('--sync') -Description 'Turn sync on or off.' -ValueKinds @('Sync')
            New-CodeInsidersOptionSpec -Tokens @('--inspect-extensions') -Description 'Allow debugging and profiling of extensions.' -ValueKinds @('Port')
            New-CodeInsidersOptionSpec -Tokens @('--inspect-brk-extensions') -Description 'Allow debugging with the extension host paused after start.' -ValueKinds @('Port')
            New-CodeInsidersOptionSpec -Tokens @('--disable-lcd-text') -Description 'Disable LCD font rendering.'
            New-CodeInsidersOptionSpec -Tokens @('--disable-gpu') -Description 'Disable GPU hardware acceleration.'
            New-CodeInsidersOptionSpec -Tokens @('--disable-chromium-sandbox') -Description 'Disable the Chromium sandbox.'
            New-CodeInsidersOptionSpec -Tokens @('--locate-shell-integration-path') -Description 'Print the path to a terminal shell integration script.' -ValueKinds @('Shell')
            New-CodeInsidersOptionSpec -Tokens @('--telemetry') -Description 'Show all telemetry events VS Code collects.'
            New-CodeInsidersOptionSpec -Tokens @('--transient') -Description 'Run with temporary data and extension directories.'
        )

        $chatOptions = @(
            New-CodeInsidersOptionSpec -Tokens @('-m', '--mode') -Description 'Mode to use for the chat session.' -ValueKinds @('ChatMode')
            New-CodeInsidersOptionSpec -Tokens @('-a', '--add-file') -Description 'Add a file as chat context.' -ValueKinds @('FilePath')
            New-CodeInsidersOptionSpec -Tokens @('--maximize') -Description 'Maximize the chat session view.'
            New-CodeInsidersOptionSpec -Tokens @('-r', '--reuse-window') -Description 'Reuse the last active window for the chat session.'
            New-CodeInsidersOptionSpec -Tokens @('-n', '--new-window') -Description 'Force a new empty window for the chat session.'
            New-CodeInsidersOptionSpec -Tokens @('--profile') -Description 'Open with the given profile.' -ValueKinds @('Profile')
        )

        $tunnelRootOptions = @(
            New-CodeInsidersOptionSpec -Tokens @('--install-extension') -Description 'Preload and install extensions on connecting servers.' -ValueKinds @('InstallExtensionTarget')
            New-CodeInsidersOptionSpec -Tokens @('--server-data-dir') -Description 'Specifies the directory that server data is kept in.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--extensions-dir') -Description 'Set the root path for extensions.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--reconnection-grace-time') -Description 'Reconnection grace time in seconds.' -ValueKinds @('Number')
            New-CodeInsidersOptionSpec -Tokens @('--random-name') -Description 'Randomly name the machine.'
            New-CodeInsidersOptionSpec -Tokens @('--no-sleep') -Description 'Prevent the machine from going to sleep.'
            New-CodeInsidersOptionSpec -Tokens @('--name') -Description 'Set the machine name for port forwarding service.' -ValueKinds @('Name')
            New-CodeInsidersOptionSpec -Tokens @('--accept-server-license-terms') -Description 'Accept the server license terms.'
            New-CodeInsidersOptionSpec -Tokens @('-h', '--help') -Description 'Print help.'
            New-CodeInsidersOptionSpec -Tokens @('--cli-data-dir') -Description 'Directory where CLI metadata should be stored.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--verbose') -Description 'Print verbose output.'
            New-CodeInsidersOptionSpec -Tokens @('--log') -Description 'Log level to use.' -ValueKinds @('LogLevel')
        )

        $tunnelUserOptions = @(
            New-CodeInsidersOptionSpec -Tokens @('-h', '--help') -Description 'Print help.'
            New-CodeInsidersOptionSpec -Tokens @('--cli-data-dir') -Description 'Directory where CLI metadata should be stored.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--verbose') -Description 'Print verbose output.'
            New-CodeInsidersOptionSpec -Tokens @('--log') -Description 'Log level to use.' -ValueKinds @('LogLevel')
        )

        $tunnelUserLoginOptions = @(
            New-CodeInsidersOptionSpec -Tokens @('--access-token') -Description 'Access token to store for authentication.' -ValueKinds @('Token')
            New-CodeInsidersOptionSpec -Tokens @('--refresh-token') -Description 'Refresh token to store for authentication.' -ValueKinds @('Token')
            New-CodeInsidersOptionSpec -Tokens @('--provider') -Description 'Authentication provider to use.' -ValueKinds @('AuthProvider')
            New-CodeInsidersOptionSpec -Tokens @('-h', '--help') -Description 'Print help.'
            New-CodeInsidersOptionSpec -Tokens @('--cli-data-dir') -Description 'Directory where CLI metadata should be stored.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--verbose') -Description 'Print verbose output.'
            New-CodeInsidersOptionSpec -Tokens @('--log') -Description 'Log level to use.' -ValueKinds @('LogLevel')
        )

        $tunnelServiceInstallOptions = @(
            New-CodeInsidersOptionSpec -Tokens @('--accept-server-license-terms') -Description 'Accept the server license terms.'
            New-CodeInsidersOptionSpec -Tokens @('--name') -Description 'Set the machine name for the tunnel service.' -ValueKinds @('Name')
            New-CodeInsidersOptionSpec -Tokens @('-h', '--help') -Description 'Print help.'
            New-CodeInsidersOptionSpec -Tokens @('--cli-data-dir') -Description 'Directory where CLI metadata should be stored.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--verbose') -Description 'Print verbose output.'
            New-CodeInsidersOptionSpec -Tokens @('--log') -Description 'Log level to use.' -ValueKinds @('LogLevel')
        )

        $serveWebOptions = @(
            New-CodeInsidersOptionSpec -Tokens @('--host') -Description 'Host to listen on.' -ValueKinds @('Host')
            New-CodeInsidersOptionSpec -Tokens @('--socket-path') -Description 'Socket path to listen on.' -ValueKinds @('FilePath')
            New-CodeInsidersOptionSpec -Tokens @('--port') -Description 'Port to listen on.' -ValueKinds @('Port')
            New-CodeInsidersOptionSpec -Tokens @('--connection-token') -Description 'Secret included with all requests.' -ValueKinds @('Token')
            New-CodeInsidersOptionSpec -Tokens @('--connection-token-file') -Description 'File containing a connection token.' -ValueKinds @('FilePath')
            New-CodeInsidersOptionSpec -Tokens @('--without-connection-token') -Description 'Run without a connection token.'
            New-CodeInsidersOptionSpec -Tokens @('--accept-server-license-terms') -Description 'Accept the server license terms.'
            New-CodeInsidersOptionSpec -Tokens @('--server-base-path') -Description 'Path under which the web UI and server are provided.' -ValueKinds @('ServerBasePath')
            New-CodeInsidersOptionSpec -Tokens @('--server-data-dir') -Description 'Specifies the directory that server data is kept in.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--default-folder') -Description 'Workspace folder to open by default.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--default-workspace') -Description 'Workspace file to open by default.' -ValueKinds @('FilePath')
            New-CodeInsidersOptionSpec -Tokens @('--disable-telemetry') -Description 'Disable telemetry.'
            New-CodeInsidersOptionSpec -Tokens @('--commit-id') -Description 'Use a specific commit SHA for the client.' -ValueKinds @('CommitId')
            New-CodeInsidersOptionSpec -Tokens @('-h', '--help') -Description 'Print help.'
            New-CodeInsidersOptionSpec -Tokens @('--cli-data-dir') -Description 'Directory where CLI metadata should be stored.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--verbose') -Description 'Print verbose output.'
            New-CodeInsidersOptionSpec -Tokens @('--log') -Description 'Log level to use.' -ValueKinds @('LogLevel')
        )

        $agentHostOptions = @(
            New-CodeInsidersOptionSpec -Tokens @('--host') -Description 'Host to listen on.' -ValueKinds @('Host')
            New-CodeInsidersOptionSpec -Tokens @('--port') -Description 'Port to listen on.' -ValueKinds @('Port')
            New-CodeInsidersOptionSpec -Tokens @('--connection-token') -Description 'Secret included with all requests.' -ValueKinds @('Token')
            New-CodeInsidersOptionSpec -Tokens @('--connection-token-file') -Description 'File containing a connection token.' -ValueKinds @('FilePath')
            New-CodeInsidersOptionSpec -Tokens @('--without-connection-token') -Description 'Run without a connection token.'
            New-CodeInsidersOptionSpec -Tokens @('--accept-server-license-terms') -Description 'Accept the server license terms.'
            New-CodeInsidersOptionSpec -Tokens @('--server-data-dir') -Description 'Specifies the directory that server data is kept in.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('-h', '--help') -Description 'Print help.'
            New-CodeInsidersOptionSpec -Tokens @('--cli-data-dir') -Description 'Directory where CLI metadata should be stored.' -ValueKinds @('DirectoryPath')
            New-CodeInsidersOptionSpec -Tokens @('--verbose') -Description 'Print verbose output.'
            New-CodeInsidersOptionSpec -Tokens @('--log') -Description 'Log level to use.' -ValueKinds @('LogLevel')
        )

        $commandSpecs = @(
            New-CodeInsidersCommandSpec -Path '' -Description 'Visual Studio Code - Insiders CLI.' -Subcommands @('chat', 'serve-web', 'agent-host', 'tunnel') -Options $rootOptions -Positionals @('RootInput')
            New-CodeInsidersCommandSpec -Path 'chat' -Description 'Run a chat session in the current working directory.' -Subcommands @() -Options $chatOptions -Positionals @('Prompt')
            New-CodeInsidersCommandSpec -Path 'serve-web' -Description 'Run a local web version of Visual Studio Code - Insiders.' -Subcommands @() -Options $serveWebOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'agent-host' -Description 'Run a local agent host server.' -Subcommands @() -Options $agentHostOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel' -Description 'Create a tunnel that is accessible from vscode.dev.' -Subcommands @('prune', 'kill', 'restart', 'status', 'rename', 'unregister', 'user', 'service', 'help') -Options $tunnelRootOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel prune' -Description 'Delete all servers that are not currently running.' -Subcommands @() -Options $tunnelRootOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel kill' -Description 'Stop any running tunnel on the system.' -Subcommands @() -Options $tunnelRootOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel restart' -Description 'Restart any running tunnel on the system.' -Subcommands @() -Options $tunnelRootOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel status' -Description 'Get whether a tunnel is running on the current machine.' -Subcommands @() -Options $tunnelRootOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel rename' -Description 'Rename this machine for the port forwarding service.' -Subcommands @() -Options $tunnelRootOptions -Positionals @('Name')
            New-CodeInsidersCommandSpec -Path 'tunnel unregister' -Description 'Remove this machine association from the port forwarding service.' -Subcommands @() -Options $tunnelRootOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel help' -Description 'Print tunnel help.' -Subcommands @() -Options @() -Positionals @('TunnelSubcommand')
            New-CodeInsidersCommandSpec -Path 'tunnel user' -Description 'Manage tunnel user authentication.' -Subcommands @('login', 'logout', 'show', 'help') -Options $tunnelUserOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel user login' -Description 'Log in to the port forwarding service.' -Subcommands @() -Options $tunnelUserLoginOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel user logout' -Description 'Log out of the port forwarding service.' -Subcommands @() -Options $tunnelUserOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel user show' -Description 'Show the logged-in tunnel account.' -Subcommands @() -Options $tunnelUserOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel user help' -Description 'Print tunnel user help.' -Subcommands @() -Options @() -Positionals @('TunnelUserSubcommand')
            New-CodeInsidersCommandSpec -Path 'tunnel service' -Description 'Manage the tunnel service.' -Subcommands @('install', 'uninstall', 'log', 'help') -Options $tunnelUserOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel service install' -Description 'Install or reinstall the tunnel service.' -Subcommands @() -Options $tunnelServiceInstallOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel service uninstall' -Description 'Uninstall and stop the tunnel service.' -Subcommands @() -Options $tunnelUserOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel service log' -Description 'Show logs for the running tunnel service.' -Subcommands @() -Options $tunnelUserOptions -Positionals @()
            New-CodeInsidersCommandSpec -Path 'tunnel service help' -Description 'Print tunnel service help.' -Subcommands @() -Options @() -Positionals @('TunnelServiceSubcommand')
        )

        $specLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($spec in $commandSpecs) {
            $specLookup[$spec.Path] = $spec
        }

        $script:CodeInsidersCompletionCache = @{
            SpecLookup              = $specLookup
            RuntimeCacheTtlSeconds  = 120
            CommandPath             = $null
            CommandPathProbed       = $false
            ExtensionIds            = @()
            ExtensionIdsLoadedAt    = [datetime]::MinValue
        }
    }

    $script:CodeInsidersCompletionCache
}

function Resolve-CodeInsidersCommandName {
    $cache = Get-CodeInsidersCompletionCache
    if ($cache.CommandPathProbed) {
        return $cache.CommandPath
    }

    $cache.CommandPathProbed = $true
    $cache.CommandPath = $null

    foreach ($name in @('code-insiders.cmd', 'code-insiders')) {
        $command = Get-Command -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            $cache.CommandPath = if ($command.Source) { $command.Source } else { $command.Name }
            break
        }
    }

    $cache.CommandPath
}

function Invoke-CodeInsidersCapture {
    param([string[]]$Arguments)

    $commandName = Resolve-CodeInsidersCommandName
    if ([string]::IsNullOrWhiteSpace($commandName)) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>$null)
    } catch {
        @()
    }
}

function Remove-CodeInsidersOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-CodeInsidersQuotedValue {
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

function Test-CodeInsidersPathLikeInput {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $cleanValue = Remove-CodeInsidersOuterQuotes -Value $Value
    $cleanValue -match '^(?:\.{1,2}[\\/]|[\\/]|~[\\/]|[A-Za-z]:|\\\\)'
}

function Get-CodeInsidersTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-CodeInsidersArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += Get-CodeInsidersTokenText -Element $element
        }
    }

    $tokens
}

function Get-CodeInsidersCommandSpec {
    param([string]$PathKey)

    $cache = Get-CodeInsidersCompletionCache
    if ($cache.SpecLookup.ContainsKey($PathKey)) {
        return $cache.SpecLookup[$PathKey]
    }

    $null
}

function Find-CodeInsidersOptionSpec {
    param(
        [string]$PathKey,
        [string]$Token
    )

    $spec = Get-CodeInsidersCommandSpec -PathKey $PathKey
    foreach ($option in @($spec.Options)) {
        if ($option.Token.Equals($Token, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $option
        }
    }

    $null
}

function Get-CodeInsidersExtensionIds {
    $cache = Get-CodeInsidersCompletionCache
    if (Test-CodeInsidersCacheFresh -LoadedAt $cache.ExtensionIdsLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.ExtensionIds
    }

    $cache.ExtensionIds = Get-CodeInsidersUniqueStrings -Items (
        Invoke-CodeInsidersCapture -Arguments @('--list-extensions') |
            ForEach-Object {
                $trimmed = $_.Trim()
                if ($trimmed -match '^[A-Za-z0-9][A-Za-z0-9._-]*\.[A-Za-z0-9][A-Za-z0-9._-]*$') {
                    $trimmed
                }
            }
    )
    $cache.ExtensionIdsLoadedAt = Get-Date
    $cache.ExtensionIds
}

function Get-CodeInsidersCommandState {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $currentToken = if ($CursorPosition -gt $CommandAst.Extent.EndOffset) { '' } else { $WordToComplete }
    $tokens = Get-CodeInsidersArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition

    $pathTokens = New-Object System.Collections.Generic.List[string]
    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingValue = $null
    $afterDoubleDash = $false
    $pathKey = ''

    foreach ($token in @($tokens)) {
        if ($afterDoubleDash) {
            [void]$positionals.Add($token)
            continue
        }

        if ($pendingValue) {
            $nextIndex = $pendingValue.ValueIndex + 1
            if ($nextIndex -lt $pendingValue.Option.ValueKinds.Count) {
                $pendingValue = [pscustomobject]@{
                    Option     = $pendingValue.Option
                    ValueIndex = $nextIndex
                }
            } else {
                $pendingValue = $null
            }
            continue
        }

        if ($token -eq '--') {
            $afterDoubleDash = $true
            continue
        }

        if ($token -match '^(?<option>--[A-Za-z0-9-]+)=(?<value>.*)$') {
            $option = Find-CodeInsidersOptionSpec -PathKey $pathKey -Token $matches['option']
            if ($option) {
                continue
            }
        }

        if ($token.StartsWith('-') -and $token -ne '-') {
            $option = Find-CodeInsidersOptionSpec -PathKey $pathKey -Token $token
            if ($option) {
                if ($option.ValueKinds.Count -gt 0 -and -not $option.OptionalValue) {
                    $pendingValue = [pscustomobject]@{
                        Option     = $option
                        ValueIndex = 0
                    }
                }
                continue
            }
        }

        if ($pathTokens.Count -eq 0) {
            $rootSpec = Get-CodeInsidersCommandSpec -PathKey ''
            if ($rootSpec.Subcommands -contains $token) {
                [void]$pathTokens.Add($token)
                $pathKey = $token
                continue
            }
        } else {
            $currentSpec = Get-CodeInsidersCommandSpec -PathKey $pathKey
            if ($currentSpec -and $currentSpec.Subcommands -contains $token) {
                [void]$pathTokens.Add($token)
                $pathKey = [string]::Join(' ', $pathTokens)
                continue
            }
        }

        [void]$positionals.Add($token)
    }

    [pscustomobject]@{
        PathKey       = $pathKey
        CurrentToken  = $currentToken
        Positionals   = @($positionals.ToArray())
        PendingValue  = $pendingValue
        AfterDoubleDash = $afterDoubleDash
    }
}

function Get-CodeInsidersPathCompletions {
    param(
        [string]$InputPath,
        [string]$Prefix = '',
        [switch]$DirectoriesOnly,
        [switch]$FilesOnly
    )

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and $InputPath.StartsWith('"')

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput.EndsWith('\') -or $cleanInput.EndsWith('/')) {
        $parent = $cleanInput
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
    } elseif ($FilesOnly) {
        $items = @($items | Where-Object { -not $_.PSIsContainer })
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

        $completionText = ConvertTo-CodeInsidersQuotedValue -Value $completionText -AlwaysQuote $alwaysQuote
        $completionText = $Prefix + $completionText

        New-CodeInsidersCompletionResult -CompletionText $completionText -ToolTip $item.FullName -ListItemText $item.Name
    }
}

function New-CodeInsidersLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-CodeInsidersCompletionResult -CompletionText ($Prefix + $Placeholder) -ToolTip $ToolTip -ListItemText $Placeholder
        )
    }

    @(
        New-CodeInsidersCompletionResult -CompletionText ($Prefix + $CurrentValue) -ToolTip $ToolTip -ListItemText $CurrentValue
    )
}

function Get-CodeInsidersDistinctResults {
    param([object[]]$Results)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($result in @($Results)) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.Add($result.CompletionText)) {
            $result
        }
    }
}

function Get-CodeInsidersStringValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [switch]$SuggestWhenEmpty,
        [string]$Prefix = ''
    )

    $typedValue = Remove-CodeInsidersOuterQuotes -Value $CurrentValue
    $results = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrWhiteSpace($typedValue)) {
        if ($Placeholder) {
            [void]$results.Add((New-CodeInsidersCompletionResult -CompletionText ($Prefix + $Placeholder) -ToolTip $ToolTip -ListItemText $Placeholder))
        }

        if ($SuggestWhenEmpty) {
            foreach ($value in @($Values)) {
                if ([string]::IsNullOrWhiteSpace($value)) {
                    continue
                }
                [void]$results.Add((New-CodeInsidersCompletionResult -CompletionText ($Prefix + $value) -ToolTip $ToolTip -ListItemText $value))
            }
        }

        return @(Get-CodeInsidersDistinctResults -Results @($results.ToArray()))
    }

    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }

        if ($value.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-CodeInsidersCompletionResult -CompletionText ($Prefix + $value) -ToolTip $ToolTip -ListItemText $value))
        }
    }

    @(Get-CodeInsidersDistinctResults -Results @($results.ToArray()))
}

function Get-CodeInsidersLogLevelResults {
    param([string]$CurrentValue)

    $levels = @('critical', 'error', 'warn', 'info', 'debug', 'trace', 'off')
    $value = Remove-CodeInsidersOuterQuotes -Value $CurrentValue
    if ($value -match '^(?<extension>[^:]+):(?<level>.*)$') {
        $extensionPrefix = $matches['extension']
        $levelPrefix = $matches['level']
        $results = foreach ($extensionId in @(Get-CodeInsidersExtensionIds)) {
            if ($extensionId.StartsWith($extensionPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                foreach ($level in @($levels)) {
                    if ($level.StartsWith($levelPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                        New-CodeInsidersCompletionResult -CompletionText ($extensionId + ':' + $level) -ToolTip 'Extension-specific log level.'
                    }
                }
            }
        }
        return @(Get-CodeInsidersDistinctResults -Results $results)
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($result in @(Get-CodeInsidersStringValueResults -Values $levels -CurrentValue $CurrentValue -Placeholder '<publisher.name:level>' -ToolTip 'Log level.' -SuggestWhenEmpty)) {
        [void]$results.Add($result)
    }
    @(Get-CodeInsidersDistinctResults -Results @($results.ToArray()))
}

function Get-CodeInsidersInstallExtensionResults {
    param([string]$CurrentValue)

    $value = Remove-CodeInsidersOuterQuotes -Value $CurrentValue
    if ([string]::IsNullOrWhiteSpace($value)) {
        return New-CodeInsidersLiteralValueResults -CurrentValue '' -Placeholder '<ext-id-or-path>' -ToolTip 'Extension ID or path to a VSIX.'
    }

    if (Test-CodeInsidersPathLikeInput -Value $value -or $value -like '*.vsix*') {
        return Get-CodeInsidersPathCompletions -InputPath $CurrentValue -FilesOnly
    }

    if ($value -match '^(?<extension>[^@]+)@(?<version>.*)$') {
        $extensionPrefix = $matches['extension']
        $version = $matches['version']
        $results = foreach ($extensionId in @(Get-CodeInsidersExtensionIds)) {
            if ($extensionId.StartsWith($extensionPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                New-CodeInsidersCompletionResult -CompletionText ($extensionId + '@' + $version) -ToolTip 'Extension ID with version suffix.'
            }
        }
        return @(Get-CodeInsidersDistinctResults -Results $results)
    }

    Get-CodeInsidersStringValueResults -Values (Get-CodeInsidersExtensionIds) -CurrentValue $CurrentValue -Placeholder '<ext-id-or-path>' -ToolTip 'Installed extension ID or VSIX path.'
}

function Get-CodeInsidersGotoResults {
    param([string]$CurrentValue)

    $value = Remove-CodeInsidersOuterQuotes -Value $CurrentValue
    if ([string]::IsNullOrWhiteSpace($value)) {
        return Get-CodeInsidersPathCompletions -InputPath '' -FilesOnly
    }

    if (Test-CodeInsidersPathLikeInput -Value $value -and $value -notmatch ':\d') {
        return Get-CodeInsidersPathCompletions -InputPath $CurrentValue -FilesOnly
    }

    New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<file:line[:character]>' -ToolTip 'File path with optional line and character.'
}

function Get-CodeInsidersRootInputResults {
    param([string]$CurrentValue)

    if ($CurrentValue -eq '-') {
        return @(
            New-CodeInsidersCompletionResult -CompletionText '-' -ToolTip 'Read input from stdin.' -ListItemText '-'
        )
    }

    if (Test-CodeInsidersPathLikeInput -Value $CurrentValue) {
        return Get-CodeInsidersPathCompletions -InputPath $CurrentValue
    }

    $results = @()
    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        $results += New-CodeInsidersCompletionResult -CompletionText '-' -ToolTip 'Read input from stdin.' -ListItemText '-'
        $results += New-CodeInsidersCompletionResult -CompletionText '<path>' -ToolTip 'Open a file or folder path.' -ListItemText '<path>'
        return $results
    }

    New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<path>' -ToolTip 'Open a file or folder path.'
}

function Get-CodeInsidersValueResults {
    param(
        [string]$ValueKind,
        [string]$CurrentValue,
        [pscustomobject]$State,
        [string]$Prefix = ''
    )

    switch ($ValueKind) {
        'RootInput' { return Get-CodeInsidersRootInputResults -CurrentValue $CurrentValue }
        'FilePath' {
            if ([string]::IsNullOrWhiteSpace($CurrentValue) -or (Test-CodeInsidersPathLikeInput -Value $CurrentValue)) {
                return Get-CodeInsidersPathCompletions -InputPath $CurrentValue -FilesOnly -Prefix $Prefix
            }
            return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<file>' -ToolTip 'File path.' -Prefix $Prefix
        }
        'DirectoryPath' {
            if ([string]::IsNullOrWhiteSpace($CurrentValue) -or (Test-CodeInsidersPathLikeInput -Value $CurrentValue)) {
                return Get-CodeInsidersPathCompletions -InputPath $CurrentValue -DirectoriesOnly -Prefix $Prefix
            }
            return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<dir>' -ToolTip 'Directory path.' -Prefix $Prefix
        }
        'GotoTarget' { return Get-CodeInsidersGotoResults -CurrentValue $CurrentValue }
        'Profile' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<profile>' -ToolTip 'Profile name.' -Prefix $Prefix }
        'Locale' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<locale>' -ToolTip 'Locale such as en-US or zh-TW.' -Prefix $Prefix }
        'Category' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<category>' -ToolTip 'Extension category filter.' -Prefix $Prefix }
        'Json' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '{"name":"server-name","command":...}' -ToolTip 'MCP server definition JSON.' -Prefix $Prefix }
        'InstalledExtensionId' { return Get-CodeInsidersStringValueResults -Values (Get-CodeInsidersExtensionIds) -CurrentValue $CurrentValue -Placeholder '<ext-id>' -ToolTip 'Installed extension ID.' -SuggestWhenEmpty -Prefix $Prefix }
        'InstallExtensionTarget' { return Get-CodeInsidersInstallExtensionResults -CurrentValue $CurrentValue }
        'LogLevel' { return Get-CodeInsidersLogLevelResults -CurrentValue $CurrentValue }
        'AuthProvider' { return Get-CodeInsidersStringValueResults -Values @('microsoft', 'github') -CurrentValue $CurrentValue -Placeholder $null -ToolTip 'Authentication provider.' -SuggestWhenEmpty -Prefix $Prefix }
        'Sync' { return Get-CodeInsidersStringValueResults -Values @('on', 'off') -CurrentValue $CurrentValue -Placeholder $null -ToolTip 'Sync state.' -SuggestWhenEmpty -Prefix $Prefix }
        'Shell' { return Get-CodeInsidersStringValueResults -Values @('bash', 'pwsh', 'zsh', 'fish') -CurrentValue $CurrentValue -Placeholder $null -ToolTip 'Shell integration script target.' -SuggestWhenEmpty -Prefix $Prefix }
        'ChatMode' {
            $results = New-Object System.Collections.Generic.List[object]
            foreach ($result in @(Get-CodeInsidersStringValueResults -Values @('ask', 'edit', 'agent') -CurrentValue $CurrentValue -Placeholder '<custom-mode>' -ToolTip 'Chat mode identifier.' -SuggestWhenEmpty -Prefix $Prefix)) {
                [void]$results.Add($result)
            }
            return @(Get-CodeInsidersDistinctResults -Results @($results.ToArray()))
        }
        'Prompt' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<prompt>' -ToolTip 'Chat prompt text.' -Prefix $Prefix }
        'Host' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<host>' -ToolTip 'Hostname or IP address.' -Prefix $Prefix }
        'Port' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<port>' -ToolTip 'Port number.' -Prefix $Prefix }
        'Token' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<token>' -ToolTip 'Secret token value.' -Prefix $Prefix }
        'ServerBasePath' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<base-path>' -ToolTip 'Server base path.' -Prefix $Prefix }
        'CommitId' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<commit-id>' -ToolTip 'Commit SHA.' -Prefix $Prefix }
        'Number' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<number>' -ToolTip 'Numeric value.' -Prefix $Prefix }
        'Name' { return New-CodeInsidersLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<name>' -ToolTip 'Name value.' -Prefix $Prefix }
        'TunnelSubcommand' { return Get-CodeInsidersStringValueResults -Values @('prune', 'kill', 'restart', 'status', 'rename', 'unregister', 'user', 'service', 'help') -CurrentValue $CurrentValue -Placeholder '<subcommand>' -ToolTip 'Tunnel subcommand.' -SuggestWhenEmpty -Prefix $Prefix }
        'TunnelUserSubcommand' { return Get-CodeInsidersStringValueResults -Values @('login', 'logout', 'show', 'help') -CurrentValue $CurrentValue -Placeholder '<subcommand>' -ToolTip 'Tunnel user subcommand.' -SuggestWhenEmpty -Prefix $Prefix }
        'TunnelServiceSubcommand' { return Get-CodeInsidersStringValueResults -Values @('install', 'uninstall', 'log', 'help') -CurrentValue $CurrentValue -Placeholder '<subcommand>' -ToolTip 'Tunnel service subcommand.' -SuggestWhenEmpty -Prefix $Prefix }
        default { return @() }
    }
}

function Write-CodeInsidersSubcommandResults {
    param(
        [string]$PathKey,
        [string]$CurrentToken
    )

    $spec = Get-CodeInsidersCommandSpec -PathKey $PathKey
    foreach ($subcommand in @($spec.Subcommands)) {
        if ([string]::IsNullOrWhiteSpace($CurrentToken) -or $subcommand.StartsWith($CurrentToken, [System.StringComparison]::OrdinalIgnoreCase)) {
            $childPath = if ([string]::IsNullOrWhiteSpace($PathKey)) { $subcommand } else { $PathKey + ' ' + $subcommand }
            $childSpec = Get-CodeInsidersCommandSpec -PathKey $childPath
            $toolTip = if ($childSpec) { $childSpec.Description } else { $subcommand }
            New-CodeInsidersCompletionResult -CompletionText $subcommand -ToolTip $toolTip -ListItemText $subcommand
        }
    }
}

function Write-CodeInsidersOptionResults {
    param(
        [string]$PathKey,
        [string]$CurrentToken
    )

    $spec = Get-CodeInsidersCommandSpec -PathKey $PathKey
    foreach ($option in @($spec.Options)) {
        if ([string]::IsNullOrWhiteSpace($CurrentToken) -or $option.Token.StartsWith($CurrentToken, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-CodeInsidersCompletionResult -CompletionText $option.Token -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $option.Token
        }
    }
}

function Write-CodeInsidersOperandResults {
    param([pscustomobject]$State)

    $spec = Get-CodeInsidersCommandSpec -PathKey $State.PathKey
    if (-not $spec) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($subcommandResult in @(Write-CodeInsidersSubcommandResults -PathKey $State.PathKey -CurrentToken $State.CurrentToken)) {
        [void]$results.Add($subcommandResult)
    }

    if ($spec.Positionals.Count -eq 0) {
        return @(Get-CodeInsidersDistinctResults -Results @($results.ToArray()))
    }

    $positionIndex = $State.Positionals.Count
    if ($positionIndex -ge $spec.Positionals.Count) {
        $positionIndex = $spec.Positionals.Count - 1
    }

    if ($positionIndex -ge 0) {
        foreach ($valueResult in @(Get-CodeInsidersValueResults -ValueKind $spec.Positionals[$positionIndex] -CurrentValue $State.CurrentToken -State $State)) {
            [void]$results.Add($valueResult)
        }
    }

    @(Get-CodeInsidersDistinctResults -Results @($results.ToArray()))
}

function Complete-CodeInsidersNative {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $state = Get-CodeInsidersCommandState -WordToComplete $WordToComplete -CommandAst $CommandAst -CursorPosition $CursorPosition

    if ($state.CurrentToken -match '^(?<option>--[A-Za-z0-9-]+)=(?<value>.*)$') {
        $inlineOption = Find-CodeInsidersOptionSpec -PathKey $state.PathKey -Token $matches['option']
        if ($inlineOption -and $inlineOption.ValueKinds.Count -eq 1) {
            return Get-CodeInsidersValueResults -ValueKind $inlineOption.ValueKinds[0] -CurrentValue $matches['value'] -State $state -Prefix ($matches['option'] + '=')
        }
    }

    if ($state.PendingValue) {
        return Get-CodeInsidersValueResults -ValueKind $state.PendingValue.Option.ValueKinds[$state.PendingValue.ValueIndex] -CurrentValue $state.CurrentToken -State $state
    }

    if ($state.CurrentToken.StartsWith('-') -and -not $state.AfterDoubleDash) {
        return @(Get-CodeInsidersDistinctResults -Results @(Write-CodeInsidersOptionResults -PathKey $state.PathKey -CurrentToken $state.CurrentToken))
    }

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($operandResult in @(Write-CodeInsidersOperandResults -State $state)) {
        [void]$results.Add($operandResult)
    }

    if ([string]::IsNullOrWhiteSpace($state.CurrentToken)) {
        foreach ($optionResult in @(Write-CodeInsidersOptionResults -PathKey $state.PathKey -CurrentToken '')) {
            [void]$results.Add($optionResult)
        }
    }

    @(Get-CodeInsidersDistinctResults -Results @($results.ToArray()))
}

Register-ArgumentCompleter -Native -CommandName @('code-insiders', 'code-insiders.cmd') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-CodeInsidersNative -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
