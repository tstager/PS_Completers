# opencode_completer.ps1
# PowerShell argument completer for opencode.exe

Set-StrictMode -Version Latest

function Complete-Opencode {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    # Parse the command line to determine context
    $tokens = $commandAst.CommandElements
    $currentWordIndex = $tokens.Count - 1
    
    # If we're completing the first argument (command/subcommand)
    if ($currentWordIndex -eq 0) {
        $commands = @(
            'completion', 'acp', 'mcp', 'attach', 'run', 'debug', 'providers', 'auth',
            'agent', 'upgrade', 'uninstall', 'serve', 'web', 'models', 'stats', 'export',
            'import', 'github', 'pr', 'session', 'plugin', 'plug', 'db'
        )
        
        foreach ($cmd in $commands) {
            if ($cmd.StartsWith($wordToComplete, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                [System.Management.Automation.CompletionResult]::new($cmd, $cmd, 'ParameterValue', $cmd)
            }
        }
        return
    }

    # Get the command being used (first argument)
    $command = if ($tokens.Count -ge 2) { $tokens[1].ToString().ToLower() } else { '' }

    switch ($command) {
        # Global options (apply to most commands)
        { $_ -in @('completion', 'acp', 'mcp', 'run', 'debug', 'providers', 'auth', 'agent', 'upgrade', 'uninstall', 'serve', 'web', 'models', 'stats', 'export', 'import', 'github', 'pr', 'session', 'plugin', 'plug', 'db') } {
            Complete-GlobalOptions -wordToComplete $wordToComplete
        }
        
        'run' {
            Complete-RunCommand -wordToComplete $wordToComplete -commandAst $commandAst -tokens $tokens
        }
        
        'attach' {
            Complete-AttachCommand -wordToComplete $wordToComplete
        }
        
        'pr' {
            Complete-PrCommand -wordToComplete $wordToComplete
        }
        
        'import' {
            Complete-ImportCommand -wordToComplete $wordToComplete
        }
        
        'models' {
            Complete-ModelsCommand -wordToComplete $wordToComplete
        }
        
        'agent' {
            Complete-AgentCommand -wordToComplete $wordToComplete -commandAst $commandAst -tokens $tokens
        }
        
        'providers' {
            Complete-ProvidersCommand -wordToComplete $wordToComplete -commandAst $commandAst -tokens $tokens
        }
        
        'upgrade' {
            Complete-UpgradeCommand -wordToComplete $wordToComplete
        }
        
        'plugin' {
            Complete-PluginCommand -wordToComplete $wordToComplete
        }
        
        'github' {
            Complete-GithubCommand -wordToComplete $wordToComplete
        }
        
        'session' {
            Complete-SessionCommand -wordToComplete $wordToComplete -commandAst $commandAst -tokens $tokens
        }
        
        default {
            # For project command or unknown commands, show global options
            Complete-GlobalOptions -wordToComplete $wordToComplete
        }
    }
}

function Complete-GlobalOptions {
    param([string]$wordToComplete)
    
    $options = @(
        '-h', '--help',
        '-v', '--version',
        '--print-logs',
        '--log-level',
        '--pure',
        '--port',
        '--hostname',
        '--mdns',
        '--mdns-domain',
        '--cors',
        '-m', '--model',
        '-c', '--continue',
        '-s', '--session',
        '--fork',
        '--prompt',
        '--agent'
    )
    
    foreach ($opt in $options) {
        if ($opt.StartsWith($wordToComplete, [System.StringComparison]::InvariantCultureIgnoreCase)) {
            $type = if ($opt.StartsWith('-')) { 'ParameterName' } else { 'ParameterValue' }
            [System.Management.Automation.CompletionResult]::new($opt, $opt, $type, $opt)
        }
    }
}

function Complete-RunCommand {
    param([string]$wordToComplete, [System.Management.Automation.CommandAst]$commandAst, [object[]]$tokens)
    
    # For run command, we complete with global options or treat as free-form message
    # Since run takes a message that can be anything, we don't provide specific completions
    # but we do provide global options
    Complete-GlobalOptions -wordToComplete $wordToComplete
}

function Complete-AttachCommand {
    param([string]$wordToComplete)
    
    # attach takes a URL, so we could provide placeholder or treat as free-form
    # For now, just show global options since URL completion is complex
    Complete-GlobalOptions -wordToComplete $wordToComplete
}

function Complete-PrCommand {
    param([string]$wordToComplete)
    
    # pr takes a number (PR number), so we don't provide specific completions
    # but we do provide global options
    Complete-GlobalOptions -wordToComplete $wordToComplete
}

function Complete-ImportCommand {
    param([string]$wordToComplete)
    
    # import takes a file path or URL
    # We'll provide global options and let PowerShell handle path completion naturally
    Complete-GlobalOptions -wordToComplete $wordToComplete
}

function Complete-ModelsCommand {
    param([string]$wordToComplete)
    
    # models can take an optional provider
    if ($wordToComplete -eq '') {
        # Show global options first
        Complete-GlobalOptions -wordToComplete $wordToComplete
    }
    # For provider completion, we could list known providers but for now just global options
    Complete-GlobalOptions -wordToComplete $wordToComplete
}

function Complete-AgentCommand {
    param([string]$wordToComplete, [System.Management.Automation.CommandAst]$commandAst, [object[]]$tokens)
    
    # Check if we're completing a subcommand for agent
    if ($tokens.Count -ge 3) {
        $subcommand = $tokens[2].ToString().ToLower()
        switch ($subcommand) {
            # agent subcommands would go here based on opencode agent --help
            default {
                Complete-GlobalOptions -wordToComplete $wordToComplete
            }
        }
    } else {
        # Completing the agent subcommand itself
        $subcommands = @('list', 'create', 'remove', 'run')  # Based on typical agent commands
        foreach ($subcmd in $subcommands) {
            if ($subcmd.StartsWith($wordToComplete, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                [System.Management.Automation.CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', $subcmd)
            }
        }
        Complete-GlobalOptions -wordToComplete $wordToComplete
    }
}

function Complete-ProvidersCommand {
    param([string]$wordToComplete, [System.Management.Automation.CommandAst]$commandAst, [object[]]$tokens)
    
    # Check if we're completing a subcommand for providers
    if ($tokens.Count -ge 3) {
        $subcommand = $tokens[2].ToString().ToLower()
        switch ($subcommand) {
            # providers subcommands would go here based on opencode providers --help
            default {
                Complete-GlobalOptions -wordToComplete $wordToComplete
            }
        }
    } else {
        # Completing the providers subcommand itself
        $subcommands = @('list', 'add', 'remove', 'default')  # Based on typical provider commands
        foreach ($subcmd in $subcommands) {
            if ($subcmd.StartsWith($wordToComplete, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                [System.Management.Automation.CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', $subcmd)
            }
        }
        Complete-GlobalOptions -wordToComplete $wordToComplete
    }
}

function Complete-UpgradeCommand {
    param([string]$wordToComplete)
    
    # upgrade can take a target version
    # We'll provide global options and let version completion be free-form
    Complete-GlobalOptions -wordToComplete $wordToComplete
}

function Complete-PluginCommand {
    param([string]$wordToComplete)
    
    # plugin takes a module name
    # We'll provide global options and let module completion be free-form
    Complete-GlobalOptions -wordToComplete $wordToComplete
}

function Complete-GithubCommand {
    param([string]$wordToComplete)
    
    # github command - we'll provide global options
    Complete-GlobalOptions -wordToComplete $wordToComplete
}

function Complete-SessionCommand {
    param([string]$wordToComplete, [System.Management.Automation.CommandAst]$commandAst, [object[]]$tokens)
    
    # Check if we're completing a subcommand for session
    if ($tokens.Count -ge 3) {
        $subcommand = $tokens[2].ToString().ToLower()
        switch ($subcommand) {
            # session subcommands would go here based on opencode session --help
            default {
                Complete-GlobalOptions -wordToComplete $wordToComplete
            }
        }
    } else {
        # Completing the session subcommand itself
        $subcommands = @('list', 'show', 'remove', 'switch')  # Based on typical session commands
        foreach ($subcmd in $subcommands) {
            if ($subcmd.StartsWith($wordToComplete, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                [System.Management.Automation.CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', $subcmd)
            }
        }
        Complete-GlobalOptions -wordToComplete $wordToComplete
    }
}

# Register the completer for both opencode and opencode.exe
# Using a literal script block to satisfy Import-CompleterScript requirements
Register-ArgumentCompleter -Native -CommandName 'opencode', 'opencode.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    
    # Parse the command line to determine context
    $tokens = $commandAst.CommandElements
    $currentWordIndex = $tokens.Count - 1
    
    # If we're completing the first argument (command/subcommand)
    if ($currentWordIndex -eq 0) {
        $commands = @(
            'completion', 'acp', 'mcp', 'attach', 'run', 'debug', 'providers', 'auth',
            'agent', 'upgrade', 'uninstall', 'serve', 'web', 'models', 'stats', 'export',
            'import', 'github', 'pr', 'session', 'plugin', 'plug', 'db'
        )
        
        foreach ($cmd in $commands) {
            if ($cmd.StartsWith($wordToComplete, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                [System.Management.Automation.CompletionResult]::new($cmd, $cmd, 'ParameterValue', $cmd)
            }
        }
        return
    }

    # Get the command being used (first argument)
    $command = if ($tokens.Count -ge 2) { $tokens[1].ToString().ToLower() } else { '' }

    switch ($command) {
        # Global options (apply to most commands)
        { $_ -in @('completion', 'acp', 'mcp', 'run', 'debug', 'providers', 'auth', 'agent', 'upgrade', 'uninstall', 'serve', 'web', 'models', 'stats', 'export', 'import', 'github', 'pr', 'session', 'plugin', 'plug', 'db') } {
            Complete-GlobalOptions -wordToComplete $wordToComplete
        }
        
        'run' {
            Complete-RunCommand -wordToComplete $wordToComplete -commandAst $commandAst -tokens $tokens
        }
        
        'attach' {
            Complete-AttachCommand -wordToComplete $wordToComplete
        }
        
        'pr' {
            Complete-PrCommand -wordToComplete $wordToComplete
        }
        
        'import' {
            Complete-ImportCommand -wordToComplete $wordToComplete
        }
        
        'models' {
            Complete-ModelsCommand -wordToComplete $wordToComplete
        }
        
        'agent' {
            Complete-AgentCommand -wordToComplete $wordToComplete -commandAst $commandAst -tokens $tokens
        }
        
        'providers' {
            Complete-ProvidersCommand -wordToComplete $wordToComplete -commandAst $commandAst -tokens $tokens
        }
        
        'upgrade' {
            Complete-UpgradeCommand -wordToComplete $wordToComplete
        }
        
        'plugin' {
            Complete-PluginCommand -wordToComplete $wordToComplete
        }
        
        'github' {
            Complete-GithubCommand -wordToComplete $wordToComplete
        }
        
        'session' {
            Complete-SessionCommand -wordToComplete $wordToComplete -commandAst $commandAst -tokens $tokens
        }
        
        default {
            # For project command or unknown commands, show global options
            Complete-GlobalOptions -wordToComplete $wordToComplete
        }
    }
}