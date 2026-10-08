# shellrunas tab completion for PowerShell
# Static native completer based on official Sysinternals web documentation.

Set-StrictMode -Version 2.0

function New-ShellRunasCompletionResult {
    param([string]$CompletionText, [string]$ResultType, [string]$ToolTip, [string]$ListItemText)
    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }
    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

function Get-ShellRunasTypedQuote {
    # The first unescaped quote character in the typed word, folded to ' or " (typographic quotes included).
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $char = $Value[$i]
        if ($char -eq [char]'`') { $i++; continue }
        if ("'$([char]0x2018)$([char]0x2019)$([char]0x201A)$([char]0x201B)".IndexOf($char) -ge 0) { return "'" }
        if ("`"$([char]0x201C)$([char]0x201D)$([char]0x201E)".IndexOf($char) -ge 0) { return '"' }
    }
    ''
}

function Remove-ShellRunasOuterQuotes {
    # The value PowerShell passes for the typed word: the parser undoes every quoted segment and escape
    # ('C:\Program Files'\Com is two elements, an unterminated quote one), and the element values join.
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput("shellrunas $Value", [ref]$tokens, [ref]$parseErrors)
    $command = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    if (-not $command) { return $Value }
    -join @($command.CommandElements | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $_ -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { $_.Value } else { $_.Extent.Text }
        })
}

function ConvertTo-ShellRunasQuotedValue {
    # Bare when safe and no quote was typed; otherwise in the typed quote style (single by default).
    param([string]$Value, [string]$Quote = '')
    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    if (-not $Quote) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') { return $Value }
        $Quote = "'"
    }
    if ($Quote -eq "'") { return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'" }
    '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
}

function Get-ShellRunasArgumentState {
    param([System.Management.Automation.Language.CommandAst]$CommandAst, [string]$WordToComplete, [int]$CursorPosition)
    # The current word is the span PowerShell replaces: the element under the cursor (an unterminated
    # quote is one element running to the end of the line), widened back over a quoted segment it is
    # glued to when it starts with a path separator ('C:\Program Files'\Com). The whole span is the
    # word, so a completion never drops typed text after the cursor or a quoted segment before it.
    $elements = @($CommandAst.CommandElements | Select-Object -Skip 1)
    $currentIndex = -1
    for ($i = 0; $i -lt $elements.Count; $i++) {
        if ($elements[$i].Extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $elements[$i].Extent.EndOffset) { $currentIndex = $i; break }
    }
    $startIndex = $currentIndex
    if ($currentIndex -gt 0 -and $elements[$currentIndex].Extent.Text -match '^[\\/]' -and $elements[$currentIndex - 1].Extent.EndOffset -eq $elements[$currentIndex].Extent.StartOffset) {
        $previous = $elements[$currentIndex - 1]
        if (($previous -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $previous -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
            $previous.StringConstantType -in @('SingleQuoted', 'DoubleQuoted')) {
            $startIndex = $currentIndex - 1
        }
    }
    $currentWord = if ($currentIndex -ge 0) {
        -join @($elements[$startIndex..$currentIndex] | ForEach-Object { $_.Extent.Text })
    } elseif ([string]::IsNullOrEmpty($WordToComplete)) {
        ''
    } else {
        $WordToComplete
    }
    $wordStart = if ($currentIndex -ge 0) { $elements[$startIndex].Extent.StartOffset } else { $CursorPosition }
    $tokensBeforeCurrent = @(
        $elements |
            Where-Object { $_.Extent.EndOffset -le $wordStart } |
            ForEach-Object { $_.Extent.Text }
    )
    [pscustomobject]@{
        CurrentWord         = $currentWord
        TokensBeforeCurrent = $tokensBeforeCurrent
    }
}

function Get-ShellRunasProgramCompletions {
    param([string]$CurrentWord)
    $trimmed = Remove-ShellRunasOuterQuotes -Value $CurrentWord
    $quote = Get-ShellRunasTypedQuote -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        foreach ($sample in @('notepad.exe', 'cmd.exe', 'powershell.exe', 'pwsh.exe')) {
            [void]$results.Add((New-ShellRunasCompletionResult -CompletionText (ConvertTo-ShellRunasQuotedValue -Value $sample -Quote $quote) -ListItemText $sample -ResultType 'ParameterValue' -ToolTip 'Program to run with alternate credentials.'))
        }
    }

    if ($trimmed -match '[\\/]|^\.' -or $trimmed -match '^[A-Za-z]:') {
        if ($trimmed -match '[\\/]$') {
            $parent = $trimmed
            $filter = '*'
        } else {
            $parent = Split-Path -Path $trimmed -Parent
            if ([string]::IsNullOrWhiteSpace($parent)) { $parent = '.' }
            $leaf = Split-Path -Path $trimmed -Leaf
            $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $parent -Filter $filter -ErrorAction Ignore)) {
            $completionPath = if ($trimmed -and -not [System.IO.Path]::IsPathRooted($trimmed) -and $parent -ne '.') {
                Join-Path -Path $parent -ChildPath $item.Name
            } elseif ($parent -eq '.') {
                $item.Name
            } else {
                $item.FullName
            }
            if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
                $completionPath += [System.IO.Path]::DirectorySeparatorChar
            }
            [void]$results.Add((New-ShellRunasCompletionResult -CompletionText (ConvertTo-ShellRunasQuotedValue -Value $completionPath -Quote $quote) -ResultType $(if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }) -ToolTip $item.FullName))
        }
    } else {
        # A '[' or ']' in the word is part of a file name, not a wildcard range: an unmatched '[' makes
        # Get-Command throw, so look up the text before the first bracket and match the rest literally.
        $bracketAt = $trimmed.IndexOfAny([char[]]'[]')
        $namePattern = if ($bracketAt -ge 0) { $trimmed.Substring(0, $bracketAt) + '*' } else { "$trimmed*" }
        $applications = @(Get-Command -Name $namePattern -CommandType Application -ErrorAction Ignore)
        if ($bracketAt -ge 0) {
            $applications = @($applications | Where-Object { $_.Name.StartsWith($trimmed, [System.StringComparison]::OrdinalIgnoreCase) })
        }
        foreach ($command in @($applications | Sort-Object -Property Name -Unique | Select-Object -First 20)) {
            [void]$results.Add((New-ShellRunasCompletionResult -CompletionText (ConvertTo-ShellRunasQuotedValue -Value $command.Name -Quote $quote) -ListItemText $command.Name -ResultType 'ParameterValue' -ToolTip $command.Name))
        }
    }

    if ($results.Count -eq 0) {
        return @(New-ShellRunasCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '<program>' } else { $CurrentWord }) -ResultType 'ParameterValue' -ToolTip 'Program to run with alternate credentials.')
    }

    $seen = @{}
    $unique = foreach ($item in $results) {
        if ($seen.ContainsKey($item.CompletionText)) { continue }
        $seen[$item.CompletionText] = $true
        $item
    }
    @($unique)
}

function Complete-ShellRunas {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $state = Get-ShellRunasArgumentState -CommandAst $CommandAst -WordToComplete $WordToComplete -CursorPosition $CursorPosition
    $currentWord = $state.CurrentWord
    $tokensBeforeCurrent = @($state.TokensBeforeCurrent)
    $mode = $null
    $quiet = $false
    $netOnly = $false
    $program = $null

    foreach ($token in $tokensBeforeCurrent) {
        $lowerToken = $token.ToLowerInvariant()
        if ($lowerToken -eq '/reg') { $mode = 'Register'; continue }
        if ($lowerToken -eq '/regnetonly') { $mode = 'RegisterNetOnly'; continue }
        if ($lowerToken -eq '/unreg') { $mode = 'Unregister'; continue }
        if ($lowerToken -eq '/quiet') { $quiet = $true; continue }
        if ($lowerToken -eq '/netonly' -and -not $mode) { $netOnly = $true; continue }

        if (-not $program) {
            $program = $token
            continue
        }
    }

    if ($program) {
        return @(New-ShellRunasCompletionResult -CompletionText $(if ([string]::IsNullOrWhiteSpace($currentWord)) { '<argument>' } else { $currentWord }) -ResultType 'ParameterValue' -ToolTip 'ShellRunas passes later arguments through without local enumeration.')
    }

    if (-not $mode -and -not [string]::IsNullOrWhiteSpace($currentWord) -and -not $currentWord.StartsWith('/')) {
        return Get-ShellRunasProgramCompletions -CurrentWord $currentWord
    }

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $mode) {
        if (-not $netOnly) {
            foreach ($item in @(
                    @{ Token = '/reg'; Description = 'Register the ShellRunas shell context-menu entry.' }
                    @{ Token = '/regnetonly'; Description = 'Register the Shell /netonly context-menu entry.' }
                    @{ Token = '/unreg'; Description = 'Unregister the ShellRunas shell context-menu entry.' }
                    @{ Token = '/netonly'; Description = 'Use specified credentials for remote access only when launching a program.' }
                )) {
                if ([string]::IsNullOrWhiteSpace($currentWord) -or $item.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-ShellRunasCompletionResult -CompletionText $item.Token -ResultType 'ParameterName' -ToolTip $item.Description))
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($currentWord) -or -not $currentWord.StartsWith('/')) {
            foreach ($item in @(Get-ShellRunasProgramCompletions -CurrentWord $currentWord)) {
                [void]$results.Add($item)
            }
        }

        return @($results.ToArray())
    }

    if ($mode -in @('Register', 'RegisterNetOnly', 'Unregister')) {
        if (-not $quiet -and ([string]::IsNullOrWhiteSpace($currentWord) -or '/quiet'.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase))) {
            [void]$results.Add((New-ShellRunasCompletionResult -CompletionText '/quiet' -ResultType 'ParameterName' -ToolTip 'Register or unregister without showing a result dialog.'))
        }
        return @($results.ToArray())
    }

    Get-ShellRunasProgramCompletions -CurrentWord $currentWord
}


Register-ArgumentCompleter -Native -CommandName @('shellrunas', 'shellrunas.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-ShellRunas -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
