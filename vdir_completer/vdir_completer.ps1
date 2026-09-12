# vdir tab completion for PowerShell
# Static option completion for vdir.exe and vdir.

Set-StrictMode -Version 2.0

function Get-VdirCompletionOptions {
    $cache = Get-Variable -Name 'VdirCompletionOptions' -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-a', '--all', '-A', '--almost-all', '--author', '-b', '--escape', '-B', '--ignore-backups', '-c', '-C', '--color', '-d', '--directory', '-f', '-F', '--classify', '--file-type', '--format', '-g', '-G', '-h', '--human-readable', '-i', '--inode', '-l', '-m', '-n', '-N', '--literal', '-o', '-p', '-q', '--hide-control-chars', '-Q', '--quote-name', '-r', '--reverse', '-R', '--recursive', '-s', '--size', '-S', '--sort=size', '-t', '--sort=time', '-u', '--sort=access', '-U', '--sort=none', '-X', '--sort=extension', '-1', '--format=single-column', '--help', '--version')
    $commandCandidates = @('vdir.exe', 'vdir')
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
            Set-Variable -Name 'VdirCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            return (Get-Variable -Name 'VdirCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'VdirCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'VdirCompletionOptions' -Scope Script).Value
}

function New-VdirCompletionResult {
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

function Remove-VdirOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-VdirQuotedValue {
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

function Get-VdirCurrentToken {
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

function Get-VdirPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-VdirOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-VdirQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-VdirCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-VdirCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-VdirOptionValueCompletions {
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
    $table['--block-size'] = @(
        @{ Text = 'K'; Tip = 'Scale sizes by K.' }
        @{ Text = 'M'; Tip = 'Scale sizes by M.' }
        @{ Text = 'G'; Tip = 'Scale sizes by G.' }
        @{ Text = 'KB'; Tip = 'Scale sizes by KB.' }
        @{ Text = 'MB'; Tip = 'Scale sizes by MB.' }
        @{ Text = 'GB'; Tip = 'Scale sizes by GB.' }
    )
    $table['--color'] = @(
        @{ Text = 'always'; Tip = 'Always.' }
        @{ Text = 'auto'; Tip = 'Only on a terminal.' }
        @{ Text = 'never'; Tip = 'Never.' }
    )
    $table['--hyperlink'] = @(
        @{ Text = 'always'; Tip = 'Always.' }
        @{ Text = 'auto'; Tip = 'Only on a terminal.' }
        @{ Text = 'never'; Tip = 'Never.' }
    )
    $table['--format'] = @(
        @{ Text = 'across'; Tip = 'Entries across, like -x.' }
        @{ Text = 'commas'; Tip = 'Comma separated, like -m.' }
        @{ Text = 'horizontal'; Tip = 'Entries across, like -x.' }
        @{ Text = 'long'; Tip = 'Long listing, like -l.' }
        @{ Text = 'single-column'; Tip = 'One entry per line, like -1.' }
        @{ Text = 'verbose'; Tip = 'Long listing, like -l.' }
        @{ Text = 'vertical'; Tip = 'Entries down columns, like -C.' }
    )
    $table['--hide'] = @(
        @{ Text = '<pattern>'; Tip = 'Shell pattern.' }
    )
    $table['-I'] = @(
        @{ Text = '<pattern>'; Tip = 'Shell pattern.' }
    )
    $table['--ignore'] = @(
        @{ Text = '<pattern>'; Tip = 'Shell pattern.' }
    )
    $table['--indicator-style'] = @(
        @{ Text = 'none'; Tip = 'No indicator.' }
        @{ Text = 'slash'; Tip = 'Slash after directories, like -p.' }
        @{ Text = 'file-type'; Tip = 'Indicator for each file type.' }
        @{ Text = 'classify'; Tip = 'Indicator for each entry, like -F.' }
    )
    $table['--quoting-style'] = @(
        @{ Text = 'literal'; Tip = 'literal quoting.' }
        @{ Text = 'locale'; Tip = 'locale quoting.' }
        @{ Text = 'shell'; Tip = 'shell quoting.' }
        @{ Text = 'shell-always'; Tip = 'shell-always quoting.' }
        @{ Text = 'shell-escape'; Tip = 'shell-escape quoting.' }
        @{ Text = 'shell-escape-always'; Tip = 'shell-escape-always quoting.' }
        @{ Text = 'c'; Tip = 'c quoting.' }
        @{ Text = 'escape'; Tip = 'escape quoting.' }
    )
    $table['--sort'] = @(
        @{ Text = 'none'; Tip = 'Directory order, like -U.' }
        @{ Text = 'size'; Tip = 'By size, like -S.' }
        @{ Text = 'time'; Tip = 'By time, like -t.' }
        @{ Text = 'version'; Tip = 'By version, like -v.' }
        @{ Text = 'extension'; Tip = 'By extension, like -X.' }
        @{ Text = 'width'; Tip = 'By width.' }
    )
    $table['--time'] = @(
        @{ Text = 'atime'; Tip = 'Access time.' }
        @{ Text = 'access'; Tip = 'Access time.' }
        @{ Text = 'use'; Tip = 'Access time.' }
        @{ Text = 'ctime'; Tip = 'Change time.' }
        @{ Text = 'status'; Tip = 'Change time.' }
        @{ Text = 'birth'; Tip = 'Creation time.' }
        @{ Text = 'creation'; Tip = 'Creation time.' }
    )
    $table['--time-style'] = @(
        @{ Text = 'full-iso'; Tip = 'Full ISO 8601.' }
        @{ Text = 'long-iso'; Tip = 'Long ISO 8601.' }
        @{ Text = 'iso'; Tip = 'Short ISO 8601.' }
        @{ Text = 'locale'; Tip = 'Locale format.' }
    )
    $table['-T'] = @(
        @{ Text = '<cols>'; Tip = 'Column count.' }
    )
    $table['--tabsize'] = @(
        @{ Text = '<cols>'; Tip = 'Column count.' }
    )
    $table['-w'] = @(
        @{ Text = '<cols>'; Tip = 'Column count.' }
    )
    $table['--width'] = @(
        @{ Text = '<cols>'; Tip = 'Column count.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-VdirPathCompletions -InputPath $prefix) {
                New-VdirCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-VdirCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Complete-Vdir {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-VdirCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $optionValues = @(Get-VdirOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-VdirCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-VdirCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'Option for vdir.'
                }
            }
        )
    }

    Get-VdirPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'vdir', 'vdir.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Vdir -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
