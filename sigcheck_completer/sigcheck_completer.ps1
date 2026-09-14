# sigcheck tab completion for PowerShell
# Native completer for Sigcheck with mode-aware switch/value and path completion.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name SigcheckCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:SigcheckCompletionCatalog = @{
        Switches = @(
            @{ Token = '-a'; Description = 'Show extended version information.'; TakesValue = $false }
            @{ Token = '-accepteula'; Description = 'Silently accept the Sigcheck EULA.'; TakesValue = $false }
            @{ Token = '-c'; Description = 'CSV output with comma delimiter.'; TakesValue = $false }
            @{ Token = '-ct'; Description = 'CSV output with tab delimiter.'; TakesValue = $false }
            @{ Token = '-d'; Description = 'Dump contents of a catalog file.'; TakesValue = $false }
            @{ Token = '-e'; Description = 'Scan executable images only.'; TakesValue = $false }
            @{ Token = '-f'; Description = 'Look for signatures in the specified catalog file.'; TakesValue = $true; ValueKind = 'CatalogFile' }
            @{ Token = '-h'; Description = 'Show file hashes.'; TakesValue = $false }
            @{ Token = '-i'; Description = 'Show catalog name and signing chain.'; TakesValue = $false }
            @{ Token = '-l'; Description = 'Traverse symbolic links and junctions.'; TakesValue = $false }
            @{ Token = '-m'; Description = 'Dump manifest.'; TakesValue = $false }
            @{ Token = '-n'; Description = 'Only show file version number.'; TakesValue = $false }
            @{ Token = '-o'; Description = 'Query VirusTotal using a previously captured CSV file.'; TakesValue = $false }
            @{ Token = '-p'; Description = 'Verify signatures against the specified policy GUID or policy file.'; TakesValue = $true; ValueKind = 'Policy' }
            @{ Token = '-q'; Description = 'Quiet - suppress per-file output detail.'; TakesValue = $false }
            @{ Token = '-r'; Description = 'Disable certificate revocation checking.'; TakesValue = $false }
            @{ Token = '-s'; Description = 'Recurse subdirectories.'; TakesValue = $false }
            @{ Token = '-t'; Description = 'Dump machine certificate stores.'; TakesValue = $false }
            @{ Token = '-tu'; Description = 'Dump user certificate stores.'; TakesValue = $false }
            @{ Token = '-tv'; Description = 'Dump machine certificate stores and validate against Microsoft roots.'; TakesValue = $false }
            @{ Token = '-tuv'; Description = 'Dump user certificate stores and validate against Microsoft roots.'; TakesValue = $false }
            @{ Token = '-u'; Description = 'Show unsigned or suspicious files.'; TakesValue = $false }
            @{ Token = '-v'; Description = 'Query VirusTotal by file hash.'; TakesValue = $false }
            @{ Token = '-vr'; Description = 'Query VirusTotal and open reports for positives.'; TakesValue = $false }
            @{ Token = '-vs'; Description = 'Query VirusTotal and submit unknown files.'; TakesValue = $false }
            @{ Token = '-vrs'; Description = 'Query VirusTotal, submit unknown files, and open positive reports.'; TakesValue = $false }
            @{ Token = '-vt'; Description = 'Accept VirusTotal terms non-interactively.'; TakesValue = $false }
            @{ Token = '-w'; Description = 'Write output to the specified file.'; TakesValue = $true; ValueKind = 'OutputFile' }
            @{ Token = '-nobanner'; Description = 'Do not display the startup banner.'; TakesValue = $false }
            @{ Token = '-?'; Description = 'Show Sigcheck help.'; TakesValue = $false }
            @{ Token = '/?'; Description = 'Show Sigcheck help.'; TakesValue = $false }
        )
        MachineStoreNames   = @()
        UserStoreNames      = @()
        StoreNamesUpdated   = $null
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
        [string]$Placeholder = '<path>',
        [string[]]$Extension = @(),
        [string[]]$Seed = @()
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

    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($seedPath in $Seed) {
        if ([string]::IsNullOrWhiteSpace($typedValue) -or $seedPath.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            $seedText = ConvertTo-SigcheckQuotedValue -Value $seedPath -AlwaysQuote $alwaysQuote
            if ($seenPaths.Add($seedText)) {
                [void]$results.Add((New-SigcheckCompletionResult -CompletionText $seedText -ListItemText $seedPath -ResultType 'ParameterValue' -ToolTip $ToolTip))
            }
        }
    }

    foreach ($item in $items) {
        if (-not [string]::IsNullOrWhiteSpace($leaf) -and
            -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        # Keep every directory so the tree stays navigable, but keep only the
        # file kinds the option actually accepts.
        if ($Extension.Count -gt 0 -and -not $item.PSIsContainer -and $item.Extension -notin $Extension) {
            continue
        }

        $candidate = if ($parentPath -eq '.') { $item.Name } else { Join-Path -Path $parentPath -ChildPath $item.Name }
        if ($item.PSIsContainer) {
            $candidate += '\'
        }

        $completionText = ConvertTo-SigcheckQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        if (-not $seenPaths.Add($completionText)) {
            continue
        }

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

function Get-SigcheckCatalogRoot {
    $root = Join-Path -Path $env:SystemRoot -ChildPath 'System32\CatRoot'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return @()
    }

    @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Ignore |
        Sort-Object -Property Name |
        ForEach-Object { $_.FullName + '\' })
}

function Update-SigcheckStoreNames {
    $lastUpdated = $script:SigcheckCompletionCatalog.StoreNamesUpdated
    if ($null -ne $lastUpdated -and
        ($script:SigcheckCompletionCatalog.MachineStoreNames.Count -gt 0 -or $script:SigcheckCompletionCatalog.UserStoreNames.Count -gt 0) -and
        ((Get-Date) - $lastUpdated).TotalSeconds -lt $script:SigcheckCompletionCatalog.StoreNamesTtl) {
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

        # Sysinternals tools accept /x for every -x switch; normalise so mode
        # detection and the used-token bookkeeping see one spelling.
        $lookup = $token.ToLowerInvariant()
        if ($lookup.Length -gt 1 -and $lookup.StartsWith('/')) {
            $lookup = '-' + $lookup.Substring(1)
        }

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
    # $CursorPosition indexes the whole input line; $line is command-relative.
    $relativeCursor = $CursorPosition - $CommandAst.Extent.StartOffset
    if ($relativeCursor -gt $line.Length) {
        $line = $line.PadRight($relativeCursor)
    }
    $relativeCursor = [Math]::Min([Math]::Max($relativeCursor, 0), $line.Length)
    $tokenState = Get-SigcheckTokenState -Line $line -CursorPosition $relativeCursor
    $argumentsState = Get-SigcheckArgumentsFromTokenState -TokenState $tokenState
    $state = Get-SigcheckCommandState -ArgumentsBeforeCurrent $argumentsState.ArgumentsBeforeCurrent
    $currentWord = $argumentsState.CurrentArgument

    switch ($state.ValueContext) {
        'CatalogFile' {
            return Get-SigcheckPathCompletions -CurrentWord $currentWord -ToolTip 'Catalog file path.' -Placeholder '<catalog-file>' -Extension @('.cat', '.cab') -Seed @(Get-SigcheckCatalogRoot)
        }
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
                $alwaysQuote = $currentWord.StartsWith('"')
                foreach ($storeName in @('*') + $storeNames + @('<store-name>')) {
                    if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
                        -not $storeName.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                        continue
                    }

                    # Store names such as 'AAD Token Issuer' contain spaces.
                    $storeText = if ($storeName -eq '*') { $storeName } else { ConvertTo-SigcheckQuotedValue -Value $storeName -AlwaysQuote $alwaysQuote }
                    [void]$results.Add((New-SigcheckCompletionResult -CompletionText $storeText -ListItemText $storeName -ResultType 'ParameterValue' -ToolTip 'Certificate store name or * for all stores.'))
                }
            }
            'offline' {
                foreach ($item in @(Get-SigcheckPathCompletions -CurrentWord $currentWord -ToolTip 'CSV file previously captured by Sigcheck -h.' -Placeholder '<sigcheck-csv-file>' -Extension @('.csv'))) {
                    [void]$results.Add($item)
                }
            }
            'catalog' {
                foreach ($item in @(Get-SigcheckPathCompletions -CurrentWord $currentWord -ToolTip 'Catalog file or directory to inspect.' -Placeholder '<catalog-file-or-directory>' -Extension @('.cat', '.cab'))) {
                    [void]$results.Add($item)
                }
            }
            default {
                foreach ($item in @(Get-SigcheckPathCompletions -CurrentWord $currentWord -ToolTip 'File or directory to inspect.' -Placeholder '<file-or-directory>')) {
                    [void]$results.Add($item)
                }
            }
        }
    }

    $wantsSwitches = [string]::IsNullOrEmpty($currentWord) -or $currentWord.StartsWith('-') -or $currentWord.StartsWith('/')
    if ($wantsSwitches) {
        # Sysinternals accepts /x for every -x switch, so a '/'-prefixed word
        # completes the whole catalog in its slash spelling.
        $useSlash = $currentWord.StartsWith('/')
        foreach ($switchSpec in $script:SigcheckCompletionCatalog.Switches) {
            $canonical = $switchSpec.Token.ToLowerInvariant()
            if ($canonical.StartsWith('/')) { $canonical = '-' + $canonical.Substring(1) }

            $token = $switchSpec.Token
            if ($useSlash) {
                $token = '/' + $token.Substring(1)
            } elseif ($token.StartsWith('/')) {
                continue
            }

            if (-not $token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            if ($state.UsedTokens.ContainsKey($canonical) -and
                $canonical -notin @('-v', '-vr', '-vs', '-vrs', '-t', '-tu', '-tv', '-tuv', '-?')) {
                continue
            }

            if (($canonical -in @('-c', '-ct')) -and
                ($state.UsedTokens.ContainsKey('-c') -or $state.UsedTokens.ContainsKey('-ct')) -and
                -not $state.UsedTokens.ContainsKey($canonical)) {
                continue
            }

            [void]$results.Add((New-SigcheckCompletionResult -CompletionText $token -ListItemText $token -ResultType 'ParameterName' -ToolTip $switchSpec.Description))
        }
    }

    Get-SigcheckUniqueCompletions -Results @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('sigcheck', 'sigcheck.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Sigcheck -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
