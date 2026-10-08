# truncate tab completion for PowerShell
# Static option completion for truncate.exe and truncate.

Set-StrictMode -Version 2.0

function Get-TruncateCompletionOptions {
    $cache = Get-Variable -Name 'TruncateCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-c', '--no-create', '-o', '--io-blocks', '-r', '--reference', '-s', '--size', '--help', '--version')
    $commandCandidates = @('truncate.exe', 'truncate')
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
            Set-Variable -Name 'TruncateCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'TruncateCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'TruncateCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'TruncateCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'TruncateCompletionOptions' -Scope Script).Value
}

function New-TruncateCompletionResult {
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

function ConvertFrom-TruncateTypedWord {
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

function ConvertTo-TruncateQuotedValue {
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

function Get-TruncateCurrentToken {
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

function Get-TruncatePathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-TruncateTypedWord -Value $InputPath
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

    # Candidates keep the directory text exactly as typed (a typed .\ or ./ included).
    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]'\/')
    $typedDirectory = if ($separatorIndex -ge 0) {
        $cleanInput.Substring(0, $separatorIndex + 1)
    } elseif ($cleanInput -match '^[A-Za-z]:') {
        $cleanInput.Substring(0, 2)
    } else {
        ''
    }

    foreach ($item in $items) {
        $pathText = $typedDirectory + $item.Name
        # A bare word starting with a dash parses as a parameter, so it gets PowerShell's .\ prefix.
        if ($pathText -match '^[-\u2013-\u2015]') {
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-TruncateQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-TruncateCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-TruncateCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-TruncateOptionValueCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['-r'] = 'path'
    $table['--reference'] = 'path'
    # SIZE grammar from the help: optional modifier prefix, integer, optional unit (K/M/G/T/P/E/Z/Y
    # are powers of 1024, KB/MB/GB/... powers of 1000). '<' and '>' are PowerShell operators, so
    # those two forms are emitted quoted.
    $sizes = @(
        @{ Text = '<size>'; Tip = 'Set the size to SIZE bytes (or I/O blocks with --io-blocks).' }
        @{ Text = '+1M'; Tip = "'+' extend by SIZE." }
        @{ Text = '-1M'; Tip = "'-' reduce by SIZE." }
        @{ Text = '<1M'; Quoted = "'<1M'"; Tip = "'<' at most SIZE." }
        @{ Text = '>1M'; Quoted = "'>1M'"; Tip = "'>' at least SIZE." }
        @{ Text = '/1M'; Tip = "'/' round down to a multiple of SIZE." }
        @{ Text = '%1M'; Tip = "'%' round up to a multiple of SIZE." }
        @{ Text = '1K'; Tip = 'K = 1024 bytes (kibibytes).' }
        @{ Text = '1M'; Tip = 'M = 1024*1024 bytes (mebibytes).' }
        @{ Text = '1G'; Tip = 'G = 1024*1024*1024 bytes (gibibytes).' }
        @{ Text = '1KB'; Tip = 'KB = 1000 bytes (kilobytes).' }
        @{ Text = '1MB'; Tip = 'MB = 1000*1000 bytes (megabytes).' }
        @{ Text = '1GB'; Tip = 'GB = 1000*1000*1000 bytes (gigabytes).' }
    )
    $table['-s'] = $sizes
    $table['--size'] = $sizes

    $option = $null
    $prefix = $CurrentWord
    $attached = ''
    if ($CurrentWord -match '^(?<option>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = $Matches['option']
        $prefix = $Matches['value']
        $attached = $option + '='
    } elseif ($null -ne $TokensBeforeCurrent -and $TokensBeforeCurrent.Count -gt 0 -and $table.ContainsKey($TokensBeforeCurrent[-1])) {
        # The option is the token before the cursor, so mid-line editing keeps the value slot and
        # a leading '-' (the reduce-by form) stays in the SIZE slot instead of the option catalog.
        $option = $TokensBeforeCurrent[-1]
    }

    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-TruncatePathCompletions -InputPath $prefix) {
                New-TruncateCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    # A quoted or half-quoted value is matched on its bare text and re-quoted the same way.
    $quote = ''
    if ($prefix.Length -gt 0 -and ($prefix[0] -eq '"' -or $prefix[0] -eq "'")) {
        $quote = [string]$prefix[0]
        $prefix = $prefix.Substring(1)
        if ($prefix.EndsWith($quote)) {
            $prefix = $prefix.Substring(0, $prefix.Length - 1)
        }
    }

    @(
        foreach ($entry in $spec) {
            if (-not $entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                continue
            }

            $completion = if ($entry.ContainsKey('Quoted')) {
                $entry.Quoted
            } elseif ($quote) {
                $quote + $entry.Text + $quote
            } else {
                $entry.Text
            }

            New-TruncateCompletionResult -CompletionText ($attached + $completion) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
        }
    )
}

function Get-TruncateOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'TruncateCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for truncate.'
}

function Complete-Truncate {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-TruncateCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $tokensBeforeCurrent = @(
        foreach ($element in ($commandAst.CommandElements | Select-Object -Skip 1)) {
            if ($element.Extent.EndOffset -lt $cursorPosition) {
                $element.Extent.Text
            }
        }
    )

    $optionValues = @(Get-TruncateOptionValueCompletions -TokensBeforeCurrent $tokensBeforeCurrent -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-TruncateCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-TruncateCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-TruncateOptionDescription -Option $option)
                }
            }
        )
    }

    Get-TruncatePathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'truncate', 'truncate.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Truncate -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
