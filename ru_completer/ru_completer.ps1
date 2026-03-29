# ru tab completion for PowerShell
# Help-driven native completer for ru.exe with registry-aware absolute-path mode and non-loading hive mode.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name RuCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:RuCompletionCatalog = @{
        Initialized = $false
        CommandName = $null
        LevelHints  = @('0', '1', '2', '3', '5', '10')
        Switches    = @()
        SwitchByKey = @{}
        RootKeys    = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
        RootLongNames = @{
            'HKLM' = 'HKEY_LOCAL_MACHINE'
            'HKCU' = 'HKEY_CURRENT_USER'
            'HKCR' = 'HKEY_CLASSES_ROOT'
            'HKU'  = 'HKEY_USERS'
            'HKCC' = 'HKEY_CURRENT_CONFIG'
        }
        RootCanonicalByAlias = @{
            'HKLM'                = 'HKLM'
            'HKCU'                = 'HKCU'
            'HKCR'                = 'HKCR'
            'HKU'                 = 'HKU'
            'HKCC'                = 'HKCC'
            'HKEY_LOCAL_MACHINE'  = 'HKLM'
            'HKEY_CURRENT_USER'   = 'HKCU'
            'HKEY_CLASSES_ROOT'   = 'HKCR'
            'HKEY_USERS'          = 'HKU'
            'HKEY_CURRENT_CONFIG' = 'HKCC'
        }
        RootProviderPaths = @{
            'HKLM' = 'Registry::HKEY_LOCAL_MACHINE'
            'HKCU' = 'Registry::HKEY_CURRENT_USER'
            'HKCR' = 'Registry::HKEY_CLASSES_ROOT'
            'HKU'  = 'Registry::HKEY_USERS'
            'HKCC' = 'Registry::HKEY_CURRENT_CONFIG'
        }
    }
}

function Resolve-RuCommandName {
    if ($script:RuCompletionCatalog.CommandName) {
        return $script:RuCompletionCatalog.CommandName
    }

    $command = Get-Command -Name ru.exe, ru -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $script:RuCompletionCatalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $script:RuCompletionCatalog.CommandName
}

function Invoke-RuHelpText {
    $commandName = Resolve-RuCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName '/?' 2>$null)
    } catch {
        @()
    }
}

function New-RuCompletionResult {
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

function Remove-RuOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-RuQuotedValue {
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

function Initialize-RuCompletionCatalog {
    if ($script:RuCompletionCatalog.Initialized) {
        return
    }

    $catalog = [ordered]@{
        '-c'        = [pscustomobject]@{ Token = '-c'; Description = 'Print output as CSV.'; TakesValue = $false }
        '-ct'       = [pscustomobject]@{ Token = '-ct'; Description = 'Print CSV output with tab delimiters.'; TakesValue = $false }
        '-h'        = [pscustomobject]@{ Token = '-h'; Description = 'Load the specified hive file, analyze it, then unload it.'; TakesValue = $true; ValueKind = 'HiveFile' }
        '-l'        = [pscustomobject]@{ Token = '-l'; Description = 'Specify subkey depth of information.'; TakesValue = $true; ValueKind = 'Levels' }
        '-n'        = [pscustomobject]@{ Token = '-n'; Description = 'Do not recurse.'; TakesValue = $false }
        '-q'        = [pscustomobject]@{ Token = '-q'; Description = 'Quiet mode.'; TakesValue = $false }
        '-v'        = [pscustomobject]@{ Token = '-v'; Description = 'Show size of all subkeys.'; TakesValue = $false }
        '-nobanner' = [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.'; TakesValue = $false }
        '/?'        = [pscustomobject]@{ Token = '/?'; Description = 'Show ru help.'; TakesValue = $false }
    }

    foreach ($line in (Invoke-RuHelpText)) {
        if ($line -match '^\s*(-c(?:\[t\])?|-h|-l|-n|-q|-v|-nobanner)\s{2,}(.*)$') {
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

    $script:RuCompletionCatalog.Switches = @($catalog.Values)
    $script:RuCompletionCatalog.SwitchByKey = @{}
    foreach ($entry in $script:RuCompletionCatalog.Switches) {
        $script:RuCompletionCatalog.SwitchByKey[$entry.Token.ToLowerInvariant()] = $entry
    }

    $script:RuCompletionCatalog.Initialized = $true
}

function Get-RuCurrentToken {
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

function Get-RuArgumentTokens {
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

function Get-RuState {
    param([string[]]$TokensBeforeCurrent)

    Initialize-RuCompletionCatalog

    $usedSwitches = @{}
    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingValueKind = $null
    $helpRequested = $false
    $hiveFile = $null

    foreach ($token in $TokensBeforeCurrent) {
        $cleanToken = Remove-RuOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($pendingValueKind) {
            if ($pendingValueKind -eq 'HiveFile') {
                $hiveFile = $cleanToken
            }
            $pendingValueKind = $null
            continue
        }

        $lookup = $cleanToken.ToLowerInvariant()
        if ($script:RuCompletionCatalog.SwitchByKey.ContainsKey($lookup)) {
            $usedSwitches[$lookup] = $true
            $switchSpec = $script:RuCompletionCatalog.SwitchByKey[$lookup]
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
        HiveMode          = $usedSwitches.ContainsKey('-h')
        HiveFile          = $hiveFile
    }
}

function Get-RuSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State
    )

    $cleanCurrent = Remove-RuOuterQuotes -Value $CurrentWord
    $depthModeUsed = ($State.UsedSwitches.ContainsKey('-l') -or $State.UsedSwitches.ContainsKey('-n') -or $State.UsedSwitches.ContainsKey('-v'))

    foreach ($switchSpec in $script:RuCompletionCatalog.Switches) {
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
            New-RuCompletionResult -CompletionText $switchSpec.Token -ListItemText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description
        }
    }
}

function Get-RuFileCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-RuOuterQuotes -Value $InputPath
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

        $quoted = ConvertTo-RuQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        $resultType = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }
        New-RuCompletionResult -CompletionText $quoted -ListItemText $pathText -ResultType $resultType -ToolTip $item.FullName
    }
}

function Get-RuLevelCompletions {
    param([string]$CurrentWord)

    $cleanCurrent = Remove-RuOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($hint in $script:RuCompletionCatalog.LevelHints) {
        if ($hint.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            $results.Add((New-RuCompletionResult -CompletionText $hint -ListItemText $hint -ResultType 'ParameterValue' -ToolTip 'Subkey depth for ru -l.'))
        }
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-RuCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip 'Subkey depth for ru -l.'))
    }

    if ($results.Count -eq 0 -and [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-RuCompletionResult -CompletionText ' ' -ListItemText '<levels>' -ResultType 'ParameterValue' -ToolTip 'Subkey depth for ru -l.'))
    }

    @($results.ToArray())
}

function Get-RuRootSuggestions {
    param([string]$CurrentValue)

    $cleanCurrent = Remove-RuOuterQuotes -Value $CurrentValue
    $preferLongNames = $cleanCurrent.StartsWith('HKEY_', [System.StringComparison]::OrdinalIgnoreCase)
    foreach ($root in $script:RuCompletionCatalog.RootKeys) {
        $displayRoot = if ($preferLongNames) { $script:RuCompletionCatalog.RootLongNames[$root] } else { $root }
        $candidate = $displayRoot + '\'
        if ($candidate.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase) -or $displayRoot.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-RuCompletionResult -CompletionText $candidate -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Absolute registry path for ru: ' + $displayRoot)
        }
    }
}

function Get-RuRegistryPathCompletions {
    param([string]$CurrentValue)

    $cleanCurrent = Remove-RuOuterQuotes -Value $CurrentValue
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentValue) -and ($CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanCurrent)) {
        return @(Get-RuRootSuggestions -CurrentValue '')
    }

    if ($cleanCurrent -notmatch '\\') {
        return @(Get-RuRootSuggestions -CurrentValue $cleanCurrent)
    }

    $segments = $cleanCurrent -split '\\', 2
    $typedRoot = $segments[0].ToUpperInvariant()
    if (-not $script:RuCompletionCatalog.RootCanonicalByAlias.ContainsKey($typedRoot)) {
        return @(Get-RuRootSuggestions -CurrentValue $cleanCurrent)
    }

    $canonicalRoot = $script:RuCompletionCatalog.RootCanonicalByAlias[$typedRoot]
    $displayRoot = if ($typedRoot.StartsWith('HKEY_', [System.StringComparison]::OrdinalIgnoreCase)) {
        $script:RuCompletionCatalog.RootLongNames[$canonicalRoot]
    } else {
        $canonicalRoot
    }

    $remainder = if ($segments.Count -gt 1) { $segments[1] } else { '' }
    if ([string]::IsNullOrWhiteSpace($remainder)) {
        $providerPath = $script:RuCompletionCatalog.RootProviderPaths[$canonicalRoot]
        $prefixPath = ''
        $leaf = ''
    } elseif ($remainder.EndsWith('\')) {
        $providerPath = $script:RuCompletionCatalog.RootProviderPaths[$canonicalRoot] + '\' + $remainder.TrimEnd('\')
        $prefixPath = $remainder.TrimEnd('\')
        $leaf = ''
    } else {
        $lastSeparator = $remainder.LastIndexOf('\')
        if ($lastSeparator -lt 0) {
            $providerPath = $script:RuCompletionCatalog.RootProviderPaths[$canonicalRoot]
            $prefixPath = ''
            $leaf = $remainder
        } else {
            $prefixPath = $remainder.Substring(0, $lastSeparator)
            $leaf = $remainder.Substring($lastSeparator + 1)
            $providerPath = $script:RuCompletionCatalog.RootProviderPaths[$canonicalRoot] + '\' + $prefixPath
        }
    }

    $children = @(Get-ChildItem -LiteralPath $providerPath -ErrorAction SilentlyContinue)
    foreach ($child in ($children | Sort-Object -Property PSChildName)) {
        $childName = [string]$child.PSChildName
        if (-not $childName.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidate = if ([string]::IsNullOrWhiteSpace($prefixPath)) {
            $displayRoot + '\' + $childName + '\'
        } else {
            $displayRoot + '\' + $prefixPath + '\' + $childName + '\'
        }

        $quoted = ConvertTo-RuQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        New-RuCompletionResult -CompletionText $quoted -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Absolute registry path for ru: ' + $candidate.TrimEnd('\'))
    }
}

function Get-RuHiveRelativePathCompletions {
    param([string]$CurrentWord)

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        return @(
            New-RuCompletionResult -CompletionText ' ' -ListItemText '<relative-path>' -ResultType 'ParameterValue' -ToolTip 'Relative path inside the hive file. Completion does not load hives.'
        )
    }

    @(
        New-RuCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip 'Relative path inside the hive file. Completion does not load hives.'
    )
}

function Complete-Ru {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-RuCompletionCatalog

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-RuCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $state = Get-RuState -TokensBeforeCurrent (Get-RuArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition)

    if ($state.HelpRequested) {
        return @(
            New-RuCompletionResult -CompletionText ' ' -ListItemText '<complete>' -ResultType 'ParameterValue' -ToolTip 'ru help is terminal for completion.'
        )
    }

    switch ($state.PendingValueKind) {
        'Levels' { return @(Get-RuLevelCompletions -CurrentWord $currentWord) }
        'HiveFile' { return @(Get-RuFileCompletions -InputPath $currentWord) }
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-RuSwitchCompletions -CurrentWord $currentWord -State $state)
    }

    $results = New-Object System.Collections.Generic.List[object]
    $canOfferRootSwitches = [string]::IsNullOrEmpty($currentWord) -or $state.Positionals.Count -gt 0
    if ($canOfferRootSwitches) {
        foreach ($switchItem in @(Get-RuSwitchCompletions -CurrentWord '' -State $state)) {
            $results.Add($switchItem)
        }
    }

    if ($state.HiveMode) {
        if (-not $state.HiveFile) {
            foreach ($item in @(Get-RuFileCompletions -InputPath $currentWord)) {
                $results.Add($item)
            }
            return @($results.ToArray())
        }

        if ($state.Positionals.Count -eq 0) {
            foreach ($item in @(Get-RuHiveRelativePathCompletions -CurrentWord $currentWord)) {
                $results.Add($item)
            }
            return @($results.ToArray())
        }

        return @()
    }

    if ($state.Positionals.Count -eq 0) {
        foreach ($item in @(Get-RuRegistryPathCompletions -CurrentValue $currentWord)) {
            $results.Add($item)
        }
        return @($results.ToArray())
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'ru', 'ru.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Ru -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
