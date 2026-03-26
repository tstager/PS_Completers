# systeminfo tab completion for PowerShell
# Builds a small help-aware switch catalog and static value hints for systeminfo.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name SysteminfoCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SysteminfoCompletionCatalog = @{
        Initialized  = $false
        SwitchOrder  = @('/S', '/U', '/P', '/FO', '/NH', '/?')
        SwitchInfo   = @{}
        FormatValues = @('TABLE', 'LIST', 'CSV')
    }
}

function New-SysteminfoCompletionResult {
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

function Get-SysteminfoStaticSwitchCatalog {
    [ordered]@{
        '/s'  = @{
            CompletionText = '/S'
            Description    = 'Specifies the remote system to connect to.'
        }
        '/u'  = @{
            CompletionText = '/U'
            Description    = 'Specifies the user context under which the command should execute.'
        }
        '/p'  = @{
            CompletionText = '/P'
            Description    = 'Specifies the password for the given user context. Prompts for input if omitted.'
        }
        '/fo' = @{
            CompletionText = '/FO'
            Description    = 'Specifies the output format. Valid values: TABLE, LIST, CSV.'
        }
        '/nh' = @{
            CompletionText = '/NH'
            Description    = 'Suppresses the column header. Valid only for TABLE and CSV output.'
        }
        '/?'  = @{
            CompletionText = '/?'
            Description    = 'Displays this help message.'
        }
    }
}

function Initialize-SysteminfoCompletionCatalog {
    if ($script:SysteminfoCompletionCatalog.Initialized) {
        return
    }

    $catalog = Get-SysteminfoStaticSwitchCatalog

    $script:SysteminfoCompletionCatalog.SwitchInfo = @{}
    foreach ($entry in $catalog.GetEnumerator()) {
        $script:SysteminfoCompletionCatalog.SwitchInfo[$entry.Key] = @{
            CompletionText = $entry.Value.CompletionText
            Description    = $entry.Value.Description
        }
    }

    $script:SysteminfoCompletionCatalog.Initialized = $true
}

function Get-SysteminfoCurrentToken {
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

function Remove-SysteminfoOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function Get-SysteminfoCommandState {
    param([string[]]$TokensBeforeCurrent)

    $usedSwitchLookup = @{}
    $valuesBySwitch = @{}
    $valueTakingSwitches = @{
        '/s'  = $true
        '/u'  = $true
        '/p'  = $true
        '/fo' = $true
    }

    for ($i = 0; $i -lt $TokensBeforeCurrent.Count; $i++) {
        $token = $TokensBeforeCurrent[$i]
        if (-not $token.StartsWith('/')) {
            continue
        }

        $switchKey = $token.ToLowerInvariant()
        $usedSwitchLookup[$switchKey] = $true

        if ($valueTakingSwitches.ContainsKey($switchKey) -and $i + 1 -lt $TokensBeforeCurrent.Count) {
            $nextToken = $TokensBeforeCurrent[$i + 1]
            if (-not $nextToken.StartsWith('/')) {
                $valuesBySwitch[$switchKey] = $nextToken
                $i++
            }
        }
    }

    $valueContext = $null
    if ($TokensBeforeCurrent.Count -gt 0) {
        $lastToken = $TokensBeforeCurrent[-1].ToLowerInvariant()
        if ($valueTakingSwitches.ContainsKey($lastToken)) {
            $valueContext = $lastToken
        }
    }

    $formatValue = $null
    if ($valuesBySwitch.ContainsKey('/fo')) {
        $formatValue = $valuesBySwitch['/fo']
    }

    [pscustomobject]@{
        UsedSwitchLookup = $usedSwitchLookup
        ValueContext     = $valueContext
        FormatValue      = $formatValue
    }
}

function Get-SysteminfoPlaceholderValueCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$Candidates,
        [string]$GenericToolTip
    )

    $typedValue = Remove-SysteminfoOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $candidate.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $results.Add((New-SysteminfoCompletionResult -CompletionText $candidate -ResultType 'ParameterValue' -ToolTip $GenericToolTip))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-SysteminfoCompletionResult -CompletionText $CurrentWord -ResultType 'ParameterValue' -ToolTip $GenericToolTip))
    }

    @($results.ToArray())
}

function Get-SysteminfoFormatCompletions {
    param(
        [string]$CurrentWord,
        [bool]$NoHeaderAlreadySpecified
    )

    $typedValue = Remove-SysteminfoOuterQuotes -Value $CurrentWord
    $allowedValues = if ($NoHeaderAlreadySpecified) {
        @('TABLE', 'CSV')
    } else {
        @($script:SysteminfoCompletionCatalog.FormatValues)
    }

    $allowedValues |
        Where-Object {
            [string]::IsNullOrWhiteSpace($typedValue) -or
            $_.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)
        } |
        ForEach-Object {
            New-SysteminfoCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip 'Output format.'
        }
}

function Get-SysteminfoSwitchCompletions {
    param(
        [string]$CurrentWord,
        [hashtable]$UsedSwitchLookup,
        [string]$FormatValue
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($switchText in $script:SysteminfoCompletionCatalog.SwitchOrder) {
        $key = $switchText.ToLowerInvariant()
        $includeSwitch = $true

        if ($UsedSwitchLookup.ContainsKey('/?')) {
            break
        }

        if ($UsedSwitchLookup.ContainsKey($key)) {
            continue
        }

        switch ($key) {
            '/nh' {
                if ($FormatValue -and $FormatValue.Equals('LIST', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $includeSwitch = $false
                }
            }
            '/?' {
                if ($UsedSwitchLookup.Count -gt 0) {
                    $includeSwitch = $false
                }
            }
        }

        if (-not $includeSwitch) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            -not $switchText.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $toolTip = $script:SysteminfoCompletionCatalog.SwitchInfo[$key].Description
        $results.Add((New-SysteminfoCompletionResult -CompletionText $switchText -ResultType 'ParameterName' -ToolTip $toolTip))
    }

    @($results.ToArray())
}

function Get-SysteminfoTerminalCompletions {
    param([string]$CurrentWord)

    $completionText = if ([string]::IsNullOrEmpty($CurrentWord)) { ' ' } else { $CurrentWord }
    @(
        New-SysteminfoCompletionResult `
            -CompletionText $completionText `
            -ResultType 'ParameterValue' `
            -ToolTip 'No further arguments are valid after /?.'
    )
}

function Complete-Systeminfo {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-SysteminfoCompletionCatalog

    $allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokens = @($allTokens | Select-Object -Skip 1)
    $line = $commandAst.ToString()
    $currentWord = if ($null -eq $wordToComplete) {
        Get-SysteminfoCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback ''
    } elseif ($wordToComplete.Length -eq 0) {
        ''
    } elseif ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        Get-SysteminfoCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
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

    $state = Get-SysteminfoCommandState -TokensBeforeCurrent $tokensBeforeCurrent
    $usedSwitchLookup = $state.UsedSwitchLookup

    if ($usedSwitchLookup.ContainsKey('/?')) {
        return @(Get-SysteminfoTerminalCompletions -CurrentWord $currentWord)
    }

    if ($state.ValueContext -eq '/p' -and
        -not [string]::IsNullOrEmpty($currentWord) -and
        $currentWord.StartsWith('/')) {
        return @(Get-SysteminfoSwitchCompletions -CurrentWord $currentWord -UsedSwitchLookup $usedSwitchLookup -FormatValue $state.FormatValue)
    }

    switch ($state.ValueContext) {
        '/s' {
            return @(Get-SysteminfoPlaceholderValueCompletions -CurrentWord $currentWord -Candidates @('<computer-name>', '<ip-address>', 'localhost', '\\localhost') -GenericToolTip 'Remote computer name or IP address.')
        }
        '/u' {
            return @(Get-SysteminfoPlaceholderValueCompletions -CurrentWord $currentWord -Candidates @('<domain\user>', '<user>') -GenericToolTip 'User name in [domain\]user form.')
        }
        '/p' {
            return @(Get-SysteminfoPlaceholderValueCompletions -CurrentWord $currentWord -Candidates @('<password>') -GenericToolTip 'Password value. If omitted, systeminfo prompts interactively.')
        }
        '/fo' {
            return @(Get-SysteminfoFormatCompletions -CurrentWord $currentWord -NoHeaderAlreadySpecified:$usedSwitchLookup.ContainsKey('/nh'))
        }
    }

    if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('/')) {
        return @(Get-SysteminfoSwitchCompletions -CurrentWord $currentWord -UsedSwitchLookup $usedSwitchLookup -FormatValue $state.FormatValue)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'systeminfo', 'systeminfo.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-Systeminfo -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
