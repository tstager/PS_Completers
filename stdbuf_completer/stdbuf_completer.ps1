# stdbuf tab completion for PowerShell
# Static option completion for stdbuf.exe and stdbuf.

Set-StrictMode -Version 2.0

function Get-StdbufCompletionOptions {
    $cache = Get-Variable -Name 'StdbufCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-i', '--input', '-o', '--output', '-e', '--error', '--help', '--version')
    $commandCandidates = @('stdbuf.exe', 'stdbuf')
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
            Set-Variable -Name 'StdbufCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'StdbufCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'StdbufCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'StdbufCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'StdbufCompletionOptions' -Scope Script).Value
}

function New-StdbufCompletionResult {
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

function Get-StdbufTypedQuote {
    # The first quote typed in a word (ASCII or typographic), or '' when none was typed.
    param([string]$Value)

    if ($Value -match '[''"\u2018-\u201E]') {
        return $Matches[0]
    }

    ''
}

function ConvertFrom-StdbufTypedWord {
    # The value of a typed word. A word holding a quote (ASCII or typographic) is read by the
    # PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if (-not (Get-StdbufTypedQuote -Value $Value)) {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    $tokens[0].Value
}

function ConvertTo-StdbufQuotedValue {
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

function Get-StdbufCurrentToken {
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

function Get-StdbufPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-StdbufTypedWord -Value $InputPath
    $quoteChar = Get-StdbufTypedQuote -Value $InputPath

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

    foreach ($item in $items) {
        # A typed '.\' or './' stays: without a separator COMMAND would be looked up on PATH.
        $pathText = if ($cleanInput -notmatch '[\\/]') {
            $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-StdbufQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-StdbufCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-StdbufCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-StdbufOptionValueCompletions {
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
        return $null
    }

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['-i'] = @(
        @{ Text = '0'; Tip = 'Unbuffered.' }
        @{ Text = '<size>'; Tip = 'Fully buffered with SIZE bytes, e.g. 4K.' }
    )
    $table['-o'] = @(
        @{ Text = 'L'; Tip = 'Line buffered.' }
        @{ Text = '0'; Tip = 'Unbuffered.' }
        @{ Text = '<size>'; Tip = 'Fully buffered with SIZE bytes, e.g. 4K.' }
    )
    $table['-e'] = @(
        @{ Text = 'L'; Tip = 'Line buffered.' }
        @{ Text = '0'; Tip = 'Unbuffered.' }
        @{ Text = '<size>'; Tip = 'Fully buffered with SIZE bytes, e.g. 4K.' }
    )
    $table['--input'] = @(
        @{ Text = '0'; Tip = 'Unbuffered.' }
        @{ Text = '<size>'; Tip = 'Fully buffered with SIZE bytes, e.g. 4K.' }
    )
    $table['--output'] = @(
        @{ Text = 'L'; Tip = 'Line buffered.' }
        @{ Text = '0'; Tip = 'Unbuffered.' }
        @{ Text = '<size>'; Tip = 'Fully buffered with SIZE bytes, e.g. 4K.' }
    )
    $table['--error'] = @(
        @{ Text = 'L'; Tip = 'Line buffered.' }
        @{ Text = '0'; Tip = 'Unbuffered.' }
        @{ Text = '<size>'; Tip = 'Fully buffered with SIZE bytes, e.g. 4K.' }
    )
    if (-not $table.ContainsKey($option)) {
        return $null
    }

    # A recognised value slot always returns an array (possibly empty), so the caller does not fall through to paths.
    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        # Quote the whole --opt=value word so it stays one constant argument.
        $quoteChar = Get-StdbufTypedQuote -Value $CurrentWord
        return , @(
            foreach ($result in Get-StdbufPathCompletions -InputPath $prefix) {
                New-StdbufCompletionResult -CompletionText (ConvertTo-StdbufQuotedValue -Value ($attached + $result.ListItemText) -QuoteChar $quoteChar) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    , @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-StdbufCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-StdbufOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'StdbufCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for stdbuf.'
}

function Test-StdbufCommandOperandSlot {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    # stdbuf stops parsing options at the first operand (COMMAND); -i/-o/-e and their long forms
    # (abbreviations included) take MODE as the next word unless it is attached.
    $pendingValue = $false
    $endOfOptions = $false
    foreach ($element in @($commandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.EndOffset -ge $cursorPosition) {
            break
        }

        $text = $element.Extent.Text
        if ($pendingValue) {
            $pendingValue = $false
        } elseif ($endOfOptions) {
            return $false
        } elseif ($text -ceq '--') {
            $endOfOptions = $true
        } elseif ($text -cmatch '^-[ioe]$') {
            $pendingValue = $true
        } elseif ($text.StartsWith('--') -and -not $text.Contains('=')) {
            foreach ($longOption in @('--input', '--output', '--error')) {
                if ($longOption.StartsWith($text, [System.StringComparison]::Ordinal)) {
                    $pendingValue = $true
                }
            }
        } elseif (-not $text.StartsWith('-') -or $text -eq '-') {
            return $false
        }
    }

    -not $pendingValue
}

function Get-StdbufCommandNameList {
    $cache = Get-Variable -Name 'StdbufCommandCache' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.Path -eq $env:PATH) {
        return $cache.Value.Names
    }

    # Read the PATH directories directly (Get-Command takes seconds cold). The MSYS exec stdbuf uses
    # finds NAME.exe from a bare NAME; .com/.bat/.cmd need their extension.
    $found = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $enumerationOptions = [System.IO.EnumerationOptions]::new()
    foreach ($directory in ([string]$env:PATH).Split([System.IO.Path]::PathSeparator)) {
        $directory = $directory.Trim().Trim([char]34)
        if ($directory -eq '' -or -not [System.IO.Directory]::Exists($directory)) {
            continue
        }

        foreach ($file in [System.IO.Directory]::GetFiles($directory, '*', $enumerationOptions)) {
            $fileName = [System.IO.Path]::GetFileName($file)
            switch ([System.IO.Path]::GetExtension($fileName).ToLowerInvariant()) {
                '.exe' { [void]$found.Add([System.IO.Path]::GetFileNameWithoutExtension($fileName)) }
                '.com' { [void]$found.Add($fileName) }
                '.bat' { [void]$found.Add($fileName) }
                '.cmd' { [void]$found.Add($fileName) }
            }
        }
    }

    $names = @($found | Sort-Object)
    Set-Variable -Name 'StdbufCommandCache' -Value @{ Path = $env:PATH; Names = $names } -Scope Script
    $names
}

function Get-StdbufCommandOperandCompletion {
    param([string]$CurrentWord)

    $quote = Get-StdbufTypedQuote -Value $CurrentWord
    $prefix = ConvertFrom-StdbufTypedWord -Value $CurrentWord
    if ($prefix -match '[\\/:]|^[.~]') {
        return @()
    }

    @(
        foreach ($name in Get-StdbufCommandNameList) {
            if (-not $name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            New-StdbufCompletionResult -CompletionText (ConvertTo-StdbufQuotedValue -Value $name -QuoteChar $quote) -ListItemText $name -ResultType 'Command' -ToolTip 'Command to run with modified buffering.'
        }
    )
}

function Complete-Stdbuf {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-StdbufCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = Get-StdbufOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord
    if ($null -ne $optionValues) {
        return $optionValues
    }

    # An empty COMMAND slot returns nothing so the engine lists the current directory ('.\name'),
    # which keeps local scripts reachable; a bare name is searched on PATH only, so once a prefix
    # that is not path-like is typed, PATH executables are what can run.
    if ($currentWord -ne '' -and -not $currentWord.StartsWith('-') -and (Test-StdbufCommandOperandSlot -commandAst $commandAst -cursorPosition $cursorPosition)) {
        $commands = @(Get-StdbufCommandOperandCompletion -CurrentWord $currentWord)
        if ($commands.Count -gt 0) {
            return $commands
        }
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-StdbufCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-StdbufCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-StdbufOptionDescription -Option $option)
                }
            }
        )
    }

    Get-StdbufPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'stdbuf', 'stdbuf.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Stdbuf -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
