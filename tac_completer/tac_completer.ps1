# tac tab completion for PowerShell
# Static option completion for tac.exe and tac.

Set-StrictMode -Version 2.0

function Get-TacCompletionOptions {
    $cache = Get-Variable -Name 'TacCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--before', '-r', '--regex', '-s', '--separator', '--help', '--version')
    $commandCandidates = @('tac.exe', 'tac')
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
            Set-Variable -Name 'TacCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'TacCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'TacCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'TacCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'TacCompletionOptions' -Scope Script).Value
}

function New-TacCompletionResult {
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

function Get-TacQuoteKind {
    param([string]$Text)

    # PowerShell treats the typographic quotes as quote characters too.
    if ($Text -match '^[''\u2018-\u201B]') {
        return "'"
    }

    if ($Text -match '^["\u201C-\u201E]') {
        return '"'
    }

    ''
}

function ConvertTo-TacQuotedValue {
    param(
        [string]$Value,
        [string]$QuoteChar
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if ($QuoteChar -eq '"') {
        return '"' + ($Value -replace '([`$"\u201C-\u201E])', '`$1') + '"'
    }

    if ($QuoteChar -eq "'" -or $Value -match '[\s{}();,|&<>''"`$\u2018-\u201E]' -or $Value -match '^[@#\-\u2013-\u2015]') {
        return "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Value) + "'"
    }

    $Value
}

function Get-TacCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$Fallback
    )

    foreach ($element in $CommandAst.CommandElements) {
        if ($CursorPosition -le $element.Extent.StartOffset -or $CursorPosition -gt $element.Extent.EndOffset) {
            continue
        }

        $text = $element.Extent.Text.Substring(0, $CursorPosition - $element.Extent.StartOffset)
        $quote = Get-TacQuoteKind -Text $text
        if ([string]::IsNullOrEmpty($quote)) {
            return $text
        }

        if ($CursorPosition -eq $element.Extent.EndOffset) {
            if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                return $quote + $element.Value
            }
            if ($element -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                return $quote + ($element.Value -replace '`(.)', '$1')
            }
        }

        $body = $text.Substring(1)
        if ($quote -eq "'") {
            return $quote + ($body -replace '[''\u2018-\u201B]{2}', "'")
        }

        return $quote + ($body -replace '`(.)', '$1')
    }

    $Fallback
}

function Get-TacPathCompletions {
    param([string]$InputPath)

    $quoteChar = Get-TacQuoteKind -Text $InputPath
    $cleanInput = if ([string]::IsNullOrEmpty($quoteChar)) { $InputPath } else { $InputPath.Substring(1) }

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

    # Keep the directory part exactly as typed (.\, ./, ..\ and the separator style).
    $typedDir = if ($cleanInput -match '^(?<dir>.*[\\/])') { $Matches['dir'] } else { '' }

    foreach ($item in $items) {
        $pathText = if ($typedDir) {
            $typedDir + $item.Name
        } elseif ($parent -eq '.') {
            # A bare leading dash would be parsed as a parameter; anchor it like PowerShell does.
            if ($item.Name -match '^[-\u2013-\u2015]') {
                '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
            } else {
                $item.Name
            }
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-TacQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-TacCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-TacCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-TacOptionValueCompletions {
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
    $table['-s'] = @(
        @{ Text = '<string>'; Tip = 'Record separator.' }
    )
    $table['--separator'] = @(
        @{ Text = '<string>'; Tip = 'Record separator.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-TacPathCompletions -InputPath $prefix) {
                New-TacCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-TacCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-TacOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'TacCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for tac.'
}

function Complete-Tac {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-TacCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition -Fallback $wordToComplete

    $optionValues = @(Get-TacOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-TacCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-TacCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-TacOptionDescription -Option $option)
                }
            }
        )
    }

    Get-TacPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'tac', 'tac.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Tac -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
