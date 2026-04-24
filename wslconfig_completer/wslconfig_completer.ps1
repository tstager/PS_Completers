<#
.SYNOPSIS
    Registers a native PowerShell argument completer for wslconfig.

.DESCRIPTION
    Provides a static-first native completer for the legacy `wslconfig` and
    `wslconfig.exe` command surface.

    The completer covers:
    - top-level slash switches
    - `/list` mode options
    - local distribution-name completion for setdefault, terminate, and unregister
    - terminal handling after help switches

    The script keeps its top level compatible with `Import-CompleterScript`.
#>

Set-StrictMode -Version Latest

function New-WslConfigCompletionResult {
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

function Get-WslConfigTokenState {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    if ($null -eq $Line) {
        $Line = ''
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    $tokens = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    $quoteChar = [char]0

    foreach ($character in $prefix.ToCharArray()) {
        if (($character -eq [char]34) -or ($character -eq [char]39)) {
            if ($quoteChar -eq [char]0) {
                $quoteChar = $character
            } elseif ($quoteChar -eq $character) {
                $quoteChar = [char]0
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and $quoteChar -eq [char]0) {
            if ($builder.Length -gt 0) {
                $tokens.Add($builder.ToString())
                [void]$builder.Clear()
            }

            continue
        }

        [void]$builder.Append($character)
    }

    $hasTrailingSpace = $prefix -match '\s$'
    if ($builder.Length -gt 0) {
        $tokens.Add($builder.ToString())
    }

    if ($hasTrailingSpace) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens)
            CurrentToken        = ''
        }
    }

    if ($tokens.Count -gt 0) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
            CurrentToken        = $tokens[$tokens.Count - 1]
        }
    }

    [pscustomobject]@{
        TokensBeforeCurrent = @()
        CurrentToken        = ''
    }
}

function Get-WslConfigArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    $tokensBeforeCurrent = @($TokenState.TokensBeforeCurrent)
    $currentArgument = if ($null -eq $TokenState.CurrentToken) { '' } else { $TokenState.CurrentToken }

    if ($tokensBeforeCurrent.Count -gt 0) {
        $argumentsBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip 1)
    } else {
        $argumentsBeforeCurrent = @()
    }

    if ($tokensBeforeCurrent.Count -eq 0 -and $currentArgument -match '^(?i)wslconfig(?:\.exe)?$') {
        $currentArgument = ''
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = $argumentsBeforeCurrent
        CurrentArgument        = $currentArgument
    }
}

function Get-WslConfigCatalog {
    if (Get-Variable -Name WslConfigCompletionCatalog -Scope Script -ErrorAction SilentlyContinue) {
        return $script:WslConfigCompletionCatalog
    }

    $switches = @(
        [pscustomobject]@{ Token = '/l';          Description = 'List registered distributions.'; ValueKind = 'ListMode' }
        [pscustomobject]@{ Token = '/list';       Description = 'List registered distributions.'; ValueKind = 'ListMode' }
        [pscustomobject]@{ Token = '/all';        Description = 'List all distributions, including installing or uninstalling ones.'; ValueKind = $null }
        [pscustomobject]@{ Token = '/running';    Description = 'List only running distributions.'; ValueKind = $null }
        [pscustomobject]@{ Token = '/s';          Description = 'Set the default distribution.'; ValueKind = 'DistributionName' }
        [pscustomobject]@{ Token = '/setdefault'; Description = 'Set the default distribution.'; ValueKind = 'DistributionName' }
        [pscustomobject]@{ Token = '/t';          Description = 'Terminate the distribution.'; ValueKind = 'DistributionName' }
        [pscustomobject]@{ Token = '/terminate';  Description = 'Terminate the distribution.'; ValueKind = 'DistributionName' }
        [pscustomobject]@{ Token = '/u';          Description = 'Unregister the distribution and delete its root filesystem.'; ValueKind = 'DistributionName' }
        [pscustomobject]@{ Token = '/unregister'; Description = 'Unregister the distribution and delete its root filesystem.'; ValueKind = 'DistributionName' }
        [pscustomobject]@{ Token = '/?';          Description = 'Show help for wslconfig.'; ValueKind = $null }
        [pscustomobject]@{ Token = '-?';          Description = 'Show help for wslconfig.'; ValueKind = $null }
        [pscustomobject]@{ Token = '--help';      Description = 'Show help for wslconfig.'; ValueKind = $null }
    )

    $switchLookup = @{}
    foreach ($switch in $switches) {
        $switchLookup[$switch.Token.ToLowerInvariant()] = $switch
    }

    $script:WslConfigCompletionCatalog = [pscustomobject]@{
        Switches        = $switches
        SwitchLookup    = $switchLookup
        ListModeOptions = @('/all', '/running')
    }

    $script:WslConfigCompletionCatalog
}

function Get-WslConfigDistributionNames {
    if (Get-Variable -Name WslConfigDistributionCache -Scope Script -ErrorAction SilentlyContinue) {
        $cache = $script:WslConfigDistributionCache
        if (((Get-Date) - $cache.UpdatedAt).TotalSeconds -lt 15) {
            return $cache.Values
        }
    }

    $values = @()
    if (Get-Command -Name wslconfig.exe -ErrorAction SilentlyContinue) {
        $values = @(
            & wslconfig.exe /l 2>$null |
                ForEach-Object { $_.ToString().Replace([string][char]0, '') } |
                ForEach-Object { $_.Trim() } |
                Where-Object {
                    $_ -and
                    $_ -notmatch '^Windows Subsystem for Linux Distributions' -and
                    $_ -notmatch '^The following distributions' -and
                    $_ -notmatch '^\*'
                } |
                ForEach-Object {
                    ($_ -replace '\s*\(Default\)\s*$', '').Trim()
                } |
                Where-Object { $_ }
        ) | Sort-Object -Unique
    }

    $script:WslConfigDistributionCache = [pscustomobject]@{
        UpdatedAt = Get-Date
        Values    = @($values)
    }

    @($values)
}

function Get-WslConfigSwitchCompletions {
    param(
        [string]$CurrentWord,
        [bool]$ListMode = $false
    )

    $catalog = Get-WslConfigCatalog
    $source = if ($ListMode) {
        foreach ($token in $catalog.ListModeOptions) {
            $catalog.SwitchLookup[$token.ToLowerInvariant()]
        }
    } else {
        $catalog.Switches
    }

    foreach ($switch in $source) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            -not $switch.Token.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        New-WslConfigCompletionResult -CompletionText $switch.Token -ResultType 'ParameterName' -ToolTip $switch.Description
    }
}

function Get-WslConfigDistributionCompletions {
    param([string]$CurrentWord)

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($distribution in @(Get-WslConfigDistributionNames)) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            -not $distribution.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-WslConfigCompletionResult -CompletionText $distribution -ResultType 'ParameterValue' -ToolTip 'WSL distribution name.'))
    }

    if ($results.Count -eq 0) {
        $placeholder = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '<distribution-name>' } else { $CurrentWord }
        [void]$results.Add((New-WslConfigCompletionResult -CompletionText $placeholder -ResultType 'ParameterValue' -ToolTip 'WSL distribution name.'))
    }

    @($results.ToArray())
}

function Get-WslConfigTerminalCompletions {
    param([string]$CurrentWord)

    $completionText = if ([string]::IsNullOrEmpty($CurrentWord)) { ' ' } else { $CurrentWord }
    @(
        New-WslConfigCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip 'No further arguments are valid after help.'
    )
}

function Complete-WslConfig {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $tokenState = Get-WslConfigTokenState -Line $commandAst.ToString() -CursorPosition $cursorPosition
    $argumentState = Get-WslConfigArgumentsFromTokenState -TokenState $tokenState
    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)

    if ($hasTrailingSpace -and -not [string]::IsNullOrEmpty($argumentState.CurrentArgument)) {
        $currentWord = ''
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent + $argumentState.CurrentArgument)
    } else {
        $currentWord = if ($null -eq $argumentState.CurrentArgument) { '' } else { $argumentState.CurrentArgument }
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent)
    }

    $catalog = Get-WslConfigCatalog

    $helpRequested = $false
    $valueContext = $null
    $listMode = $false

    if ($argumentsBeforeCurrent.Count -gt 0) {
        foreach ($token in $argumentsBeforeCurrent) {
            $key = $token.ToLowerInvariant()
            if ($key -in @('/?', '-?', '--help')) {
                $helpRequested = $true
                break
            }
        }

        if (-not $helpRequested) {
            $lastToken = $argumentsBeforeCurrent[-1].ToLowerInvariant()
            if ($lastToken -in @('/s', '/setdefault', '/t', '/terminate', '/u', '/unregister')) {
                $valueContext = 'DistributionName'
            } elseif ($lastToken -in @('/l', '/list')) {
                $listMode = $true
            }
        }
    }

    if ($helpRequested) {
        return @(Get-WslConfigTerminalCompletions -CurrentWord $currentWord)
    }

    if ($valueContext -eq 'DistributionName') {
        return @(Get-WslConfigDistributionCompletions -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and ($currentWord.StartsWith('/') -or $currentWord.StartsWith('-'))) {
        return @(Get-WslConfigSwitchCompletions -CurrentWord $currentWord -ListMode:$listMode)
    }

    if ($listMode) {
        return @(Get-WslConfigSwitchCompletions -CurrentWord $currentWord -ListMode $true)
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-WslConfigSwitchCompletions -CurrentWord $currentWord)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('wslconfig', 'wslconfig.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-WslConfig -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
