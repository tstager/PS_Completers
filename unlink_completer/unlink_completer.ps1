# unlink tab completion for PowerShell
# Static option completion for unlink.exe and unlink.

Set-StrictMode -Version 2.0

function Get-UnlinkCompletionOptions {
    $cache = Get-Variable -Name 'UnlinkCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('--help', '--version')
    $commandCandidates = @('unlink.exe', 'unlink')
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
            Set-Variable -Name 'UnlinkCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'UnlinkCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'UnlinkCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'UnlinkCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'UnlinkCompletionOptions' -Scope Script).Value
}

function New-UnlinkCompletionResult {
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

function Remove-UnlinkOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    # The word may be an unterminated quote running to the cursor, so the closing
    # quote is optional. Undo the quoting PowerShell applies inside each form so a
    # previously accepted quoted completion matches its file again.
    if ($Value.StartsWith("'")) {
        $inner = $Value.Substring(1)
        if ($inner -match "('+)$" -and $Matches[1].Length % 2 -eq 1) {
            $inner = $inner.Substring(0, $inner.Length - 1)
        }

        return $inner.Replace("''", "'")
    }

    if ($Value.StartsWith('"')) {
        $inner = $Value.Substring(1)
        if ($inner -match '^(?:[^`]|`.)*"$') {
            $inner = $inner.Substring(0, $inner.Length - 1)
        }

        return ($inner -replace '`(.)', '$1')
    }

    $Value
}

function ConvertTo-UnlinkQuotedValue {
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    # Whitespace and argument-mode metacharacters would end, split or expand a
    # bare word, so such names are quoted in the user's quote style (single
    # quotes when the user typed none, matching the engine's own path quoting).
    if ($QuoteChar -eq '"') {
        return '"' + ($Value -replace '([`"$])', '`$1') + '"'
    }

    if ($QuoteChar -eq "'" -or $Value -match '[\s{}();,|&<>''"`$]|^[@#]') {
        return "'" + $Value.Replace("'", "''") + "'"
    }

    $Value
}

function Get-UnlinkCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$Fallback
    )

    # The parser keeps an unterminated quote as one element running to the
    # cursor, so the word under the cursor is read from the AST, not by splitting
    # the line on whitespace.
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    # No element under the cursor (it sits in whitespace): the engine's word is empty.
    $Fallback
}

function Get-UnlinkPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-UnlinkOuterQuotes -Value $InputPath
    $quoteChar = if (-not [string]::IsNullOrEmpty($InputPath) -and ($InputPath[0] -eq [char]34 -or $InputPath[0] -eq [char]39)) {
        [string]$InputPath[0]
    } else {
        ''
    }

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

        $quotedPath = ConvertTo-UnlinkQuotedValue -Value $pathText -QuoteChar $quoteChar
        if ($item.PSIsContainer) {
            New-UnlinkCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-UnlinkCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-UnlinkOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'UnlinkCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for unlink.'
}

function Complete-Unlink {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-UnlinkCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-UnlinkCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-UnlinkCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-UnlinkOptionDescription -Option $option)
                }
            }
        )
    }

    Get-UnlinkPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'unlink', 'unlink.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Unlink -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
