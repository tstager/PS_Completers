# RegDelNull tab completion for PowerShell
# Small native completer for RegDelNull with local registry-path completion and destructive-aware placeholders.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name RegDelNullCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:RegDelNullCompletionCatalog = @{
        RootKeys = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
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
        Switches = @(
            [pscustomobject]@{ Token = '-s'; Description = 'Recurse into subkeys.' }
            [pscustomobject]@{ Token = '-y'; Description = 'Suppress confirmation before deleting null-embedded keys.' }
            [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.' }
            [pscustomobject]@{ Token = '/?'; Description = 'Show RegDelNull help.' }
        )
    }
}

function New-RegDelNullCompletionResult {
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

function Remove-RegDelNullOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-RegDelNullQuotedValue {
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

function Get-RegDelNullCurrentToken {
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

function Get-RegDelNullArgumentTokens {
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

function Get-RegDelNullProviderPath {
    param([string]$KeyPath)

    $cleanKeyPath = Remove-RegDelNullOuterQuotes -Value $KeyPath
    if ([string]::IsNullOrWhiteSpace($cleanKeyPath)) {
        return $null
    }

    $root, $rest = $cleanKeyPath -split '\\', 2
    $rootAlias = $root.ToUpperInvariant()
    if (-not $script:RegDelNullCompletionCatalog.RootCanonicalByAlias.ContainsKey($rootAlias)) {
        return $null
    }

    $canonicalRoot = $script:RegDelNullCompletionCatalog.RootCanonicalByAlias[$rootAlias]
    if ([string]::IsNullOrWhiteSpace($rest)) {
        return $script:RegDelNullCompletionCatalog.RootProviderPaths[$canonicalRoot]
    }

    $script:RegDelNullCompletionCatalog.RootProviderPaths[$canonicalRoot] + '\' + $rest
}

function Get-RegDelNullRootSuggestions {
    param([string]$CurrentValue)

    $cleanCurrent = Remove-RegDelNullOuterQuotes -Value $CurrentValue
    $preferLongNames = $cleanCurrent.StartsWith('HKEY_', [System.StringComparison]::OrdinalIgnoreCase)
    foreach ($root in $script:RegDelNullCompletionCatalog.RootKeys) {
        $displayRoot = if ($preferLongNames) { $script:RegDelNullCompletionCatalog.RootLongNames[$root] } else { $root }
        $candidate = $displayRoot + '\'
        if ($candidate.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase) -or $displayRoot.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-RegDelNullCompletionResult -CompletionText $candidate -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Registry root ' + $displayRoot)
        }
    }
}

function Get-RegDelNullRegistryPathCompletions {
    param([string]$CurrentValue)

    $cleanCurrent = Remove-RegDelNullOuterQuotes -Value $CurrentValue
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentValue) -and ($CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanCurrent)) {
        return @(Get-RegDelNullRootSuggestions -CurrentValue '')
    }

    if ($cleanCurrent -notmatch '\\') {
        return @(Get-RegDelNullRootSuggestions -CurrentValue $cleanCurrent)
    }

    $segments = $cleanCurrent -split '\\', 2
    $typedRoot = $segments[0].ToUpperInvariant()
    if (-not $script:RegDelNullCompletionCatalog.RootCanonicalByAlias.ContainsKey($typedRoot)) {
        return @(Get-RegDelNullRootSuggestions -CurrentValue $cleanCurrent)
    }

    $canonicalRoot = $script:RegDelNullCompletionCatalog.RootCanonicalByAlias[$typedRoot]
    $displayRoot = if ($typedRoot.StartsWith('HKEY_', [System.StringComparison]::OrdinalIgnoreCase)) {
        $script:RegDelNullCompletionCatalog.RootLongNames[$canonicalRoot]
    } else {
        $canonicalRoot
    }

    $remainder = if ($segments.Count -gt 1) { $segments[1] } else { '' }
    if ([string]::IsNullOrWhiteSpace($remainder)) {
        $providerPath = $script:RegDelNullCompletionCatalog.RootProviderPaths[$canonicalRoot]
        $prefixPath = ''
        $leaf = ''
    } elseif ($remainder.EndsWith('\')) {
        $providerPath = $script:RegDelNullCompletionCatalog.RootProviderPaths[$canonicalRoot] + '\' + $remainder.TrimEnd('\')
        $prefixPath = $remainder.TrimEnd('\')
        $leaf = ''
    } else {
        $lastSeparator = $remainder.LastIndexOf('\')
        if ($lastSeparator -lt 0) {
            $providerPath = $script:RegDelNullCompletionCatalog.RootProviderPaths[$canonicalRoot]
            $prefixPath = ''
            $leaf = $remainder
        } else {
            $prefixPath = $remainder.Substring(0, $lastSeparator)
            $leaf = $remainder.Substring($lastSeparator + 1)
            $providerPath = $script:RegDelNullCompletionCatalog.RootProviderPaths[$canonicalRoot] + '\' + $prefixPath
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

        $quoted = ConvertTo-RegDelNullQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        New-RegDelNullCompletionResult -CompletionText $quoted -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Registry path to scan for embedded nulls: ' + $candidate.TrimEnd('\'))
    }
}

function Get-RegDelNullSwitchCompletions {
    param(
        [string]$CurrentWord,
        [hashtable]$UsedSwitches
    )

    $cleanCurrent = Remove-RegDelNullOuterQuotes -Value $CurrentWord
    foreach ($switchSpec in $script:RegDelNullCompletionCatalog.Switches) {
        $lookup = $switchSpec.Token.ToLowerInvariant()
        if ($UsedSwitches.ContainsKey($lookup)) {
            continue
        }

        if ($switchSpec.Token.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-RegDelNullCompletionResult -CompletionText $switchSpec.Token -ListItemText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description
        }
    }
}

function Complete-RegDelNull {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-RegDelNullCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $usedSwitches = @{}
    $pathProvided = $false
    $helpRequested = $false

    foreach ($token in (Get-RegDelNullArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition)) {
        $cleanToken = Remove-RegDelNullOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($cleanToken.StartsWith('-') -or $cleanToken.StartsWith('/')) {
            $lookup = $cleanToken.ToLowerInvariant()
            $usedSwitches[$lookup] = $true
            if ($lookup -eq '/?') {
                $helpRequested = $true
            }
            continue
        }

        $pathProvided = $true
    }

    if ($helpRequested) {
        return @(
            New-RegDelNullCompletionResult -CompletionText ' ' -ListItemText '<complete>' -ResultType 'ParameterValue' -ToolTip 'RegDelNull help is terminal for completion.'
        )
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and ($currentWord.StartsWith('-') -or $currentWord.StartsWith('/'))) {
        return @(Get-RegDelNullSwitchCompletions -CurrentWord $currentWord -UsedSwitches $usedSwitches)
    }

    if (-not $pathProvided) {
        $results = @()
        $results += @(Get-RegDelNullRegistryPathCompletions -CurrentValue $currentWord)
        $results += @(Get-RegDelNullSwitchCompletions -CurrentWord '' -UsedSwitches $usedSwitches)
        if ($results.Count -gt 0) {
            return @($results)
        }

        if (-not [string]::IsNullOrWhiteSpace($currentWord)) {
            return @(
                New-RegDelNullCompletionResult -CompletionText $currentWord -ListItemText $currentWord -ResultType 'ParameterValue' -ToolTip 'Registry path to scan and potentially delete embedded-null keys.'
            )
        }
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-RegDelNullSwitchCompletions -CurrentWord '' -UsedSwitches $usedSwitches)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'RegDelNull', 'RegDelNull.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-RegDelNull -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
