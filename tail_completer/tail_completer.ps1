# tail tab completion for PowerShell
# Static option completion for tail.exe and tail.

Set-StrictMode -Version 2.0

function Get-TailCompletionOptions {
    $cache = Get-Variable -Name 'TailCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-c', '--bytes', '-f', '--follow', '-n', '--lines', '--pid', '-q', '--quiet', '--silent', '-s', '--sleep-interval', '--max-unchanged-stats', '--use-polling', '-v', '--verbose', '-z', '--zero-terminated', '--retry', '-F', '--debug', '-h', '--help', '-V', '--version')
    $commandCandidates = @('tail.exe', 'tail')
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
            Set-Variable -Name 'TailCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'TailCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'TailCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'TailCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'TailCompletionOptions' -Scope Script).Value
}


function New-TailCompletionResult {
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

function ConvertFrom-TailTypedWord {
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

function ConvertTo-TailQuotedValue {
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
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]|^[-\u2013-\u2015]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-TailCurrentToken {
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

function Get-TailPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-TailTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    if ([string]::IsNullOrEmpty($cleanInput)) {
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

    # Keep the directory part exactly as typed ('.\', './', '..\', 'C:\x\'), so only the leaf is completed.
    $typedPrefix = if ([string]::IsNullOrEmpty($cleanInput)) {
        ''
    } elseif ($cleanInput.EndsWith($leaf, [System.StringComparison]::Ordinal)) {
        $cleanInput.Substring(0, $cleanInput.Length - $leaf.Length)
    } else {
        $null
    }

    $items = @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = if ($typedPrefix -eq '' -and $item.Name -match '^[-\u2013-\u2015]') {
            # PowerShell reads a word starting with a dash as a parameter name; '.\' keeps it a path.
            '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        } elseif ($null -ne $typedPrefix) {
            $typedPrefix + $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-TailQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-TailCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-TailCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-TailOptionValueCompletions {
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
        # the word before the cursor, not the last word on the line, so mid-line edits keep their value slot
        $previous = @($commandAst.CommandElements | Select-Object -Skip 1 | Where-Object { $_.Extent.EndOffset -lt $CursorPosition })
        if ($previous.Count -gt 0) {
            $option = $previous[-1].Extent.Text
        }
    }

    # --follow's value is optional and taken only attached (--follow=name, -f=name); a separate word is a FILE operand
    if ([string]::IsNullOrEmpty($attached) -and ($option -ceq '-f' -or $option -ceq '--follow')) {
        return @()
    }

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['-c'] = @(
        @{ Text = '<num>'; Tip = 'Last NUM units.' }
        @{ Text = '+<num>'; Tip = 'Starting at unit NUM.' }
    )
    $table['--bytes'] = @(
        @{ Text = '<num>'; Tip = 'Last NUM units.' }
        @{ Text = '+<num>'; Tip = 'Starting at unit NUM.' }
    )
    $table['-n'] = @(
        @{ Text = '<num>'; Tip = 'Last NUM units.' }
        @{ Text = '+<num>'; Tip = 'Starting at unit NUM.' }
    )
    $table['--lines'] = @(
        @{ Text = '<num>'; Tip = 'Last NUM units.' }
        @{ Text = '+<num>'; Tip = 'Starting at unit NUM.' }
    )
    $table['-f'] = @(
        @{ Text = 'name'; Tip = 'Follow by file name.' }
        @{ Text = 'descriptor'; Tip = 'Follow by file descriptor.' }
    )
    $table['--follow'] = @(
        @{ Text = 'name'; Tip = 'Follow by file name.' }
        @{ Text = 'descriptor'; Tip = 'Follow by file descriptor.' }
    )
    $table['--max-unchanged-stats'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--pid'] = { foreach ($process in (Get-Process | Sort-Object -Property Id)) { @{ Text = [string]$process.Id; Tip = $process.ProcessName } } }
    $table['-s'] = @(
        @{ Text = '1'; Tip = '1 second.' }
        @{ Text = '5'; Tip = '5 seconds.' }
        @{ Text = '<seconds>'; Tip = 'Sleep interval.' }
    )
    $table['--sleep-interval'] = @(
        @{ Text = '1'; Tip = '1 second.' }
        @{ Text = '5'; Tip = '5 seconds.' }
        @{ Text = '<seconds>'; Tip = 'Sleep interval.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-TailPathCompletions -InputPath $prefix) {
                New-TailCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-TailCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-TailOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'TailCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for tail.'
}

function Complete-Tail {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-TailCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-TailOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord -CursorPosition $cursorPosition)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-TailCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-TailCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-TailOptionDescription -Option $option)
                }
            }
        )
    }

    Get-TailPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'tail', 'tail.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Tail -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
