# split tab completion for PowerShell
# Static option completion for split.exe and split.

Set-StrictMode -Version 2.0

function Get-SplitCompletionOptions {
    $cache = Get-Variable -Name 'SplitCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--bytes', '-C', '--line-bytes', '-l', '--lines', '-n', '--number', '--additional-suffix', '--filter', '-e', '--elide-empty-files', '-d', '--numeric-suffixes', '-x', '--hex-suffixes', '-a', '--suffix-length', '--verbose', '-t', '--separator', '-h', '--help', '-V', '--version', '-s')
    $commandCandidates = @('split.exe', 'split')
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
            Set-Variable -Name 'SplitCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'SplitCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'SplitCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'SplitCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'SplitCompletionOptions' -Scope Script).Value
}


function New-SplitCompletionResult {
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

function Get-SplitTypedQuote {
    # The quote family the user opened the word with: ' (also U+2018-U+201B), " (also U+201C-U+201E), or '' when bare.
    param([string]$Value)

    if ($Value -match '^[''\u2018-\u201B]') {
        return "'"
    }

    if ($Value -match '^["\u201C-\u201E]') {
        return '"'
    }

    ''
}

function ConvertFrom-SplitTypedWord {
    # The value of a typed word as the PowerShell parser reads it; an unterminated quote still yields its text.
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    $ast = [System.Management.Automation.Language.Parser]::ParseInput('x ' + $Value, [ref]$null, [ref]$null)
    $command = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    if ($null -ne $command -and $command.CommandElements.Count -eq 2 -and $command.CommandElements[1] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $command.CommandElements[1].Value
    }

    $Value
}

function Get-SplitClosedWord {
    # The typed word as one finished argument: kept verbatim, with an unterminated quote closed in its own family.
    param([string]$Value)

    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput('x ' + $Value, [ref]$null, [ref]$errors)
    if (-not @($errors | Where-Object { $_.ErrorId -eq 'TerminatorExpectedAtEndOfString' })) {
        return $Value
    }

    if ([regex]::Match($Value, '[''"\u2018-\u201E]').Value -match '[''\u2018-\u201B]') {
        return $Value + "'"
    }

    $Value + '"'
}

function ConvertTo-SplitQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the typed quote style (single by default).
    param(
        [string]$Value,
        [string]$Quote
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $Quote) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -eq "'") {
        return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
    }

    '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
}

function Get-SplitCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$Fallback
    )

    # The parser keeps an unterminated quoted word as one element running past the cursor, so
    # the element under the cursor is the whole typed word even when it holds spaces.
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $element.Extent.EndOffset) {
            return $element.Extent.Text.Substring(0, $CursorPosition - $element.Extent.StartOffset)
        }
    }

    # Between words, where PowerShell's own word is empty too.
    $Fallback
}

function Get-SplitPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-SplitTypedWord -Value $InputPath
    $quote = Get-SplitTypedQuote -Value $InputPath

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

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = if ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $item.Name
        } elseif ([System.IO.Path]::IsPathRooted($cleanInput)) {
            Join-Path -Path $parent -ChildPath $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-SplitQuotedValue -Value $pathText -Quote $quote
        if ($item.PSIsContainer) {
            New-SplitCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-SplitCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-SplitOptionValueCompletions {
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
        $elements = @($commandAst.CommandElements | Where-Object { $_.Extent.StartOffset -lt $CursorPosition } | ForEach-Object { $_.Extent.Text })
        if ([string]::IsNullOrEmpty($CurrentWord)) {
            if ($elements.Count -gt 1) {
                $option = $elements[-1]
            }
        } elseif ($elements.Count -gt 2 -and $elements[-1].StartsWith($CurrentWord, [System.StringComparison]::Ordinal)) {
            $option = $elements[-2]
        }
    }

    if ([string]::IsNullOrEmpty($option)) {
        return @()
    }

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['-a'] = @(
        @{ Text = '<n>'; Tip = 'Suffix length.' }
    )
    $table['--suffix-length'] = @(
        @{ Text = '<n>'; Tip = 'Suffix length.' }
    )
    $table['--additional-suffix'] = @(
        @{ Text = '<suffix>'; Tip = 'Extra suffix for file names.' }
    )
    $table['-b'] = @(
        @{ Text = '1K'; Tip = '1K per output file.' }
        @{ Text = '1M'; Tip = '1M per output file.' }
        @{ Text = '10M'; Tip = '10M per output file.' }
        @{ Text = '100M'; Tip = '100M per output file.' }
        @{ Text = '1G'; Tip = '1G per output file.' }
    )
    $table['--bytes'] = @(
        @{ Text = '1K'; Tip = '1K per output file.' }
        @{ Text = '1M'; Tip = '1M per output file.' }
        @{ Text = '10M'; Tip = '10M per output file.' }
        @{ Text = '100M'; Tip = '100M per output file.' }
        @{ Text = '1G'; Tip = '1G per output file.' }
    )
    $table['-C'] = @(
        @{ Text = '1K'; Tip = '1K per output file.' }
        @{ Text = '1M'; Tip = '1M per output file.' }
        @{ Text = '10M'; Tip = '10M per output file.' }
        @{ Text = '100M'; Tip = '100M per output file.' }
        @{ Text = '1G'; Tip = '1G per output file.' }
    )
    $table['--line-bytes'] = @(
        @{ Text = '1K'; Tip = '1K per output file.' }
        @{ Text = '1M'; Tip = '1M per output file.' }
        @{ Text = '10M'; Tip = '10M per output file.' }
        @{ Text = '100M'; Tip = '100M per output file.' }
        @{ Text = '1G'; Tip = '1G per output file.' }
    )
    $table['--numeric-suffixes'] = @(
        @{ Text = '<from>'; Tip = 'Starting suffix value.' }
    )
    $table['--hex-suffixes'] = @(
        @{ Text = '<from>'; Tip = 'Starting suffix value.' }
    )
    $table['--filter'] = @(
        @{ Text = '<command>'; Tip = 'Shell command receiving each chunk.' }
    )
    $table['-l'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--lines'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-n'] = @(
        @{ Text = '<chunks>'; Tip = 'Number of chunks.' }
        @{ Text = 'l/<n>'; Tip = 'N chunks without splitting lines.' }
        @{ Text = 'r/<n>'; Tip = 'Round-robin distribution into N chunks.' }
    )
    $table['--number'] = @(
        @{ Text = '<chunks>'; Tip = 'Number of chunks.' }
        @{ Text = 'l/<n>'; Tip = 'N chunks without splitting lines.' }
        @{ Text = 'r/<n>'; Tip = 'Round-robin distribution into N chunks.' }
    )
    $table['-t'] = @(
        @{ Text = '<sep>'; Tip = 'Record separator.' }
    )
    $table['--separator'] = @(
        @{ Text = '<sep>'; Tip = 'Record separator.' }
    )
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    # --numeric-suffixes and --hex-suffixes take FROM only in the attached form; a separate word is the INPUT operand.
    if ($attached -eq '' -and $option -cin @('--numeric-suffixes', '--hex-suffixes')) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-SplitPathCompletions -InputPath $prefix) {
                New-SplitCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    # PowerShell replaces the whole word under the cursor, so the typed text after the cursor
    # belongs to the value too: candidates must start with all of it, and the echo keeps it.
    foreach ($element in $commandAst.CommandElements) {
        if ($element.Extent.StartOffset -lt $CursorPosition -and $CursorPosition -lt $element.Extent.EndOffset) {
            $prefix += $element.Extent.Text.Substring($CursorPosition - $element.Extent.StartOffset)
        }
    }

    $quote = Get-SplitTypedQuote -Value $prefix
    $value = ConvertFrom-SplitTypedWord -Value $prefix
    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    $results = @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($value, [System.StringComparison]::Ordinal)) {
                $text = if ($quote) { ConvertTo-SplitQuotedValue -Value $entry.Text -Quote $quote } else { $entry.Text }
                New-SplitCompletionResult -CompletionText ($attached + $text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
    if ($results.Count -gt 0) {
        return $results
    }

    # A free-form value keeps what the user typed: an empty result would hand the slot to
    # PowerShell's filename fallback, which lists paths for a SIZE or separator.
    @(New-SplitCompletionResult -CompletionText ($attached + (Get-SplitClosedWord -Value $prefix)) -ListItemText $value -ResultType 'ParameterValue' -ToolTip "$option value")
}

function Get-SplitOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'SplitCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for split.'
}

function Complete-Split {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-SplitCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition -Fallback $wordToComplete

    $optionValues = @(Get-SplitOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord -CursorPosition $cursorPosition)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-SplitCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-SplitCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-SplitOptionDescription -Option $option)
                }
            }
        )
    }

    Get-SplitPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'split', 'split.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Split -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
