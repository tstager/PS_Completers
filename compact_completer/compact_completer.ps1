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

function ConvertFrom-CompactTypedWord {
    # The value of a typed word. A word holding a quote (ASCII or typographic, also mid-word) is
    # read by the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ($Value -notmatch '[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    if ($tokens[0] -is [System.Management.Automation.Language.StringToken]) {
        return $tokens[0].Value
    }

    $Value
}

function Get-CompactTypedQuote {
    # The first quote typed in a word (opening or mid-word), or '' when none was typed.
    param([string]$Value)

    $match = [regex]::Match($Value, '[''"\u2018-\u201E]')
    if ($match.Success) { $match.Value } else { '' }
}

function ConvertTo-CompactQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default). PowerShell reads ' and
    # U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes.
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $QuoteChar) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-CompactArgumentState {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The parser keeps an unterminated quoted word as one element running to the cursor.
    $argumentsBeforeCurrent = New-Object System.Collections.Generic.List[string]
    $currentArgument = ''
    foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.EndOffset -lt $CursorPosition) {
            $argumentsBeforeCurrent.Add($extent.Text)
        } elseif ($extent.StartOffset -lt $CursorPosition) {
            $currentArgument = $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = @($argumentsBeforeCurrent)
        CurrentArgument        = $currentArgument
    }
}

function Get-CompactCatalog {
    if (Get-Variable -Name CompactCompletionCatalog -Scope Script -ErrorAction Ignore) {
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

    $match = [regex]::Match($Token, '^(?i)(?<root>/(?:S|EXE|CompactOs|WinDir)):(?<value>.*)$')
    if (-not $match.Success) {
        return $null
    }

    $catalog = Get-CompactCatalog
    $switchKey = ($match.Groups['root'].Value + ':').ToLowerInvariant()
    if (-not $catalog.SwitchLookup.ContainsKey($switchKey)) {
        return $null
    }

    $switch = $catalog.SwitchLookup[$switchKey]
    [pscustomobject]@{
        Prefix = $switch.Token
        Value  = $match.Groups['value'].Value
        Switch = $switch
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

    $typedValue = ConvertFrom-CompactTypedWord -Value $CurrentValue
    $quoteChar = Get-CompactTypedQuote -Value $CurrentValue
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($suggestion in $Suggestions) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $suggestion.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-CompactCompletionResult -CompletionText ($Prefix + $suggestion) -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText ($Prefix + $suggestion)))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentValue)) { $Prefix + $Placeholder } elseif (-not $quoteChar) { $Prefix + $CurrentValue } else { $Prefix + (ConvertTo-CompactQuotedValue -Value $typedValue -QuoteChar $quoteChar) }
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
        [string]$Placeholder,
        [switch]$NoPlaceholder
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $cleanValue = ConvertFrom-CompactTypedWord -Value $typedValue
    $quoteChar = Get-CompactTypedQuote -Value $typedValue
    $results = New-Object System.Collections.Generic.List[object]

    # The typed directory part (.\, ../, sub/, C:) is kept exactly as typed on every candidate.
    $directoryPart = ''
    $separatorIndex = $cleanValue.LastIndexOfAny([char[]]@('\', '/'))
    if ($separatorIndex -ge 0) {
        $directoryPart = $cleanValue.Substring(0, $separatorIndex + 1)
    } elseif ($cleanValue -match '^[A-Za-z]:') {
        $directoryPart = $cleanValue.Substring(0, 2)
    }

    $leaf = $cleanValue.Substring($directoryPart.Length)
    $parentPath = if ($directoryPart) { $directoryPart } else { '.' }
    $separator = if ($directoryPart.EndsWith('/')) { '/' } else { [System.IO.Path]::DirectorySeparatorChar }

    $items = @()
    if (Test-Path -LiteralPath $parentPath -PathType Container -ErrorAction Ignore) {
        $items = @(Get-ChildItem -LiteralPath $parentPath -Force -ErrorAction Ignore)
    }

    foreach ($item in $items) {
        if ($Kind -eq 'Directory' -and -not $item.PSIsContainer) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($leaf) -and
            -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidate = $directoryPart + $item.Name
        # A whole word starting with a dash would parse as a parameter: prefix .\ as PowerShell does.
        if (-not $Prefix -and -not $directoryPart -and $candidate -match '^[-\u2013-\u2015]') {
            $candidate = '.' + $separator + $candidate
        }

        if ($item.PSIsContainer) {
            $candidate += $separator
        }

        $completionText = ConvertTo-CompactQuotedValue -Value $candidate -QuoteChar $quoteChar
        [void]$results.Add((New-CompactCompletionResult -CompletionText ($Prefix + $completionText) -ResultType 'ParameterValue' -ToolTip $item.FullName -ListItemText ($Prefix + $candidate)))
    }

    if ($results.Count -eq 0 -and -not $NoPlaceholder) {
        $fallback = if ([string]::IsNullOrWhiteSpace($typedValue)) { $Prefix + $Placeholder } elseif (-not $quoteChar) { $Prefix + $typedValue } else { $Prefix + (ConvertTo-CompactQuotedValue -Value $cleanValue -QuoteChar $quoteChar) }
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

    $argumentState = Get-CompactArgumentState -CommandAst $commandAst -CursorPosition $cursorPosition
    $currentWord = $argumentState.CurrentArgument
    $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent)

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
        return @(
            Get-CompactSwitchCompletions -CurrentWord $currentWord
            Get-CompactPathCompletions -CurrentValue '' -Prefix '' -Kind 'Any' -ToolTip 'File or directory pattern.' -Placeholder '<path>' -NoPlaceholder
        )
    }

    @(Get-CompactPathCompletions -CurrentValue $currentWord -Prefix '' -Kind 'Any' -ToolTip 'File or directory pattern.' -Placeholder '<path>')
}

Register-ArgumentCompleter -Native -CommandName @('compact', 'compact.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Compact -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
