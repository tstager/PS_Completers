# nl tab completion for PowerShell
# Static option completion for nl.exe and nl.

Set-StrictMode -Version 2.0

function Get-NlCompletionOptions {
    $cache = Get-Variable -Name 'NlCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--body-numbering', '-d', '--section-delimiter', '-f', '--footer-numbering', '-h', '--header-numbering', '-i', '--line-increment', '-l', '--join-blank-lines', '-n', '--number-format', '-p', '--no-renumber', '-s', '--number-separator', '-v', '--starting-line-number', '-w', '--number-width', '--help', '--version')
    $commandCandidates = @('nl.exe', 'nl')
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
            foreach ($match in [regex]::Matches($line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|=|\[|$))')) {
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
            Set-Variable -Name 'NlCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'NlCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'NlCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'NlCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'NlCompletionOptions' -Scope Script).Value
}

function New-NlCompletionResult {
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

function ConvertFrom-NlTypedWord {
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

function ConvertTo-NlQuotedValue {
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

function Get-NlCurrentToken {
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

function Get-NlPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-NlTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
        $typedDir = ''
    } elseif ($cleanInput -match '[\\/]+$') {
        $parent = $cleanInput
        $leaf = ''
        $typedDir = $cleanInput
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
        # The directory part exactly as typed, so a typed .\ or ./ prefix and separator style survive.
        $typedDir = if ($cleanInput -match '^(.*[\\/])') { $Matches[1] } else { '' }
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = $typedDir + $item.Name
        if (-not $typedDir -and $item.Name -match '^[-\u2013-\u2015]') {
            # A bare word starting with a dash parses as a parameter; anchor it to the current directory.
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-NlQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-NlCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-NlCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-NlOptionValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $option = $null
    $prefix = $CurrentWord
    $attached = ''
    if ($CurrentWord -match '^(?<option>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = $Matches['option']
        $prefix = $Matches['value']
        $attached = $option + '='
    } elseif (-not $CurrentWord.StartsWith('-')) {
        $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
        if ([string]::IsNullOrEmpty($CurrentWord)) {
            if ($elements.Count -gt 1) {
                $option = $elements[-1]
            }
        } elseif ($elements.Count -gt 2 -and $elements[-1] -eq $CurrentWord) {
            $option = $elements[-2]
        }
    }

    if ([string]::IsNullOrEmpty($option)) {
        return @()
    }

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['-b'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['--body-numbering'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['-f'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['--footer-numbering'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['-h'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['--header-numbering'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['-d'] = @(
        @{ Text = '<cc>'; Tip = 'Two-character section delimiter.' }
    )
    $table['--section-delimiter'] = @(
        @{ Text = '<cc>'; Tip = 'Two-character section delimiter.' }
    )
    $table['-i'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--line-increment'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-l'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--join-blank-lines'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-v'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--starting-line-number'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-w'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--number-width'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-n'] = @(
        @{ Text = 'ln'; Tip = 'Left justified, no leading zeros.' }
        @{ Text = 'rn'; Tip = 'Right justified, no leading zeros.' }
        @{ Text = 'rz'; Tip = 'Right justified, leading zeros.' }
    )
    $table['--number-format'] = @(
        @{ Text = 'ln'; Tip = 'Left justified, no leading zeros.' }
        @{ Text = 'rn'; Tip = 'Right justified, no leading zeros.' }
        @{ Text = 'rz'; Tip = 'Right justified, leading zeros.' }
    )
    $table['-s'] = @(
        @{ Text = '<string>'; Tip = 'Text after the line number.' }
    )
    $table['--number-separator'] = @(
        @{ Text = '<string>'; Tip = 'Text after the line number.' }
    )
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-NlPathCompletions -InputPath $prefix) {
                New-NlCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    $valueQuote = if ($prefix -match '^[''"\u2018-\u201E]') { $prefix.Substring(0, 1) } else { '' }
    $prefix = ConvertFrom-NlTypedWord -Value $prefix
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                $valueText = if ($valueQuote) { ConvertTo-NlQuotedValue -Value $entry.Text -QuoteChar $valueQuote } else { $entry.Text }
                New-NlCompletionResult -CompletionText ($attached + $valueText) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-NlOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'NlCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for nl.'
}

function Complete-Nl {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-NlCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-NlOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return Get-NlPathCompletions -InputPath ''
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-NlCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-NlCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-NlOptionDescription -Option $option)
                }
            }
        )
    }

    Get-NlPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'nl', 'nl.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Nl -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
