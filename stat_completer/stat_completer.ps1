# stat tab completion for PowerShell
# Static option completion for stat.exe and stat.

Set-StrictMode -Version 2.0

function Get-StatCompletionOptions {
    $cache = Get-Variable -Name 'StatCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-L', '--dereference', '-f', '--file-system', '-t', '--terse', '-c', '--format', '--printf', '-h', '--help', '-V', '--version', '-r', '-s')
    # Application-only lookup: a missing name never triggers module auto-load discovery.
    # The fallback list cached below is the session's negative cache when stat is absent.
    $command = Get-Command -Name 'stat.exe', 'stat' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    $helpOutput = ''
    if ($null -ne $command) {
        try {
            $helpOutput = $null | & $command.Source --help 2>&1 | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String
        } catch {
            $helpOutput = ''
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($helpOutput)) {
        $options = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $descriptions = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
        $sequences = @{
            File       = [System.Collections.Generic.List[object]]::new()
            FileSystem = [System.Collections.Generic.List[object]]::new()
        }
        $section = $null
        foreach ($line in ([regex]::Split($helpOutput, '\r?\n'))) {
            # GNU prints '  %a   desc', uutils prints '  -`%a`: desc'; a non-blank, non-sequence line ends the block.
            if ($line -match 'format sequences for file systems') {
                $section = 'FileSystem'
            } elseif ($line -match 'format sequences for files') {
                $section = 'File'
            } elseif ($null -ne $section -and $line -match '^\s*-?`?(?<seq>%[A-Za-z])`?:?\s+(?<tip>\S.*)$') {
                $sequences[$section].Add(@{ Text = $Matches['seq']; Tip = $Matches['tip'].Trim() })
            } elseif (-not [string]::IsNullOrWhiteSpace($line)) {
                $section = $null
            }

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
            Set-Variable -Name 'StatCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'StatCompletionDescriptions' -Value $descriptions -Scope Script
            Set-Variable -Name 'StatFormatSequences' -Value $sequences -Scope Script
            return (Get-Variable -Name 'StatCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'StatCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'StatCompletionOptions' -Scope Script).Value
}


function New-StatCompletionResult {
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

function ConvertFrom-StatTypedWord {
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

function ConvertTo-StatQuotedValue {
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

function Get-StatCurrentToken {
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

function Get-StatPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-StatTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # The typed directory part (through the last separator, or a bare drive 'C:') is kept
    # exactly as typed, so a typed .\ or ./ prefix and its separator style survive.
    $directoryText = ''
    $leaf = $cleanInput
    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]'\/')
    if ($separatorIndex -ge 0) {
        $directoryText = $cleanInput.Substring(0, $separatorIndex + 1)
        $leaf = $cleanInput.Substring($separatorIndex + 1)
    } elseif ($cleanInput -match '^[A-Za-z]:') {
        $directoryText = $cleanInput.Substring(0, 2)
        $leaf = $cleanInput.Substring(2)
    }

    $parent = if ($directoryText) { $directoryText } else { '.' }
    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        # A bare leading dash reads as a parameter; like PowerShell's own completion, prefix .\ instead.
        $pathText = if (-not $directoryText -and $item.Name -match '^[-\u2013-\u2015]') {
            '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        } else {
            $directoryText + $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-StatQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-StatCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-StatCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-StatFormatSequence {
    param([bool]$FileSystem)

    $null = Get-StatCompletionOptions
    $key = if ($FileSystem) { 'FileSystem' } else { 'File' }
    $cache = Get-Variable -Name 'StatFormatSequences' -Scope Script -ErrorAction Ignore
    $values = if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value[$key].Count -gt 0) {
        $cache.Value[$key]
    } elseif ($FileSystem) {
        @(
            @{ Text = '%a'; Tip = 'Free blocks available to non-superuser.' }
            @{ Text = '%b'; Tip = 'Total data blocks in file system.' }
            @{ Text = '%c'; Tip = 'Total file nodes in file system.' }
            @{ Text = '%d'; Tip = 'Free file nodes in file system.' }
            @{ Text = '%f'; Tip = 'Free blocks in file system.' }
            @{ Text = '%i'; Tip = 'File system ID in hex.' }
            @{ Text = '%l'; Tip = 'Maximum length of filenames.' }
            @{ Text = '%n'; Tip = 'File name.' }
            @{ Text = '%s'; Tip = 'Block size (for faster transfers).' }
            @{ Text = '%S'; Tip = 'Fundamental block size (for block counts).' }
            @{ Text = '%t'; Tip = 'File system type in hex.' }
            @{ Text = '%T'; Tip = 'File system type in human readable form.' }
        )
    } else {
        @(
            @{ Text = '%n'; Tip = 'File name.' }
            @{ Text = '%s'; Tip = 'Size in bytes.' }
            @{ Text = '%a'; Tip = 'Permission bits in octal.' }
            @{ Text = '%A'; Tip = 'Permission bits, human readable.' }
            @{ Text = '%U'; Tip = 'Owner name.' }
            @{ Text = '%F'; Tip = 'File type.' }
            @{ Text = '%y'; Tip = 'Last modification, human readable.' }
            @{ Text = '%Y'; Tip = 'Last modification, seconds since epoch.' }
            @{ Text = '%i'; Tip = 'Inode number.' }
        )
    }

    @($values) + @(@{ Text = '<format>'; Tip = 'Custom stat format.' })
}

function Test-StatFileSystemMode {
    param([System.Management.Automation.Language.CommandAst]$commandAst)

    # -f, a long prefix of --file-system, or a short cluster with f before any c (letters after c are its value).
    foreach ($element in @($commandAst.CommandElements | Select-Object -Skip 1)) {
        $text = $element.Extent.Text
        if ($text -eq '--') {
            return $false
        }

        if ($text -cmatch '^-[A-Za-z]+$' -and ($text -csplit 'c', 2)[0].Contains('f')) {
            return $true
        }

        if ($text.Length -ge 4 -and '--file-system'.StartsWith($text, [System.StringComparison]::Ordinal)) {
            return $true
        }
    }

    $false
}

function Get-StatOptionValueCompletions {
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
    $table['--cached'] = @(
        @{ Text = 'always'; Tip = 'Use cached attributes.' }
        @{ Text = 'never'; Tip = 'Never use cached attributes.' }
        @{ Text = 'default'; Tip = 'Let the system decide.' }
    )
    $formatSequences = { Get-StatFormatSequence -FileSystem (Test-StatFileSystemMode -commandAst $commandAst) }
    $table['-c'] = $formatSequences
    $table['--format'] = $formatSequences
    $table['--printf'] = $formatSequences
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        # An attached path is quoted as a whole word ('--opt=a b'): --opt='a b' is not one constant.
        $pathQuote = if ($prefix -match '^[''"\u2018-\u201E]') { $prefix.Substring(0, 1) } else { '' }
        return @(
            foreach ($result in Get-StatPathCompletions -InputPath $prefix) {
                $text = if ($attached) { ConvertTo-StatQuotedValue -Value ($attached + $result.ListItemText) -QuoteChar $pathQuote } else { $result.CompletionText }
                New-StatCompletionResult -CompletionText $text -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    # A quoted value ('%, --format="%) matches without its quotes; the candidate keeps
    # the user's quote character and closes it.
    $quote = ''
    if ($prefix.Length -gt 0 -and ($prefix[0] -eq [char]39 -or $prefix[0] -eq [char]34)) {
        $quote = [string]$prefix[0]
        $prefix = $prefix.Substring(1)
        if ($prefix.EndsWith($quote, [System.StringComparison]::Ordinal)) {
            $prefix = $prefix.Substring(0, $prefix.Length - 1)
        }
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                $text = if ($quote -eq "'") {
                    "'" + $entry.Text.Replace("'", "''") + "'"
                } elseif ($quote -eq '"') {
                    '"' + ($entry.Text -replace '([`"$])', '`$1') + '"'
                } else {
                    $entry.Text
                }

                New-StatCompletionResult -CompletionText ($attached + $text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-StatOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'StatCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for stat.'
}

function Complete-Stat {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-StatCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $optionValues = @(Get-StatOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-StatCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-StatCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-StatOptionDescription -Option $option)
                }
            }
        )
    }

    Get-StatPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'stat', 'stat.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Stat -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
