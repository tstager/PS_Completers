# fold tab completion for PowerShell
# Static option completion for fold.exe and fold.

Set-StrictMode -Version 2.0

function Get-FoldCompletionOptions {
    $cache = Get-Variable -Name 'FoldCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--bytes', '-s', '--spaces', '-w', '--width', '-h', '--help', '-V', '--version')
    $commandCandidates = @('fold.exe', 'fold')
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
            Set-Variable -Name 'FoldCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'FoldCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'FoldCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'FoldCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'FoldCompletionOptions' -Scope Script).Value
}

function New-FoldCompletionResult {
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

function Remove-FoldOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function Get-FoldTypedQuote {
    # The quote the user opened the word with, as its ASCII form ('' when bare). PowerShell
    # reads U+2018-U+201B as single quotes and U+201C-U+201E as double quotes.
    param([string]$Value)

    if ($Value -match '^[''\u2018-\u201B]') {
        return "'"
    }

    if ($Value -match '^["\u201C-\u201E]') {
        return '"'
    }

    ''
}

function ConvertFrom-FoldTypedWord {
    # The value of a typed word without its quotes and that quote style's escapes.
    param([string]$Value)

    $quote = Get-FoldTypedQuote -Value $Value
    if (-not $quote) {
        return $Value
    }

    # The parser undoes doubled quotes (typographic ones included) and backtick escapes; a word
    # still open at the cursor is closed first.
    foreach ($candidate in @($Value, ($Value + $quote))) {
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($candidate, [ref]$null, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            continue
        }

        $constant = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
        if ($null -ne $constant -and $constant.Extent.Text -eq $candidate) {
            return $constant.Value
        }
    }

    Remove-FoldOuterQuotes -Value $Value
}

function ConvertTo-FoldQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false,
        [string]$QuoteChar = "'"
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    # Whitespace, argument-mode metacharacters, the typographic quotes and a leading dash split or change a bare word.
    if (-not $AlwaysQuote -and $Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]|^[-\u2013-\u2015]') {
        return $Value
    }

    if ($QuoteChar -eq '"') {
        return '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
    }

    "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
}

function Get-FoldCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    foreach ($element in $CommandAst.CommandElements) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    ''
}

function Get-FoldPathCompletions {
    param([string]$InputPath)

    $quoteChar = Get-FoldTypedQuote -Value $InputPath
    $cleanInput = ConvertFrom-FoldTypedWord -Value $InputPath
    $alwaysQuote = [bool]$quoteChar

    # The directory part is kept exactly as typed (a leading .\ or ./ included), so no typed text is lost.
    $typedDirectory = ''
    $leaf = $cleanInput
    if ($cleanInput -match '^(?<dir>.*[\\/]|[A-Za-z]:)(?<leaf>[^\\/]*)$') {
        $typedDirectory = $Matches['dir']
        $leaf = $Matches['leaf']
    }

    $parent = if ($typedDirectory) { $typedDirectory } else { '.' }
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = $typedDirectory + $item.Name
        # A bare word starting with a dash is read as a parameter; PowerShell's own completion adds .\ here.
        if (-not $typedDirectory -and $pathText -match '^[-\u2013-\u2015]') {
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-FoldQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-FoldCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-FoldCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-FoldOptionValueCompletions {
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
    $table['-w'] = @(
        @{ Text = '72'; Tip = '72 columns.' }
        @{ Text = '80'; Tip = '80 columns, the default.' }
        @{ Text = '<width>'; Tip = 'Column width.' }
    )
    $table['--width'] = @(
        @{ Text = '72'; Tip = '72 columns.' }
        @{ Text = '80'; Tip = '80 columns, the default.' }
        @{ Text = '<width>'; Tip = 'Column width.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-FoldPathCompletions -InputPath $prefix) {
                New-FoldCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-FoldCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-FoldOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'FoldCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for fold.'
}

function Complete-Fold {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete closes an open quote and spans past the cursor.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-FoldCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-FoldOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return Get-FoldPathCompletions -InputPath ''
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-FoldCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-FoldCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-FoldOptionDescription -Option $option)
                }
            }
        )
    }

    Get-FoldPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'fold', 'fold.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Fold -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
