# readlink tab completion for PowerShell
# Static option completion for readlink.exe and readlink.

Set-StrictMode -Version 2.0

function Get-ReadlinkCompletionOptions {
    $cache = Get-Variable -Name 'ReadlinkCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-f', '--canonicalize', '-e', '--canonicalize-existing', '-m', '--canonicalize-missing', '-n', '--no-newline', '-q', '--quiet', '-s', '--silent', '-v', '--verbose', '-z', '--zero', '-h', '--help', '-V', '--version')
    $commandCandidates = @('readlink.exe', 'readlink')
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
            Set-Variable -Name 'ReadlinkCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'ReadlinkCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'ReadlinkCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'ReadlinkCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'ReadlinkCompletionOptions' -Scope Script).Value
}


function New-ReadlinkCompletionResult {
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

function Get-ReadlinkTypedQuote {
    # The quote style the user opened the word with ('' when bare). PowerShell reads the
    # typographic quotes U+2018-U+201B as single quotes and U+201C-U+201E as double quotes.
    param([string]$Value)

    if ($Value -match '^[''\u2018-\u201B]') {
        return "'"
    }

    if ($Value -match '^["\u201C-\u201E]') {
        return '"'
    }

    ''
}

function ConvertFrom-ReadlinkTypedWord {
    # The value of a typed word without its quotes and escapes, read by the parser in
    # argument mode so doubled quotes and backticks resolve exactly as PowerShell will.
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    $ast = [System.Management.Automation.Language.Parser]::ParseInput('readlink ' + $Value, [ref]$null, [ref]$null)
    $command = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    if ($null -ne $command -and $command.CommandElements.Count -eq 2) {
        $element = $command.CommandElements[1]
        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $element -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            return $element.Value
        }
    }

    $Value
}

function ConvertTo-ReadlinkQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the typed quote style (single by default). Whitespace and argument-mode
    # metacharacters, the typographic quotes among them, end, split or rewrite a bare word.
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

    if ($QuoteChar -eq "'") {
        return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
    }

    '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
}

function Get-ReadlinkCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The parser keeps an unterminated quote as one element running to the cursor.
    foreach ($element in $CommandAst.CommandElements) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    ''
}

function Get-ReadlinkPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-ReadlinkTypedWord -Value $InputPath
    $quoteChar = Get-ReadlinkTypedQuote -Value $InputPath

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

    $items = @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction Ignore)
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

        $quotedPath = ConvertTo-ReadlinkQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-ReadlinkCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-ReadlinkCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-ReadlinkOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'ReadlinkCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for readlink.'
}

function Complete-Readlink {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if ([string]::IsNullOrEmpty($wordToComplete)) {
        return @()
    }

    $currentWord = Get-ReadlinkCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-ReadlinkCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-ReadlinkCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-ReadlinkOptionDescription -Option $option)
                }
            }
        )
    }

    Get-ReadlinkPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'readlink', 'readlink.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Readlink -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
