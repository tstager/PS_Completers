# sigcheck tab completion for PowerShell
# Native completer for Sigcheck with mode-aware switch/value and path completion.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name SigcheckCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SigcheckCompletionCatalog = @{
        Switches = @(
            [pscustomobject]@{ Token = '-a'; Description = 'Show extended version information.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-accepteula'; Description = 'Silently accept the Sigcheck EULA.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-c'; Description = 'CSV output with comma delimiter.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-ct'; Description = 'CSV output with tab delimiter.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-d'; Description = 'Dump contents of a catalog file.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-e'; Description = 'Scan executable images only.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-f'; Description = 'Look for signatures in the specified catalog file.'; TakesValue = $true; ValueKind = 'CatalogFile' }
            [pscustomobject]@{ Token = '-h'; Description = 'Show file hashes.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-i'; Description = 'Show catalog name and signing chain.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-l'; Description = 'Traverse symbolic links and junctions.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-m'; Description = 'Dump manifest.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-n'; Description = 'Only show file version number.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-o'; Description = 'Query VirusTotal using a previously captured CSV file.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-p'; Description = 'Verify signatures against the specified policy GUID or policy file.'; TakesValue = $true; ValueKind = 'Policy' }
            [pscustomobject]@{ Token = '-r'; Description = 'Disable certificate revocation checking.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-s'; Description = 'Recurse subdirectories.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-t'; Description = 'Dump machine certificate stores.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-tu'; Description = 'Dump user certificate stores.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-tv'; Description = 'Dump machine certificate stores and validate against Microsoft roots.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-tuv'; Description = 'Dump user certificate stores and validate against Microsoft roots.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-u'; Description = 'Show unsigned or suspicious files.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-v'; Description = 'Query VirusTotal by file hash.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-vr'; Description = 'Query VirusTotal and open reports for positives.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-vs'; Description = 'Query VirusTotal and submit unknown files.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-vrs'; Description = 'Query VirusTotal, submit unknown files, and open positive reports.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-vt'; Description = 'Accept VirusTotal terms non-interactively.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-w'; Description = 'Write output to the specified file.'; TakesValue = $true; ValueKind = 'OutputFile' }
            [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-?'; Description = 'Show Sigcheck help.'; TakesValue = $false }
            [pscustomobject]@{ Token = '/?'; Description = 'Show Sigcheck help.'; TakesValue = $false }
        )
        MachineStoreNames   = @()
        UserStoreNames      = @()
        StoreNamesUpdated   = [datetime]::MinValue
        StoreNamesTtl       = 60
    }
}

function New-SigcheckCompletionResult {
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

function Remove-SigcheckOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function ConvertTo-SigcheckQuotedValue {
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

function Get-SigcheckTokenState {
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

function Get-SigcheckArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    [pscustomobject]@{
        ArgumentsBeforeCurrent = @($TokenState.TokensBeforeCurrent | Select-Object -Skip 1)
        CurrentArgument        = $TokenState.CurrentToken
    }
}

function Get-SigcheckUniqueCompletions {
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

function Get-SigcheckPathCompletions {
    param(
        [string]$CurrentWord,
        [string]$ToolTip,
        [string]$Placeholder = '<path>'
    )

    $typedValue = Remove-SigcheckOuterQuotes -Value $CurrentWord
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

        $completionText = ConvertTo-SigcheckQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        [void]$results.Add((New-SigcheckCompletionResult -CompletionText $completionText -ListItemText $completionText -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
            [void]$results.Add((New-SigcheckCompletionResult -CompletionText $Placeholder -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip))
        } else {
            [void]$results.Add((New-SigcheckCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip $ToolTip))
        }
    }

    @($results.ToArray())
}

function Update-SigcheckStoreNames {
    $age = (Get-Date) - $script:SigcheckCompletionCatalog.StoreNamesUpdated
    if (($script:SigcheckCompletionCatalog.MachineStoreNames.Count -gt 0 -or $script:SigcheckCompletionCatalog.UserStoreNames.Count -gt 0) -and
        $age.TotalSeconds -lt $script:SigcheckCompletionCatalog.StoreNamesTtl) {
        return
    }

    try {
        $script:SigcheckCompletionCatalog.MachineStoreNames = @(
            Get-ChildItem -Path Cert:\LocalMachine -ErrorAction Stop |
                Select-Object -ExpandProperty PSChildName |
                Sort-Object -Unique
        )
    } catch {
        $script:SigcheckCompletionCatalog.MachineStoreNames = @('Root', 'CA', 'My', 'TrustedPublisher')
    }

    try {
        $script:SigcheckCompletionCatalog.UserStoreNames = @(
            Get-ChildItem -Path Cert:\CurrentUser -ErrorAction Stop |
                Select-Object -ExpandProperty PSChildName |
                Sort-Object -Unique
        )
    } catch {
        $script:SigcheckCompletionCatalog.UserStoreNames = @('Root', 'CA', 'My', 'TrustedPublisher')
    }

    $script:SigcheckCompletionCatalog.StoreNamesUpdated = Get-Date
}

function Get-SigcheckCommandState {
    param([string[]]$ArgumentsBeforeCurrent)

    $usedTokens = @{}
    $valueContext = $null
    $mode = 'scan'
    $storeMode = $null
    $positionals = New-Object System.Collections.Generic.List[string]

    for ($index = 0; $index -lt $ArgumentsBeforeCurrent.Count; $index++) {
        $token = $ArgumentsBeforeCurrent[$index]
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        $lookup = $token.ToLowerInvariant()
        $usedTokens[$lookup] = $true

        switch ($lookup) {
            '-d' {
                $mode = 'catalog'
                continue
            }
            '-o' {
                $mode = 'offline'
                continue
            }
            '-t' {
                $mode = 'store'
                $storeMode = 'machine'
                continue
            }
            '-tu' {
                $mode = 'store'
                $storeMode = 'user'
                continue
            }
            '-tv' {
                $mode = 'store'
                $storeMode = 'machine'
                continue
            }
            '-tuv' {
                $mode = 'store'
                $storeMode = 'user'
                continue
            }
            '-f' {
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = 'CatalogFile'
                    break
                }

                $index++
                continue
            }
            '-p' {
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = 'Policy'
                    break
                }

                $index++
                continue
            }
            '-w' {
                if ($index -eq ($ArgumentsBeforeCurrent.Count - 1)) {
                    $valueContext = 'OutputFile'
                    break
                }

                $index++
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
        UsedTokens   = $usedTokens
        ValueContext = $valueContext
        Mode         = $mode
        StoreMode    = $storeMode
        Positionals  = @($positionals.ToArray())
    }
}

function Complete-Sigcheck {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $line = if ($CommandAst.Extent -and $null -ne $CommandAst.Extent.Text) { $CommandAst.Extent.Text } else { $CommandAst.ToString() }
    if ($cursorPosition -gt $line.Length) {
        $line = $line.PadRight($cursorPosition)
    }
    $tokenState = Get-SigcheckTokenState -Line $line -CursorPosition $CursorPosition
    $argumentsState = Get-SigcheckArgumentsFromTokenState -TokenState $tokenState
    $state = Get-SigcheckCommandState -ArgumentsBeforeCurrent $argumentsState.ArgumentsBeforeCurrent
    $currentWord = $argumentsState.CurrentArgument

    switch ($state.ValueContext) {
        'CatalogFile' { return Get-SigcheckPathCompletions -CurrentWord $currentWord -ToolTip 'Catalog file path.' -Placeholder '<catalog-file>' }
        'OutputFile' { return Get-SigcheckPathCompletions -CurrentWord $currentWord -ToolTip 'Output file path.' -Placeholder '<output-file>' }
        'Policy' {
            $typedValue = Remove-SigcheckOuterQuotes -Value $currentWord
            $results = New-Object System.Collections.Generic.List[object]
            foreach ($sample in @('{00000000-0000-0000-0000-000000000000}', '<policy-guid-or-path>')) {
                if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
                    -not $sample.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                [void]$results.Add((New-SigcheckCompletionResult -CompletionText $sample -ListItemText $sample -ResultType 'ParameterValue' -ToolTip 'Policy GUID or policy file path.'))
            }

            $pathResults = Get-SigcheckPathCompletions -CurrentWord $currentWord -ToolTip 'Policy file path.' -Placeholder '<policy-file>'
            foreach ($item in $pathResults) {
                [void]$results.Add($item)
            }

            return Get-SigcheckUniqueCompletions -Results @($results.ToArray())
        }
    }

    $results = New-Object System.Collections.Generic.List[object]

    if (-not $currentWord.StartsWith('-') -and -not $currentWord.StartsWith('/')) {
        switch ($state.Mode) {
            'store' {
                Update-SigcheckStoreNames
                $typedValue = Remove-SigcheckOuterQuotes -Value $currentWord
                $storeNames = if ($state.StoreMode -eq 'user') { $script:SigcheckCompletionCatalog.UserStoreNames } else { $script:SigcheckCompletionCatalog.MachineStoreNames }
                foreach ($storeName in @('*') + $storeNames + @('<store-name>')) {
                    if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
                        -not $storeName.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                        continue
                    }

                    [void]$results.Add((New-SigcheckCompletionResult -CompletionText $storeName -ListItemText $storeName -ResultType 'ParameterValue' -ToolTip 'Certificate store name or * for all stores.'))
                }
            }
            'offline' {
                $results.AddRange((Get-SigcheckPathCompletions -CurrentWord $currentWord -ToolTip 'CSV file previously captured by Sigcheck -h.' -Placeholder '<sigcheck-csv-file>'))
            }
            'catalog' {
                $results.AddRange((Get-SigcheckPathCompletions -CurrentWord $currentWord -ToolTip 'Catalog file or directory to inspect.' -Placeholder '<catalog-file-or-directory>'))
            }
            default {
                $results.AddRange((Get-SigcheckPathCompletions -CurrentWord $currentWord -ToolTip 'File or directory to inspect.' -Placeholder '<file-or-directory>'))
            }
        }
    }

    $wantsSwitches = [string]::IsNullOrEmpty($currentWord) -or $currentWord.StartsWith('-') -or $currentWord.StartsWith('/')
    if ($wantsSwitches) {
        foreach ($switchSpec in $script:SigcheckCompletionCatalog.Switches) {
            if (-not $switchSpec.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            if ($state.UsedTokens.ContainsKey($switchSpec.Token.ToLowerInvariant()) -and
                $switchSpec.Token -notin @('-v', '-vr', '-vs', '-vrs', '-t', '-tu', '-tv', '-tuv', '-?', '/?')) {
                continue
            }

            if (($switchSpec.Token -in @('-c', '-ct')) -and
                ($state.UsedTokens.ContainsKey('-c') -or $state.UsedTokens.ContainsKey('-ct')) -and
                -not $state.UsedTokens.ContainsKey($switchSpec.Token.ToLowerInvariant())) {
                continue
            }

            [void]$results.Add((New-SigcheckCompletionResult -CompletionText $switchSpec.Token -ListItemText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description))
        }
    }

    Get-SigcheckUniqueCompletions -Results @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('sigcheck', 'sigcheck.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Sigcheck -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
