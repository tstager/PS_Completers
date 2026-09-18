# stat tab completion for PowerShell
# Static option completion for stat.exe and stat.

Set-StrictMode -Version 2.0

function Get-StatCompletionOptions {
    $cache = Get-Variable -Name 'StatCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-L', '--dereference', '-f', '--file-system', '-t', '--terse', '-c', '--format', '--printf', '-h', '--help', '-V', '--version', '-r', '-s')
    $commandCandidates = @('stat.exe', 'stat')
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
            Set-Variable -Name 'StatCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'StatCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'StatCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'StatCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'StatCompletionOptions' -Scope Script).Value
}


function New-StatCompletionResult {
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

function Remove-StatOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-StatQuotedValue {
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

function Get-StatCurrentToken {
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

function Get-StatPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-StatOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-StatQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-StatCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-StatCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-StatOptionValueCompletions {
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
    $table['--cached'] = @(
        @{ Text = 'always'; Tip = 'Use cached attributes.' }
        @{ Text = 'never'; Tip = 'Never use cached attributes.' }
        @{ Text = 'default'; Tip = 'Let the system decide.' }
    )
    $table['-c'] = @(
        @{ Text = '%n'; Tip = 'File name.' }
        @{ Text = '%s'; Tip = 'Size in bytes.' }
        @{ Text = '%a'; Tip = 'Permission bits in octal.' }
        @{ Text = '%A'; Tip = 'Permission bits, human readable.' }
        @{ Text = '%U'; Tip = 'Owner name.' }
        @{ Text = '%F'; Tip = 'File type.' }
        @{ Text = '%y'; Tip = 'Last modification, human readable.' }
        @{ Text = '%Y'; Tip = 'Last modification, seconds since epoch.' }
        @{ Text = '%i'; Tip = 'Inode number.' }
        @{ Text = '<format>'; Tip = 'Custom stat format.' }
    )
    $table['--format'] = @(
        @{ Text = '%n'; Tip = 'File name.' }
        @{ Text = '%s'; Tip = 'Size in bytes.' }
        @{ Text = '%a'; Tip = 'Permission bits in octal.' }
        @{ Text = '%A'; Tip = 'Permission bits, human readable.' }
        @{ Text = '%U'; Tip = 'Owner name.' }
        @{ Text = '%F'; Tip = 'File type.' }
        @{ Text = '%y'; Tip = 'Last modification, human readable.' }
        @{ Text = '%Y'; Tip = 'Last modification, seconds since epoch.' }
        @{ Text = '%i'; Tip = 'Inode number.' }
        @{ Text = '<format>'; Tip = 'Custom stat format.' }
    )
    $table['--printf'] = @(
        @{ Text = '%n'; Tip = 'File name.' }
        @{ Text = '%s'; Tip = 'Size in bytes.' }
        @{ Text = '%a'; Tip = 'Permission bits in octal.' }
        @{ Text = '%A'; Tip = 'Permission bits, human readable.' }
        @{ Text = '%U'; Tip = 'Owner name.' }
        @{ Text = '%F'; Tip = 'File type.' }
        @{ Text = '%y'; Tip = 'Last modification, human readable.' }
        @{ Text = '%Y'; Tip = 'Last modification, seconds since epoch.' }
        @{ Text = '%i'; Tip = 'Inode number.' }
        @{ Text = '<format>'; Tip = 'Custom stat format.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-StatPathCompletions -InputPath $prefix) {
                New-StatCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-StatCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-StatOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'StatCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for stat.'
}

function Complete-Stat {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-StatCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $optionValues = @(Get-StatOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-StatCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-StatCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-StatOptionDescription -Option $option)
                }
            }
        )
    }

    Get-StatPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'stat', 'stat.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Stat -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
