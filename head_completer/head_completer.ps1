# head tab completion for PowerShell
# Static option completion for head.exe and head.

Set-StrictMode -Version 2.0

function Get-HeadCompletionOptions {
    $cache = Get-Variable -Name 'HeadCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-c', '--bytes', '-n', '--lines', '-q', '--quiet', '--silent', '-v', '--verbose', '-z', '--zero-terminated', '-h', '--help', '-V', '--version')
    $commandCandidates = @('head.exe', 'head')
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
            Set-Variable -Name 'HeadCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'HeadCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'HeadCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'HeadCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'HeadCompletionOptions' -Scope Script).Value
}


function New-HeadCompletionResult {
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

function Remove-HeadOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    # The word may be an unterminated quote running to the cursor: strip the
    # opening quote, a matching closing one if present, and undo its escaping.
    if ($Value.StartsWith("'")) {
        $inner = $Value.Substring(1)
        if ($inner.EndsWith("'") -and -not $inner.EndsWith("''")) {
            $inner = $inner.Substring(0, $inner.Length - 1)
        }
        return $inner.Replace("''", "'")
    }

    if ($Value.StartsWith('"')) {
        $inner = $Value.Substring(1)
        if ($inner.EndsWith('"') -and -not $inner.EndsWith('`"')) {
            $inner = $inner.Substring(0, $inner.Length - 1)
        }
        return [regex]::Replace($inner, '`(.)', '$1')
    }

    $Value
}

function ConvertTo-HeadQuotedValue {
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (-not $QuoteChar -and $Value -notmatch '[\s{}();,|&<>''"`$]|^[@#]') {
        return $Value
    }

    if ($QuoteChar -eq '"') {
        return '"' + $Value.Replace('`', '``').Replace('"', '`"').Replace('$', '`$') + '"'
    }

    "'" + $Value.Replace("'", "''") + "'"
}

function Get-HeadCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$Fallback
    )

    # Read the word from the parser: an unterminated quote is one element that
    # runs to the cursor, so a quoted fragment with a space stays whole.
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    $Fallback
}

function Get-HeadPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-HeadOuterQuotes -Value $InputPath
    $quoteChar = if ($InputPath.StartsWith('"')) { '"' } elseif ($InputPath.StartsWith("'")) { "'" } else { '' }

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

        $quotedPath = ConvertTo-HeadQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-HeadCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-HeadCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-HeadOptionValueCompletions {
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
    $table['-c'] = @(
        @{ Text = '<num>'; Tip = 'First NUM units.' }
        @{ Text = '-<num>'; Tip = 'All but the last NUM units.' }
    )
    $table['--bytes'] = @(
        @{ Text = '<num>'; Tip = 'First NUM units.' }
        @{ Text = '-<num>'; Tip = 'All but the last NUM units.' }
    )
    $table['-n'] = @(
        @{ Text = '<num>'; Tip = 'First NUM units.' }
        @{ Text = '-<num>'; Tip = 'All but the last NUM units.' }
    )
    $table['--lines'] = @(
        @{ Text = '<num>'; Tip = 'First NUM units.' }
        @{ Text = '-<num>'; Tip = 'All but the last NUM units.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-HeadPathCompletions -InputPath $prefix) {
                New-HeadCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-HeadCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-HeadOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'HeadCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for head.'
}

function Complete-Head {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-HeadCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $optionValues = @(Get-HeadOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-HeadCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-HeadCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-HeadOptionDescription -Option $option)
                }
            }
        )
    }

    Get-HeadPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'head', 'head.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Head -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
