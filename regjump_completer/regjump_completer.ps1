# regjump tab completion for PowerShell
# Small native completer for regjump with local registry-path completion and terminal clipboard handling.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name RegJumpCompletionCatalog -Scope Script -ErrorAction Ignore)) {
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
        ChildCache = @{}
        MaxChildResults = 300
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"?|''[^'']*''?|\S+') | ForEach-Object { $_.Value })
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
    foreach ($root in $script:RegJumpCompletionCatalog.RootKeys) {
        # regjump accepts both the abbreviated (HKLM) and standard (HKEY_LOCAL_MACHINE)
        # root form, so offer whichever one the typed text is a prefix of.
        $longName = $script:RegJumpCompletionCatalog.RootLongNames[$root]
        $displayRoot = if ($root.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            $root
        } elseif ($longName.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            $longName
        } else {
            continue
        }

        $candidate = $displayRoot + '\'
        New-RegJumpCompletionResult -CompletionText $candidate -ListItemText $candidate -ResultType 'ProviderContainer' -ToolTip ('Registry path to open in Regedit: ' + $displayRoot)
    }
}

function Get-RegJumpChildName {
    param(
        [string]$CanonicalRoot,
        [string]$SubKeyPath
    )

    $cacheKey = $CanonicalRoot + '\' + $SubKeyPath
    if ($script:RegJumpCompletionCatalog.ChildCache.ContainsKey($cacheKey)) {
        return @($script:RegJumpCompletionCatalog.ChildCache[$cacheKey])
    }

    # RegistryKey.GetSubKeyNames lists the names held by the parent without opening
    # each child, so it is ~40x faster than the Registry provider on HKCR, never
    # shows the provider's merged-view duplicates, and still lists keys the session
    # cannot open (SECURITY, BCD00000000).
    $baseKey = switch ($CanonicalRoot) {
        'HKLM' { [Microsoft.Win32.Registry]::LocalMachine }
        'HKCU' { [Microsoft.Win32.Registry]::CurrentUser }
        'HKCR' { [Microsoft.Win32.Registry]::ClassesRoot }
        'HKU' { [Microsoft.Win32.Registry]::Users }
        'HKCC' { [Microsoft.Win32.Registry]::CurrentConfig }
        default { $null }
    }

    $names = @()
    $subKey = $null
    $errorCountBefore = $Error.Count
    try {
        if ($null -ne $baseKey) {
            if ([string]::IsNullOrEmpty($SubKeyPath)) {
                $names = @($baseKey.GetSubKeyNames())
            } else {
                $subKey = $baseKey.OpenSubKey($SubKeyPath, $false)
                if ($null -ne $subKey) {
                    $names = @($subKey.GetSubKeyNames())
                }
            }
        }
    } catch {
        Write-Debug ('regjump completer: cannot enumerate ' + $cacheKey + ': ' + $_.Exception.Message)
        $names = @()
    } finally {
        if ($null -ne $subKey) {
            $subKey.Dispose()
        }

        # An unreadable key is an expected outcome while completing, not a fault to
        # leave behind in $Error.
        while ($Error.Count -gt $errorCountBefore) {
            $Error.RemoveAt(0)
        }
    }

    $script:RegJumpCompletionCatalog.ChildCache[$cacheKey] = $names
    @($names)
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
        $prefixPath = ''
        $leaf = ''
    } elseif ($remainder.EndsWith('\')) {
        $prefixPath = $remainder.TrimEnd('\')
        $leaf = ''
    } else {
        $lastSeparator = $remainder.LastIndexOf('\')
        if ($lastSeparator -lt 0) {
            $prefixPath = ''
            $leaf = $remainder
        } else {
            $prefixPath = $remainder.Substring(0, $lastSeparator)
            $leaf = $remainder.Substring($lastSeparator + 1)
        }
    }

    # Filter on the typed leaf before sorting, and cap the emitted count so a hive
    # the size of HKCR cannot stall the completion thread.
    $matchedNames = @(
        Get-RegJumpChildName -CanonicalRoot $canonicalRoot -SubKeyPath $prefixPath |
            Where-Object { $_.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase) } |
            Sort-Object |
            Select-Object -First $script:RegJumpCompletionCatalog.MaxChildResults
    )

    foreach ($childName in $matchedNames) {
        $candidate = if ([string]::IsNullOrWhiteSpace($prefixPath)) {
            $displayRoot + '\' + $childName + '\'
        } else {
            $displayRoot + '\' + $prefixPath + '\' + $childName + '\'
        }

        # Keys are emitted as ProviderContainer so the accepted text keeps inviting
        # the next level: an unquoted key already ends in '\', and for a quoted key
        # PSReadLine inserts the separator before the closing quote and parks the
        # cursor there, exactly as it does for a quoted directory.
        $completionText = if ($alwaysQuote -or $candidate -match '\s') {
            ConvertTo-RegJumpQuotedValue -Value $candidate.TrimEnd('\') -AlwaysQuote $true
        } else {
            $candidate
        }

        New-RegJumpCompletionResult -CompletionText $completionText -ListItemText $candidate -ResultType 'ProviderContainer' -ToolTip ('Registry path to open in Regedit: ' + $candidate.TrimEnd('\'))
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
        Get-RegJumpCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
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

    if ($pathProvided) {
        # Usage is 'regjump <<path>|-c>': once a path is present nothing else is valid.
        return @()
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        if ('-c'.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            return @(
                New-RegJumpCompletionResult -CompletionText '-c' -ListItemText '-c' -ResultType 'ParameterName' -ToolTip 'Copy the path from the clipboard.'
            )
        }

        return @()
    }

    $results = @()
    if ('-c'.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
        $results += New-RegJumpCompletionResult -CompletionText '-c' -ListItemText '-c' -ResultType 'ParameterName' -ToolTip 'Copy the path from the clipboard.'
    }
    $results += @(Get-RegJumpRegistryPathCompletions -CurrentValue $currentWord)
    @($results)
}

Register-ArgumentCompleter -Native -CommandName 'regjump', 'regjump.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-RegJump -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
