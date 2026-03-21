# tasklist.exe tab completion for PowerShell
# Builds completion data from tasklist built-in help.
# Usage: . .\tasklist_completer.ps1

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name TasklistCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:TasklistCompletionCatalog = @{
        Initialized            = $false
        SwitchTokens           = @()
        OptionToolTipsByToken  = @{}
        ValueHintsByOption     = @{}
        FilterNames            = @()
        FilterOperatorsByName  = @{}
        FilterValueHintsByName = @{}
        RuntimeSnapshot        = @()
        RuntimeSnapshotUpdated = [datetime]::MinValue
        RuntimeSnapshotTtlSeconds = 15
        UserNames             = @()
        UserNamesUpdated      = [datetime]::MinValue
        UserNamesTtlSeconds   = 30
        ServiceNames          = @()
        ServiceNamesUpdated   = [datetime]::MinValue
        ServiceNamesTtlSeconds = 60
        WindowTitles          = @()
        WindowTitlesUpdated   = [datetime]::MinValue
        WindowTitlesTtlSeconds = 10
        ModuleNames           = @()
        ModuleNamesUpdated    = [datetime]::MinValue
        ModuleNamesTtlSeconds = 30
    }
}

function Test-TasklistCommandAvailable {
    if (Get-Command -Name tasklist.exe -ErrorAction SilentlyContinue) {
        return $true
    }

    if (Get-Command -Name tasklist -ErrorAction SilentlyContinue) {
        return $true
    }

    $false
}

function Invoke-TasklistHelpText {
    if (-not (Get-Command -Name tasklist.exe -ErrorAction SilentlyContinue)) {
        return @()
    }

    @(& tasklist.exe '/?' 2>$null)
}

function New-TasklistCompletionResult {
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

function New-TasklistValueItem {
    param(
        [string]$CompletionText,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [pscustomobject]@{
        CompletionText = $CompletionText
        ToolTip        = $ToolTip
    }
}

function Get-TasklistDefaultSwitchTokens {
    @('/S', '/U', '/P', '/M', '/SVC', '/APPS', '/V', '/FI', '/FO', '/NH', '/?')
}

function Get-TasklistDefaultOptionToolTips {
    @{
        '/S'   = 'Specifies the remote system to connect to.'
        '/U'   = 'Specifies the user context under which the command should execute.'
        '/P'   = 'Specifies the password for the given user context.'
        '/M'   = 'Lists tasks using the given exe or dll name.'
        '/SVC' = 'Displays services hosted in each process.'
        '/APPS' = 'Displays Store Apps and their associated processes.'
        '/V'   = 'Displays verbose task information.'
        '/FI'  = 'Displays tasks that match the specified filter expression.'
        '/FO'  = 'Specifies the output format: TABLE, LIST, or CSV.'
        '/NH'  = 'Suppresses the header row for TABLE and CSV output.'
        '/?'   = 'Displays tasklist help.'
    }
}

function Get-TasklistDefaultFilterOperators {
    @{
        'STATUS'      = @('eq', 'ne')
        'IMAGENAME'   = @('eq', 'ne')
        'PID'         = @('eq', 'ne', 'gt', 'lt', 'ge', 'le')
        'SESSION'     = @('eq', 'ne', 'gt', 'lt', 'ge', 'le')
        'SESSIONNAME' = @('eq', 'ne')
        'CPUTIME'     = @('eq', 'ne', 'gt', 'lt', 'ge', 'le')
        'MEMUSAGE'    = @('eq', 'ne', 'gt', 'lt', 'ge', 'le')
        'USERNAME'    = @('eq', 'ne')
        'SERVICES'    = @('eq', 'ne')
        'WINDOWTITLE' = @('eq', 'ne')
        'MODULES'     = @('eq', 'ne')
    }
}

function Get-TasklistDefaultFilterValueHints {
    @{
        'STATUS' = @('RUNNING', 'SUSPENDED', 'NOT RESPONDING', 'UNKNOWN')
    }
}

function Get-TasklistParameterMap {
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

        if ($line -match '^\s*Filters:\s*$' -or $line -match '^\s*Examples?:\s*$') {
            break
        }

        if ($line -match '^\s*(/[A-Za-z?][A-Za-z0-9?]*)\b') {
            $currentToken = $matches[1].ToUpperInvariant()
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

function Get-TasklistFilterDefinitions {
    param([string[]]$Lines)

    $definitions = @{}
    $inFilters = $false
    $currentFilterName = $null

    foreach ($line in $Lines) {
        if ($line -match '^\s*Filters:\s*$') {
            $inFilters = $true
            continue
        }

        if (-not $inFilters) {
            continue
        }

        if ($line -match '^\s*(NOTE:|Examples?:)\b') {
            break
        }

        if ($line -match '^\s*Filter Name\s+Valid Operators' -or $line -match '^\s*-{3,}') {
            continue
        }

        if ($line -match '^\s*([A-Z][A-Z0-9]+)\s+([a-z,\s]+?)\s{2,}(.+?)\s*$') {
            $currentFilterName = $matches[1].ToUpperInvariant()
            $definitions[$currentFilterName] = [pscustomobject]@{
                FilterName = $currentFilterName
                Operators  = @($matches[2] -split '\s*,\s*' | Where-Object { $_ })
                ValueLines = [System.Collections.Generic.List[string]]::new()
            }

            if (-not [string]::IsNullOrWhiteSpace($matches[3])) {
                $definitions[$currentFilterName].ValueLines.Add($matches[3].Trim())
            }

            continue
        }

        if ($currentFilterName -and -not [string]::IsNullOrWhiteSpace($line)) {
            $definitions[$currentFilterName].ValueLines.Add($line.Trim())
        }
    }

    @($definitions.Values)
}

function Get-TasklistDocumentedFilterValueHints {
    param(
        [string]$FilterName,
        [string[]]$ValueLines
    )

    switch ($FilterName.ToUpperInvariant()) {
        'STATUS' {
            $joined = ($ValueLines -join ' | ')
            @(
                $joined -split '\|' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ }
            )
        }
        default {
            @()
        }
    }
}

function Initialize-TasklistCompletionCatalog {
    if ($script:TasklistCompletionCatalog.Initialized) {
        return
    }

    $defaultSwitchTokens = Get-TasklistDefaultSwitchTokens
    $script:TasklistCompletionCatalog.SwitchTokens = @($defaultSwitchTokens)
    $script:TasklistCompletionCatalog.OptionToolTipsByToken = Get-TasklistDefaultOptionToolTips
    $script:TasklistCompletionCatalog.ValueHintsByOption = @{
        '/FO' = @('TABLE', 'LIST', 'CSV')
    }

    $defaultFilterOperators = Get-TasklistDefaultFilterOperators
    $defaultFilterValueHints = Get-TasklistDefaultFilterValueHints
    $script:TasklistCompletionCatalog.FilterNames = @($defaultFilterOperators.Keys | Sort-Object)
    $script:TasklistCompletionCatalog.FilterOperatorsByName = @{}
    $script:TasklistCompletionCatalog.FilterValueHintsByName = @{}

    foreach ($filterName in $defaultFilterOperators.Keys) {
        $script:TasklistCompletionCatalog.FilterOperatorsByName[$filterName] = @($defaultFilterOperators[$filterName])
    }

    foreach ($filterName in $defaultFilterValueHints.Keys) {
        $script:TasklistCompletionCatalog.FilterValueHintsByName[$filterName] = @($defaultFilterValueHints[$filterName])
    }

    $helpLines = Invoke-TasklistHelpText
    if ($helpLines -and $helpLines.Count -gt 0) {
        $parameterMap = Get-TasklistParameterMap -Lines $helpLines
        if ($parameterMap.Count -gt 0) {
            $orderedTokens = [System.Collections.Generic.List[string]]::new()
            $seenTokens = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($token in $defaultSwitchTokens) {
                if ($seenTokens.Add($token)) {
                    $orderedTokens.Add($token)
                }
            }

            foreach ($token in @($parameterMap.Keys | Sort-Object)) {
                if ($seenTokens.Add($token)) {
                    $orderedTokens.Add($token)
                }

                $script:TasklistCompletionCatalog.OptionToolTipsByToken[$token] = ($parameterMap[$token] -join ' ')
            }

            $script:TasklistCompletionCatalog.SwitchTokens = @($orderedTokens)
        }

        $filterDefinitions = Get-TasklistFilterDefinitions -Lines $helpLines
        if ($filterDefinitions.Count -gt 0) {
            $filterNames = [System.Collections.Generic.List[string]]::new()
            foreach ($definition in $filterDefinitions | Sort-Object FilterName) {
                $filterNames.Add($definition.FilterName)
                $script:TasklistCompletionCatalog.FilterOperatorsByName[$definition.FilterName] = @($definition.Operators)

                $documentedHints = Get-TasklistDocumentedFilterValueHints -FilterName $definition.FilterName -ValueLines @($definition.ValueLines)
                if (@($documentedHints).Count -gt 0) {
                    $script:TasklistCompletionCatalog.FilterValueHintsByName[$definition.FilterName] = @($documentedHints)
                }
            }

            $script:TasklistCompletionCatalog.FilterNames = @($filterNames)
        }
    }

    $script:TasklistCompletionCatalog.Initialized = $true
}

function Update-TasklistRuntimeSnapshotCache {
    $cacheAge = (Get-Date) - $script:TasklistCompletionCatalog.RuntimeSnapshotUpdated
    if ($cacheAge.TotalSeconds -lt $script:TasklistCompletionCatalog.RuntimeSnapshotTtlSeconds) {
        return
    }

    $csvLines = @(& tasklist.exe '/FO' 'CSV' '/NH' 2>$null)
    if (-not $csvLines -or $csvLines.Count -eq 0) {
        $script:TasklistCompletionCatalog.RuntimeSnapshot = @()
        $script:TasklistCompletionCatalog.RuntimeSnapshotUpdated = Get-Date
        return
    }

    $rows = @(
        $csvLines |
            ConvertFrom-Csv -Header @('ImageName', 'PID', 'SessionName', 'SessionId', 'MemUsage')
    )

    $script:TasklistCompletionCatalog.RuntimeSnapshot = @($rows)
    $script:TasklistCompletionCatalog.RuntimeSnapshotUpdated = Get-Date
}

function Update-TasklistUserNameCache {
    $cacheAge = (Get-Date) - $script:TasklistCompletionCatalog.UserNamesUpdated
    if ($cacheAge.TotalSeconds -lt $script:TasklistCompletionCatalog.UserNamesTtlSeconds) {
        return
    }

    $nameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $userNames = [System.Collections.Generic.List[string]]::new()

    foreach ($process in @(Get-Process -IncludeUserName -ErrorAction SilentlyContinue)) {
        if ($process.UserName -and $process.UserName -ne 'N/A' -and $nameSet.Add($process.UserName)) {
            $userNames.Add($process.UserName)
        }
    }

    if ($env:USERDOMAIN -and $env:USERNAME) {
        $currentUserName = "$($env:USERDOMAIN)\$($env:USERNAME)"
        if ($nameSet.Add($currentUserName)) {
            $userNames.Add($currentUserName)
        }
    }

    $script:TasklistCompletionCatalog.UserNames = @($userNames | Sort-Object)
    $script:TasklistCompletionCatalog.UserNamesUpdated = Get-Date
}

function Update-TasklistServiceNameCache {
    $cacheAge = (Get-Date) - $script:TasklistCompletionCatalog.ServiceNamesUpdated
    if ($cacheAge.TotalSeconds -lt $script:TasklistCompletionCatalog.ServiceNamesTtlSeconds) {
        return
    }

    $serviceNames = @(
        Get-Service -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name |
            Sort-Object -Unique
    )

    $script:TasklistCompletionCatalog.ServiceNames = @($serviceNames)
    $script:TasklistCompletionCatalog.ServiceNamesUpdated = Get-Date
}

function Update-TasklistWindowTitleCache {
    $cacheAge = (Get-Date) - $script:TasklistCompletionCatalog.WindowTitlesUpdated
    if ($cacheAge.TotalSeconds -lt $script:TasklistCompletionCatalog.WindowTitlesTtlSeconds) {
        return
    }

    $windowTitles = @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle) } |
            Select-Object -ExpandProperty MainWindowTitle |
            Sort-Object -Unique
    )

    $script:TasklistCompletionCatalog.WindowTitles = @($windowTitles)
    $script:TasklistCompletionCatalog.WindowTitlesUpdated = Get-Date
}

function Update-TasklistModuleNameCache {
    $cacheAge = (Get-Date) - $script:TasklistCompletionCatalog.ModuleNamesUpdated
    if ($cacheAge.TotalSeconds -lt $script:TasklistCompletionCatalog.ModuleNamesTtlSeconds) {
        return
    }

    $moduleNames = @(
        Get-Process -Module -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty ModuleName |
            Sort-Object -Unique
    )

    $script:TasklistCompletionCatalog.ModuleNames = @($moduleNames)
    $script:TasklistCompletionCatalog.ModuleNamesUpdated = Get-Date
}

function Get-TasklistTokenState {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    if ([string]::IsNullOrEmpty($Line)) {
        return [pscustomobject]@{
            ArgumentTokens      = @()
            CurrentToken        = ''
            TokensBeforeCurrent = @()
            HasTrailingDelimiter = $false
        }
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $linePrefix = $Line.Substring(0, $safeCursor)
    $tokenBuilder = [System.Text.StringBuilder]::new()
    $commandTokens = [System.Collections.Generic.List[string]]::new()
    $inQuotes = $false

    foreach ($character in $linePrefix.ToCharArray()) {
        if ($character -eq '"') {
            $null = $tokenBuilder.Append($character)
            $inQuotes = -not $inQuotes
            continue
        }

        if ([char]::IsWhiteSpace($character) -and -not $inQuotes) {
            if ($tokenBuilder.Length -gt 0) {
                $commandTokens.Add($tokenBuilder.ToString())
                $null = $tokenBuilder.Clear()
            }

            continue
        }

        $null = $tokenBuilder.Append($character)
    }

    $hasTrailingDelimiter = $false
    if (-not $inQuotes -and $linePrefix.Length -gt 0) {
        $hasTrailingDelimiter = [char]::IsWhiteSpace($linePrefix[$linePrefix.Length - 1])
    }

    $currentToken = if ($hasTrailingDelimiter) { '' } else { $tokenBuilder.ToString() }
    if (-not $hasTrailingDelimiter -and $tokenBuilder.Length -gt 0) {
        $commandTokens.Add($currentToken)
    }

    [object[]]$argumentTokens = if ($commandTokens.Count -gt 1) {
        @($commandTokens | Select-Object -Skip 1)
    } else {
        @()
    }

    [object[]]$tokensBeforeCurrent = if ($hasTrailingDelimiter) {
        @($argumentTokens)
    } elseif ($argumentTokens.Count -gt 0) {
        @($argumentTokens | Select-Object -First ($argumentTokens.Count - 1))
    } else {
        @()
    }

    [pscustomobject]@{
        ArgumentTokens      = $argumentTokens
        CurrentToken        = $currentToken
        TokensBeforeCurrent = $tokensBeforeCurrent
        HasTrailingDelimiter = $hasTrailingDelimiter
    }
}

function Get-TasklistExpectedValueOption {
    param([string[]]$TokensBeforeCurrent)

    if (-not $TokensBeforeCurrent -or $TokensBeforeCurrent.Count -eq 0) {
        return $null
    }

    $lastToken = $TokensBeforeCurrent[-1].ToUpperInvariant()
    switch ($lastToken) {
        '/S' { '/S' }
        '/U' { '/U' }
        '/P' { '/P' }
        '/M' { '/M' }
        '/FO' { '/FO' }
        default { $null }
    }
}

function Resolve-TasklistFilterName {
    param([string]$FilterName)

    foreach ($knownFilterName in $script:TasklistCompletionCatalog.FilterNames) {
        if ($knownFilterName.Equals($FilterName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $knownFilterName
        }
    }

    $null
}

function Format-TasklistFilterExpressionCompletion {
    param(
        [string]$Expression,
        [bool]$CloseQuote = $false
    )

    if ($CloseQuote) {
        return '"' + $Expression + '"'
    }

    '"' + $Expression
}

function Test-TasklistClosedQuotedExpression {
    param([string]$Expression)

    if ([string]::IsNullOrEmpty($Expression)) {
        return $false
    }

    $trimmedExpression = $Expression.Trim()
    if (-not $trimmedExpression.StartsWith('"')) {
        return $false
    }

    $quoteCount = 0
    foreach ($character in $trimmedExpression.ToCharArray()) {
        if ($character -eq '"') {
            $quoteCount++
        }
    }

    ($quoteCount -ge 2) -and (($quoteCount % 2) -eq 0) -and $trimmedExpression.EndsWith('"')
}

function Get-TasklistFilterValueItems {
    param(
        [string]$FilterName,
        [string]$TypedValue
    )

    switch ($FilterName.ToUpperInvariant()) {
        'STATUS' {
            @(
                $script:TasklistCompletionCatalog.FilterValueHintsByName['STATUS'] |
                    ForEach-Object {
                        New-TasklistValueItem -CompletionText $_ -ToolTip "Status value $_"
                    }
            )
        }
        'CPUTIME' {
            @(
                New-TasklistValueItem -CompletionText '00:00:00' -ToolTip 'CPU time in hh:mm:ss format'
                New-TasklistValueItem -CompletionText '00:01:00' -ToolTip 'CPU time in hh:mm:ss format'
                New-TasklistValueItem -CompletionText '01:00:00' -ToolTip 'CPU time in hh:mm:ss format'
            )
        }
        'MEMUSAGE' {
            @(
                New-TasklistValueItem -CompletionText '1024' -ToolTip 'Memory usage in KB'
                New-TasklistValueItem -CompletionText '4096' -ToolTip 'Memory usage in KB'
                New-TasklistValueItem -CompletionText '65536' -ToolTip 'Memory usage in KB'
            )
        }
        'IMAGENAME' {
            Update-TasklistRuntimeSnapshotCache
            @(
                $script:TasklistCompletionCatalog.RuntimeSnapshot |
                    ForEach-Object { $_.ImageName } |
                    Where-Object { $_ } |
                    Sort-Object -Unique |
                    ForEach-Object {
                        New-TasklistValueItem -CompletionText $_ -ToolTip "Image name $_"
                    }
            )
        }
        'PID' {
            Update-TasklistRuntimeSnapshotCache
            @(
                $script:TasklistCompletionCatalog.RuntimeSnapshot |
                    ForEach-Object { [string]$_.PID } |
                    Where-Object { $_ } |
                    Sort-Object -Unique |
                    ForEach-Object {
                        New-TasklistValueItem -CompletionText $_ -ToolTip "Process ID $_"
                    }
            )
        }
        'SESSION' {
            Update-TasklistRuntimeSnapshotCache
            @(
                $script:TasklistCompletionCatalog.RuntimeSnapshot |
                    ForEach-Object { [string]$_.SessionId } |
                    Where-Object { $_ } |
                    Sort-Object -Unique |
                    ForEach-Object {
                        New-TasklistValueItem -CompletionText $_ -ToolTip "Session ID $_"
                    }
            )
        }
        'SESSIONNAME' {
            Update-TasklistRuntimeSnapshotCache
            @(
                $script:TasklistCompletionCatalog.RuntimeSnapshot |
                    ForEach-Object { $_.SessionName } |
                    Where-Object { $_ } |
                    Sort-Object -Unique |
                    ForEach-Object {
                        New-TasklistValueItem -CompletionText $_ -ToolTip "Session name $_"
                    }
            )
        }
        'USERNAME' {
            Update-TasklistUserNameCache
            @(
                $script:TasklistCompletionCatalog.UserNames |
                    ForEach-Object {
                        New-TasklistValueItem -CompletionText $_ -ToolTip "User name $_"
                    }
            )
        }
        'SERVICES' {
            Update-TasklistServiceNameCache
            @(
                $script:TasklistCompletionCatalog.ServiceNames |
                    ForEach-Object {
                        New-TasklistValueItem -CompletionText $_ -ToolTip "Service name $_"
                    }
            )
        }
        'WINDOWTITLE' {
            Update-TasklistWindowTitleCache
            @(
                $script:TasklistCompletionCatalog.WindowTitles |
                    ForEach-Object {
                        New-TasklistValueItem -CompletionText $_ -ToolTip "Window title $_"
                    }
            )
        }
        'MODULES' {
            Update-TasklistModuleNameCache
            @(
                $script:TasklistCompletionCatalog.ModuleNames |
                    ForEach-Object {
                        New-TasklistValueItem -CompletionText $_ -ToolTip "Module name $_"
                    }
            )
        }
        default {
            @()
        }
    }
}

function Get-TasklistSwitchCompletions {
    param([string]$CurrentWord)

    $prefix = if ([string]::IsNullOrEmpty($CurrentWord)) { '' } else { $CurrentWord }
    $script:TasklistCompletionCatalog.SwitchTokens |
        Where-Object { $_ -like "$prefix*" } |
        ForEach-Object {
            $toolTip = $script:TasklistCompletionCatalog.OptionToolTipsByToken[$_]
            New-TasklistCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $toolTip
        }
}

function Get-TasklistFormatCompletions {
    param([string]$CurrentWord)

    $prefix = if ([string]::IsNullOrEmpty($CurrentWord)) { '' } else { $CurrentWord.Trim('"') }
    $script:TasklistCompletionCatalog.ValueHintsByOption['/FO'] |
        Where-Object { $_ -like "$prefix*" } |
        ForEach-Object {
            New-TasklistCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip "Output format $_"
        }
}

function Get-TasklistFilterExpressionCompletions {
    param([string]$CurrentWord)

    $filterWord = if ([string]::IsNullOrEmpty($CurrentWord)) { '"' } else { $CurrentWord }
    if (-not $filterWord.StartsWith('"')) {
        $filterWord = '"' + $filterWord
    }

    $expression = $filterWord.Substring(1)
    $expressionTrimmed = $expression.TrimStart()
    $endsWithWhitespace = $expression.Length -gt 0 -and [char]::IsWhiteSpace($expression[$expression.Length - 1])
    $parts = @($expressionTrimmed -split '\s+' | Where-Object { $_ })

    if ($parts.Count -eq 0) {
        return @(
            $script:TasklistCompletionCatalog.FilterNames |
                ForEach-Object {
                    $completionText = Format-TasklistFilterExpressionCompletion -Expression "$_ " -CloseQuote $false
                    New-TasklistCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip "Filter $_"
                }
        )
    }

    $partialFilterName = $parts[0]
    if ($parts.Count -eq 1 -and -not $endsWithWhitespace) {
        return @(
            $script:TasklistCompletionCatalog.FilterNames |
                Where-Object { $_ -like "$partialFilterName*" } |
                ForEach-Object {
                    $completionText = Format-TasklistFilterExpressionCompletion -Expression "$_ " -CloseQuote $false
                    New-TasklistCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip "Filter $_"
                }
        )
    }

    $filterName = Resolve-TasklistFilterName -FilterName $partialFilterName
    if (-not $filterName) {
        return @()
    }

    $operators = @($script:TasklistCompletionCatalog.FilterOperatorsByName[$filterName])
    if ($parts.Count -eq 1) {
        return @(
            $operators |
                ForEach-Object {
                    $completionText = Format-TasklistFilterExpressionCompletion -Expression "$filterName $_ " -CloseQuote $false
                    New-TasklistCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip "$filterName $_"
                }
        )
    }

    $partialOperator = $parts[1]
    if ($parts.Count -eq 2 -and -not $endsWithWhitespace) {
        return @(
            $operators |
                Where-Object { $_ -like "$partialOperator*" } |
                ForEach-Object {
                    $completionText = Format-TasklistFilterExpressionCompletion -Expression "$filterName $_ " -CloseQuote $false
                    New-TasklistCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip "$filterName $_"
                }
        )
    }

    $resolvedOperator = $null
    foreach ($operator in $operators) {
        if ($operator.Equals($partialOperator, [System.StringComparison]::OrdinalIgnoreCase)) {
            $resolvedOperator = $operator
            break
        }
    }

    if (-not $resolvedOperator) {
        return @()
    }

    $typedValue = if ($parts.Count -gt 2) {
        ($parts[2..($parts.Count - 1)] -join ' ')
    } else {
        ''
    }

    $valueItems = @(Get-TasklistFilterValueItems -FilterName $filterName -TypedValue $typedValue)
    if ($valueItems.Count -eq 0) {
        return @()
    }

    @(
        $valueItems |
            Where-Object { $_.CompletionText -like "$typedValue*" } |
            ForEach-Object {
                $completionText = Format-TasklistFilterExpressionCompletion -Expression "$filterName $resolvedOperator $($_.CompletionText)" -CloseQuote $true
                New-TasklistCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $_.ToolTip
            }
    )
}

function Get-TasklistFilterExpressionWord {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentToken,
        [bool]$HasTrailingDelimiter
    )

    if (-not $TokensBeforeCurrent -or $TokensBeforeCurrent.Count -eq 0) {
        return $null
    }

    $fiIndex = -1
    for ($index = $TokensBeforeCurrent.Count - 1; $index -ge 0; $index--) {
        if ($TokensBeforeCurrent[$index].Equals('/FI', [System.StringComparison]::OrdinalIgnoreCase)) {
            $fiIndex = $index
            break
        }
    }

    if ($fiIndex -lt 0) {
        return $null
    }

    $expressionTokensBeforeCurrent = @()
    if ($fiIndex + 1 -lt $TokensBeforeCurrent.Count) {
        $expressionTokensBeforeCurrent = @($TokensBeforeCurrent[($fiIndex + 1)..($TokensBeforeCurrent.Count - 1)])
    }

    $hasCompletedQuotedExpression = $false
    $containsFollowingSwitch = $false
    if ($expressionTokensBeforeCurrent.Count -gt 0) {
        $hasCompletedQuotedExpression =
            (Test-TasklistClosedQuotedExpression -Expression ($expressionTokensBeforeCurrent -join ' ')) -and
            ($HasTrailingDelimiter -or -not [string]::IsNullOrEmpty($CurrentToken))

        $containsFollowingSwitch = [bool]@(
            $expressionTokensBeforeCurrent |
                Where-Object { -not [string]::IsNullOrEmpty($_) -and $_.StartsWith('/') } |
                Select-Object -First 1
        )
    }

    if ($hasCompletedQuotedExpression -or $containsFollowingSwitch) {
        return $null
    }

    $expressionTokens = @($expressionTokensBeforeCurrent)
    if (-not [string]::IsNullOrEmpty($CurrentToken)) {
        $expressionTokens += $CurrentToken
    }

    $expression = $expressionTokens -join ' '
    if ($HasTrailingDelimiter) {
        $expression += ' '
    }

    $expression
}

function Complete-Tasklist {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if (-not (Test-TasklistCommandAvailable)) {
        return @()
    }

    Initialize-TasklistCompletionCatalog

    $completionLine = $commandAst.Extent.Text + (' ' * [Math]::Max(0, $cursorPosition - $commandAst.Extent.Text.Length))
    $tokenState = Get-TasklistTokenState -Line $completionLine -CursorPosition $cursorPosition
    $currentWord = $tokenState.CurrentToken
    $tokensBeforeCurrent = @($tokenState.TokensBeforeCurrent)
    $hasTrailingDelimiter = [bool]$tokenState.HasTrailingDelimiter

    if ([string]::IsNullOrEmpty($wordToComplete)) {
        $currentWord = ''
        $tokensBeforeCurrent = @($tokenState.ArgumentTokens)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('/')) {
        return @(Get-TasklistSwitchCompletions -CurrentWord $currentWord)
    }

    $filterExpressionWord = Get-TasklistFilterExpressionWord -TokensBeforeCurrent $tokensBeforeCurrent -CurrentToken $currentWord -HasTrailingDelimiter $hasTrailingDelimiter
    if ($null -ne $filterExpressionWord) {
        return @(Get-TasklistFilterExpressionCompletions -CurrentWord $filterExpressionWord)
    }

    $expectedValueOption = Get-TasklistExpectedValueOption -TokensBeforeCurrent $tokensBeforeCurrent
    switch ($expectedValueOption) {
        '/FO' {
            return @(Get-TasklistFormatCompletions -CurrentWord $currentWord)
        }
        '/S' { return @() }
        '/U' { return @() }
        '/P' { return @() }
        '/M' { return @() }
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @(Get-TasklistSwitchCompletions -CurrentWord '')
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('tasklist', 'tasklist.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Tasklist -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
