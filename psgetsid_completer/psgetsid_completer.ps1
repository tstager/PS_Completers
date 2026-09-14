# psgetsid tab completion for PowerShell
# Builds a small static-native completer for PsGetsid with remote-target and identity-aware hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name PsGetsidCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:PsGetsidCompletionCatalog = @{
        Initialized            = $false
        SwitchInfo             = @{}
        FirstSlotIdentityHints = @('<account>', '<domain\user>', '<SID>')
        UsernameHints          = @('<username>', '<domain\user>')
        PasswordHints          = @('<password>')
    }
}

function New-PsGetsidCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Initialize-PsGetsidCompletionCatalog {
    if ($script:PsGetsidCompletionCatalog.Initialized) {
        return
    }

    $script:PsGetsidCompletionCatalog.SwitchInfo = @{
        '-u'        = @{
            CompletionText = '-u'
            Description    = 'Specifies the optional user name for login to the remote computer.'
        }
        '-p'        = @{
            CompletionText = '-p'
            Description    = 'Specifies the optional password for the remote user name.'
        }
        '-nobanner' = @{
            CompletionText = '-nobanner'
            Description    = 'Do not display the startup banner and copyright message.'
        }
        '-accepteula' = @{
            CompletionText = '-accepteula'
            Description    = 'Suppress the Sysinternals license dialog on first run.'
        }
        '-?'        = @{
            CompletionText = '-?'
            Description    = 'Displays PsGetsid help and terminates further argument completion.'
        }
        '/?'        = @{
            CompletionText = '/?'
            Description    = 'Displays PsGetsid help and terminates further argument completion.'
        }
    }

    $script:PsGetsidCompletionCatalog.Initialized = $true
}

function Remove-PsGetsidOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function ConvertTo-PsGetsidQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        $escaped = $Value.Replace('`', '``').Replace('"', '`"')
        return '"' + $escaped + '"'
    }

    $Value
}

function ConvertTo-PsGetsidSwitchKey {
    # PsTools accept both '-x' and '/x'; the catalog is keyed on the dash form.
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return ''
    }

    $key = $Token.ToLowerInvariant()
    if ($key.StartsWith('/') -and $key -ne '/?') {
        $key = '-' + $key.Substring(1)
    }

    $key
}

function Test-PsGetsidKnownSwitch {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    $script:PsGetsidCompletionCatalog.SwitchInfo.ContainsKey((ConvertTo-PsGetsidSwitchKey -Token $Token))
}

function Test-PsGetsidRemoteTargetToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    $unquoted = Remove-PsGetsidOuterQuotes -Value $Token
    $unquoted.StartsWith('\\') -or $unquoted.StartsWith('@')
}

function Get-PsGetsidRemoteTargetCandidates {
    $currentComputer = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
        $null
    } else {
        '\\' + $env:COMPUTERNAME
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    $candidates.Add([pscustomobject]@{
            CompletionText = '\\<computer>'
            ToolTip        = 'Remote computer name in PsGetsid remote-target form.'
        })
    $candidates.Add([pscustomobject]@{
            CompletionText = '\\localhost'
            ToolTip        = 'Loop back to the local machine using PsGetsid remote-target syntax.'
        })

    if ($currentComputer) {
        $candidates.Add([pscustomobject]@{
                CompletionText = $currentComputer
                ToolTip        = 'Current computer name in PsGetsid remote-target syntax.'
            })
    }

    $candidates.Add([pscustomobject]@{
            CompletionText = '\\*'
            ToolTip        = 'Wildcard remote target for all computers in the current domain.'
        })

    @($candidates.ToArray())
}

function Get-PsGetsidPlaceholderValueCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$Candidates,
        [string]$GenericToolTip
    )

    $typedValue = Remove-PsGetsidOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $candidate.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $results.Add((New-PsGetsidCompletionResult -CompletionText $candidate -ResultType 'ParameterValue' -ToolTip $GenericToolTip))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-PsGetsidCompletionResult -CompletionText $CurrentWord -ResultType 'ParameterValue' -ToolTip $GenericToolTip))
    }

    @($results.ToArray())
}

function Get-PsGetsidAtFileCompletions {
    param([string]$CurrentWord)

    $trimmedCurrentWord = Remove-PsGetsidOuterQuotes -Value $CurrentWord
    $pathPortion = if ($trimmedCurrentWord.StartsWith('@')) {
        $trimmedCurrentWord.Substring(1)
    } else {
        $trimmedCurrentWord
    }

    if ([string]::IsNullOrWhiteSpace($pathPortion)) {
        $parent = '.'
        $leaf = ''
    } else {
        $parent = Split-Path -Path $pathPortion -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $pathPortion -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('"')
    $items = @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)

    $results = @(foreach ($item in $items) {
        $completionPath = if ($pathPortion -and -not [System.IO.Path]::IsPathRooted($pathPortion) -and $parent -ne '.') {
            Join-Path -Path $parent -ChildPath $item.Name
        } else {
            $item.FullName
        }

        if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionPath += [System.IO.Path]::DirectorySeparatorChar
        }

        $completionText = ConvertTo-PsGetsidQuotedValue -Value ('@' + $completionPath) -AlwaysQuote:$alwaysQuote
        $resultType = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }
        New-PsGetsidCompletionResult -CompletionText $completionText -ResultType $resultType -ToolTip $item.FullName
    })

    if ($results.Count -gt 0) {
        return @($results)
    }

    if (-not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        return @(
            New-PsGetsidCompletionResult `
                -CompletionText $CurrentWord `
                -ResultType 'ParameterValue' `
                -ToolTip 'File containing remote computer names for @file syntax.'
        )
    }

    @(
        New-PsGetsidCompletionResult -CompletionText '@<file>' -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names, one per line.'
    )
}

function Get-PsGetsidRemoteTargetCompletions {
    param([string]$CurrentWord)

    $trimmedCurrentWord = Remove-PsGetsidOuterQuotes -Value $CurrentWord

    if ($trimmedCurrentWord.StartsWith('@')) {
        return @(Get-PsGetsidAtFileCompletions -CurrentWord $CurrentWord)
    }

    $results = New-Object System.Collections.Generic.List[object]
    $candidates = @(Get-PsGetsidRemoteTargetCandidates)

    if ([string]::IsNullOrWhiteSpace($trimmedCurrentWord)) {
        foreach ($candidate in $candidates) {
            $results.Add((New-PsGetsidCompletionResult -CompletionText $candidate.CompletionText -ResultType 'ParameterValue' -ToolTip $candidate.ToolTip))
        }

        $results.Add((New-PsGetsidCompletionResult -CompletionText '@<file>' -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names, one per line.'))
        return @($results.ToArray())
    }

    $listPrefix = ''
    $tail = $trimmedCurrentWord
    if ($trimmedCurrentWord.Contains(',')) {
        $lastComma = $trimmedCurrentWord.LastIndexOf(',')
        $listPrefix = $trimmedCurrentWord.Substring(0, $lastComma + 1)
        $tail = $trimmedCurrentWord.Substring($lastComma + 1)
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($tail) -and
            -not $candidate.CompletionText.StartsWith($tail, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $completionText = $listPrefix + $candidate.CompletionText
        $results.Add((New-PsGetsidCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $candidate.ToolTip))
    }

    if ($results.Count -eq 0) {
        $results.Add((New-PsGetsidCompletionResult -CompletionText $CurrentWord -ResultType 'ParameterValue' -ToolTip 'Remote target token, remote list, or @file input.'))
    }

    @($results.ToArray())
}

function Get-PsGetsidIdentityCompletions {
    param([string]$CurrentWord)

    @(Get-PsGetsidPlaceholderValueCompletions `
            -CurrentWord $CurrentWord `
            -Candidates $script:PsGetsidCompletionCatalog.FirstSlotIdentityHints `
            -GenericToolTip 'Account name, domain\user, or SID to translate.')
}

function Get-PsGetsidAvailableSwitchOrder {
    # One switch model for every branch, derived from the live usage line:
    # [\\computer[,computer2[,...] | @file] [-u Username [-p Password]]] [account | SID]
    param([pscustomobject]$State)

    $used = $State.UsedSwitchLookup
    $order = New-Object System.Collections.Generic.List[string]

    if (($State.RemoteTarget -or $used.ContainsKey('-p')) -and -not $used.ContainsKey('-u')) {
        $order.Add('-u')
    }

    if ($State.ValuesBySwitch.ContainsKey('-u') -and -not $used.ContainsKey('-p')) {
        $order.Add('-p')
    }

    if (-not $used.ContainsKey('-nobanner')) {
        $order.Add('-nobanner')
    }

    if (-not $used.ContainsKey('-accepteula')) {
        $order.Add('-accepteula')
    }

    if (-not $State.HasArguments) {
        $order.Add('-?')
        $order.Add('/?')
    }

    @($order.ToArray())
}

function Get-PsGetsidSwitchCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$SwitchOrder
    )

    $results = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $wantsSlashForm = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('/')

    foreach ($switchText in $SwitchOrder) {
        $key = $switchText.ToLowerInvariant()
        $completionText = $switchText
        if ($wantsSlashForm -and $switchText.StartsWith('-')) {
            $completionText = '/' + $switchText.Substring(1)
        }

        if ($seen.ContainsKey($completionText)) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            -not $completionText.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $seen[$completionText] = $true
        $results.Add((New-PsGetsidCompletionResult `
                    -CompletionText $completionText `
                    -ResultType 'ParameterName' `
                    -ToolTip $script:PsGetsidCompletionCatalog.SwitchInfo[$key].Description))
    }

    @($results.ToArray())
}

function Get-PsGetsidTerminalCompletions {
    param([string]$CurrentWord)

    $completionText = if ([string]::IsNullOrEmpty($CurrentWord)) { ' ' } else { $CurrentWord }
    @(
        New-PsGetsidCompletionResult `
            -CompletionText $completionText `
            -ResultType 'ParameterValue' `
            -ToolTip 'No further arguments are valid after -? or /?.'
    )
}

function Get-PsGetsidCommandState {
    param([string[]]$TokensBeforeCurrent)

    $usedSwitchLookup = @{}
    $valuesBySwitch = @{}
    $remoteTarget = $null
    $identity = $null
    $valueTakingSwitches = @{
        '-u' = $true
        '-p' = $true
    }

    for ($i = 0; $i -lt $TokensBeforeCurrent.Count; $i++) {
        $token = $TokensBeforeCurrent[$i]
        $tokenKey = ConvertTo-PsGetsidSwitchKey -Token $token

        if (Test-PsGetsidKnownSwitch -Token $token) {
            $usedSwitchLookup[$tokenKey] = $true

            if ($valueTakingSwitches.ContainsKey($tokenKey) -and $i + 1 -lt $TokensBeforeCurrent.Count) {
                $nextToken = $TokensBeforeCurrent[$i + 1]
                if (-not (Test-PsGetsidKnownSwitch -Token $nextToken)) {
                    $valuesBySwitch[$tokenKey] = $nextToken
                    $i++
                }
            }

            continue
        }

        if (-not $remoteTarget -and (Test-PsGetsidRemoteTargetToken -Token $token)) {
            $remoteTarget = $token
            continue
        }

        if (-not $identity) {
            $identity = $token
        }
    }

    $valueContext = $null
    if ($TokensBeforeCurrent.Count -gt 0) {
        $lastToken = ConvertTo-PsGetsidSwitchKey -Token $TokensBeforeCurrent[-1]
        if ($valueTakingSwitches.ContainsKey($lastToken)) {
            $valueContext = $lastToken
        }
    }

    [pscustomobject]@{
        UsedSwitchLookup = $usedSwitchLookup
        ValuesBySwitch   = $valuesBySwitch
        RemoteTarget     = $remoteTarget
        Identity         = $identity
        ValueContext     = $valueContext
        HasArguments     = ($TokensBeforeCurrent.Count -gt 0)
    }
}

function Complete-PsGetsid {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-PsGetsidCompletionCatalog

    # Tokenize the raw command text up to the cursor (command-relative) so that a cursor
    # inside an earlier token only sees the tokens to its left.
    $line = $commandAst.Extent.Text
    $relativeCursor = [Math]::Min([Math]::Max($cursorPosition - $commandAst.Extent.StartOffset, 0), $line.Length)
    $linePrefix = $line.Substring(0, $relativeCursor)
    $hasTrailingSpace = ($cursorPosition - $commandAst.Extent.StartOffset) -gt $line.Length -or $linePrefix -match '\s$'
    $prefixTokens = @([regex]::Matches($linePrefix, '"[^"]*"?|\S+') | ForEach-Object { $_.Value })
    $argumentTokens = @($prefixTokens | Select-Object -Skip 1)

    $rawCurrentWord = ''
    $tokensBeforeCurrent = @($argumentTokens)
    if (-not $hasTrailingSpace -and $argumentTokens.Count -gt 0) {
        $rawCurrentWord = [string]$argumentTokens[-1]
        $tokensBeforeCurrent = @($argumentTokens | Select-Object -First ($argumentTokens.Count - 1))
    }

    # The engine's word is preferred (it resolves $env: references and closes an open quote);
    # a comma-separated remote list such as a trailing '\\a,' is an array literal to the
    # parser and reaches us as an empty word, so fall back to the raw token then.
    $currentWord = if ([string]::IsNullOrEmpty($wordToComplete)) { $rawCurrentWord } else { $wordToComplete }

    $state = Get-PsGetsidCommandState -TokensBeforeCurrent $tokensBeforeCurrent
    $usedSwitchLookup = $state.UsedSwitchLookup

    if ($usedSwitchLookup.ContainsKey('-?') -or $usedSwitchLookup.ContainsKey('/?')) {
        return @(Get-PsGetsidTerminalCompletions -CurrentWord $currentWord)
    }

    switch ($state.ValueContext) {
        '-u' {
            return @(Get-PsGetsidPlaceholderValueCompletions `
                    -CurrentWord $currentWord `
                    -Candidates $script:PsGetsidCompletionCatalog.UsernameHints `
                    -GenericToolTip 'Remote user name for PsGetsid, typically <username> or <domain\user>.')
        }
        '-p' {
            return @(Get-PsGetsidPlaceholderValueCompletions `
                    -CurrentWord $currentWord `
                    -Candidates $script:PsGetsidCompletionCatalog.PasswordHints `
                    -GenericToolTip 'Remote password for PsGetsid. If omitted at runtime, PsGetsid prompts interactively.')
        }
    }

    $switchOrder = @(Get-PsGetsidAvailableSwitchOrder -State $state)

    if ($currentWord.StartsWith('-') -or $currentWord.StartsWith('/')) {
        return @(Get-PsGetsidSwitchCompletions -CurrentWord $currentWord -SwitchOrder $switchOrder)
    }

    if (-not $state.RemoteTarget -and -not $state.Identity) {
        if ($currentWord.StartsWith('\') -or $currentWord.StartsWith('@') -or $currentWord.StartsWith('"@')) {
            return @(Get-PsGetsidRemoteTargetCompletions -CurrentWord $currentWord)
        }

        $results = New-Object System.Collections.Generic.List[object]

        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            foreach ($result in @(Get-PsGetsidRemoteTargetCompletions -CurrentWord $currentWord)) {
                $results.Add($result)
            }
        }

        foreach ($result in @(Get-PsGetsidIdentityCompletions -CurrentWord $currentWord)) {
            $results.Add($result)
        }

        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            foreach ($result in @(Get-PsGetsidSwitchCompletions -CurrentWord $currentWord -SwitchOrder $switchOrder)) {
                $results.Add($result)
            }
        }

        return @($results.ToArray())
    }

    if ($state.RemoteTarget -and -not $state.Identity) {
        $results = New-Object System.Collections.Generic.List[object]

        foreach ($result in @(Get-PsGetsidIdentityCompletions -CurrentWord $currentWord)) {
            $results.Add($result)
        }

        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            foreach ($result in @(Get-PsGetsidSwitchCompletions -CurrentWord $currentWord -SwitchOrder $switchOrder)) {
                $results.Add($result)
            }
        }

        return @($results.ToArray())
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-PsGetsidSwitchCompletions -CurrentWord $currentWord -SwitchOrder $switchOrder)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'psgetsid', 'PsGetsid.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsGetsid -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
