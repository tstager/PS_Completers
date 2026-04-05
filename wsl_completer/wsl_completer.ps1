# PowerShell Argument Completer for wsl.exe
# Provides tab completion for common wsl subcommands and options.
# This script is self‑contained and registers a native completer for the `wsl` command.

Set-StrictMode -Version Latest

function Get-WslDistributionNames {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        return
    }

    wsl -l -q 2>$null |
        ForEach-Object { $_.Replace([string][char]0, '').Trim() } |
        Where-Object { $_ }
}

function Get-WslDistributionIds {
    $lxssPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'

    if (-not (Test-Path -LiteralPath $lxssPath)) {
        return
    }

    Get-ChildItem -LiteralPath $lxssPath -ErrorAction SilentlyContinue |
        ForEach-Object {
            $distributionId = $_.PSChildName
            $parsedGuid = [guid]::Empty

            if ([guid]::TryParse($distributionId, [ref] $parsedGuid)) {
                $distributionId
            }
        }
}

function New-WslCompletionResult {
    param(
        [string[]] $Values,
        [string] $WordToComplete,
        [ValidateSet('ParameterName', 'ParameterValue')]
        [string] $ResultType = 'ParameterValue'
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($value in $Values) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        if ($value -notlike "$WordToComplete*") {
            continue
        }

        if (-not $seen.Add($value)) {
            continue
        }

        [System.Management.Automation.CompletionResult]::new($value, $value, $ResultType, $value)
    }
}

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
        $completedTokens = $tokens
    }
    elseif ($tokens.Count -gt 1) {
        $completedTokens = @($tokens[0..($tokens.Count - 2)])
    }
    else {
        $completedTokens = @()
    }

    if ($completedTokens.Count -gt 1) {
        $argumentTokens = @($completedTokens[1..($completedTokens.Count - 1)])
    }
    else {
        $argumentTokens = @()
    }

    $previousToken = if ($argumentTokens.Count -gt 0) { $argumentTokens[-1] } else { '' }

    $topLevelSwitches = @(
        '--',
        '--cd',
        '--debug-shell',
        '--distribution',
        '-d',
        '--distribution-id',
        '--exec',
        '-e',
        '--export',
        '--help',
        '--import',
        '--import-in-place',
        '--install',
        '--list',
        '-l',
        '--manage',
        '--mount',
        '--set-default',
        '-s',
        '--set-default-version',
        '--set-version',
        '--shell-type',
        '--shutdown',
        '--status',
        '--system',
        '--terminate',
        '-t',
        '--uninstall',
        '--unmount',
        '--unregister',
        '--update',
        '--user',
        '-u',
        '--version',
        '-v'
    )

    $listSwitches = @(
        '--all',
        '--running',
        '--quiet',
        '-q',
        '--verbose',
        '-v',
        '--online',
        '-o'
    )

    $manageSwitches = @(
        '--move',
        '--resize',
        '--set-default-user',
        '--set-sparse',
        '-s'
    )

    $distributionValueSwitches = @(
        '--distribution',
        '-d',
        '--export',
        '--manage',
        '--set-default',
        '--set-version',
        '--terminate',
        '-t',
        '--unregister'
    )

    if ($previousToken -eq '-s' -and $argumentTokens.Count -eq 1) {
        New-WslCompletionResult -Values (Get-WslDistributionNames) -WordToComplete $wordToComplete
        return
    }

    if ($previousToken -eq '-u' -or $previousToken -eq '--user') {
        New-WslCompletionResult -Values @('root') -WordToComplete $wordToComplete
        return
    }

    if ($previousToken -eq '--distribution-id') {
        New-WslCompletionResult -Values (Get-WslDistributionIds) -WordToComplete $wordToComplete
        return
    }

    if ($previousToken -in $distributionValueSwitches) {
        New-WslCompletionResult -Values (Get-WslDistributionNames) -WordToComplete $wordToComplete
        return
    }

    if ($previousToken -in @('--list', '-l')) {
        New-WslCompletionResult -Values $listSwitches -WordToComplete $wordToComplete -ResultType ParameterName
        return
    }

    if (
        $argumentTokens.Count -ge 2 -and
        $argumentTokens[0] -eq '--manage' -and
        $argumentTokens[1] -notlike '-*' -and
        ($wordToComplete -eq '' -or $wordToComplete -like '-*')
    ) {
        New-WslCompletionResult -Values $manageSwitches -WordToComplete $wordToComplete -ResultType ParameterName
        return
    }

    New-WslCompletionResult -Values $topLevelSwitches -WordToComplete $wordToComplete -ResultType ParameterName
}

Register-ArgumentCompleter -Native -CommandName @('wsl', 'wsl.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-WslNative -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
