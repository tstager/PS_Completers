<#
.SYNOPSIS
    Registers a native PowerShell argument completer for compact.

.DESCRIPTION
    Provides a static-first native completer for `compact` and `compact.exe`.

    The completer covers:
    - slash-style switch completion
    - attached value switches such as `/S:`, `/EXE:`, `/CompactOs:`, and `/WinDir:`
    - local file and directory completion for compact operands
    - placeholder-safe enum completion for algorithm and CompactOS value slots

    The script keeps its top level compatible with `Import-CompleterScript`.
#>

Set-StrictMode -Version 2.0

function New-CompactCompletionResult {
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
        $ToolTip = $ListItemText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Remove-CompactOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-CompactQuotedValue {
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

function Get-CompactTokenState {
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

function Get-CompactArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    $tokensBeforeCurrent = @($TokenState.TokensBeforeCurrent)
    $currentArgument = if ($null -eq $TokenState.CurrentToken) { '' } else { $TokenState.CurrentToken }

    if ($tokensBeforeCurrent.Count -gt 0) {
        $argumentsBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip 1)
    } else {
        $argumentsBeforeCurrent = @()
    }

    if ($tokensBeforeCurrent.Count -eq 0 -and $currentArgument -match '^(?i)compact(?:\.exe)?$') {
        $currentArgument = ''
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = $argumentsBeforeCurrent
        CurrentArgument        = $currentArgument
    }
}

function Get-CompactCatalog {
    if (Get-Variable -Name CompactCompletionCatalog -Scope Script -ErrorAction SilentlyContinue) {
        return $script:CompactCompletionCatalog
    }

    $switches = @(
        [pscustomobject]@{ Token = '/C';           Description = 'Compress the specified files.' }
        [pscustomobject]@{ Token = '/U';           Description = 'Uncompress the specified files.' }
        [pscustomobject]@{ Token = '/S';           Description = 'Process the current directory and all subdirectories, or use /S:dir.' }
        [pscustomobject]@{ Token = '/S:';          Description = 'Process the specified directory and all subdirectories.'; ValueKind = 'DirectoryPath' }
        [pscustomobject]@{ Token = '/A';           Description = 'Display files with hidden or system attributes.' }
        [pscustomobject]@{ Token = '/I';           Description = 'Continue even after errors occur.' }
        [pscustomobject]@{ Token = '/F';           Description = 'Force compression of already-compressed files.' }
        [pscustomobject]@{ Token = '/Q';           Description = 'Report only essential information.' }
        [pscustomobject]@{ Token = '/EXE';         Description = 'Use executable-file compression defaults.' }
        [pscustomobject]@{ Token = '/EXE:';        Description = 'Use compression optimized for executable files.'; ValueKind = 'ExeAlgorithm' }
        [pscustomobject]@{ Token = '/CompactOs';   Description = 'Set or query the system Compact state.' }
        [pscustomobject]@{ Token = '/CompactOs:';  Description = 'Set the system Compact state.'; ValueKind = 'CompactOsOption' }
        [pscustomobject]@{ Token = '/WinDir:';     Description = 'Specify the offline Windows directory when querying CompactOS.'; ValueKind = 'DirectoryPath' }
        [pscustomobject]@{ Token = '/?';           Description = 'Show compact help.' }
    )

    $lookup = @{}
    foreach ($switch in $switches) {
        $lookup[$switch.Token.ToLowerInvariant()] = $switch
    }

    $script:CompactCompletionCatalog = [pscustomobject]@{
        Switches         = $switches
        SwitchLookup     = $lookup
        ExeAlgorithms    = @('XPRESS4K', 'XPRESS8K', 'XPRESS16K', 'LZX')
        CompactOsOptions = @('query', 'always', 'never')
    }

    $script:CompactCompletionCatalog
}

function Get-CompactAttachedTokenInfo {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $match = [regex]::Match($Token, '^(?<root>/(?:S|EXE|CompactOs|WinDir)):(?<value>.*)$')
    if (-not $match.Success) {
        return $null
    }

    $catalog = Get-CompactCatalog
    $switchToken = $match.Groups['root'].Value + ':'
    $switchKey = $switchToken.ToLowerInvariant()
    if (-not $catalog.SwitchLookup.ContainsKey($switchKey)) {
        return $null
    }

    [pscustomobject]@{
        Prefix = $switchToken
        Value  = $match.Groups['value'].Value
        Switch = $catalog.SwitchLookup[$switchKey]
    }
}

function Get-CompactSwitchCompletions {
    param([string]$CurrentWord)

    foreach ($switch in (Get-CompactCatalog).Switches) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            -not $switch.Token.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        New-CompactCompletionResult -CompletionText $switch.Token -ResultType 'ParameterName' -ToolTip $switch.Description -ListItemText $switch.Token
    }
}

function Get-CompactPrefixedValueCompletions {
    param(
        [string]$Prefix,
        [string]$CurrentValue,
        [string[]]$Suggestions,
        [string]$ToolTip,
        [string]$Placeholder
    )

    $typedValue = Remove-CompactOuterQuotes -Value $CurrentValue
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($suggestion in $Suggestions) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $suggestion.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-CompactCompletionResult -CompletionText ($Prefix + $suggestion) -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText ($Prefix + $suggestion)))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentValue)) { $Prefix + $Placeholder } else { $Prefix + $CurrentValue }
        [void]$results.Add((New-CompactCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText $fallback))
    }

    @($results.ToArray())
}

function Get-CompactPathCompletions {
    param(
        [string]$CurrentValue,
        [string]$Prefix,
        [ValidateSet('File','Directory','Any')]
        [string]$Kind,
        [string]$ToolTip,
        [string]$Placeholder
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $cleanValue = Remove-CompactOuterQuotes -Value $typedValue
    $alwaysQuote = $typedValue.StartsWith('"')
    $results = New-Object System.Collections.Generic.List[object]

    $parentPath = '.'
    $leaf = ''
    if (-not [string]::IsNullOrWhiteSpace($cleanValue)) {
        if ($cleanValue.EndsWith('\') -or $cleanValue.EndsWith('/')) {
            $parentPath = $cleanValue
        } else {
            try {
                $candidateParent = Split-Path -Path $cleanValue -Parent
            } catch {
                $candidateParent = ''
            }

            if ([string]::IsNullOrWhiteSpace($candidateParent)) {
                $leaf = $cleanValue
            } else {
                $parentPath = $candidateParent
                try {
                    $leaf = Split-Path -Path $cleanValue -Leaf
                } catch {
                    $leaf = $cleanValue
                }
            }
        }
    }

    try {
        $items = @(Get-ChildItem -LiteralPath $parentPath -ErrorAction Stop)
    } catch {
        $items = @()
    }

    foreach ($item in $items) {
        if ($Kind -eq 'Directory' -and -not $item.PSIsContainer) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($leaf) -and
            -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidate = if ($parentPath -eq '.') { $item.Name } else { Join-Path -Path $parentPath -ChildPath $item.Name }
        if ($item.PSIsContainer -and -not ($candidate.EndsWith('\') -or $candidate.EndsWith('/'))) {
            $candidate += '\'
        }

        $completionText = ConvertTo-CompactQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        [void]$results.Add((New-CompactCompletionResult -CompletionText ($Prefix + $completionText) -ResultType 'ParameterValue' -ToolTip $item.FullName -ListItemText ($Prefix + $completionText)))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($typedValue)) { $Prefix + $Placeholder } else { $Prefix + $typedValue }
        [void]$results.Add((New-CompactCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText $fallback))
    }

    @($results.ToArray())
}

function Get-CompactTerminalCompletions {
    param([string]$CurrentWord)

    $completionText = if ([string]::IsNullOrEmpty($CurrentWord)) { ' ' } else { $CurrentWord }
    @(
        New-CompactCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip 'No further arguments are valid after /?.' -ListItemText $completionText
    )
}

function Complete-Compact {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $tokenState = Get-CompactTokenState -Line $commandAst.ToString() -CursorPosition $cursorPosition
    $argumentState = Get-CompactArgumentsFromTokenState -TokenState $tokenState
    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)

    if ($hasTrailingSpace -and -not [string]::IsNullOrEmpty($argumentState.CurrentArgument)) {
        $currentWord = ''
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent + $argumentState.CurrentArgument)
    } else {
        $currentWord = if ($null -eq $argumentState.CurrentArgument) { '' } else { $argumentState.CurrentArgument }
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent)
    }

    $helpRequested = $argumentsBeforeCurrent -contains '/?'
    $catalog = Get-CompactCatalog

    if ($helpRequested) {
        return @(Get-CompactTerminalCompletions -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('/')) {
        $attached = Get-CompactAttachedTokenInfo -Token $currentWord
        if ($null -ne $attached) {
            switch ($attached.Switch.ValueKind) {
                'ExeAlgorithm' {
                    return @(Get-CompactPrefixedValueCompletions -Prefix $attached.Prefix -CurrentValue $attached.Value -Suggestions $catalog.ExeAlgorithms -ToolTip $attached.Switch.Description -Placeholder '<algorithm>')
                }
                'CompactOsOption' {
                    return @(Get-CompactPrefixedValueCompletions -Prefix $attached.Prefix -CurrentValue $attached.Value -Suggestions $catalog.CompactOsOptions -ToolTip $attached.Switch.Description -Placeholder '<option>')
                }
                'DirectoryPath' {
                    return @(Get-CompactPathCompletions -CurrentValue $attached.Value -Prefix $attached.Prefix -Kind 'Directory' -ToolTip $attached.Switch.Description -Placeholder '<dir>')
                }
            }
        }

        return @(Get-CompactSwitchCompletions -CurrentWord $currentWord)
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-CompactSwitchCompletions -CurrentWord $currentWord)
    }

    @(Get-CompactPathCompletions -CurrentValue $currentWord -Prefix '' -Kind 'Any' -ToolTip 'File or directory pattern.' -Placeholder '<path>')
}

Register-ArgumentCompleter -Native -CommandName @('compact', 'compact.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Compact -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
