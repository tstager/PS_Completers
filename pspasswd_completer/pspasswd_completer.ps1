# pspasswd tab completion for PowerShell
# Static native completer for PsPasswd with safe remote and account placeholders.

Set-StrictMode -Version 2.0

function New-PsPasswdCompletionResult {
    param([string]$CompletionText, [string]$ResultType, [string]$ToolTip, [string]$ListItemText)
    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }
    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

# PowerShell treats U+2018-U+201B as single quotes and U+201C-U+201E as double
# quotes, exactly like ' and ", so every quote test below covers both.
function Get-PsPasswdTypedQuote {
    param([string]$Value)
    if ($Value -match '^([''"\u2018-\u201E])') { return $Matches[1] }
    ''
}

function Remove-PsPasswdOuterQuotes {
    # The value of a typed word. A word opened with a quote is read by the PowerShell
    # tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    if (-not (Get-PsPasswdTypedQuote -Value $Value)) { return $Value -replace '`(.)', '$1' }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    [string]$tokens[0].Value
}

function ConvertTo-PsPasswdQuotedValue {
    # Bare when safe and no quote was typed, otherwise in the quote the user typed
    # (single by default). Inside single quotes every single-quote character is
    # doubled; inside double quotes ` " $ and the typographic double quotes take a backtick.
    param([string]$Value, [string]$Quote = '')
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if (-not $Quote -and $Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') { return $Value }
    if (-not $Quote) { $Quote = "'" }
    if ($Quote -match "['\u2018-\u201B]") {
        return $Quote + ($Value -replace "(['\u2018-\u201B])", '$1$1') + $Quote
    }
    $Quote + ($Value -replace '([`$"\u201C-\u201E])', '`$1') + $Quote
}

function Get-PsPasswdArgumentState {
    param([System.Management.Automation.Language.CommandAst]$CommandAst, [int]$CursorPosition)
    # A bare '@' is an unrecognized token, so the parser splits '@.\hosts.txt' into '@' and
    # '.\hosts.txt'; glue it back onto the element it touches so the word is the @file word.
    $words = New-Object System.Collections.Generic.List[object]
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $previous = if ($words.Count -gt 0) { $words[$words.Count - 1] } else { $null }
        if ($previous -and $previous.Text -eq '@' -and -not $previous.At -and $previous.End -eq $element.Extent.StartOffset) {
            $previous.Text = '@' + $element.Extent.Text
            $previous.End = $element.Extent.EndOffset
            $previous.At = $true
            continue
        }
        [void]$words.Add([pscustomobject]@{ Start = $element.Extent.StartOffset; End = $element.Extent.EndOffset; Text = $element.Extent.Text; At = $false })
    }
    # The word under the cursor comes from the parser (an unterminated quote is one element),
    # cut at the cursor. SpanText is the text PowerShell replaces: the whole element, so an echo
    # of it changes nothing. For a glued '@' the span is only the path after it (StrandedAt),
    # or only the '@' itself when the cursor sits right after it.
    $currentWord = ''
    $spanText = ''
    $strandedAt = $false
    foreach ($word in $words) {
        if ($word.Start -lt $CursorPosition -and $word.End -ge $CursorPosition) {
            $currentWord = $word.Text.Substring(0, $CursorPosition - $word.Start)
            $spanText = $word.Text
            if ($word.At) {
                $atOnly = $CursorPosition -eq $word.Start + 1
                $strandedAt = -not $atOnly
                $spanText = if ($atOnly) { '@' } else { $word.Text.Substring(1) }
            }
            break
        }
    }
    # Only elements that end at or before the cursor are established state; a token to the
    # right of the caret must not be consumed as the Account or NewPassword positional.
    $tokens = @($words | Where-Object { $_.End -le $CursorPosition } | ForEach-Object { $_.Text })
    $tokensBeforeCurrent = @($tokens)
    if (-not [string]::IsNullOrEmpty($currentWord) -and $tokensBeforeCurrent.Count -gt 0 -and $tokensBeforeCurrent[-1] -eq $currentWord) {
        $tokensBeforeCurrent = @($tokensBeforeCurrent | Select-Object -First ($tokensBeforeCurrent.Count - 1))
    }
    [pscustomobject]@{
        CurrentWord         = $currentWord
        SpanText            = $spanText
        StrandedAt          = $strandedAt
        TokensBeforeCurrent = $tokensBeforeCurrent
    }
}

function Get-PsPasswdAtFileCompletions {
    param([string]$CurrentWord, [string]$SpanText, [bool]$StrandedAt = $false)
    $trimmed = Remove-PsPasswdOuterQuotes -Value $CurrentWord
    if (-not $trimmed.StartsWith('@')) { return @() }
    $pathPortion = $trimmed.Substring(1)
    if ([string]::IsNullOrWhiteSpace($pathPortion)) {
        $parent = '.'
        $leaf = ''
    } elseif ($pathPortion -match '[\\/]+$') {
        $parent = $pathPortion
        $leaf = ''
    } else {
        $parent = Split-Path -Path $pathPortion -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) { $parent = '.' }
        $leaf = Split-Path -Path $pathPortion -Leaf
    }
    $quote = Get-PsPasswdTypedQuote -Value $CurrentWord
    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') })
    # The directory part is kept exactly as typed (.\ ./ ..\ C:\ C:), so no typed text is dropped.
    $typedDirectory = $pathPortion.Substring(0, $pathPortion.LastIndexOfAny([char[]]'\/:') + 1)
    $results = foreach ($item in $items) {
        $completionPath = $typedDirectory + $item.Name
        if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionPath += [System.IO.Path]::DirectorySeparatorChar
        }
        # A stranded '@' stays in the line, and only '@(' keeps it valid: it passes the
        # quoted '@path' to pspasswd as one argument.
        $completionText = if ($StrandedAt) {
            '(' + (ConvertTo-PsPasswdQuotedValue -Value ('@' + $completionPath) -Quote "'") + ')'
        } else {
            ConvertTo-PsPasswdQuotedValue -Value ('@' + $completionPath) -Quote $quote
        }
        New-PsPasswdCompletionResult -CompletionText $completionText -ListItemText ('@' + $item.Name) -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.'
    }
    if (@($results).Count -eq 0) {
        return @(New-PsPasswdCompletionResult -CompletionText $SpanText -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.')
    }
    @($results)
}

function Complete-PsPasswd {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $state = Get-PsPasswdArgumentState -CommandAst $CommandAst -CursorPosition $CursorPosition
    $currentWord = $state.CurrentWord
    $spanText = $state.SpanText
    # A placeholder offered inside a typed quote stays inside that quote.
    $typedQuote = Get-PsPasswdTypedQuote -Value $currentWord
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
            $userResults = @(
                foreach ($userHint in @(
                        @{ Text = '<username>'; ToolTip = 'Remote user name.' }
                        @{ Text = '<domain\user>'; ToolTip = 'Remote user name in Domain\User syntax.' }
                    )) {
                    if ([string]::IsNullOrWhiteSpace($currentWord) -or $userHint.Text.StartsWith((Remove-PsPasswdOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                        New-PsPasswdCompletionResult -CompletionText $(if ($typedQuote) { ConvertTo-PsPasswdQuotedValue -Value $userHint.Text -Quote $typedQuote } else { $userHint.Text }) -ListItemText $userHint.Text -ResultType 'ParameterValue' -ToolTip $userHint.ToolTip
                    }
                }
            )
            if ($userResults.Count -gt 0) { return $userResults }
            # A typed user name that matches no placeholder is kept as-is instead of being overwritten.
            return @(New-PsPasswdCompletionResult -CompletionText $spanText -ResultType 'ParameterValue' -ToolTip 'Remote user name.')
        }
        'Password' {
            return @(New-PsPasswdCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($currentWord)) { '<password>' } else { $spanText }) -ResultType 'ParameterValue' -ToolTip 'Remote password value.')
        }
    }

    if ((Remove-PsPasswdOuterQuotes -Value $currentWord).StartsWith('@')) {
        return Get-PsPasswdAtFileCompletions -CurrentWord $currentWord -SpanText $spanText -StrandedAt $state.StrandedAt
    }

    if ($account -and -not $newPassword) {
        return @(New-PsPasswdCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($currentWord)) { '<new-password>' } else { $spanText }) -ResultType 'ParameterValue' -ToolTip 'New password. Completion intentionally does not enumerate or transform secrets.')
    }

    # pspasswd [\\computer|@file] [-u Username [-p Password]] <Account> [NewPassword]: nothing follows NewPassword.
    if ($account -and $newPassword) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $remoteTarget) {
        foreach ($target in @('\\<computer>', '\\localhost', '\\*', '@file')) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $target.StartsWith((Remove-PsPasswdOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsPasswdCompletionResult -CompletionText $(if ($typedQuote) { ConvertTo-PsPasswdQuotedValue -Value $target -Quote $typedQuote } else { $target }) -ListItemText $target -ResultType 'ParameterValue' -ToolTip 'Remote target placeholder for local-account password changes.'))
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
                [void]$results.Add((New-PsPasswdCompletionResult -CompletionText $(if ($typedQuote) { ConvertTo-PsPasswdQuotedValue -Value $hint -Quote $typedQuote } else { $hint }) -ListItemText $hint -ResultType 'ParameterValue' -ToolTip 'Local account or domain account placeholder.'))
            }
        }
    }

    @($results.ToArray())
}


Register-ArgumentCompleter -Native -CommandName @('pspasswd', 'pspasswd.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsPasswd -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
