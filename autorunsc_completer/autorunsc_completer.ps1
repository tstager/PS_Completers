# autorunsc tab completion for PowerShell
# Native completer for Autorunsc with safe switch/value completion and local profile hints.

Set-StrictMode -Version 2.0

function Initialize-AutorunscCompletionCatalog {
    if (Get-Variable -Name AutorunscCompletionCatalog -Scope Script -ErrorAction Ignore) {
        return
    }

    $script:AutorunscCompletionCatalog = @{
        Switches = @(
            [pscustomobject]@{ Token = '-a'; Description = 'Autostart entry selection filter.'; TakesValue = $true; ValueKind = 'Selection' }
            [pscustomobject]@{ Token = '-c'; Description = 'Print output as CSV.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-ct'; Description = 'Print output as tab-delimited values.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-h'; Description = 'Show file hashes.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-m'; Description = 'Hide Microsoft entries.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-o'; Description = 'Write output to the specified file.'; TakesValue = $true; ValueKind = 'OutputPath' }
            [pscustomobject]@{ Token = '-s'; Description = 'Verify digital signatures.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-t'; Description = 'Show timestamps in normalized UTC.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-u'; Description = 'Show unsigned or suspicious entries.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-x'; Description = 'Print output as XML.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-v'; Description = 'Query VirusTotal by file hash.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-vr'; Description = 'Query VirusTotal and open reports for positives.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-vs'; Description = 'Query VirusTotal and submit unknown files.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-vrs'; Description = 'Query VirusTotal, submit unknown files, and open positive reports.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-vt'; Description = 'Accept VirusTotal terms non-interactively.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-z'; Description = 'Scan an offline Windows system root and user profile.'; TakesValue = $true; ValueKind = 'OfflineRoot' }
            [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-accepteula'; Description = 'Accept the Sysinternals licence agreement non-interactively.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-?'; Description = 'Show Autorunsc help.'; TakesValue = $false }
            [pscustomobject]@{ Token = '/?'; Description = 'Show Autorunsc help.'; TakesValue = $false }
        )
        SelectionValues = @(
            [pscustomobject]@{ Token = '*'; Description = 'All autostart categories.' }
            [pscustomobject]@{ Token = 'b'; Description = 'Boot execute.' }
            [pscustomobject]@{ Token = 'c'; Description = 'Codecs.' }
            [pscustomobject]@{ Token = 'd'; Description = 'Appinit DLLs.' }
            [pscustomobject]@{ Token = 'e'; Description = 'Explorer addons.' }
            [pscustomobject]@{ Token = 'g'; Description = 'Sidebar gadgets.' }
            [pscustomobject]@{ Token = 'h'; Description = 'Image hijacks.' }
            [pscustomobject]@{ Token = 'i'; Description = 'Internet Explorer addons.' }
            [pscustomobject]@{ Token = 'k'; Description = 'Known DLLs.' }
            [pscustomobject]@{ Token = 'l'; Description = 'Logon startups.' }
            [pscustomobject]@{ Token = 'm'; Description = 'WMI entries.' }
            [pscustomobject]@{ Token = 'n'; Description = 'Winsock providers.' }
            [pscustomobject]@{ Token = 'o'; Description = 'Office add-ins.' }
            [pscustomobject]@{ Token = 'p'; Description = 'Printer monitor DLLs.' }
            [pscustomobject]@{ Token = 'r'; Description = 'LSA security providers.' }
            [pscustomobject]@{ Token = 's'; Description = 'Services and non-disabled drivers.' }
            [pscustomobject]@{ Token = 't'; Description = 'Scheduled tasks.' }
            [pscustomobject]@{ Token = 'w'; Description = 'Winlogon entries.' }
            [pscustomobject]@{ Token = 'x'; Description = 'Packaged (Store) app startups.' }
        )
        UserProfiles        = @()
        UserProfilesUpdated = [datetime]::MinValue
        UserProfilesTtl     = 60
    }
}

function New-AutorunscCompletionResult {
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

function Remove-AutorunscOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function ConvertFrom-AutorunscTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    # Returns $null when text follows the closing quote: that word is not one plain value.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    if ($tokens[0].Extent.EndOffset -lt $Value.Length) {
        return $null
    }

    $tokens[0].Value
}

function ConvertTo-AutorunscQuotedValue {
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
        # A leading dash (ASCII or U+2013-U+2015) would make PowerShell read the word as a parameter.
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

function Get-AutorunscTokenState {
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
    $quoteChar = ''

    foreach ($character in $prefix.ToCharArray()) {
        # PowerShell reads U+2018-U+201B as single quotes and U+201C-U+201E as double quotes.
        $quoteClass = if ([string]$character -match '[''\u2018-\u201B]') { "'" } elseif ([string]$character -match '["\u201C-\u201E]') { '"' } else { '' }
        if ($quoteClass) {
            if (-not $quoteChar) {
                $quoteChar = $quoteClass
            } elseif ($quoteChar -eq $quoteClass) {
                $quoteChar = ''
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and -not $quoteChar) {
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

function Get-AutorunscArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    [pscustomobject]@{
        ArgumentsBeforeCurrent = @($TokenState.TokensBeforeCurrent | Select-Object -Skip 1)
        CurrentArgument        = $TokenState.CurrentToken
    }
}

function Get-AutorunscUniqueCompletions {
    param([object[]]$Results)

    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[object]
    foreach ($result in $Results) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.ContainsKey($result.CompletionText)) {
            continue
        }

        $seen[$result.CompletionText] = $true
        [void]$unique.Add($result)
    }

    @($unique.ToArray())
}

function Get-AutorunscPathCompletions {
    param(
        [string]$CurrentWord,
        [string]$ToolTip,
        [string]$Placeholder = '<path>',
        [switch]$DirectoriesOnly
    )

    $typedValue = ConvertFrom-AutorunscTypedWord -Value $CurrentWord
    $quoteChar = if ($CurrentWord -match '^[''"\u2018-\u201E]') { $CurrentWord.Substring(0, 1) } else { '' }
    $results = New-Object System.Collections.Generic.List[object]
    if ($null -eq $typedValue) {
        # Text follows the closing quote; PowerShell's own file completion handles that word.
        return @()
    }

    # The -z operands name an offline image, not something under the working
    # directory, so start them at the volume roots instead of the cwd listing.
    if ($DirectoriesOnly -and [string]::IsNullOrWhiteSpace($typedValue)) {
        try {
            foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
                if (-not $drive.IsReady) {
                    continue
                }

                [void]$results.Add((New-AutorunscCompletionResult -CompletionText (ConvertTo-AutorunscQuotedValue -Value $drive.Name -QuoteChar $quoteChar) -ListItemText $drive.Name -ResultType 'ParameterValue' -ToolTip $ToolTip))
            }
        } catch {
            [void]$results.Clear()
        }

        if ($results.Count -gt 0) {
            return @($results.ToArray())
        }

        [void]$results.Add((New-AutorunscCompletionResult -CompletionText $Placeholder -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip))
        return @($results.ToArray())
    }

    # Candidates keep the directory part exactly as typed (a typed .\ or ./ included).
    $parentPath = '.'
    $directoryText = ''
    $leaf = $typedValue
    $separatorIndex = $typedValue.LastIndexOfAny([char[]]@('\', '/', ':'))
    if ($separatorIndex -ge 0) {
        $directoryText = $typedValue.Substring(0, $separatorIndex + 1)
        $parentPath = $directoryText
        $leaf = $typedValue.Substring($separatorIndex + 1)
    }

    $items = if (-not (Test-Path -LiteralPath $parentPath -PathType Container -ErrorAction Ignore)) {
        @()
    } elseif ($DirectoriesOnly) {
        @(Get-ChildItem -LiteralPath $parentPath -Directory -Force -ErrorAction Ignore)
    } else {
        @(Get-ChildItem -LiteralPath $parentPath -ErrorAction Ignore)
    }

    foreach ($item in $items) {
        if (-not [string]::IsNullOrWhiteSpace($leaf) -and
            -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidate = $directoryText + $item.Name
        if (-not $directoryText -and $candidate -match '^[-\u2013-\u2015]') {
            # Like PowerShell's own file completion: .\-name instead of a word read as a parameter.
            $candidate = '.' + [System.IO.Path]::DirectorySeparatorChar + $candidate
        }

        if ($item.PSIsContainer) {
            $candidate += '\'
        }

        $completionText = ConvertTo-AutorunscQuotedValue -Value $candidate -QuoteChar $quoteChar
        [void]$results.Add((New-AutorunscCompletionResult -CompletionText $completionText -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
            [void]$results.Add((New-AutorunscCompletionResult -CompletionText $Placeholder -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip))
        } else {
            [void]$results.Add((New-AutorunscCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip $ToolTip))
        }
    }

    @($results.ToArray())
}

function Update-AutorunscUserProfiles {
    $age = (Get-Date) - $script:AutorunscCompletionCatalog.UserProfilesUpdated
    if ($script:AutorunscCompletionCatalog.UserProfiles.Count -gt 0 -and $age.TotalSeconds -lt $script:AutorunscCompletionCatalog.UserProfilesTtl) {
        return
    }

    try {
        $usersRoot = Join-Path -Path $env:SystemDrive -ChildPath 'Users'
        $script:AutorunscCompletionCatalog.UserProfiles = @(
            Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction Stop |
                Select-Object -ExpandProperty Name |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        $script:AutorunscCompletionCatalog.UserProfilesUpdated = Get-Date
    } catch {
        $script:AutorunscCompletionCatalog.UserProfiles = @()
    }
}

function Get-AutorunscCommandState {
    param([string[]]$ArgumentsBeforeCurrent)

    $usedTokens = @{}
    $valueContext = $null
    $offlinePaths = 0
    $offlineMode = $false
    $positionals = New-Object System.Collections.Generic.List[string]

    for ($index = 0; $index -lt $ArgumentsBeforeCurrent.Count; $index++) {
        $token = $ArgumentsBeforeCurrent[$index]
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        $lookup = $token.ToLowerInvariant()
        $usedTokens[$lookup] = $true

        switch ($lookup) {
            '-a' {
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = 'Selection'
                    break
                }

                $index++
                continue
            }
            '-o' {
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = 'OutputPath'
                    break
                }

                $index++
                continue
            }
            '-z' {
                $offlineMode = $true
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = 'OfflineRoot'
                    break
                }

                $index++
                $offlinePaths++
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = 'OfflineUserProfile'
                    break
                }

                $index++
                $offlinePaths++
                continue
            }
            default {
                if ($lookup.StartsWith('-') -or $lookup.StartsWith('/')) {
                    continue
                }

                $positionals.Add($token)
            }
        }
    }

    [pscustomobject]@{
        UsedTokens    = $usedTokens
        ValueContext  = $valueContext
        OfflineMode   = $offlineMode
        OfflinePaths  = $offlinePaths
        Positionals   = @($positionals.ToArray())
    }
}

function Complete-Autorunsc {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    Initialize-AutorunscCompletionCatalog

    $line = if ($CommandAst.Extent -and $null -ne $CommandAst.Extent.Text) { $CommandAst.Extent.Text } else { $CommandAst.ToString() }
    $relativeCursor = $CursorPosition - $CommandAst.Extent.StartOffset
    if ($relativeCursor -gt $line.Length) {
        $line = $line.PadRight($relativeCursor)
    }
    $tokenState = Get-AutorunscTokenState -Line $line -CursorPosition $relativeCursor
    $argumentsState = Get-AutorunscArgumentsFromTokenState -TokenState $tokenState
    $state = Get-AutorunscCommandState -ArgumentsBeforeCurrent $argumentsState.ArgumentsBeforeCurrent
    $currentWord = $argumentsState.CurrentArgument
    $results = New-Object System.Collections.Generic.List[object]

    switch ($state.ValueContext) {
        'Selection' {
            # Help's usage line is '-a <*|bcdeghi klmnoprstw>': category letters may be
            # concatenated, so a typed run of letters is a prefix to extend, not a token
            # to match. Offer the run itself first, then every letter not yet in it.
            $typedValue = Remove-AutorunscOuterQuotes -Value $currentWord
            if ($typedValue -match '^[A-Za-z]+$') {
                $letterSpecs = @($script:AutorunscCompletionCatalog.SelectionValues | Where-Object { $_.Token -ne '*' })
                $known = @{}
                foreach ($selection in $letterSpecs) {
                    $known[$selection.Token.ToLowerInvariant()] = $selection.Description
                }

                $typedLetters = @($typedValue.ToCharArray() | ForEach-Object { ([string]$_).ToLowerInvariant() })
                $unknown = @($typedLetters | Where-Object { -not $known.ContainsKey($_) })
                if ($unknown.Count -gt 0) {
                    return @()
                }

                $describedRun = (@($typedLetters | ForEach-Object { $known[$_] }) -join ' ')
                [void]$results.Add((New-AutorunscCompletionResult -CompletionText $typedValue -ListItemText $typedValue -ResultType 'ParameterValue' -ToolTip $describedRun))

                foreach ($selection in $letterSpecs) {
                    if ($selection.Token.ToLowerInvariant() -in $typedLetters) {
                        continue
                    }

                    $clustered = $typedValue + $selection.Token
                    [void]$results.Add((New-AutorunscCompletionResult -CompletionText $clustered -ListItemText $clustered -ResultType 'ParameterValue' -ToolTip ('Add ' + $selection.Description)))
                }

                return Get-AutorunscUniqueCompletions -Results @($results.ToArray())
            }

            foreach ($selection in $script:AutorunscCompletionCatalog.SelectionValues) {
                if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
                    -not $selection.Token.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                [void]$results.Add((New-AutorunscCompletionResult -CompletionText $selection.Token -ListItemText $selection.Token -ResultType 'ParameterValue' -ToolTip $selection.Description))
            }

            return Get-AutorunscUniqueCompletions -Results @($results.ToArray())
        }
        'OutputPath' {
            return Get-AutorunscPathCompletions -CurrentWord $currentWord -ToolTip 'Output file path.' -Placeholder '<output-file>'
        }
        'OfflineRoot' {
            return Get-AutorunscPathCompletions -CurrentWord $currentWord -ToolTip 'Offline Windows system root path.' -Placeholder '<offline-systemroot>' -DirectoriesOnly
        }
        'OfflineUserProfile' {
            return Get-AutorunscPathCompletions -CurrentWord $currentWord -ToolTip 'Offline user profile path.' -Placeholder '<offline-userprofile>' -DirectoriesOnly
        }
    }

    $wantsSwitches = [string]::IsNullOrEmpty($currentWord) -or $currentWord.StartsWith('-') -or $currentWord.StartsWith('/')
    if ($wantsSwitches) {
        foreach ($switchSpec in $script:AutorunscCompletionCatalog.Switches) {
            if (-not $switchSpec.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            if ($state.UsedTokens.ContainsKey($switchSpec.Token.ToLowerInvariant()) -and
                $switchSpec.Token -notin @('-v', '-vr', '-vs', '-vrs', '-?', '/?')) {
                continue
            }

            if (($switchSpec.Token -in @('-c', '-ct')) -and
                ($state.UsedTokens.ContainsKey('-c') -or $state.UsedTokens.ContainsKey('-ct')) -and
                -not $state.UsedTokens.ContainsKey($switchSpec.Token.ToLowerInvariant())) {
                continue
            }

            [void]$results.Add((New-AutorunscCompletionResult -CompletionText $switchSpec.Token -ListItemText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description))
        }
    }

    if (-not $currentWord.StartsWith('-') -and -not $currentWord.StartsWith('/')) {
        if ($state.OfflineMode) {
            if ($state.OfflinePaths -eq 0) {
                $results.AddRange((Get-AutorunscPathCompletions -CurrentWord $currentWord -ToolTip 'Offline Windows system root path.' -Placeholder '<offline-systemroot>' -DirectoriesOnly))
            } elseif ($state.OfflinePaths -eq 1) {
                $results.AddRange((Get-AutorunscPathCompletions -CurrentWord $currentWord -ToolTip 'Offline user profile path.' -Placeholder '<offline-userprofile>' -DirectoriesOnly))
            } else {
                $terminalText = if ([string]::IsNullOrWhiteSpace($currentWord)) { '<no-more-arguments>' } else { $currentWord }
                $results.Add((New-AutorunscCompletionResult -CompletionText $terminalText -ListItemText $terminalText -ResultType 'ParameterValue' -ToolTip 'Autorunsc accepts no further positional arguments after -z <systemroot> <userprofile>.'))
            }
        } else {
            Update-AutorunscUserProfiles
            $typedValue = ConvertFrom-AutorunscTypedWord -Value $currentWord
            $quoteChar = if ($currentWord -match '^[''"\u2018-\u201E]') { $currentWord.Substring(0, 1) } else { '' }
            foreach ($userName in @('*', $env:USERNAME) + $script:AutorunscCompletionCatalog.UserProfiles + @('<user>')) {
                if ($null -eq $typedValue) {
                    break
                }

                if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
                    -not $userName.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                # Profile folder names may hold spaces or other PowerShell metacharacters.
                $userText = if ($userName -eq '<user>') { $userName } else { ConvertTo-AutorunscQuotedValue -Value $userName -QuoteChar $quoteChar }
                [void]$results.Add((New-AutorunscCompletionResult -CompletionText $userText -ListItemText $userName -ResultType 'ParameterValue' -ToolTip 'User account name or * for all profiles.'))
            }
        }
    }

    Get-AutorunscUniqueCompletions -Results @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('autorunsc', 'autorunsc.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Autorunsc -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
