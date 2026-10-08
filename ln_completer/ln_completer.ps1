# ln tab completion for PowerShell
# Static option completion for ln.exe and ln.

Set-StrictMode -Version 2.0

function Get-LnCompletionOptions {
    $cache = Get-Variable -Name 'LnCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--backup', '-f', '--force', '-i', '--interactive', '-L', '--logical', '-n', '--no-dereference', '-P', '--physical', '-r', '--relative', '-S', '--suffix', '-s', '--symbolic', '-t', '--target-directory', '-T', '--no-target-directory', '-v', '--verbose', '-h', '--help', '-V', '--version')
    $commandCandidates = @('ln.exe', 'ln')
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
            Set-Variable -Name 'LnCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'LnCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'LnCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'LnCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'LnCompletionOptions' -Scope Script).Value
}


function New-LnCompletionResult {
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

function ConvertFrom-LnTypedWord {
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

function ConvertTo-LnQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default). PowerShell reads ' and
    # U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes.
    param(
        [string]$Value,
        [string]$QuoteChar = '',
        [string]$DefaultQuote = "'"
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $QuoteChar) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]|^[-\u2013-\u2015]') {
            return $Value
        }

        $QuoteChar = $DefaultQuote
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-LnCurrentToken {
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

function Get-LnPathCompletions {
    param(
        [string]$InputPath,
        [switch]$ContainersOnly,
        [string]$DefaultQuote = "'"
    )

    $cleanInput = ConvertFrom-LnTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # Candidates keep the typed directory text verbatim (.\, ./, ..\ and the typed separators).
    $null = $cleanInput -match '(?s)^(?<dir>.*[\\/])?(?<leaf>.*)$'
    $dirText = if ($Matches['dir']) { $Matches['dir'] } else { '' }
    $leaf = $Matches['leaf']
    $parent = if ($dirText) { $dirText } else { '.' }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name
    if ($ContainersOnly) {
        $items = $items | Where-Object { $_.PSIsContainer }
    }

    foreach ($item in $items) {
        # A bare word starting with a dash parses as a parameter, so such a name gets the
        # current-directory prefix, as PowerShell's own file completion does.
        $pathText = if (-not $dirText -and $item.Name -match '^[-\u2013-\u2015]') {
            '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        } else {
            $dirText + $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-LnQuotedValue -Value $pathText -QuoteChar $quoteChar -DefaultQuote $DefaultQuote
        if ($item.PSIsContainer) {
            New-LnCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-LnCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-LnOptionValueCompletions {
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

    # --backup[=CONTROL] takes an optional argument, so CONTROL is only accepted attached.
    if ($option -ceq '--backup' -and -not $attached) {
        return @()
    }

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['--backup'] = @(
        @{ Text = 'none'; Tip = 'Never make backups.' }
        @{ Text = 'off'; Tip = 'Never make backups.' }
        @{ Text = 'numbered'; Tip = 'Numbered backups.' }
        @{ Text = 't'; Tip = 'Numbered backups.' }
        @{ Text = 'existing'; Tip = 'Numbered if numbered backups exist, simple otherwise.' }
        @{ Text = 'nil'; Tip = 'Numbered if numbered backups exist, simple otherwise.' }
        @{ Text = 'simple'; Tip = 'Simple backups.' }
        @{ Text = 'never'; Tip = 'Simple backups.' }
    )
    $table['-S'] = @(
        @{ Text = '~'; Tip = 'Default backup suffix.' }
        @{ Text = '<suffix>'; Tip = 'Backup suffix.' }
    )
    $table['--suffix'] = @(
        @{ Text = '~'; Tip = 'Default backup suffix.' }
        @{ Text = '<suffix>'; Tip = 'Backup suffix.' }
    )
    $table['-t'] = 'directory'
    $table['--target-directory'] = 'directory'
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'directory') {
        return @(
            foreach ($result in Get-LnPathCompletions -InputPath $prefix -ContainersOnly) {
                New-LnCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType $result.ResultType -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-LnCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-LnOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'LnCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for ln.'
}

function Complete-Ln {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-LnCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-LnOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-LnCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-LnCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-LnOptionDescription -Option $option)
                }
            }
        )
    }

    # A word glued to a closing single quote ('it'sp) is its own argument; a single-quoted
    # candidate there would form a '' escape and merge with it, so quote with " instead.
    $wordStart = $cursorPosition - $currentWord.Length - $commandAst.Extent.StartOffset
    $defaultQuote = if ($wordStart -gt 0 -and $commandAst.Extent.Text[$wordStart - 1] -match '[''\u2018-\u201B]') { '"' } else { "'" }
    Get-LnPathCompletions -InputPath $currentWord -DefaultQuote $defaultQuote
}

Register-ArgumentCompleter -Native -CommandName 'ln', 'ln.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Ln -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
