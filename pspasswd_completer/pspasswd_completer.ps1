# pspasswd tab completion for PowerShell
# Static native completer for PsPasswd with safe remote and account placeholders.

Set-StrictMode -Version 2.0

function New-PsPasswdCompletionResult {
    param([string]$CompletionText, [string]$ResultType, [string]$ToolTip, [string]$ListItemText)
    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }
    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

function Get-PsPasswdCurrentToken {
    param([string]$Line, [int]$CursorPosition, [string]$Fallback)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $Fallback }
    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') { return '' }
    $parts = @([regex]::Matches($prefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) { return $parts[-1] }
    $Fallback
}

function Remove-PsPasswdOuterQuotes {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) { return $Value.Substring(1, $Value.Length - 2) }
    $Value.TrimStart('"')
}

function ConvertTo-PsPasswdQuotedValue {
    param([string]$Value, [bool]$AlwaysQuote = $false)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + $Value.Replace('`', '``').Replace('"', '`"') + '"'
    }
    $Value
}

function Get-PsPasswdArgumentState {
    param([System.Management.Automation.Language.CommandAst]$CommandAst, [string]$WordToComplete, [int]$CursorPosition)
    # $CursorPosition is line-absolute; the extent text is command-relative.
    $relativeCursor = [Math]::Max(0, $CursorPosition - $CommandAst.Extent.StartOffset)
    $currentWord = if ([string]::IsNullOrEmpty($WordToComplete)) {
        ''
    } else {
        Get-PsPasswdCurrentToken -Line $CommandAst.Extent.Text -CursorPosition $relativeCursor -Fallback $WordToComplete
    }
    # Only elements that end at or before the cursor are established state; a token to the
    # right of the caret must not be consumed as the Account or NewPassword positional.
    $tokens = @($CommandAst.CommandElements | Select-Object -Skip 1 | Where-Object { $_.Extent.EndOffset -le $CursorPosition } | ForEach-Object { $_.Extent.Text })
    $tokensBeforeCurrent = @($tokens)
    if (-not [string]::IsNullOrEmpty($currentWord) -and $tokensBeforeCurrent.Count -gt 0 -and $tokensBeforeCurrent[-1] -eq $currentWord) {
        $tokensBeforeCurrent = @($tokensBeforeCurrent | Select-Object -First ($tokensBeforeCurrent.Count - 1))
    }
    [pscustomobject]@{
        CurrentWord         = $currentWord
        TokensBeforeCurrent = $tokensBeforeCurrent
    }
}

function Get-PsPasswdAtFileCompletions {
    param([string]$CurrentWord)
    $trimmed = Remove-PsPasswdOuterQuotes -Value $CurrentWord
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
        New-PsPasswdCompletionResult -CompletionText (ConvertTo-PsPasswdQuotedValue -Value ('@' + $completionPath) -AlwaysQuote:$alwaysQuote) -ListItemText ('@' + $item.Name) -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.'
    }
    if (@($results).Count -eq 0) {
        return @(New-PsPasswdCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '@file' } else { $CurrentWord }) -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.')
    }
    @($results)
}

function Complete-PsPasswd {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $state = Get-PsPasswdArgumentState -CommandAst $CommandAst -WordToComplete $WordToComplete -CursorPosition $CursorPosition
    $currentWord = $state.CurrentWord
    $tokensBeforeCurrent = @($state.TokensBeforeCurrent)
    $used = @{}
    $valueContext = $null
    $remoteTarget = $null
    $account = $null
    $newPassword = $null

    for ($i = 0; $i -lt $tokensBeforeCurrent.Count; $i++) {
        $token = $tokensBeforeCurrent[$i]
        $lowerToken = $token.ToLowerInvariant()
        if ($lowerToken -eq '-u') { $used['-u'] = $true; if ($i -eq ($tokensBeforeCurrent.Count - 1)) { $valueContext = 'User'; break }; $i++; continue }
        if ($lowerToken -eq '-p') { $used['-p'] = $true; if ($i -eq ($tokensBeforeCurrent.Count - 1)) { $valueContext = 'Password'; break }; $i++; continue }
        if ($lowerToken -eq '-nobanner') { $used['-nobanner'] = $true; continue }
        if ($lowerToken -eq '-accepteula') { $used['-accepteula'] = $true; continue }
        if ($lowerToken -eq '-?') { $used['-?'] = $true; continue }
        if ($lowerToken -eq '/?') { $used['/?'] = $true; continue }

        if (-not $remoteTarget -and ((Remove-PsPasswdOuterQuotes -Value $token).StartsWith('\\') -or (Remove-PsPasswdOuterQuotes -Value $token).StartsWith('@'))) {
            $remoteTarget = $token
            continue
        }
        if (-not $account) { $account = $token; continue }
        if (-not $newPassword) { $newPassword = $token }
    }

    switch ($valueContext) {
        'User' {
            return @(
                New-PsPasswdCompletionResult -CompletionText '<username>' -ResultType 'ParameterValue' -ToolTip 'Remote user name.'
                New-PsPasswdCompletionResult -CompletionText '<domain\user>' -ResultType 'ParameterValue' -ToolTip 'Remote user name in Domain\User syntax.'
            )
        }
        'Password' {
            return @(New-PsPasswdCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($currentWord)) { '<password>' } else { $currentWord }) -ResultType 'ParameterValue' -ToolTip 'Remote password value.')
        }
    }

    if ($currentWord.StartsWith('@') -or $currentWord.StartsWith('"@')) {
        return Get-PsPasswdAtFileCompletions -CurrentWord $currentWord
    }

    if ($account -and -not $newPassword) {
        return @(New-PsPasswdCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($currentWord)) { '<new-password>' } else { $currentWord }) -ResultType 'ParameterValue' -ToolTip 'New password. Completion intentionally does not enumerate or transform secrets.')
    }

    # pspasswd [\\computer|@file] [-u Username [-p Password]] <Account> [NewPassword]: nothing follows NewPassword.
    if ($account -and $newPassword) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $remoteTarget) {
        foreach ($target in @('\\<computer>', '\\localhost', '\\*', '@file')) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $target.StartsWith((Remove-PsPasswdOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsPasswdCompletionResult -CompletionText $target -ResultType 'ParameterValue' -ToolTip 'Remote target placeholder for local-account password changes.'))
            }
        }
    }

    foreach ($switchSpec in @(
            @{ Token = '-u'; Description = 'Optional user name for remote login.'; NeedsRemote = $true; BeforeAccount = $true }
            @{ Token = '-p'; Description = 'Optional password for remote login.'; NeedsRemote = $true; BeforeAccount = $true }
            @{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.' }
            @{ Token = '-accepteula'; Description = 'Suppress the Sysinternals EULA dialog on first run.' }
            @{ Token = '-?'; Description = 'Display PsPasswd help.' }
            @{ Token = '/?'; Description = 'Display PsPasswd help.' }
        )) {
        if ($used.ContainsKey($switchSpec.Token.ToLowerInvariant())) { continue }
        if ($switchSpec.ContainsKey('NeedsRemote') -and $switchSpec.NeedsRemote -and -not $remoteTarget) { continue }
        if ($switchSpec.ContainsKey('BeforeAccount') -and $switchSpec.BeforeAccount -and $account) { continue }
        if (-not [string]::IsNullOrWhiteSpace($currentWord) -and -not $switchSpec.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        [void]$results.Add((New-PsPasswdCompletionResult -CompletionText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description))
    }

    if (-not $account) {
        foreach ($hint in @('<account>', '<domain\account>', 'Administrator', 'CONTOSO\User')) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $hint.StartsWith((Remove-PsPasswdOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsPasswdCompletionResult -CompletionText $hint -ResultType 'ParameterValue' -ToolTip 'Local account or domain account placeholder.'))
            }
        }
    }

    @($results.ToArray())
}


Register-ArgumentCompleter -Native -CommandName @('pspasswd', 'pspasswd.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsPasswd -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
