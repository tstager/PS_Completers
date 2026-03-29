# psinfo tab completion for PowerShell
# Static-first native completer for PsInfo with safe filter and remote-target hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name PsInfoCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PsInfoCompletionCatalog = @{
        Switches = @(
            [pscustomobject]@{ Token = '-u'; Description = 'Optional user name for login to the remote computer.'; TakesValue = $true; ValueKind = 'User' }
            [pscustomobject]@{ Token = '-p'; Description = 'Optional password for the remote computer user name.'; TakesValue = $true; ValueKind = 'Password' }
            [pscustomobject]@{ Token = '-h'; Description = 'Show installed hotfixes.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-s'; Description = 'Show installed software.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-d'; Description = 'Show disk volume information.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-c'; Description = 'Print in CSV format.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-t'; Description = 'Delimiter used with -c. Use "\t" for tab.'; TakesValue = $true; ValueKind = 'Delimiter' }
            [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-?'; Description = 'Display PsInfo help.'; TakesValue = $false; Terminal = $true }
            [pscustomobject]@{ Token = '/?'; Description = 'Display PsInfo help.'; TakesValue = $false; Terminal = $true }
        )
        FilterHints = @('host', 'uptime', 'kernel', 'processor', 'memory', 'service pack', 'build', 'install date')
        DelimiterHints = @(',', ';', '|', ':', '\t')
    }
}

function New-PsInfoCompletionResult {
    param([string]$CompletionText, [string]$ResultType, [string]$ToolTip, [string]$ListItemText)
    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }
    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

function Get-PsInfoCurrentToken {
    param([string]$Line, [int]$CursorPosition, [string]$Fallback)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $Fallback }
    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') { return '' }
    $parts = @([regex]::Matches($prefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) { return $parts[-1] }
    $Fallback
}

function Remove-PsInfoOuterQuotes {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) { return $Value.Substring(1, $Value.Length - 2) }
    $Value.TrimStart('"')
}

function ConvertTo-PsInfoQuotedValue {
    param([string]$Value, [bool]$AlwaysQuote = $false)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + $Value.Replace('`', '``').Replace('"', '`"') + '"'
    }
    $Value
}

function Get-PsInfoArgumentState {
    param([System.Management.Automation.Language.CommandAst]$CommandAst, [string]$WordToComplete, [int]$CursorPosition)
    $currentWord = if ([string]::IsNullOrEmpty($WordToComplete)) {
        ''
    } else {
        Get-PsInfoCurrentToken -Line $CommandAst.Extent.Text -CursorPosition $CursorPosition -Fallback $WordToComplete
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

function Get-PsInfoAtFileCompletions {
    param([string]$CurrentWord)
    $trimmed = Remove-PsInfoOuterQuotes -Value $CurrentWord
    if (-not $trimmed.StartsWith('@')) { return @() }
    $pathPortion = $trimmed.Substring(1)
    if ([string]::IsNullOrWhiteSpace($pathPortion)) {
        $parent = '.'
        $leaf = ''
    } else {
        $parent = Split-Path -Path $pathPortion -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) { $parent = '.' }
        $leaf = Split-Path -Path $pathPortion -Leaf
    }
    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('"')

    $results = foreach ($item in @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)) {
        $completionPath = if ($pathPortion -and -not [System.IO.Path]::IsPathRooted($pathPortion) -and $parent -ne '.') {
            Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($parent -eq '.') {
            $item.Name
        } else {
            $item.FullName
        }

        if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionPath += [System.IO.Path]::DirectorySeparatorChar
        }

        New-PsInfoCompletionResult -CompletionText (ConvertTo-PsInfoQuotedValue -Value ('@' + $completionPath) -AlwaysQuote:$alwaysQuote) -ListItemText ('@' + $item.Name) -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.'
    }

    if (@($results).Count -eq 0) {
        return @(
            New-PsInfoCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '@file' } else { $CurrentWord }) -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.'
        )
    }

    @($results)
}

function Complete-PsInfo {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $state = Get-PsInfoArgumentState -CommandAst $CommandAst -WordToComplete $WordToComplete -CursorPosition $CursorPosition
    $currentWord = $state.CurrentWord
    $tokensBeforeCurrent = @($state.TokensBeforeCurrent)
    $switchLookup = @{}
    foreach ($spec in $script:PsInfoCompletionCatalog.Switches) { $switchLookup[$spec.Token.ToLowerInvariant()] = $spec }
    $used = @{}
    $valueContext = $null
    $remoteTarget = $null
    $filter = $null

    for ($i = 0; $i -lt $tokensBeforeCurrent.Count; $i++) {
        $token = $tokensBeforeCurrent[$i]
        $key = $token.ToLowerInvariant()
        if ($switchLookup.ContainsKey($key)) {
            $used[$key] = $true
            $spec = $switchLookup[$key]
            if ($spec.TakesValue) {
                if ($i -eq ($tokensBeforeCurrent.Count - 1)) { $valueContext = $spec.ValueKind; break }
                $i++
            }
            continue
        }

        if (-not $remoteTarget -and ((Remove-PsInfoOuterQuotes -Value $token).StartsWith('\\') -or (Remove-PsInfoOuterQuotes -Value $token).StartsWith('@'))) {
            $remoteTarget = $token
            continue
        }

        if (-not $filter) { $filter = $token }
    }

    switch ($valueContext) {
        'User' {
            return @(
                New-PsInfoCompletionResult -CompletionText '<username>' -ResultType 'ParameterValue' -ToolTip 'Remote user name.'
                New-PsInfoCompletionResult -CompletionText '<domain\user>' -ResultType 'ParameterValue' -ToolTip 'Remote user name in Domain\User syntax.'
            )
        }
        'Password' {
            return @(New-PsInfoCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($currentWord)) { '<password>' } else { $currentWord }) -ResultType 'ParameterValue' -ToolTip 'Remote password value.')
        }
        'Delimiter' {
            return @($script:PsInfoCompletionCatalog.DelimiterHints | ForEach-Object { New-PsInfoCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Delimiter used with -c.' })
        }
    }

    if ($currentWord.StartsWith('@') -or $currentWord.StartsWith('"@')) {
        return Get-PsInfoAtFileCompletions -CurrentWord $currentWord
    }

    $results = New-Object System.Collections.Generic.List[object]

    if (-not $remoteTarget) {
        foreach ($target in @('\\<computer>', '\\localhost', '\\*', '@file')) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $target.StartsWith((Remove-PsInfoOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsInfoCompletionResult -CompletionText $target -ResultType 'ParameterValue' -ToolTip 'Remote target placeholder for PsInfo.'))
            }
        }
    }

    foreach ($spec in $script:PsInfoCompletionCatalog.Switches) {
        $key = $spec.Token.ToLowerInvariant()
        if ($used.ContainsKey($key)) { continue }
        $isTerminal = [bool]($spec.PSObject.Properties['Terminal'] -and $spec.Terminal)
        if ($isTerminal -and $tokensBeforeCurrent.Count -gt 0) { continue }
        if (($key -in @('-u', '-p')) -and -not $remoteTarget) { continue }
        if ($key -eq '-t' -and -not $used.ContainsKey('-c')) { continue }
        if (-not [string]::IsNullOrWhiteSpace($currentWord) -and -not $spec.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        [void]$results.Add((New-PsInfoCompletionResult -CompletionText $spec.Token -ResultType 'ParameterName' -ToolTip $spec.Description))
    }

    if (-not $filter) {
        foreach ($hint in $script:PsInfoCompletionCatalog.FilterHints) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $hint.StartsWith((Remove-PsInfoOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsInfoCompletionResult -CompletionText $hint -ResultType 'ParameterValue' -ToolTip 'Sample PsInfo filter field hint.'))
            }
        }
    }

    @($results.ToArray())
}

function Ensure-PsInfoCommandAlias {
    $existingAlias = Get-Alias -Name psinfo -ErrorAction SilentlyContinue
    if ($existingAlias) { return }

    $exeCommand = Get-Command -Name psinfo.exe -ErrorAction SilentlyContinue
    if (-not $exeCommand) { return }

    $bareCommand = Get-Command -Name psinfo -ErrorAction SilentlyContinue
    if ($bareCommand -and $bareCommand.CommandType -ne 'Application') { return }

    Set-Alias -Name psinfo -Value psinfo.exe -Option AllScope -Scope Global
}

Ensure-PsInfoCommandAlias

Register-ArgumentCompleter -Native -CommandName @('psinfo', 'psinfo.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsInfo -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
