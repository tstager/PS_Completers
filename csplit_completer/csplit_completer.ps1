# csplit tab completion for PowerShell
# Static option completion for csplit.exe and csplit.

Set-StrictMode -Version 2.0

function Get-CsplitCompletionOptions {
    $cache = Get-Variable -Name 'CsplitCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--suffix-format', '-f', '--prefix', '-n', '--digits', '-s', '--quiet', '--silent', '-z', '--elide-empty-files', '-x', '--suppress-matched', '-k', '--keep-files', '--help', '--version')
    $commandCandidates = @('csplit.exe', 'csplit')
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
            foreach ($match in [regex]::Matches($line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|=|\[|\]|\)|$))')) {
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
            Set-Variable -Name 'CsplitCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'CsplitCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'CsplitCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'CsplitCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'CsplitCompletionOptions' -Scope Script).Value
}

function New-CsplitCompletionResult {
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

function ConvertFrom-CsplitTypedWord {
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

function ConvertTo-CsplitQuotedValue {
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
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]|^[-\u2013-\u2015]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-CsplitCurrentToken {
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

function Get-CsplitPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-CsplitTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # Keep the typed directory part ('.\', './', 'sub/', 'C:\') exactly as typed; only the
    # leaf after the last separator is completed.
    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    $directoryText = $cleanInput.Substring(0, $separatorIndex + 1)
    $leaf = $cleanInput.Substring($separatorIndex + 1)
    $parent = if ($directoryText) { $directoryText } else { '.' }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = $directoryText + $item.Name
        # PowerShell reads a word starting with a dash as a parameter: lead with '.\' as its
        # own file completion does.
        if (-not $directoryText -and $pathText -match '^[-\u2013-\u2015]') {
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-CsplitQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-CsplitCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-CsplitCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-CsplitOptionValueCompletions {
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
        @{ Text = '%02d'; Tip = 'Two-digit suffix.' }
        @{ Text = '%03d'; Tip = 'Three-digit suffix.' }
        @{ Text = '%d'; Tip = 'Unpadded suffix.' }
    )
    $table['--suffix-format'] = @(
        @{ Text = '%02d'; Tip = 'Two-digit suffix.' }
        @{ Text = '%03d'; Tip = 'Three-digit suffix.' }
        @{ Text = '%d'; Tip = 'Unpadded suffix.' }
    )
    $table['-f'] = @(
        @{ Text = '<prefix>'; Tip = 'Output file prefix.' }
    )
    $table['--prefix'] = @(
        @{ Text = '<prefix>'; Tip = 'Output file prefix.' }
    )
    $table['-n'] = @(
        @{ Text = '<digits>'; Tip = 'Number of suffix digits.' }
    )
    $table['--digits'] = @(
        @{ Text = '<digits>'; Tip = 'Number of suffix digits.' }
    )
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-CsplitPathCompletions -InputPath $prefix) {
                New-CsplitCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-CsplitCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-CsplitOperandIndex {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    # Count the operands typed before the cursor: skip options, and the token that follows a
    # value-taking option in its separate form ('-f PREFIX', '--digits N').
    $valueOptions = @('-b', '--suffix-format', '-f', '--prefix', '-n', '--digits')
    $index = 0
    $skipNext = $false
    foreach ($element in ($commandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.EndOffset -ge $cursorPosition) {
            break
        }

        $text = $element.Extent.Text
        if ($skipNext) {
            $skipNext = $false
            continue
        }

        if ($text -ceq '--') {
            continue
        }

        if ($text.StartsWith('-') -and $text.Length -gt 1) {
            if ($text -cin $valueOptions) {
                $skipNext = $true
            }

            continue
        }

        $index++
    }

    $index
}

function Complete-CsplitPattern {
    param([string]$CurrentWord)

    # 'csplit [OPTION]... FILE PATTERN...': every operand after FILE is a pattern from the
    # grammar in the help text, never a path.
    $patterns = @(
        @{ Text = '<INTEGER>'; Tip = 'Copy up to but not including the specified line number.' }
        @{ Text = '/REGEXP/'; Tip = 'Copy up to but not including a matching line; an optional +N or -N line offset may follow.' }
        @{ Text = '%REGEXP%'; Tip = 'Skip to, but not including, a matching line; an optional +N or -N line offset may follow.' }
        @{ Text = '{INTEGER}'; Tip = 'Repeat the previous pattern the specified number of times.' }
        @{ Text = '{*}'; Tip = 'Repeat the previous pattern as many times as possible.' }
    )

    @(
        foreach ($pattern in $patterns) {
            if ($pattern.Text.StartsWith($CurrentWord, [System.StringComparison]::Ordinal)) {
                New-CsplitCompletionResult -CompletionText $pattern.Text -ListItemText $pattern.Text -ResultType 'ParameterValue' -ToolTip $pattern.Tip
            }
        }
    )
}

function Get-CsplitOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'CsplitCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for csplit.'
}

function Complete-Csplit {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-CsplitCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-CsplitOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    $operandIndex = Get-CsplitOperandIndex -commandAst $commandAst -cursorPosition $cursorPosition

    if ([string]::IsNullOrEmpty($currentWord)) {
        if ($operandIndex -ge 1) {
            return Complete-CsplitPattern -CurrentWord ''
        }

        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            # A bare '-' in the FILE slot is also the documented stdin operand.
            if ($currentWord -ceq '-' -and $operandIndex -eq 0) {
                New-CsplitCompletionResult -CompletionText '-' -ListItemText '-' -ResultType 'ParameterValue' -ToolTip 'Read standard input instead of a FILE.'
            }
            foreach ($option in Get-CsplitCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-CsplitCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-CsplitOptionDescription -Option $option)
                }
            }
        )
    }

    if ($operandIndex -ge 1) {
        return Complete-CsplitPattern -CurrentWord $currentWord
    }

    Get-CsplitPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'csplit', 'csplit.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Csplit -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
