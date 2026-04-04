# PowerShell Argument Completer for wsl.exe
# Provides tab completion for common wsl subcommands and options.
# This script is self‑contained and registers a native completer for the `wsl` command.

Set-StrictMode -Version Latest

function Complete-WslNative {
    param($wordToComplete, $commandAst, $cursorPosition)

    # Ensure wsl.exe is available
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        return
    }

    $line = $commandAst.ToString()
    $tokens = @([regex]::Matches($line, '\S+') | ForEach-Object { $_.Value })

    $hasTrailingSpace = ($line -match '\s$') -or ($cursorPosition -gt $line.Length)
    if ($hasTrailingSpace) {
        $argIndex = $tokens.Count - 1
    }
    else {
        $argIndex = $tokens.Count - 2
    }
    if ($argIndex -lt 1) { $argIndex = 1 }

    $prevToken = if ($tokens.Count -gt 1) { $tokens[-2] } else { '' }

    $subcommands = @(
        '--list',
        '--set-default',
        '--set-version',
        '--install',
        '--update',
        '--shutdown',
        '--help',
        '--version'
    )

    $options = @(
        '-d', '--distribution',
        '-e', '--exec',
        '-u', '--user',
        '-c', '--command',
        '--cd', '--workingdir'
    )

    $complete = {
        param([string[]]$list)
        $list |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }

    switch ($prevToken) {
        '-d' { $distros = wsl -l -q 2>$null; & $complete $distros; return }
        '--distribution' { $distros = wsl -l -q 2>$null; & $complete $distros; return }
        '--set-default' { $distros = wsl -l -q 2>$null; & $complete $distros; return }
        '--set-version' { $distros = wsl -l -q 2>$null; & $complete $distros; return }
        '-u' { & $complete @('root'); return }
        '--user' { & $complete @('root'); return }
    }

    # Default completion: subcommands and options
    $all = $subcommands + $options
    & $complete $all
}

Register-ArgumentCompleter -Native -CommandName @('wsl', 'wsl.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-WslNative -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
