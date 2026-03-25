# xcopy tab completion for PowerShell
# Builds a help-driven switch catalog and path-aware value completion for xcopy.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name XcopyCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:XcopyCompletionCatalog = @{
        Initialized     = $false
        Options         = @()
        OptionInfoByKey = @{}
        DateSuggestions = @()
    }
}

function Test-XcopyCommandAvailable {
    [bool](Get-Command -Name xcopy.exe -ErrorAction SilentlyContinue)
}

function Invoke-XcopyHelpText {
    if (-not (Test-XcopyCommandAvailable)) {
        return @()
    }

    try {
        @(& xcopy.exe '/?' 2>$null)
    } catch {
        @()
    }
}

function New-XcopyCompletionResult {
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

function Remove-XcopyOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return $Value
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-XcopyQuotedValue {
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

function Get-XcopyStaticOptionMetadata {
    $today = Get-Date

    @{
        '/d' = @{
            Key            = '/d'
            Display        = '/D[:date]'
            CompletionText = '/D'
            Description    = 'Copies files changed on or after the specified date.'
            InlineValueKind = 'List'
            Suggestions    = @(
                $today.ToString('M-d-yyyy'),
                $today.ToString('MM-dd-yyyy'),
                (Get-Date -Date $today.AddDays(-1)).ToString('M-d-yyyy'),
                '1-1-2024',
                '01-01-2024'
            )
        }
        '/exclude' = @{
            Key             = '/exclude'
            Display         = '/EXCLUDE:file1[+file2][+file3]...'
            CompletionText  = '/EXCLUDE:'
            Description     = 'Specifies files containing exclude strings to match against absolute paths.'
            InlineValueKind = 'PathChain'
        }
        '/sparse' = @{
            Key            = '/sparse'
            Display        = '/SPARSE'
            CompletionText = '/SPARSE'
            Description    = 'Enable retaining the sparse state of files during copy.'
        }
        '/-sparse' = @{
            Key            = '/-sparse'
            Display        = '/-SPARSE'
            CompletionText = '/-SPARSE'
            Description    = 'Disable retaining the sparse state of files during copy.'
        }
    }
}

function Expand-XcopyHelpToken {
    param([string]$Token)

    $cleanToken = $Token.Trim().TrimEnd('.', ',', ';', ')')
    if ([string]::IsNullOrWhiteSpace($cleanToken)) {
        return @()
    }

    if ($cleanToken.Equals('/[-]SPARSE', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @('/SPARSE', '/-SPARSE')
    }

    @($cleanToken)
}

function ConvertFrom-XcopyHelpToken {
    param([string]$Token)

    foreach ($expandedToken in (Expand-XcopyHelpToken -Token $Token)) {
        $match = [regex]::Match($expandedToken, '^/(?<name>-?[A-Za-z?][A-Za-z0-9-]*)(?<suffix>.*)$')
        if (-not $match.Success) {
            continue
        }

        $root = '/' + $match.Groups['name'].Value
        $suffix = $match.Groups['suffix'].Value
        $completionText = if ($suffix -match '^\[:') {
            $root
        } elseif ($suffix.StartsWith(':')) {
            "${root}:"
        } else {
            $root
        }

        @{
            Key            = $root.ToLowerInvariant()
            Display        = $expandedToken
            CompletionText = $completionText
            Description    = $expandedToken
        }
    }
}

function Get-XcopyOptionLineMatch {
    param([string]$Line)

    [regex]::Match($Line, '^\s*(?<token>/\S+)\s{2,}(?<description>.+?)\s*$')
}

function Initialize-XcopyCompletionCatalog {
    if ($script:XcopyCompletionCatalog.Initialized) {
        return
    }

    $catalog = @{}
    foreach ($entry in (Get-XcopyStaticOptionMetadata).GetEnumerator()) {
        $catalog[$entry.Key] = @{} + $entry.Value
    }

    $helpLines = Invoke-XcopyHelpText
    $currentKeys = @()

    foreach ($line in $helpLines) {
        $optionMatch = Get-XcopyOptionLineMatch -Line $line
        if ($optionMatch.Success) {
            $description = $optionMatch.Groups['description'].Value.Trim()
            $currentKeys = @()

            foreach ($parsed in @(ConvertFrom-XcopyHelpToken -Token $optionMatch.Groups['token'].Value)) {
                $key = $parsed.Key
                if ($catalog.ContainsKey($key)) {
                    if (-not $catalog[$key].ContainsKey('Display')) {
                        $catalog[$key]['Display'] = $parsed.Display
                    }

                    if (-not $catalog[$key].ContainsKey('CompletionText')) {
                        $catalog[$key]['CompletionText'] = $parsed.CompletionText
                    }
                } else {
                    $catalog[$key] = @{} + $parsed
                }

                $catalog[$key]['Description'] = $description
                $currentKeys += $key
            }

            continue
        }

        if ($currentKeys.Count -gt 0 -and $line -match '^\s{2,}(?<continuation>\S.*)$') {
            $continuation = $matches['continuation'].Trim()
            foreach ($key in $currentKeys) {
                if (-not [string]::IsNullOrWhiteSpace($continuation) -and
                    -not $catalog[$key]['Description'].EndsWith($continuation, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $catalog[$key]['Description'] += ' ' + $continuation
                }
            }

            continue
        }

        $currentKeys = @()
    }

    $script:XcopyCompletionCatalog.Options = @(
        foreach ($entry in $catalog.Values) {
            [pscustomobject]$entry
        }
    ) | Sort-Object -Property CompletionText, Display -Unique

    $script:XcopyCompletionCatalog.OptionInfoByKey = @{}
    foreach ($option in $script:XcopyCompletionCatalog.Options) {
        $script:XcopyCompletionCatalog.OptionInfoByKey[$option.Key] = $option
    }

    $dateSuggestions = New-Object System.Collections.Generic.List[string]
    foreach ($option in $script:XcopyCompletionCatalog.Options) {
        if ($option.Key -eq '/d' -and $option.PSObject.Properties.Name -contains 'Suggestions') {
            foreach ($suggestion in $option.Suggestions) {
                if (-not [string]::IsNullOrWhiteSpace($suggestion)) {
                    $dateSuggestions.Add([string]$suggestion)
                }
            }
        }
    }

    $script:XcopyCompletionCatalog.DateSuggestions = @($dateSuggestions | Sort-Object -Unique)
    $script:XcopyCompletionCatalog.Initialized = $true
}

function Get-XcopyCurrentToken {
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

function Get-XcopyArgumentList {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $arguments = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $arguments += $element.Extent.Text
        }
    }

    $arguments
}

function Get-XcopyOptionKey {
    param([string]$Token)

    $cleanToken = Remove-XcopyOuterQuotes $Token
    if ([string]::IsNullOrWhiteSpace($cleanToken) -or -not $cleanToken.StartsWith('/')) {
        return $null
    }

    $match = [regex]::Match($cleanToken, '^/(?<name>-?[A-Za-z?][A-Za-z0-9-]*)')
    if ($match.Success) {
        return ('/' + $match.Groups['name'].Value).ToLowerInvariant()
    }

    $null
}

function Get-XcopyCompletionContext {
    param([string[]]$Arguments)

    $positionals = New-Object System.Collections.Generic.List[string]

    foreach ($argument in $Arguments) {
        if ([string]::IsNullOrWhiteSpace($argument)) {
            continue
        }

        if ($null -ne (Get-XcopyOptionKey -Token $argument)) {
            continue
        }

        $positionals.Add($argument)
    }

    [pscustomobject]@{
        Positionals = @($positionals)
    }
}

function Get-XcopyUniqueCompletions {
    param([System.Management.Automation.CompletionResult[]]$Results)

    $seen = @{}
    $unique = @()

    foreach ($result in $Results) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.ContainsKey($result.CompletionText)) {
            continue
        }

        $seen[$result.CompletionText] = $true
        $unique += $result
    }

    $unique
}

function Get-XcopyPathCompletions {
    param(
        [string]$InputPath,
        [string]$Kind,
        [string]$CompletionPrefix = ''
    )

    $cleanInput = Remove-XcopyOuterQuotes $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $inputIsRooted = -not [string]::IsNullOrWhiteSpace($cleanInput) -and [System.IO.Path]::IsPathRooted($cleanInput)
    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like "$leaf*" }

    if ($Kind -eq 'Directory') {
        $items = $items | Where-Object { $_.PSIsContainer }
    } elseif ($Kind -eq 'File') {
        $items = $items | Where-Object { -not $_.PSIsContainer }
    }

    foreach ($item in $items | Sort-Object -Property Name) {
        if ($inputIsRooted) {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $pathText = $item.Name
        } else {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $quotedPath = ConvertTo-XcopyQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        $completionText = $CompletionPrefix + $quotedPath
        $listItemText = $CompletionPrefix + $pathText

        New-XcopyCompletionResult `
            -CompletionText $completionText `
            -ListItemText $listItemText `
            -ResultType 'ParameterValue' `
            -ToolTip $item.FullName
    }
}

function Get-XcopyPrefixedSuggestions {
    param(
        [string]$Prefix,
        [string]$CurrentValue,
        [string[]]$Suggestions,
        [string]$ToolTip
    )

    $cleanCurrentValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    foreach ($suggestion in ($Suggestions | Sort-Object -Unique)) {
        if ($suggestion.StartsWith($cleanCurrentValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            $tokenText = $Prefix + $suggestion
            New-XcopyCompletionResult -CompletionText $tokenText -ListItemText $tokenText -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }
}

function Get-XcopyChainedPathCompletions {
    param(
        [string]$Prefix,
        [string]$CurrentValue,
        [string]$Kind
    )

    $valuePrefix = ''
    $currentSegment = $CurrentValue
    $lastPlusIndex = if ([string]::IsNullOrEmpty($CurrentValue)) { -1 } else { $CurrentValue.LastIndexOf('+') }

    if ($lastPlusIndex -ge 0) {
        $valuePrefix = $CurrentValue.Substring(0, $lastPlusIndex + 1)
        $currentSegment = $CurrentValue.Substring($lastPlusIndex + 1)
    }

    @(Get-XcopyPathCompletions -InputPath $currentSegment -Kind $Kind -CompletionPrefix ($Prefix + $valuePrefix))
}

function Get-XcopyInlineValueCompletions {
    param([string]$WordToComplete)

    Initialize-XcopyCompletionCatalog

    $cleanWord = Remove-XcopyOuterQuotes $WordToComplete
    $match = [regex]::Match($cleanWord, '^(?<root>/-?[A-Za-z?][A-Za-z0-9-]*)(?<separator>:)(?<value>.*)$')
    if (-not $match.Success) {
        return @()
    }

    $key = $match.Groups['root'].Value.ToLowerInvariant()
    if (-not $script:XcopyCompletionCatalog.OptionInfoByKey.ContainsKey($key)) {
        return @()
    }

    $optionInfo = $script:XcopyCompletionCatalog.OptionInfoByKey[$key]
    if (-not ($optionInfo.PSObject.Properties.Name -contains 'InlineValueKind')) {
        return @()
    }

    $prefix = $match.Groups['root'].Value + ':'
    $currentValue = $match.Groups['value'].Value

    switch ($optionInfo.InlineValueKind) {
        'List' {
            return @(Get-XcopyPrefixedSuggestions -Prefix $prefix -CurrentValue $currentValue -Suggestions $optionInfo.Suggestions -ToolTip $optionInfo.Description)
        }
        'PathChain' {
            return @(Get-XcopyChainedPathCompletions -Prefix $prefix -CurrentValue $currentValue -Kind 'File')
        }
    }

    @()
}

function Get-XcopyOptionCompletions {
    param([string]$WordToComplete)

    Initialize-XcopyCompletionCatalog

    $prefix = if ([string]::IsNullOrWhiteSpace($WordToComplete)) {
        ''
    } else {
        (Remove-XcopyOuterQuotes $WordToComplete).ToUpperInvariant()
    }

    foreach ($option in $script:XcopyCompletionCatalog.Options) {
        if ($option.CompletionText.ToUpperInvariant().StartsWith($prefix) -or $option.Display.ToUpperInvariant().StartsWith($prefix)) {
            New-XcopyCompletionResult `
                -CompletionText $option.CompletionText `
                -ListItemText $option.Display `
                -ResultType 'ParameterName' `
                -ToolTip $option.Description
        }
    }
}

function Complete-Xcopy {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if (-not (Test-XcopyCommandAvailable)) {
        return @()
    }

    Initialize-XcopyCompletionCatalog

    $currentWord = if ($null -eq $wordToComplete) { '' } else { $wordToComplete }
    if ([string]::IsNullOrWhiteSpace($currentWord) -and $cursorPosition -le $commandAst.Extent.EndOffset) {
        $currentWord = Get-XcopyCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and (Remove-XcopyOuterQuotes $currentWord).StartsWith('/')) {
        $inlineValueCompletions = @(Get-XcopyInlineValueCompletions -WordToComplete $currentWord)
        if ($inlineValueCompletions.Count -gt 0) {
            return $inlineValueCompletions
        }

        return @(Get-XcopyOptionCompletions -WordToComplete $currentWord)
    }

    $arguments = @(Get-XcopyArgumentList -CommandAst $commandAst -CursorPosition $cursorPosition)
    $context = Get-XcopyCompletionContext -Arguments $arguments

    if ($context.Positionals.Count -lt 2) {
        $results = @()
        $results += @(Get-XcopyPathCompletions -InputPath $currentWord -Kind 'Any')

        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            $results += @(Get-XcopyOptionCompletions -WordToComplete $currentWord)
        }

        return @(Get-XcopyUniqueCompletions -Results $results)
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-XcopyOptionCompletions -WordToComplete $currentWord)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'xcopy', 'xcopy.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Xcopy -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
