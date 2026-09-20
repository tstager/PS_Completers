# join tab completion for PowerShell
# Static option completion for join.exe and join.

Set-StrictMode -Version 2.0

function Get-JoinCompletionOptions {
    $cache = Get-Variable -Name 'JoinCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-a', '-e', '-i', '--ignore-case', '-j', '-o', '-t', '-v', '-1', '-2', '--check-order', '--nocheck-order', '--header', '-z', '--zero-terminated', '-h', '--help', '-V', '--version')
    $commandCandidates = @('join.exe', 'join')
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
            # Only option-table rows are harvested; the GNU trailer 'E.g., use "sort -k 1b,1" ...'
            # otherwise injects a '-k' option join does not have.
            if ($line -notmatch '^\s+-') {
                continue
            }

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
            Set-Variable -Name 'JoinCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'JoinCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'JoinCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'JoinCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'JoinCompletionOptions' -Scope Script).Value
}


function New-JoinCompletionResult {
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

function Remove-JoinOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-JoinQuotedValue {
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

function Get-JoinCurrentToken {
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

    # An unterminated quote ('"my file') is one token, matching what PowerShell hands over.
    $parts = @([regex]::Matches($prefix, '"[^"]*"?|''[^'']*''?|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-JoinPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-JoinOuterQuotes -Value $InputPath
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

        $quotedPath = ConvertTo-JoinQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-JoinCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-JoinCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-JoinOptionValueTable {
    $fields = @(
        @{ Text = '1'; Tip = 'Field 1 (fields are counted from 1).' }
        @{ Text = '2'; Tip = 'Field 2.' }
        @{ Text = '3'; Tip = 'Field 3.' }
        @{ Text = '<field>'; Tip = 'Field number, counted from 1.' }
    )
    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['-a'] = @(
        @{ Text = '1'; Tip = 'Also print unpairable lines from FILE1.' }
        @{ Text = '2'; Tip = 'Also print unpairable lines from FILE2.' }
    )
    $table['-v'] = @(
        @{ Text = '1'; Tip = 'Print only the unpairable lines from FILE1.' }
        @{ Text = '2'; Tip = 'Print only the unpairable lines from FILE2.' }
    )
    $table['-1'] = $fields
    $table['-2'] = $fields
    $table['-j'] = $fields
    $table['-e'] = @(
        @{ Text = '<empty>'; Tip = 'String that replaces missing input fields.' }
    )
    $table['-o'] = @(
        @{ Text = 'auto'; Tip = 'The first line of each file determines the number of output fields.' }
        @{ Text = '0'; Tip = 'The join field.' }
        @{ Text = '<format>'; Tip = 'Comma or blank separated list of FILENUM.FIELD or 0.' }
    )
    $table['-t'] = @(
        @{ Text = ','; Tip = 'Comma field separator.' }
        @{ Text = ';'; Tip = 'Semicolon field separator.' }
        @{ Text = ':'; Tip = 'Colon field separator.' }
        @{ Text = '|'; Tip = 'Pipe field separator.' }
        @{ Text = "`t"; Display = '<tab>'; Quoted = '"`t"'; Tip = 'Tab field separator (PowerShell "`t" escape).' }
        @{ Text = '<char>'; Tip = 'Single character used as the input and output field separator.' }
    )
    $table
}

function Get-JoinOptionValueCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $table = Get-JoinOptionValueTable
    $option = $null
    $prefix = $CurrentWord
    $attached = ''
    if ($CurrentWord -match '^(?<option>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = $Matches['option']
        $prefix = $Matches['value']
        $attached = $option + '='
    } elseif ($CurrentWord -cmatch '^(?<option>-[A-Za-z0-9])(?<value>.+)$' -and $table.ContainsKey($Matches['option'])) {
        # Attached short form ('-a1', '-t,').
        $option = $Matches['option']
        $prefix = $Matches['value']
        $attached = $option
    } elseif (-not $CurrentWord.StartsWith('-') -and $null -ne $TokensBeforeCurrent -and $TokensBeforeCurrent.Count -gt 0) {
        # The option is the token before the cursor, so editing mid-line keeps its value slot.
        $option = $TokensBeforeCurrent[-1]
    }

    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    # A quoted or half-quoted value is matched on its bare text and re-quoted the same way.
    $quote = ''
    if ($prefix.Length -gt 0 -and ($prefix[0] -eq '"' -or $prefix[0] -eq "'")) {
        $quote = [string]$prefix[0]
        $prefix = $prefix.Substring(1)
        if ($prefix.EndsWith($quote)) {
            $prefix = $prefix.Substring(0, $prefix.Length - 1)
        }
    }

    @(
        foreach ($entry in $table[$option]) {
            # A '<placeholder>' describes the empty slot only; once the user types, the concrete
            # candidates are what can match.
            if ($entry.Text -match '^<.*>$') {
                if (-not [string]::IsNullOrEmpty($prefix)) {
                    continue
                }
            } elseif (-not $entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                continue
            }

            $display = if ($entry.ContainsKey('Display')) { $entry.Display } else { $entry.Text }
            $completion = if ($entry.ContainsKey('Quoted')) {
                $entry.Quoted
            } elseif ($quote) {
                $quote + $entry.Text + $quote
            } else {
                $entry.Text
            }

            New-JoinCompletionResult -CompletionText ($attached + $completion) -ListItemText $display -ResultType 'ParameterValue' -ToolTip $entry.Tip
        }
    )
}

function Complete-JoinShortFlagCluster {
    param([string]$CurrentWord)

    # Boolean short flags cluster ('-iz'); extend a cluster of known value-less short flags with
    # each remaining one.
    if ($CurrentWord -notmatch '^-[A-Za-z]{2,}$') {
        return @()
    }

    $valueOptions = Get-JoinOptionValueTable
    $booleanFlags = @(Get-JoinCompletionOptions | Where-Object { $_ -cmatch '^-[A-Za-z]$' -and -not $valueOptions.ContainsKey($_) })
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
            New-JoinCompletionResult -CompletionText $clustered -ListItemText $clustered -ResultType 'ParameterName' -ToolTip ('{0}: {1}' -f $flag, (Get-JoinOptionDescription -Option $flag))
        }
    )
}

function Get-JoinOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'JoinCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for join.'
}

function Complete-Join {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-JoinCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $tokensBeforeCurrent = @(
        foreach ($element in ($commandAst.CommandElements | Select-Object -Skip 1)) {
            if ($element.Extent.EndOffset -lt $cursorPosition) {
                $element.Extent.Text
            }
        }
    )

    $optionValues = @(Get-JoinOptionValueCompletions -TokensBeforeCurrent $tokensBeforeCurrent -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        $optionMatches = @(
            foreach ($option in Get-JoinCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-JoinCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-JoinOptionDescription -Option $option)
                }
            }
        )
        if ($optionMatches.Count -gt 0) {
            return $optionMatches
        }

        return Complete-JoinShortFlagCluster -CurrentWord $currentWord
    }

    Get-JoinPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'join', 'join.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Join -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
