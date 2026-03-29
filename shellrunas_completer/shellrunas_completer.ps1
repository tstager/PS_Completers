# shellrunas tab completion for PowerShell
# Static native completer based on official Sysinternals web documentation.

Set-StrictMode -Version 2.0

function New-ShellRunasCompletionResult {
    param([string]$CompletionText, [string]$ResultType, [string]$ToolTip, [string]$ListItemText)
    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }
    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

function Get-ShellRunasCurrentToken {
    param([string]$Line, [int]$CursorPosition, [string]$Fallback)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $Fallback }
    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') { return '' }
    $parts = @([regex]::Matches($prefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) { return $parts[-1] }
    $Fallback
}

function Remove-ShellRunasOuterQuotes {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) { return $Value.Substring(1, $Value.Length - 2) }
    $Value.TrimStart('"')
}

function ConvertTo-ShellRunasQuotedValue {
    param([string]$Value, [bool]$AlwaysQuote = $false)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + $Value.Replace('`', '``').Replace('"', '`"') + '"'
    }
    $Value
}

function Get-ShellRunasArgumentState {
    param([System.Management.Automation.Language.CommandAst]$CommandAst, [string]$WordToComplete, [int]$CursorPosition)
    $currentWord = if ([string]::IsNullOrEmpty($WordToComplete)) {
        ''
    } else {
        Get-ShellRunasCurrentToken -Line $CommandAst.Extent.Text -CursorPosition $CursorPosition -Fallback $WordToComplete
    }
    $tokens = @($CommandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text })
    $tokensBeforeCurrent = @($tokens)
    if (-not [string]::IsNullOrEmpty($currentWord) -and $tokensBeforeCurrent.Count -gt 0 -and $tokensBeforeCurrent[-1] -eq $currentWord) {
        if ($tokensBeforeCurrent.Count -gt 1) {
            $tokensBeforeCurrent = @($tokensBeforeCurrent[0..($tokensBeforeCurrent.Count - 2)])
        } else {
            $tokensBeforeCurrent = @()
        }
    }
    [pscustomobject]@{
        CurrentWord         = $currentWord
        TokensBeforeCurrent = $tokensBeforeCurrent
    }
}

function Get-ShellRunasProgramCompletions {
    param([string]$CurrentWord)
    $trimmed = Remove-ShellRunasOuterQuotes -Value $CurrentWord
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('"')
    $results = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        foreach ($sample in @('notepad.exe', 'cmd.exe', 'powershell.exe', 'pwsh.exe')) {
            [void]$results.Add((New-ShellRunasCompletionResult -CompletionText $sample -ResultType 'ParameterValue' -ToolTip 'Program to run with alternate credentials.'))
        }
    }

    if ($trimmed -match '[\\/]|^\.' -or $trimmed -match '^[A-Za-z]:') {
        $parent = Split-Path -Path $trimmed -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) { $parent = '.' }
        $leaf = Split-Path -Path $trimmed -Leaf
        $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
        foreach ($item in @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)) {
            $completionPath = if ($trimmed -and -not [System.IO.Path]::IsPathRooted($trimmed) -and $parent -ne '.') {
                Join-Path -Path $parent -ChildPath $item.Name
            } elseif ($parent -eq '.') {
                $item.Name
            } else {
                $item.FullName
            }
            if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
                $completionPath += [System.IO.Path]::DirectorySeparatorChar
            }
            [void]$results.Add((New-ShellRunasCompletionResult -CompletionText (ConvertTo-ShellRunasQuotedValue -Value $completionPath -AlwaysQuote:$alwaysQuote) -ResultType $(if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }) -ToolTip $item.FullName))
        }
    } else {
        foreach ($command in @(Get-Command -Name "$trimmed*" -CommandType Application -ErrorAction SilentlyContinue | Sort-Object -Property Name -Unique | Select-Object -First 20)) {
            [void]$results.Add((New-ShellRunasCompletionResult -CompletionText $command.Name -ResultType 'ParameterValue' -ToolTip $command.Name))
        }
    }

    if ($results.Count -eq 0) {
        return @(New-ShellRunasCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '<program>' } else { $CurrentWord }) -ResultType 'ParameterValue' -ToolTip 'Program to run with alternate credentials.')
    }

    $seen = @{}
    $unique = foreach ($item in $results) {
        if ($seen.ContainsKey($item.CompletionText)) { continue }
        $seen[$item.CompletionText] = $true
        $item
    }
    @($unique)
}

function Complete-ShellRunas {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $state = Get-ShellRunasArgumentState -CommandAst $CommandAst -WordToComplete $WordToComplete -CursorPosition $CursorPosition
    $currentWord = $state.CurrentWord
    $tokensBeforeCurrent = @($state.TokensBeforeCurrent)
    $mode = $null
    $quiet = $false
    $program = $null

    foreach ($token in $tokensBeforeCurrent) {
        $lowerToken = $token.ToLowerInvariant()
        if ($lowerToken -eq '/reg') { $mode = 'Register'; continue }
        if ($lowerToken -eq '/regnetonly') { $mode = 'RegisterNetOnly'; continue }
        if ($lowerToken -eq '/unreg') { $mode = 'Unregister'; continue }
        if ($lowerToken -eq '/quiet') { $quiet = $true; continue }
        if ($lowerToken -eq '/netonly' -and -not $mode) { continue }

        if (-not $program) {
            $program = $token
            continue
        }
    }

    if ($program) {
        return @(New-ShellRunasCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($currentWord)) { '<argument>' } else { $currentWord }) -ResultType 'ParameterValue' -ToolTip 'ShellRunas passes later arguments through without local enumeration.')
    }

    if (-not $mode -and -not [string]::IsNullOrWhiteSpace($currentWord) -and -not $currentWord.StartsWith('/')) {
        return Get-ShellRunasProgramCompletions -CurrentWord $currentWord
    }

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $mode) {
        foreach ($item in @(
                @{ Token = '/reg'; Description = 'Register the ShellRunas shell context-menu entry.' }
                @{ Token = '/regnetonly'; Description = 'Register the Shell /netonly context-menu entry.' }
                @{ Token = '/unreg'; Description = 'Unregister the ShellRunas shell context-menu entry.' }
                @{ Token = '/netonly'; Description = 'Use specified credentials for remote access only when launching a program.' }
            )) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $item.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-ShellRunasCompletionResult -CompletionText $item.Token -ResultType 'ParameterName' -ToolTip $item.Description))
            }
        }

        if ([string]::IsNullOrWhiteSpace($currentWord) -or -not $currentWord.StartsWith('/')) {
            foreach ($item in @(Get-ShellRunasProgramCompletions -CurrentWord $currentWord)) {
                [void]$results.Add($item)
            }
        }

        return @($results.ToArray())
    }

    if (($mode -in @('Register', 'RegisterNetOnly', 'Unregister')) -and -not $quiet) {
        if ([string]::IsNullOrWhiteSpace($currentWord) -or '/quiet'.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-ShellRunasCompletionResult -CompletionText '/quiet' -ResultType 'ParameterName' -ToolTip 'Register or unregister without showing a result dialog.'))
        }
        return @($results.ToArray())
    }

    Get-ShellRunasProgramCompletions -CurrentWord $currentWord
}

function Ensure-ShellRunasCommandAlias {
    $existingAlias = Get-Alias -Name shellrunas -ErrorAction SilentlyContinue
    if ($existingAlias) { return }

    $exeCommand = Get-Command -Name shellrunas.exe -ErrorAction SilentlyContinue
    if (-not $exeCommand) { return }

    $bareCommand = Get-Command -Name shellrunas -ErrorAction SilentlyContinue
    if ($bareCommand -and $bareCommand.CommandType -ne 'Application') { return }

    Set-Alias -Name shellrunas -Value shellrunas.exe -Option AllScope -Scope Global
}

Ensure-ShellRunasCommandAlias

Register-ArgumentCompleter -Native -CommandName @('shellrunas', 'shellrunas.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-ShellRunas -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
