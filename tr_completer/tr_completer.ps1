# tr tab completion for PowerShell
# Static option completion for tr.exe and tr.

Set-StrictMode -Version 2.0

function Get-TrCompletionOptions {
    $cache = Get-Variable -Name 'TrCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-c', '--complement', '-C', '-d', '--delete', '-s', '--squeeze-repeats', '-t', '--truncate-set1', '-h', '--help', '-V', '--version')
    $commandCandidates = @('tr.exe', 'tr')
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
            foreach ($match in [regex]::Matches($line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|=|\[|\]|$))')) {
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
            Set-Variable -Name 'TrCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'TrCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'TrCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'TrCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'TrCompletionOptions' -Scope Script).Value
}


function New-TrCompletionResult {
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

function Remove-TrOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-TrQuotedValue {
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

function Get-TrCurrentToken {
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

function Get-TrPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-TrOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]+$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
        $parent = if ($separatorIndex -ge 0) { $cleanInput.Substring(0, $separatorIndex + 1) } else { '.' }
        $leaf = $cleanInput.Substring($separatorIndex + 1)
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

        $quotedPath = ConvertTo-TrQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-TrCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-TrCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-TrSetVocabulary {
    param([string]$InputWord)

    $quote = if (-not [string]::IsNullOrEmpty($InputWord) -and ($InputWord[0] -eq [char]39 -or $InputWord[0] -eq [char]34)) { [string]$InputWord[0] } else { '' }
    $typed = Remove-TrOuterQuotes -Value $InputWord

    $vocabulary = [ordered]@{
        '[:alnum:]'  = 'Letters and digits'
        '[:alpha:]'  = 'Letters'
        '[:blank:]'  = 'Horizontal whitespace (space and tab)'
        '[:cntrl:]'  = 'Control characters'
        '[:digit:]'  = 'Digits'
        '[:graph:]'  = 'Printable characters, not including space'
        '[:lower:]'  = 'Lowercase letters'
        '[:print:]'  = 'Printable characters, including space'
        '[:punct:]'  = 'Punctuation characters'
        '[:space:]'  = 'Horizontal or vertical whitespace'
        '[:upper:]'  = 'Uppercase letters'
        '[:xdigit:]' = 'Hexadecimal digits'
        '\\'         = 'Backslash'
        '\a'         = 'Audible BEL'
        '\b'         = 'Backspace'
        '\f'         = 'Form feed'
        '\n'         = 'New line'
        '\r'         = 'Return'
        '\t'         = 'Horizontal tab'
        '\v'         = 'Vertical tab'
    }

    if ($typed -match '^\[=(.)=?$') {
        $vocabulary['[=' + $Matches[1] + '=]'] = 'All characters equivalent to ' + $Matches[1]
    } elseif ($typed -match '^\[([^:=])\*(\d*)$') {
        $vocabulary['[' + $Matches[1] + '*' + $Matches[2] + ']'] = if ($Matches[2]) { $Matches[2] + ' copies of ' + $Matches[1] } else { 'Copies of ' + $Matches[1] + ' up to the length of SET1 (SET2 only)' }
    }

    foreach ($entry in $vocabulary.GetEnumerator()) {
        if ($entry.Key.StartsWith($typed, [System.StringComparison]::Ordinal)) {
            New-TrCompletionResult -CompletionText ($quote + $entry.Key + $quote) -ListItemText $entry.Key -ResultType 'ParameterValue' -ToolTip $entry.Value
        }
    }
}

function Test-TrSetOperandSlot {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    # tr takes SET1 alone with -d (and no -s), otherwise SET1 SET2 (SET2 is optional with -s alone).
    # Options end at '--' or at the first operand; long options may be abbreviated.
    $operands = 0
    $delete = $false
    $squeeze = $false
    $endOfOptions = $false
    foreach ($element in @($commandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.EndOffset -ge $cursorPosition) {
            break
        }

        $text = $element.Extent.Text
        if ($endOfOptions -or $operands -gt 0 -or -not $text.StartsWith('-') -or $text -eq '-') {
            $operands++
        } elseif ($text -ceq '--') {
            $endOfOptions = $true
        } elseif ($text.StartsWith('--')) {
            $delete = $delete -or '--delete'.StartsWith($text, [System.StringComparison]::Ordinal)
            $squeeze = $squeeze -or '--squeeze-repeats'.StartsWith($text, [System.StringComparison]::Ordinal)
        } else {
            $delete = $delete -or $text.Contains('d')
            $squeeze = $squeeze -or $text.Contains('s')
        }
    }

    $maxOperands = if ($delete -and -not $squeeze) { 1 } else { 2 }
    $operands -lt $maxOperands
}

function Get-TrOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'TrCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for tr.'
}

function Complete-Tr {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-TrCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $inSetSlot = Test-TrSetOperandSlot -commandAst $commandAst -cursorPosition $cursorPosition
    if ([string]::IsNullOrEmpty($currentWord) -and -not $inSetSlot) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-TrCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-TrCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-TrOptionDescription -Option $option)
                }
            }
        )
    }

    if ($inSetSlot) {
        $setCompletions = @(Get-TrSetVocabulary -InputWord $currentWord)
        if ($setCompletions.Count -gt 0) {
            return $setCompletions
        }
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    Get-TrPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'tr', 'tr.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Tr -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
