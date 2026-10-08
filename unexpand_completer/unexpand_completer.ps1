# unexpand tab completion for PowerShell
# Static option completion for unexpand.exe and unexpand.

Set-StrictMode -Version 2.0

function Get-UnexpandCompletionCache {
    $cache = Get-Variable -Name 'UnexpandCompletionCache' -Scope Script -ErrorAction Ignore
    $path = [string]$env:PATH
    $hasCache = $null -ne $cache -and $null -ne $cache.Value
    $resolve = -not ($hasCache -and $cache.Value.Path -ceq $path)
    if (-not $resolve) {
        $sources = @($cache.Value.Sources)
        $resolve = $sources.Count -gt 0 -and -not [System.IO.File]::Exists($sources[0])
    }
    if ($resolve) {
        $sources = @(foreach ($candidate in @('unexpand.exe', 'unexpand')) {
            $command = Get-Command -Name $candidate -CommandType Application -ErrorAction Ignore | Select-Object -First 1
            if ($null -ne $command) {
                $command.Source
                break
            }
        })
    }

    $key = ''
    if ($sources.Count -gt 0) {
        $key = $sources[0] + '|' + [System.IO.File]::GetLastWriteTimeUtc($sources[0]).Ticks
    }

    if ($hasCache -and $cache.Value.Key -ceq $key) {
        $cache.Value.Path = $path
        $cache.Value.Sources = $sources
        return $cache.Value
    }

    $fallbackOptions = @('-a', '--all', '-i', '--initial', '-t', '--tabs', '--help', '--version')
    foreach ($source in $sources) {
        try {
            $helpOutput = $null | & $source --help 2>&1 | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String
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
            $entry = @{ Path = $path; Sources = $sources; Key = $key; Options = @($options | Sort-Object); Descriptions = $descriptions }
            Set-Variable -Name 'UnexpandCompletionCache' -Value $entry -Scope Script
            return $entry
        }
    }

    $entry = @{ Path = $path; Sources = $sources; Key = $key; Options = $fallbackOptions; Descriptions = @{} }
    Set-Variable -Name 'UnexpandCompletionCache' -Value $entry -Scope Script
    $entry
}

function New-UnexpandCompletionResult {
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

function ConvertFrom-UnexpandTypedWord {
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

function ConvertTo-UnexpandQuotedValue {
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

function Get-UnexpandCurrentToken {
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

function Get-UnexpandPathCompletions {
    param(
        [string]$InputPath,
        [string]$Attached = ''
    )

    # An attached '--opt=' prefix is quoted together with the path so the word stays one argument.
    $cleanInput = ConvertFrom-UnexpandTypedWord -Value $InputPath
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

    # The directory part is kept exactly as typed (.\, ./, ..\, C:\...), so no typed text is lost.
    $typedDirectory = if ($cleanInput -match '^(?<dir>.*[\\/:])') { $Matches['dir'] } else { '' }

    foreach ($item in $items) {
        $pathText = $typedDirectory + $item.Name

        # A bare word starting with a dash is parsed as a parameter; anchor it to the current directory.
        if (-not $typedDirectory -and -not $Attached -and $pathText -match '^[-\u2013-\u2015]') {
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-UnexpandQuotedValue -Value ($Attached + $pathText) -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-UnexpandCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-UnexpandCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-UnexpandOptionValueCompletions {
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
    $table['-t'] = @(
        @{ Text = '4'; Tip = 'Tabs every 4 columns.' }
        @{ Text = '8'; Tip = 'Tabs every 8 columns, the default.' }
        @{ Text = '<list>'; Tip = 'Comma-separated tab positions.' }
    )
    $table['--tabs'] = @(
        @{ Text = '4'; Tip = 'Tabs every 4 columns.' }
        @{ Text = '8'; Tip = 'Tabs every 8 columns, the default.' }
        @{ Text = '<list>'; Tip = 'Comma-separated tab positions.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            Get-UnexpandPathCompletions -InputPath $prefix -Attached $attached
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-UnexpandCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-UnexpandOptionDescription {
    param(
        [string]$Option,
        [hashtable]$Descriptions
    )

    if ($Descriptions.ContainsKey($Option)) {
        return $Descriptions[$Option]
    }

    'Option for unexpand.'
}

function Complete-Unexpand {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-UnexpandCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-UnexpandOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        $optionCache = Get-UnexpandCompletionCache
        return @(
            foreach ($option in $optionCache.Options) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-UnexpandCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-UnexpandOptionDescription -Option $option -Descriptions $optionCache.Descriptions)
                }
            }
        )
    }

    Get-UnexpandPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'unexpand', 'unexpand.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Unexpand -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
