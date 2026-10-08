# xcopy tab completion for PowerShell
# Builds a help-driven switch catalog and path-aware value completion for xcopy.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name XcopyCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:XcopyCompletionCatalog = @{
        Initialized     = $false
        Options         = @()
        OptionInfoByKey = @{}
        DateSuggestions = @()
    }
}

function Test-XcopyCommandAvailable {
    [bool](Get-Command -Name xcopy.exe -ErrorAction SilentlyContinue)
}

function Invoke-XcopyHelpText {
    if (-not (Test-XcopyCommandAvailable)) {
        return @()
    }

    try {
        @(& xcopy.exe '/?' 2>$null)
    } catch {
        @()
    }
}

function New-XcopyCompletionResult {
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

function Remove-XcopyOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return $Value
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function Get-XcopyTypedQuote {
    # The first quote the user typed in the word ('' when none); the completion quotes the
    # whole word in it. PowerShell reads ' and U+2018-U+201B as single quotes and " and
    # U+201C-U+201E as double quotes.
    param([string]$Value)

    if ($Value -match '[''"\u2018-\u201E]') {
        return $Matches[0]
    }

    ''
}

function ConvertFrom-XcopyTypedWord {
    # The value of a typed word. A word holding a quote (ASCII or typographic) is read by the
    # PowerShell tokenizer as a command argument, which drops the quotes and undoes that quote
    # style's escapes; adjacent pieces such as 'sub dir'\x are joined into one value.
    param([string]$Value)

    if (-not (Get-XcopyTypedQuote -Value $Value)) {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput('x ' + $Value, [ref]$tokens, [ref]$parseErrors)
    -join @(
        foreach ($token in ($tokens | Select-Object -Skip 1)) {
            if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::EndOfInput) {
                continue
            }

            if ($token -is [System.Management.Automation.Language.StringToken]) { $token.Value } else { $token.Text }
        }
    )
}

function ConvertTo-XcopyQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default).
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $QuoteChar) {
        # A bare word starting with - or U+2013-U+2015 is read by PowerShell as a parameter.
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]' -and $Value -notmatch '^[-\u2013-\u2015]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-XcopyStaticOptionMetadata {
    $today = Get-Date

    @{
        '/d' = @{
            Key            = '/d'
            Display        = '/D[:date]'
            CompletionText = '/D'
            Description    = 'Copies files changed on or after the specified date.'
            InlineValueKind = 'List'
            Suggestions    = @(
                $today.ToString('M-d-yyyy'),
                $today.ToString('MM-dd-yyyy'),
                (Get-Date -Date $today.AddDays(-1)).ToString('M-d-yyyy'),
                '1-1-2024',
                '01-01-2024'
            )
        }
        '/exclude' = @{
            Key             = '/exclude'
            Display         = '/EXCLUDE:file1[+file2][+file3]...'
            CompletionText  = '/EXCLUDE:'
            Description     = 'Specifies files containing exclude strings to match against absolute paths.'
            InlineValueKind = 'PathChain'
        }
        '/sparse' = @{
            Key            = '/sparse'
            Display        = '/SPARSE'
            CompletionText = '/SPARSE'
            Description    = 'Enable retaining the sparse state of files during copy.'
        }
        '/-sparse' = @{
            Key            = '/-sparse'
            Display        = '/-SPARSE'
            CompletionText = '/-SPARSE'
            Description    = 'Disable retaining the sparse state of files during copy.'
        }
        '/?' = @{
            Key            = '/?'
            Display        = '/?'
            CompletionText = '/?'
            Description    = 'Displays this help message.'
        }
    }
}

function Expand-XcopyHelpToken {
    param([string]$Token)

    $cleanToken = $Token.Trim().TrimEnd('.', ',', ';', ')')
    if ([string]::IsNullOrWhiteSpace($cleanToken)) {
        return @()
    }

    if ($cleanToken.Equals('/[-]SPARSE', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @('/SPARSE', '/-SPARSE')
    }

    @($cleanToken)
}

function ConvertFrom-XcopyHelpToken {
    param([string]$Token)

    foreach ($expandedToken in (Expand-XcopyHelpToken -Token $Token)) {
        $match = [regex]::Match($expandedToken, '^/(?<name>-?[A-Za-z?][A-Za-z0-9-]*)(?<suffix>.*)$')
        if (-not $match.Success) {
            continue
        }

        $root = '/' + $match.Groups['name'].Value
        $suffix = $match.Groups['suffix'].Value
        $completionText = if ($suffix -match '^\[:') {
            $root
        } elseif ($suffix.StartsWith(':')) {
            "${root}:"
        } else {
            $root
        }

        @{
            Key            = $root.ToLowerInvariant()
            Display        = $expandedToken
            CompletionText = $completionText
            Description    = $expandedToken
        }
    }
}

function Get-XcopyOptionLineMatch {
    param([string]$Line)

    # Either '/TOKEN   description' or a token alone on its line (help prints
    # '/EXCLUDE:file1[+file2][+file3]...' that way, with the description on the next lines).
    [regex]::Match($Line, '^\s*(?<token>/\S+)(?:\s{2,}(?<description>.+?))?\s*$')
}

function Initialize-XcopyCompletionCatalog {
    if ($script:XcopyCompletionCatalog.Initialized) {
        return
    }

    $catalog = @{}
    foreach ($entry in (Get-XcopyStaticOptionMetadata).GetEnumerator()) {
        $catalog[$entry.Key] = @{} + $entry.Value
    }

    $helpLines = Invoke-XcopyHelpText
    $currentKeys = @()

    foreach ($line in $helpLines) {
        $optionMatch = Get-XcopyOptionLineMatch -Line $line
        if ($optionMatch.Success) {
            $description = $optionMatch.Groups['description'].Value.Trim()
            $currentKeys = @()

            foreach ($parsed in @(ConvertFrom-XcopyHelpToken -Token $optionMatch.Groups['token'].Value)) {
                $key = $parsed.Key
                if ($catalog.ContainsKey($key)) {
                    if (-not $catalog[$key].ContainsKey('Display')) {
                        $catalog[$key]['Display'] = $parsed.Display
                    }

                    if (-not $catalog[$key].ContainsKey('CompletionText')) {
                        $catalog[$key]['CompletionText'] = $parsed.CompletionText
                    }
                } else {
                    $catalog[$key] = @{} + $parsed
                }

                $catalog[$key]['Description'] = $description
                $currentKeys += $key
            }

            continue
        }

        if ($currentKeys.Count -gt 0 -and $line -match '^\s{2,}(?<continuation>\S.*)$') {
            $continuation = $matches['continuation'].Trim()
            foreach ($key in $currentKeys) {
                if ([string]::IsNullOrWhiteSpace($continuation)) {
                    continue
                }

                if ([string]::IsNullOrEmpty($catalog[$key]['Description'])) {
                    $catalog[$key]['Description'] = $continuation
                } elseif (-not $catalog[$key]['Description'].EndsWith($continuation, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $catalog[$key]['Description'] += ' ' + $continuation
                }
            }

            continue
        }

        $currentKeys = @()
    }

    $script:XcopyCompletionCatalog.Options = @(
        foreach ($entry in $catalog.Values) {
            [pscustomobject]$entry
        }
    ) | Sort-Object -Property CompletionText, Display -Unique

    $script:XcopyCompletionCatalog.OptionInfoByKey = @{}
    foreach ($option in $script:XcopyCompletionCatalog.Options) {
        $script:XcopyCompletionCatalog.OptionInfoByKey[$option.Key] = $option
    }

    $dateSuggestions = New-Object System.Collections.Generic.List[string]
    foreach ($option in $script:XcopyCompletionCatalog.Options) {
        if ($option.Key -eq '/d' -and $option.PSObject.Properties.Name -contains 'Suggestions') {
            foreach ($suggestion in $option.Suggestions) {
                if (-not [string]::IsNullOrWhiteSpace($suggestion)) {
                    $dateSuggestions.Add([string]$suggestion)
                }
            }
        }
    }

    $script:XcopyCompletionCatalog.DateSuggestions = @($dateSuggestions | Sort-Object -Unique)
    $script:XcopyCompletionCatalog.Initialized = $true
}

function Get-XcopyCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The typed text of the word at the cursor, quotes included. The parser keeps an
    # unterminated quoted word as one element running to the cursor. Like PowerShell's own
    # replacement span, a quoted string followed directly by a \ or / piece ('sub dir'\x) is
    # one path word.
    $elements = $CommandAst.CommandElements
    for ($index = 1; $index -lt $elements.Count; $index++) {
        $extent = $elements[$index].Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            $start = $extent.StartOffset
            $previous = $elements[$index - 1]
            if ($index -gt 1 -and $previous.Extent.EndOffset -eq $start -and $extent.Text -match '^[\\/]' -and
                ($previous -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                    $previous -is [System.Management.Automation.Language.ExpandableStringExpressionAst])) {
                $start = $previous.Extent.StartOffset
            }

            return $CommandAst.Extent.Text.Substring($start - $CommandAst.Extent.StartOffset, $CursorPosition - $start)
        }
    }

    ''
}

function Get-XcopyArgumentList {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$WordStart
    )

    # The arguments before the word being completed (adjacent elements reach a native command
    # as separate arguments).
    $arguments = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $WordStart) {
            $arguments += $element.Extent.Text
        }
    }

    $arguments
}

function Get-XcopyOptionKey {
    param([string]$Token)

    $cleanToken = Remove-XcopyOuterQuotes $Token
    if ([string]::IsNullOrWhiteSpace($cleanToken) -or -not $cleanToken.StartsWith('/')) {
        return $null
    }

    $match = [regex]::Match($cleanToken, '^/(?<name>-?[A-Za-z?][A-Za-z0-9-]*)')
    if ($match.Success) {
        return ('/' + $match.Groups['name'].Value).ToLowerInvariant()
    }

    $null
}

function Get-XcopyCompletionContext {
    param([string[]]$Arguments)

    $positionals = New-Object System.Collections.Generic.List[string]

    foreach ($argument in $Arguments) {
        if ([string]::IsNullOrWhiteSpace($argument)) {
            continue
        }

        if ($null -ne (Get-XcopyOptionKey -Token $argument)) {
            continue
        }

        $positionals.Add($argument)
    }

    [pscustomobject]@{
        Positionals = @($positionals)
    }
}

function Get-XcopyUniqueCompletions {
    param([System.Management.Automation.CompletionResult[]]$Results)

    $seen = @{}
    $unique = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()

    foreach ($result in $Results) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.ContainsKey($result.CompletionText)) {
            continue
        }

        $seen[$result.CompletionText] = $true
        $unique.Add($result)
    }

    @($unique.ToArray())
}

function Get-XcopyPathCompletions {
    param(
        [string]$InputPath,
        [string]$Kind,
        [string]$CompletionPrefix = '',
        [string]$QuoteChar = ''
    )

    # InputPath is the unquoted value; the whole word (CompletionPrefix + path) is quoted as
    # one argument in QuoteChar, the quote the user typed. The directory part is kept exactly
    # as typed (.\, ./, C:\), so no typed text is dropped.
    $directoryText = if ($InputPath -match '^(.*[\\/]|[A-Za-z]:)') { $Matches[1] } else { '' }
    $leaf = $InputPath.Substring($directoryText.Length)
    $parent = if ($directoryText) { $directoryText } else { '.' }

    # Filter during enumeration and cap the result: a completion menu past a few hundred
    # entries is unusable, and %TEMP%-sized directories (30k entries) must not take seconds.
    $maxResults = 500
    $items = @(
        Get-ChildItem -LiteralPath $parent -Filter ($leaf + '*') -ErrorAction Ignore |
            Where-Object {
                if ($Kind -eq 'Directory') { $_.PSIsContainer }
                elseif ($Kind -eq 'File') { -not $_.PSIsContainer }
                else { $true }
            } |
            Select-Object -First $maxResults
    )

    foreach ($item in $items | Sort-Object -Property Name) {
        $pathText = $directoryText + $item.Name
        if (-not $directoryText -and -not $CompletionPrefix -and $pathText -match '^[-\u2013-\u2015]') {
            # A whole word starting with a dash would be read as a parameter: anchor it like
            # PowerShell's own file completion does (.\-name).
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $completionText = ConvertTo-XcopyQuotedValue -Value ($CompletionPrefix + $pathText) -QuoteChar $QuoteChar
        $listItemText = $CompletionPrefix + $pathText

        New-XcopyCompletionResult `
            -CompletionText $completionText `
            -ListItemText $listItemText `
            -ResultType 'ParameterValue' `
            -ToolTip $item.FullName
    }
}

function Get-XcopyPrefixedSuggestions {
    param(
        [string]$Prefix,
        [string]$CurrentValue,
        [string[]]$Suggestions,
        [string]$ToolTip,
        [string]$QuoteChar = ''
    )

    $cleanCurrentValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    foreach ($suggestion in ($Suggestions | Sort-Object -Unique)) {
        if ($suggestion.StartsWith($cleanCurrentValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            $tokenText = $Prefix + $suggestion
            New-XcopyCompletionResult -CompletionText (ConvertTo-XcopyQuotedValue -Value $tokenText -QuoteChar $QuoteChar) -ListItemText $tokenText -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }
}

function Get-XcopyChainedPathCompletions {
    param(
        [string]$Prefix,
        [string]$CurrentValue,
        [string]$Kind,
        [string]$QuoteChar = ''
    )

    $valuePrefix = ''
    $currentSegment = $CurrentValue
    $lastPlusIndex = if ([string]::IsNullOrEmpty($CurrentValue)) { -1 } else { $CurrentValue.LastIndexOf('+') }

    if ($lastPlusIndex -ge 0) {
        $valuePrefix = $CurrentValue.Substring(0, $lastPlusIndex + 1)
        $currentSegment = $CurrentValue.Substring($lastPlusIndex + 1)
    }

    @(Get-XcopyPathCompletions -InputPath $currentSegment -Kind $Kind -CompletionPrefix ($Prefix + $valuePrefix) -QuoteChar $QuoteChar)
}

function Get-XcopyInlineValueCompletions {
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    Initialize-XcopyCompletionCatalog

    # Value is the unquoted word. The quote may open the whole word ('/EXCLUDE:a) or sit
    # anywhere in it (/EXCLUDE:'a, /EXCLUDE:a+'b); either way the completion quotes the whole
    # word as one constant argument.
    $match = [regex]::Match($Value, '^(?<root>/-?[A-Za-z?][A-Za-z0-9-]*)(?<separator>:)(?<value>.*)$')
    if (-not $match.Success) {
        return @()
    }

    $key = $match.Groups['root'].Value.ToLowerInvariant()
    if (-not $script:XcopyCompletionCatalog.OptionInfoByKey.ContainsKey($key)) {
        return @()
    }

    $optionInfo = $script:XcopyCompletionCatalog.OptionInfoByKey[$key]
    if (-not ($optionInfo.PSObject.Properties.Name -contains 'InlineValueKind')) {
        return @()
    }

    $prefix = $match.Groups['root'].Value + ':'
    $currentValue = $match.Groups['value'].Value

    switch ($optionInfo.InlineValueKind) {
        'List' {
            return @(Get-XcopyPrefixedSuggestions -Prefix $prefix -CurrentValue $currentValue -Suggestions $optionInfo.Suggestions -ToolTip $optionInfo.Description -QuoteChar $QuoteChar)
        }
        'PathChain' {
            # The value is a path to an exclude-list file; directories are offered (with a
            # trailing backslash) so the user can navigate to a file outside the current directory.
            return @(Get-XcopyChainedPathCompletions -Prefix $prefix -CurrentValue $currentValue -Kind 'Any' -QuoteChar $QuoteChar)
        }
    }

    @()
}

function Get-XcopyOptionCompletions {
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    Initialize-XcopyCompletionCatalog

    # Value is the unquoted word; a typed quote is kept around the switch.
    $prefix = if ([string]::IsNullOrWhiteSpace($Value)) { '' } else { $Value.ToUpperInvariant() }

    foreach ($option in $script:XcopyCompletionCatalog.Options) {
        if ($option.CompletionText.ToUpperInvariant().StartsWith($prefix) -or $option.Display.ToUpperInvariant().StartsWith($prefix)) {
            New-XcopyCompletionResult `
                -CompletionText (ConvertTo-XcopyQuotedValue -Value $option.CompletionText -QuoteChar $QuoteChar) `
                -ListItemText $option.Display `
                -ResultType 'ParameterName' `
                -ToolTip $option.Description
        }
    }
}

function Complete-Xcopy {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if (-not (Test-XcopyCommandAvailable)) {
        return @()
    }

    Initialize-XcopyCompletionCatalog

    # The word is cut from the CommandAst element at the cursor: wordToComplete spans past the
    # cursor and drops the quotes the user typed.
    $currentWord = Get-XcopyCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition
    $currentValue = ConvertFrom-XcopyTypedWord -Value $currentWord
    $quoteChar = Get-XcopyTypedQuote -Value $currentWord

    if (-not [string]::IsNullOrEmpty($currentValue) -and $currentValue.StartsWith('/')) {
        $inlineValueCompletions = @(Get-XcopyInlineValueCompletions -Value $currentValue -QuoteChar $quoteChar)
        if ($inlineValueCompletions.Count -gt 0) {
            return $inlineValueCompletions
        }

        return @(Get-XcopyOptionCompletions -Value $currentValue -QuoteChar $quoteChar)
    }

    $arguments = @(Get-XcopyArgumentList -CommandAst $commandAst -WordStart ($cursorPosition - $currentWord.Length))
    $context = Get-XcopyCompletionContext -Arguments $arguments

    if ($context.Positionals.Count -lt 2) {
        $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
        foreach ($result in @(Get-XcopyPathCompletions -InputPath $currentValue -Kind 'Any' -QuoteChar $quoteChar)) {
            $results.Add($result)
        }

        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            foreach ($result in @(Get-XcopyOptionCompletions -Value $currentValue)) {
                $results.Add($result)
            }
        }

        return @(Get-XcopyUniqueCompletions -Results $results.ToArray())
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-XcopyOptionCompletions -Value $currentValue)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'xcopy', 'xcopy.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Xcopy -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
