# strings tab completion for PowerShell
# Native completer for Strings with switch-aware numeric hints and path completion.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name StringsCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:StringsCompletionCatalog = @{
        Switches = @(
            @{ Token = '-a'; Description = 'Ascii-only search.'; TakesValue = $false }
            @{ Token = '-b'; Description = 'Bytes of file to scan.'; TakesValue = $true; ValueKind = 'Bytes' }
            @{ Token = '-f'; Description = 'File offset at which to start scanning.'; TakesValue = $true; ValueKind = 'Offset' }
            @{ Token = '-n'; Description = 'Minimum string length.'; TakesValue = $true; ValueKind = 'Length' }
            @{ Token = '-o'; Description = 'Print offset where the string was located.'; TakesValue = $false }
            @{ Token = '-s'; Description = 'Recurse subdirectories.'; TakesValue = $false }
            @{ Token = '-u'; Description = 'Unicode-only search.'; TakesValue = $false }
            @{ Token = '-nobanner'; Description = 'Do not display the startup banner.'; TakesValue = $false }
            @{ Token = '-accepteula'; Description = 'Accept the Sysinternals license agreement (suppresses the first-run EULA dialog).'; TakesValue = $false }
            @{ Token = '-?'; Description = 'Show Strings help.'; TakesValue = $false }
            @{ Token = '/?'; Description = 'Show Strings help.'; TakesValue = $false }
        )
        ByteHints   = @('256', '512', '1024', '4096', '65536')
        OffsetHints = @('512', '4096', '65536', '1048576')
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

function ConvertFrom-StringsTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes;
    # text glued after the closing quote ("C:\Program Files"\) joins the same argument.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput('x ' + $Value, [ref]$tokens, [ref]$parseErrors)
    -join @($tokens | Select-Object -Skip 1 | Where-Object { $_.Kind -ne 'EndOfInput' } | ForEach-Object {
            if ($_ -is [System.Management.Automation.Language.StringToken]) { $_.Value } else { $_.Text }
        })
}

function ConvertTo-StringsQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default). PowerShell reads ' and
    # U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes. A bare word
    # starting with a dash (- or U+2013-U+2015) would be read as a parameter.
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $QuoteChar) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]' -and $Value -notmatch '^[-\u2013-\u2015]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-StringsCurrentWord {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The parser keeps an unterminated quoted word (any quote style) as one element running
    # to the cursor, which is the word PowerShell replaces. A quoted string glued to a path
    # tail ("C:\Program Files"\x) is one argument, and PowerShell then replaces all of it.
    $elements = @($CommandAst.CommandElements)
    for ($index = 1; $index -lt $elements.Count; $index++) {
        $extent = $elements[$index].Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            $start = $index
            while ($start -gt 1 -and
                $elements[$start - 1].Extent.EndOffset -eq $elements[$start].Extent.StartOffset -and
                $elements[$start].Extent.Text -match '^[\\/]' -and
                $elements[$start - 1].PSObject.Properties['StringConstantType'] -and
                $elements[$start - 1].StringConstantType -ne 'BareWord') {
                $start--
            }

            $startOffset = $elements[$start].Extent.StartOffset
            return $CommandAst.Extent.Text.Substring($startOffset - $CommandAst.Extent.StartOffset, $CursorPosition - $startOffset)
        }
    }

    ''
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

function Expand-StringsPathText {
    # Resolve the forms a user types at the prompt ($env:NAME, ${env:NAME}, %NAME%, ~) to a
    # filesystem path for enumeration, while the typed text itself stays in the completion.
    param([string]$Path)

    if ([string]::IsNullOrEmpty($Path)) {
        return $Path
    }

    $expanded = [regex]::Replace($Path, '\$\{?env:([A-Za-z_][A-Za-z0-9_]*)\}?', {
            param($match)
            $value = [System.Environment]::GetEnvironmentVariable($match.Groups[1].Value)
            if ($null -eq $value) { $match.Value } else { $value }
        })
    $expanded = [System.Environment]::ExpandEnvironmentVariables($expanded)

    if ($expanded -eq '~' -or $expanded.StartsWith('~\') -or $expanded.StartsWith('~/')) {
        $expanded = $HOME + $expanded.Substring(1)
    }

    $expanded
}

function Get-StringsPathCompletions {
    param(
        [string]$CurrentWord,
        [string]$ToolTip,
        [string]$Placeholder = '<file-or-directory>'
    )

    $typedValue = ConvertFrom-StringsTypedWord -Value $CurrentWord
    $quoteChar = if ($CurrentWord -match '^[''"\u2018-\u201E]') { $CurrentWord.Substring(0, 1) } else { '' }
    $results = New-Object System.Collections.Generic.List[object]

    # Split on the typed text (so the completion keeps the user's prefix verbatim) and
    # enumerate the expanded form.
    $typedParent = ''
    $leaf = $typedValue
    $separatorIndex = $typedValue.LastIndexOfAny([char[]]@('\', '/'))
    if ($separatorIndex -ge 0) {
        $typedParent = $typedValue.Substring(0, $separatorIndex + 1)
        $leaf = $typedValue.Substring($separatorIndex + 1)
    }

    # Single quotes keep $env: literal, so only an unquoted or double-quoted parent expands it.
    # A leading ~ resolves to the home folder in every quote style, as PowerShell's own path
    # completion does; quoted candidates then spell out the expanded parent.
    $expandedParent = if ($quoteChar -notmatch '^[''\u2018-\u201B]$') {
        Expand-StringsPathText -Path $typedParent
    } elseif ($typedParent -match '^~[\\/]') {
        $HOME + $typedParent.Substring(1)
    } else {
        $typedParent
    }
    $enumeratePath = if ([string]::IsNullOrEmpty($typedParent)) { '.' } else { $expandedParent }
    $items = @()
    try {
        $items = @(Get-ChildItem -LiteralPath $enumeratePath -ErrorAction Ignore)
    } catch {
        Write-Debug "strings path enumeration failed for '$enumeratePath': $($_.Exception.Message)"
    }

    foreach ($item in $items) {
        if (-not [string]::IsNullOrWhiteSpace($leaf) -and
            -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $name = $item.Name
        if ($item.PSIsContainer) {
            $name += '\'
        }

        $parent = $typedParent
        $valueParent = $expandedParent
        if (-not $typedParent -and $name -match '^[-\u2013-\u2015]') {
            # A name starting with a dash gets the current-directory prefix, as PowerShell's
            # own file completion does, so it cannot be read as a parameter.
            $parent = $valueParent = '.' + [System.IO.Path]::DirectorySeparatorChar
        }

        $candidate = $parent + $name
        # A bare $env:/~ prefix stays live while the name needs no quoting; a quoted word
        # would not expand it, so quoted candidates spell out the expanded parent instead.
        if (-not $quoteChar -and $parent -ne $valueParent -and (ConvertTo-StringsQuotedValue -Value $name) -eq $name) {
            $completionText = $candidate
        } else {
            $completionText = ConvertTo-StringsQuotedValue -Value ($valueParent + $name) -QuoteChar $quoteChar
        }

        [void]$results.Add((New-StringsCompletionResult -CompletionText $completionText -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    # With nothing typed, the placeholder keeps the slot visible; with a typed value that
    # matches nothing, return nothing so PowerShell's own path completion can take over.
    if ($results.Count -eq 0 -and [string]::IsNullOrWhiteSpace($CurrentWord)) {
        [void]$results.Add((New-StringsCompletionResult -CompletionText $Placeholder -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip))
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
    # $CursorPosition is line-absolute; the extent text is command-relative.
    $relativeCursor = [Math]::Max(0, $CursorPosition - $CommandAst.Extent.StartOffset)
    if ($relativeCursor -gt $line.Length) {
        $line = $line.PadRight($relativeCursor)
    }
    $tokenState = Get-StringsTokenState -Line $line -CursorPosition $relativeCursor
    $argumentsState = Get-StringsArgumentsFromTokenState -TokenState $tokenState
    $state = Get-StringsCommandState -ArgumentsBeforeCurrent $argumentsState.ArgumentsBeforeCurrent
    $currentWord = Get-StringsCurrentWord -CommandAst $CommandAst -CursorPosition $CursorPosition

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
