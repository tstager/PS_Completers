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
    # leading @ or #), as PowerShell's own path completion does.
    if ($QuoteChar -eq '"') {
        return '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
    }

    if ($QuoteChar -eq "'" -or $Value -match '[\s{}();,|&<>''"`$\u2018-\u201E]' -or $Value -match '^[@#]') {
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
    $prefix = $Line.Substring(0, $safeCursor)

    # The word under the cursor is the parser token that ends at the cursor; an
    # unterminated quote is one token running to the cursor, spaces included.
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($prefix, [ref]$tokens, [ref]$parseErrors)
    $lastToken = $tokens | Where-Object { $_.Kind -ne [System.Management.Automation.Language.TokenKind]::EndOfInput } | Select-Object -Last 1
    if ($null -eq $lastToken -or $lastToken.Extent.EndOffset -ne $prefix.Length) {
        return ''
    }

    $lastToken.Text
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

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = if ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $item.Name
        } elseif ([System.IO.Path]::IsPathRooted($cleanInput)) {
            Join-Path -Path $parent -ChildPath $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
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
