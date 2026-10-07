# sha1sum tab completion for PowerShell
# Static option completion for sha1sum.exe and sha1sum.

Set-StrictMode -Version 2.0

function Get-Sha1sumCompletionOptions {
    $cache = Get-Variable -Name 'Sha1sumCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--binary', '-c', '--check', '-w', '--warn', '--status', '--quiet', '--strict', '--ignore-missing', '--tag', '-t', '--text', '-z', '--zero', '-h', '--help', '-V', '--version')
    $commandCandidates = @('sha1sum.exe', 'sha1sum')
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
            Set-Variable -Name 'Sha1sumCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'Sha1sumCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'Sha1sumCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'Sha1sumCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'Sha1sumCompletionOptions' -Scope Script).Value
}

function New-Sha1sumCompletionResult {
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

function Remove-Sha1sumOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-Sha1sumQuotedValue {
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

function Get-Sha1sumCurrentToken {
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

function Get-Sha1sumPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-Sha1sumOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-Sha1sumQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-Sha1sumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-Sha1sumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-Sha1sumOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'Sha1sumCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for sha1sum.'
}

function Test-Sha1sumCheckMode {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # True when another word on the line selects verify mode: -c, a short cluster containing c,
    # or --check and its unambiguous abbreviations (--c, --ch, ...). Words after '--' are files.
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($CursorPosition -ge $element.Extent.StartOffset -and $CursorPosition -le $element.Extent.EndOffset) {
            continue
        }

        $text = if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $element.Value } else { $element.Extent.Text }
        if ($text -ceq '--') {
            break
        }

        if (($text -cmatch '^-[A-Za-z]+$' -and $text.Contains('c')) -or ($text.Length -ge 3 -and '--check'.StartsWith($text, [System.StringComparison]::Ordinal))) {
            return $true
        }
    }

    $false
}

function Get-Sha1sumExcludedOptionSet {
    param([bool]$Checking)

    # The tool rejects verify-only options when hashing, and hash-output options when verifying.
    if ($Checking) {
        return @('-c', '--check', '--tag', '-z', '--zero', '-b', '--binary', '-t', '--text')
    }

    @('-w', '--warn', '--status', '--quiet', '--strict', '--ignore-missing')
}

function Complete-Sha1sumShortFlagCluster {
    param(
        [string]$CurrentWord,
        [bool]$Checking
    )

    # Every sha1sum option is a boolean switch, so '-cw' is '-c -w'; extend a cluster of known
    # short flags with each flag not yet in it.
    if ($CurrentWord -notmatch '^-[A-Za-z]{2,}$') {
        return @()
    }

    $shortFlags = @(Get-Sha1sumCompletionOptions | Where-Object { $_ -cmatch '^-[A-Za-z]$' })
    $usedLetters = @($CurrentWord.Substring(1).ToCharArray() | ForEach-Object { [string]$_ })
    foreach ($letter in $usedLetters) {
        if (('-' + $letter) -cnotin $shortFlags) {
            return @()
        }
    }

    $excluded = Get-Sha1sumExcludedOptionSet -Checking ($Checking -or 'c' -cin $usedLetters)
    @(
        foreach ($flag in $shortFlags) {
            $letter = $flag.Substring(1)
            if ($letter -cin $usedLetters -or $flag -cin $excluded) {
                continue
            }

            $clustered = $CurrentWord + $letter
            New-Sha1sumCompletionResult -CompletionText $clustered -ListItemText $clustered -ResultType 'ParameterName' -ToolTip ('{0}: {1}' -f $flag, (Get-Sha1sumOptionDescription -Option $flag))
        }
    )
}

function Complete-Sha1sum {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-Sha1sumCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        $checking = Test-Sha1sumCheckMode -CommandAst $commandAst -CursorPosition $cursorPosition
        $excluded = Get-Sha1sumExcludedOptionSet -Checking $checking
        $optionMatches = @(
            foreach ($option in Get-Sha1sumCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal) -and $option -cnotin $excluded) {
                    New-Sha1sumCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-Sha1sumOptionDescription -Option $option)
                }
            }
        )
        if ($optionMatches.Count -gt 0) {
            return $optionMatches
        }

        return Complete-Sha1sumShortFlagCluster -CurrentWord $currentWord -Checking $checking
    }

    Get-Sha1sumPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'sha1sum', 'sha1sum.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Sha1sum -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
