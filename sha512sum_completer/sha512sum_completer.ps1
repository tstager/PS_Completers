# sha512sum tab completion for PowerShell
# Static option completion for sha512sum.exe and sha512sum.

Set-StrictMode -Version 2.0

function Get-Sha512sumCompletionOptions {
    $cache = Get-Variable -Name 'Sha512sumCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--binary', '-c', '--check', '-w', '--warn', '--status', '--quiet', '--strict', '--ignore-missing', '--tag', '-t', '--text', '-z', '--zero', '-h', '--help', '-V', '--version')
    $commandCandidates = @('sha512sum.exe', 'sha512sum')
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
            Set-Variable -Name 'Sha512sumCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'Sha512sumCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'Sha512sumCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'Sha512sumCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'Sha512sumCompletionOptions' -Scope Script).Value
}

function New-Sha512sumCompletionResult {
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

function ConvertFrom-Sha512sumTypedWord {
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

function ConvertTo-Sha512sumQuotedValue {
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

function Get-Sha512sumCurrentToken {
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

function Get-Sha512sumPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-Sha512sumTypedWord -Value $InputPath
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

    $items = @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    # Candidates keep the directory part exactly as typed (including a leading .\ or ./).
    $typedDirectory = $cleanInput.Substring(0, $cleanInput.LastIndexOfAny([char[]]'\/:') + 1)
    $separator = if ($typedDirectory -match '[\\/]$') { $typedDirectory[-1] } else { [System.IO.Path]::DirectorySeparatorChar }

    foreach ($item in $items) {
        $pathText = $typedDirectory + $item.Name

        # A bare word starting with a dash parses as a parameter; anchor it to the current directory.
        if (-not $typedDirectory -and $pathText -match '^[-\u2013-\u2015]') {
            $pathText = '.' + $separator + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith($separator)) {
            $pathText += $separator
        }

        $quotedPath = ConvertTo-Sha512sumQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-Sha512sumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-Sha512sumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Complete-Sha512sumOperand {
    param(
        [string]$CurrentWord,
        [string[]]$TokensBeforeCurrent
    )

    # An unquoted path with spaces ('C:\Program Files\cor') reaches the completer as the last
    # whitespace-split piece. Re-join it with the operand tokens typed before it until a parent
    # directory exists, and emit only the piece PowerShell will replace.
    $head = ''
    $inputPath = $CurrentWord
    if ($CurrentWord -notmatch '^[''"\u2018-\u201E]') {
        $operands = @($TokensBeforeCurrent | Where-Object { -not $_.StartsWith('-') -and $_ -notmatch '[''"\u2018-\u201E]' })
        $joined = $CurrentWord
        $joinedHead = ''
        for ($i = $operands.Count - 1; $i -ge [Math]::Max(0, $operands.Count - 3); $i--) {
            $joinedHead = $operands[$i] + ' ' + $joinedHead
            $joined = $operands[$i] + ' ' + $joined
            $parent = if ($joined -match '[\\/]+$') { $joined } else { Split-Path -Path $joined -Parent }
            if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
                $head = $joinedHead
                $inputPath = $joined
                break
            }
        }
    }

    $results = @(Get-Sha512sumPathCompletions -InputPath $inputPath)
    if ($head) {
        # Only the last piece is replaced, so it is quoted on its own (ListItemText is the bare path).
        $results = @(
            foreach ($result in $results) {
                if ($result.ListItemText.StartsWith($head, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-Sha512sumCompletionResult -CompletionText (ConvertTo-Sha512sumQuotedValue -Value $result.ListItemText.Substring($head.Length)) -ListItemText $result.ListItemText -ResultType $result.ResultType -ToolTip $result.ToolTip
                }
            }
        )
    }

    # After -c/--check (or a cluster containing c) the operand is a checksum manifest, so
    # manifest-shaped files are listed first.
    $checking = $false
    foreach ($token in $TokensBeforeCurrent) {
        if ($token -ceq '--check' -or ($token -cmatch '^-[A-Za-z]+$' -and $token.Contains('c'))) {
            $checking = $true
        }
    }

    if (-not $checking) {
        return $results
    }

    $manifests = [System.Collections.Generic.List[object]]::new()
    $others = [System.Collections.Generic.List[object]]::new()
    foreach ($result in $results) {
        if ($result.ResultType -eq 'ProviderItem' -and $result.ListItemText -match '(?i)(^|[\\/])(SHA512SUMS?|CHECKSUMS?(\.txt)?|[^\\/]*\.(sha512|sha512sum|sha|sum|sums|txt))$') {
            $manifests.Add((New-Sha512sumCompletionResult -CompletionText $result.CompletionText -ListItemText $result.ListItemText -ResultType $result.ResultType -ToolTip ('Checksum manifest to verify: ' + $result.ToolTip)))
        } else {
            $others.Add($result)
        }
    }

    @($manifests.ToArray() + $others.ToArray())
}

function Complete-Sha512sumShortFlagCluster {
    param([string]$CurrentWord)

    # Every sha512sum option is a boolean switch, so '-cw' is '-c -w'; extend a cluster of known
    # short flags with each flag not yet in it.
    if ($CurrentWord -notmatch '^-[A-Za-z]{2,}$') {
        return @()
    }

    $shortFlags = @(Get-Sha512sumCompletionOptions | Where-Object { $_ -cmatch '^-[A-Za-z]$' })
    $usedLetters = @($CurrentWord.Substring(1).ToCharArray() | ForEach-Object { [string]$_ })
    foreach ($letter in $usedLetters) {
        if (('-' + $letter) -cnotin $shortFlags) {
            return @()
        }
    }

    @(
        foreach ($flag in $shortFlags) {
            $letter = $flag.Substring(1)
            if ($letter -cin $usedLetters) {
                continue
            }

            $clustered = $CurrentWord + $letter
            New-Sha512sumCompletionResult -CompletionText $clustered -ListItemText $clustered -ResultType 'ParameterName' -ToolTip ('{0}: {1}' -f $flag, (Get-Sha512sumOptionDescription -Option $flag))
        }
    )
}

function Get-Sha512sumOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'Sha512sumCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for sha512sum.'
}

function Complete-Sha512sum {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-Sha512sumCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    $tokensBeforeCurrent = @(
        foreach ($element in ($commandAst.CommandElements | Select-Object -Skip 1)) {
            if ($element.Extent.EndOffset -lt $cursorPosition) {
                $element.Extent.Text
            }
        }
    )

    if ([string]::IsNullOrEmpty($currentWord)) {
        $checking = @($tokensBeforeCurrent | Where-Object { $_ -ceq '--check' -or ($_ -cmatch '^-[A-Za-z]+$' -and $_.Contains('c')) }).Count -gt 0
        if ($checking) {
            return Complete-Sha512sumOperand -CurrentWord '' -TokensBeforeCurrent $tokensBeforeCurrent
        }

        return @()
    }

    if ($currentWord.StartsWith('-')) {
        $optionMatches = @(
            foreach ($option in Get-Sha512sumCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-Sha512sumCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-Sha512sumOptionDescription -Option $option)
                }
            }
        )
        if ($optionMatches.Count -gt 0) {
            return $optionMatches
        }

        return Complete-Sha512sumShortFlagCluster -CurrentWord $currentWord
    }

    Complete-Sha512sumOperand -CurrentWord $currentWord -TokensBeforeCurrent $tokensBeforeCurrent
}

Register-ArgumentCompleter -Native -CommandName 'sha512sum', 'sha512sum.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Sha512sum -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
