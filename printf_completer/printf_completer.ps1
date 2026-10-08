# printf tab completion for PowerShell
# Static option completion for printf.exe and printf.

Set-StrictMode -Version 2.0

function Get-PrintfCompletionOptions {
    $cache = Get-Variable -Name 'PrintfCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('--help', '--version')
    $commandCandidates = @('printf.exe', 'printf')
    foreach ($candidate in $commandCandidates) {
        $command = Get-Command -Name $candidate -ErrorAction Ignore
        if ($null -eq $command) {
            continue
        }

        try {
            $helpOutput = $null | & $command.Source --help 2>&1 | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String
        } catch {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($helpOutput)) {
            continue
        }

        # Only the indented option column counts, and the scan stops at the first
        # unindented paragraph after it, so dash words in prose ('-max places ...',
        # 'ls --quoting=shell-escape') are never taken for options.
        $options = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $descriptions = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
        $optionPattern = '^\s{2,}(?<opts>-{1,2}[A-Za-z0-9][A-Za-z0-9-]*(?:[=\[]\S*)?(?:,\s*-{1,2}[A-Za-z0-9][A-Za-z0-9-]*(?:[=\[]\S*)?)*)(?:\s{2,}(?<desc>\S.*?))?\s*$'
        foreach ($line in ([regex]::Split($helpOutput, '\r?\n'))) {
            if ($options.Count -gt 0 -and $line -match '^\S') {
                break
            }

            $match = [regex]::Match($line, $optionPattern)
            if (-not $match.Success) {
                continue
            }

            foreach ($rawOption in $match.Groups['opts'].Value.Split(',')) {
                $normalized = ($rawOption.Trim() -replace '[=\[].*$', '')
                [void]$options.Add($normalized)
                if ($match.Groups['desc'].Success -and -not $descriptions.ContainsKey($normalized)) {
                    $descriptions[$normalized] = $match.Groups['desc'].Value
                }
            }
        }

        if ($options.Count -gt 0) {
            foreach ($option in $fallbackOptions) {
                [void]$options.Add($option)
            }

            Set-Variable -Name 'PrintfFormatCatalog' -Value (Get-PrintfHelpFormatCatalog -HelpText $helpOutput) -Scope Script
            Set-Variable -Name 'PrintfCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'PrintfCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'PrintfCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'PrintfFormatCatalog' -Value (Get-PrintfHelpFormatCatalog -HelpText '') -Scope Script
    Set-Variable -Name 'PrintfCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'PrintfCompletionOptions' -Scope Script).Value
}

function Get-PrintfHelpFormatCatalog {
    param([string]$HelpText)

    # GNU prints the interpreted sequences and %%/%b/%q as a two-column list and the
    # remaining conversions as 'ending with one of diouxXfeEgGcs'. Other builds (uutils)
    # use a different layout, so each half falls back to the static GNU table.
    $staticEscapes = @(
        @('\"', 'double quote'),
        @('\\', 'backslash'),
        @('\a', 'alert (BEL)'),
        @('\b', 'backspace'),
        @('\c', 'produce no further output'),
        @('\e', 'escape'),
        @('\f', 'form feed'),
        @('\n', 'new line'),
        @('\r', 'carriage return'),
        @('\t', 'horizontal tab'),
        @('\v', 'vertical tab'),
        @('\xHH', 'byte with hexadecimal value HH (1 to 2 digits)'),
        @('\uHHHH', 'Unicode (ISO/IEC 10646) character with hex value HHHH (4 digits)'),
        @('\UHHHHHHHH', 'Unicode character with hex value HHHHHHHH (8 digits)')
    )
    $staticBareFields = @(
        @('%%', 'a single %'),
        @('%b', 'ARGUMENT as a string with ''\'' escapes interpreted'),
        @('%q', 'ARGUMENT is printed in a format that can be reused as shell input')
    )
    $conversionDescriptions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $conversionDescriptions['d'] = 'ARGUMENT as a signed decimal integer'
    $conversionDescriptions['i'] = 'ARGUMENT as a signed decimal integer'
    $conversionDescriptions['o'] = 'ARGUMENT as an unsigned octal integer'
    $conversionDescriptions['u'] = 'ARGUMENT as an unsigned decimal integer'
    $conversionDescriptions['x'] = 'ARGUMENT as an unsigned hexadecimal integer (lowercase)'
    $conversionDescriptions['X'] = 'ARGUMENT as an unsigned hexadecimal integer (uppercase)'
    $conversionDescriptions['f'] = 'ARGUMENT as a decimal floating point number'
    $conversionDescriptions['e'] = 'ARGUMENT in scientific notation (lowercase e)'
    $conversionDescriptions['E'] = 'ARGUMENT in scientific notation (uppercase E)'
    $conversionDescriptions['g'] = 'ARGUMENT as the shorter of %f and %e'
    $conversionDescriptions['G'] = 'ARGUMENT as the shorter of %f and %E'
    $conversionDescriptions['c'] = 'first character of ARGUMENT'
    $conversionDescriptions['s'] = 'ARGUMENT as a string'
    $conversionLetters = 'diouxXfeEgGcs'

    $escapes = [System.Collections.Generic.List[object]]::new()
    $bareFields = [System.Collections.Generic.List[object]]::new()
    $last = $null
    foreach ($line in ([regex]::Split($HelpText, '\r?\n'))) {
        $entry = [regex]::Match($line, '^\s{2}(?<key>\\\S+|%\S)\s+(?<desc>\S.*?)\s*$')
        if ($entry.Success) {
            $last = [pscustomobject]@{ Key = $entry.Groups['key'].Value; Description = $entry.Groups['desc'].Value }
            if ($last.Key.StartsWith('\')) {
                $escapes.Add($last)
            } else {
                $bareFields.Add($last)
            }
            continue
        }

        if ($null -ne $last -and $line -match '^\s{4,}(\S.*?)\s*$') {
            $last.Description = $last.Description.TrimEnd(',') + ' ' + $Matches[1]
            continue
        }

        $last = $null
        $letters = [regex]::Match($line, 'ending with one of\s+(?<letters>[A-Za-z]+)')
        if ($letters.Success) {
            $conversionLetters = $letters.Groups['letters'].Value
        }
    }

    if ($escapes.Count -eq 0) {
        foreach ($pair in $staticEscapes) {
            $escapes.Add([pscustomobject]@{ Key = $pair[0]; Description = $pair[1] })
        }
    }

    if ($bareFields.Count -eq 0) {
        foreach ($pair in $staticBareFields) {
            $bareFields.Add([pscustomobject]@{ Key = $pair[0]; Description = $pair[1] })
        }
    }

    # Text inserted after the trailing backslash: the literal part of each sequence.
    # \NNN is all placeholder, so it has nothing to insert and is not offered.
    $escapeCandidates = foreach ($escape in $escapes) {
        $insert = if ($escape.Key -cmatch '^\\(.)$') {
            $Matches[1]
        } elseif ($escape.Key -cmatch '^\\([xuU])H+$') {
            $Matches[1]
        } else {
            $null
        }

        if ($null -ne $insert) {
            [pscustomobject]@{ ListItem = $escape.Key; Insert = $insert; Description = $escape.Description }
        }
    }

    # %%, %b and %q reject flags, width and precision; the C conversions accept them.
    $fieldCandidates = @(
        foreach ($field in $bareFields) {
            [pscustomobject]@{ ListItem = $field.Key; Insert = $field.Key.Substring(1); Description = $field.Description; BareOnly = $true }
        }
        foreach ($letter in $conversionLetters.ToCharArray()) {
            $key = [string]$letter
            $description = if ($conversionDescriptions.ContainsKey($key)) { $conversionDescriptions[$key] } else { 'C format specification' }
            [pscustomobject]@{ ListItem = '%' + $key; Insert = $key; Description = $description; BareOnly = $false }
        }
    )

    [pscustomobject]@{
        Escapes = @($escapeCandidates)
        Fields  = $fieldCandidates
    }
}

function Get-PrintfFormatCatalog {
    $cache = Get-Variable -Name 'PrintfFormatCatalog' -Scope Script -ErrorAction Ignore
    if ($null -eq $cache -or $null -eq $cache.Value) {
        [void](Get-PrintfCompletionOptions)
        $cache = Get-Variable -Name 'PrintfFormatCatalog' -Scope Script -ErrorAction Ignore
    }

    $cache.Value
}

function New-PrintfCompletionResult {
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

function ConvertTo-PrintfQuotedValue {
    param(
        [string]$Value,
        [string]$Quote = ''
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    # Keep the quote the user typed; otherwise single-quote anything argument mode
    # would split or expand. PowerShell reads the typographic quotes as quotes too, so
    # they are escaped (U+201C-U+201E) or doubled (U+2018-U+201B) like their ASCII forms.
    if ($Quote -eq '"') {
        return '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
    }

    if ($Quote -eq "'" -or $Value -match '[\s{}();,|&<>''"`$\u2018-\u201E]' -or $Value -match '^[@#]') {
        return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
    }

    $Value
}

function Get-PrintfCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The parser keeps an unterminated quote as one element running to the cursor,
    # so '"C:\Program Fi' is one word, not 'Fi'. No element under the cursor means a
    # new, empty word.
    foreach ($element in $CommandAst.CommandElements) {
        if ($CursorPosition -gt $element.Extent.StartOffset -and $CursorPosition -le $element.Extent.EndOffset) {
            return $element.Extent.Text.Substring(0, $CursorPosition - $element.Extent.StartOffset)
        }
    }

    ''
}

function Get-PrintfPathCompletions {
    param([string]$InputPath)

    # Read the typed word through the parser: an opening ASCII or typographic quote is
    # recognised, and doubled quotes and backtick escapes resolve to the real name.
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput('x ' + $InputPath, [ref]$tokens, [ref]$errors)
    if ($tokens.Count -lt 2 -or $tokens[1].Extent.EndOffset -ne ($InputPath.Length + 2)) {
        return @()
    }

    $cleanInput = if ($tokens[1] -is [System.Management.Automation.Language.StringToken]) { $tokens[1].Value } else { $tokens[1].Text }
    $quote = switch ([string]$tokens[1].Kind) {
        'StringLiteral' { "'" }
        'StringExpandable' { '"' }
        default { '' }
    }

    # The typed directory part (through the last separator) is kept verbatim, so a
    # typed .\ or ./ prefix and the user's separator style survive.
    $prefix = $cleanInput.Substring(0, $cleanInput.LastIndexOfAny([char[]]'\/:') + 1)
    $leaf = $cleanInput.Substring($prefix.Length)
    $parent = if ($prefix) { $prefix } else { '.' }

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        # A bare name starting with a dash would be read as a parameter, so it gets the
        # current-directory prefix, as PowerShell's own file completion does.
        $pathText = if (-not $prefix -and $item.Name -match '^[-\u2013-\u2015]') {
            '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        } else {
            $prefix + $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-PrintfQuotedValue -Value $pathText -Quote $quote
        if ($item.PSIsContainer) {
            New-PrintfCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-PrintfCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-PrintfOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'PrintfCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for printf.'
}

function Get-PrintfFormatContext {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # FORMAT is the first operand; GNU printf and uutils both skip a leading '--'.
    $elements = $CommandAst.CommandElements
    $formatIndex = if ($elements.Count -gt 2 -and $elements[1].Extent.Text -eq '--') { 2 } else { 1 }
    if ($elements.Count -le $formatIndex) {
        return $null
    }

    $element = $elements[$formatIndex]
    if ($CursorPosition -le $element.Extent.StartOffset -or $CursorPosition -gt $element.Extent.EndOffset) {
        return $null
    }

    # Re-parse the typed text as an argument: an unterminated quote is one token
    # running to the cursor, and the token value has PowerShell's escapes resolved.
    $typed = $element.Extent.Text.Substring(0, $CursorPosition - $element.Extent.StartOffset)
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput('x ' + $typed, [ref]$tokens, [ref]$errors)
    if ($tokens.Count -lt 2 -or $tokens[1].Extent.StartOffset -ne 2 -or $tokens[1].Extent.EndOffset -ne ($typed.Length + 2)) {
        return $null
    }

    $token = $tokens[1]
    $tokenKind = [string]$token.Kind
    if ($tokenKind -notin @('Generic', 'StringLiteral', 'StringExpandable')) {
        return $null
    }

    # "$var %" expands at run time, so its text cannot be read as FORMAT here.
    if ($token -is [System.Management.Automation.Language.StringExpandableToken] -and $null -ne $token.NestedTokens -and $token.NestedTokens.Count -gt 0) {
        return $null
    }

    $value = if ($token -is [System.Management.Automation.Language.StringToken]) { $token.Value } else { $token.Text }
    $quote = ''
    $raw = ''
    if ($tokenKind -ne 'Generic') {
        $quote = [string]$typed[0]
        $raw = $typed.Substring(1)
        if (-not @($errors | Where-Object { $_.ErrorId -eq 'TerminatorExpectedAtEndOfString' })) {
            $raw = $raw.Substring(0, $raw.Length - 1)
        }
    }

    $pieces = @([regex]::Matches($value, '\\[\s\S]?|%(?:%|[-+ #0'']*(?:\*|[0-9]+)?(?:\.(?:\*|[0-9]*))?[\s\S]?)|[^\\%]+') | ForEach-Object { $_.Value })
    if ($pieces.Count -eq 0) {
        return $null
    }

    $tail = $pieces[-1]
    $kind = if ($tail -cmatch '^%[-+ #0'']*(?:\*|[0-9]+)?(?:\.(?:\*|[0-9]*))?$') {
        'Field'
    } elseif ($tail -eq '\') {
        'Escape'
    } else {
        return $null
    }

    [pscustomobject]@{
        Kind      = $kind
        Spec      = $tail
        TokenKind = $tokenKind
        Quote     = $quote
        Raw       = $raw
        Value     = $value
    }
}

function ConvertTo-PrintfFormatArgument {
    param(
        [object]$Context,
        [string]$Insert
    )

    # Keep the user's quote and typed text, escaping only what is appended; a bare word
    # is single-quoted once the result needs it.
    if ($Context.TokenKind -eq 'StringLiteral') {
        return $Context.Quote + $Context.Raw + ($Insert -replace '([''\u2018-\u201B])', '$1$1') + $Context.Quote
    }

    if ($Context.TokenKind -eq 'StringExpandable') {
        return $Context.Quote + $Context.Raw + ($Insert -replace '([`"$\u201C-\u201E])', '`$1') + $Context.Quote
    }

    ConvertTo-PrintfQuotedValue -Value ($Context.Value + $Insert)
}

function Get-PrintfFormatCompletion {
    param([object]$Context)

    $catalog = Get-PrintfFormatCatalog
    if ($Context.Kind -eq 'Escape') {
        foreach ($escape in $catalog.Escapes) {
            New-PrintfCompletionResult -CompletionText (ConvertTo-PrintfFormatArgument -Context $Context -Insert $escape.Insert) -ListItemText $escape.ListItem -ResultType 'ParameterValue' -ToolTip $escape.Description
        }

        return
    }

    $bare = $Context.Spec -eq '%'
    foreach ($field in $catalog.Fields) {
        if ($field.BareOnly -and -not $bare) {
            continue
        }

        New-PrintfCompletionResult -CompletionText (ConvertTo-PrintfFormatArgument -Context $Context -Insert $field.Insert) -ListItemText ($Context.Spec + $field.Insert) -ResultType 'ParameterValue' -ToolTip $field.Description
    }
}

function Complete-Printf {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete closes an open quote and spans past the cursor.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-PrintfCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition
    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    # A FORMAT word ending in an open '%' spec gets the conversions; one ending in an
    # unpaired backslash gets the escapes, unless it names a directory (.\, C:\). A lone
    # backslash is the start of an escape, not the drive root.
    $format = Get-PrintfFormatContext -CommandAst $commandAst -CursorPosition $cursorPosition
    if ($null -ne $format -and -not ($format.Kind -eq 'Escape' -and $format.Value.Length -gt 1 -and (Test-Path -LiteralPath $format.Value -PathType Container))) {
        return @(Get-PrintfFormatCompletion -Context $format)
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-PrintfCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-PrintfCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-PrintfOptionDescription -Option $option)
                }
            }
        )
    }

    Get-PrintfPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'printf', 'printf.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Printf -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
