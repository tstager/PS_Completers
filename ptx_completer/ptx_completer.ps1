# ptx tab completion for PowerShell
# Static option completion for ptx.exe and ptx.

Set-StrictMode -Version 2.0

function Get-PtxCompletionOptions {
    $cache = Get-Variable -Name 'PtxCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('--format', '--gnu', '--output', '--width', '--indent', '--no-indent', '--ignore-case', '--references', '--break-file', '--file-prefix', '--output-file', '--silent', '--help', '--version', '-F', '-G', '-M', '-R', '-S', '-T', '-b', '-f', '-g', '-i', '-m', '-o', '-r', '-s', '-t', '-w')
    $commandCandidates = @('ptx.exe', 'ptx')
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
            Set-Variable -Name 'PtxCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'PtxCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'PtxCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'PtxCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'PtxCompletionOptions' -Scope Script).Value
}

function New-PtxCompletionResult {
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

function ConvertFrom-PtxTypedWord {
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

function ConvertTo-PtxQuotedValue {
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

function Get-PtxCurrentToken {
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

function Get-PtxPathCompletions {
    param(
        [string]$InputPath,
        [switch]$Attached
    )

    $cleanInput = ConvertFrom-PtxTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # Keep the typed directory part exactly as typed (.\, ./, ..\, sub/) and complete the leaf.
    [void]($cleanInput -match '^(?<dir>.*[\\/]|[A-Za-z]:)?(?<leaf>[^\\/]*)$')
    $typedDir = [string]$Matches['dir']
    $leaf = $Matches['leaf']
    $parent = if ($typedDir) { $typedDir } else { '.' }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = $typedDir + $item.Name
        if (-not $typedDir -and -not $Attached -and $pathText -match '^[-\u2013-\u2015]') {
            # A whole word starting with a dash would be read as a parameter: prefix .\ as PowerShell does.
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-PtxQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-PtxCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-PtxCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-PtxOptionValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord,
        [ref]$IsValueSlot
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
    $table['-F'] = @(
        @{ Text = '<string>'; Tip = 'Literal string.' }
    )
    $table['--flag-truncation'] = @(
        @{ Text = '<string>'; Tip = 'Literal string.' }
    )
    $table['-M'] = @(
        @{ Text = '<string>'; Tip = 'Literal string.' }
    )
    $table['--macro-name'] = @(
        @{ Text = '<string>'; Tip = 'Literal string.' }
    )
    $table['-S'] = @(
        @{ Text = '<regexp>'; Tip = 'Regular expression.' }
    )
    $table['--sentence-regexp'] = @(
        @{ Text = '<regexp>'; Tip = 'Regular expression.' }
    )
    $table['-W'] = @(
        @{ Text = '<regexp>'; Tip = 'Regular expression.' }
    )
    $table['--word-regexp'] = @(
        @{ Text = '<regexp>'; Tip = 'Regular expression.' }
    )
    $table['-b'] = 'path'
    $table['--break-file'] = 'path'
    $table['-i'] = 'path'
    $table['--ignore-file'] = 'path'
    $table['-o'] = 'path'
    $table['--only-file'] = 'path'
    $gapSizes = @(
        @{ Text = '1'; Tip = 'Gap of 1 column between output fields.' }
        @{ Text = '2'; Tip = 'Gap of 2 columns between output fields.' }
        @{ Text = '3'; Tip = 'Gap of 3 columns between output fields (default).' }
    )
    $table['-g'] = $gapSizes
    $table['--gap-size'] = $gapSizes
    $widths = @(
        @{ Text = '72'; Tip = 'Output width of 72 columns (default).' }
        @{ Text = '80'; Tip = 'Output width of 80 columns.' }
        @{ Text = '100'; Tip = 'Output width of 100 columns (the -t default).' }
        @{ Text = '132'; Tip = 'Output width of 132 columns.' }
    )
    $table['-w'] = $widths
    $table['--width'] = $widths
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $IsValueSlot.Value = $true

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-PtxPathCompletions -InputPath $prefix -Attached:([bool]$attached)) {
                New-PtxCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-PtxCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-PtxOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'PtxCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for ptx.'
}

function Complete-Ptx {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-PtxCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $isValueSlot = $false
    $optionValues = @(Get-PtxOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord -IsValueSlot ([ref]$isValueSlot))
    if ($isValueSlot) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-PtxCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-PtxCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-PtxOptionDescription -Option $option)
                }
            }
        )
    }

    Get-PtxPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'ptx', 'ptx.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Ptx -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
