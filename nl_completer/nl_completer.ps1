# nl tab completion for PowerShell
# Static option completion for nl.exe and nl.

Set-StrictMode -Version 2.0

function Get-NlCompletionOptions {
    $cache = Get-Variable -Name 'NlCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--body-numbering', '-d', '--section-delimiter', '-f', '--footer-numbering', '-h', '--header-numbering', '-i', '--line-increment', '-l', '--join-blank-lines', '-n', '--number-format', '-p', '--no-renumber', '-s', '--number-separator', '-v', '--starting-line-number', '-w', '--number-width', '--help', '--version')
    $commandCandidates = @('nl.exe', 'nl')
    foreach ($candidate in $commandCandidates) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
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
            Set-Variable -Name 'NlCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'NlCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'NlCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'NlCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'NlCompletionOptions' -Scope Script).Value
}

function New-NlCompletionResult {
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

function Remove-NlOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-NlQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        $escaped = $Value.Replace('`', '``').Replace('"', '`"')
        return '"' + $escaped + '"'
    }

    $Value
}

function Get-NlCurrentToken {
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
    if ($prefix -match '\s$') {
        return ''
    }

    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-NlPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-NlOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

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
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-NlQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-NlCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-NlCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-NlOptionValueCompletions {
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

    if ([string]::IsNullOrEmpty($option)) {
        return @()
    }

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['-b'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['--body-numbering'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['-f'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['--footer-numbering'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['-h'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['--header-numbering'] = @(
        @{ Text = 'a'; Tip = 'Number all lines.' }
        @{ Text = 't'; Tip = 'Number only non-empty lines.' }
        @{ Text = 'n'; Tip = 'Number no lines.' }
        @{ Text = 'p<regex>'; Tip = 'Number only lines matching the regex.' }
    )
    $table['-d'] = @(
        @{ Text = '<cc>'; Tip = 'Two-character section delimiter.' }
    )
    $table['--section-delimiter'] = @(
        @{ Text = '<cc>'; Tip = 'Two-character section delimiter.' }
    )
    $table['-i'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--line-increment'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-l'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--join-blank-lines'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-v'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--starting-line-number'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-w'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--number-width'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-n'] = @(
        @{ Text = 'ln'; Tip = 'Left justified, no leading zeros.' }
        @{ Text = 'rn'; Tip = 'Right justified, no leading zeros.' }
        @{ Text = 'rz'; Tip = 'Right justified, leading zeros.' }
    )
    $table['--number-format'] = @(
        @{ Text = 'ln'; Tip = 'Left justified, no leading zeros.' }
        @{ Text = 'rn'; Tip = 'Right justified, no leading zeros.' }
        @{ Text = 'rz'; Tip = 'Right justified, leading zeros.' }
    )
    $table['-s'] = @(
        @{ Text = '<string>'; Tip = 'Text after the line number.' }
    )
    $table['--number-separator'] = @(
        @{ Text = '<string>'; Tip = 'Text after the line number.' }
    )
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-NlPathCompletions -InputPath $prefix) {
                New-NlCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-NlCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-NlOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'NlCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for nl.'
}

function Complete-Nl {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-NlCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $optionValues = @(Get-NlOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return Get-NlPathCompletions -InputPath ''
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-NlCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-NlCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-NlOptionDescription -Option $option)
                }
            }
        )
    }

    Get-NlPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'nl', 'nl.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Nl -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
