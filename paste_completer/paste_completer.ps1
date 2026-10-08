# paste tab completion for PowerShell
# Static option completion for paste.exe and paste.

Set-StrictMode -Version 2.0

function Get-PasteCompletionOptions {
    $cache = Get-Variable -Name 'PasteCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-d', '--delimiters', '-s', '--serial', '-z', '--zero-terminated', '--help', '--version')
    $commandCandidates = @('paste.exe', 'paste')
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
            Set-Variable -Name 'PasteCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'PasteCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'PasteCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'PasteCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'PasteCompletionOptions' -Scope Script).Value
}

function New-PasteCompletionResult {
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

function Get-PasteTypedQuote {
    # The quote style the user opened the word with: ' or " ('' when bare). PowerShell reads the
    # typographic quotes U+2018-U+201B as single quotes and U+201C-U+201E as double quotes.
    param([string]$Value)

    if ($Value -match '^[''\u2018-\u201B]') {
        return "'"
    }

    if ($Value -match '^["\u201C-\u201E]') {
        return '"'
    }

    ''
}

function ConvertFrom-PasteTypedWord {
    # The value of a typed word without its quotes and that quote style's escapes.
    param([string]$Value)

    $quote = Get-PasteTypedQuote -Value $Value
    if (-not $quote) {
        return $Value
    }

    $clean = $Value.Substring(1)
    if ($quote -eq "'") {
        # An odd run of quote characters at the end holds the closing quote.
        if ($clean -match '[''\u2018-\u201B]+$' -and $Matches[0].Length % 2 -eq 1) {
            $clean = $clean.Substring(0, $clean.Length - 1)
        }

        return $clean -replace '([''\u2018-\u201B])[''\u2018-\u201B]', '$1'
    }

    if ($clean -match '(?<!`)(?:``)*["\u201C-\u201E]$') {
        $clean = $clean.Substring(0, $clean.Length - 1)
    }

    $clean -replace '`(.)', '$1'
}

function Get-PasteCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The parser keeps an unterminated quote as one element running to the cursor, so a quoted word with a space stays whole.
    $word = ''
    foreach ($element in $CommandAst.CommandElements) {
        if ($element.Extent.StartOffset -le $CursorPosition -and $CursorPosition -le $element.Extent.EndOffset) {
            $word = $element.Extent.Text.Substring(0, $CursorPosition - $element.Extent.StartOffset)
        }
    }

    $word
}

function Get-PastePathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-PasteTypedWord -Value $InputPath
    $typedQuote = Get-PasteTypedQuote -Value $InputPath

    # The directory part is kept exactly as typed (a typed .\ or ./ included); only the leaf is completed.
    $typedDirectory = ''
    $leaf = ''
    if (-not [string]::IsNullOrWhiteSpace($cleanInput)) {
        $separatorIndex = $cleanInput.LastIndexOfAny([char[]]'\/:')
        $typedDirectory = $cleanInput.Substring(0, $separatorIndex + 1)
        $leaf = $cleanInput.Substring($separatorIndex + 1)
    }

    $parent = if ($typedDirectory) { $typedDirectory } else { '.' }
    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = $typedDirectory + $item.Name
        if (-not $typedDirectory -and $item.Name -match '^[-\u2013-\u2015]') {
            # A bare word starting with a dash parses as a parameter, so name it relative to the current directory.
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-PasteValueArgument -Value $pathText -Quote $typedQuote
        if ($item.PSIsContainer) {
            New-PasteCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-PasteCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function ConvertTo-PasteValueArgument {
    param(
        [string]$Value,
        [string]$Quote
    )

    # Renders a value as one PowerShell argument: bare when safe and no quote was typed, otherwise
    # in the typed quote style (single by default), with every quote character of that style
    # (typographic ones included) escaped.
    if ($Quote -eq '"') {
        return '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
    }

    if ($Quote -eq "'" -or $Value -match '[\s{}();,|&<>''"`$@#\u2018-\u201E]' -or $Value -match '^[-\u2013-\u2015]') {
        return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
    }

    $Value
}

function Get-PasteOptionValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord,
        [string]$WordToComplete
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
    $delimiters = @(
        @{ Text = '\t'; Tip = 'Tab delimiter.' }
        @{ Text = '\n'; Tip = 'Newline delimiter.' }
        @{ Text = '\0'; Tip = 'Empty delimiter (no separator).' }
        @{ Text = '\\'; Tip = 'Backslash delimiter.' }
        @{ Text = ','; Tip = 'Comma delimiter.' }
        @{ Text = '|'; Tip = 'Pipe delimiter.' }
        @{ Text = ';'; Tip = 'Semicolon delimiter.' }
        @{ Text = ':'; Tip = 'Colon delimiter.' }
        @{ Text = '<list>'; Tip = 'Delimiter characters, reused in turn.' }
    )
    $table['-d'] = $delimiters
    $table['--delimiters'] = $delimiters
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return
    }

    # A known value slot answers even with no match, so the word never falls through to options or paths.
    # An unquoted ',' after '=' is split off the word by the engine, which would insert any candidate after it.
    if ($attached -and -not $WordToComplete.StartsWith($attached, [System.StringComparison]::Ordinal)) {
        return , @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return , @(
            foreach ($result in Get-PastePathCompletions -InputPath $prefix) {
                New-PasteCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $quote = Get-PasteTypedQuote -Value $prefix
    $prefix = ConvertFrom-PasteTypedWord -Value $prefix

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    , @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                $argument = if ($entry.Text -eq '<list>') { $entry.Text } else { ConvertTo-PasteValueArgument -Value $entry.Text -Quote $quote }
                New-PasteCompletionResult -CompletionText ($attached + $argument) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-PasteOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'PasteCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for paste.'
}

function Complete-Paste {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-PasteCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition
    }

    $optionValues = Get-PasteOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord -WordToComplete $wordToComplete
    if ($null -ne $optionValues) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-PasteCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-PasteCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-PasteOptionDescription -Option $option)
                }
            }
        )
    }

    Get-PastePathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'paste', 'paste.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Paste -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
