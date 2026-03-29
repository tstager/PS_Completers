# autorunsc tab completion for PowerShell
# Native completer for Autorunsc with safe switch/value completion and local profile hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name AutorunscCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
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

function ConvertTo-AutorunscQuotedValue {
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
        [string]$Placeholder = '<path>'
    )

    $typedValue = Remove-AutorunscOuterQuotes -Value $CurrentWord
    $alwaysQuote = $CurrentWord.StartsWith('"')
    $results = New-Object System.Collections.Generic.List[object]

    $parentPath = '.'
    $leaf = ''
    if (-not [string]::IsNullOrWhiteSpace($typedValue)) {
        if ($typedValue.EndsWith('\') -or $typedValue.EndsWith('/')) {
            $parentPath = $typedValue
        } else {
            $candidateParent = Split-Path -Path $typedValue -Parent
            if ([string]::IsNullOrWhiteSpace($candidateParent)) {
                $leaf = $typedValue
            } else {
                $parentPath = $candidateParent
                $leaf = Split-Path -Path $typedValue -Leaf
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
        if ($item.PSIsContainer) {
            $candidate += '\'
        }

        $completionText = ConvertTo-AutorunscQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        [void]$results.Add((New-AutorunscCompletionResult -CompletionText $completionText -ListItemText $completionText -ResultType 'ParameterValue' -ToolTip $ToolTip))
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

    $line = if ($CommandAst.Extent -and $null -ne $CommandAst.Extent.Text) { $CommandAst.Extent.Text } else { $CommandAst.ToString() }
    if ($cursorPosition -gt $line.Length) {
        $line = $line.PadRight($cursorPosition)
    }
    $tokenState = Get-AutorunscTokenState -Line $line -CursorPosition $CursorPosition
    $argumentsState = Get-AutorunscArgumentsFromTokenState -TokenState $tokenState
    $state = Get-AutorunscCommandState -ArgumentsBeforeCurrent $argumentsState.ArgumentsBeforeCurrent
    $currentWord = $argumentsState.CurrentArgument
    $results = New-Object System.Collections.Generic.List[object]

    switch ($state.ValueContext) {
        'Selection' {
            $typedValue = Remove-AutorunscOuterQuotes -Value $currentWord
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
            return Get-AutorunscPathCompletions -CurrentWord $currentWord -ToolTip 'Offline Windows system root path.' -Placeholder '<offline-systemroot>'
        }
        'OfflineUserProfile' {
            return Get-AutorunscPathCompletions -CurrentWord $currentWord -ToolTip 'Offline user profile path.' -Placeholder '<offline-userprofile>'
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
                $results.AddRange((Get-AutorunscPathCompletions -CurrentWord $currentWord -ToolTip 'Offline Windows system root path.' -Placeholder '<offline-systemroot>'))
            } elseif ($state.OfflinePaths -eq 1) {
                $results.AddRange((Get-AutorunscPathCompletions -CurrentWord $currentWord -ToolTip 'Offline user profile path.' -Placeholder '<offline-userprofile>'))
            } else {
                $results.Add((New-AutorunscCompletionResult -CompletionText $currentWord -ListItemText $currentWord -ResultType 'ParameterValue' -ToolTip 'Autorunsc accepts no further positional arguments after -z <systemroot> <userprofile>.'))
            }
        } else {
            Update-AutorunscUserProfiles
            $typedValue = Remove-AutorunscOuterQuotes -Value $currentWord
            foreach ($userName in @('*', $env:USERNAME) + $script:AutorunscCompletionCatalog.UserProfiles + @('<user>')) {
                if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
                    -not $userName.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                [void]$results.Add((New-AutorunscCompletionResult -CompletionText $userName -ListItemText $userName -ResultType 'ParameterValue' -ToolTip 'User account name or * for all profiles.'))
            }
        }
    }

    Get-AutorunscUniqueCompletions -Results @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('autorunsc', 'autorunsc.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Autorunsc -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
