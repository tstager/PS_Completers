# regjump tab completion for PowerShell
# Small native completer for regjump with local registry-path completion and terminal clipboard handling.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name RegJumpCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:RegJumpCompletionCatalog = @{
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
    }
}

function New-RegJumpCompletionResult {
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

function Remove-RegJumpOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-RegJumpQuotedValue {
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

function Get-RegJumpCurrentToken {
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

function Get-RegJumpArgumentTokens {
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

function Get-RegJumpRootSuggestions {
    param([string]$CurrentValue)

    $cleanCurrent = Remove-RegJumpOuterQuotes -Value $CurrentValue
    $preferLongNames = $cleanCurrent.StartsWith('HKEY_', [System.StringComparison]::OrdinalIgnoreCase)
    foreach ($root in $script:RegJumpCompletionCatalog.RootKeys) {
        $displayRoot = if ($preferLongNames) { $script:RegJumpCompletionCatalog.RootLongNames[$root] } else { $root }
        $candidate = $displayRoot + '\'
        if ($candidate.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase) -or $displayRoot.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-RegJumpCompletionResult -CompletionText $candidate -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Registry path to open in Regedit: ' + $displayRoot)
        }
    }
}

function Get-RegJumpRegistryPathCompletions {
    param([string]$CurrentValue)

    $cleanCurrent = Remove-RegJumpOuterQuotes -Value $CurrentValue
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentValue) -and ($CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanCurrent)) {
        return @(Get-RegJumpRootSuggestions -CurrentValue '')
    }

    if ($cleanCurrent -notmatch '\\') {
        return @(Get-RegJumpRootSuggestions -CurrentValue $cleanCurrent)
    }

    $segments = $cleanCurrent -split '\\', 2
    $typedRoot = $segments[0].ToUpperInvariant()
    if (-not $script:RegJumpCompletionCatalog.RootCanonicalByAlias.ContainsKey($typedRoot)) {
        return @(Get-RegJumpRootSuggestions -CurrentValue $cleanCurrent)
    }

    $canonicalRoot = $script:RegJumpCompletionCatalog.RootCanonicalByAlias[$typedRoot]
    $displayRoot = if ($typedRoot.StartsWith('HKEY_', [System.StringComparison]::OrdinalIgnoreCase)) {
        $script:RegJumpCompletionCatalog.RootLongNames[$canonicalRoot]
    } else {
        $canonicalRoot
    }

    $remainder = if ($segments.Count -gt 1) { $segments[1] } else { '' }
    if ([string]::IsNullOrWhiteSpace($remainder)) {
        $providerPath = $script:RegJumpCompletionCatalog.RootProviderPaths[$canonicalRoot]
        $prefixPath = ''
        $leaf = ''
    } elseif ($remainder.EndsWith('\')) {
        $providerPath = $script:RegJumpCompletionCatalog.RootProviderPaths[$canonicalRoot] + '\' + $remainder.TrimEnd('\')
        $prefixPath = $remainder.TrimEnd('\')
        $leaf = ''
    } else {
        $lastSeparator = $remainder.LastIndexOf('\')
        if ($lastSeparator -lt 0) {
            $providerPath = $script:RegJumpCompletionCatalog.RootProviderPaths[$canonicalRoot]
            $prefixPath = ''
            $leaf = $remainder
        } else {
            $prefixPath = $remainder.Substring(0, $lastSeparator)
            $leaf = $remainder.Substring($lastSeparator + 1)
            $providerPath = $script:RegJumpCompletionCatalog.RootProviderPaths[$canonicalRoot] + '\' + $prefixPath
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

        $quoted = ConvertTo-RegJumpQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        New-RegJumpCompletionResult -CompletionText $quoted -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Registry path to open in Regedit: ' + $candidate.TrimEnd('\'))
    }
}

function Complete-RegJump {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-RegJumpCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $arguments = @(Get-RegJumpArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition)
    $clipboardMode = $false
    $pathProvided = $false

    foreach ($argument in $arguments) {
        $cleanArgument = Remove-RegJumpOuterQuotes -Value $argument
        if ([string]::IsNullOrWhiteSpace($cleanArgument)) {
            continue
        }

        if ($cleanArgument.ToLowerInvariant() -eq '-c') {
            $clipboardMode = $true
            continue
        }

        if (-not ($cleanArgument.StartsWith('-') -or $cleanArgument.StartsWith('/'))) {
            $pathProvided = $true
        }
    }

    if ($clipboardMode) {
        return @(
            New-RegJumpCompletionResult -CompletionText ' ' -ListItemText '<complete>' -ResultType 'ParameterValue' -ToolTip 'regjump -c copies the path from the clipboard and takes no further arguments.'
        )
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        if ('-c'.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            return @(
                New-RegJumpCompletionResult -CompletionText '-c' -ListItemText '-c' -ResultType 'ParameterName' -ToolTip 'Copy the path from the clipboard.'
            )
        }

        return @()
    }

    if (-not $pathProvided) {
        $results = @()
        if ('-c'.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            $results += New-RegJumpCompletionResult -CompletionText '-c' -ListItemText '-c' -ResultType 'ParameterName' -ToolTip 'Copy the path from the clipboard.'
        }
        $results += @(Get-RegJumpRegistryPathCompletions -CurrentValue $currentWord)
        return @($results)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'regjump', 'regjump.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-RegJump -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
