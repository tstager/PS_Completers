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

function ConvertFrom-PsGetsidTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    $tokens[0].Value
}

function ConvertTo-PsGetsidQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default). PowerShell reads ' and
    # U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes.
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $QuoteChar) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
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

    $unquoted = ConvertFrom-PsGetsidTypedWord -Value $Token
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

    $typedValue = ConvertFrom-PsGetsidTypedWord -Value $CurrentWord
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

    $trimmedCurrentWord = ConvertFrom-PsGetsidTypedWord -Value $CurrentWord
    $pathPortion = if ($trimmedCurrentWord.StartsWith('@')) {
        $trimmedCurrentWord.Substring(1)
    } else {
        $trimmedCurrentWord
    }

    if ([string]::IsNullOrWhiteSpace($pathPortion)) {
        $parent = '.'
        $leaf = ''
    } elseif ($pathPortion -match '[\\/]$') {
        $parent = $pathPortion
        $leaf = ''
    } else {
        $parent = Split-Path -Path $pathPortion -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $pathPortion -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $quoteChar = if ($CurrentWord -match '^[''"\u2018-\u201E]') { $CurrentWord.Substring(0, 1) } else { '' }
    $items = @(Get-ChildItem -LiteralPath $parent -Filter $filter -ErrorAction Ignore)

    # A typed directory (.\, ./, ..\, sub\, C:/x/) is kept exactly as typed, separators included.
    $typedDirectory = if ($pathPortion -match '^(.*[\\/])') { $Matches[1] } else { '' }

    $results = @(foreach ($item in $items) {
        $completionPath = if ($typedDirectory) {
            $typedDirectory + $item.Name
        } else {
            $item.FullName
        }

        if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionPath += [System.IO.Path]::DirectorySeparatorChar
        }

        # The whole '@path' word is quoted so it stays one constant argument.
        $completionText = ConvertTo-PsGetsidQuotedValue -Value ('@' + $completionPath) -QuoteChar $quoteChar
        $resultType = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }
        New-PsGetsidCompletionResult -CompletionText $completionText -ListItemText ('@' + $item.Name) -ResultType $resultType -ToolTip $item.FullName
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

    $trimmedCurrentWord = ConvertFrom-PsGetsidTypedWord -Value $CurrentWord

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

function Get-PsGetsidCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The parser keeps an unterminated quoted word as one element running to the cursor; in a
    # remote list ('\\a,\\b') the engine completes the list element under the cursor.
    foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $parts = if ($element -is [System.Management.Automation.Language.ArrayLiteralAst]) { $element.Elements } else { @($element) }
        foreach ($part in $parts) {
            $extent = $part.Extent
            if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
                return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
            }
        }
    }

    ''
}

function ConvertTo-PsGetsidQuotedResult {
    # Re-renders results computed from a quoted word's value inside the quote the user typed.
    param(
        [string]$QuoteChar,
        [object[]]$Result
    )

    if (-not $QuoteChar) {
        return $Result
    }

    @(foreach ($item in $Result) {
        New-PsGetsidCompletionResult `
            -CompletionText (ConvertTo-PsGetsidQuotedValue -Value $item.CompletionText -QuoteChar $QuoteChar) `
            -ListItemText $item.ListItemText `
            -ResultType $item.ResultType `
            -ToolTip $item.ToolTip
    })
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
    # A token is a run of quoted segments (ASCII or typographic, open to the cursor) and bare
    # characters, so a quoted word keeps its spaces; whitespace after the last token is a new word.
    $prefixMatches = @([regex]::Matches($linePrefix, '(?:["\u201C-\u201E](?:`.|[^`"\u201C-\u201E])*["\u201C-\u201E]?|[''\u2018-\u201B](?:[''\u2018-\u201B]{2}|[^''\u2018-\u201B])*[''\u2018-\u201B]?|[^\s''"\u2018-\u201E])+'))
    $prefixTokens = @($prefixMatches | ForEach-Object { $_.Value })
    $tokensEnd = if ($prefixMatches.Count -gt 0) { $prefixMatches[-1].Index + $prefixMatches[-1].Length } else { 0 }
    $hasTrailingSpace = ($cursorPosition - $commandAst.Extent.StartOffset) -gt $line.Length -or $tokensEnd -lt $linePrefix.Length
    $argumentTokens = @($prefixTokens | Select-Object -Skip 1)

    $rawCurrentWord = ''
    $tokensBeforeCurrent = @($argumentTokens)
    if (-not $hasTrailingSpace -and $argumentTokens.Count -gt 0) {
        $rawCurrentWord = [string]$argumentTokens[-1]
        $tokensBeforeCurrent = @($argumentTokens | Select-Object -First ($argumentTokens.Count - 1))
    }

    # The word is the typed text of the parser element the engine replaces: the engine's own
    # word is a quoted value re-wrapped in a plain quote with its escapes undone, which no longer
    # reads back as what was typed. A trailing '\\a,' is an incomplete remote list and reaches
    # us as an empty word, so fall back to the raw token then. A word that is no argument
    # element (a redirection target) keeps the engine's word.
    $currentWord = if ([string]::IsNullOrEmpty($wordToComplete)) {
        $rawCurrentWord
    } else {
        Get-PsGetsidCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition
    }
    if (-not $currentWord) {
        $currentWord = $wordToComplete
    }
    $typedValue = ConvertFrom-PsGetsidTypedWord -Value $currentWord

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

    $quoteChar = if ($currentWord -match '^[''"\u2018-\u201E]') { $currentWord.Substring(0, 1) } else { '' }

    if ($typedValue.StartsWith('-') -or $typedValue.StartsWith('/')) {
        return @(ConvertTo-PsGetsidQuotedResult -QuoteChar $quoteChar -Result @(Get-PsGetsidSwitchCompletions -CurrentWord $typedValue -SwitchOrder $switchOrder))
    }

    if (-not $state.RemoteTarget -and -not $state.Identity) {
        if ($typedValue.StartsWith('@')) {
            return @(Get-PsGetsidRemoteTargetCompletions -CurrentWord $currentWord)
        }

        if ($typedValue.StartsWith('\')) {
            return @(ConvertTo-PsGetsidQuotedResult -QuoteChar $quoteChar -Result @(Get-PsGetsidRemoteTargetCompletions -CurrentWord $typedValue))
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
