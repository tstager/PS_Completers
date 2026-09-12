# od tab completion for PowerShell
# Static option completion for od.exe and od.

Set-StrictMode -Version 2.0

function Get-OdCompletionOptions {
    $cache = Get-Variable -Name 'OdCompletionOptions' -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-A', '--address-radix', '-j', '--skip-bytes', '-N', '--read-bytes', '-S', '--strings', '-t', '--format', '-v', '--output-duplicates', '-An', '-w', '--width', '-x', '--hex', '-b', '--byte', '-c', '--char', '-d', '--decimal', '-o', '--octal', '-f', '--float', '--help', '--version')
    $commandCandidates = @('od.exe', 'od')
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
            Set-Variable -Name 'OdCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            return (Get-Variable -Name 'OdCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'OdCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'OdCompletionOptions' -Scope Script).Value
}

function New-OdCompletionResult {
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

function Remove-OdOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-OdQuotedValue {
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

function Get-OdCurrentToken {
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

function Get-OdPreviousToken {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    if ($elements.Count -le 1) {
        return $null
    }

    if ([string]::IsNullOrEmpty($CurrentWord)) {
        return $elements[-1]
    }

    if ($elements[-1] -eq $CurrentWord) {
        return $elements[-2]
    }

    return $elements[-1]
}

function Get-OdValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $previousToken = Get-OdPreviousToken -commandAst $commandAst -CurrentWord $CurrentWord
    if ($null -eq $previousToken) {
        return @()
    }

    switch ($previousToken) {
        '--address-radix' { return @(
            New-OdCompletionResult -CompletionText 'd' -ListItemText 'd' -ResultType 'ParameterValue' -ToolTip 'Decimal address radix.'
            New-OdCompletionResult -CompletionText 'o' -ListItemText 'o' -ResultType 'ParameterValue' -ToolTip 'Octal address radix.'
            New-OdCompletionResult -CompletionText 'x' -ListItemText 'x' -ResultType 'ParameterValue' -ToolTip 'Hexadecimal address radix.'
        ) }
        '--format' { return @(
            New-OdCompletionResult -CompletionText 'd' -ListItemText 'd' -ResultType 'ParameterValue' -ToolTip 'Decimal output.'
            New-OdCompletionResult -CompletionText 'o' -ListItemText 'o' -ResultType 'ParameterValue' -ToolTip 'Octal output.'
            New-OdCompletionResult -CompletionText 'x' -ListItemText 'x' -ResultType 'ParameterValue' -ToolTip 'Hex output.'
        ) }
        '--skip-bytes' { return @(
            New-OdCompletionResult -CompletionText '<bytes>' -ListItemText '<bytes>' -ResultType 'ParameterValue' -ToolTip 'Number of bytes to skip.'
        ) }
        '--read-bytes' { return @(
            New-OdCompletionResult -CompletionText '<bytes>' -ListItemText '<bytes>' -ResultType 'ParameterValue' -ToolTip 'Number of bytes to read.'
        ) }
        '--strings' { return @(
            New-OdCompletionResult -CompletionText '<bytes>' -ListItemText '<bytes>' -ResultType 'ParameterValue' -ToolTip 'Minimum string length.'
        ) }
        '--width' { return @(
            New-OdCompletionResult -CompletionText '16' -ListItemText '16' -ResultType 'ParameterValue' -ToolTip '16-byte output width.'
            New-OdCompletionResult -CompletionText '<width>' -ListItemText '<width>' -ResultType 'ParameterValue' -ToolTip 'Output width.'
        ) }
    }

    return @()
}

function Get-OdPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-OdOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-OdQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-OdCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-OdCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-OdOptionValueCompletions {
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
    $table['-A'] = @(
        @{ Text = 'd'; Tip = 'Decimal offsets.' }
        @{ Text = 'o'; Tip = 'Octal offsets.' }
        @{ Text = 'x'; Tip = 'Hexadecimal offsets.' }
        @{ Text = 'n'; Tip = 'No offsets.' }
    )
    $table['--address-radix'] = @(
        @{ Text = 'd'; Tip = 'Decimal offsets.' }
        @{ Text = 'o'; Tip = 'Octal offsets.' }
        @{ Text = 'x'; Tip = 'Hexadecimal offsets.' }
        @{ Text = 'n'; Tip = 'No offsets.' }
    )
    $table['-t'] = @(
        @{ Text = 'a'; Tip = 'Named characters.' }
        @{ Text = 'c'; Tip = 'Printable characters or escapes.' }
        @{ Text = 'd1'; Tip = 'Signed decimal, 1 byte.' }
        @{ Text = 'd2'; Tip = 'Signed decimal, 2 bytes.' }
        @{ Text = 'd4'; Tip = 'Signed decimal, 4 bytes.' }
        @{ Text = 'd8'; Tip = 'Signed decimal, 8 bytes.' }
        @{ Text = 'o1'; Tip = 'Octal, 1 byte.' }
        @{ Text = 'o2'; Tip = 'Octal, 2 bytes.' }
        @{ Text = 'o4'; Tip = 'Octal, 4 bytes.' }
        @{ Text = 'o8'; Tip = 'Octal, 8 bytes.' }
        @{ Text = 'u1'; Tip = 'Unsigned decimal, 1 byte.' }
        @{ Text = 'u2'; Tip = 'Unsigned decimal, 2 bytes.' }
        @{ Text = 'u4'; Tip = 'Unsigned decimal, 4 bytes.' }
        @{ Text = 'u8'; Tip = 'Unsigned decimal, 8 bytes.' }
        @{ Text = 'x1'; Tip = 'Hexadecimal, 1 byte.' }
        @{ Text = 'x2'; Tip = 'Hexadecimal, 2 bytes.' }
        @{ Text = 'x4'; Tip = 'Hexadecimal, 4 bytes.' }
        @{ Text = 'x8'; Tip = 'Hexadecimal, 8 bytes.' }
        @{ Text = 'f4'; Tip = 'Float, 4 bytes.' }
        @{ Text = 'f8'; Tip = 'Float, 8 bytes.' }
    )
    $table['--format'] = @(
        @{ Text = 'a'; Tip = 'Named characters.' }
        @{ Text = 'c'; Tip = 'Printable characters or escapes.' }
        @{ Text = 'd1'; Tip = 'Signed decimal, 1 byte.' }
        @{ Text = 'd2'; Tip = 'Signed decimal, 2 bytes.' }
        @{ Text = 'd4'; Tip = 'Signed decimal, 4 bytes.' }
        @{ Text = 'd8'; Tip = 'Signed decimal, 8 bytes.' }
        @{ Text = 'o1'; Tip = 'Octal, 1 byte.' }
        @{ Text = 'o2'; Tip = 'Octal, 2 bytes.' }
        @{ Text = 'o4'; Tip = 'Octal, 4 bytes.' }
        @{ Text = 'o8'; Tip = 'Octal, 8 bytes.' }
        @{ Text = 'u1'; Tip = 'Unsigned decimal, 1 byte.' }
        @{ Text = 'u2'; Tip = 'Unsigned decimal, 2 bytes.' }
        @{ Text = 'u4'; Tip = 'Unsigned decimal, 4 bytes.' }
        @{ Text = 'u8'; Tip = 'Unsigned decimal, 8 bytes.' }
        @{ Text = 'x1'; Tip = 'Hexadecimal, 1 byte.' }
        @{ Text = 'x2'; Tip = 'Hexadecimal, 2 bytes.' }
        @{ Text = 'x4'; Tip = 'Hexadecimal, 4 bytes.' }
        @{ Text = 'x8'; Tip = 'Hexadecimal, 8 bytes.' }
        @{ Text = 'f4'; Tip = 'Float, 4 bytes.' }
        @{ Text = 'f8'; Tip = 'Float, 8 bytes.' }
    )
    $table['--endian'] = @(
        @{ Text = 'big'; Tip = 'Big-endian input.' }
        @{ Text = 'little'; Tip = 'Little-endian input.' }
    )
    $table['-j'] = @(
        @{ Text = '<bytes>'; Tip = 'Byte count, suffixes like K or M allowed.' }
    )
    $table['--skip-bytes'] = @(
        @{ Text = '<bytes>'; Tip = 'Byte count, suffixes like K or M allowed.' }
    )
    $table['-N'] = @(
        @{ Text = '<bytes>'; Tip = 'Byte count, suffixes like K or M allowed.' }
    )
    $table['--read-bytes'] = @(
        @{ Text = '<bytes>'; Tip = 'Byte count, suffixes like K or M allowed.' }
    )
    $table['-S'] = @(
        @{ Text = '<bytes>'; Tip = 'Byte count, suffixes like K or M allowed.' }
    )
    $table['--strings'] = @(
        @{ Text = '<bytes>'; Tip = 'Byte count, suffixes like K or M allowed.' }
    )
    $table['-w'] = @(
        @{ Text = '16'; Tip = '16 bytes per line.' }
        @{ Text = '32'; Tip = '32 bytes per line.' }
        @{ Text = '<bytes>'; Tip = 'Bytes per output line.' }
    )
    $table['--width'] = @(
        @{ Text = '16'; Tip = '16 bytes per line.' }
        @{ Text = '32'; Tip = '32 bytes per line.' }
        @{ Text = '<bytes>'; Tip = 'Bytes per output line.' }
    )
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-OdPathCompletions -InputPath $prefix) {
                New-OdCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-OdCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Complete-Od {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-OdCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $optionValues = @(Get-OdOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        $valueCompletions = @(Get-OdValueCompletions -commandAst $commandAst -CurrentWord $wordToComplete)
        if ($valueCompletions.Count -gt 0) {
            return $valueCompletions
        }

        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-OdCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-OdCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'Option for od.'
                }
            }
        )
    }

    Get-OdPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'od', 'od.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Od -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
