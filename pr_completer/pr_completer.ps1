# pr tab completion for PowerShell
# Static option completion for pr.exe and pr.

Set-StrictMode -Version 2.0

function Get-PrCompletionOptions {
    $cache = Get-Variable -Name 'PrCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-a', '--across', '-c', '--show-control-chars', '-d', '--double-space', '-e', '--expand-tabs', '-f', '--form-feed', '-h', '--header', '-i', '--indent', '-l', '--length', '-m', '--merge', '-n', '--number-lines', '-o', '--output-tabs', '-r', '--no-file-warnings', '-s', '--separator', '-t', '--omit-header', '-T', '--omit-pagination', '-v', '--show-all', '-w', '--width', '-F', '--page-range', '--help', '--version')
    $commandCandidates = @('pr.exe', 'pr')
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
        $attachedOnly = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($line in ([regex]::Split($helpOutput, '\r?\n'))) {
            # GNU spells optional arguments attached ('-s[CHAR], --separator[=CHAR]'): a separate word is a FILE.
            foreach ($match in [regex]::Matches($line, '(?<=^\s*(?:-\S*,\s+)*)(--?[A-Za-z0-9][A-Za-z0-9-]*)\[')) {
                [void]$attachedOnly.Add($match.Groups[1].Value)
            }

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
            Set-Variable -Name 'PrCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'PrCompletionDescriptions' -Value $descriptions -Scope Script
            Set-Variable -Name 'PrAttachedOnlyOptions' -Value $attachedOnly -Scope Script
            return (Get-Variable -Name 'PrCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'PrCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'PrCompletionOptions' -Scope Script).Value
}

function New-PrCompletionResult {
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

function ConvertFrom-PrTypedWord {
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

function ConvertTo-PrQuotedValue {
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

function Get-PrCurrentToken {
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

function Get-PrPreviousToken {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    if ($elements.Count -le 1) {
        return $null
    }

    if ([string]::IsNullOrEmpty($CurrentWord)) {
        return $elements[-1]
    }

    if ($elements[-1] -eq $CurrentWord) {
        return $elements[-2]
    }

    return $elements[-1]
}

function Get-PrValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $previousToken = Get-PrPreviousToken -commandAst $commandAst -CurrentWord $CurrentWord
    if ($null -eq $previousToken) {
        return @()
    }

    switch ($previousToken) {
        '--columns' { return @(
            New-PrCompletionResult -CompletionText '2' -ListItemText '2' -ResultType 'ParameterValue' -ToolTip 'Split into two columns.'
            New-PrCompletionResult -CompletionText '3' -ListItemText '3' -ResultType 'ParameterValue' -ToolTip 'Split into three columns.'
        ) }
        '--header' { return @(
            New-PrCompletionResult -CompletionText '<header>' -ListItemText '<header>' -ResultType 'ParameterValue' -ToolTip 'Custom header text.'
        ) }
        '--indent' { return @(
            New-PrCompletionResult -CompletionText '<indent>' -ListItemText '<indent>' -ResultType 'ParameterValue' -ToolTip 'Indent string.'
        ) }
        '--length' { return @(
            New-PrCompletionResult -CompletionText '66' -ListItemText '66' -ResultType 'ParameterValue' -ToolTip 'Standard page length.'
            New-PrCompletionResult -CompletionText '<length>' -ListItemText '<length>' -ResultType 'ParameterValue' -ToolTip 'Page length.'
        ) }
        '--width' { return @(
            New-PrCompletionResult -CompletionText '72' -ListItemText '72' -ResultType 'ParameterValue' -ToolTip 'Standard page width.'
            New-PrCompletionResult -CompletionText '<width>' -ListItemText '<width>' -ResultType 'ParameterValue' -ToolTip 'Page width.'
        ) }
        '--page-range' { return @(
            New-PrCompletionResult -CompletionText '1-2' -ListItemText '1-2' -ResultType 'ParameterValue' -ToolTip 'Page range.'
            New-PrCompletionResult -CompletionText '<range>' -ListItemText '<range>' -ResultType 'ParameterValue' -ToolTip 'Page range to print.'
        ) }
    }

    return @()
}

function Get-PrPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-PrTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]+$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    # Keep the typed directory text (.\, ./, sub/) exactly as typed.
    $typedDirectory = $cleanInput -replace '[^\\/]*$', ''
    foreach ($item in $items) {
        $pathText = $typedDirectory + $item.Name
        # A bare word starting with a dash is parsed as a parameter: anchor it like PowerShell does.
        if (-not $typedDirectory -and $pathText -match '^[-\u2013-\u2015]') {
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-PrQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-PrCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-PrCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-PrOptionValueCompletions {
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

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['--pages'] = @(
        @{ Text = '1'; Tip = 'Start at page 1.' }
        @{ Text = '1:2'; Tip = 'Pages 1 through 2.' }
        @{ Text = '<first>[:<last>]'; Tip = 'Page range, colon-separated.' }
    )
    $table['--columns'] = @(
        @{ Text = '<n>'; Tip = 'Number of columns.' }
    )
    $table['-D'] = @(
        @{ Text = '<format>'; Tip = 'strftime date format.' }
    )
    $table['--date-format'] = @(
        @{ Text = '<format>'; Tip = 'strftime date format.' }
    )
    $table['-e'] = @(
        @{ Text = '<char>'; Tip = 'Tab or separator character.' }
    )
    $table['--expand-tabs'] = @(
        @{ Text = '<char>'; Tip = 'Tab or separator character.' }
    )
    $table['-i'] = @(
        @{ Text = '<char>'; Tip = 'Tab or separator character.' }
    )
    $table['--output-tabs'] = @(
        @{ Text = '<char>'; Tip = 'Tab or separator character.' }
    )
    $table['-s'] = @(
        @{ Text = '<char>'; Tip = 'Tab or separator character.' }
    )
    $table['--separator'] = @(
        @{ Text = '<char>'; Tip = 'Tab or separator character.' }
    )
    $table['-h'] = @(
        @{ Text = '<header>'; Tip = 'Page header text.' }
    )
    $table['--header'] = @(
        @{ Text = '<header>'; Tip = 'Page header text.' }
    )
    $table['-l'] = @(
        @{ Text = '66'; Tip = '66 lines, the default.' }
        @{ Text = '<lines>'; Tip = 'Page length.' }
    )
    $table['--length'] = @(
        @{ Text = '66'; Tip = '66 lines, the default.' }
        @{ Text = '<lines>'; Tip = 'Page length.' }
    )
    $table['-n'] = @(
        @{ Text = '<sep>'; Tip = 'Separator after the line number.' }
    )
    $table['--number-lines'] = @(
        @{ Text = '<sep>'; Tip = 'Separator after the line number.' }
    )
    $table['-N'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--first-line-number'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-o'] = @(
        @{ Text = '<margin>'; Tip = 'Left margin width.' }
    )
    $table['--indent'] = @(
        @{ Text = '<margin>'; Tip = 'Left margin width.' }
    )
    $table['-S'] = @(
        @{ Text = '<string>'; Tip = 'Column separator string.' }
    )
    $table['--sep-string'] = @(
        @{ Text = '<string>'; Tip = 'Column separator string.' }
    )
    $table['-w'] = @(
        @{ Text = '72'; Tip = '72 columns, the default.' }
        @{ Text = '<cols>'; Tip = 'Page width.' }
    )
    $table['--width'] = @(
        @{ Text = '72'; Tip = '72 columns, the default.' }
        @{ Text = '<cols>'; Tip = 'Page width.' }
    )
    $table['-W'] = @(
        @{ Text = '72'; Tip = '72 columns, the default.' }
        @{ Text = '<cols>'; Tip = 'Page width.' }
    )
    $table['--page-width'] = @(
        @{ Text = '72'; Tip = '72 columns, the default.' }
        @{ Text = '<cols>'; Tip = 'Page width.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    if ([string]::IsNullOrEmpty($attached)) {
        [void](Get-PrCompletionOptions)
        $attachedOnly = Get-Variable -Name 'PrAttachedOnlyOptions' -Scope Script -ErrorAction Ignore
        if ($null -ne $attachedOnly -and $attachedOnly.Value.Contains($option)) {
            return @()
        }
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-PrPathCompletions -InputPath $prefix) {
                New-PrCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-PrCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-PrOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'PrCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for pr.'
}

function Complete-Pr {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-PrCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-PrOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        $valueCompletions = @(Get-PrValueCompletions -commandAst $commandAst -CurrentWord $wordToComplete)
        if ($valueCompletions.Count -gt 0) {
            return $valueCompletions
        }

        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-PrCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-PrCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-PrOptionDescription -Option $option)
                }
            }
        )
    }

    Get-PrPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'pr', 'pr.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pr -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
