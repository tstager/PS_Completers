# dd tab completion for PowerShell
# Static option completion for dd.exe and dd.

Set-StrictMode -Version 2.0

function Get-DdCompletionOptions {
    $cache = Get-Variable -Name 'DdCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('--if=', '--of=', '--bs=', '--ibs=', '--obs=', '--skip=', '--seek=', '--count=', '--conv=', '--status=', '--help', '--version')
    $commandCandidates = @('dd.exe', 'dd')
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
            Set-Variable -Name 'DdCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'DdCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'DdCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'DdCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'DdCompletionOptions' -Scope Script).Value
}

function New-DdCompletionResult {
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

function Remove-DdOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-DdQuotedValue {
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

function Get-DdCurrentToken {
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

function Get-DdPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-DdOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-DdQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-DdCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-DdCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-DdOptionValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $option = $null
    $prefix = $CurrentWord
    $attached = ''
    if ($CurrentWord -match '^(?<option>[A-Za-z]+)=(?<value>.*)$') {
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
    $table['if'] = 'path'
    $table['of'] = 'path'
    $table['bs'] = @(
        @{ Text = '<size>'; Tip = 'Size, suffixes K, M, G accepted.' }
        @{ Text = '1K'; Tip = '1 KiB.' }
        @{ Text = '1M'; Tip = '1 MiB.' }
        @{ Text = '1G'; Tip = '1 GiB.' }
    )
    $table['ibs'] = @(
        @{ Text = '<size>'; Tip = 'Size, suffixes K, M, G accepted.' }
        @{ Text = '1K'; Tip = '1 KiB.' }
        @{ Text = '1M'; Tip = '1 MiB.' }
        @{ Text = '1G'; Tip = '1 GiB.' }
    )
    $table['obs'] = @(
        @{ Text = '<size>'; Tip = 'Size, suffixes K, M, G accepted.' }
        @{ Text = '1K'; Tip = '1 KiB.' }
        @{ Text = '1M'; Tip = '1 MiB.' }
        @{ Text = '1G'; Tip = '1 GiB.' }
    )
    $table['cbs'] = @(
        @{ Text = '<size>'; Tip = 'Size, suffixes K, M, G accepted.' }
        @{ Text = '1K'; Tip = '1 KiB.' }
        @{ Text = '1M'; Tip = '1 MiB.' }
        @{ Text = '1G'; Tip = '1 GiB.' }
    )
    $table['count'] = @(
        @{ Text = '<blocks>'; Tip = 'Number of blocks.' }
    )
    $table['skip'] = @(
        @{ Text = '<blocks>'; Tip = 'Number of blocks.' }
    )
    $table['seek'] = @(
        @{ Text = '<blocks>'; Tip = 'Number of blocks.' }
    )
    $table['conv'] = @(
        @{ Text = 'ascii'; Tip = 'EBCDIC to ASCII.' }
        @{ Text = 'ebcdic'; Tip = 'ASCII to EBCDIC.' }
        @{ Text = 'block'; Tip = 'Pad newline-terminated records.' }
        @{ Text = 'unblock'; Tip = 'Replace trailing spaces with newline.' }
        @{ Text = 'lcase'; Tip = 'Upper to lower case.' }
        @{ Text = 'ucase'; Tip = 'Lower to upper case.' }
        @{ Text = 'sparse'; Tip = 'Seek instead of writing NUL blocks.' }
        @{ Text = 'swab'; Tip = 'Swap every pair of input bytes.' }
        @{ Text = 'sync'; Tip = 'Pad every input block with NULs.' }
        @{ Text = 'excl'; Tip = 'Fail if the output file exists.' }
        @{ Text = 'nocreat'; Tip = 'Do not create the output file.' }
        @{ Text = 'notrunc'; Tip = 'Do not truncate the output file.' }
        @{ Text = 'noerror'; Tip = 'Continue after read errors.' }
        @{ Text = 'fdatasync'; Tip = 'Sync output data before finishing.' }
        @{ Text = 'fsync'; Tip = 'Sync output data and metadata.' }
    )
    $table['iflag'] = @(
        @{ Text = 'append'; Tip = 'Append mode.' }
        @{ Text = 'direct'; Tip = 'Direct I/O.' }
        @{ Text = 'directory'; Tip = 'Fail unless a directory.' }
        @{ Text = 'dsync'; Tip = 'Synchronized data I/O.' }
        @{ Text = 'sync'; Tip = 'Synchronized I/O.' }
        @{ Text = 'fullblock'; Tip = 'Accumulate full input blocks.' }
        @{ Text = 'nonblock'; Tip = 'Non-blocking I/O.' }
        @{ Text = 'noatime'; Tip = 'Do not update access time.' }
        @{ Text = 'nocache'; Tip = 'Request to drop cache.' }
        @{ Text = 'noctty'; Tip = 'Do not assign a controlling terminal.' }
        @{ Text = 'nofollow'; Tip = 'Do not follow symlinks.' }
    )
    $table['oflag'] = @(
        @{ Text = 'append'; Tip = 'Append mode.' }
        @{ Text = 'direct'; Tip = 'Direct I/O.' }
        @{ Text = 'directory'; Tip = 'Fail unless a directory.' }
        @{ Text = 'dsync'; Tip = 'Synchronized data I/O.' }
        @{ Text = 'sync'; Tip = 'Synchronized I/O.' }
        @{ Text = 'fullblock'; Tip = 'Accumulate full input blocks.' }
        @{ Text = 'nonblock'; Tip = 'Non-blocking I/O.' }
        @{ Text = 'noatime'; Tip = 'Do not update access time.' }
        @{ Text = 'nocache'; Tip = 'Request to drop cache.' }
        @{ Text = 'noctty'; Tip = 'Do not assign a controlling terminal.' }
        @{ Text = 'nofollow'; Tip = 'Do not follow symlinks.' }
    )
    $table['status'] = @(
        @{ Text = 'none'; Tip = 'Suppress everything but errors.' }
        @{ Text = 'noxfer'; Tip = 'Suppress transfer statistics.' }
        @{ Text = 'progress'; Tip = 'Show periodic transfer statistics.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        if ($CurrentWord.StartsWith('-')) {
            return @()
        }
        $operands = @(
            @{ Text = 'if='; Tip = 'Input file.' }
            @{ Text = 'of='; Tip = 'Output file.' }
            @{ Text = 'bs='; Tip = 'Block size for both input and output.' }
            @{ Text = 'ibs='; Tip = 'Input block size.' }
            @{ Text = 'obs='; Tip = 'Output block size.' }
            @{ Text = 'cbs='; Tip = 'Conversion block size.' }
            @{ Text = 'count='; Tip = 'Copy only this many input blocks.' }
            @{ Text = 'skip='; Tip = 'Skip input blocks.' }
            @{ Text = 'seek='; Tip = 'Skip output blocks.' }
            @{ Text = 'conv='; Tip = 'Conversion flags.' }
            @{ Text = 'iflag='; Tip = 'Input flags.' }
            @{ Text = 'oflag='; Tip = 'Output flags.' }
            @{ Text = 'status='; Tip = 'Information level.' }
        )
        return @(
            foreach ($entry in $operands) {
                if ($entry.Text.StartsWith($CurrentWord, [System.StringComparison]::Ordinal)) {
                    New-DdCompletionResult -CompletionText $entry.Text -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
                }
            }
        )
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-DdPathCompletions -InputPath $prefix) {
                New-DdCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-DdCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-DdOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'DdCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for dd.'
}

function Complete-Dd {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-DdCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $optionValues = @(Get-DdOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-DdCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-DdCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-DdOptionDescription -Option $option)
                }
            }
        )
    }

    Get-DdPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'dd', 'dd.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Dd -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
