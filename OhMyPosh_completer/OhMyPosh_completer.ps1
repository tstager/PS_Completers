  # oh-my-posh argument completer
function Complete-OhMyPosh {
    param($wordToComplete, $commandAst, $cursorPosition)
    
        $tokens = $commandAst.ToString().Split(' ')
        $subcommand = $tokens | Select-Object -Skip 1 | Select-Object -First 1
    
        # Main commands
        $mainCommands = @(
            'auth',
            'cache',
            'claude',
            'config',
            'debug',
            'disable',
            'enable',
            'font',
            'get',
            'help',
            'init',
            'notice',
            'print',
            'shell',
            'toggle',
            'upgrade',
            'version'
        )
    
        # Global flags
        $globalFlags = @(
            '--config',
            '-c',
            '--shell',
            '-s',
            '--plain',
            '--trace',
            '--version',
            '--help',
            '-h',
            '--init',
            '-i'
        )
    
        # Subcommand-specific flags
        $subcommandFlags = @{
            'init'    = @('--shell', '-s', '--config', '-c', '--print', '-p')
            'config'  = @('--output', '-o', '--config', '-c', '--list', '-l')
            'print'   = @('--shell', '-s', '--config', '-c', '--cursor-position', '--error')
            'debug'   = @('--shell', '-s', '--config', '-c')
            'get'     = @('--shell', '-s', '--config', '-c')
            'toggle'  = @('--config', '-c', '--shell', '-s')
            'enable'  = @('--config', '-c')
            'disable' = @('--config', '-c')
            'cache'   = @('--clean', '--delete', '--info')
            'font'    = @('--install', '--info', '--list')
            'auth'    = @('--login', '--logout', '--status')
        }
    
        if ([string]::IsNullOrWhiteSpace($subcommand) -or $mainCommands -notcontains $subcommand) {
            # Complete main commands
            $mainCommands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        
            # Complete global flags
            $globalFlags | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        else {
            # Complete subcommand-specific flags
            if ($subcommandFlags.ContainsKey($subcommand)) {
                $subcommandFlags[$subcommand] | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
            }
        
            # Always include global flags
            $globalFlags | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
    }

Register-ArgumentCompleter -Native -CommandName @('oh-my-posh.exe', 'oh-my-posh') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-OhMyPosh -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
