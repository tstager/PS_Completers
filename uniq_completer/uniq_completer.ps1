# uniq tab completion for PowerShell
# Static option completion for uniq.exe and uniq.

Set-StrictMode -Version 2.0

function Get-UniqCompletionOptions {
    $cache = Get-Variable -Name 'UniqCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-D', '--all-repeated', '-m', '--group', '-w', '--check-chars', '-c', '--count', '-i', '--ignore-case', '-d', '--repeated', '-s', '--skip-chars', '-f', '--skip-fields', '-u', '--unique', '-z', '--zero-terminated', '-h', '--help', '-V', '--version')
    $commandCandidates = @('uniq.exe', 'uniq')
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
            Set-Variable -Name 'UniqCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'UniqCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'UniqCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'UniqCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'UniqCompletionOptions' -Scope Script).Value
}


function New-UniqCompletionResult {
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

function ConvertFrom-UniqTypedWord {
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

function ConvertTo-UniqQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default). PowerShell reads ' and
    # U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes.
    param(
        [string]$Value,
        [string]$Quote = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if ([string]::IsNullOrEmpty($Quote)) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }
        $Quote = "'"
    }

    if ($Quote -match '^[''\u2018-\u201B]$') {
        return $Quote + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $Quote
    }

    $Quote + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $Quote
}

function Get-UniqCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The parser keeps an unterminated quote as one element running to the cursor.
    foreach ($element in $CommandAst.CommandElements) {
        $extent = $element.Extent
        if ($CursorPosition -gt $extent.StartOffset -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    ''
}

function Get-UniqPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-UniqTypedWord -Value $InputPath
    $quote = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

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

    # Keep the directory part exactly as typed (.\, ./, C:, ...) so no typed text is lost.
    $typedDirectory = if ($cleanInput -match '^(?<dir>.*[\\/]|[A-Za-z]:)') { $Matches['dir'] } else { '' }

    foreach ($item in $items) {
        $pathText = $typedDirectory + $item.Name
        # A bare word starting with a dash is a parameter to PowerShell; anchor it like PowerShell does.
        if ($typedDirectory -eq '' -and $pathText -match '^[-\u2013-\u2015]') {
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-UniqQuotedValue -Value $pathText -Quote $quote
        if ($item.PSIsContainer) {
            New-UniqCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-UniqCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-UniqOptionValueCompletions {
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

    # --group and --all-repeated take an optional METHOD that uniq accepts only attached (--group=both);
    # after a space the word is the INPUT operand, so no value is pending.
    if ([string]::IsNullOrEmpty($attached) -and ($option -ceq '--group' -or $option -ceq '--all-repeated')) {
        return @()
    }

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['--all-repeated'] = @(
        @{ Text = 'none'; Tip = 'No group separator.' }
        @{ Text = 'prepend'; Tip = 'Separator before each group.' }
        @{ Text = 'separate'; Tip = 'Separator between groups.' }
    )
    $table['--group'] = @(
        @{ Text = 'separate'; Tip = 'Separator between groups.' }
        @{ Text = 'prepend'; Tip = 'Separator before each group.' }
        @{ Text = 'append'; Tip = 'Separator after each group.' }
        @{ Text = 'both'; Tip = 'Separator before and after each group.' }
    )
    $table['-f'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--skip-fields'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-s'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--skip-chars'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-w'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--check-chars'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-UniqPathCompletions -InputPath $prefix) {
                New-UniqCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-UniqCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-UniqOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'UniqCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for uniq.'
}

function Complete-Uniq {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete closes an open quote and spans past the cursor.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-UniqCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-UniqOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-UniqCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-UniqCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-UniqOptionDescription -Option $option)
                }
            }
        )
    }

    Get-UniqPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'uniq', 'uniq.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Uniq -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
