<#
.SYNOPSIS
    Registers a native PowerShell argument completer for findstr.

.DESCRIPTION
    Provides a static-first native completer for `findstr` and `findstr.exe`.

    The completer covers:
    - slash-style switch completion from the built-in help surface
    - attached value switches such as `/A:`, `/C:`, `/D:`, `/F:`, `/G:`, and `/Q:`
    - placeholder-driven search-string completion to suppress unwanted filesystem fallback
    - local path completion for filename operands, file-list values, pattern-file values, and directory lists
    - conservative handling of the ambiguous bare `search-string` vs `filename` boundary

    The script keeps its top level compatible with `Import-CompleterScript`.
#>

Set-StrictMode -Version Latest

function New-FindStrCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
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

function New-FindStrSwitchSpec {
    param(
        [string]$Token,
        [string]$Description,
        [string]$ValueKind
    )

    [pscustomobject]@{
        Token       = $Token
        Key         = $Token.ToLowerInvariant()
        Description = $Description
        ValueKind   = $ValueKind
        TakesValue  = -not [string]::IsNullOrWhiteSpace($ValueKind)
    }
}

function Get-FindStrCompletionCatalog {
    if (Get-Variable -Name FindStrCompletionCatalog -Scope Script -ErrorAction SilentlyContinue) {
        return $script:FindStrCompletionCatalog
    }

    $switches = @(
        New-FindStrSwitchSpec -Token '/B' -Description 'Matches pattern if at the beginning of a line.'
        New-FindStrSwitchSpec -Token '/E' -Description 'Matches pattern if at the end of a line.'
        New-FindStrSwitchSpec -Token '/L' -Description 'Uses search strings literally.'
        New-FindStrSwitchSpec -Token '/R' -Description 'Uses search strings as regular expressions.'
        New-FindStrSwitchSpec -Token '/S' -Description 'Searches for matching files in the current directory and all subdirectories.'
        New-FindStrSwitchSpec -Token '/I' -Description 'Specifies that the search is not case-sensitive.'
        New-FindStrSwitchSpec -Token '/X' -Description 'Prints lines that match exactly.'
        New-FindStrSwitchSpec -Token '/V' -Description 'Prints only lines that do not contain a match.'
        New-FindStrSwitchSpec -Token '/N' -Description 'Prints the line number before each line that matches.'
        New-FindStrSwitchSpec -Token '/M' -Description 'Prints only the filename if a file contains a match.'
        New-FindStrSwitchSpec -Token '/O' -Description 'Prints character offset before each matching line.'
        New-FindStrSwitchSpec -Token '/P' -Description 'Skips files with non-printable characters.'
        New-FindStrSwitchSpec -Token '/A:' -Description 'Specifies color attribute with two hex digits. See color /?.' -ValueKind 'ColorAttr'
        New-FindStrSwitchSpec -Token '/F:' -Description 'Reads the file list from the specified file, or / for console input.' -ValueKind 'FileListPathOrConsole'
        New-FindStrSwitchSpec -Token '/C:' -Description 'Uses the specified string as a literal search string.' -ValueKind 'SearchString'
        New-FindStrSwitchSpec -Token '/G:' -Description 'Gets search strings from the specified file, or / for console input.' -ValueKind 'PatternFilePathOrConsole'
        New-FindStrSwitchSpec -Token '/D:' -Description 'Searches a semicolon-delimited list of directories.' -ValueKind 'DirectoryList'
        New-FindStrSwitchSpec -Token '/Q:' -Description 'Quiet mode flags. Currently supports u to suppress unsupported-Unicode warnings.' -ValueKind 'QuietFlags'
        New-FindStrSwitchSpec -Token '/OFF' -Description 'Does not skip files with the offline attribute set.'
        New-FindStrSwitchSpec -Token '/OFFLINE' -Description 'Does not skip files with the offline attribute set.'
        New-FindStrSwitchSpec -Token '/?' -Description 'Displays help for findstr.'
    )

    $switchLookup = @{}
    $attachedValueLookup = @{}
    foreach ($switch in $switches) {
        $switchLookup[$switch.Key] = $switch
        if ($switch.TakesValue) {
            $attachedValueLookup[$switch.Key.TrimEnd(':')] = $switch
        }
    }

    $script:FindStrCompletionCatalog = [pscustomobject]@{
        Switches            = $switches
        SwitchLookup        = $switchLookup
        AttachedValueLookup = $attachedValueLookup
        ColorHints          = @('07', '0A', '0C', '0E', '1F', '2F', '4F', '70')
        QuietFlags          = @('u')
    }

    $script:FindStrCompletionCatalog
}

function Remove-FindStrOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function ConvertTo-FindStrQuotedValue {
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

function Get-FindStrTokenState {
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

function Get-FindStrArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    $tokensBeforeCurrent = @($TokenState.TokensBeforeCurrent)
    $currentArgument = if ($null -eq $TokenState.CurrentToken) { '' } else { $TokenState.CurrentToken }

    if ($tokensBeforeCurrent.Count -gt 0) {
        $argumentsBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip 1)
    } else {
        $argumentsBeforeCurrent = @()
    }

    if ($tokensBeforeCurrent.Count -eq 0 -and $currentArgument -match '^(?i)findstr(?:\.exe)?$') {
        $currentArgument = ''
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = $argumentsBeforeCurrent
        CurrentArgument        = $currentArgument
    }
}

function Get-FindStrAttachedTokenInfo {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $match = [regex]::Match($Token, '^(?<root>/[A-Za-z?][A-Za-z0-9-]*):(?<value>.*)$')
    if (-not $match.Success) {
        return $null
    }

    $catalog = Get-FindStrCompletionCatalog
    $rootKey = $match.Groups['root'].Value.ToLowerInvariant()
    if (-not $catalog.AttachedValueLookup.ContainsKey($rootKey)) {
        return $null
    }

    [pscustomobject]@{
        RootKey = $rootKey
        Prefix  = $match.Groups['root'].Value + ':'
        Value   = $match.Groups['value'].Value
        Switch  = $catalog.AttachedValueLookup[$rootKey]
    }
}

function Get-FindStrCompletionContext {
    param([string[]]$ArgumentsBeforeCurrent)

    $catalog = Get-FindStrCompletionCatalog
    $helpRequested = $false
    $hasExplicitSearchSource = $false
    $bareSearchCount = 0
    $inFilenameMode = $false

    foreach ($argument in @($ArgumentsBeforeCurrent)) {
        if ([string]::IsNullOrWhiteSpace($argument)) {
            continue
        }

        $attachedInfo = Get-FindStrAttachedTokenInfo -Token $argument
        if ($null -ne $attachedInfo) {
            switch ($attachedInfo.RootKey) {
                '/c' { $hasExplicitSearchSource = $true }
                '/g' { $hasExplicitSearchSource = $true }
            }

            continue
        }

        $argumentKey = $argument.ToLowerInvariant()
        if ($catalog.SwitchLookup.ContainsKey($argumentKey)) {
            if ($argumentKey -eq '/?') {
                $helpRequested = $true
            }

            continue
        }

        if ($hasExplicitSearchSource) {
            $inFilenameMode = $true
            continue
        }

        if ($bareSearchCount -eq 0) {
            $bareSearchCount = 1
            continue
        }

        $inFilenameMode = $true
    }

    [pscustomobject]@{
        HelpRequested           = $helpRequested
        HasExplicitSearchSource = $hasExplicitSearchSource
        BareSearchCount         = $bareSearchCount
        HasBareSearchStrings    = $bareSearchCount -gt 0
        InFilenameMode          = $inFilenameMode
    }
}

function Get-FindStrUniqueCompletions {
    param([object[]]$Results)

    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[object]

    foreach ($result in @($Results)) {
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

function Get-FindStrSwitchCompletions {
    param([string]$CurrentWord)

    $catalog = Get-FindStrCompletionCatalog
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($switch in $catalog.Switches) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            -not $switch.Token.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-FindStrCompletionResult -CompletionText $switch.Token -ResultType 'ParameterName' -ToolTip $switch.Description))
    }

    @($results.ToArray())
}

function Get-FindStrPrefixedValueCompletions {
    param(
        [string]$Prefix,
        [string]$CurrentValue,
        [string[]]$Suggestions,
        [string]$ToolTip,
        [string]$Placeholder
    )

    $typedValue = Remove-FindStrOuterQuotes -Value $CurrentValue
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($suggestion in @($Suggestions)) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $suggestion.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + $suggestion) -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
            [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + $Placeholder) -ResultType 'ParameterValue' -ToolTip $ToolTip))
        } else {
            [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + $CurrentValue) -ResultType 'ParameterValue' -ToolTip $ToolTip))
        }
    }

    @($results.ToArray())
}

function Get-FindStrSearchStringCompletions {
    param(
        [string]$CurrentValue,
        [string]$Prefix = ''
    )

    $results = New-Object System.Collections.Generic.List[object]
    $toolTip = if ([string]::IsNullOrEmpty($Prefix)) {
        'Search string.'
    } else {
        'Literal search string.'
    }

    if ([string]::IsNullOrEmpty($CurrentValue)) {
        [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + '<search-string>') -ResultType 'ParameterValue' -ToolTip $toolTip))
        if (-not [string]::IsNullOrEmpty($Prefix)) {
            [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + '"<search-string>"') -ResultType 'ParameterValue' -ToolTip $toolTip))
        }

        return @($results.ToArray())
    }

    if ($CurrentValue -eq '"') {
        [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + '"<search-string>"') -ResultType 'ParameterValue' -ToolTip $toolTip))
        return @($results.ToArray())
    }

    @(
        New-FindStrCompletionResult -CompletionText ($Prefix + $CurrentValue) -ResultType 'ParameterValue' -ToolTip $toolTip
    )
}

function Get-FindStrPathCompletions {
    param(
        [string]$CurrentValue,
        [string]$Prefix = '',
        [ValidateSet('File', 'Directory', 'Any')]
        [string]$Kind = 'Any',
        [string]$ToolTip = 'Path value.',
        [string]$Placeholder = '<path>',
        [bool]$AllowConsoleSentinel = $false,
        [bool]$HasOpenQuotePrefix = $false
    )

    $results = New-Object System.Collections.Generic.List[object]
    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $cleanValue = Remove-FindStrOuterQuotes -Value $typedValue
    $alwaysQuote = -not $HasOpenQuotePrefix -and $typedValue.StartsWith('"')

    if ($AllowConsoleSentinel) {
        if ([string]::IsNullOrWhiteSpace($cleanValue) -or '/'.StartsWith($cleanValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + '/') -ResultType 'ParameterValue' -ToolTip 'Read this value from console input.'))
        }
    }

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
        if (-not [string]::IsNullOrWhiteSpace($leaf) -and
            -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ($Kind -eq 'Directory' -and -not $item.PSIsContainer) {
            continue
        }

        $candidate = if ($parentPath -eq '.') {
            $item.Name
        } else {
            Join-Path -Path $parentPath -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not ($candidate.EndsWith('\') -or $candidate.EndsWith('/'))) {
            $candidate += '\'
        }

        $completionText = if ($HasOpenQuotePrefix) {
            $candidate
        } else {
            ConvertTo-FindStrQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        }

        [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + $completionText) -ResultType 'ParameterValue' -ToolTip $item.FullName))
    }

    if ($results.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
            [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + $Placeholder) -ResultType 'ParameterValue' -ToolTip $ToolTip))
        } else {
            [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + $CurrentValue) -ResultType 'ParameterValue' -ToolTip $ToolTip))
        }
    }

    @($results.ToArray())
}

function Get-FindStrDirectoryListCompletions {
    param(
        [string]$Prefix,
        [string]$CurrentValue
    )

    $valuePrefix = ''
    $currentSegment = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $lastSemicolonIndex = if ([string]::IsNullOrEmpty($currentSegment)) { -1 } else { $currentSegment.LastIndexOf(';') }

    if ($lastSemicolonIndex -ge 0) {
        $valuePrefix = $currentSegment.Substring(0, $lastSemicolonIndex + 1)
        $currentSegment = $currentSegment.Substring($lastSemicolonIndex + 1)
    }

    $combinedPrefix = $Prefix + $valuePrefix
    $hasOpenQuotePrefix = ([regex]::Matches($combinedPrefix, '"').Count % 2) -eq 1
    $placeholder = if ([string]::IsNullOrEmpty($valuePrefix) -and [string]::IsNullOrEmpty($currentSegment)) {
        '<dir[;dir...]>'
    } else {
        '<dir>'
    }

    @(Get-FindStrPathCompletions -CurrentValue $currentSegment -Prefix $combinedPrefix -Kind 'Directory' -ToolTip 'Directory list entry.' -Placeholder $placeholder -HasOpenQuotePrefix:$hasOpenQuotePrefix)
}

function Get-FindStrTerminalCompletions {
    param([string]$CurrentValue)

    $completionText = if ([string]::IsNullOrEmpty($CurrentValue)) { ' ' } else { $CurrentValue }
    @(
        New-FindStrCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip 'No further arguments are valid after /?.'
    )
}

function Complete-FindStr {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $tokenState = Get-FindStrTokenState -Line $commandAst.ToString() -CursorPosition $cursorPosition
    $argumentState = Get-FindStrArgumentsFromTokenState -TokenState $tokenState
    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)

    if ($hasTrailingSpace -and -not [string]::IsNullOrEmpty($argumentState.CurrentArgument)) {
        $currentWord = ''
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent + $argumentState.CurrentArgument)
    } else {
        $currentWord = if ($null -eq $argumentState.CurrentArgument) { '' } else { $argumentState.CurrentArgument }
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent)
    }

    $context = Get-FindStrCompletionContext -ArgumentsBeforeCurrent $argumentsBeforeCurrent
    $catalog = Get-FindStrCompletionCatalog

    $canCompleteSwitches = -not $context.InFilenameMode -and -not $context.HasBareSearchStrings
    $fileOperandMode = $context.HasBareSearchStrings -or $context.InFilenameMode

    if ($canCompleteSwitches -and -not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('/')) {
        $attachedInfo = Get-FindStrAttachedTokenInfo -Token $currentWord
        if ($null -ne $attachedInfo) {
            switch ($attachedInfo.RootKey) {
                '/a' {
                    return @(Get-FindStrPrefixedValueCompletions -Prefix $attachedInfo.Prefix -CurrentValue $attachedInfo.Value -Suggestions $catalog.ColorHints -ToolTip $attachedInfo.Switch.Description -Placeholder '<hh>')
                }
                '/q' {
                    return @(Get-FindStrPrefixedValueCompletions -Prefix $attachedInfo.Prefix -CurrentValue $attachedInfo.Value -Suggestions $catalog.QuietFlags -ToolTip $attachedInfo.Switch.Description -Placeholder '<qflags>')
                }
                '/f' {
                    return @(Get-FindStrPathCompletions -CurrentValue $attachedInfo.Value -Prefix $attachedInfo.Prefix -Kind 'File' -ToolTip $attachedInfo.Switch.Description -Placeholder '<file-list>' -AllowConsoleSentinel $true)
                }
                '/g' {
                    return @(Get-FindStrPathCompletions -CurrentValue $attachedInfo.Value -Prefix $attachedInfo.Prefix -Kind 'File' -ToolTip $attachedInfo.Switch.Description -Placeholder '<pattern-file>' -AllowConsoleSentinel $true)
                }
                '/d' {
                    return @(Get-FindStrDirectoryListCompletions -Prefix $attachedInfo.Prefix -CurrentValue $attachedInfo.Value)
                }
                '/c' {
                    return @(Get-FindStrSearchStringCompletions -CurrentValue $attachedInfo.Value -Prefix $attachedInfo.Prefix)
                }
            }
        }

        if ($context.HelpRequested) {
            return @(Get-FindStrTerminalCompletions -CurrentValue $currentWord)
        }

        return @(Get-FindStrSwitchCompletions -CurrentWord $currentWord)
    }

    if ($context.HelpRequested) {
        return @(Get-FindStrTerminalCompletions -CurrentValue $currentWord)
    }

    if ($fileOperandMode) {
        return @(Get-FindStrPathCompletions -CurrentValue $currentWord -Kind 'File' -ToolTip 'File to search.' -Placeholder '<file>')
    }

    if ($context.HasExplicitSearchSource) {
        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            $results = New-Object System.Collections.Generic.List[object]
            foreach ($completion in @(Get-FindStrSwitchCompletions -CurrentWord $currentWord)) {
                [void]$results.Add($completion)
            }

            foreach ($completion in @(Get-FindStrPathCompletions -CurrentValue $currentWord -Kind 'File' -ToolTip 'File to search.' -Placeholder '<file>')) {
                [void]$results.Add($completion)
            }

            return @(Get-FindStrUniqueCompletions -Results $results.ToArray())
        }

        return @(Get-FindStrPathCompletions -CurrentValue $currentWord -Kind 'File' -ToolTip 'File to search.' -Placeholder '<file>')
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        $results = New-Object System.Collections.Generic.List[object]
        foreach ($completion in @(Get-FindStrSwitchCompletions -CurrentWord $currentWord)) {
            [void]$results.Add($completion)
        }

        foreach ($completion in @(Get-FindStrSearchStringCompletions -CurrentValue $currentWord)) {
            [void]$results.Add($completion)
        }

        return @(Get-FindStrUniqueCompletions -Results $results.ToArray())
    }

    @(Get-FindStrSearchStringCompletions -CurrentValue $currentWord)
}

Register-ArgumentCompleter -Native -CommandName @('findstr', 'findstr.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-FindStr -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
