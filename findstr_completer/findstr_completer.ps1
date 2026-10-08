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
    if (Get-Variable -Name FindStrCompletionCatalog -Scope Script -ErrorAction Ignore) {
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
        ColorNames          = [ordered]@{
            '0' = 'Black';  '1' = 'Blue';         '2' = 'Green';        '3' = 'Aqua'
            '4' = 'Red';    '5' = 'Purple';       '6' = 'Yellow';       '7' = 'White'
            '8' = 'Gray';   '9' = 'Light Blue';   'A' = 'Light Green';  'B' = 'Light Aqua'
            'C' = 'Light Red'; 'D' = 'Light Purple'; 'E' = 'Light Yellow'; 'F' = 'Bright White'
        }
        QuietFlags          = @('u')
    }

    $script:FindStrCompletionCatalog
}

function Get-FindStrColorCompletion {
    param(
        [string]$Prefix,
        [string]$CurrentValue
    )

    # /A: takes exactly two hex digits, background then foreground, using the
    # digit table from color /?; every one of the 256 pairs is valid.
    $names = (Get-FindStrCompletionCatalog).ColorNames
    $typedValue = (Remove-FindStrOuterQuotes -Value $CurrentValue).ToUpperInvariant()
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($background in $names.Keys) {
        foreach ($foreground in $names.Keys) {
            $pair = $background + $foreground
            if (-not $pair.StartsWith($typedValue)) {
                continue
            }

            [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + $pair) -ResultType 'ParameterValue' -ToolTip ($names[$foreground] + ' on ' + $names[$background] + '.')))
        }
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentValue)) { $Prefix + '<hh>' } else { $Prefix + $CurrentValue }
        [void]$results.Add((New-FindStrCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip 'Color attribute: two hex digits, background then foreground.'))
    }

    @($results.ToArray())
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

function ConvertFrom-FindStrTypedWord {
    # The value of a typed word and the quote it opened with ('' when bare). A word opened
    # with a quote (ASCII or typographic) is read by the PowerShell tokenizer, which drops
    # the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return [pscustomobject]@{ Value = $Value; Quote = '' }
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    [pscustomobject]@{ Value = [string]$tokens[0].Value; Quote = $Value.Substring(0, 1) }
}

function ConvertTo-FindStrQuotedValue {
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
    # PowerShell reads ' and U+2018-U+201B as single quotes and " and
    # U+201C-U+201E as double quotes; a backtick outside single quotes escapes
    # the next character.
    $quoteClass = ''
    $escapeNext = $false

    foreach ($character in $prefix.ToCharArray()) {
        if ($escapeNext) {
            $escapeNext = $false
            [void]$builder.Append($character)
            continue
        }

        if ($character -eq '`' -and $quoteClass -ne 'single') {
            $escapeNext = $true
            [void]$builder.Append($character)
            continue
        }

        $characterClass = if ($character -match '[''\u2018-\u201B]') { 'single' } elseif ($character -match '["\u201C-\u201E]') { 'double' } else { '' }
        if ($characterClass) {
            if (-not $quoteClass) {
                $quoteClass = $characterClass
            } elseif ($quoteClass -eq $characterClass) {
                $quoteClass = ''
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and -not $quoteClass) {
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

    # findstr parses a switch word letter by letter, so plain flags may lead a
    # value switch in one cluster (/nic:text, /na:0C); the value switch must
    # come last, and the whole typed head stays the completion prefix.
    $match = [regex]::Match($Token, '^(?<head>/(?i:[belrsixvnmop]*)(?<root>[A-Za-z])):(?<value>.*)$')
    if (-not $match.Success) {
        return $null
    }

    $catalog = Get-FindStrCompletionCatalog
    $rootKey = '/' + $match.Groups['root'].Value.ToLowerInvariant()
    if (-not $catalog.AttachedValueLookup.ContainsKey($rootKey)) {
        return $null
    }

    [pscustomobject]@{
        RootKey = $rootKey
        Prefix  = $match.Groups['head'].Value + ':'
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

        # A cluster of plain flags (/si, /spin, /i?) is still switches, not
        # the bare search string.
        if ([regex]::IsMatch($argument, '^/(?i:[belrsixvnmop?]{2,})$')) {
            if ($argument.Contains('?')) {
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
        [string]$ListSeparator = ''
    )

    $results = New-Object System.Collections.Generic.List[object]
    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $typedWord = ConvertFrom-FindStrTypedWord -Value $typedValue
    $cleanValue = $typedWord.Value

    # In a list value the whole list is re-quoted as one argument, so the
    # entries before the last separator ride along in front of each candidate.
    $valuePrefix = ''
    if ($ListSeparator -and $cleanValue.Contains($ListSeparator)) {
        $separatorIndex = $cleanValue.LastIndexOf($ListSeparator)
        $valuePrefix = $cleanValue.Substring(0, $separatorIndex + 1)
        $cleanValue = $cleanValue.Substring($separatorIndex + 1)
    }

    if ($AllowConsoleSentinel) {
        if ([string]::IsNullOrWhiteSpace($cleanValue) -or '/'.StartsWith($cleanValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + '/') -ResultType 'ParameterValue' -ToolTip 'Read this value from console input.'))
        }
    }

    # Candidates are built on the directory text exactly as typed, so a typed
    # .\ or ./ prefix and the typed separator style survive.
    $directoryText = ''
    $separatorIndex = $cleanValue.LastIndexOfAny([char[]]@('\', '/'))
    if ($separatorIndex -ge 0) {
        $directoryText = $cleanValue.Substring(0, $separatorIndex + 1)
    } elseif ($cleanValue -match '^[A-Za-z]:') {
        $directoryText = $cleanValue.Substring(0, 2)
    }

    $parentPath = if ($directoryText) { $directoryText } else { '.' }
    $leaf = $cleanValue.Substring($directoryText.Length)

    $items = @()
    if (Test-Path -LiteralPath $parentPath -PathType Container -ErrorAction Ignore) {
        $items = @(Get-ChildItem -LiteralPath $parentPath -ErrorAction Ignore)
    }

    foreach ($item in $items) {
        if (-not [string]::IsNullOrWhiteSpace($leaf) -and
            -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ($Kind -eq 'Directory' -and -not $item.PSIsContainer) {
            continue
        }

        $candidate = $directoryText + $item.Name
        if ($item.PSIsContainer) {
            $candidate += '\'
        }

        # A whole-word value starting with a dash would parse as a parameter, so
        # it gets the current-directory prefix, as PowerShell's own file completion does.
        if (-not ($Prefix -or $valuePrefix) -and $candidate -match '^[-\u2013-\u2015]') {
            $candidate = '.' + [System.IO.Path]::DirectorySeparatorChar + $candidate
        }

        $completionText = ConvertTo-FindStrQuotedValue -Value ($valuePrefix + $candidate) -QuoteChar $typedWord.Quote
        [void]$results.Add((New-FindStrCompletionResult -CompletionText ($Prefix + $completionText) -ResultType 'ParameterValue' -ToolTip $item.FullName -ListItemText $candidate))
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

    # A real multi-directory list must be quoted (an unquoted ';' ends the
    # PowerShell statement); each candidate re-quotes the whole list, so a
    # typed closing quote is neither swallowed nor left dangling.
    @(Get-FindStrPathCompletions -CurrentValue $CurrentValue -Prefix $Prefix -Kind 'Directory' -ToolTip 'Directory list entry.' -Placeholder '<dir[;dir...]>' -ListSeparator ';')
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

    $tokenState = Get-FindStrTokenState -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset)
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
                    return @(Get-FindStrColorCompletion -Prefix $attachedInfo.Prefix -CurrentValue $attachedInfo.Value)
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
