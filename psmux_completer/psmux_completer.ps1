Set-StrictMode -Version 2.0

function New-PsmuxCompletionResult {
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

function New-PsmuxOptionSpec {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [string]$ValueKind
    )

    [pscustomobject]@{
        Tokens      = @($Tokens)
        Description = $Description
        ValueKind   = $ValueKind
    }
}

function New-PsmuxCommandSpec {
    param(
        [string]$Path,
        [string]$Description,
        [string[]]$Subcommands,
        [object[]]$Options,
        [string[]]$Positionals
    )

    [pscustomobject]@{
        Path        = $Path
        Description = $Description
        Subcommands = @($Subcommands)
        Options     = @($Options)
        Positionals = @($Positionals)
    }
}

function Get-PsmuxAliasMap {
    @{
        'new'            = 'new-session'
        'a'              = 'attach-session'
        'at'             = 'attach-session'
        'attach'         = 'attach-session'
        'attach-session' = 'attach-session'
        'ls'             = 'list-sessions'
        'list-sessions'  = 'list-sessions'
        'has'            = 'has-session'
        'has-session'    = 'has-session'
        'kill-ses'       = 'kill-session'
        'kill-session'   = 'kill-session'
        'rename'         = 'rename-session'
        'rename-session' = 'rename-session'
        'switchc'        = 'switch-client'
        'switch-client'  = 'switch-client'
        'lsc'            = 'list-clients'
        'list-clients'   = 'list-clients'
        'info'           = 'server-info'
        'server-info'    = 'server-info'
        'neww'           = 'new-window'
        'new-window'     = 'new-window'
        'killw'          = 'kill-window'
        'kill-window'    = 'kill-window'
        'renamew'        = 'rename-window'
        'rename-window'  = 'rename-window'
        'selectw'        = 'select-window'
        'select-window'  = 'select-window'
        'next'           = 'next-window'
        'next-window'    = 'next-window'
        'prev'           = 'previous-window'
        'previous-window'= 'previous-window'
        'last'           = 'last-window'
        'last-window'    = 'last-window'
        'movew'          = 'move-window'
        'move-window'    = 'move-window'
        'swapw'          = 'swap-window'
        'swap-window'    = 'swap-window'
        'findw'          = 'find-window'
        'find-window'    = 'find-window'
        'linkw'          = 'link-window'
        'link-window'    = 'link-window'
        'unlinkw'        = 'unlink-window'
        'unlink-window'  = 'unlink-window'
        'lsw'            = 'list-windows'
        'list-windows'   = 'list-windows'
        'splitw'         = 'split-window'
        'split-window'   = 'split-window'
        'killp'          = 'kill-pane'
        'kill-pane'      = 'kill-pane'
        'selectp'        = 'select-pane'
        'select-pane'    = 'select-pane'
        'resizep'        = 'resize-pane'
        'resize-pane'    = 'resize-pane'
        'swapp'          = 'swap-pane'
        'swap-pane'      = 'swap-pane'
        'joinp'          = 'join-pane'
        'join-pane'      = 'join-pane'
        'breakp'         = 'break-pane'
        'break-pane'     = 'break-pane'
        'rotatew'        = 'rotate-window'
        'rotate-window'  = 'rotate-window'
        'displayp'       = 'display-panes'
        'display-panes'  = 'display-panes'
        'zoom-pane'      = 'zoom-pane'
        'respawnp'       = 'respawn-pane'
        'respawn-pane'   = 'respawn-pane'
        'pipep'          = 'pipe-pane'
        'pipe-pane'      = 'pipe-pane'
        'lsp'            = 'list-panes'
        'list-panes'     = 'list-panes'
        'capturep'       = 'capture-pane'
        'capture-pane'   = 'capture-pane'
        'copy-mode'      = 'copy-mode'
        'setb'           = 'set-buffer'
        'set-buffer'     = 'set-buffer'
        'pasteb'         = 'paste-buffer'
        'paste-buffer'   = 'paste-buffer'
        'lsb'            = 'list-buffers'
        'list-buffers'   = 'list-buffers'
        'showb'          = 'show-buffer'
        'show-buffer'    = 'show-buffer'
        'deleteb'        = 'delete-buffer'
        'delete-buffer'  = 'delete-buffer'
        'chooseb'        = 'choose-buffer'
        'choose-buffer'  = 'choose-buffer'
        'saveb'          = 'save-buffer'
        'save-buffer'    = 'save-buffer'
        'loadb'          = 'load-buffer'
        'load-buffer'    = 'load-buffer'
        'clearhist'      = 'clear-history'
        'clear-history'  = 'clear-history'
        'bind'           = 'bind-key'
        'bind-key'       = 'bind-key'
        'unbind'         = 'unbind-key'
        'unbind-key'     = 'unbind-key'
        'lsk'            = 'list-keys'
        'list-keys'      = 'list-keys'
        'send'           = 'send-keys'
        'send-keys'      = 'send-keys'
        'set'            = 'set-option'
        'set-option'     = 'set-option'
        'show'           = 'show-options'
        'show-options'   = 'show-options'
        'showw'          = 'show-window-options'
        'show-window-options' = 'show-window-options'
        'source'         = 'source-file'
        'source-file'    = 'source-file'
        'setenv'         = 'set-environment'
        'set-environment'= 'set-environment'
        'showenv'        = 'show-environment'
        'show-environment' = 'show-environment'
        'set-hook'       = 'set-hook'
        'show-hooks'     = 'show-hooks'
        'lscm'           = 'list-commands'
        'list-commands'  = 'list-commands'
        'selectl'        = 'select-layout'
        'select-layout'  = 'select-layout'
        'next-layout'    = 'next-layout'
        'previous-layout'= 'previous-layout'
        'display'        = 'display-message'
        'display-message'= 'display-message'
        'menu'           = 'display-menu'
        'display-menu'   = 'display-menu'
        'popup'          = 'display-popup'
        'display-popup'  = 'display-popup'
        'confirm'        = 'confirm-before'
        'confirm-before' = 'confirm-before'
        'clock-mode'     = 'clock-mode'
        'run'            = 'run-shell'
        'run-shell'      = 'run-shell'
        'if'             = 'if-shell'
        'if-shell'       = 'if-shell'
        'wait'           = 'wait-for'
        'wait-for'       = 'wait-for'
        'help'           = 'help'
        'version'        = 'version'
    }
}

function Get-PsmuxRootSubcommands {
    [string[]](Get-PsmuxAliasMap).Keys | Sort-Object -Unique
}

function Get-PsmuxOptionNames {
    @(
        'prefix', 'base-index', 'pane-base-index', 'escape-time', 'repeat-time', 'history-limit',
        'display-time', 'display-panes-time', 'status-interval', 'mouse', 'status', 'status-position',
        'focus-events', 'mode-keys', 'renumber-windows', 'automatic-rename', 'monitor-activity',
        'monitor-silence', 'synchronize-panes', 'remain-on-exit', 'aggressive-resize', 'set-titles',
        'set-titles-string', 'default-shell', 'default-command', 'word-separators',
        'prediction-dimming', 'cursor-style', 'cursor-blink', 'bell-action', 'visual-bell',
        'status-left', 'status-right', 'status-style', 'status-bg', 'status-fg', 'status-left-style',
        'status-right-style', 'status-justify', 'message-style', 'message-command-style',
        'mode-style', 'pane-border-style', 'pane-active-border-style', 'pane-border-hover-style',
        'window-status-format', 'window-status-current-format', 'window-status-separator',
        'window-status-style', 'window-status-current-style', 'window-status-activity-style',
        'window-status-bell-style', 'window-status-last-style'
    )
}

function Get-PsmuxLayoutSuggestions {
    @('even-horizontal', 'even-vertical', 'main-horizontal', 'main-vertical', 'tiled')
}

function Get-PsmuxEnvVarSuggestions {
    @('PSMUX_SESSION_NAME', 'PSMUX_DEFAULT_SESSION', 'PSMUX_CURSOR_STYLE', 'PSMUX_CURSOR_BLINK', 'PSMUX_DIM_PREDICTIONS', 'TMUX', 'TMUX_PANE')
}

function Get-PsmuxKeySuggestions {
    @('Enter', 'Escape', 'Tab', 'Space', 'Up', 'Down', 'Left', 'Right', 'Home', 'End', 'C-c', 'C-d')
}

function Get-PsmuxHookSuggestions {
    @('session-created', 'session-closed', 'window-linked', 'window-renamed', 'pane-died')
}

function Get-PsmuxTargetSuggestions {
    $suggestions = @(':1', ':2.1', '%1', '%2', '@1', '@2', 'default', 'work')
    $suggestions + (Get-PsmuxSessionSuggestions)
}

function Get-PsmuxSessionSuggestions {
    $command = Get-Command -Name psmux.exe, psmux -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return @()
    }

    try {
        @(
            & $command.Source ls 2>$null |
                ForEach-Object {
                    if ($_ -match '^\s*([A-Za-z0-9_.-]+)') { $matches[1] }
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
    } catch {
        @()
    }
}

function Get-PsmuxCommandSpecs {
    @(
        New-PsmuxCommandSpec -Path '' -Description 'psmux root command.' -Subcommands (Get-PsmuxRootSubcommands) -Options @(
            New-PsmuxOptionSpec -Tokens @('-f') -Description 'Use a configuration file.' -ValueKind 'Path'
            New-PsmuxOptionSpec -Tokens @('-L') -Description 'Server socket name.' -ValueKind 'Name'
            New-PsmuxOptionSpec -Tokens @('-S') -Description 'Server socket path.' -ValueKind 'Path'
            New-PsmuxOptionSpec -Tokens @('-t') -Description 'Target session, window, or pane.' -ValueKind 'Target'
            New-PsmuxOptionSpec -Tokens @('-h', '--help') -Description 'Show help.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-V', '--version') -Description 'Show version.' -ValueKind $null
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'new-session' -Description 'Create a new session.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-s') -Description 'Session name.' -ValueKind 'SessionName'
            New-PsmuxOptionSpec -Tokens @('-d') -Description 'Start detached.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-n') -Description 'Initial window name.' -ValueKind 'WindowName'
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'attach-session' -Description 'Attach to a session.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-t') -Description 'Target session name.' -ValueKind 'SessionTarget'
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'has-session' -Description 'Check if a session exists.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-t') -Description 'Target session name.' -ValueKind 'SessionTarget'
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'kill-session' -Description 'Kill a session.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-t') -Description 'Target session name.' -ValueKind 'SessionTarget'
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'rename-session' -Description 'Rename the current session.' -Subcommands @() -Options @() -Positionals @('SessionName')
        New-PsmuxCommandSpec -Path 'switch-client' -Description 'Switch to another session.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-t') -Description 'Target session name.' -ValueKind 'SessionTarget'
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'new-window' -Description 'Create a new window.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-n') -Description 'Window name.' -ValueKind 'WindowName'
            New-PsmuxOptionSpec -Tokens @('-d') -Description 'Create detached.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-c') -Description 'Start directory.' -ValueKind 'Path'
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'rename-window' -Description 'Rename the current window.' -Subcommands @() -Options @() -Positionals @('WindowName')
        New-PsmuxCommandSpec -Path 'select-window' -Description 'Select a window by index.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-t') -Description 'Target window index.' -ValueKind 'Index'
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'find-window' -Description 'Find a window by name.' -Subcommands @() -Options @() -Positionals @('Query')
        New-PsmuxCommandSpec -Path 'list-windows' -Description 'List windows in a session.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-t') -Description 'Target session/window.' -ValueKind 'Target'
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'split-window' -Description 'Split the current pane.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-h') -Description 'Split horizontally.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-v') -Description 'Split vertically.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-p') -Description 'Pane size percentage.' -ValueKind 'Percent'
            New-PsmuxOptionSpec -Tokens @('-c') -Description 'Start directory.' -ValueKind 'Path'
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'select-pane' -Description 'Select a pane.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-U', '-D', '-L', '-R') -Description 'Pane direction.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-t') -Description 'Target pane.' -ValueKind 'PaneTarget'
            New-PsmuxOptionSpec -Tokens @('-m') -Description 'Mark pane.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-M') -Description 'Unmark pane.' -ValueKind $null
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'resize-pane' -Description 'Resize a pane.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-U', '-D', '-L', '-R') -Description 'Resize direction.' -ValueKind 'Count'
            New-PsmuxOptionSpec -Tokens @('-Z') -Description 'Toggle zoom.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-x') -Description 'Absolute column width.' -ValueKind 'Cols'
            New-PsmuxOptionSpec -Tokens @('-y') -Description 'Absolute row height.' -ValueKind 'Rows'
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'swap-pane' -Description 'Swap panes.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-U', '-D') -Description 'Swap direction.' -ValueKind $null
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'pipe-pane' -Description 'Pipe pane output to a command.' -Subcommands @() -Options @() -Positionals @('CommandTail')
        New-PsmuxCommandSpec -Path 'capture-pane' -Description 'Capture pane content.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-p') -Description 'Print to stdout.' -ValueKind $null
        ) -Positionals @()
        New-PsmuxCommandSpec -Path 'send-keys' -Description 'Send keys to a pane.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-l') -Description 'Send literally.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-p') -Description 'Paste text.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-t') -Description 'Target pane.' -ValueKind 'Target'
        ) -Positionals @('Keys')
        New-PsmuxCommandSpec -Path 'set-option' -Description 'Set a session/window option.' -Subcommands @() -Options @(
            New-PsmuxOptionSpec -Tokens @('-g') -Description 'Set globally.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-u') -Description 'Unset/reset to default.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-a') -Description 'Append to current value.' -ValueKind $null
            New-PsmuxOptionSpec -Tokens @('-q') -Description 'Quiet on unknown option.' -ValueKind $null
        ) -Positionals @('OptionName', 'OptionValue')
        New-PsmuxCommandSpec -Path 'source-file' -Description 'Execute commands from a config file.' -Subcommands @() -Options @() -Positionals @('Path')
        New-PsmuxCommandSpec -Path 'set-environment' -Description 'Set an environment variable.' -Subcommands @() -Options @() -Positionals @('EnvName', 'EnvValue')
        New-PsmuxCommandSpec -Path 'set-hook' -Description 'Set a hook command for an event.' -Subcommands @() -Options @() -Positionals @('HookName', 'CommandTail')
        New-PsmuxCommandSpec -Path 'select-layout' -Description 'Apply a layout preset.' -Subcommands @() -Options @() -Positionals @('Layout')
        New-PsmuxCommandSpec -Path 'display-message' -Description 'Display a message or format variable.' -Subcommands @() -Options @() -Positionals @('FormatOrMessage')
        New-PsmuxCommandSpec -Path 'run-shell' -Description 'Run a shell command.' -Subcommands @() -Options @() -Positionals @('CommandTail')
        New-PsmuxCommandSpec -Path 'if-shell' -Description 'Conditional command execution.' -Subcommands @() -Options @() -Positionals @('CommandTail')
        New-PsmuxCommandSpec -Path 'wait-for' -Description 'Wait for or signal a channel.' -Subcommands @() -Options @() -Positionals @('ChannelName')
        New-PsmuxCommandSpec -Path 'help' -Description 'Show help for a command.' -Subcommands @() -Options @() -Positionals @('HelpTopic')
    )
}

function Get-PsmuxCommandSpecByPath {
    param([string]$Path)

    foreach ($spec in Get-PsmuxCommandSpecs) {
        if ($spec.Path -eq $Path) {
            return $spec
        }
    }

    $null
}

function Remove-PsmuxOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-PsmuxQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        $escaped = $Value.Replace('`', '``').Replace('"', '`"')
        return '"' + $escaped + '"'
    }

    $Value
}

function Get-PsmuxPathCompletions {
    param([string]$InputPath)

    $typedValue = Remove-PsmuxOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($typedValue)) {
        $parent = '.'
        $leaf = ''
    } elseif ($typedValue.EndsWith('\') -or $typedValue.EndsWith('/')) {
        $parent = $typedValue
        $leaf = ''
    } else {
        $candidateParent = Split-Path -Path $typedValue -Parent
        if ([string]::IsNullOrWhiteSpace($candidateParent)) {
            $parent = '.'
            $leaf = $typedValue
        } else {
            $parent = $candidateParent
            $leaf = Split-Path -Path $typedValue -Leaf
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$leaf*" } | Sort-Object -Property Name)) {
        $pathText = if ($parent -eq '.') { $item.Name } else { Join-Path -Path $parent -ChildPath $item.Name }
        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }
        [void]$results.Add((New-PsmuxCompletionResult -CompletionText (ConvertTo-PsmuxQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote) -ToolTip $item.FullName))
    }

    if ($results.Count -eq 0) {
        [void]$results.Add((New-PsmuxCompletionResult -CompletionText '<path>' -ToolTip 'Filesystem path.'))
    }

    @($results.ToArray())
}

function Get-PsmuxCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') {
        return ''
    }

    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-PsmuxTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-PsmuxArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += Get-PsmuxTokenText -Element $element
        }
    }

    $tokens
}

function Get-PsmuxActiveContext {
    param([string[]]$TokensBeforeCurrent)

    $aliasMap = Get-PsmuxAliasMap
    $rootSpec = Get-PsmuxCommandSpecByPath -Path ''
    $activePath = ''
    $activeSpec = $rootSpec
    $positionals = New-Object System.Collections.Generic.List[string]
    $expectedValue = $null

    foreach ($token in @($TokensBeforeCurrent)) {
        if ($null -ne $expectedValue) {
            $positionals.Add($token)
            $expectedValue = $null
            continue
        }

        $matchedOption = $null
        foreach ($option in $activeSpec.Options + $rootSpec.Options) {
            if ($option.Tokens -contains $token) {
                $matchedOption = $option
                break
            }
        }

        if ($matchedOption) {
            if ($matchedOption.ValueKind) {
                $expectedValue = $matchedOption
            }
            continue
        }

        if ($token -eq '--') {
            $positionals.Add($token)
            continue
        }

        if ($activeSpec.Subcommands -contains $token -or $aliasMap.ContainsKey($token)) {
            $canonical = if ($aliasMap.ContainsKey($token)) { $aliasMap[$token] } else { $token }
            $activePath = $canonical
            $activeSpec = Get-PsmuxCommandSpecByPath -Path $canonical
            if (-not $activeSpec) {
                $activeSpec = $rootSpec
            }
            $positionals.Clear()
            continue
        }

        $positionals.Add($token)
    }

    [pscustomobject]@{
        RootSpec    = $rootSpec
        ActivePath  = $activePath
        ActiveSpec  = $activeSpec
        Positionals = @($positionals.ToArray())
        Expected    = $expectedValue
    }
}

function Get-PsmuxOptionValueCompletions {
    param(
        [string]$ValueKind,
        [string]$CurrentWord,
        [string[]]$Positionals
    )

    switch ($ValueKind) {
        'Path'          { return @(Get-PsmuxPathCompletions -InputPath $CurrentWord) }
        'SessionName'   { return ((Get-PsmuxSessionSuggestions + @('<session-name>')) | Sort-Object -Unique | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Session name.' }) }
        'SessionTarget' { return ((Get-PsmuxSessionSuggestions + @('default', 'work')) | Sort-Object -Unique | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Target session.' }) }
        'WindowName'    { return @('<window-name>') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Window name.' } }
        'PaneTarget'    { return @('%1', '%2', ':1.0', ':2.1') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Target pane.' } }
        'Target'        { return (Get-PsmuxTargetSuggestions | Sort-Object -Unique | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Session/window/pane target.' }) }
        'Index'         { return @('0','1','2','3','4','5','6','7','8','9') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Window index.' } }
        'Percent'       { return @('25','33','50','66','75') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Percentage.' } }
        'Count'         { return @('1','2','5','10') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Resize count.' } }
        'Cols'          { return @('80','100','120') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Column count.' } }
        'Rows'          { return @('24','30','40') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Row count.' } }
        'Name'          { return @('default', 'main', 'dev') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Name value.' } }
    }

    @()
}

function Get-PsmuxPositionalCompletions {
    param(
        [string]$ActivePath,
        [string[]]$Positionals,
        [string]$CurrentWord
    )

    $spec = Get-PsmuxCommandSpecByPath -Path $ActivePath
    if (-not $spec) {
        return @()
    }

    $positionIndex = $Positionals.Count
    if ($positionIndex -ge $spec.Positionals.Count) {
        return @()
    }

    $kind = $spec.Positionals[$positionIndex]
    switch ($kind) {
        'SessionName'   { return Get-PsmuxOptionValueCompletions -ValueKind 'SessionName' -CurrentWord $CurrentWord -Positionals $Positionals }
        'WindowName'    { return @('<window-name>') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Window name.' } }
        'Path'          { return @(Get-PsmuxPathCompletions -InputPath $CurrentWord) }
        'Layout'        { return Get-PsmuxLayoutSuggestions | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Layout preset.' } }
        'EnvName'       { return Get-PsmuxEnvVarSuggestions | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Environment variable.' } }
        'EnvValue'      { return @('<value>') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Environment variable value.' } }
        'Keys'          { return Get-PsmuxKeySuggestions | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Key name.' } }
        'HookName'      { return Get-PsmuxHookSuggestions | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Hook event.' } }
        'ChannelName'   { return @('build', 'deploy', 'sync') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Wait/signal channel.' } }
        'Query'         { return @('<query>') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Search string.' } }
        'HelpTopic'     { return Get-PsmuxRootSubcommands | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'psmux command topic.' } }
        'FormatOrMessage' { return @('#S', '#W', '#{?window_active,yes,no}', '<message>') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Message or format expression.' } }
        'CommandTail' {
            $suggestions = New-Object System.Collections.Generic.List[object]
            foreach ($name in @('pwsh', 'powershell', 'cmd', 'python', 'git')) {
                if ($name -like "$CurrentWord*") {
                    [void]$suggestions.Add((New-PsmuxCompletionResult -CompletionText $name -ToolTip 'Executable name.'))
                }
            }

            foreach ($command in @(Get-Command -Name "$CurrentWord*" -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Sort-Object -Property Name -Unique | Select-Object -First 20)) {
                [void]$suggestions.Add((New-PsmuxCompletionResult -CompletionText $command.Name -ToolTip $command.Source))
            }

            if ($suggestions.Count -eq 0) {
                [void]$suggestions.Add((New-PsmuxCompletionResult -CompletionText '<command>' -ToolTip 'Shell command or executable.'))
            }

            return @($suggestions.ToArray())
        }
        'OptionName' {
            return Get-PsmuxOptionNames | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'psmux option name.'
            }
        }
        'OptionValue' {
            $optionName = if ($Positionals.Count -gt 0) { $Positionals[0] } else { '' }
            $boolOptions = @('mouse','status','focus-events','renumber-windows','automatic-rename','monitor-activity','synchronize-panes','remain-on-exit','aggressive-resize','set-titles','visual-bell','cursor-blink','prediction-dimming')
            if ($boolOptions -contains $optionName) {
                return @('on','off','true','false') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                    New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Boolean option value.'
                }
            }

            switch ($optionName) {
                'mode-keys'      { return @('vi','emacs') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Key mode.' } }
                'status-position'{ return @('top','bottom') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Status bar position.' } }
                'default-shell'  { return @('pwsh','powershell','cmd','nu','bash') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Default shell.' } }
                'default-command'{ return @('pwsh','cmd /K','python') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Default command.' } }
                'cursor-style'   { return @('block','underline','bar') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Cursor style.' } }
                'bell-action'    { return @('any','none','current','other') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Bell handling mode.' } }
                'status-justify' { return @('left','centre','right') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Status alignment.' } }
                'prefix'         { return @('C-b','C-a') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object { New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Prefix key.' } }
                default {
                    return @('<value>') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                        New-PsmuxCompletionResult -CompletionText $_ -ToolTip 'Option value.'
                    }
                }
            }
        }
    }

    @()
}

function Get-PsmuxOptionCompletions {
    param(
        [object]$Spec,
        [string]$CurrentWord
    )

    foreach ($option in $Spec.Options + (Get-PsmuxCommandSpecByPath -Path '').Options) {
        foreach ($token in $option.Tokens) {
            if ($token -like "$CurrentWord*") {
                New-PsmuxCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $option.Description
            }
        }
    }
}

function Complete-Psmux {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $currentWord = if ($null -eq $WordToComplete) {
        Get-PsmuxCurrentToken -Line $CommandAst.ToString() -CursorPosition $CursorPosition -Fallback $WordToComplete
    } else {
        $WordToComplete
    }

    $tokensBeforeCurrent = @(Get-PsmuxArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $context = Get-PsmuxActiveContext -TokensBeforeCurrent $tokensBeforeCurrent

    if ($context.Expected) {
        return @(Get-PsmuxOptionValueCompletions -ValueKind $context.Expected.ValueKind -CurrentWord $currentWord -Positionals $context.Positionals)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-PsmuxOptionCompletions -Spec $context.ActiveSpec -CurrentWord $currentWord)
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrWhiteSpace($context.ActivePath) -and $context.Positionals.Count -eq 0) {
        foreach ($commandName in $context.RootSpec.Subcommands) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $commandName -like "$currentWord*") {
                [void]$results.Add((New-PsmuxCompletionResult -CompletionText $commandName -ToolTip 'psmux subcommand.'))
            }
        }

        foreach ($item in @(Get-PsmuxOptionCompletions -Spec $context.ActiveSpec -CurrentWord $currentWord)) {
            [void]$results.Add($item)
        }

        return @($results.ToArray())
    }

    if ($context.ActiveSpec.Subcommands.Count -gt 0 -and $context.Positionals.Count -eq 0) {
        foreach ($commandName in $context.ActiveSpec.Subcommands) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $commandName -like "$currentWord*") {
                [void]$results.Add((New-PsmuxCompletionResult -CompletionText $commandName -ToolTip 'psmux subcommand.'))
            }
        }
    }

    foreach ($item in @(Get-PsmuxPositionalCompletions -ActivePath $context.ActivePath -Positionals $context.Positionals -CurrentWord $currentWord)) {
        [void]$results.Add($item)
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        foreach ($item in @(Get-PsmuxOptionCompletions -Spec $context.ActiveSpec -CurrentWord $currentWord)) {
            [void]$results.Add($item)
        }
    }

    @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('psmux', 'psmux.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Psmux -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
