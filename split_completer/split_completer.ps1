# split tab completion for PowerShell
# Static option completion for split.exe and split.

Set-StrictMode -Version 2.0

function Get-SplitCompletionOptions {
    $cache = Get-Variable -Name 'SplitCompletionOptions' -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--bytes', '-C', '--line-bytes', '-l', '--lines', '-n', '--number', '--additional-suffix', '--filter', '-e', '--elide-empty-files', '-d', '--numeric-suffixes', '-x', '--hex-suffixes', '-a', '--suffix-length', '--verbose', '-t', '--separator', '-h', '--help', '-V', '--version', '-s')
    $commandCandidates = @('split.exe', 'split')
    foreach ($candidate in $commandCandidates) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            continue
        }

        try {
            $helpOutput = $null | & $command.Source --help 2>&1 | Out-String
        } catch {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($helpOutput)) {
            continue
        }

        $options = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
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
                }
            }
        }

        if ($options.Count -gt 0) {
            Set-Variable -Name 'SplitCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            return (Get-Variable -Name 'SplitCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'SplitCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'SplitCompletionOptions' -Scope Script).Value
}


function New-SplitCompletionResult {
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

function Remove-SplitOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-SplitQuotedValue {
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

function Get-SplitCurrentToken {
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

function Get-SplitPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-SplitOuterQuotes -Value $InputPath
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
        } elseif ([System.IO.Path]::IsPathRooted($cleanInput)) {
            Join-Path -Path $parent -ChildPath $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-SplitQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-SplitCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-SplitCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-SplitOptionValueCompletions {
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
    $table['-a'] = @(
        @{ Text = '<n>'; Tip = 'Suffix length.' }
    )
    $table['--suffix-length'] = @(
        @{ Text = '<n>'; Tip = 'Suffix length.' }
    )
    $table['--additional-suffix'] = @(
        @{ Text = '<suffix>'; Tip = 'Extra suffix for file names.' }
    )
    $table['-b'] = @(
        @{ Text = '1K'; Tip = '1K per output file.' }
        @{ Text = '1M'; Tip = '1M per output file.' }
        @{ Text = '10M'; Tip = '10M per output file.' }
        @{ Text = '100M'; Tip = '100M per output file.' }
        @{ Text = '1G'; Tip = '1G per output file.' }
    )
    $table['--bytes'] = @(
        @{ Text = '1K'; Tip = '1K per output file.' }
        @{ Text = '1M'; Tip = '1M per output file.' }
        @{ Text = '10M'; Tip = '10M per output file.' }
        @{ Text = '100M'; Tip = '100M per output file.' }
        @{ Text = '1G'; Tip = '1G per output file.' }
    )
    $table['-C'] = @(
        @{ Text = '1K'; Tip = '1K per output file.' }
        @{ Text = '1M'; Tip = '1M per output file.' }
        @{ Text = '10M'; Tip = '10M per output file.' }
        @{ Text = '100M'; Tip = '100M per output file.' }
        @{ Text = '1G'; Tip = '1G per output file.' }
    )
    $table['--line-bytes'] = @(
        @{ Text = '1K'; Tip = '1K per output file.' }
        @{ Text = '1M'; Tip = '1M per output file.' }
        @{ Text = '10M'; Tip = '10M per output file.' }
        @{ Text = '100M'; Tip = '100M per output file.' }
        @{ Text = '1G'; Tip = '1G per output file.' }
    )
    $table['--numeric-suffixes'] = @(
        @{ Text = '<from>'; Tip = 'Starting suffix value.' }
    )
    $table['--hex-suffixes'] = @(
        @{ Text = '<from>'; Tip = 'Starting suffix value.' }
    )
    $table['--filter'] = @(
        @{ Text = '<command>'; Tip = 'Shell command receiving each chunk.' }
    )
    $table['-l'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['--lines'] = @(
        @{ Text = '<number>'; Tip = 'Numeric value.' }
    )
    $table['-n'] = @(
        @{ Text = '<chunks>'; Tip = 'Number of chunks.' }
        @{ Text = 'l/<n>'; Tip = 'N chunks without splitting lines.' }
        @{ Text = 'r/<n>'; Tip = 'Round-robin distribution into N chunks.' }
    )
    $table['--number'] = @(
        @{ Text = '<chunks>'; Tip = 'Number of chunks.' }
        @{ Text = 'l/<n>'; Tip = 'N chunks without splitting lines.' }
        @{ Text = 'r/<n>'; Tip = 'Round-robin distribution into N chunks.' }
    )
    $table['-t'] = @(
        @{ Text = '<sep>'; Tip = 'Record separator.' }
    )
    $table['--separator'] = @(
        @{ Text = '<sep>'; Tip = 'Record separator.' }
    )
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-SplitPathCompletions -InputPath $prefix) {
                New-SplitCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-SplitCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Complete-Split {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-SplitCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $optionValues = @(Get-SplitOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-SplitCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-SplitCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'Option for split.'
                }
            }
        )
    }

    Get-SplitPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'split', 'split.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Split -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
