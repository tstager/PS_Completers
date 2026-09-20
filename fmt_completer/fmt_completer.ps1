# fmt tab completion for PowerShell
# Static option completion for fmt.exe and fmt.

Set-StrictMode -Version 2.0

function Get-FmtCompletionOptions {
    $cache = Get-Variable -Name 'FmtCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-c', '--crown-margin', '-s', '--split-only', '-t', '--tagged-paragraph', '-u', '--uniform-spacing', '-w', '--width', '-h', '--help', '-V', '--version')
    $commandCandidates = @('fmt.exe', 'fmt')
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
        $valueKinds = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
        foreach ($line in ([regex]::Split($helpOutput, '\r?\n'))) {
            # Only option-table rows are harvested; GNU's prose 'The option -WIDTH is an
            # abbreviated form of --width=DIGITS.' otherwise yields a bogus '-WIDTH' option.
            if ($line -notmatch '^\s+-') {
                continue
            }

            # The row's metavariable ('--width=WIDTH', '--width <WIDTH>') tells which options take
            # a value and what kind, so builds with options the static table does not know still
            # get a typed hint instead of filename noise.
            $metavariable = $null
            if ($line -match '(?:^|\s|,)--?[A-Za-z0-9][A-Za-z0-9-]*(?:=| )<?(?<meta>[A-Z][A-Z0-9_-]+)>?(?=\s|$|,)') {
                $metavariable = $Matches['meta']
            }

            foreach ($match in [regex]::Matches($line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|=|\[|$))')) {
                $rawOption = $match.Groups[1].Value
                $normalized = $rawOption.Trim()
                if ($normalized.StartsWith('--')) {
                    $normalized = $normalized -replace '\[.*$', ''
                    $normalized = $normalized -replace '=.*$', ''
                }
                if ($normalized -cmatch '^-[A-Z]{2,}$') {
                    continue
                }
                if ($normalized -match '^-{1,2}[A-Za-z0-9][A-Za-z0-9-]*$') {
                    [void]$options.Add($normalized)
                    if ($metavariable -and -not $valueKinds.ContainsKey($normalized)) {
                        $valueKinds[$normalized] = $metavariable
                    }
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
            Set-Variable -Name 'FmtCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'FmtCompletionDescriptions' -Value $descriptions -Scope Script
            Set-Variable -Name 'FmtCompletionValueKinds' -Value $valueKinds -Scope Script
            return (Get-Variable -Name 'FmtCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'FmtCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'FmtCompletionOptions' -Scope Script).Value
}

function Get-FmtOptionValueKind {
    param([string]$Option)

    [void](Get-FmtCompletionOptions)
    $cache = Get-Variable -Name 'FmtCompletionValueKinds' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    $null
}

function New-FmtCompletionResult {
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

function Remove-FmtOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-FmtQuotedValue {
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

function Get-FmtCurrentToken {
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

function Get-FmtPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-FmtOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-FmtQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-FmtCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-FmtCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-FmtOptionValueCompletions {
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
    $table['-p'] = @(
        @{ Text = '<string>'; Tip = 'Line prefix to reformat.' }
    )
    $table['--prefix'] = @(
        @{ Text = '<string>'; Tip = 'Line prefix to reformat.' }
    )
    $table['-w'] = @(
        @{ Text = '72'; Tip = '72 columns.' }
        @{ Text = '80'; Tip = '80 columns.' }
        @{ Text = '<width>'; Tip = 'Column width.' }
    )
    $table['--width'] = @(
        @{ Text = '72'; Tip = '72 columns.' }
        @{ Text = '80'; Tip = '80 columns.' }
        @{ Text = '<width>'; Tip = 'Column width.' }
    )
    $table['-g'] = @(
        @{ Text = '72'; Tip = '72 columns.' }
        @{ Text = '80'; Tip = '80 columns.' }
        @{ Text = '<width>'; Tip = 'Column width.' }
    )
    $table['--goal'] = @(
        @{ Text = '72'; Tip = '72 columns.' }
        @{ Text = '80'; Tip = '80 columns.' }
        @{ Text = '<width>'; Tip = 'Column width.' }
    )
    if ([string]::IsNullOrEmpty($option)) {
        return @()
    }

    if (-not $table.ContainsKey($option)) {
        # Fall back to the metavariable the live help printed for this option.
        $kind = Get-FmtOptionValueKind -Option $option
        if ([string]::IsNullOrEmpty($kind)) {
            return @()
        }

        $placeholder = '<' + $kind.ToLowerInvariant() + '>'
        $table[$option] = switch -Regex ($kind) {
            '^(WIDTH|GOAL|DIGITS)$' { @(@{ Text = '72'; Tip = '72 columns.' }, @{ Text = '80'; Tip = '80 columns.' }, @{ Text = $placeholder; Tip = 'Column width.' }) }
            '^TABWIDTH$' { @(@{ Text = '4'; Tip = 'Tabs count as 4 columns.' }, @{ Text = '8'; Tip = 'Tabs count as 8 columns (default).' }, @{ Text = $placeholder; Tip = 'Columns per tab when measuring line length.' }) }
            '^FILE$' { 'path' }
            default { @(@{ Text = $placeholder; Tip = ('Value for {0} ({1}).' -f $option, $kind) }) }
        }
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-FmtPathCompletions -InputPath $prefix) {
                New-FmtCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-FmtCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Complete-FmtShortFlagCluster {
    param([string]$CurrentWord)

    # GNU fmt accepts clustered boolean flags ('-csu'); extend a cluster of known value-less short
    # flags with each remaining one.
    if ($CurrentWord -notmatch '^-[A-Za-z]{2,}$') {
        return @()
    }

    $booleanFlags = @(Get-FmtCompletionOptions | Where-Object { $_ -cmatch '^-[A-Za-z]$' -and $_ -cnotin @('-p', '-w', '-g') -and [string]::IsNullOrEmpty((Get-FmtOptionValueKind -Option $_)) })
    $usedLetters = @($CurrentWord.Substring(1).ToCharArray() | ForEach-Object { [string]$_ })
    foreach ($letter in $usedLetters) {
        if (('-' + $letter) -cnotin $booleanFlags) {
            return @()
        }
    }

    @(
        foreach ($flag in $booleanFlags) {
            $letter = $flag.Substring(1)
            if ($letter -cin $usedLetters) {
                continue
            }

            $clustered = $CurrentWord + $letter
            New-FmtCompletionResult -CompletionText $clustered -ListItemText $clustered -ResultType 'ParameterName' -ToolTip ('{0}: {1}' -f $flag, (Get-FmtOptionDescription -Option $flag))
        }
    )
}

function Get-FmtOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'FmtCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for fmt.'
}

function Complete-Fmt {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-FmtCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $optionValues = @(Get-FmtOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return Get-FmtPathCompletions -InputPath ''
    }

    if ($currentWord.StartsWith('-')) {
        # '-72' is the legacy abbreviation of --width=72 ('Usage: fmt [-WIDTH] [OPTION]...').
        if ($currentWord -match '^-[0-9]+$') {
            return @(New-FmtCompletionResult -CompletionText $currentWord -ListItemText $currentWord -ResultType 'ParameterValue' -ToolTip ('Legacy width abbreviation, same as --width=' + $currentWord.Substring(1) + '.'))
        }

        $optionMatches = @(
            foreach ($option in Get-FmtCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-FmtCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-FmtOptionDescription -Option $option)
                }
            }
            if ('-<width>'.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                New-FmtCompletionResult -CompletionText '-<width>' -ListItemText '-<width>' -ResultType 'ParameterValue' -ToolTip 'Legacy numeric abbreviation of --width=N, for example -72.'
            }
        )
        if ($optionMatches.Count -gt 0) {
            return $optionMatches
        }

        return Complete-FmtShortFlagCluster -CurrentWord $currentWord
    }

    Get-FmtPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'fmt', 'fmt.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Fmt -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
