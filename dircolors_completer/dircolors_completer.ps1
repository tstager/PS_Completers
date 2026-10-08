# dircolors tab completion for PowerShell
# Static option completion for dircolors.exe and dircolors.

Set-StrictMode -Version 2.0

function Get-DircolorsCompletionOptions {
    $cache = Get-Variable -Name 'DircolorsCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--print-database', '-p', '--print-database', '-c', '--sh', '--help', '--version')
    $commandCandidates = @('dircolors.exe', 'dircolors')
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
            Set-Variable -Name 'DircolorsCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'DircolorsCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'DircolorsCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'DircolorsCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'DircolorsCompletionOptions' -Scope Script).Value
}

function New-DircolorsCompletionResult {
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

function Remove-DircolorsOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    # Re-tokenize the word in argument position so a quoted word loses its quotes
    # and escapes ('it''s, "a`$b) exactly as PowerShell reads it, terminated or not.
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput('x ' + $Value, [ref]$tokens, [ref]$parseErrors)
    if ($tokens.Count -gt 1 -and $tokens[1] -is [System.Management.Automation.Language.StringToken]) {
        # A bareword whose single quote opens mid-word and never closes (it's) means
        # the quote literally: escape that quote and read the word again, but only
        # when the literal reading is still one word (it's b stays one quoted word).
        # A double quote cannot be part of a file name, so it keeps its string reading.
        if ($tokens[1].Kind -eq [System.Management.Automation.Language.TokenKind]::Generic) {
            $openQuote = $parseErrors | Where-Object { $_.ErrorId -eq 'TerminatorExpectedAtEndOfString' } | Select-Object -First 1
            if ($null -ne $openQuote) {
                $quoteAt = $openQuote.Extent.StartOffset - 2
                if ($quoteAt -gt 0 -and $quoteAt -lt $Value.Length -and $Value[$quoteAt] -match '[''\u2018-\u201B]') {
                    $literal = $Value.Substring(0, $quoteAt) + '`' + $Value.Substring($quoteAt)
                    $literalTokens = $null
                    $literalErrors = $null
                    [void][System.Management.Automation.Language.Parser]::ParseInput('x ' + $literal, [ref]$literalTokens, [ref]$literalErrors)
                    if ($literalTokens.Count -gt 1 -and $literalTokens[1].Extent.EndOffset -eq $literal.Length + 2) {
                        return Remove-DircolorsOuterQuotes -Value $literal
                    }
                }
            }
        }

        return $tokens[1].Value
    }

    $Value
}

function ConvertTo-DircolorsQuotedValue {
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    # Keep the quote the user opened; otherwise single-quote any value that would
    # split or expand as a bare argument (whitespace, metacharacters, quotes, a
    # leading @, # or dash), as PowerShell's own path completion does.
    if ($QuoteChar -eq '"') {
        return '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
    }

    if ($QuoteChar -eq "'" -or $Value -match '[\s{}();,|&<>''"`$\u2018-\u201E]' -or $Value -match '^[@#\-\u2013-\u2015]') {
        return "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Value) + "'"
    }

    $Value
}

function Get-DircolorsCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)

    # The word under the cursor is the whole parser token around the cursor, the
    # span PowerShell replaces, so text typed after the cursor stays part of the
    # word instead of being deleted; an unterminated quote is one token running
    # to the end, spaces included.
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$parseErrors)
    $currentToken = $tokens | Where-Object {
        $_.Kind -ne [System.Management.Automation.Language.TokenKind]::EndOfInput -and
        $_.Extent.StartOffset -lt $safeCursor -and $_.Extent.EndOffset -ge $safeCursor
    } | Select-Object -First 1
    if ($null -eq $currentToken) {
        return ''
    }

    $currentToken.Text
}

function Get-DircolorsPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-DircolorsOuterQuotes -Value $InputPath
    $quoteChar = ''
    if (-not [string]::IsNullOrEmpty($InputPath)) {
        if ($InputPath[0] -match '[''\u2018-\u201B]') {
            $quoteChar = "'"
        } elseif ($InputPath[0] -match '["\u201C-\u201E]') {
            $quoteChar = '"'
        }
    }

    # Keep the typed directory part (.\, ./, ..\, C:\...) verbatim and complete
    # only the leaf after the last separator, so no typed text is dropped.
    $separatorAt = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    if ($separatorAt -ge 0) {
        $prefix = $cleanInput.Substring(0, $separatorAt + 1)
        $parent = $prefix
        $leaf = $cleanInput.Substring($separatorAt + 1)
    } else {
        $prefix = ''
        $parent = '.'
        $leaf = $cleanInput
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        # A bare name starting with a dash would parse as a parameter: anchor it
        # to the current directory, as PowerShell's own file completion does.
        $pathText = if ($prefix -eq '' -and $item.Name -match '^[-\u2013-\u2015]') {
            '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        } else {
            $prefix + $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-DircolorsQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-DircolorsCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-DircolorsCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-DircolorsOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'DircolorsCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for dircolors.'
}

function Complete-Dircolors {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-DircolorsCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-DircolorsCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-DircolorsCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-DircolorsOptionDescription -Option $option)
                }
            }
        )
    }

    Get-DircolorsPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'dircolors', 'dircolors.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Dircolors -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
