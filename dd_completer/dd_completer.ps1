# dd tab completion for PowerShell
# Static option completion for dd.exe and dd.

Set-StrictMode -Version 2.0

function Get-DdCompletionOptions {
    $cache = Get-Variable -Name 'DdCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('--if=', '--of=', '--bs=', '--ibs=', '--obs=', '--skip=', '--seek=', '--count=', '--conv=', '--status=', '--help', '--version')
    $commandCandidates = @('dd.exe', 'dd')
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
            Set-Variable -Name 'DdCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'DdCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'DdCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'DdCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'DdCompletionOptions' -Scope Script).Value
}

function New-DdCompletionResult {
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

function ConvertFrom-DdTypedWord {
    # The value of a typed word. A word holding a quote (ASCII or typographic) is read by the
    # PowerShell tokenizer as one command argument, which drops the quotes and undoes that quote
    # style's escapes (if='sp'a reads as if=spa). $null when the word is not a single argument
    # token ('sp a'.tx), so nothing is offered rather than replacing text the value lost.
    param([string]$Value)

    if ($Value -notmatch '[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput('x ' + $Value, [ref]$tokens, [ref]$parseErrors)
    if ($tokens.Count -ne 3 -or $tokens[1] -isnot [System.Management.Automation.Language.StringToken]) {
        return $null
    }

    $tokens[1].Value
}

function ConvertTo-DdQuotedValue {
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

function Get-DdCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The parser keeps an unterminated quoted word (if='sp a) as one element running to the cursor.
    foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    ''
}

function Get-DdPathCompletions {
    # $InputPath is the whole typed word; $Attached is an option head it starts with (if=), which
    # the caller puts back in front of each candidate.
    param(
        [string]$InputPath,
        [string]$Attached = ''
    )

    $cleanInput = ConvertFrom-DdTypedWord -Value $InputPath
    if ($null -eq $cleanInput -or -not $cleanInput.StartsWith($Attached, [System.StringComparison]::Ordinal)) {
        return @()
    }

    $cleanInput = $cleanInput.Substring($Attached.Length)
    $typedValue = $InputPath.Substring($Attached.Length)
    $quoteChar = if ($typedValue -match '^[''"\u2018-\u201E]') { $typedValue.Substring(0, 1) } else { '' }

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

    # Keep the directory part exactly as typed (.\, ./, ..\, C:\x\) in front of each name.
    $typedDir = if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        ''
    } elseif ($cleanInput.EndsWith($leaf, [System.StringComparison]::Ordinal)) {
        $cleanInput.Substring(0, $cleanInput.Length - $leaf.Length)
    } else {
        $null
    }

    foreach ($item in $items) {
        $pathText = if ($null -ne $typedDir) {
            # A bare word starting with a dash parses as a parameter, so a whole-word relative
            # name like -dash.txt gets the current-directory prefix, as PowerShell's own does.
            if (-not $typedDir -and -not $Attached -and $item.Name -match '^[-\u2013-\u2015]') {
                '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
            } else {
                $typedDir + $item.Name
            }
        } elseif ($parent -eq '.') {
            $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-DdQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-DdCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-DdCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-DdOptionValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord,
        [string]$WordToComplete
    )

    $option = $null
    $prefix = $CurrentWord
    $attached = ''
    if ($CurrentWord -match '^(?<option>[A-Za-z]+)=(?<value>.*)$') {
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
    $table['if'] = 'path'
    $table['of'] = 'path'
    $table['bs'] = @(
        @{ Text = '<size>'; Tip = 'Size, suffixes K, M, G accepted.' }
        @{ Text = '1K'; Tip = '1 KiB.' }
        @{ Text = '1M'; Tip = '1 MiB.' }
        @{ Text = '1G'; Tip = '1 GiB.' }
    )
    $table['ibs'] = @(
        @{ Text = '<size>'; Tip = 'Size, suffixes K, M, G accepted.' }
        @{ Text = '1K'; Tip = '1 KiB.' }
        @{ Text = '1M'; Tip = '1 MiB.' }
        @{ Text = '1G'; Tip = '1 GiB.' }
    )
    $table['obs'] = @(
        @{ Text = '<size>'; Tip = 'Size, suffixes K, M, G accepted.' }
        @{ Text = '1K'; Tip = '1 KiB.' }
        @{ Text = '1M'; Tip = '1 MiB.' }
        @{ Text = '1G'; Tip = '1 GiB.' }
    )
    $table['cbs'] = @(
        @{ Text = '<size>'; Tip = 'Size, suffixes K, M, G accepted.' }
        @{ Text = '1K'; Tip = '1 KiB.' }
        @{ Text = '1M'; Tip = '1 MiB.' }
        @{ Text = '1G'; Tip = '1 GiB.' }
    )
    $table['count'] = @(
        @{ Text = '<blocks>'; Tip = 'Number of blocks.' }
    )
    $table['skip'] = @(
        @{ Text = '<blocks>'; Tip = 'Number of blocks.' }
    )
    $table['seek'] = @(
        @{ Text = '<blocks>'; Tip = 'Number of blocks.' }
    )
    $table['conv'] = @(
        @{ Text = 'ascii'; Tip = 'EBCDIC to ASCII.' }
        @{ Text = 'ebcdic'; Tip = 'ASCII to EBCDIC.' }
        @{ Text = 'ibm'; Tip = 'ASCII to alternate EBCDIC.' }
        @{ Text = 'block'; Tip = 'Pad newline-terminated records.' }
        @{ Text = 'unblock'; Tip = 'Replace trailing spaces with newline.' }
        @{ Text = 'lcase'; Tip = 'Upper to lower case.' }
        @{ Text = 'ucase'; Tip = 'Lower to upper case.' }
        @{ Text = 'sparse'; Tip = 'Seek instead of writing NUL blocks.' }
        @{ Text = 'swab'; Tip = 'Swap every pair of input bytes.' }
        @{ Text = 'sync'; Tip = 'Pad every input block with NULs.' }
        @{ Text = 'excl'; Tip = 'Fail if the output file exists.' }
        @{ Text = 'nocreat'; Tip = 'Do not create the output file.' }
        @{ Text = 'notrunc'; Tip = 'Do not truncate the output file.' }
        @{ Text = 'noerror'; Tip = 'Continue after read errors.' }
        @{ Text = 'fdatasync'; Tip = 'Sync output data before finishing.' }
        @{ Text = 'fsync'; Tip = 'Sync output data and metadata.' }
    )
    $table['iflag'] = @(
        @{ Text = 'append'; Tip = 'Append mode.' }
        @{ Text = 'direct'; Tip = 'Direct I/O.' }
        @{ Text = 'directory'; Tip = 'Fail unless a directory.' }
        @{ Text = 'dsync'; Tip = 'Synchronized data I/O.' }
        @{ Text = 'sync'; Tip = 'Synchronized I/O.' }
        @{ Text = 'fullblock'; Tip = 'Accumulate full input blocks.' }
        @{ Text = 'nonblock'; Tip = 'Non-blocking I/O.' }
        @{ Text = 'noatime'; Tip = 'Do not update access time.' }
        @{ Text = 'nocache'; Tip = 'Request to drop cache.' }
        @{ Text = 'noctty'; Tip = 'Do not assign a controlling terminal.' }
        @{ Text = 'nofollow'; Tip = 'Do not follow symlinks.' }
        @{ Text = 'binary'; Tip = 'Binary I/O.' }
        @{ Text = 'text'; Tip = 'Text I/O.' }
        @{ Text = 'count_bytes'; Tip = 'Treat count=N as a byte count.' }
        @{ Text = 'skip_bytes'; Tip = 'Treat skip=N as a byte count.' }
    )
    $table['oflag'] = @(
        @{ Text = 'append'; Tip = 'Append mode.' }
        @{ Text = 'direct'; Tip = 'Direct I/O.' }
        @{ Text = 'directory'; Tip = 'Fail unless a directory.' }
        @{ Text = 'dsync'; Tip = 'Synchronized data I/O.' }
        @{ Text = 'sync'; Tip = 'Synchronized I/O.' }
        @{ Text = 'nonblock'; Tip = 'Non-blocking I/O.' }
        @{ Text = 'noatime'; Tip = 'Do not update access time.' }
        @{ Text = 'nocache'; Tip = 'Request to drop cache.' }
        @{ Text = 'noctty'; Tip = 'Do not assign a controlling terminal.' }
        @{ Text = 'nofollow'; Tip = 'Do not follow symlinks.' }
        @{ Text = 'binary'; Tip = 'Binary I/O.' }
        @{ Text = 'text'; Tip = 'Text I/O.' }
        @{ Text = 'seek_bytes'; Tip = 'Treat seek=N as a byte count.' }
    )
    $table['status'] = @(
        @{ Text = 'none'; Tip = 'Suppress everything but errors.' }
        @{ Text = 'noxfer'; Tip = 'Suppress transfer statistics.' }
        @{ Text = 'progress'; Tip = 'Show periodic transfer statistics.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        if ($CurrentWord.StartsWith('-')) {
            return @()
        }
        $operands = @(
            @{ Text = 'if='; Tip = 'Input file.' }
            @{ Text = 'of='; Tip = 'Output file.' }
            @{ Text = 'bs='; Tip = 'Block size for both input and output.' }
            @{ Text = 'ibs='; Tip = 'Input block size.' }
            @{ Text = 'obs='; Tip = 'Output block size.' }
            @{ Text = 'cbs='; Tip = 'Conversion block size.' }
            @{ Text = 'count='; Tip = 'Copy only this many input blocks.' }
            @{ Text = 'skip='; Tip = 'Skip input blocks.' }
            @{ Text = 'seek='; Tip = 'Skip output blocks.' }
            @{ Text = 'conv='; Tip = 'Conversion flags.' }
            @{ Text = 'iflag='; Tip = 'Input flags.' }
            @{ Text = 'oflag='; Tip = 'Output flags.' }
            @{ Text = 'status='; Tip = 'Information level.' }
        )
        return @(
            foreach ($entry in $operands) {
                if ($entry.Text.StartsWith($CurrentWord, [System.StringComparison]::Ordinal)) {
                    New-DdCompletionResult -CompletionText $entry.Text -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
                }
            }
        )
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-DdPathCompletions -InputPath $CurrentWord -Attached $attached) {
                New-DdCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }

    # conv=, iflag= and oflag= take a comma separated symbol list: complete the
    # segment after the last comma. PowerShell parses 'conv=sync,no' as an array
    # literal whose replacement range is only the word after the comma, so emit
    # just the part of the full value that $WordToComplete covers.
    $listHead = ''
    $usedSymbols = @()
    $emitFrom = 0
    $lastComma = $prefix.LastIndexOf(',')
    if (@('conv', 'iflag', 'oflag') -ccontains $option -and $lastComma -ge 0) {
        $listHead = $prefix.Substring(0, $lastComma + 1)
        $prefix = $prefix.Substring($lastComma + 1)
        $usedSymbols = @($listHead.Split(','))
        if ($CurrentWord.EndsWith($WordToComplete, [System.StringComparison]::Ordinal)) {
            $emitFrom = $CurrentWord.Length - $WordToComplete.Length
        }
    }

    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal) -and -not ($usedSymbols -ccontains $entry.Text)) {
                New-DdCompletionResult -CompletionText ($attached + $listHead + $entry.Text).Substring($emitFrom) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-DdOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'DdCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for dd.'
}

function Complete-Dd {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-DdCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-DdOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord -WordToComplete $wordToComplete)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-DdCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-DdCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-DdOptionDescription -Option $option)
                }
            }
        )
    }

    Get-DdPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'dd', 'dd.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Dd -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
