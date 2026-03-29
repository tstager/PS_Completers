# sdelete tab completion for PowerShell
# Static-first native completer for SDelete with risk-bounded mode-aware suggestions.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name SDeleteCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SDeleteCompletionCatalog = @{
        PassHints = @('1', '3', '7', '10')
        Switches  = @(
            [pscustomobject]@{ Token = '-c'; Description = 'Clean free space.'; TakesValue = $false; Modes = @('free', 'root') }
            [pscustomobject]@{ Token = '-f'; Description = 'Force bare-letter arguments to be treated as file or directory paths.'; TakesValue = $false; Modes = @('delete', 'root') }
            [pscustomobject]@{ Token = '-p'; Description = 'Specifies number of overwrite passes.'; TakesValue = $true; ValueKind = 'Passes'; Modes = @('delete', 'free', 'root') }
            [pscustomobject]@{ Token = '-q'; Description = 'Quiet mode.'; TakesValue = $false; Modes = @('delete', 'free', 'root') }
            [pscustomobject]@{ Token = '-r'; Description = 'Remove the read-only attribute.'; TakesValue = $false; Modes = @('delete', 'root') }
            [pscustomobject]@{ Token = '-s'; Description = 'Recurse subdirectories.'; TakesValue = $false; Modes = @('delete', 'root') }
            [pscustomobject]@{ Token = '-z'; Description = 'Zero free space.'; TakesValue = $false; Modes = @('free', 'root') }
            [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.'; TakesValue = $false; Modes = @('delete', 'free', 'root') }
            [pscustomobject]@{ Token = '/?'; Description = 'Show SDelete help.'; TakesValue = $false; Modes = @('delete', 'free', 'root') }
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

function ConvertTo-SDeleteQuotedValue {
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

function Get-SDeleteCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') {
        return ''
    }

    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
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

function Get-SDeleteArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += $element.Extent.Text
        }
    }

    $tokens
}

function Get-SDeleteState {
    param([string[]]$TokensBeforeCurrent)

    $usedSwitches = @{}
    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingValueKind = $null
    $helpRequested = $false

    foreach ($token in $TokensBeforeCurrent) {
        $cleanToken = Remove-SDeleteOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($pendingValueKind) {
            $positionals.Add($cleanToken)
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

    $cleanInput = Remove-SDeleteOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $inputIsRooted = -not [string]::IsNullOrWhiteSpace($cleanInput) -and [System.IO.Path]::IsPathRooted($cleanInput)
    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like "$leaf*" }

    foreach ($item in ($items | Sort-Object -Property @{ Expression = 'PSIsContainer'; Descending = $true }, Name)) {
        if ($inputIsRooted) {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $pathText = $item.Name
        } else {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $quotedPath = ConvertTo-SDeleteQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
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

function Get-SDeleteFreeSpaceTargetCompletions {
    param([string]$CurrentWord)

    $cleanCurrent = Remove-SDeleteOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Sort-Object -Property Name)) {
        $candidate = $drive.Name + ':'
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

    @(
        New-SDeleteCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip 'Bare-letter paths are ambiguous for SDelete; use -f or a path separator to force file or directory mode.'
    )
}

function Complete-SDelete {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-SDeleteCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $state = Get-SDeleteState -TokensBeforeCurrent (Get-SDeleteArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition)

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
    foreach ($switchItem in @(Get-SDeleteSwitchCompletions -CurrentWord '' -State $state)) {
        $results.Add($switchItem)
    }

    if ($state.Mode -eq 'free') {
        foreach ($item in @(Get-SDeleteFreeSpaceTargetCompletions -CurrentWord $currentWord)) {
            $results.Add($item)
        }

        return @($results.ToArray())
    }

    if (-not $state.UsedSwitches.ContainsKey('-f') -and (Remove-SDeleteOuterQuotes -Value $currentWord) -match '^[A-Za-z]$') {
        return @(Get-SDeleteAmbiguousLetterResults -CurrentWord $currentWord)
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
