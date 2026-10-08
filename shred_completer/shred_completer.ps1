# shred tab completion for PowerShell
# Static option completion for shred.exe and shred.

Set-StrictMode -Version 2.0

function Get-ShredCompletionOptions {
    $cache = Get-Variable -Name 'ShredCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-f', '--force', '-n', '--iterations', '-s', '--size', '-u', '--remove', '-v', '--verbose', '-x', '--exact', '-r', '-z', '--zero', '--random-source', '-h', '--help', '-V', '--version', '-b')
    $commandCandidates = @('shred.exe', 'shred')
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
            Set-Variable -Name 'ShredCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'ShredCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'ShredCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'ShredCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'ShredCompletionOptions' -Scope Script).Value
}


function New-ShredCompletionResult {
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

function Remove-ShredOuterQuotes {
    # The parser resolves the typed quotes and escapes ('it''s, with` s) and reads an
    # unterminated quote to its end. A bare word that does not parse (it's) is a name typed
    # as is: the parser would drop its apostrophe.
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput('x ' + $Value, [ref]$tokens, [ref]$parseErrors)
    $quotes = "'" + '"' + [char]0x2018 + [char]0x2019 + [char]0x201A + [char]0x201B + [char]0x201C + [char]0x201D + [char]0x201E
    if (@($parseErrors).Count -gt 0 -and -not $quotes.Contains($Value[0])) {
        return $Value
    }

    $element = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    if ($null -ne $element -and $element.CommandElements.Count -eq 2) {
        $argument = $element.CommandElements[1]
        if ($argument -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $argument -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            return $argument.Value
        }
    }

    $Value
}

function ConvertTo-ShredQuotedValue {
    # Quote is the quote character the user typed ('' when none): its kind is kept, and a
    # value that needs quoting without one is single-quoted.
    param(
        [string]$Value,
        [string]$Quote = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    $singleQuotes = "'" + [char]0x2018 + [char]0x2019 + [char]0x201A + [char]0x201B
    $doubleQuotes = '"' + [char]0x201C + [char]0x201D + [char]0x201E
    if ([string]::IsNullOrEmpty($Quote) -and $Value -notmatch ('[\s{}();,|&<>`$@#' + $singleQuotes + $doubleQuotes + ']')) {
        return $Value
    }

    if (-not [string]::IsNullOrEmpty($Quote) -and $doubleQuotes.Contains($Quote)) {
        return '"' + [regex]::Replace($Value, '[`$' + $doubleQuotes + ']', '`$0') + '"'
    }

    "'" + [regex]::Replace($Value, '[' + $singleQuotes + ']', '$0$0') + "'"
}

function Get-ShredCurrentToken {
    # The word under the cursor comes from the parser: an unterminated quote is one element
    # that runs to the cursor, so a quoted path with a space stays whole. PowerShell replaces
    # such an element up to the end of the line, so the words typed after the cursor (from
    # the first whitespace on) are returned as Tail for every candidate to carry; the rest of
    # the current word is replaced, as it is for any other word.
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.StartOffset -lt $CursorPosition -and $element.Extent.EndOffset -ge $CursorPosition) {
            $cut = $CursorPosition - $element.Extent.StartOffset
            $tail = ''
            $rest = $element.Extent.Text.Substring($cut)
            $space = [regex]::Match($rest, '\s')
            if ($space.Success) {
                $tokens = $null
                $parseErrors = $null
                [void][System.Management.Automation.Language.Parser]::ParseInput($element.Extent.Text, [ref]$tokens, [ref]$parseErrors)
                if (@($parseErrors | Where-Object { $_.ErrorId -eq 'TerminatorExpectedAtEndOfString' }).Count -gt 0) {
                    $tail = $rest.Substring($space.Index)
                }
            }

            return [pscustomobject]@{ Word = $element.Extent.Text.Substring(0, $cut); Tail = $tail }
        }
    }

    [pscustomobject]@{ Word = ''; Tail = '' }
}

function Get-ShredPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-ShredOuterQuotes -Value $InputPath
    $typedQuote = ''
    if ($InputPath -match ('^[''"' + [char]0x2018 + [char]0x2019 + [char]0x201A + [char]0x201B + [char]0x201C + [char]0x201D + [char]0x201E + ']')) {
        $typedQuote = $Matches[0]
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

    $items = @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction Ignore)
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

        $quotedPath = ConvertTo-ShredQuotedValue -Value $pathText -Quote $typedQuote
        if ($item.PSIsContainer) {
            New-ShredCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-ShredCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-ShredOptionValueCompletions {
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
    $table['-n'] = @(
        @{ Text = '3'; Tip = 'Default, 3 passes.' }
        @{ Text = '<n>'; Tip = 'Number of passes.' }
    )
    $table['--iterations'] = @(
        @{ Text = '3'; Tip = 'Default, 3 passes.' }
        @{ Text = '<n>'; Tip = 'Number of passes.' }
    )
    $table['--random-source'] = 'path'
    $table['-s'] = @(
        @{ Text = '<size>'; Tip = 'Size, suffixes K, M, G accepted.' }
        @{ Text = '1K'; Tip = '1 KiB.' }
        @{ Text = '1M'; Tip = '1 MiB.' }
        @{ Text = '1G'; Tip = '1 GiB.' }
    )
    $table['--size'] = @(
        @{ Text = '<size>'; Tip = 'Size, suffixes K, M, G accepted.' }
        @{ Text = '1K'; Tip = '1 KiB.' }
        @{ Text = '1M'; Tip = '1 MiB.' }
        @{ Text = '1G'; Tip = '1 GiB.' }
    )
    $table['--remove'] = @(
        @{ Text = 'unlink'; Tip = 'Just unlink.' }
        @{ Text = 'wipe'; Tip = 'Obfuscate the name before unlinking.' }
        @{ Text = 'wipesync'; Tip = 'Sync each obfuscated byte to disk.' }
    )
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-ShredPathCompletions -InputPath $prefix) {
                New-ShredCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-ShredCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-ShredOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'ShredCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for shred.'
}

function Complete-Shred {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete closes an open quote and spans past the cursor.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $token = Get-ShredCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition
    $currentWord = $token.Word

    $results = @(Get-ShredOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($results.Count -eq 0) {
        if ([string]::IsNullOrEmpty($currentWord)) {
            return @()
        }

        $results = if ($currentWord.StartsWith('-')) {
            @(
                foreach ($option in Get-ShredCompletionOptions) {
                    if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                        New-ShredCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-ShredOptionDescription -Option $option)
                    }
                }
            )
        } else {
            @(Get-ShredPathCompletions -InputPath $currentWord)
        }
    }

    if ([string]::IsNullOrEmpty($token.Tail)) {
        return $results
    }

    foreach ($result in $results) {
        [System.Management.Automation.CompletionResult]::new($result.CompletionText + $token.Tail, $result.ListItemText, $result.ResultType, $result.ToolTip)
    }
}

Register-ArgumentCompleter -Native -CommandName 'shred', 'shred.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Shred -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
