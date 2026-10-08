# head tab completion for PowerShell
# Static option completion for head.exe and head.

Set-StrictMode -Version 2.0

function Get-HeadCompletionOptions {
    $cache = Get-Variable -Name 'HeadCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-c', '--bytes', '-n', '--lines', '-q', '--quiet', '--silent', '-v', '--verbose', '-z', '--zero-terminated', '-h', '--help', '-V', '--version')
    $commandCandidates = @('head.exe', 'head')
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
            Set-Variable -Name 'HeadCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'HeadCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'HeadCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'HeadCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'HeadCompletionOptions' -Scope Script).Value
}


function New-HeadCompletionResult {
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

function ConvertFrom-HeadTypedWord {
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

function ConvertTo-HeadQuotedValue {
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

function Get-HeadCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$Fallback
    )

    # Read the word from the parser: an unterminated quote is one element that
    # runs to the cursor, so a quoted fragment with a space stays whole.
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    $Fallback
}

function Get-HeadPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-HeadTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # The typed directory part (.\ and ./ included) is kept exactly as typed.
    $directory = ''
    $leaf = ''
    if (-not [string]::IsNullOrWhiteSpace($cleanInput) -and $cleanInput -match '^(?<dir>.*[\\/]|[A-Za-z]:)?(?<leaf>[^\\/]*)$') {
        $directory = $Matches['dir']
        $leaf = $Matches['leaf']
    }

    $parent = if ($directory) { $directory } else { '.' }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        # A bare word starting with a dash parses as a parameter: anchor it to the current directory.
        $pathText = if (-not $directory -and $item.Name -match '^[-\u2013-\u2015]') {
            '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        } else {
            $directory + $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-HeadQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-HeadCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-HeadCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-HeadOptionValueCompletions {
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
    } elseif ($CurrentWord -match '^(?<option>-[cn])(?<value>.+)$') {
        # head accepts the value glued to the short option (-n5, -c1K).
        $option = $Matches['option']
        $prefix = $Matches['value']
        $attached = $option
    } elseif (-not $CurrentWord.StartsWith('-') -or $CurrentWord -match '^-\d') {
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
    $table['-c'] = @(
        @{ Text = '<num>'; Tip = 'First NUM units.' }
        @{ Text = '-<num>'; Tip = 'All but the last NUM units.' }
    )
    $table['--bytes'] = @(
        @{ Text = '<num>'; Tip = 'First NUM units.' }
        @{ Text = '-<num>'; Tip = 'All but the last NUM units.' }
    )
    $table['-n'] = @(
        @{ Text = '<num>'; Tip = 'First NUM units.' }
        @{ Text = '-<num>'; Tip = 'All but the last NUM units.' }
    )
    $table['--lines'] = @(
        @{ Text = '<num>'; Tip = 'First NUM units.' }
        @{ Text = '-<num>'; Tip = 'All but the last NUM units.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-HeadPathCompletions -InputPath $prefix) {
                New-HeadCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    if ($prefix -match '^(?<num>-?\d+)(?<suffix>[A-Za-z]*)$') {
        # A typed number replaces the placeholders: keep it, offer a short
        # ladder, and the multiplier suffixes head accepts (always for bytes,
        # once a suffix letter is typed for lines).
        $num = $Matches['num']
        $tip = if ($num.StartsWith('-')) { 'All but the last NUM units.' } else { 'First NUM units.' }
        $values = @(
            if (-not $Matches['suffix']) {
                foreach ($text in $num, ($num + '0'), ($num + '00')) {
                    @{ Text = $text; Tip = $tip }
                }
            }
            if ($option -eq '-c' -or $option -eq '--bytes' -or $Matches['suffix']) {
                foreach ($suffix in @(
                        @{ Text = 'b'; Tip = '512' }
                        @{ Text = 'K'; Tip = '1024' }
                        @{ Text = 'KiB'; Tip = '1024' }
                        @{ Text = 'kB'; Tip = '1000' }
                        @{ Text = 'M'; Tip = '1024*1024' }
                        @{ Text = 'MiB'; Tip = '1024*1024' }
                        @{ Text = 'MB'; Tip = '1000*1000' }
                        @{ Text = 'G'; Tip = '1024^3' }
                        @{ Text = 'GiB'; Tip = '1024^3' }
                        @{ Text = 'GB'; Tip = '1000^3' }
                    )) {
                    @{ Text = $num + $suffix.Text; Tip = $tip + ' Multiplier ' + $suffix.Text + ' = ' + $suffix.Tip + '.' }
                }
            }
        )
    }

    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-HeadCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-HeadOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'HeadCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for head.'
}

function Complete-Head {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-HeadCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $optionValues = @(Get-HeadOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-HeadCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-HeadCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-HeadOptionDescription -Option $option)
                }
            }
        )
    }

    Get-HeadPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'head', 'head.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Head -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
