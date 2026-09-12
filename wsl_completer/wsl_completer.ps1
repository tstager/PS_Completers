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
        '--', '--cd', '--debug-shell', '--distribution', '-d', '--distribution-id', '--exec', '-e', '--export', '--help',
        '--import', '--import-in-place', '--install', '--list', '-l', '--manage', '--mount', '--set-default', '-s',
        '--set-default-version', '--set-version', '--shell-type', '--shutdown', '--status', '--system', '--terminate', '-t',
        '--uninstall', '--unmount', '--unregister', '--update', '--user', '-u', '--version', '-v'
    )

    $listSwitches = @('--all', '--running', '--quiet', '-q', '--verbose', '-v', '--online', '-o')
    $modeSwitches = @{
        '--install'  = @('--no-launch', '--web-download', '--no-distribution', '--enable-wsl1', '--from-file', '--name', '--location', '--version', '--legacy')
        '--mount'    = @('--vhd', '--bare', '--name', '--type', '--options', '--partition')
        '--export'   = @('--vhd', '--format')
        '--import'   = @('--version', '--vhd')
        '--shutdown' = @('--force')
        '--update'   = @('--pre-release')
        '--list'     = $listSwitches
        '-l'         = $listSwitches
        '--manage'   = @('--move', '--resize', '--set-default-user', '--set-sparse', '-s')
    }

    $enumValues = @{
        '--version'             = @('1', '2')
        '--set-default-version' = @('1', '2')
        '--shell-type'          = @('standard', 'login', 'none')
        '--set-sparse'          = @('true', 'false')
        '--format'              = @('tar', 'tar.gz', 'tar.xz', 'vhd')
        '--type'                = @('ext4', 'drvfs')
        '--user'                = @('root')
        '-u'                    = @('root')
    }

    $distributionValueSwitches = @('--distribution', '-d', '--export', '--manage', '--set-default', '--set-version', '--terminate', '-t', '--unregister')

    $mode = $null
    foreach ($token in $argumentTokens) {
        if ($modeSwitches.ContainsKey($token)) {
            $mode = $token
            break
        }
    }

    if ($previousToken -eq '-s') {
        if ($mode -eq '--manage') {
            New-WslCompletionResult -Values @('true', 'false') -WordToComplete $wordToComplete
            return
        }

        if ($argumentTokens.Count -eq 1) {
            New-WslCompletionResult -Values (Get-WslDistributionNames) -WordToComplete $wordToComplete
            return
        }
    }

    if ($enumValues.ContainsKey($previousToken)) {
        New-WslCompletionResult -Values $enumValues[$previousToken] -WordToComplete $wordToComplete
        return
    }

    if ($argumentTokens.Count -eq 2 -and $argumentTokens[0] -eq '--set-version') {
        New-WslCompletionResult -Values @('1', '2') -WordToComplete $wordToComplete
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

    if ($previousToken -in @('--from-file', '--location', '--move', '--cd', '--name', '--options', '--partition', '--resize', '--set-default-user')) {
        return
    }

    if ($mode) {
        $operandSlot = -not ($wordToComplete -like '-*') -and $argumentTokens.Count -eq 1
        if ($operandSlot -and $mode -in @('--import', '--mount')) {
            return
        }

        if (-not ($wordToComplete -like '-*') -and $mode -eq '--import' -and $argumentTokens.Count -le 3) {
            return
        }

        if (-not ($wordToComplete -like '-*') -and $mode -eq '--export' -and $argumentTokens.Count -eq 2) {
            return
        }

        New-WslCompletionResult -Values $modeSwitches[$mode] -WordToComplete $wordToComplete -ResultType ParameterName
        return
    }

    New-WslCompletionResult -Values $topLevelSwitches -WordToComplete $wordToComplete -ResultType ParameterName
}

Register-ArgumentCompleter -Native -CommandName @('wsl', 'wsl.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-WslNative -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
