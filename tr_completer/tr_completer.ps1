# tr tab completion for PowerShell
# Static option completion for tr.exe and tr.

Set-StrictMode -Version 2.0

function Get-TrCompletionOptions {
    $cache = Get-Variable -Name 'TrCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-c', '--complement', '-C', '-d', '--delete', '-s', '--squeeze-repeats', '-t', '--truncate-set1', '-h', '--help', '-V', '--version')
    $commandCandidates = @('tr.exe', 'tr')
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

        $options = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $descriptions = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
        foreach ($line in ([regex]::Split($helpOutput, '\r?\n'))) {
            foreach ($match in [regex]::Matches($line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|=|\[|\]|$))')) {
                $rawOption = $match.Groups[1].Value
                $normalized = $rawOption.Trim()
                if ($normalized.StartsWith('--')) {
                    $normalized = $normalized -replace '\[.*$', ''
                    $normalized = $normalized -replace '=.*$', ''
                }
                if ($normalized -match '^-{1,2}[A-Za-z0-9][A-Za-z0-9-]*$') {
                    [void]$options.Add($normalized)
                if (-not $descriptions.ContainsKey($normalized)) {
                    $description = ($line -replace '^\s*(?:-{1,2}[A-Za-z0-9][A-Za-z0-9-]*(?:[=\[]\S*)?[,\s]+)+', '').Trim()
                    if ($description -and $description -ne $line.Trim()) {
                        $descriptions[$normalized] = $description
                    }
                }
                }
            }
        }

        if ($options.Count -gt 0) {
            Set-Variable -Name 'TrCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'TrCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'TrCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'TrCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'TrCompletionOptions' -Scope Script).Value
}


function New-TrCompletionResult {
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

function ConvertFrom-TrTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    $tokens[0].Value
}

function ConvertTo-TrQuotedValue {
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

function Get-TrCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The parser keeps an unterminated quoted word as one element running to the cursor.
    foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    ''
}

function Get-TrPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-TrTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    if ([string]::IsNullOrEmpty($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]+$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
        $parent = if ($separatorIndex -ge 0) { $cleanInput.Substring(0, $separatorIndex + 1) } else { '.' }
        $leaf = $cleanInput.Substring($separatorIndex + 1)
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    $separator = if ($parent.EndsWith('/')) { [char]'/' } else { [System.IO.Path]::DirectorySeparatorChar }
    foreach ($item in $items) {
        # Keep the typed directory text (.\, ./, ..\) as typed. A bare name starting with a dash
        # would be read as a parameter, so it gets the current-directory prefix.
        $pathText = if ($parent -ne '.') {
            $parent + $item.Name
        } elseif ($item.Name -match '^[-\u2013-\u2015]') {
            '.' + $separator + $item.Name
        } else {
            $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith($separator)) {
            $pathText += $separator
        }

        $quotedPath = ConvertTo-TrQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-TrCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-TrCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-TrSetVocabulary {
    param([string]$InputWord)

    $quote = if ($InputWord -match '^[''"\u2018-\u201E]') { $InputWord.Substring(0, 1) } else { '' }
    $typed = ConvertFrom-TrTypedWord -Value $InputWord

    $vocabulary = [ordered]@{
        '[:alnum:]'  = 'Letters and digits'
        '[:alpha:]'  = 'Letters'
        '[:blank:]'  = 'Horizontal whitespace (space and tab)'
        '[:cntrl:]'  = 'Control characters'
        '[:digit:]'  = 'Digits'
        '[:graph:]'  = 'Printable characters, not including space'
        '[:lower:]'  = 'Lowercase letters'
        '[:print:]'  = 'Printable characters, including space'
        '[:punct:]'  = 'Punctuation characters'
        '[:space:]'  = 'Horizontal or vertical whitespace'
        '[:upper:]'  = 'Uppercase letters'
        '[:xdigit:]' = 'Hexadecimal digits'
        '\\'         = 'Backslash'
        '\a'         = 'Audible BEL'
        '\b'         = 'Backspace'
        '\f'         = 'Form feed'
        '\n'         = 'New line'
        '\r'         = 'Return'
        '\t'         = 'Horizontal tab'
        '\v'         = 'Vertical tab'
    }

    if ($typed -match '^\[=(.)=?$') {
        $vocabulary['[=' + $Matches[1] + '=]'] = 'All characters equivalent to ' + $Matches[1]
    } elseif ($typed -match '^\[([^:=])\*(\d*)$') {
        $vocabulary['[' + $Matches[1] + '*' + $Matches[2] + ']'] = if ($Matches[2]) { $Matches[2] + ' copies of ' + $Matches[1] } else { 'Copies of ' + $Matches[1] + ' up to the length of SET1 (SET2 only)' }
    }

    foreach ($entry in $vocabulary.GetEnumerator()) {
        if ($entry.Key.StartsWith($typed, [System.StringComparison]::Ordinal)) {
            New-TrCompletionResult -CompletionText (ConvertTo-TrQuotedValue -Value $entry.Key -QuoteChar $quote) -ListItemText $entry.Key -ResultType 'ParameterValue' -ToolTip $entry.Value
        }
    }
}

function Test-TrSetOperandSlot {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    # tr takes SET1 alone with -d (and no -s), otherwise SET1 SET2 (SET2 is optional with -s alone).
    # Options end at '--' or at the first operand; long options may be abbreviated.
    $operands = 0
    $delete = $false
    $squeeze = $false
    $endOfOptions = $false
    foreach ($element in @($commandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.EndOffset -ge $cursorPosition) {
            break
        }

        $text = $element.Extent.Text
        if ($endOfOptions -or $operands -gt 0 -or -not $text.StartsWith('-') -or $text -eq '-') {
            $operands++
        } elseif ($text -ceq '--') {
            $endOfOptions = $true
        } elseif ($text.StartsWith('--')) {
            $delete = $delete -or '--delete'.StartsWith($text, [System.StringComparison]::Ordinal)
            $squeeze = $squeeze -or '--squeeze-repeats'.StartsWith($text, [System.StringComparison]::Ordinal)
        } else {
            $delete = $delete -or $text.Contains('d')
            $squeeze = $squeeze -or $text.Contains('s')
        }
    }

    $maxOperands = if ($delete -and -not $squeeze) { 1 } else { 2 }
    $operands -lt $maxOperands
}

function Get-TrOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'TrCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for tr.'
}

function Complete-Tr {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-TrCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $inSetSlot = Test-TrSetOperandSlot -commandAst $commandAst -cursorPosition $cursorPosition
    if ([string]::IsNullOrEmpty($currentWord) -and -not $inSetSlot) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-TrCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-TrCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-TrOptionDescription -Option $option)
                }
            }
        )
    }

    if ($inSetSlot) {
        $setCompletions = @(Get-TrSetVocabulary -InputWord $currentWord)
        if ($setCompletions.Count -gt 0) {
            return $setCompletions
        }
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    Get-TrPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'tr', 'tr.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Tr -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
