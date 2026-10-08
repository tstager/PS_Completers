# test tab completion for PowerShell
# Static operator completion for the GNU/coreutils test(1) binary.
#
# test(1) has no help output by design: POSIX requires it to treat --help and
# --version as ordinary nonempty STRINGs, so both installed builds answer them
# with an empty stdout and exit 0. The catalog below is transcribed from the
# GNU coreutils test help printed by the sibling '[' binary and verified
# against the test.exe that Get-Command resolves.

Set-StrictMode -Version 2.0

function Get-TestOperatorCatalog {
    $cache = Get-Variable -Name 'TestOperatorCatalog' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $catalog = @(
        @{ Token = '-b'; ValueKind = 'File'; Description = 'FILE exists and is block special.' }
        @{ Token = '-c'; ValueKind = 'File'; Description = 'FILE exists and is character special.' }
        @{ Token = '-d'; ValueKind = 'File'; Description = 'FILE exists and is a directory.' }
        @{ Token = '-e'; ValueKind = 'File'; Description = 'FILE exists.' }
        @{ Token = '-f'; ValueKind = 'File'; Description = 'FILE exists and is a regular file.' }
        @{ Token = '-g'; ValueKind = 'File'; Description = 'FILE exists and is set-group-ID.' }
        @{ Token = '-h'; ValueKind = 'File'; Description = 'FILE exists and is a symbolic link (same as -L).' }
        @{ Token = '-L'; ValueKind = 'File'; Description = 'FILE exists and is a symbolic link (same as -h).' }
        @{ Token = '-n'; ValueKind = 'String'; Description = 'The length of STRING is nonzero.' }
        @{ Token = '-p'; ValueKind = 'File'; Description = 'FILE exists and is a named pipe.' }
        @{ Token = '-r'; ValueKind = 'File'; Description = 'FILE exists and read permission is granted.' }
        @{ Token = '-s'; ValueKind = 'File'; Description = 'FILE exists and has a size greater than zero.' }
        @{ Token = '-S'; ValueKind = 'File'; Description = 'FILE exists and is a socket.' }
        @{ Token = '-t'; ValueKind = 'Fd'; Description = 'File descriptor FD is opened on a terminal.' }
        @{ Token = '-u'; ValueKind = 'File'; Description = 'FILE exists and its set-user-ID bit is set.' }
        @{ Token = '-w'; ValueKind = 'File'; Description = 'FILE exists and write permission is granted.' }
        @{ Token = '-x'; ValueKind = 'File'; Description = 'FILE exists and execute (or search) permission is granted.' }
        @{ Token = '-z'; ValueKind = 'String'; Description = 'The length of STRING is zero.' }
        @{ Token = '-G'; ValueKind = 'File'; Description = 'FILE exists and is owned by the effective group ID.' }
        @{ Token = '-k'; ValueKind = 'File'; Description = 'FILE exists and has its sticky bit set.' }
        @{ Token = '-N'; ValueKind = 'File'; Description = 'FILE exists and has been modified since it was last read.' }
        @{ Token = '-O'; ValueKind = 'File'; Description = 'FILE exists and is owned by the effective user ID.' }
        @{ Token = '-ef'; ValueKind = 'File'; Description = 'FILE1 and FILE2 have the same device and inode numbers.' }
        @{ Token = '-nt'; ValueKind = 'File'; Description = 'FILE1 is newer (modification date) than FILE2.' }
        @{ Token = '-ot'; ValueKind = 'File'; Description = 'FILE1 is older than FILE2.' }
        @{ Token = '-eq'; ValueKind = 'Integer'; Description = 'INTEGER1 is equal to INTEGER2.' }
        @{ Token = '-ne'; ValueKind = 'Integer'; Description = 'INTEGER1 is not equal to INTEGER2.' }
        @{ Token = '-ge'; ValueKind = 'Integer'; Description = 'INTEGER1 is greater than or equal to INTEGER2.' }
        @{ Token = '-gt'; ValueKind = 'Integer'; Description = 'INTEGER1 is greater than INTEGER2.' }
        @{ Token = '-le'; ValueKind = 'Integer'; Description = 'INTEGER1 is less than or equal to INTEGER2.' }
        @{ Token = '-lt'; ValueKind = 'Integer'; Description = 'INTEGER1 is less than INTEGER2.' }
        @{ Token = '-a'; ValueKind = 'Expression'; Description = 'Both EXPRESSION1 and EXPRESSION2 are true.' }
        @{ Token = '-o'; ValueKind = 'Expression'; Description = 'Either EXPRESSION1 or EXPRESSION2 is true.' }
        @{ Token = '!'; ValueKind = 'Expression'; Description = 'EXPRESSION is false.' }
        @{ Token = '='; ValueKind = 'String'; Description = 'The strings are equal.' }
        @{ Token = '!='; ValueKind = 'String'; Description = 'The strings are not equal.' }
        @{ Token = '('; ValueKind = 'Expression'; Description = 'Start a grouped EXPRESSION (escape it for the shell).' }
        @{ Token = ')'; ValueKind = 'Expression'; Description = 'End a grouped EXPRESSION (escape it for the shell).' }
    )

    Set-Variable -Name 'TestOperatorCatalog' -Value $catalog -Scope Script
    $catalog
}

function Get-TestOperatorSpec {
    param([string]$Token)

    if ([string]::IsNullOrEmpty($Token)) { return $null }
    foreach ($spec in Get-TestOperatorCatalog) {
        if ([string]::Equals($spec.Token, $Token, [System.StringComparison]::Ordinal)) {
            return $spec
        }
    }

    $null
}

function New-TestCompletionResult {
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

function ConvertFrom-TestTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    $tokens[0].Value
}

function ConvertTo-TestQuotedValue {
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

function Get-TestLineState {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # Words come from the parser, so a quoted word with spaces (even an unterminated
    # one, which runs to the cursor) is one word.
    $currentWord = ''
    $operands = @()
    foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.EndOffset -lt $CursorPosition) {
            $operands += $extent.Text
            continue
        }

        if ($extent.StartOffset -lt $CursorPosition) {
            $currentWord = $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }

        break
    }

    [pscustomobject]@{
        CurrentWord = $currentWord
        Operands    = $operands
    }
}

function Get-TestPathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-TestTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # The typed directory part (up to the last separator) is kept exactly as typed,
    # so a typed .\ or ./ prefix survives.
    $lastSeparator = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    if ($lastSeparator -ge 0) {
        $directoryText = $cleanInput.Substring(0, $lastSeparator + 1)
        $parent = $directoryText
        $leaf = $cleanInput.Substring($lastSeparator + 1)
    } else {
        $directoryText = ''
        $parent = '.'
        $leaf = $cleanInput
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = @($items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name)

    foreach ($item in $items) {
        # A bare relative name starting with a dash would parse as a parameter, so it
        # gets the current-directory prefix, as PowerShell's own file completion does.
        $pathText = if ($directoryText -eq '' -and $item.Name -match '^[-\u2013-\u2015]') {
            '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        } else {
            $directoryText + $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $completionText = ConvertTo-TestQuotedValue -Value $pathText -QuoteChar $quoteChar

        if ($item.PSIsContainer) {
            New-TestCompletionResult -CompletionText $completionText -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-TestCompletionResult -CompletionText $completionText -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-TestOperandValueCompletions {
    param(
        [string]$ValueKind,
        [string]$CurrentWord
    )

    $values = switch ($ValueKind) {
        'Fd' {
            @(
                @{ Text = '0'; ToolTip = 'Standard input is opened on a terminal.' }
                @{ Text = '1'; ToolTip = 'Standard output is opened on a terminal.' }
                @{ Text = '2'; ToolTip = 'Standard error is opened on a terminal.' }
                @{ Text = '<fd>'; ToolTip = 'File descriptor number.' }
            )
        }
        'Integer' { @(@{ Text = '<integer>'; ToolTip = 'INTEGER operand.' }) }
        'String' { @(@{ Text = '<string>'; ToolTip = 'STRING operand.' }) }
        default { @() }
    }

    foreach ($value in $values) {
        if (-not [string]::IsNullOrEmpty($CurrentWord) -and
            -not $value.Text.StartsWith($CurrentWord, [System.StringComparison]::Ordinal)) {
            continue
        }

        New-TestCompletionResult -CompletionText $value.Text -ListItemText $value.Text -ResultType 'ParameterValue' -ToolTip $value.ToolTip
    }
}

function Complete-Test {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $state = Get-TestLineState -CommandAst $commandAst -CursorPosition $cursorPosition
    $currentWord = $state.CurrentWord
    $operands = @($state.Operands)

    # An operator that takes a typed (non-path) operand owns the slot after it.
    if ($operands.Count -gt 0) {
        $previous = Get-TestOperatorSpec -Token $operands[-1]
        if ($null -ne $previous -and $previous.ValueKind -in @('Fd', 'Integer', 'String')) {
            return @(Get-TestOperandValueCompletions -ValueKind $previous.ValueKind -CurrentWord $currentWord)
        }
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($spec in Get-TestOperatorCatalog) {
                if ($spec.Token.StartsWith('-') -and $spec.Token.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-TestCompletionResult -CompletionText $spec.Token -ListItemText $spec.Token -ResultType 'ParameterName' -ToolTip $spec.Description
                }
            }
        )
    }

    # '!', '=', '!=', '(' and ')' are operators too, and never start with '-'.
    # '(' and ')' only reach a native completer in their quoted form, because
    # PowerShell parses a bare parenthesis as a sub-expression, so the quoted
    # spelling is echoed back when the typed word is quoted.
    $bareWord = ConvertFrom-TestTypedWord -Value $currentWord
    if (-not [string]::IsNullOrEmpty($bareWord)) {
        $quoteChar = if ($currentWord -match '^[''"\u2018-\u201E]') { $currentWord.Substring(0, 1) } else { '' }
        $operatorMatches = @(
            foreach ($spec in Get-TestOperatorCatalog) {
                if ($spec.Token.StartsWith('-')) { continue }
                if (-not $spec.Token.StartsWith($bareWord, [System.StringComparison]::Ordinal)) { continue }
                $text = ConvertTo-TestQuotedValue -Value $spec.Token -QuoteChar $quoteChar
                New-TestCompletionResult -CompletionText $text -ListItemText $spec.Token -ResultType 'ParameterName' -ToolTip $spec.Description
            }
        )
        if ($operatorMatches.Count -gt 0) {
            return $operatorMatches
        }
    }

    Get-TestPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'test', 'test.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Test -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
