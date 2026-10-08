# base64 tab completion for PowerShell
# Static option completion for base64.exe and base64.

Set-StrictMode -Version 2.0

function Get-Base64CompletionOptions {
    $cache = Get-Variable -Name 'Base64CompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-d', '--decode', '-i', '--ignore-garbage', '-w', '--wrap', '--help', '--version')
    $commandCandidates = @('base64.exe', 'base64')
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

        # Seeded with the static list so a lossy parse can only add spellings, never lose them.
        $options = [System.Collections.Generic.HashSet[string]]::new([string[]]$fallbackOptions, [System.StringComparer]::Ordinal)
        $descriptions = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
        foreach ($line in ([regex]::Split($helpOutput, '\r?\n'))) {
            # ']' and ')' close the lookahead so uutils' 'decode data [alias: -D]' contributes -D.
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
            Set-Variable -Name 'Base64CompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'Base64CompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'Base64CompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'Base64CompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'Base64CompletionOptions' -Scope Script).Value
}

function New-Base64CompletionResult {
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

function ConvertFrom-Base64TypedWord {
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

function ConvertTo-Base64QuotedValue {
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

function Get-Base64CurrentToken {
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

function Get-Base64PathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-Base64TypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # The directory part is kept exactly as typed ('.\', '../', 'C:\x/'), so no typed text is lost.
    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    $typedDirectory = $cleanInput.Substring(0, $separatorIndex + 1)
    $leaf = $cleanInput.Substring($separatorIndex + 1)
    $parent = if ($typedDirectory) { $typedDirectory } else { '.' }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = $typedDirectory + $item.Name
        # A bare word led by a dash parses as a parameter; lead it with '.\' as PowerShell does.
        if (-not $typedDirectory -and $pathText -match '^[-\u2013-\u2015]') {
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-Base64QuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-Base64CompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-Base64CompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-Base64OptionValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord,
        [int]$CursorPosition
    )

    $option = $null
    $prefix = $CurrentWord
    $attached = ''
    if ($CurrentWord -match '^(?<option>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = $Matches['option']
        $prefix = $Matches['value']
        $attached = $option + '='
    } elseif (-not $CurrentWord.StartsWith('-')) {
        # The option owning the slot is the word that ends before the cursor, not the line's
        # last word, so a value slot followed by a later operand still completes its values.
        $before = @($commandAst.CommandElements | Where-Object { $_.Extent.EndOffset -lt $CursorPosition } | ForEach-Object { $_.Extent.Text })
        if ($before.Count -gt 1) {
            $option = $before[-1]
        }
    }

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['-w'] = @(
        @{ Text = '0'; Tip = 'Disable wrapping.' }
        @{ Text = '64'; Tip = '64 columns.' }
        @{ Text = '76'; Tip = '76 columns, the default.' }
    )
    $table['--wrap'] = @(
        @{ Text = '0'; Tip = 'Disable wrapping.' }
        @{ Text = '64'; Tip = '64 columns.' }
        @{ Text = '76'; Tip = '76 columns, the default.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-Base64PathCompletions -InputPath $prefix) {
                New-Base64CompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-Base64CompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Complete-Base64ShortFlagCluster {
    param([string]$CurrentWord)

    # Both installed builds merge short flags ('-di'); extend a cluster of known short flags with
    # each remaining one. A cluster already holding the value-taking -w is complete.
    if ($CurrentWord -notmatch '^-[A-Za-z]{2,}$') {
        return @()
    }

    $shortFlags = @(Get-Base64CompletionOptions | Where-Object { $_ -cmatch '^-[A-Za-z]$' })
    $usedLetters = @($CurrentWord.Substring(1).ToCharArray() | ForEach-Object { [string]$_ })
    foreach ($letter in $usedLetters) {
        if (('-' + $letter) -cnotin $shortFlags) {
            return @()
        }
    }

    if ('w' -cin $usedLetters) {
        return @()
    }

    @(
        foreach ($flag in $shortFlags) {
            $letter = $flag.Substring(1)
            if ($letter -cin $usedLetters) {
                continue
            }

            $clustered = $CurrentWord + $letter
            New-Base64CompletionResult -CompletionText $clustered -ListItemText $clustered -ResultType 'ParameterName' -ToolTip ('{0}: {1}' -f $flag, (Get-Base64OptionDescription -Option $flag))
        }
    )
}

function Get-Base64OptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'Base64CompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for base64.'
}

function Complete-Base64 {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-Base64CurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-Base64OptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord -CursorPosition $cursorPosition)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    # 'With no FILE, or when FILE is -, read standard input': the documented '-' operand leads
    # the empty slot and the bare '-' word, ahead of the paths and options.
    $stdinResult = New-Base64CompletionResult -CompletionText '-' -ListItemText '-' -ResultType 'ParameterValue' -ToolTip 'Read standard input instead of a FILE.'

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @(
            $stdinResult
            Get-Base64PathCompletions -InputPath ''
        )
    }

    if ($currentWord.StartsWith('-')) {
        $optionMatches = @(
            if ($currentWord -ceq '-') {
                $stdinResult
            }
            foreach ($option in Get-Base64CompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-Base64CompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-Base64OptionDescription -Option $option)
                }
            }
        )
        if ($optionMatches.Count -gt 0) {
            return $optionMatches
        }

        return Complete-Base64ShortFlagCluster -CurrentWord $currentWord
    }

    Get-Base64PathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'base64', 'base64.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Base64 -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
