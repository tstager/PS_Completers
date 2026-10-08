# psinfo tab completion for PowerShell
# Static-first native completer for PsInfo with safe filter and remote-target hints.

Set-StrictMode -Version 2.0

function Initialize-PsInfoCompletionCatalog {
    if (Get-Variable -Name PsInfoCompletionCatalog -Scope Script -ErrorAction Ignore) { return }

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
            [pscustomobject]@{ Token = '-accepteula'; Description = 'Suppress the Sysinternals license dialog.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-?'; Description = 'Display PsInfo help.'; TakesValue = $false; Terminal = $true }
            [pscustomobject]@{ Token = '/?'; Description = 'Display PsInfo help.'; TakesValue = $false; Terminal = $true }
        )
        # PsInfo filters by field-label prefix; these are the labels PsInfo v1.79 prints.
        FilterHints = @(
            'uptime', 'kernel version', 'product type', 'product version', 'service pack', 'kernel build number',
            'registered organization', 'registered owner', 'ie version', 'system root',
            'processors', 'processor speed', 'processor type', 'physical memory', 'video driver'
        )
        # ',' ';' and '|' are PowerShell syntax, so every delimiter except \t must reach PsInfo quoted.
        DelimiterHints = @(',', ';', '|', ':', '\t')
    }
}

function New-PsInfoCompletionResult {
    param([string]$CompletionText, [string]$ResultType, [string]$ToolTip, [string]$ListItemText)
    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }
    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

# PowerShell treats U+2018-U+201B as single quotes and U+201C-U+201E as double
# quotes, exactly like ' and ", so every quote test below covers both.
function Get-PsInfoTypedQuote {
    param([string]$Value)
    if ($Value -match '^([''"\u2018-\u201E])') { return $Matches[1] }
    ''
}

function Remove-PsInfoOuterQuotes {
    # The value of a typed word. A word opened with a quote is read by the PowerShell
    # tokenizer, which drops the quotes and undoes that quote style's escapes; an
    # unterminated quote reads up to the cursor.
    param([string]$Value)
    if (-not (Get-PsInfoTypedQuote -Value $Value)) { return $Value }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    [string]$tokens[0].Value
}

function ConvertTo-PsInfoQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote is given,
    # otherwise in the given quote (single by default). Inside single quotes every
    # single-quote character is doubled; inside double quotes ` " $ and the typographic
    # double quotes take a backtick.
    param([string]$Value, [string]$Quote = '')
    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    if (-not $Quote) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') { return $Value }
        $Quote = "'"
    }
    if ($Quote -match '^[''\u2018-\u201B]$') {
        return $Quote + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $Quote
    }
    $Quote + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $Quote
}

function Get-PsInfoArgumentState {
    param([System.Management.Automation.Language.CommandAst]$CommandAst, [int]$CursorPosition)

    # A bare '@' is an unrecognized token, so the parser splits '@.\hosts.txt'
    # into '@' and '.\hosts.txt'; glue it back onto the element it touches so
    # the word is the one psinfo will see.
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

    # The word under the cursor is read from the parser, never from
    # $wordToComplete (a registered completer receives it with '$name'
    # expanded): the element that contains the cursor, cut at the cursor. An
    # unterminated quote is one element. SpanText is the text PowerShell's
    # replacement span covers, so an echo of it changes nothing. For a glued
    # '@' the span is only the path after it (StrandedAt, results must keep
    # that '@' valid), or only the '@' itself when the cursor sits right after
    # it (AtOnly).
    $currentWord = ''
    $spanText = ''
    $strandedAt = $false
    $atOnly = $false
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

    # Only elements that end before the cursor are consumed; the token under the cursor and anything after it are not.
    $tokensBeforeCurrent = @($words | Where-Object { $_.End -lt $CursorPosition } | ForEach-Object { $_.Text })

    [pscustomobject]@{
        CurrentWord         = $currentWord
        SpanText            = $spanText
        StrandedAt          = $strandedAt
        AtOnly              = $atOnly
        TokensBeforeCurrent = $tokensBeforeCurrent
    }
}

function Get-PsInfoAtFileCompletions {
    param([string]$CurrentWord, [string]$SpanText, [bool]$StrandedAt = $false)
    $trimmed = Remove-PsInfoOuterQuotes -Value $CurrentWord
    if (-not $trimmed.StartsWith('@')) { return @() }
    $pathPortion = $trimmed.Substring(1)
    # Candidates keep the typed directory text verbatim ('.\', './', '..\', 'C:\x\'),
    # so nothing the user typed is dropped.
    $leaf = if ([string]::IsNullOrWhiteSpace($pathPortion) -or $pathPortion -match '[\\/]$') { '' } else { Split-Path -Path $pathPortion -Leaf }
    $typedDirectory = $pathPortion.Substring(0, $pathPortion.Length - $leaf.Length)
    $parent = if ([string]::IsNullOrWhiteSpace($typedDirectory)) { '.' } else { $typedDirectory }
    $quote = Get-PsInfoTypedQuote -Value $CurrentWord
    # The typed leaf is matched literally: '[' or '`' in it is not a wildcard.
    $items = @(
        if (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore) {
            Get-ChildItem -LiteralPath $parent -ErrorAction Ignore |
                Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') }
        }
    )

    $results = foreach ($item in $items) {
        $completionPath = $typedDirectory + $item.Name

        if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionPath += [System.IO.Path]::DirectorySeparatorChar
        }

        # The '@' is part of the value, so the word is always quoted ('@path'). A
        # stranded '@' stays in the line, and only '@(' keeps it valid: it passes
        # the quoted '@path' to psinfo as one argument.
        $completionText = if ($StrandedAt) {
            '(' + (ConvertTo-PsInfoQuotedValue -Value ('@' + $completionPath)) + ')'
        } else {
            ConvertTo-PsInfoQuotedValue -Value ('@' + $completionPath) -Quote $quote
        }
        New-PsInfoCompletionResult -CompletionText $completionText -ListItemText ('@' + $item.Name) -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.'
    }

    if (@($results).Count -eq 0) {
        return @(
            New-PsInfoCompletionResult -CompletionText $SpanText -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.'
        )
    }

    @($results)
}

function Complete-PsInfo {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'WordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; a registered completer receives WordToComplete with $name expanded.')]
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    Initialize-PsInfoCompletionCatalog

    $state = Get-PsInfoArgumentState -CommandAst $CommandAst -CursorPosition $CursorPosition
    # Tab between a bare '@' and the path after it replaces only the '@':
    # anything else would fuse with the typed path, so keep the line as it is.
    if ($state.AtOnly) {
        return @(New-PsInfoCompletionResult -CompletionText '@' -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.')
    }
    $currentWord = $state.CurrentWord
    $spanText = $state.SpanText
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
            if (-not [string]::IsNullOrWhiteSpace($currentWord)) {
                return @(New-PsInfoCompletionResult -CompletionText $spanText -ResultType 'ParameterValue' -ToolTip 'Remote user name.')
            }
            return @(
                New-PsInfoCompletionResult -CompletionText '<username>' -ResultType 'ParameterValue' -ToolTip 'Remote user name.'
                New-PsInfoCompletionResult -CompletionText '<domain\user>' -ResultType 'ParameterValue' -ToolTip 'Remote user name in Domain\User syntax.'
            )
        }
        'Password' {
            return @(New-PsInfoCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($currentWord)) { '<password>' } else { $spanText }) -ResultType 'ParameterValue' -ToolTip 'Remote password value.')
        }
        'Delimiter' {
            # Keep the quote the user typed; an untyped delimiter keeps this completer's double quotes.
            $delimiterQuote = Get-PsInfoTypedQuote -Value $currentWord
            # Only hints that extend the typed delimiter; any other typed delimiter is echoed, never replaced.
            $typedDelimiter = Remove-PsInfoOuterQuotes -Value $currentWord
            $delimiterHints = @($script:PsInfoCompletionCatalog.DelimiterHints | Where-Object { $_.StartsWith($typedDelimiter, [System.StringComparison]::Ordinal) })
            if ($delimiterHints.Count -eq 0) {
                return @(New-PsInfoCompletionResult -CompletionText $spanText -ResultType 'ParameterValue' -ToolTip 'Delimiter used with -c.')
            }
            return @($delimiterHints | ForEach-Object {
                $text = if ($_ -eq '\t' -and -not $delimiterQuote) { $_ } else { ConvertTo-PsInfoQuotedValue -Value $_ -Quote $(if ($delimiterQuote) { $delimiterQuote } else { '"' }) }
                New-PsInfoCompletionResult -CompletionText $text -ListItemText $_ -ResultType 'ParameterValue' -ToolTip 'Delimiter used with -c.'
            })
        }
    }

    if ((Remove-PsInfoOuterQuotes -Value $currentWord).StartsWith('@')) {
        return Get-PsInfoAtFileCompletions -CurrentWord $currentWord -SpanText $spanText -StrandedAt $state.StrandedAt
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
                # Keep the quote the user typed; an untyped multi-word label keeps this completer's double quotes.
                $hintQuote = Get-PsInfoTypedQuote -Value $currentWord
                if (-not $hintQuote -and $hint -match '\s') { $hintQuote = '"' }
                [void]$results.Add((New-PsInfoCompletionResult -CompletionText (ConvertTo-PsInfoQuotedValue -Value $hint -Quote $hintQuote) -ListItemText $hint -ResultType 'ParameterValue' -ToolTip 'PsInfo field label prefix; only the matching field is printed.'))
            }
        }
    }

    @($results.ToArray())
}


Register-ArgumentCompleter -Native -CommandName @('psinfo', 'psinfo.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsInfo -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
