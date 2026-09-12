# df tab completion for PowerShell
# Static option completion for df.exe and df.

Set-StrictMode -Version 2.0

function Get-DfCompletionOptions {
    $cache = Get-Variable -Name 'DfCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-a', '--all', '-B', '--block-size', '--total', '-h', '--human-readable', '-H', '--si', '-i', '--inodes', '-k', '-l', '--local', '--no-sync', '--output', '-P', '--portability', '--sync', '-t', '--type', '-T', '--print-type', '-w', '-x', '--exclude-type', '-V', '--version', '--help')
    $commandCandidates = @('df.exe', 'df')
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
            Set-Variable -Name 'DfCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'DfCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'DfCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'DfCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'DfCompletionOptions' -Scope Script).Value
}


function New-DfCompletionResult {
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

function Remove-DfOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-DfQuotedValue {
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

function Get-DfCurrentToken {
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

function Get-DfPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-DfOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-DfQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-DfCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-DfCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-DfOptionValueCompletions {
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
    $table['-B'] = @(
        @{ Text = 'K'; Tip = 'Scale sizes by K.' }
        @{ Text = 'M'; Tip = 'Scale sizes by M.' }
        @{ Text = 'G'; Tip = 'Scale sizes by G.' }
        @{ Text = 'T'; Tip = 'Scale sizes by T.' }
        @{ Text = 'KB'; Tip = 'Scale sizes by KB.' }
        @{ Text = 'MB'; Tip = 'Scale sizes by MB.' }
        @{ Text = 'GB'; Tip = 'Scale sizes by GB.' }
        @{ Text = '1K'; Tip = 'Scale sizes by 1K.' }
        @{ Text = '1M'; Tip = 'Scale sizes by 1M.' }
    )
    $table['--block-size'] = @(
        @{ Text = 'K'; Tip = 'Scale sizes by K.' }
        @{ Text = 'M'; Tip = 'Scale sizes by M.' }
        @{ Text = 'G'; Tip = 'Scale sizes by G.' }
        @{ Text = 'T'; Tip = 'Scale sizes by T.' }
        @{ Text = 'KB'; Tip = 'Scale sizes by KB.' }
        @{ Text = 'MB'; Tip = 'Scale sizes by MB.' }
        @{ Text = 'GB'; Tip = 'Scale sizes by GB.' }
        @{ Text = '1K'; Tip = 'Scale sizes by 1K.' }
        @{ Text = '1M'; Tip = 'Scale sizes by 1M.' }
    )
    $table['-t'] = @(
        @{ Text = 'ntfs'; Tip = 'ntfs file system.' }
        @{ Text = 'fat32'; Tip = 'fat32 file system.' }
        @{ Text = 'exfat'; Tip = 'exfat file system.' }
        @{ Text = 'refs'; Tip = 'refs file system.' }
        @{ Text = 'udf'; Tip = 'udf file system.' }
        @{ Text = 'vfat'; Tip = 'vfat file system.' }
    )
    $table['--type'] = @(
        @{ Text = 'ntfs'; Tip = 'ntfs file system.' }
        @{ Text = 'fat32'; Tip = 'fat32 file system.' }
        @{ Text = 'exfat'; Tip = 'exfat file system.' }
        @{ Text = 'refs'; Tip = 'refs file system.' }
        @{ Text = 'udf'; Tip = 'udf file system.' }
        @{ Text = 'vfat'; Tip = 'vfat file system.' }
    )
    $table['-x'] = @(
        @{ Text = 'ntfs'; Tip = 'ntfs file system.' }
        @{ Text = 'fat32'; Tip = 'fat32 file system.' }
        @{ Text = 'exfat'; Tip = 'exfat file system.' }
        @{ Text = 'refs'; Tip = 'refs file system.' }
        @{ Text = 'udf'; Tip = 'udf file system.' }
        @{ Text = 'vfat'; Tip = 'vfat file system.' }
    )
    $table['--exclude-type'] = @(
        @{ Text = 'ntfs'; Tip = 'ntfs file system.' }
        @{ Text = 'fat32'; Tip = 'fat32 file system.' }
        @{ Text = 'exfat'; Tip = 'exfat file system.' }
        @{ Text = 'refs'; Tip = 'refs file system.' }
        @{ Text = 'udf'; Tip = 'udf file system.' }
        @{ Text = 'vfat'; Tip = 'vfat file system.' }
    )
    $table['--output'] = @(
        @{ Text = 'source'; Tip = 'Output field source.' }
        @{ Text = 'fstype'; Tip = 'Output field fstype.' }
        @{ Text = 'itotal'; Tip = 'Output field itotal.' }
        @{ Text = 'iused'; Tip = 'Output field iused.' }
        @{ Text = 'iavail'; Tip = 'Output field iavail.' }
        @{ Text = 'ipcent'; Tip = 'Output field ipcent.' }
        @{ Text = 'size'; Tip = 'Output field size.' }
        @{ Text = 'used'; Tip = 'Output field used.' }
        @{ Text = 'avail'; Tip = 'Output field avail.' }
        @{ Text = 'pcent'; Tip = 'Output field pcent.' }
        @{ Text = 'file'; Tip = 'Output field file.' }
        @{ Text = 'target'; Tip = 'Output field target.' }
    )
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-DfPathCompletions -InputPath $prefix) {
                New-DfCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-DfCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-DfOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'DfCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for df.'
}

function Complete-Df {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-DfCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $optionValues = @(Get-DfOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-DfCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-DfCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-DfOptionDescription -Option $option)
                }
            }
        )
    }

    Get-DfPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'df', 'df.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Df -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
