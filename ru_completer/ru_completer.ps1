# ru tab completion for PowerShell
# Help-driven native completer for ru.exe with registry-aware absolute-path mode and non-loading hive mode.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name RuCompletionCatalog -Scope Script -ErrorAction Ignore)) {
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
        ChildCache = @{}
        ChildCacheTtlSeconds = 30
        ChildCacheMaxEntries = 256
        MaxChildResults = 300
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
        @($null | & $commandName '/?' 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })
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

    # A word opened with a quote (ASCII or typographic) is read by the PowerShell
    # tokenizer, which drops the quotes and undoes that quote style's escapes, even
    # when the quote has no closing partner yet. Elsewhere a backtick escapes the
    # next character.
    if ($Value -match '^[''"\u2018-\u201E]') {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
        return $tokens[0].Value
    }

    [regex]::Replace($Value, '`(.)|"$', { param($match) $match.Groups[1].Value })
}

function Get-RuTypedQuote {
    param([string]$Value)

    if ($Value -match '^[''"\u2018-\u201E]') { $Value.Substring(0, 1) } else { '' }
}

function ConvertTo-RuQuotedValue {
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
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]|^[-\u2013-\u2015]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
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

    # ru /? wraps option bodies onto indented continuation lines (-c and -h), and
    # -nobanner starts its body on the following line, so join every indented line
    # that follows an option token onto that option's description.
    $helpEntries = [ordered]@{}
    $currentToken = $null
    foreach ($line in (Invoke-RuHelpText)) {
        if ($line -match '^\s*(-c(?:\[t\])?|-h|-l|-n|-q|-v|-nobanner)(?:\s{2,}(.*))?$') {
            $currentToken = $matches[1].ToLowerInvariant()
            $helpEntries[$currentToken] = if ($matches.Count -gt 2) { $matches[2].Trim() } else { '' }
            continue
        }

        if ($currentToken -and $line -match '^\s{6,}(\S.*)$') {
            $helpEntries[$currentToken] = ($helpEntries[$currentToken] + ' ' + $matches[1].Trim()).Trim()
            continue
        }

        $currentToken = $null
    }

    foreach ($token in $helpEntries.Keys) {
        $description = $helpEntries[$token]
        if ([string]::IsNullOrWhiteSpace($description)) {
            continue
        }

        if ($token -eq '-c[t]') {
            $catalog['-c'] = [pscustomobject]@{ Token = '-c'; Description = $description; TakesValue = $false }
            $catalog['-ct'] = [pscustomobject]@{ Token = '-ct'; Description = 'Print output as CSV with tab delimiters.'; TakesValue = $false }
        } elseif ($catalog.Contains($token)) {
            $entry = $catalog[$token]
            $catalog[$token] = [pscustomobject]@{
                Token       = $entry.Token
                Description = $description
                TakesValue  = $entry.TakesValue
                ValueKind   = if ($entry.PSObject.Properties.Name -contains 'ValueKind') { $entry.ValueKind } else { $null }
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
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$Fallback
    )

    # The parser keeps an unterminated quote or a backtick-escaped space in one
    # element, so the word under the cursor is that element's text up to the cursor.
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        $extent = $element.Extent
        if ($extent.StartOffset -le $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
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
    $quoteChar = Get-RuTypedQuote -Value $InputPath

    # The typed directory part (through the last separator) is kept verbatim, so a typed
    # .\ or ./ prefix and the typed separator style survive.
    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    if ($separatorIndex -ge 0) {
        $directoryText = $cleanInput.Substring(0, $separatorIndex + 1)
        $parent = $directoryText
    } elseif ($cleanInput -match '^[A-Za-z]:') {
        $directoryText = $cleanInput.Substring(0, 2)
        $parent = $directoryText
    } else {
        $directoryText = ''
        $parent = '.'
    }
    $leaf = $cleanInput.Substring($directoryText.Length)

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') }

    foreach ($item in ($items | Sort-Object -Property @{ Expression = 'PSIsContainer'; Descending = $true }, Name)) {
        $pathText = $directoryText + $item.Name
        if (-not $directoryText -and $item.Name -match '^[-\u2013-\u2015]') {
            # A bare word starting with a dash parses as a parameter; anchor it to the current directory.
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $quoted = ConvertTo-RuQuotedValue -Value $pathText -QuoteChar $quoteChar
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
    param(
        [string]$CurrentValue,
        [string]$QuoteChar = ''
    )

    $cleanCurrent = Remove-RuOuterQuotes -Value $CurrentValue
    $preferLongNames = $cleanCurrent.StartsWith('HKEY_', [System.StringComparison]::OrdinalIgnoreCase)
    foreach ($root in $script:RuCompletionCatalog.RootKeys) {
        $displayRoot = if ($preferLongNames) { $script:RuCompletionCatalog.RootLongNames[$root] } else { $root }
        $candidate = $displayRoot + '\'
        if ($candidate.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase) -or $displayRoot.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-RuCompletionResult -CompletionText (ConvertTo-RuQuotedValue -Value $candidate -QuoteChar $QuoteChar) -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Absolute registry path for ru: ' + $displayRoot)
        }
    }
}

function Get-RuChildKeyState {
    param(
        [string]$CanonicalRoot,
        [string]$SubKeyPath
    )

    # Entries expire so keys created or deleted during the session show up on a later
    # Tab, and the table is cleared once it grows past its bound.
    $cache = $script:RuCompletionCatalog.ChildCache
    $now = [datetime]::UtcNow
    $cacheKey = $CanonicalRoot + '\' + $SubKeyPath
    if ($cache.ContainsKey($cacheKey)) {
        $entry = $cache[$cacheKey]
        if (($now - $entry.Captured).TotalSeconds -lt $script:RuCompletionCatalog.ChildCacheTtlSeconds) {
            return $entry
        }
    }

    # RegistryKey.GetSubKeyNames lists the names held by the parent without opening
    # each child, so it is ~40x faster than the Registry provider on HKCR and still
    # lists keys the session cannot open (SECURITY, BCD00000000). Opening a key the
    # session may not read throws, and that is recorded as Denied so the slot can
    # say so instead of looking empty.
    $baseKey = switch ($CanonicalRoot) {
        'HKLM' { [Microsoft.Win32.Registry]::LocalMachine }
        'HKCU' { [Microsoft.Win32.Registry]::CurrentUser }
        'HKCR' { [Microsoft.Win32.Registry]::ClassesRoot }
        'HKU' { [Microsoft.Win32.Registry]::Users }
        'HKCC' { [Microsoft.Win32.Registry]::CurrentConfig }
        default { $null }
    }

    $names = @()
    $denied = $false
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
        Write-Debug ('ru completer: cannot enumerate ' + $cacheKey + ': ' + $_.Exception.Message)
        $names = @()
        $denied = $true
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

    $state = [pscustomobject]@{ Names = @($names); Denied = $denied; Captured = $now }
    if (-not $cache.ContainsKey($cacheKey) -and $cache.Count -ge $script:RuCompletionCatalog.ChildCacheMaxEntries) {
        $cache.Clear()
    }
    $cache[$cacheKey] = $state
    $state
}

function Get-RuRegistryPathCompletions {
    param([string]$CurrentValue)

    $cleanCurrent = Remove-RuOuterQuotes -Value $CurrentValue
    $quoteChar = Get-RuTypedQuote -Value $CurrentValue

    if ([string]::IsNullOrWhiteSpace($cleanCurrent)) {
        return @(Get-RuRootSuggestions -CurrentValue '' -QuoteChar $quoteChar)
    }

    if ($cleanCurrent -notmatch '\\') {
        return @(Get-RuRootSuggestions -CurrentValue $cleanCurrent -QuoteChar $quoteChar)
    }

    $segments = $cleanCurrent -split '\\', 2
    $typedRoot = $segments[0].ToUpperInvariant()
    if (-not $script:RuCompletionCatalog.RootCanonicalByAlias.ContainsKey($typedRoot)) {
        return @(Get-RuRootSuggestions -CurrentValue $cleanCurrent -QuoteChar $quoteChar)
    }

    $canonicalRoot = $script:RuCompletionCatalog.RootCanonicalByAlias[$typedRoot]
    $displayRoot = if ($typedRoot.StartsWith('HKEY_', [System.StringComparison]::OrdinalIgnoreCase)) {
        $script:RuCompletionCatalog.RootLongNames[$canonicalRoot]
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

    $childState = Get-RuChildKeyState -CanonicalRoot $canonicalRoot -SubKeyPath $prefixPath
    if ($childState.Denied) {
        # Keep the typed path intact and say why nothing is listed, instead of
        # letting the engine substitute filesystem entries for a registry slot.
        return @(
            New-RuCompletionResult -CompletionText $CurrentValue -ListItemText '<access denied>' -ResultType 'ParameterValue' -ToolTip ('This session cannot read ' + $displayRoot + '\' + $prefixPath + '; run ru elevated to size it.')
        )
    }

    # Filter on the typed leaf before sorting, and cap the emitted count so a hive
    # the size of HKCR cannot stall the completion thread.
    $matchedNames = @(
        $childState.Names |
            Where-Object { $_.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase) } |
            Sort-Object |
            Select-Object -First $script:RuCompletionCatalog.MaxChildResults
    )

    foreach ($childName in $matchedNames) {
        $candidate = if ([string]::IsNullOrWhiteSpace($prefixPath)) {
            $displayRoot + '\' + $childName + '\'
        } else {
            $displayRoot + '\' + $prefixPath + '\' + $childName + '\'
        }

        $quoted = ConvertTo-RuQuotedValue -Value $candidate -QuoteChar $quoteChar
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
        Get-RuCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition -Fallback $wordToComplete
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
        foreach ($switchItem in @(Get-RuSwitchCompletions -CurrentWord $currentWord -State $state)) {
            $results.Add($switchItem)
        }
    }

    if ($state.HiveMode) {
        if (-not $state.HiveFile) {
            foreach ($item in @(Get-RuFileCompletions -InputPath $currentWord)) {
                $results.Add($item)
            }
        } elseif ($state.Positionals.Count -eq 0) {
            foreach ($item in @(Get-RuHiveRelativePathCompletions -CurrentWord $currentWord)) {
                $results.Add($item)
            }
        }

        return @($results.ToArray())
    }

    if ($state.Positionals.Count -eq 0) {
        foreach ($item in @(Get-RuRegistryPathCompletions -CurrentValue $currentWord)) {
            $results.Add($item)
        }
    }

    # After the operand only the remaining switches are valid, so the switch list
    # built above is the whole answer here.
    @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName 'ru', 'ru.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Ru -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
