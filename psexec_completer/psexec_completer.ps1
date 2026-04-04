# psexec tab completion for PowerShell
# Static-first native completer for PsExec with safe remote placeholders and conservative command-tail handling.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name PsExecCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PsExecCompletionCatalog = @{
        Switches = @(
            [pscustomobject]@{ Token = '-u'; Description = 'Optional user name for login to the remote computer.'; TakesValue = $true; ValueKind = 'User' }
            [pscustomobject]@{ Token = '-p'; Description = 'Optional password for the remote user name.'; TakesValue = $true; ValueKind = 'Password' }
            [pscustomobject]@{ Token = '-n'; Description = 'Timeout in seconds connecting to remote computers.'; TakesValue = $true; ValueKind = 'Timeout' }
            [pscustomobject]@{ Token = '-r'; Description = 'Name of the remote service to create or interact with.'; TakesValue = $true; ValueKind = 'ServiceName' }
            [pscustomobject]@{ Token = '-h'; Description = 'Run with the account''s elevated token when available.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-l'; Description = 'Run process as a limited user.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-s'; Description = 'Run the remote process in the System account.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-e'; Description = 'Do not load the specified account''s profile.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-x'; Description = 'Display UI on the Winlogon secure desktop (local only).' ; TakesValue = $false }
            [pscustomobject]@{ Token = '-i'; Description = 'Run the program interactively in the specified session.'; TakesValue = $true; ValueKind = 'Session' }
            [pscustomobject]@{ Token = '-c'; Description = 'Copy the specified program to the remote system for execution.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-f'; Description = 'Copy the specified program even if it already exists remotely.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-v'; Description = 'Copy only if the local file is newer or a higher version.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-w'; Description = 'Set the remote working directory for the process.'; TakesValue = $true; ValueKind = 'RemoteDirectory' }
            [pscustomobject]@{ Token = '-d'; Description = 'Do not wait for process termination.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-g'; Description = 'Set the primary thread processor group.'; TakesValue = $true; ValueKind = 'ProcessorGroup' }
            [pscustomobject]@{ Token = '-a'; Description = 'Restrict the application to the specified CPUs.'; TakesValue = $true; ValueKind = 'Affinity' }
            [pscustomobject]@{ Token = '-arm'; Description = 'Indicate that the remote computer is ARM architecture.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-verbose'; Description = 'Enable verbose PsExec status output.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-accepteula'; Description = 'Suppress the Sysinternals license dialog.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-low'; Description = 'Run the process at low priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-belownormal'; Description = 'Run the process below normal priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-abovenormal'; Description = 'Run the process above normal priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-high'; Description = 'Run the process at high priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-realtime'; Description = 'Run the process at realtime priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-background'; Description = 'Run the process at low I/O and memory priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-?'; Description = 'Display PsExec help.'; TakesValue = $false; Terminal = $true }
            [pscustomobject]@{ Token = '/?'; Description = 'Display PsExec help.'; TakesValue = $false; Terminal = $true }
        )
        TimeoutHints = @('1', '2', '5', '10', '30', '60')
        SessionHints = @('0', '1', '2', '<session-id>')
        GroupHints   = @('0', '1', '<group-id>')
        AffinityHints = @('0', '1', '0,1', '1,2', '<cpu-list>')
    }
}

function New-PsExecCompletionResult {
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

function Get-PsExecCurrentToken {
    param([string]$Line, [int]$CursorPosition, [string]$Fallback)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $Fallback }
    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') { return '' }
    $parts = @([regex]::Matches($prefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) { return $parts[-1] }
    $Fallback
}

function Remove-PsExecOuterQuotes {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }
    $Value.TrimStart('"')
}

function ConvertTo-PsExecQuotedValue {
    param([string]$Value, [bool]$AlwaysQuote = $false)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + $Value.Replace('`', '``').Replace('"', '`"') + '"'
    }
    $Value
}

function Get-PsExecArgumentState {
    param([System.Management.Automation.Language.CommandAst]$CommandAst, [string]$WordToComplete, [int]$CursorPosition)

    $currentWord = if ([string]::IsNullOrEmpty($WordToComplete)) {
        ''
    } else {
        Get-PsExecCurrentToken -Line $CommandAst.Extent.Text -CursorPosition $CursorPosition -Fallback $WordToComplete
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
        CurrentWord        = $currentWord
        TokensBeforeCurrent = $tokensBeforeCurrent
    }
}

function Get-PsExecAtFileCompletions {
    param([string]$CurrentWord)

    $trimmed = Remove-PsExecOuterQuotes -Value $CurrentWord
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
    $items = @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('"')
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($item in $items) {
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

        [void]$results.Add((New-PsExecCompletionResult -CompletionText (ConvertTo-PsExecQuotedValue -Value ('@' + $completionPath) -AlwaysQuote:$alwaysQuote) -ListItemText ('@' + $item.Name) -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.'))
    }

    if ($results.Count -eq 0) {
        $placeholder = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '@file' } else { $CurrentWord }
        return @(
            New-PsExecCompletionResult -CompletionText $placeholder -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.'
        )
    }

    @($results.ToArray())
}

function Get-PsExecExecutableCompletions {
    param([string]$CurrentWord)

    $trimmed = Remove-PsExecOuterQuotes -Value $CurrentWord
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('"')
    $results = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        foreach ($sample in @('cmd.exe', 'powershell.exe', 'pwsh.exe')) {
            [void]$results.Add((New-PsExecCompletionResult -CompletionText $sample -ResultType 'ParameterValue' -ToolTip 'Local executable or script to copy and run with -c.'))
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

            [void]$results.Add((New-PsExecCompletionResult -CompletionText (ConvertTo-PsExecQuotedValue -Value $completionPath -AlwaysQuote:$alwaysQuote) -ResultType $(if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }) -ToolTip $item.FullName))
        }
    } else {
        foreach ($command in @(Get-Command -Name "$trimmed*" -CommandType Application -ErrorAction SilentlyContinue | Sort-Object -Property Name -Unique | Select-Object -First 20)) {
            [void]$results.Add((New-PsExecCompletionResult -CompletionText $command.Name -ResultType 'ParameterValue' -ToolTip ($command.Source ? $command.Source : $command.Name)))
        }
    }

    if ($results.Count -eq 0) {
        $completion = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '<local-command>' } else { $CurrentWord }
        return @(
            New-PsExecCompletionResult -CompletionText $completion -ResultType 'ParameterValue' -ToolTip 'Local executable or script to copy and run with -c.'
        )
    }

    $seen = @{}
    $unique = foreach ($item in $results) {
        if ($seen.ContainsKey($item.CompletionText)) { continue }
        $seen[$item.CompletionText] = $true
        $item
    }
    @($unique)
}

function Complete-PsExec {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $state = Get-PsExecArgumentState -CommandAst $CommandAst -WordToComplete $WordToComplete -CursorPosition $CursorPosition
    $currentWord = $state.CurrentWord
    $tokensBeforeCurrent = @($state.TokensBeforeCurrent)
    $usedSwitches = @{}
    $valueContext = $null
    $remoteTarget = $null
    $commandToken = $null
    $commandTail = @()
    $copyMode = $false
    $prioritySelected = $false

    $switchLookup = @{}
    foreach ($spec in $script:PsExecCompletionCatalog.Switches) {
        $switchLookup[$spec.Token.ToLowerInvariant()] = $spec
    }

    for ($i = 0; $i -lt $tokensBeforeCurrent.Count; $i++) {
        $token = $tokensBeforeCurrent[$i]
        $key = $token.ToLowerInvariant()

        if ($switchLookup.ContainsKey($key)) {
            $usedSwitches[$key] = $true
            $spec = $switchLookup[$key]
            if ($spec.PSObject.Properties['Group'] -and $spec.Group -eq 'Priority') { $prioritySelected = $true }
            if ($key -eq '-c') { $copyMode = $true }
            if ($spec.TakesValue) {
                if ($i -eq ($tokensBeforeCurrent.Count - 1)) {
                    $valueContext = $spec.ValueKind
                    break
                }

                $i++
            }
            continue
        }

        if (-not $remoteTarget -and ((Remove-PsExecOuterQuotes -Value $token).StartsWith('\\') -or (Remove-PsExecOuterQuotes -Value $token).StartsWith('@'))) {
            $remoteTarget = $token
            continue
        }

        if (-not $commandToken) {
            $commandToken = $token
            continue
        }

        $commandTail += $token
    }

    switch ($valueContext) {
        'User' {
            return @(
                New-PsExecCompletionResult -CompletionText '<username>' -ResultType 'ParameterValue' -ToolTip 'Remote user name.'
                New-PsExecCompletionResult -CompletionText '<domain\user>' -ResultType 'ParameterValue' -ToolTip 'Remote user name in Domain\User syntax.'
            )
        }
        'Password' {
            $value = if ([string]::IsNullOrWhiteSpace($currentWord)) { '<password>' } else { $currentWord }
            return @(New-PsExecCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'Remote password value.')
        }
        'Timeout' {
            return @($script:PsExecCompletionCatalog.TimeoutHints | ForEach-Object { New-PsExecCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Remote connection timeout in seconds.' })
        }
        'ServiceName' {
            return @(
                New-PsExecCompletionResult -CompletionText 'PSEXESVC' -ResultType 'ParameterValue' -ToolTip 'Default PsExec remote service name.'
                New-PsExecCompletionResult -CompletionText '<service-name>' -ResultType 'ParameterValue' -ToolTip 'Remote service name for PsExec.'
            )
        }
        'Session' {
            return @($script:PsExecCompletionCatalog.SessionHints | ForEach-Object { New-PsExecCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Interactive session number for -i.' })
        }
        'RemoteDirectory' {
            $value = if ([string]::IsNullOrWhiteSpace($currentWord)) { '<remote-directory>' } else { $currentWord }
            return @(New-PsExecCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'Remote working directory path for -w.')
        }
        'ProcessorGroup' {
            return @($script:PsExecCompletionCatalog.GroupHints | ForEach-Object { New-PsExecCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Processor group number for -g.' })
        }
        'Affinity' {
            return @($script:PsExecCompletionCatalog.AffinityHints | ForEach-Object { New-PsExecCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Comma-separated CPU list for -a.' })
        }
    }

    if ($currentWord.StartsWith('@') -or $currentWord.StartsWith('"@')) {
        return Get-PsExecAtFileCompletions -CurrentWord $currentWord
    }

    if ($copyMode -and -not $commandToken -and [string]::IsNullOrEmpty($currentWord)) {
        return Get-PsExecExecutableCompletions -CurrentWord $currentWord
    }

    if ($commandToken) {
        if ($copyMode -and -not $commandTail) {
            return Get-PsExecExecutableCompletions -CurrentWord $currentWord
        }

        $argumentValue = if ([string]::IsNullOrWhiteSpace($currentWord)) { '<argument>' } else { $currentWord }
        return @(New-PsExecCompletionResult -CompletionText $argumentValue -ResultType 'ParameterValue' -ToolTip 'Command tail is intentionally conservative and non-enumerating.')
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and -not $currentWord.StartsWith('-') -and -not $currentWord.StartsWith('\')) {
        if ($copyMode) {
            return Get-PsExecExecutableCompletions -CurrentWord $currentWord
        }

        return @(
            New-PsExecCompletionResult -CompletionText $currentWord -ResultType 'ParameterValue' -ToolTip 'Remote command or command path.'
            New-PsExecCompletionResult -CompletionText '<command>' -ResultType 'ParameterValue' -ToolTip 'Remote command or command path.'
        )
    }

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $remoteTarget) {
        foreach ($target in @('\\<computer>', '\\localhost', '\\*', '@file')) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $target.StartsWith((Remove-PsExecOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsExecCompletionResult -CompletionText $target -ResultType 'ParameterValue' -ToolTip 'PsExec remote target placeholder.'))
            }
        }
    }

    foreach ($spec in $script:PsExecCompletionCatalog.Switches) {
        $key = $spec.Token.ToLowerInvariant()
        $isTerminal = [bool]($spec.PSObject.Properties['Terminal'] -and $spec.Terminal)
        $isPriority = [bool]($spec.PSObject.Properties['Group'] -and $spec.Group -eq 'Priority')
        if ($isTerminal -and $tokensBeforeCurrent.Count -gt 0) { continue }
        if ($usedSwitches.ContainsKey($key)) { continue }
        if (($key -in @('-f', '-v')) -and -not $copyMode) { continue }
        if (($key -in @('-u', '-p')) -and -not $remoteTarget) { continue }
        if (($key -eq '-s' -and $usedSwitches.ContainsKey('-e')) -or ($key -eq '-e' -and $usedSwitches.ContainsKey('-s'))) { continue }
        if ($isPriority -and $prioritySelected) { continue }
        if (-not [string]::IsNullOrWhiteSpace($currentWord) -and -not $spec.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        [void]$results.Add((New-PsExecCompletionResult -CompletionText $spec.Token -ResultType 'ParameterName' -ToolTip $spec.Description))
    }

    if ($copyMode) {
        [void]$results.AddRange(@(Get-PsExecExecutableCompletions -CurrentWord $currentWord))
    } elseif (-not [string]::IsNullOrWhiteSpace($currentWord) -and -not $currentWord.StartsWith('-')) {
        [void]$results.Add((New-PsExecCompletionResult -CompletionText '<command>' -ResultType 'ParameterValue' -ToolTip 'Remote command or command path.'))
    }

    @($results.ToArray())
}

function Ensure-PsExecCommandAlias {
    $existingAlias = Get-Alias -Name psexec -ErrorAction SilentlyContinue
    if ($existingAlias) {
        return
    }

    $exeCommand = Get-Command -Name psexec.exe -ErrorAction SilentlyContinue
    if (-not $exeCommand) {
        return
    }

    $bareCommand = Get-Command -Name psexec -ErrorAction SilentlyContinue
    if ($bareCommand -and $bareCommand.CommandType -ne 'Application') {
        return
    }

    Set-Alias -Name psexec -Value psexec.exe -Option AllScope -Scope Global
}

Register-ArgumentCompleter -Native -CommandName @('psexec', 'psexec.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Ensure-PsExecCommandAlias
    Complete-PsExec -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
