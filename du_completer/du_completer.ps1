# du tab completion for PowerShell
# Help-driven native completer for du.exe with level hints and directory-only operand completion.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name DuCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DuCompletionCatalog = @{
        Initialized  = $false
        CommandName  = $null
        LevelHints   = @('0', '1', '2', '3', '5', '10')
        Switches     = @()
        SwitchByKey  = @{}
    }
}

function Resolve-DuCommandName {
    if ($script:DuCompletionCatalog.CommandName) {
        return $script:DuCompletionCatalog.CommandName
    }

    $command = Get-Command -Name du.exe, du -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $script:DuCompletionCatalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $script:DuCompletionCatalog.CommandName
}

function Invoke-DuHelpText {
    $commandName = Resolve-DuCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName '/?' 2>$null)
    } catch {
        @()
    }
}

function New-DuCompletionResult {
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

function Remove-DuOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-DuQuotedValue {
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

function Initialize-DuCompletionCatalog {
    if ($script:DuCompletionCatalog.Initialized) {
        return
    }

    $catalog = [ordered]@{
        '-c'        = [pscustomobject]@{ Token = '-c'; Description = 'Print output as CSV.'; TakesValue = $false }
        '-ct'       = [pscustomobject]@{ Token = '-ct'; Description = 'Print CSV output with tab delimiters.'; TakesValue = $false }
        '-l'        = [pscustomobject]@{ Token = '-l'; Description = 'Specify subdirectory depth of information.'; TakesValue = $true; ValueKind = 'Levels' }
        '-n'        = [pscustomobject]@{ Token = '-n'; Description = 'Do not recurse.'; TakesValue = $false }
        '-q'        = [pscustomobject]@{ Token = '-q'; Description = 'Quiet mode.'; TakesValue = $false }
        '-u'        = [pscustomobject]@{ Token = '-u'; Description = 'Count each instance of a hardlinked file.'; TakesValue = $false }
        '-v'        = [pscustomobject]@{ Token = '-v'; Description = 'Show size of all subdirectories.'; TakesValue = $false }
        '-nobanner' = [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.'; TakesValue = $false }
        '/?'        = [pscustomobject]@{ Token = '/?'; Description = 'Show du help.'; TakesValue = $false }
    }

    $helpLines = Invoke-DuHelpText
    foreach ($line in $helpLines) {
        if ($line -match '^\s*(-c(?:\[t\])?|-l|-n|-q|-u|-v|-nobanner)\s{2,}(.*)$') {
            $token = $matches[1]
            $description = $matches[2].Trim()
            switch ($token.ToLowerInvariant()) {
                '-c[t]' {
                    $catalog['-c'] = [pscustomobject]@{ Token = '-c'; Description = $description; TakesValue = $false }
                    $catalog['-ct'] = [pscustomobject]@{ Token = '-ct'; Description = 'Print output as CSV with tab delimiters.'; TakesValue = $false }
                }
                default {
                    if ($catalog.Contains($token.ToLowerInvariant())) {
                        $entry = $catalog[$token.ToLowerInvariant()]
                        $catalog[$token.ToLowerInvariant()] = [pscustomobject]@{
                            Token       = $entry.Token
                            Description = $description
                            TakesValue  = $entry.TakesValue
                            ValueKind   = if ($entry.PSObject.Properties.Name -contains 'ValueKind') { $entry.ValueKind } else { $null }
                        }
                    }
                }
            }
        }
    }

    $script:DuCompletionCatalog.Switches = @($catalog.Values)
    $script:DuCompletionCatalog.SwitchByKey = @{}
    foreach ($entry in $script:DuCompletionCatalog.Switches) {
        $script:DuCompletionCatalog.SwitchByKey[$entry.Token.ToLowerInvariant()] = $entry
    }

    $script:DuCompletionCatalog.Initialized = $true
}

function Get-DuCurrentToken {
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

function Get-DuArgumentTokens {
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

function Get-DuState {
    param([string[]]$TokensBeforeCurrent)

    Initialize-DuCompletionCatalog

    $usedSwitches = @{}
    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingValueKind = $null
    $helpRequested = $false

    foreach ($token in $TokensBeforeCurrent) {
        $cleanToken = Remove-DuOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($pendingValueKind) {
            $pendingValueKind = $null
            continue
        }

        $lookup = $cleanToken.ToLowerInvariant()
        if ($script:DuCompletionCatalog.SwitchByKey.ContainsKey($lookup)) {
            $usedSwitches[$lookup] = $true
            $switchSpec = $script:DuCompletionCatalog.SwitchByKey[$lookup]
            if ($lookup -eq '/?') {
                $helpRequested = $true
            }

            if ($switchSpec.TakesValue) {
                $pendingValueKind = $switchSpec.ValueKind
            }
            continue
        }

        $positionals.Add($cleanToken)
    }

    [pscustomobject]@{
        UsedSwitches      = $usedSwitches
        Positionals       = @($positionals)
        PendingValueKind  = $pendingValueKind
        HelpRequested     = $helpRequested
    }
}

function Get-DuSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State
    )

    Initialize-DuCompletionCatalog

    $cleanCurrent = Remove-DuOuterQuotes -Value $CurrentWord
    $depthModeUsed = ($State.UsedSwitches.ContainsKey('-l') -or $State.UsedSwitches.ContainsKey('-n') -or $State.UsedSwitches.ContainsKey('-v'))

    foreach ($switchSpec in $script:DuCompletionCatalog.Switches) {
        $lookup = $switchSpec.Token.ToLowerInvariant()
        if ($State.UsedSwitches.ContainsKey($lookup)) {
            continue
        }

        if ($switchSpec.Token -eq '-ct' -and $State.UsedSwitches.ContainsKey('-c')) {
            continue
        }

        if ($switchSpec.Token -eq '-c' -and $State.UsedSwitches.ContainsKey('-ct')) {
            continue
        }

        if ($depthModeUsed -and $switchSpec.Token -in @('-l', '-n', '-v')) {
            continue
        }

        if ($switchSpec.Token.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-DuCompletionResult -CompletionText $switchSpec.Token -ListItemText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description
        }
    }
}

function Get-DuDirectoryCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-DuOuterQuotes -Value $InputPath
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
    $items = @(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like "$leaf*" }

    foreach ($item in ($items | Sort-Object -Property Name)) {
        if ($inputIsRooted) {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $pathText = $item.Name
        } else {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        }

        if (-not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $quotedPath = ConvertTo-DuQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        New-DuCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
    }
}

function Get-DuLevelCompletions {
    param([string]$CurrentWord)

    $cleanCurrent = Remove-DuOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($hint in $script:DuCompletionCatalog.LevelHints) {
        if ($hint.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            $results.Add((New-DuCompletionResult -CompletionText $hint -ListItemText $hint -ResultType 'ParameterValue' -ToolTip 'Subdirectory depth for du -l.'))
        }
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-DuCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip 'Subdirectory depth for du -l.'))
    }

    if ($results.Count -eq 0 -and [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-DuCompletionResult -CompletionText ' ' -ListItemText '<levels>' -ResultType 'ParameterValue' -ToolTip 'Subdirectory depth for du -l.'))
    }

    @($results.ToArray())
}

function Complete-Du {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-DuCompletionCatalog

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-DuCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $state = Get-DuState -TokensBeforeCurrent (Get-DuArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition)

    if ($state.HelpRequested) {
        return @(
            New-DuCompletionResult -CompletionText ' ' -ListItemText '<complete>' -ResultType 'ParameterValue' -ToolTip 'du help is terminal for completion.'
        )
    }

    if ($state.PendingValueKind -eq 'Levels') {
        return @(Get-DuLevelCompletions -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-DuSwitchCompletions -CurrentWord $currentWord -State $state)
    }

    if ($state.Positionals.Count -eq 0) {
        $results = @()
        $results += @(Get-DuDirectoryCompletions -InputPath $currentWord)
        foreach ($item in @(Get-DuSwitchCompletions -CurrentWord '' -State $state)) {
            $results += $item
        }

        return @($results)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'du', 'du.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Du -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
