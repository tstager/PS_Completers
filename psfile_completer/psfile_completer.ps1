# psfile tab completion for PowerShell
# Static native completer for PsFile with non-enumerating remote and file-id/path hints.

Set-StrictMode -Version 2.0

function New-PsFileCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }
    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

function Get-PsFileCurrentToken {
    param([string]$Line, [int]$CursorPosition, [string]$Fallback)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $Fallback }
    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') { return '' }
    $parts = @([regex]::Matches($prefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) { return $parts[-1] }
    $Fallback
}

function Get-PsFileArgumentState {
    param([System.Management.Automation.Language.CommandAst]$CommandAst, [string]$WordToComplete, [int]$CursorPosition)
    $currentWord = if ([string]::IsNullOrEmpty($WordToComplete)) {
        ''
    } else {
        Get-PsFileCurrentToken -Line $CommandAst.Extent.Text -CursorPosition $CursorPosition -Fallback $WordToComplete
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

function Complete-PsFile {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $state = Get-PsFileArgumentState -CommandAst $CommandAst -WordToComplete $WordToComplete -CursorPosition $CursorPosition
    $currentWord = $state.CurrentWord
    $tokensBeforeCurrent = @($state.TokensBeforeCurrent)
    $used = @{}
    $valueContext = $null
    $remoteTarget = $null
    $identifier = $null
    $closeMode = $false

    for ($i = 0; $i -lt $tokensBeforeCurrent.Count; $i++) {
        $token = $tokensBeforeCurrent[$i]
        $lowerToken = $token.ToLowerInvariant()
        if ($lowerToken -eq '-u') {
            $used['-u'] = $true
            if ($i -eq ($tokensBeforeCurrent.Count - 1)) { $valueContext = 'User'; break }
            $i++
            continue
        }
        if ($lowerToken -eq '-p') {
            $used['-p'] = $true
            if ($i -eq ($tokensBeforeCurrent.Count - 1)) { $valueContext = 'Password'; break }
            $i++
            continue
        }
        if ($lowerToken -eq '-c') {
            $used['-c'] = $true
            $closeMode = $true
            continue
        }
        if ($lowerToken -eq '-nobanner') { $used['-nobanner'] = $true; continue }
        if ($lowerToken -eq '-?') { $used['-?'] = $true; continue }
        if ($lowerToken -eq '/?') { $used['/?'] = $true; continue }

        if (-not $remoteTarget -and $token.StartsWith('\\')) {
            $remoteTarget = $token
            continue
        }

        if (-not $identifier) {
            $identifier = $token
        }
    }

    switch ($valueContext) {
        'User' {
            return @(
                New-PsFileCompletionResult -CompletionText '<username>' -ResultType 'ParameterValue' -ToolTip 'Remote user name.'
                New-PsFileCompletionResult -CompletionText '<domain\user>' -ResultType 'ParameterValue' -ToolTip 'Remote user name in Domain\User syntax.'
            )
        }
        'Password' {
            $value = if ([string]::IsNullOrWhiteSpace($currentWord)) { '<password>' } else { $currentWord }
            return @(New-PsFileCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'Remote password value.')
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $remoteTarget) {
        foreach ($target in @('\\<RemoteComputer>', '\\localhost', '\\*')) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $target.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsFileCompletionResult -CompletionText $target -ResultType 'ParameterValue' -ToolTip 'Remote computer placeholder for PsFile.'))
            }
        }
    }

    foreach ($switchSpec in @(
            @{ Token = '-u'; Description = 'Optional user name for remote login.'; NeedsRemote = $true }
            @{ Token = '-p'; Description = 'Optional password for remote login.'; NeedsRemote = $true }
            @{ Token = '-c'; Description = 'Close the file identified by the specified file ID.' }
            @{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.' }
            @{ Token = '-?'; Description = 'Display PsFile help.' }
            @{ Token = '/?'; Description = 'Display PsFile help.' }
        )) {
        if ($used.ContainsKey($switchSpec.Token.ToLowerInvariant())) { continue }
        if ($switchSpec.ContainsKey('NeedsRemote') -and $switchSpec.NeedsRemote -and -not $remoteTarget) { continue }
        if ($switchSpec.Token -eq '-c' -and -not $identifier) { continue }
        if (-not [string]::IsNullOrWhiteSpace($currentWord) -and -not $switchSpec.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        [void]$results.Add((New-PsFileCompletionResult -CompletionText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description))
    }

    if (-not $identifier) {
        foreach ($value in @('<file-id>', '<path>', '"C:\path\fragment*"')) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $value.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase) -or -not $currentWord.StartsWith('-')) {
                [void]$results.Add((New-PsFileCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'PsFile file identifier or path pattern.'))
            }
        }
    } elseif (-not $closeMode) {
        [void]$results.Add((New-PsFileCompletionResult -CompletionText '-c' -ResultType 'ParameterName' -ToolTip 'Close the file identified by the specified file ID. This is destructive and intentionally not executed by completion.'))
    } elseif (-not [string]::IsNullOrWhiteSpace($currentWord)) {
        [void]$results.Add((New-PsFileCompletionResult -CompletionText $currentWord -ResultType 'ParameterValue' -ToolTip 'PsFile does not take additional values here.'))
    }

    @($results.ToArray())
}

function Ensure-PsFileCommandAlias {
    $existingAlias = Get-Alias -Name psfile -ErrorAction SilentlyContinue
    if ($existingAlias) { return }

    $exeCommand = Get-Command -Name psfile.exe -ErrorAction SilentlyContinue
    if (-not $exeCommand) { return }

    $bareCommand = Get-Command -Name psfile -ErrorAction SilentlyContinue
    if ($bareCommand -and $bareCommand.CommandType -ne 'Application') { return }

    Set-Alias -Name psfile -Value psfile.exe -Option AllScope -Scope Global
}

Ensure-PsFileCommandAlias

Register-ArgumentCompleter -Native -CommandName @('psfile', 'psfile.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsFile -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
