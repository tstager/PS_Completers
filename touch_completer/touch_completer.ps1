# touch tab completion for PowerShell
# Static option completion for touch.exe and touch.

Set-StrictMode -Version 2.0

function Get-TouchCompletionOptions {
    $cache = Get-Variable -Name 'TouchCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-a', '-t', '-d', '--date', '-f', '-m', '-c', '--no-create', '-h', '--no-dereference', '-r', '--reference', '--time', '-V', '--version', '--help')
    $commandCandidates = @('touch.exe', 'touch')
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
            Set-Variable -Name 'TouchCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'TouchCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'TouchCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'TouchCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'TouchCompletionOptions' -Scope Script).Value
}


function New-TouchCompletionResult {
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

function Get-TouchTypedQuote {
    # The quote character the user opened the word with, typographic ones included ('' when bare).
    param([string]$Value)

    if ($Value -match '^[''"\u2018-\u201E]') {
        return $Value.Substring(0, 1)
    }

    ''
}

function Remove-TouchOuterQuotes {
    # The argument value of a typed word. The parser drops the quotes and undoes that quote
    # style's escapes (every doubled single-quote character, backticks); an open quote is closed first.
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    $quote = Get-TouchTypedQuote -Value $Value
    foreach ($text in @($Value, ($Value + $quote))) {
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput('touch ' + $text, [ref]$null, [ref]$parseErrors)
        $command = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
        if (@($parseErrors).Count -gt 0 -or $null -eq $command -or $command.CommandElements.Count -ne 2) {
            continue
        }

        $element = $command.CommandElements[1]
        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $element -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            return $element.Value
        }

        return $element.Extent.Text
    }

    $Value.Substring($quote.Length)
}

function ConvertTo-TouchQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the typed quote character (single by default). Whitespace and argument-mode
    # metacharacters (including the typographic quotes) end or split a bare word, a
    # leading '@' or '#' would start a splat or a comment, and a leading dash a parameter.
    param(
        [string]$Value,
        [string]$Quote
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $Quote) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$\u2018-\u201E]' -and $Value -notmatch '^[@#\-\u2013-\u2015]') {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -match '^[''\u2018-\u201B]$') {
        return $Quote + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $Quote
    }

    $Quote + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $Quote
}

function Get-TouchCurrentToken {
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

function Get-TouchPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-TouchOuterQuotes -Value $InputPath
    $quote = Get-TouchTypedQuote -Value $InputPath

    # The typed directory part (separators and any .\ prefix exactly as typed) is kept verbatim.
    $directory = ''
    if ($cleanInput -match '^(?<dir>.*[\\/:])') {
        $directory = $Matches['dir']
    }

    $parent = if ($directory) { $directory } else { '.' }
    $leaf = $cleanInput.Substring($directory.Length)

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = $directory + $item.Name
        if (-not $directory -and $pathText -match '^[-\u2013-\u2015]') {
            # A bare dash-leading word parses as a parameter; anchor it to the current directory.
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-TouchQuotedValue -Value $pathText -Quote $quote
        if ($item.PSIsContainer) {
            New-TouchCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-TouchCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-TouchOptionValueCompletions {
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
    $table['-d'] = @(
        @{ Text = 'now'; Tip = 'Current time.' }
        @{ Text = 'today'; Tip = 'Start of today.' }
        @{ Text = 'yesterday'; Tip = 'Same time yesterday.' }
        @{ Text = 'tomorrow'; Tip = 'Same time tomorrow.' }
    )
    $table['--date'] = @(
        @{ Text = 'now'; Tip = 'Current time.' }
        @{ Text = 'today'; Tip = 'Start of today.' }
        @{ Text = 'yesterday'; Tip = 'Same time yesterday.' }
        @{ Text = 'tomorrow'; Tip = 'Same time tomorrow.' }
    )
    $table['-r'] = 'path'
    $table['--reference'] = 'path'
    $table['-t'] = @(
        @{ Text = '<stamp>'; Tip = '[[CC]YY]MMDDhhmm[.ss] timestamp.' }
    )
    $table['--time'] = @(
        @{ Text = 'access'; Tip = 'Change the access time.' }
        @{ Text = 'atime'; Tip = 'Change the access time.' }
        @{ Text = 'use'; Tip = 'Change the access time.' }
        @{ Text = 'modify'; Tip = 'Change the modification time.' }
        @{ Text = 'mtime'; Tip = 'Change the modification time.' }
    )
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-TouchPathCompletions -InputPath $prefix) {
                New-TouchCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-TouchCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-TouchOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'TouchCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for touch.'
}

function Complete-Touch {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete closes an open quote and spans past the cursor.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-TouchCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-TouchOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-TouchCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-TouchCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-TouchOptionDescription -Option $option)
                }
            }
        )
    }

    Get-TouchPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'touch', 'touch.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Touch -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
