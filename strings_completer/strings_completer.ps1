# strings tab completion for PowerShell
# Native completer for Strings with switch-aware numeric hints and path completion.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name StringsCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:StringsCompletionCatalog = @{
        Switches = @(
            [pscustomobject]@{ Token = '-a'; Description = 'Ascii-only search.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-b'; Description = 'Bytes of file to scan.'; TakesValue = $true; ValueKind = 'Bytes' }
            [pscustomobject]@{ Token = '-f'; Description = 'File offset at which to start scanning.'; TakesValue = $true; ValueKind = 'Offset' }
            [pscustomobject]@{ Token = '-n'; Description = 'Minimum string length.'; TakesValue = $true; ValueKind = 'Length' }
            [pscustomobject]@{ Token = '-o'; Description = 'Print offset where the string was located.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-s'; Description = 'Recurse subdirectories.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-u'; Description = 'Unicode-only search.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-?'; Description = 'Show Strings help.'; TakesValue = $false }
            [pscustomobject]@{ Token = '/?'; Description = 'Show Strings help.'; TakesValue = $false }
        )
        ByteHints   = @('256', '512', '1024', '4096', '65536')
        OffsetHints = @('0', '512', '4096', '65536', '0x1000')
        LengthHints = @('3', '4', '8', '16', '32')
    }
}

function New-StringsCompletionResult {
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

function Remove-StringsOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function ConvertTo-StringsQuotedValue {
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

function Get-StringsTokenState {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    if ($null -eq $Line) {
        $Line = ''
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    $tokens = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    $quoteChar = [char]0

    foreach ($character in $prefix.ToCharArray()) {
        if (($character -eq [char]34) -or ($character -eq [char]39)) {
            if ($quoteChar -eq [char]0) {
                $quoteChar = $character
            } elseif ($quoteChar -eq $character) {
                $quoteChar = [char]0
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and $quoteChar -eq [char]0) {
            if ($builder.Length -gt 0) {
                $tokens.Add($builder.ToString())
                [void]$builder.Clear()
            }

            continue
        }

        [void]$builder.Append($character)
    }

    $hasTrailingSpace = $prefix -match '\s$'
    if ($builder.Length -gt 0) {
        $tokens.Add($builder.ToString())
    }

    if ($hasTrailingSpace) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens)
            CurrentToken        = ''
        }
    }

    if ($tokens.Count -gt 0) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
            CurrentToken        = $tokens[$tokens.Count - 1]
        }
    }

    [pscustomobject]@{
        TokensBeforeCurrent = @()
        CurrentToken        = ''
    }
}

function Get-StringsArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    [pscustomobject]@{
        ArgumentsBeforeCurrent = @($TokenState.TokensBeforeCurrent | Select-Object -Skip 1)
        CurrentArgument        = $TokenState.CurrentToken
    }
}

function Get-StringsUniqueCompletions {
    param([object[]]$Results)

    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[object]
    foreach ($result in $Results) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.ContainsKey($result.CompletionText)) {
            continue
        }

        $seen[$result.CompletionText] = $true
        [void]$unique.Add($result)
    }

    @($unique.ToArray())
}

function Get-StringsStaticValueResults {
    param(
        [string]$CurrentWord,
        [string[]]$Values,
        [string]$ToolTip
    )

    $typedValue = Remove-StringsOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $value.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-StringsCompletionResult -CompletionText $value -ListItemText $value -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
            [void]$results.Add((New-StringsCompletionResult -CompletionText '<value>' -ListItemText '<value>' -ResultType 'ParameterValue' -ToolTip $ToolTip))
        } else {
            [void]$results.Add((New-StringsCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip $ToolTip))
        }
    }

    @($results.ToArray())
}

function Get-StringsPathCompletions {
    param(
        [string]$CurrentWord,
        [string]$ToolTip,
        [string]$Placeholder = '<file-or-directory>'
    )

    $typedValue = Remove-StringsOuterQuotes -Value $CurrentWord
    $alwaysQuote = $CurrentWord.StartsWith('"')
    $results = New-Object System.Collections.Generic.List[object]

    $parentPath = '.'
    $leaf = ''
    if (-not [string]::IsNullOrWhiteSpace($typedValue)) {
        if ($typedValue.EndsWith('\') -or $typedValue.EndsWith('/')) {
            $parentPath = $typedValue
        } else {
            $candidateParent = Split-Path -Path $typedValue -Parent
            if ([string]::IsNullOrWhiteSpace($candidateParent)) {
                $leaf = $typedValue
            } else {
                $parentPath = $candidateParent
                $leaf = Split-Path -Path $typedValue -Leaf
            }
        }
    }

    try {
        $items = @(Get-ChildItem -LiteralPath $parentPath -ErrorAction Stop)
    } catch {
        $items = @()
    }

    foreach ($item in $items) {
        if (-not [string]::IsNullOrWhiteSpace($leaf) -and
            -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidate = if ($parentPath -eq '.') { $item.Name } else { Join-Path -Path $parentPath -ChildPath $item.Name }
        if ($item.PSIsContainer) {
            $candidate += '\'
        }

        $completionText = ConvertTo-StringsQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        [void]$results.Add((New-StringsCompletionResult -CompletionText $completionText -ListItemText $completionText -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
            [void]$results.Add((New-StringsCompletionResult -CompletionText $Placeholder -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip))
        } else {
            [void]$results.Add((New-StringsCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip $ToolTip))
        }
    }

    @($results.ToArray())
}

function Get-StringsCommandState {
    param([string[]]$ArgumentsBeforeCurrent)

    $usedTokens = @{}
    $valueContext = $null
    $positionals = New-Object System.Collections.Generic.List[string]

    for ($index = 0; $index -lt $ArgumentsBeforeCurrent.Count; $index++) {
        $token = $ArgumentsBeforeCurrent[$index]
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        $lookup = $token.ToLowerInvariant()
        $usedTokens[$lookup] = $true

        switch ($lookup) {
            '-b' {
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = 'Bytes'
                    break
                }

                $index++
                continue
            }
            '-f' {
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = 'Offset'
                    break
                }

                $index++
                continue
            }
            '-n' {
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = 'Length'
                    break
                }

                $index++
                continue
            }
            default {
                if ($lookup.StartsWith('-') -or $lookup.StartsWith('/')) {
                    continue
                }

                $positionals.Add($token)
            }
        }
    }

    [pscustomobject]@{
        UsedTokens   = $usedTokens
        ValueContext = $valueContext
        Positionals  = @($positionals.ToArray())
    }
}

function Complete-Strings {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $line = if ($CommandAst.Extent -and $null -ne $CommandAst.Extent.Text) { $CommandAst.Extent.Text } else { $CommandAst.ToString() }
    if ($cursorPosition -gt $line.Length) {
        $line = $line.PadRight($cursorPosition)
    }
    $tokenState = Get-StringsTokenState -Line $line -CursorPosition $CursorPosition
    $argumentsState = Get-StringsArgumentsFromTokenState -TokenState $tokenState
    $state = Get-StringsCommandState -ArgumentsBeforeCurrent $argumentsState.ArgumentsBeforeCurrent
    $currentWord = $argumentsState.CurrentArgument

    switch ($state.ValueContext) {
        'Bytes' { return Get-StringsStaticValueResults -CurrentWord $currentWord -Values $script:StringsCompletionCatalog.ByteHints -ToolTip 'Bytes of file to scan.' }
        'Offset' { return Get-StringsStaticValueResults -CurrentWord $currentWord -Values $script:StringsCompletionCatalog.OffsetHints -ToolTip 'File offset at which to start scanning.' }
        'Length' { return Get-StringsStaticValueResults -CurrentWord $currentWord -Values $script:StringsCompletionCatalog.LengthHints -ToolTip 'Minimum string length.' }
    }

    $results = New-Object System.Collections.Generic.List[object]
    $wantsSwitches = [string]::IsNullOrEmpty($currentWord) -or $currentWord.StartsWith('-') -or $currentWord.StartsWith('/')

    if ($wantsSwitches) {
        foreach ($switchSpec in $script:StringsCompletionCatalog.Switches) {
            if (-not $switchSpec.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            if ($state.UsedTokens.ContainsKey($switchSpec.Token.ToLowerInvariant()) -and
                $switchSpec.Token -notin @('-?', '/?')) {
                continue
            }

            [void]$results.Add((New-StringsCompletionResult -CompletionText $switchSpec.Token -ListItemText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description))
        }
    }

    if (-not $currentWord.StartsWith('-') -and -not $currentWord.StartsWith('/')) {
        foreach ($item in (Get-StringsPathCompletions -CurrentWord $currentWord -ToolTip 'File or directory to scan for strings.' -Placeholder '<file-or-directory>')) {
            [void]$results.Add($item)
        }
    }

    Get-StringsUniqueCompletions -Results @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('strings', 'strings.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Strings -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
