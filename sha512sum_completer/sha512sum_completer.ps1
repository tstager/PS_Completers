# sha512sum tab completion for PowerShell
# Static option completion for sha512sum.exe and sha512sum.

Set-StrictMode -Version 2.0

function Get-Sha512sumCompletionOptions {
    $cache = Get-Variable -Name 'Sha512sumCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--binary', '-c', '--check', '-w', '--warn', '--status', '--quiet', '--strict', '--ignore-missing', '--tag', '-t', '--text', '-z', '--zero', '-h', '--help', '-V', '--version')
    $commandCandidates = @('sha512sum.exe', 'sha512sum')
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
            Set-Variable -Name 'Sha512sumCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'Sha512sumCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'Sha512sumCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'Sha512sumCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'Sha512sumCompletionOptions' -Scope Script).Value
}

function New-Sha512sumCompletionResult {
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

function Remove-Sha512sumOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-Sha512sumQuotedValue {
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

function Get-Sha512sumCurrentToken {
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

function Get-Sha512sumPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-Sha512sumOuterQuotes -Value $InputPath
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

    $items = @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue)
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

        $quotedPath = ConvertTo-Sha512sumQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-Sha512sumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-Sha512sumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Complete-Sha512sumOperand {
    param(
        [string]$CurrentWord,
        [string[]]$TokensBeforeCurrent
    )

    # An unquoted path with spaces ('C:\Program Files\cor') reaches the completer as the last
    # whitespace-split piece. Re-join it with the operand tokens typed before it until a parent
    # directory exists, and emit only the piece PowerShell will replace.
    $head = ''
    $inputPath = $CurrentWord
    if (-not ($CurrentWord.StartsWith('"') -or $CurrentWord.StartsWith("'"))) {
        $operands = @($TokensBeforeCurrent | Where-Object { -not $_.StartsWith('-') -and -not $_.Contains('"') -and -not $_.Contains("'") })
        $joined = $CurrentWord
        $joinedHead = ''
        for ($i = $operands.Count - 1; $i -ge [Math]::Max(0, $operands.Count - 3); $i--) {
            $joinedHead = $operands[$i] + ' ' + $joinedHead
            $joined = $operands[$i] + ' ' + $joined
            $parent = if ($joined -match '[\\/]+$') { $joined } else { Split-Path -Path $joined -Parent }
            if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-Path -LiteralPath $parent -PathType Container)) {
                $head = $joinedHead
                $inputPath = $joined
                break
            }
        }
    }

    $results = @(Get-Sha512sumPathCompletions -InputPath $inputPath)
    if ($head) {
        # The line is unquoted, so the emitted piece stays unquoted too (ListItemText is the bare path).
        $results = @(
            foreach ($result in $results) {
                if ($result.ListItemText.StartsWith($head, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-Sha512sumCompletionResult -CompletionText $result.ListItemText.Substring($head.Length) -ListItemText $result.ListItemText -ResultType $result.ResultType -ToolTip $result.ToolTip
                }
            }
        )
    }

    # After -c/--check (or a cluster containing c) the operand is a checksum manifest, so
    # manifest-shaped files are listed first.
    $checking = $false
    foreach ($token in $TokensBeforeCurrent) {
        if ($token -ceq '--check' -or ($token -cmatch '^-[A-Za-z]+$' -and $token.Contains('c'))) {
            $checking = $true
        }
    }

    if (-not $checking) {
        return $results
    }

    $manifests = [System.Collections.Generic.List[object]]::new()
    $others = [System.Collections.Generic.List[object]]::new()
    foreach ($result in $results) {
        if ($result.ResultType -eq 'ProviderItem' -and $result.ListItemText -match '(?i)(^|[\\/])(SHA512SUMS?|CHECKSUMS?(\.txt)?|[^\\/]*\.(sha512|sha512sum|sha|sum|sums|txt))$') {
            $manifests.Add((New-Sha512sumCompletionResult -CompletionText $result.CompletionText -ListItemText $result.ListItemText -ResultType $result.ResultType -ToolTip ('Checksum manifest to verify: ' + $result.ToolTip)))
        } else {
            $others.Add($result)
        }
    }

    @($manifests.ToArray() + $others.ToArray())
}

function Complete-Sha512sumShortFlagCluster {
    param([string]$CurrentWord)

    # Every sha512sum option is a boolean switch, so '-cw' is '-c -w'; extend a cluster of known
    # short flags with each flag not yet in it.
    if ($CurrentWord -notmatch '^-[A-Za-z]{2,}$') {
        return @()
    }

    $shortFlags = @(Get-Sha512sumCompletionOptions | Where-Object { $_ -cmatch '^-[A-Za-z]$' })
    $usedLetters = @($CurrentWord.Substring(1).ToCharArray() | ForEach-Object { [string]$_ })
    foreach ($letter in $usedLetters) {
        if (('-' + $letter) -cnotin $shortFlags) {
            return @()
        }
    }

    @(
        foreach ($flag in $shortFlags) {
            $letter = $flag.Substring(1)
            if ($letter -cin $usedLetters) {
                continue
            }

            $clustered = $CurrentWord + $letter
            New-Sha512sumCompletionResult -CompletionText $clustered -ListItemText $clustered -ResultType 'ParameterName' -ToolTip ('{0}: {1}' -f $flag, (Get-Sha512sumOptionDescription -Option $flag))
        }
    )
}

function Get-Sha512sumOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'Sha512sumCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for sha512sum.'
}

function Complete-Sha512sum {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-Sha512sumCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $tokensBeforeCurrent = @(
        foreach ($element in ($commandAst.CommandElements | Select-Object -Skip 1)) {
            if ($element.Extent.EndOffset -lt $cursorPosition) {
                $element.Extent.Text
            }
        }
    )

    if ([string]::IsNullOrEmpty($currentWord)) {
        $checking = @($tokensBeforeCurrent | Where-Object { $_ -ceq '--check' -or ($_ -cmatch '^-[A-Za-z]+$' -and $_.Contains('c')) }).Count -gt 0
        if ($checking) {
            return Complete-Sha512sumOperand -CurrentWord '' -TokensBeforeCurrent $tokensBeforeCurrent
        }

        return @()
    }

    if ($currentWord.StartsWith('-')) {
        $optionMatches = @(
            foreach ($option in Get-Sha512sumCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-Sha512sumCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-Sha512sumOptionDescription -Option $option)
                }
            }
        )
        if ($optionMatches.Count -gt 0) {
            return $optionMatches
        }

        return Complete-Sha512sumShortFlagCluster -CurrentWord $currentWord
    }

    Complete-Sha512sumOperand -CurrentWord $currentWord -TokensBeforeCurrent $tokensBeforeCurrent
}

Register-ArgumentCompleter -Native -CommandName 'sha512sum', 'sha512sum.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Sha512sum -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
