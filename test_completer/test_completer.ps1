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

function Remove-TestOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-TestQuotedValue {
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

function Get-TestLineState {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [string]$WordToComplete,
        [int]$CursorPosition
    )

    $line = $CommandAst.Extent.Text
    $relative = $CursorPosition - $CommandAst.Extent.StartOffset
    $safeCursor = [Math]::Min([Math]::Max($relative, 0), $line.Length)
    $prefix = $line.Substring(0, $safeCursor)
    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })

    $currentWord = ''
    if ($CursorPosition -le $CommandAst.Extent.EndOffset -and $prefix -notmatch '\s$') {
        if ($parts.Count -gt 0) {
            $currentWord = $parts[-1]
            $parts = @($parts | Select-Object -First ($parts.Count - 1))
        } else {
            $currentWord = $WordToComplete
        }
    }

    $operands = @()
    if ($parts.Count -gt 1) {
        $operands = @($parts | Select-Object -Skip 1)
    }

    [pscustomobject]@{
        CurrentWord = $currentWord
        Operands    = $operands
    }
}

function Get-TestPathParent {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return '.'
    }

    if ($Candidate -match '[\\/]+$') {
        return $Candidate
    }

    $parent = Split-Path -Path $Candidate -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) {
        return '.'
    }

    $parent
}

function Test-TestPathContainer {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $false
    }

    Test-Path -LiteralPath $Candidate -PathType Container
}

function Get-TestPathCompletions {
    param(
        [string]$InputPath,
        [string[]]$Operands = @()
    )

    $cleanInput = Remove-TestOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    # An unquoted path containing a space arrives split across several words.
    # Walk left over the plain operands already on the line, rejoining them
    # until the candidate resolves to a real directory; the line prefix that
    # was rejoined is then stripped back off every completion, because the
    # engine only replaces the last whitespace-delimited fragment.
    $linePrefix = ''
    if (-not $alwaysQuote -and -not (Test-TestPathContainer -Candidate (Get-TestPathParent -Candidate $cleanInput))) {
        for ($i = $Operands.Count - 1; $i -ge 0; $i--) {
            $fragment = $Operands[$i]
            if ($fragment.StartsWith('-') -or $null -ne (Get-TestOperatorSpec -Token $fragment)) { break }
            $candidatePrefix = ((@($Operands | Select-Object -Skip $i)) -join ' ') + ' '
            $candidate = $candidatePrefix + $cleanInput
            if (Test-TestPathContainer -Candidate (Get-TestPathParent -Candidate $candidate)) {
                $linePrefix = $candidatePrefix
                $cleanInput = $candidate
                break
            }
        }
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
    $items = @($items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name)

    foreach ($item in $items) {
        $pathText = if ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $completionText = if ($linePrefix) {
            $pathText.Substring($linePrefix.Length)
        } else {
            ConvertTo-TestQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        }

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

    $state = Get-TestLineState -CommandAst $commandAst -WordToComplete $wordToComplete -CursorPosition $cursorPosition
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
    $bareWord = Remove-TestOuterQuotes -Value $currentWord
    if (-not [string]::IsNullOrEmpty($bareWord)) {
        $quoted = $bareWord -ne $currentWord
        $operatorMatches = @(
            foreach ($spec in Get-TestOperatorCatalog) {
                if ($spec.Token.StartsWith('-')) { continue }
                if (-not $spec.Token.StartsWith($bareWord, [System.StringComparison]::Ordinal)) { continue }
                $text = if ($quoted) { "'" + $spec.Token + "'" } else { $spec.Token }
                New-TestCompletionResult -CompletionText $text -ListItemText $spec.Token -ResultType 'ParameterName' -ToolTip $spec.Description
            }
        )
        if ($operatorMatches.Count -gt 0) {
            return $operatorMatches
        }
    }

    Get-TestPathCompletions -InputPath $currentWord -Operands $operands
}

Register-ArgumentCompleter -Native -CommandName 'test', 'test.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Test -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
