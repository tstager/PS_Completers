# sha256sum tab completion for PowerShell
# Static option completion for sha256sum.exe and sha256sum.

Set-StrictMode -Version 2.0

function Get-Sha256sumCompletionOptions {
    $cache = Get-Variable -Name 'Sha256sumCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-c', '--check', '-w', '--warn', '--status', '--quiet', '--ignore-missing', '--strict', '-z', '--tag', '-t', '--text', '--zero', '-h', '--help', '-V', '--version')
    $commandCandidates = @('sha256sum.exe', 'sha256sum')
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
            Set-Variable -Name 'Sha256sumCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'Sha256sumCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'Sha256sumCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'Sha256sumCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'Sha256sumCompletionOptions' -Scope Script).Value
}


function New-Sha256sumCompletionResult {
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

function ConvertFrom-Sha256sumTypedWord {
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

function ConvertTo-Sha256sumQuotedValue {
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

function Get-Sha256sumCurrentToken {
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

function Get-Sha256sumPathCompletions {
    param([string]$InputPath)

    $cleanInput = [string](ConvertFrom-Sha256sumTypedWord -Value $InputPath)
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # The typed directory text (up to the last separator) is kept verbatim, so a typed .\ or ../
    # prefix and the typed separator style survive.
    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    $typedDirectory = if ($separatorIndex -ge 0) {
        $cleanInput.Substring(0, $separatorIndex + 1)
    } elseif ($cleanInput -match '^[A-Za-z]:') {
        $cleanInput.Substring(0, 2)
    } else {
        ''
    }
    $leaf = $cleanInput.Substring($typedDirectory.Length)
    $parent = if ($typedDirectory) { $typedDirectory } else { '.' }
    $separator = if ($separatorIndex -ge 0) { $cleanInput[$separatorIndex] } else { [System.IO.Path]::DirectorySeparatorChar }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = $typedDirectory + $item.Name

        # PowerShell reads a bare word starting with a dash as a parameter, so a dash-leading
        # name gets the current-directory prefix, as PowerShell's own file completion does.
        if (-not $typedDirectory -and $pathText -match '^[-\u2013-\u2015]') {
            $pathText = '.' + $separator + $pathText
        }

        if ($item.PSIsContainer) {
            $pathText += $separator
        }

        $quotedPath = ConvertTo-Sha256sumQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-Sha256sumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-Sha256sumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-Sha256sumOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'Sha256sumCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for sha256sum.'
}

function Complete-Sha256sum {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and unescapes quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-Sha256sumCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    if ([string]::IsNullOrEmpty($currentWord)) {
        return Get-Sha256sumPathCompletions -InputPath ''
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-Sha256sumCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-Sha256sumCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-Sha256sumOptionDescription -Option $option)
                }
            }
        )
    }

    Get-Sha256sumPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'sha256sum', 'sha256sum.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Sha256sum -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
