# schtasks tab completion for PowerShell
# Builds completion data from schtasks built-in help.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name SchtasksCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SchtasksCompletionCatalog = @{
        Initialized          = $false
        Subcommands          = @()
        OptionTokensByKey    = @{}
        ValueHintsByOption   = @{}
        TaskNameCache        = @()
        TaskNameCacheUpdated = [datetime]::MinValue
    }
}

function Invoke-SchtasksHelpText {
    param([string[]]$Arguments)

    if (-not (Get-Command -Name schtasks.exe -ErrorAction SilentlyContinue)) {
        return @()
    }

    @(& schtasks.exe @Arguments '/?' 2>$null)
}

function Get-SchtasksParameterMap {
    param([string[]]$Lines)

    $result = @{}
    $inParameterList = $false
    $currentToken = $null

    foreach ($line in $Lines) {
        if ($line -match '^\s*Parameter List:\s*$') {
            $inParameterList = $true
            continue
        }

        if (-not $inParameterList) {
            continue
        }

        if ($line -match '^\s*Examples?:\s*$') {
            break
        }

        if ($line -match '^\s*(/[A-Za-z?][A-Za-z0-9?]*)\b') {
            $currentToken = $matches[1]
            if (-not $result.ContainsKey($currentToken)) {
                $result[$currentToken] = New-Object System.Collections.Generic.List[string]
            }

            $result[$currentToken].Add($line.Trim())
            continue
        }

        if ($currentToken -and -not [string]::IsNullOrWhiteSpace($line)) {
            $result[$currentToken].Add($line.Trim())
        }
    }

    $parameterMap = @{}
    foreach ($token in $result.Keys) {
        $parameterMap[$token] = @($result[$token])
    }

    $parameterMap
}

function Get-SchtasksStaticValueHints {
    @{
        '/sc'  = @('MINUTE', 'HOURLY', 'DAILY', 'WEEKLY', 'MONTHLY', 'ONCE', 'ONSTART', 'ONLOGON', 'ONIDLE', 'ONEVENT')
        '/fo'  = @('TABLE', 'LIST', 'CSV')
        '/rl'  = @('LIMITED', 'HIGHEST')
        '/d'   = @('MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN', '*')
        '/m'   = @('JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC', '*')
        '/xml' = @('ONE')
        '/ru'  = @(
            'SYSTEM',
            '"NT AUTHORITY\SYSTEM"',
            '"NT AUTHORITY\LOCALSERVICE"',
            '"NT AUTHORITY\NETWORKSERVICE"'
        )
    }
}

function Initialize-SchtasksCompletionCatalog {
    if ($script:SchtasksCompletionCatalog.Initialized) {
        return
    }

    $topHelp = Invoke-SchtasksHelpText
    if (-not $topHelp -or $topHelp.Count -eq 0) {
        $script:SchtasksCompletionCatalog.Initialized = $true
        return
    }

    $topParameterMap = Get-SchtasksParameterMap -Lines $topHelp
    $subcommands = @($topParameterMap.Keys | Where-Object { $_ -ne '/?' } | Sort-Object -Unique)

    $script:SchtasksCompletionCatalog.Subcommands = $subcommands
    $script:SchtasksCompletionCatalog.OptionTokensByKey['__top__'] = @($topParameterMap.Keys | Sort-Object -Unique)
    $script:SchtasksCompletionCatalog.ValueHintsByOption = Get-SchtasksStaticValueHints

    foreach ($subcommand in $subcommands) {
        $helpLines = Invoke-SchtasksHelpText -Arguments @($subcommand)
        $parameterMap = Get-SchtasksParameterMap -Lines $helpLines
        $script:SchtasksCompletionCatalog.OptionTokensByKey[$subcommand.ToLowerInvariant()] =
            @($parameterMap.Keys | Sort-Object -Unique)
    }

    $script:SchtasksCompletionCatalog.Initialized = $true
}

function Get-SchtasksActiveSubcommand {
    param(
        [string[]]$Tokens,
        [string[]]$KnownSubcommands
    )

    $known = @{}
    foreach ($subcommand in $KnownSubcommands) {
        $known[$subcommand.ToLowerInvariant()] = $subcommand
    }

    foreach ($token in $Tokens) {
        $lookup = $token.ToLowerInvariant()
        if ($known.ContainsKey($lookup)) {
            return $known[$lookup]
        }
    }

    $null
}

function ConvertTo-SchtasksQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + $Value + '"'
    }

    $Value
}

function New-SchtasksCompletionResult {
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

function Get-SchtasksPathCompletions {
    param(
        [string]$InputPath,
        [string[]]$AllowedExtensions
    )

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    $parent = Split-Path -Path $cleanInput -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) {
        $parent = '.'
    }

    $leaf = Split-Path -Path $cleanInput -Leaf
    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }

    $items = Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue
    if ($AllowedExtensions -and $AllowedExtensions.Count -gt 0) {
        $items = $items | Where-Object {
            $_.PSIsContainer -or ($AllowedExtensions -contains $_.Extension.ToLowerInvariant())
        }
    }

    $alwaysQuote = $InputPath.StartsWith('"')
    $items | ForEach-Object { ConvertTo-SchtasksQuotedValue -Value $_.FullName -AlwaysQuote $alwaysQuote }
}

function Update-SchtasksTaskNameCache {
    $cacheAge = (Get-Date) - $script:SchtasksCompletionCatalog.TaskNameCacheUpdated
    if ($cacheAge.TotalSeconds -lt 60 -and $script:SchtasksCompletionCatalog.TaskNameCache.Count -gt 0) {
        return
    }

    $csvLines = @(& schtasks.exe /Query /FO CSV 2>$null)
    if (-not $csvLines -or $csvLines.Count -lt 2) {
        $script:SchtasksCompletionCatalog.TaskNameCache = @()
        $script:SchtasksCompletionCatalog.TaskNameCacheUpdated = Get-Date
        return
    }

    $rows = @($csvLines | ConvertFrom-Csv)
    $taskNames = foreach ($row in $rows) {
        $firstProperty = $row.PSObject.Properties | Select-Object -First 1
        if ($firstProperty) {
            $firstProperty.Value
        }
    }

    $script:SchtasksCompletionCatalog.TaskNameCache = @($taskNames | Where-Object { $_ } | Sort-Object -Unique)
    $script:SchtasksCompletionCatalog.TaskNameCacheUpdated = Get-Date
}

function Get-SchtasksTaskNameCompletions {
    param([string]$WordToComplete)

    Update-SchtasksTaskNameCache

    $cleanPrefix = $WordToComplete.Trim('"')
    $alwaysQuote = $WordToComplete.StartsWith('"')

    $script:SchtasksCompletionCatalog.TaskNameCache |
        Where-Object { $_ -like "$cleanPrefix*" } |
        ForEach-Object { ConvertTo-SchtasksQuotedValue -Value $_ -AlwaysQuote $alwaysQuote }
}

function Get-SchtasksExpectedValueOption {
    param(
        [string[]]$TokensBeforeCurrent,
        [string[]]$KnownSubcommands
    )

    if (-not $TokensBeforeCurrent -or $TokensBeforeCurrent.Count -eq 0) {
        return $null
    }

    $lastToken = $TokensBeforeCurrent[-1]
    if (-not $lastToken.StartsWith('/')) {
        return $null
    }

    foreach ($subcommand in $KnownSubcommands) {
        if ($lastToken.Equals($subcommand, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }
    }

    if ($lastToken -eq '/?') {
        return $null
    }

    $lastToken
}

function Get-SchtasksCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    if ($CursorPosition -gt $Line.Length) {
        return ''
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

function Test-SchtasksPathLikeOption {
    param([string]$Option)

    switch ($Option.ToLowerInvariant()) {
        '/tr' { $true }
        '/xml' { $true }
        default { $false }
    }
}

function Get-SchtasksAllowedExtensionsForOption {
    param([string]$Option)

    switch ($Option.ToLowerInvariant()) {
        '/xml' { @('.xml') }
        default { @() }
    }
}

Register-ArgumentCompleter -Native -CommandName 'schtasks', 'schtasks.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Initialize-SchtasksCompletionCatalog

    $allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokens = @($allTokens | Select-Object -Skip 1)
    $line = $commandAst.ToString()
    $currentWord = if ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        Get-SchtasksCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
    } else {
        $wordToComplete
    }
    $hasTrailingSpace = ($line -match '\s$') -or ($cursorPosition -gt $line.Length)

    if ($hasTrailingSpace) {
        $tokensBeforeCurrent = @($tokens)
    } elseif ($tokens.Count -gt 1) {
        $tokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
    } else {
        $tokensBeforeCurrent = @()
    }

    $activeSubcommand = Get-SchtasksActiveSubcommand -Tokens $tokensBeforeCurrent -KnownSubcommands $script:SchtasksCompletionCatalog.Subcommands
    $expectedValueOption = Get-SchtasksExpectedValueOption -TokensBeforeCurrent $tokensBeforeCurrent -KnownSubcommands $script:SchtasksCompletionCatalog.Subcommands

    if ($expectedValueOption) {
        switch ($expectedValueOption.ToLowerInvariant()) {
            '/tn' {
                if ($activeSubcommand -and -not $activeSubcommand.Equals('/Create', [System.StringComparison]::OrdinalIgnoreCase)) {
                    return Get-SchtasksTaskNameCompletions -WordToComplete $currentWord |
                        ForEach-Object {
                            New-SchtasksCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                        }
                }
            }
        }

        if (Test-SchtasksPathLikeOption -Option $expectedValueOption) {
            $allowedExtensions = Get-SchtasksAllowedExtensionsForOption -Option $expectedValueOption
            return Get-SchtasksPathCompletions -InputPath $currentWord -AllowedExtensions $allowedExtensions |
                ForEach-Object {
                    New-SchtasksCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                }
        }

        $optionKey = $expectedValueOption.ToLowerInvariant()
        if ($script:SchtasksCompletionCatalog.ValueHintsByOption.ContainsKey($optionKey)) {
            return $script:SchtasksCompletionCatalog.ValueHintsByOption[$optionKey] |
                Where-Object { $_ -like "$currentWord*" } |
                ForEach-Object {
                    New-SchtasksCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                }
        }
    }

    if (-not $activeSubcommand) {
        $topSuggestions = @($script:SchtasksCompletionCatalog.Subcommands + '/?')
        if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('/')) {
            return $topSuggestions |
                Sort-Object -Unique |
                Where-Object { $_ -like "$currentWord*" } |
                ForEach-Object {
                    New-SchtasksCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
                }
        }

        return @()
    }

    if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('/')) {
        $optionKey = $activeSubcommand.ToLowerInvariant()
        $suggestions = @()

        if ($script:SchtasksCompletionCatalog.OptionTokensByKey.ContainsKey($optionKey)) {
            $suggestions = @($script:SchtasksCompletionCatalog.OptionTokensByKey[$optionKey])
        }

        return $suggestions |
            Sort-Object -Unique |
            Where-Object { $_ -like "$currentWord*" } |
            ForEach-Object {
                New-SchtasksCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
            }
    }

    @()
}
