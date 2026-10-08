# df tab completion for PowerShell
# Static option completion for df.exe and df.

Set-StrictMode -Version 2.0

function Get-DfCompletionOptions {
    $cache = Get-Variable -Name 'DfCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-a', '--all', '-B', '--block-size', '--total', '-h', '--human-readable', '-H', '--si', '-i', '--inodes', '-k', '-l', '--local', '--no-sync', '--output', '-P', '--portability', '--sync', '-t', '--type', '-T', '--print-type', '-w', '-x', '--exclude-type', '-V', '--version', '--help')
    $commandCandidates = @('df.exe', 'df')
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
            Set-Variable -Name 'DfCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'DfCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'DfCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'DfCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'DfCompletionOptions' -Scope Script).Value
}


function New-DfCompletionResult {
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

function ConvertFrom-DfTypedWord {
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

function ConvertTo-DfQuotedValue {
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

function Get-DfCurrentToken {
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

function Get-DfPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-DfTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # Keep the typed directory text (.\, ./, C:, ..\x/) exactly and complete only the leaf.
    if ($cleanInput -notmatch '^(?<dir>(?:[A-Za-z]:)?(?:.*[\\/])?)(?<leaf>[^\\/]*)$') {
        return @()
    }

    $dirText = $Matches['dir']
    $leaf = $Matches['leaf']
    $parent = if ($dirText) { $dirText } else { '.' }
    $separator = if ($dirText -match '[\\/](?=[^\\/]*$)') { $Matches[0] } else { [string][System.IO.Path]::DirectorySeparatorChar }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = $dirText + $item.Name
        if (-not $dirText -and $item.Name -match '^[-\u2013-\u2015]') {
            # A bare word starting with a dash is parsed as a parameter: anchor it like PowerShell does.
            $pathText = '.' + $separator + $item.Name
        }

        if ($item.PSIsContainer) {
            $pathText += $separator
        }

        $quotedPath = ConvertTo-DfQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-DfCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-DfCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-DfOptionValueCompletions {
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
    } elseif ($CurrentWord -cmatch '^(?<option>-[Btx])(?<value>.+)$') {
        # df's help documents the attached short spelling ('-BM').
        $option = $Matches['option']
        $prefix = $Matches['value']
        $attached = $option
    } elseif (-not $CurrentWord.StartsWith('-')) {
        $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
        if ([string]::IsNullOrEmpty($CurrentWord)) {
            if ($elements.Count -gt 1) {
                $option = $elements[-1]
            }
        } elseif ($elements.Count -gt 2 -and $elements[-1] -eq $CurrentWord) {
            $option = $elements[-2]
        }

        # --output[=FIELD_LIST] takes its argument only attached; a separate word is an operand.
        if ($option -ceq '--output') {
            $option = $null
        }
    }

    if ([string]::IsNullOrEmpty($option)) {
        return @()
    }

    # FIELD_LIST is comma-separated: complete the segment after the last comma, keep the
    # earlier fields and skip the ones already listed (df rejects a repeated field).
    $head = ''
    $listed = @()
    if ($option -ceq '--output') {
        $commaIndex = $prefix.LastIndexOf(',')
        if ($commaIndex -ge 0) {
            $head = $prefix.Substring(0, $commaIndex + 1)
            $prefix = $prefix.Substring($commaIndex + 1)
            $listed = $head.Split(',')
        }
    }

    # In argument mode PowerShell ends $wordToComplete at a ',', and replaces only that part,
    # so the text before it is left out of CompletionText.
    $skip = 0
    if ($head -and $CurrentWord.Length -gt $WordToComplete.Length -and $CurrentWord.EndsWith($WordToComplete, [System.StringComparison]::Ordinal)) {
        $skip = $CurrentWord.Length - $WordToComplete.Length
    }

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['-B'] = @(
        @{ Text = 'K'; Tip = 'Scale sizes by K.' }
        @{ Text = 'M'; Tip = 'Scale sizes by M.' }
        @{ Text = 'G'; Tip = 'Scale sizes by G.' }
        @{ Text = 'T'; Tip = 'Scale sizes by T.' }
        @{ Text = 'KB'; Tip = 'Scale sizes by KB.' }
        @{ Text = 'MB'; Tip = 'Scale sizes by MB.' }
        @{ Text = 'GB'; Tip = 'Scale sizes by GB.' }
        @{ Text = '1K'; Tip = 'Scale sizes by 1K.' }
        @{ Text = '1M'; Tip = 'Scale sizes by 1M.' }
    )
    $table['--block-size'] = @(
        @{ Text = 'K'; Tip = 'Scale sizes by K.' }
        @{ Text = 'M'; Tip = 'Scale sizes by M.' }
        @{ Text = 'G'; Tip = 'Scale sizes by G.' }
        @{ Text = 'T'; Tip = 'Scale sizes by T.' }
        @{ Text = 'KB'; Tip = 'Scale sizes by KB.' }
        @{ Text = 'MB'; Tip = 'Scale sizes by MB.' }
        @{ Text = 'GB'; Tip = 'Scale sizes by GB.' }
        @{ Text = '1K'; Tip = 'Scale sizes by 1K.' }
        @{ Text = '1M'; Tip = 'Scale sizes by 1M.' }
    )
    $table['-t'] = @(
        @{ Text = 'ntfs'; Tip = 'ntfs file system.' }
        @{ Text = 'fat32'; Tip = 'fat32 file system.' }
        @{ Text = 'exfat'; Tip = 'exfat file system.' }
        @{ Text = 'refs'; Tip = 'refs file system.' }
        @{ Text = 'udf'; Tip = 'udf file system.' }
        @{ Text = 'vfat'; Tip = 'vfat file system.' }
    )
    $table['--type'] = @(
        @{ Text = 'ntfs'; Tip = 'ntfs file system.' }
        @{ Text = 'fat32'; Tip = 'fat32 file system.' }
        @{ Text = 'exfat'; Tip = 'exfat file system.' }
        @{ Text = 'refs'; Tip = 'refs file system.' }
        @{ Text = 'udf'; Tip = 'udf file system.' }
        @{ Text = 'vfat'; Tip = 'vfat file system.' }
    )
    $table['-x'] = @(
        @{ Text = 'ntfs'; Tip = 'ntfs file system.' }
        @{ Text = 'fat32'; Tip = 'fat32 file system.' }
        @{ Text = 'exfat'; Tip = 'exfat file system.' }
        @{ Text = 'refs'; Tip = 'refs file system.' }
        @{ Text = 'udf'; Tip = 'udf file system.' }
        @{ Text = 'vfat'; Tip = 'vfat file system.' }
    )
    $table['--exclude-type'] = @(
        @{ Text = 'ntfs'; Tip = 'ntfs file system.' }
        @{ Text = 'fat32'; Tip = 'fat32 file system.' }
        @{ Text = 'exfat'; Tip = 'exfat file system.' }
        @{ Text = 'refs'; Tip = 'refs file system.' }
        @{ Text = 'udf'; Tip = 'udf file system.' }
        @{ Text = 'vfat'; Tip = 'vfat file system.' }
    )
    $table['--output'] = @(
        @{ Text = 'source'; Tip = 'Output field source.' }
        @{ Text = 'fstype'; Tip = 'Output field fstype.' }
        @{ Text = 'itotal'; Tip = 'Output field itotal.' }
        @{ Text = 'iused'; Tip = 'Output field iused.' }
        @{ Text = 'iavail'; Tip = 'Output field iavail.' }
        @{ Text = 'ipcent'; Tip = 'Output field ipcent.' }
        @{ Text = 'size'; Tip = 'Output field size.' }
        @{ Text = 'used'; Tip = 'Output field used.' }
        @{ Text = 'avail'; Tip = 'Output field avail.' }
        @{ Text = 'pcent'; Tip = 'Output field pcent.' }
        @{ Text = 'file'; Tip = 'Output field file.' }
        @{ Text = 'target'; Tip = 'Output field target.' }
    )
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-DfPathCompletions -InputPath $prefix) {
                # Quote the whole attached word so it stays one constant argument.
                New-DfCompletionResult -CompletionText (ConvertTo-DfQuotedValue -Value ($attached + $result.ListItemText)) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal) -and $listed -cnotcontains $entry.Text) {
                New-DfCompletionResult -CompletionText ($attached + $head + $entry.Text).Substring($skip) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-DfOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'DfCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for df.'
}

function Complete-Df {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-DfCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-DfOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord -WordToComplete $wordToComplete)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-DfCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-DfCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-DfOptionDescription -Option $option)
                }
            }
        )
    }

    Get-DfPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'df', 'df.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Df -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
