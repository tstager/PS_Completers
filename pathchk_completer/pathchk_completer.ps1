# pathchk tab completion for PowerShell
# Static option completion for pathchk.exe and pathchk.

Set-StrictMode -Version 2.0

function Get-PathchkCompletionOptions {
    $cache = Get-Variable -Name 'PathchkCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-p', '--portability', '--help', '--version')
    $commandCandidates = @('pathchk.exe', 'pathchk')
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
            Set-Variable -Name 'PathchkCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'PathchkCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'PathchkCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'PathchkCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'PathchkCompletionOptions' -Scope Script).Value
}

function New-PathchkCompletionResult {
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

function ConvertTo-PathchkQuotedValue {
    param(
        [string]$Value,
        [string]$Quote = ''
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    # Quote when the user opened a quote, or when the bare word would be split,
    # expanded or rejected in argument mode: whitespace, the argument-mode
    # metacharacters (including the typographic quotes PowerShell treats as quotes)
    # and a leading @ or #.
    if ($Quote -eq '' -and $Value -notmatch '[\s{}();,|&<>''"`$\u2018-\u201E]' -and $Value -notmatch '^[@#]') {
        return $Value
    }

    if ($Quote -eq '"') {
        return '"' + ($Value -replace '[`"$\u201C-\u201E]', '`$0') + '"'
    }

    "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Value) + "'"
}

function Get-PathchkCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The parser already resolved quoting and escapes: take the argument element
    # that holds the cursor (an unterminated quote is one element running to the
    # cursor) and report its unescaped text plus the quote the user typed.
    $elements = @($CommandAst.CommandElements)
    for ($index = 1; $index -lt $elements.Count; $index++) {
        $element = $elements[$index]
        if ($element.Extent.StartOffset -ge $CursorPosition -or $element.Extent.EndOffset -lt $CursorPosition) {
            continue
        }

        # A word the parser split at a paren or sub-expression ('p(1)\' is 'p', '(1)', '\') is
        # not a path: the fragment under the cursor touches the element before or after it.
        if ($element.Extent.StartOffset -eq $elements[$index - 1].Extent.EndOffset -or
            ($index + 1 -lt $elements.Count -and $elements[$index + 1].Extent.StartOffset -eq $element.Extent.EndOffset)) {
            return [pscustomobject]@{ Text = $element.Extent.Text; Quote = ''; Fragment = $true }
        }

        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $element -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            $quote = switch ($element.StringConstantType) {
                'SingleQuoted' { "'" }
                'DoubleQuoted' { '"' }
                default { '' }
            }
            return [pscustomobject]@{ Text = $element.Value; Quote = $quote; Fragment = $false }
        }

        if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
            return [pscustomobject]@{ Text = $element.Extent.Text; Quote = ''; Fragment = $false }
        }

        # A paren, sub-expression, variable or array element is not a path either.
        break
    }

    [pscustomobject]@{ Text = ''; Quote = ''; Fragment = $false }
}

function Get-PathchkPathCompletions {
    param(
        [string]$InputPath,
        [string]$Quote = ''
    )

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        $parent = '.'
        $leaf = ''
    } elseif ($InputPath -match '[\\/]+$') {
        $parent = $InputPath
        $leaf = ''
    } else {
        $parent = Split-Path -Path $InputPath -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $InputPath -Leaf
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = if ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($InputPath)) {
            $item.Name
        } elseif ([System.IO.Path]::IsPathRooted($InputPath)) {
            Join-Path -Path $parent -ChildPath $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-PathchkQuotedValue -Value $pathText -Quote $Quote
        if ($item.PSIsContainer) {
            New-PathchkCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-PathchkCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-PathchkOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'PathchkCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for pathchk.'
}

function Complete-Pathchk {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is read from the CommandAst element at the cursor; wordToComplete re-wraps an open quote without its escapes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $token = Get-PathchkCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition
    $currentWord = $token.Text

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    # PowerShell completes file names itself when a native completer returns nothing, and would
    # replace the fragment with unrelated paths; offer the fragment unchanged so Tab is a no-op.
    if ($token.Fragment) {
        return @(New-PathchkCompletionResult -CompletionText $currentWord -ResultType 'ParameterValue' -ToolTip 'PowerShell splits an unquoted word at ( ) and $( ); quote the path to complete it.')
    }

    if ($token.Quote -eq '' -and $currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-PathchkCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-PathchkCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-PathchkOptionDescription -Option $option)
                }
            }
        )
    }

    Get-PathchkPathCompletions -InputPath $currentWord -Quote $token.Quote
}

Register-ArgumentCompleter -Native -CommandName 'pathchk', 'pathchk.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pathchk -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
