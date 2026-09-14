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

function Get-PsFileSwitchCatalog {
    @(
        @{ Token = '-u'; Description = 'Specifies optional user name for login to the remote computer.'; NeedsRemote = $true; NeedsIdentifier = $false; SlashOnly = $false }
        @{ Token = '-p'; Description = 'Specifies password for the user name given with -u.'; NeedsRemote = $true; NeedsIdentifier = $false; SlashOnly = $false }
        @{ Token = '-c'; Description = 'Closes the file identified by the preceding file Id. Destructive; completion never runs it.'; NeedsRemote = $false; NeedsIdentifier = $true; SlashOnly = $false }
        @{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.'; NeedsRemote = $false; NeedsIdentifier = $false; SlashOnly = $false }
        @{ Token = '-accepteula'; Description = 'Suppress the first-run EULA dialog; required for unattended use.'; NeedsRemote = $false; NeedsIdentifier = $false; SlashOnly = $false }
        @{ Token = '-?'; Description = 'Display PsFile help.'; NeedsRemote = $false; NeedsIdentifier = $false; SlashOnly = $false }
        @{ Token = '/?'; Description = 'Display PsFile help.'; NeedsRemote = $false; NeedsIdentifier = $false; SlashOnly = $false }
        @{ Token = '/nobanner'; Description = 'Slash form of -nobanner.'; NeedsRemote = $false; NeedsIdentifier = $false; SlashOnly = $true }
        @{ Token = '/accepteula'; Description = 'Slash form of -accepteula.'; NeedsRemote = $false; NeedsIdentifier = $false; SlashOnly = $true }
    )
}

function Get-PsFileSwitchKey {
    param([string]$Token)

    if ([string]::IsNullOrEmpty($Token)) { return '' }
    if (-not ($Token.StartsWith('-') -or $Token.StartsWith('/'))) { return '' }
    $Token.Substring(1).ToLowerInvariant()
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
    $relativeCursor = $CursorPosition - $CommandAst.Extent.StartOffset
    $currentWord = if ([string]::IsNullOrEmpty($WordToComplete)) {
        ''
    } else {
        Get-PsFileCurrentToken -Line $CommandAst.Extent.Text -CursorPosition $relativeCursor -Fallback $WordToComplete
    }
    $tokens = @($CommandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text })
    $tokensBeforeCurrent = @($tokens)
    if (-not [string]::IsNullOrEmpty($currentWord) -and $tokensBeforeCurrent.Count -gt 0 -and $tokensBeforeCurrent[-1] -eq $currentWord) {
        $tokensBeforeCurrent = @($tokensBeforeCurrent | Select-Object -First ($tokensBeforeCurrent.Count - 1))
    }

    [pscustomobject]@{
        CurrentWord         = $currentWord
        TokensBeforeCurrent = $tokensBeforeCurrent
    }
}

function Add-PsFileResult {
    param(
        [System.Collections.Generic.List[object]]$Results,
        [System.Collections.Generic.HashSet[string]]$Seen,
        [string]$CurrentWord,
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip
    )

    if (-not [string]::IsNullOrEmpty($CurrentWord) -and
        -not $CompletionText.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }
    if (-not $Seen.Add($CompletionText)) { return }
    [void]$Results.Add((New-PsFileCompletionResult -CompletionText $CompletionText -ResultType $ResultType -ToolTip $ToolTip))
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
        $key = Get-PsFileSwitchKey -Token $token
        if ($key -eq 'u') {
            $used['u'] = $true
            if ($i -eq ($tokensBeforeCurrent.Count - 1)) { $valueContext = 'User'; break }
            $i++
            continue
        }
        if ($key -eq 'p') {
            $used['p'] = $true
            if ($i -eq ($tokensBeforeCurrent.Count - 1)) { $valueContext = 'Password'; break }
            $i++
            continue
        }
        if ($key -eq 'c') {
            $used['c'] = $true
            $closeMode = $true
            continue
        }
        if ($key) {
            # Any other dash- or slash-prefixed token is a switch, never the file identifier.
            $used[$key] = $true
            continue
        }

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

    $results = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Usage: psfile [\\RemoteComputer [-u Username [-p Password]]] [[Id | path] [-c]]
    # The remote target is only legal before the file identifier.
    if (-not $remoteTarget -and -not $identifier -and -not $closeMode) {
        foreach ($target in @('\\<RemoteComputer>', '\\localhost', '\\*')) {
            Add-PsFileResult -Results $results -Seen $seen -CurrentWord $currentWord -CompletionText $target -ResultType 'ParameterValue' -ToolTip 'Remote computer placeholder for PsFile.'
        }
    }

    foreach ($switchSpec in Get-PsFileSwitchCatalog) {
        if ($used.ContainsKey((Get-PsFileSwitchKey -Token $switchSpec.Token))) { continue }
        if ($switchSpec.NeedsRemote -and -not $remoteTarget) { continue }
        if ($switchSpec.NeedsIdentifier -and -not $identifier) { continue }
        if ($switchSpec.SlashOnly -and -not $currentWord.StartsWith('/')) { continue }
        Add-PsFileResult -Results $results -Seen $seen -CurrentWord $currentWord -CompletionText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description
    }

    if (-not $identifier -and -not $closeMode) {
        foreach ($value in @('<file-id>', '<path>', '"C:\path\fragment*"')) {
            Add-PsFileResult -Results $results -Seen $seen -CurrentWord $currentWord -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'PsFile file identifier or path pattern.'
        }
    }

    @($results.ToArray())
}


Register-ArgumentCompleter -Native -CommandName @('psfile', 'psfile.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsFile -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
