# sdelete tab completion for PowerShell
# Static-first native completer for SDelete with risk-bounded mode-aware suggestions.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name SDeleteCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:SDeleteCompletionCatalog = @{
        PassHints  = @('1', '3', '7', '10')
        DriveCache = $null
        Switches   = @(
            @{ Token = '-c'; Description = 'Clean free space.'; TakesValue = $false; Modes = @('free', 'root') }
            @{ Token = '-f'; Description = 'Force bare-letter arguments to be treated as file or directory paths.'; TakesValue = $false; Modes = @('delete', 'root') }
            @{ Token = '-p'; Description = 'Specifies number of overwrite passes.'; TakesValue = $true; ValueKind = 'Passes'; Modes = @('delete', 'free', 'root') }
            @{ Token = '-q'; Description = 'Quiet mode.'; TakesValue = $false; Modes = @('delete', 'free', 'root') }
            @{ Token = '-r'; Description = 'Remove the read-only attribute.'; TakesValue = $false; Modes = @('delete', 'root') }
            @{ Token = '-s'; Description = 'Recurse subdirectories.'; TakesValue = $false; Modes = @('delete', 'root') }
            @{ Token = '-z'; Description = 'Zero free space.'; TakesValue = $false; Modes = @('free', 'root') }
            @{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.'; TakesValue = $false; Modes = @('delete', 'free', 'root') }
            @{ Token = '-accepteula'; Description = 'Accept the Sysinternals license agreement (suppresses the first-run dialog).'; TakesValue = $false; Modes = @('delete', 'free', 'root') }
            @{ Token = '/?'; Description = 'Show SDelete help.'; TakesValue = $false; Modes = @('delete', 'free', 'root') }
        )
    }
}

function New-SDeleteCompletionResult {
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

function Remove-SDeleteOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertFrom-SDeleteTypedWord {
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

function ConvertTo-SDeleteQuotedValue {
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

function Get-SDeleteTokenState {
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
        # Typographic quotes close a quote of their own class: U+2018-U+201B single, U+201C-U+201E double.
        $quoteClass = if ([string]$character -match '^[''\u2018-\u201B]$') { [char]39 } elseif ([string]$character -match '^["\u201C-\u201E]$') { [char]34 } else { [char]0 }
        if ($quoteClass -ne [char]0) {
            if ($quoteChar -eq [char]0) {
                $quoteChar = $quoteClass
            } elseif ($quoteChar -eq $quoteClass) {
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

function Get-SDeleteState {
    param([string[]]$TokensBeforeCurrent)

    $usedSwitches = @{}
    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingValueKind = $null
    $helpRequested = $false
    $passValue = $null

    foreach ($token in $TokensBeforeCurrent) {
        $cleanToken = Remove-SDeleteOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($pendingValueKind) {
            if ($pendingValueKind -eq 'Passes') {
                $passValue = $cleanToken
            }

            $pendingValueKind = $null
            continue
        }

        if ($cleanToken.StartsWith('-') -or $cleanToken.StartsWith('/')) {
            $lookup = $cleanToken.ToLowerInvariant()
            $usedSwitches[$lookup] = $true
            if ($lookup -eq '-p') {
                $pendingValueKind = 'Passes'
            }
            if ($lookup -eq '/?') {
                $helpRequested = $true
            }
            continue
        }

        $positionals.Add($cleanToken)
    }

    $mode = if ($usedSwitches.ContainsKey('-c') -or $usedSwitches.ContainsKey('-z')) { 'free' } else { 'delete' }

    [pscustomobject]@{
        UsedSwitches      = $usedSwitches
        Positionals       = @($positionals)
        PendingValueKind  = $pendingValueKind
        HelpRequested     = $helpRequested
        PassValue         = $passValue
        Mode              = $mode
    }
}

function Get-SDeleteSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State
    )

    $cleanCurrent = Remove-SDeleteOuterQuotes -Value $CurrentWord
    $freeModeChosen = ($State.UsedSwitches.ContainsKey('-c') -or $State.UsedSwitches.ContainsKey('-z'))

    foreach ($switchSpec in $script:SDeleteCompletionCatalog.Switches) {
        $lookup = $switchSpec.Token.ToLowerInvariant()
        if ($State.UsedSwitches.ContainsKey($lookup)) {
            continue
        }

        if ($freeModeChosen -and $switchSpec.Token -in @('-r', '-s', '-f')) {
            continue
        }

        if (-not $freeModeChosen -and $State.Positionals.Count -gt 0 -and $switchSpec.Token -in @('-c', '-z')) {
            continue
        }

        if ($freeModeChosen -and (($switchSpec.Token -eq '-c' -and $State.UsedSwitches.ContainsKey('-z')) -or ($switchSpec.Token -eq '-z' -and $State.UsedSwitches.ContainsKey('-c')))) {
            continue
        }

        if ($switchSpec.Token.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-SDeleteCompletionResult -CompletionText $switchSpec.Token -ListItemText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description
        }
    }
}

function Get-SDeleteDeletePathCompletions {
    param([string]$InputPath)

    $cleanInput = ConvertFrom-SDeleteTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # The typed directory part (through the last separator, or a bare drive such as C:) is kept
    # verbatim, so a typed .\ or ./ prefix and the typed separator style survive.
    $directoryText = if ($cleanInput -match '^(.*[\\/]|[A-Za-z]:)') { $Matches[1] } else { '' }
    $parent = if ($directoryText) { $directoryText } else { '.' }
    $leaf = $cleanInput.Substring($directoryText.Length)

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') }

    foreach ($item in ($items | Sort-Object -Property @{ Expression = 'PSIsContainer'; Descending = $true }, Name)) {
        $pathText = $directoryText + $item.Name
        if (-not $directoryText -and $pathText -match '^[-\u2013-\u2015]') {
            # A bare word starting with a dash parses as a parameter; anchor it to the current directory.
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $quotedPath = ConvertTo-SDeleteQuotedValue -Value $pathText -QuoteChar $quoteChar
        $resultType = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }
        New-SDeleteCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType $resultType -ToolTip $item.FullName
    }
}

function Get-SDeletePassCompletions {
    param([string]$CurrentWord)

    $cleanCurrent = Remove-SDeleteOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($hint in $script:SDeleteCompletionCatalog.PassHints) {
        if ($hint.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            $results.Add((New-SDeleteCompletionResult -CompletionText $hint -ListItemText $hint -ResultType 'ParameterValue' -ToolTip 'Overwrite pass count for SDelete.'))
        }
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-SDeleteCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip 'Overwrite pass count for SDelete.'))
    }

    if ($results.Count -eq 0 -and [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-SDeleteCompletionResult -CompletionText ' ' -ListItemText '<passes>' -ResultType 'ParameterValue' -ToolTip 'Overwrite pass count for SDelete.'))
    }

    @($results.ToArray())
}

function Get-SDeleteDriveLetterCache {
    if ($null -eq $script:SDeleteCompletionCatalog.DriveCache) {
        $script:SDeleteCompletionCatalog.DriveCache = @(
            Get-PSDrive -PSProvider FileSystem -ErrorAction Ignore |
                Where-Object { $_.Name.Length -eq 1 } |
                Sort-Object -Property Name |
                ForEach-Object { $_.Name + ':' }
        )
    }

    @($script:SDeleteCompletionCatalog.DriveCache)
}

function Get-SDeleteFreeSpaceTargetCompletions {
    param([string]$CurrentWord)

    $cleanCurrent = Remove-SDeleteOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($candidate in (Get-SDeleteDriveLetterCache)) {
        if ($candidate.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            $results.Add((New-SDeleteCompletionResult -CompletionText $candidate -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Free-space cleaning target drive ' + $candidate)))
        }
    }

    foreach ($diskNumber in @('0', '1', '2')) {
        if ($diskNumber.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            $results.Add((New-SDeleteCompletionResult -CompletionText $diskNumber -ListItemText $diskNumber -ResultType 'ParameterValue' -ToolTip 'Sample physical disk number target.'))
        }
    }

    if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or '<drive:>'.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
        $results.Add((New-SDeleteCompletionResult -CompletionText '<drive:>' -ListItemText '<drive:>' -ResultType 'ParameterValue' -ToolTip 'Drive letter target for -c or -z mode.'))
    }

    if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or '<physical-disk-number>'.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
        $results.Add((New-SDeleteCompletionResult -CompletionText '<physical-disk-number>' -ListItemText '<physical-disk-number>' -ResultType 'ParameterValue' -ToolTip 'Physical disk number target for -c or -z mode.'))
    }

    @($results.ToArray())
}

function Get-SDeleteAmbiguousLetterResults {
    param([string]$CurrentWord)

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        return @()
    }

    $value = ConvertFrom-SDeleteTypedWord -Value $CurrentWord
    $quoteChar = if ($CurrentWord -match '^[''"\u2018-\u201E]') { $CurrentWord.Substring(0, 1) } else { '' }

    @(
        New-SDeleteCompletionResult -CompletionText (ConvertTo-SDeleteQuotedValue -Value $value -QuoteChar $quoteChar) -ListItemText $value -ResultType 'ParameterValue' -ToolTip 'Bare-letter paths are ambiguous for SDelete; use -f or a path separator to force file or directory mode.'
    )
}

function Complete-SDelete {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $line = $commandAst.ToString()
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    if ($relativeCursor -gt $line.Length) {
        $line = $line.PadRight($relativeCursor)
    }

    $tokenState = Get-SDeleteTokenState -Line $line -CursorPosition $relativeCursor
    $currentWord = $tokenState.CurrentToken

    $state = Get-SDeleteState -TokensBeforeCurrent @($tokenState.TokensBeforeCurrent | Select-Object -Skip 1)

    if ($state.HelpRequested) {
        return @(
            New-SDeleteCompletionResult -CompletionText ' ' -ListItemText '<complete>' -ResultType 'ParameterValue' -ToolTip 'SDelete help is terminal for completion.'
        )
    }

    if ($state.PendingValueKind -eq 'Passes') {
        return @(Get-SDeletePassCompletions -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and ($currentWord.StartsWith('-') -or $currentWord.StartsWith('/'))) {
        return @(Get-SDeleteSwitchCompletions -CurrentWord $currentWord -State $state)
    }

    $results = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrEmpty((Remove-SDeleteOuterQuotes -Value $currentWord))) {
        foreach ($switchItem in @(Get-SDeleteSwitchCompletions -CurrentWord '' -State $state)) {
            $results.Add($switchItem)
        }
    }

    if ($state.Mode -eq 'free') {
        foreach ($item in @(Get-SDeleteFreeSpaceTargetCompletions -CurrentWord $currentWord)) {
            $results.Add($item)
        }

        return @($results.ToArray())
    }

    if (-not $state.UsedSwitches.ContainsKey('-f') -and (ConvertFrom-SDeleteTypedWord -Value $currentWord) -match '^[A-Za-z]$') {
        foreach ($item in @(Get-SDeleteAmbiguousLetterResults -CurrentWord $currentWord)) {
            $results.Add($item)
        }
    }

    foreach ($item in @(Get-SDeleteDeletePathCompletions -InputPath $currentWord)) {
        $results.Add($item)
    }

    @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName 'sdelete', 'sdelete.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-SDelete -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
