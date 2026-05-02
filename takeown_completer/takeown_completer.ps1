<#
.SYNOPSIS
    Registers a native PowerShell argument completer for takeown.

.DESCRIPTION
    Provides a static-first native completer for `takeown` and `takeown.exe`.

    The completer covers:
    - slash-style switch completion
    - switch/value state transitions for `/S`, `/U`, `/P`, `/F`, and `/D`
    - local file and directory completion for `/F`
    - placeholder-only completion for remote system, user, password, and UNC slots

    The script keeps its top level compatible with `Import-CompleterScript`.
#>

Set-StrictMode -Version 2.0

function New-TakeownCompletionResult {
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

function Remove-TakeownOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-TakeownQuotedValue {
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

function Get-TakeownTokenState {
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

function Get-TakeownArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    $tokensBeforeCurrent = @($TokenState.TokensBeforeCurrent)
    $currentArgument = if ($null -eq $TokenState.CurrentToken) { '' } else { $TokenState.CurrentToken }

    if ($tokensBeforeCurrent.Count -gt 0) {
        $argumentsBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip 1)
    } else {
        $argumentsBeforeCurrent = @()
    }

    if ($tokensBeforeCurrent.Count -eq 0 -and $currentArgument -match '^(?i)takeown(?:\.exe)?$') {
        $currentArgument = ''
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = $argumentsBeforeCurrent
        CurrentArgument        = $currentArgument
    }
}

function Get-TakeownCatalog {
    if (Get-Variable -Name TakeownCompletionCatalog -Scope Script -ErrorAction SilentlyContinue) {
        return $script:TakeownCompletionCatalog
    }

    $switches = @(
        [pscustomobject]@{ Token = '/S';       Description = 'Specifies the remote system to connect to.'; ValueKind = 'System' }
        [pscustomobject]@{ Token = '/U';       Description = 'Specifies the user context under which the command should execute.'; ValueKind = 'User' }
        [pscustomobject]@{ Token = '/P';       Description = 'Specifies the password for the given user context. Prompts if omitted.'; ValueKind = 'Password' }
        [pscustomobject]@{ Token = '/F';       Description = 'Specifies the file or directory name pattern.'; ValueKind = 'Path' }
        [pscustomobject]@{ Token = '/A';       Description = 'Gives ownership to the Administrators group instead of the current user.' }
        [pscustomobject]@{ Token = '/R';       Description = 'Operates on files in the specified directory and all subdirectories.' }
        [pscustomobject]@{ Token = '/D';       Description = 'Default answer used during recursive processing when list-folder permission is missing.'; ValueKind = 'Prompt' }
        [pscustomobject]@{ Token = '/SKIPSL';  Description = 'Do not follow symbolic links. Only applicable with /R.' }
        [pscustomobject]@{ Token = '/?';       Description = 'Displays takeown help.' }
    )

    $switchLookup = @{}
    foreach ($switch in $switches) {
        $switchLookup[$switch.Token.ToUpperInvariant()] = $switch
    }

    $systemSuggestions = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
        $systemSuggestions.Add($env:COMPUTERNAME)
    }
    $systemSuggestions.Add('<system>')

    $userSuggestions = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
        $userSuggestions.Add($env:USERNAME)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERDOMAIN) -and -not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
        $userSuggestions.Add($env:USERDOMAIN + '\' + $env:USERNAME)
    }
    $userSuggestions.Add('<user>')
    $userSuggestions.Add('<domain\user>')

    $script:TakeownCompletionCatalog = [pscustomobject]@{
        Switches           = $switches
        SwitchLookup       = $switchLookup
        SystemSuggestions  = @($systemSuggestions | Select-Object -Unique)
        UserSuggestions    = @($userSuggestions | Select-Object -Unique)
        PromptSuggestions  = @('Y', 'N')
    }

    $script:TakeownCompletionCatalog
}

function Get-TakeownPendingValueSwitch {
    param([string[]]$ArgumentsBeforeCurrent)

    if ($ArgumentsBeforeCurrent.Count -eq 0) {
        return $null
    }

    $lastArgument = $ArgumentsBeforeCurrent[$ArgumentsBeforeCurrent.Count - 1]
    Get-TakeownValueSwitchName -Argument $lastArgument
}

function Get-TakeownValueSwitchName {
    param([string]$Argument)

    if ([string]::IsNullOrWhiteSpace($Argument)) {
        return $null
    }

    switch ($Argument.ToUpperInvariant()) {
        '/S' { return '/S' }
        '/U' { return '/U' }
        '/P' { return '/P' }
        '/F' { return '/F' }
        '/D' { return '/D' }
    }

    $null
}

function Get-TakeownState {
    param([string[]]$Arguments)

    $state = [pscustomobject]@{
        HasSystemValue        = $false
        HasUserValue          = $false
        HasPasswordSwitch     = $false
        HasPasswordValue      = $false
        HasFileValue          = $false
        HasAdministrators     = $false
        HasRecurse            = $false
        HasDefaultAnswerValue = $false
        HasSkipSymbolicLinks  = $false
        HasHelp               = $false
    }

    $pendingValueSwitch = $null

    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]

        if ($null -ne $pendingValueSwitch) {
            if (-not [string]::IsNullOrWhiteSpace($argument) -and -not $argument.StartsWith('/')) {
                switch ($pendingValueSwitch) {
                    '/S' { $state.HasSystemValue = $true }
                    '/U' { $state.HasUserValue = $true }
                    '/P' { $state.HasPasswordValue = $true }
                    '/F' { $state.HasFileValue = $true }
                    '/D' { $state.HasDefaultAnswerValue = $true }
                }

                $pendingValueSwitch = $null
                continue
            }

            $pendingValueSwitch = $null
        }

        switch ($argument.ToUpperInvariant()) {
            '/S' { $pendingValueSwitch = '/S' }
            '/U' { $pendingValueSwitch = '/U' }
            '/P' {
                $state.HasPasswordSwitch = $true
                $pendingValueSwitch = '/P'
            }
            '/F' { $pendingValueSwitch = '/F' }
            '/A' { $state.HasAdministrators = $true }
            '/R' { $state.HasRecurse = $true }
            '/D' { $pendingValueSwitch = '/D' }
            '/SKIPSL' { $state.HasSkipSymbolicLinks = $true }
            '/?' { $state.HasHelp = $true }
        }
    }

    $state
}

function Get-TakeownSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State
    )

    $catalog = Get-TakeownCatalog
    $allowedTokens = New-Object System.Collections.Generic.List[string]

    if (-not $State.HasFileValue) {
        if (-not $State.HasSystemValue) {
            $allowedTokens.Add('/S')
        }

        if ($State.HasSystemValue -and -not $State.HasUserValue) {
            $allowedTokens.Add('/U')
        }

        if ($State.HasUserValue -and -not $State.HasPasswordSwitch) {
            $allowedTokens.Add('/P')
        }

        $allowedTokens.Add('/F')
    }

    if ($State.HasFileValue -and -not $State.HasAdministrators) {
        $allowedTokens.Add('/A')
    }

    if ($State.HasFileValue -and -not $State.HasRecurse) {
        $allowedTokens.Add('/R')
    }

    if ($State.HasRecurse -and -not $State.HasDefaultAnswerValue) {
        $allowedTokens.Add('/D')
    }

    if ($State.HasRecurse -and -not $State.HasSkipSymbolicLinks) {
        $allowedTokens.Add('/SKIPSL')
    }

    $allowedTokens.Add('/?')

    foreach ($token in @($allowedTokens | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            -not $token.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $metadata = $catalog.SwitchLookup[$token.ToUpperInvariant()]
        New-TakeownCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $metadata.Description -ListItemText $token
    }
}

function Get-TakeownValueCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$Suggestions,
        [string]$Placeholder,
        [string]$ToolTip,
        [switch]$PlaceholderOnlyOnMiss
    )

    $typedValue = if ($null -eq $CurrentWord) { '' } else { Remove-TakeownOuterQuotes -Value $CurrentWord }
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($suggestion in $Suggestions) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $suggestion.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-TakeownCompletionResult -CompletionText $suggestion -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText $suggestion))
    }

    if ($results.Count -eq 0) {
        $fallback = if (-not $PlaceholderOnlyOnMiss -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
            $CurrentWord
        } else {
            $Placeholder
        }
        [void]$results.Add((New-TakeownCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText $fallback))
    }

    @($results.ToArray())
}

function Get-TakeownUncPathCompletions {
    param(
        [string]$CurrentValue,
        [string]$ToolTip
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $cleanValue = Remove-TakeownOuterQuotes -Value $typedValue
    $results = New-Object System.Collections.Generic.List[object]

    $placeholder = if ($cleanValue -match '^\\\\(?<computer>[^\\]+)\\(?<share>[^\\]+)\\') {
        '\\' + $Matches.computer + '\' + $Matches.share + '\<path>'
    } elseif ($cleanValue -match '^\\\\(?<computer>[^\\]+)\\') {
        '\\' + $Matches.computer + '\<share>\'
    } else {
        '\\<computer>\'
    }

    if (-not [string]::IsNullOrWhiteSpace($typedValue)) {
        [void]$results.Add((New-TakeownCompletionResult -CompletionText $typedValue -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText $typedValue))
    }

    [void]$results.Add((New-TakeownCompletionResult -CompletionText $placeholder -ResultType 'ParameterValue' -ToolTip 'UNC path placeholder. Remote shares are not enumerated during completion.' -ListItemText $placeholder))

    @($results.ToArray())
}

function Get-TakeownPathCompletions {
    param(
        [string]$CurrentValue,
        [string]$ToolTip
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $cleanValue = Remove-TakeownOuterQuotes -Value $typedValue
    $alwaysQuote = $typedValue.StartsWith('"')
    $results = New-Object System.Collections.Generic.List[object]

    if ($cleanValue.StartsWith('\\')) {
        return @(Get-TakeownUncPathCompletions -CurrentValue $typedValue -ToolTip $ToolTip)
    }

    $parentPath = '.'
    $leaf = ''

    if (-not [string]::IsNullOrWhiteSpace($cleanValue)) {
        if ($cleanValue -match '^[A-Za-z]:$') {
            $parentPath = $cleanValue + '\'
        } elseif ($cleanValue.EndsWith('\') -or $cleanValue.EndsWith('/')) {
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

        $candidate = if ($parentPath -eq '.') { $item.Name } else { Join-Path -Path $parentPath -ChildPath $item.Name }
        if ($item.PSIsContainer -and -not ($candidate.EndsWith('\') -or $candidate.EndsWith('/'))) {
            $candidate += '\'
        }

        $completionText = ConvertTo-TakeownQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        [void]$results.Add((New-TakeownCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $item.FullName -ListItemText $completionText))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($typedValue)) { '<path>' } else { $typedValue }
        [void]$results.Add((New-TakeownCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText $fallback))
    }

    @($results.ToArray())
}

function Get-TakeownTerminalCompletions {
    param([string]$CurrentWord)

    $completionText = if ([string]::IsNullOrEmpty($CurrentWord)) { ' ' } else { $CurrentWord }
    $listItemText = '[terminal] /? already ends the command'
    $toolTip = 'No further arguments are valid after /?.'
    @(
        New-TakeownCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $listItemText
    )
}

function Get-TakeownRequiresRecurseCompletions {
    param([string]$CurrentWord)

    $completionText = if ([string]::IsNullOrEmpty($CurrentWord)) { ' ' } else { $CurrentWord }
    $listItemText = '[requires /R] /D only accepts Y or N with /R'
    $toolTip = 'takeown only accepts /D values when /R is present.'
    @(
        New-TakeownCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $listItemText
    )
}

function Complete-Takeown {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $tokenState = Get-TakeownTokenState -Line $commandAst.ToString() -CursorPosition $cursorPosition
    $argumentState = Get-TakeownArgumentsFromTokenState -TokenState $tokenState
    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)

    if ($hasTrailingSpace -and -not [string]::IsNullOrEmpty($argumentState.CurrentArgument)) {
        $currentWord = ''
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent + $argumentState.CurrentArgument)
    } else {
        $currentWord = if ($null -eq $argumentState.CurrentArgument) { '' } else { $argumentState.CurrentArgument }
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent)
    }

    $state = Get-TakeownState -Arguments $argumentsBeforeCurrent
    if ($state.HasHelp) {
        return @(Get-TakeownTerminalCompletions -CurrentWord $currentWord)
    }

    $expectedValueSwitch = Get-TakeownPendingValueSwitch -ArgumentsBeforeCurrent $argumentsBeforeCurrent
    if ($null -eq $expectedValueSwitch) {
        $inlineValueSwitch = Get-TakeownValueSwitchName -Argument $currentWord
        if ($null -ne $inlineValueSwitch) {
            $expectedValueSwitch = $inlineValueSwitch
            $currentWord = ''
        }
    }

    $catalog = Get-TakeownCatalog

    if ($null -ne $expectedValueSwitch) {
        switch ($expectedValueSwitch) {
            '/S' {
                return @(Get-TakeownValueCompletions -CurrentWord $currentWord -Suggestions $catalog.SystemSuggestions -Placeholder '<system>' -ToolTip $catalog.SwitchLookup['/S'].Description)
            }
            '/U' {
                return @(Get-TakeownValueCompletions -CurrentWord $currentWord -Suggestions $catalog.UserSuggestions -Placeholder '<domain\user>' -ToolTip $catalog.SwitchLookup['/U'].Description)
            }
            '/P' {
                return @(Get-TakeownValueCompletions -CurrentWord $currentWord -Suggestions @('<password>') -Placeholder '<password>' -ToolTip 'Password placeholder only. The completer never inspects secrets.' -PlaceholderOnlyOnMiss)
            }
            '/F' {
                return @(Get-TakeownPathCompletions -CurrentValue $currentWord -ToolTip $catalog.SwitchLookup['/F'].Description)
            }
            '/D' {
                if (-not $state.HasRecurse) {
                    return @(Get-TakeownRequiresRecurseCompletions -CurrentWord $currentWord)
                }

                return @(Get-TakeownValueCompletions -CurrentWord $currentWord -Suggestions $catalog.PromptSuggestions -Placeholder '<Y|N>' -ToolTip $catalog.SwitchLookup['/D'].Description)
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('/')) {
        return @(Get-TakeownSwitchCompletions -CurrentWord $currentWord -State $state)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('takeown', 'takeown.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Takeown -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
