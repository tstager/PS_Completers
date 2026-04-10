# whoami tab completion for PowerShell
# Static-first native completer for whoami with runtime-shaped mode tracking.

Set-StrictMode -Version 2.0

function Get-WhoamiCompletionCatalog {
    if (-not (Get-Variable -Name WhoamiCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
        $script:WhoamiCompletionCatalog = @{
            Initialized      = $false
            SwitchOrder      = @('/UPN', '/FQDN', '/LOGONID', '/USER', '/GROUPS', '/CLAIMS', '/PRIV', '/ALL', '/FO', '/NH', '/?')
            SwitchInfo       = @{}
            FormatValues     = @('TABLE', 'LIST', 'CSV')
            IdentitySwitches = @('/UPN', '/FQDN', '/LOGONID')
            DetailSwitches   = @('/USER', '/GROUPS', '/CLAIMS', '/PRIV')
        }
    }

    $script:WhoamiCompletionCatalog
}

function New-WhoamiCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $CompletionText,
        $ResultType,
        $ToolTip
    )
}

function Get-WhoamiStaticSwitchCatalog {
    [ordered]@{
        '/UPN' = 'Displays the user name in User Principal Name (UPN) format.'
        '/FQDN' = 'Displays the user name in Fully Qualified Distinguished Name (FQDN) format.'
        '/LOGONID' = 'Displays the logon ID of the current user.'
        '/USER' = 'Displays the current user and SID.'
        '/GROUPS' = 'Displays group membership, attributes, and SIDs.'
        '/CLAIMS' = 'Displays current user claims.'
        '/PRIV' = 'Displays the current user''s security privileges.'
        '/ALL' = 'Displays user, group, claim, privilege, and SID information.'
        '/FO' = 'Specifies the output format. Valid values: TABLE, LIST, CSV.'
        '/NH' = 'Suppresses the column header. Valid only for TABLE and CSV output.'
        '/?' = 'Displays whoami help.'
    }
}

function Initialize-WhoamiCompletionCatalog {
    $catalog = Get-WhoamiCompletionCatalog
    if ($catalog.Initialized) {
        return
    }

    $catalog.SwitchInfo = @{}
    foreach ($entry in (Get-WhoamiStaticSwitchCatalog).GetEnumerator()) {
        $catalog.SwitchInfo[$entry.Key] = $entry.Value
    }

    $catalog.Initialized = $true
}

function Get-WhoamiCurrentToken {
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Remove-WhoamiOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function Get-WhoamiCommandState {
    param([string[]]$TokensBeforeCurrent)

    $catalog = Get-WhoamiCompletionCatalog
    $usedSwitchLookup = @{}
    $detailSwitchesUsed = New-Object System.Collections.Generic.List[string]
    $identityModeSwitch = $null
    $formatValue = $null
    $valueContext = $null

    for ($i = 0; $i -lt $TokensBeforeCurrent.Count; $i++) {
        $cleanToken = Remove-WhoamiOuterQuotes -Value $TokensBeforeCurrent[$i]
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        $switchKey = $cleanToken.ToUpperInvariant()
        if (-not $switchKey.StartsWith('/')) {
            continue
        }

        if ($switchKey -eq '/FO') {
            $usedSwitchLookup['/FO'] = $true
            if ($i + 1 -lt $TokensBeforeCurrent.Count) {
                $nextToken = Remove-WhoamiOuterQuotes -Value $TokensBeforeCurrent[$i + 1]
                if (-not [string]::IsNullOrWhiteSpace($nextToken) -and -not $nextToken.StartsWith('/')) {
                    $formatValue = $nextToken
                    $i++
                    continue
                }
            }
            continue
        }

        $usedSwitchLookup[$switchKey] = $true

        if (-not $identityModeSwitch -and $catalog.IdentitySwitches -contains $switchKey) {
            $identityModeSwitch = $switchKey
        }

        if ($catalog.DetailSwitches -contains $switchKey) {
            $detailSwitchesUsed.Add($switchKey)
        }
    }

    $hasAllMode = $usedSwitchLookup.ContainsKey('/ALL')
    $hasDetailMode = $detailSwitchesUsed.Count -gt 0
    $hasReportPrelude = $hasAllMode -or $hasDetailMode -or $usedSwitchLookup.ContainsKey('/FO') -or $usedSwitchLookup.ContainsKey('/NH')
    if ($TokensBeforeCurrent.Count -gt 0) {
        $lastToken = Remove-WhoamiOuterQuotes -Value $TokensBeforeCurrent[-1]
        if ($lastToken.ToUpperInvariant() -eq '/FO') {
            $valueContext = '/FO'
        }
    }

    [pscustomobject]@{
        UsedSwitchLookup  = $usedSwitchLookup
        ValueContext      = $valueContext
        FormatValue       = $formatValue
        IdentityModeSwitch = $identityModeSwitch
        DetailSwitchesUsed = @($detailSwitchesUsed)
        HasAllMode        = $hasAllMode
        HasDetailMode     = $hasDetailMode
        HasReportPrelude  = $hasReportPrelude
    }
}

function Get-WhoamiFormatCompletions {
    param(
        [string]$CurrentWord,
        [bool]$NoHeaderAlreadySpecified
    )

    $catalog = Get-WhoamiCompletionCatalog
    $typedValue = Remove-WhoamiOuterQuotes -Value $CurrentWord
    $allowedValues = if ($NoHeaderAlreadySpecified) {
        @('TABLE', 'CSV')
    } else {
        @($catalog.FormatValues)
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($value in $allowedValues) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $value.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $results.Add((New-WhoamiCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'Output format.'))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-WhoamiCompletionResult -CompletionText $CurrentWord -ResultType 'ParameterValue' -ToolTip 'Output format.'))
    }

    @($results.ToArray())
}

 function Get-WhoamiTerminalCompletions {
     param(
         [string]$CurrentWord,
         [string]$ToolTip
     )
 
    $completionText = if ([string]::IsNullOrEmpty($CurrentWord) -or $CurrentWord.StartsWith('/')) { ' ' } else { $CurrentWord }
     @(
         New-WhoamiCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $ToolTip
     )
 }

function Get-WhoamiSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State
    )

    $catalog = Get-WhoamiCompletionCatalog
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($switchText in $catalog.SwitchOrder) {
        $key = $switchText.ToUpperInvariant()
        $explicitRequest = -not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            $switchText.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)
        $includeSwitch = $false

        if ($State.UsedSwitchLookup.ContainsKey($key)) {
            continue
        }

        switch ($key) {
            '/?' {
                $includeSwitch = $State.UsedSwitchLookup.Count -eq 0
            }
            '/UPN' { $includeSwitch = -not $State.HasReportPrelude -and -not $State.IdentityModeSwitch }
            '/FQDN' { $includeSwitch = -not $State.HasReportPrelude -and -not $State.IdentityModeSwitch }
            '/LOGONID' { $includeSwitch = -not $State.HasReportPrelude -and -not $State.IdentityModeSwitch }
            '/USER' { $includeSwitch = -not $State.HasAllMode -and -not $State.IdentityModeSwitch }
            '/GROUPS' { $includeSwitch = -not $State.HasAllMode -and -not $State.IdentityModeSwitch }
            '/CLAIMS' { $includeSwitch = -not $State.HasAllMode -and -not $State.IdentityModeSwitch }
            '/PRIV' { $includeSwitch = -not $State.HasAllMode -and -not $State.IdentityModeSwitch }
            '/ALL' { $includeSwitch = -not $State.HasDetailMode -and -not $State.IdentityModeSwitch }
            '/FO' {
                $includeSwitch = -not $State.IdentityModeSwitch -and ($State.HasReportPrelude -or $explicitRequest)
            }
            '/NH' {
                $includeSwitch = -not $State.IdentityModeSwitch -and
                    -not ($State.FormatValue -and $State.FormatValue.Equals('LIST', [System.StringComparison]::OrdinalIgnoreCase)) -and
                    ($State.HasReportPrelude -or $explicitRequest)
            }
        }

        if (-not $includeSwitch) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $explicitRequest) {
            continue
        }

        $results.Add((New-WhoamiCompletionResult -CompletionText $switchText -ResultType 'ParameterName' -ToolTip $catalog.SwitchInfo[$key]))
    }

    @($results.ToArray())
}

function Complete-Whoami {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-WhoamiCompletionCatalog

    $allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokens = @($allTokens | Select-Object -Skip 1)
    $line = $commandAst.ToString()
    $currentWord = if ($null -eq $wordToComplete) {
        Get-WhoamiCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback ''
    } elseif ($wordToComplete.Length -eq 0) {
        ''
    } elseif ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        Get-WhoamiCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
    } else {
        $wordToComplete
    }

    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)
    if ($hasTrailingSpace) {
        $tokensBeforeCurrent = @($tokens)
    } elseif ($tokens.Count -gt 1) {
        $tokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
    } else {
        $tokensBeforeCurrent = @()
    }

    $state = Get-WhoamiCommandState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.UsedSwitchLookup.ContainsKey('/?')) {
        return @(Get-WhoamiTerminalCompletions -CurrentWord $currentWord -ToolTip 'No further arguments are valid after /?.')
    }

    if ($state.IdentityModeSwitch) {
        return @(Get-WhoamiTerminalCompletions -CurrentWord $currentWord -ToolTip 'No further arguments are valid after an identity-format switch.')
    }

    if ($state.ValueContext -eq '/FO') {
        return @(Get-WhoamiFormatCompletions -CurrentWord $currentWord -NoHeaderAlreadySpecified:$state.UsedSwitchLookup.ContainsKey('/NH'))
    }

    if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('/')) {
        $switchResults = @(Get-WhoamiSwitchCompletions -CurrentWord $currentWord -State $state)
        if ($switchResults.Count -gt 0) {
            return $switchResults
        }

        if ($state.HasAllMode -or $state.HasDetailMode -or $state.HasReportPrelude) {
            return @(Get-WhoamiTerminalCompletions -CurrentWord $currentWord -ToolTip 'No further arguments are valid for the current whoami mode.')
        }
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'whoami', 'whoami.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-Whoami -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
