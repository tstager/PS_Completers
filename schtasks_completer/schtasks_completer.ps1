# schtasks tab completion for PowerShell
# Builds completion data from schtasks built-in help.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name SchtasksCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:SchtasksCompletionCatalog = @{
        Initialized          = $false
        Subcommands          = @()
        OptionTokensByKey    = @{}
        ValueHintsByOption   = @{}
        TaskNameCache        = @()
        TaskNameCacheUpdated = $null
        ModifiersBySchedule  = @{}
    }
}

function Invoke-SchtasksHelpText {
    param([string[]]$Arguments)

    if (-not (Get-Command -Name schtasks.exe -ErrorAction SilentlyContinue)) {
        return @()
    }

    @($null | & schtasks.exe @Arguments '/?' 2>$null)
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

        # '?' is not a word character, so a \b anchor would drop the '/?' row.
        if ($line -match '^\s*(/(?:\?|[A-Za-z][A-Za-z0-9]*))(?=\s|$)') {
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

function Get-SchtasksValueOptionTable {
    # Value-bearing options and how each slot completes. '*' rows apply to every
    # subcommand; a subcommand row overrides them where the help differs
    # (/XML is a file under /Create but an [xml_type] under /Query; /I is a bare
    # switch under /Run). A $null entry marks a bare switch. Optional slots yield
    # to a following switch, as '[password]' and '[xml_type]' document.
    @{
        '*'      = @{
            '/s'     = @{ Kind = 'Placeholder'; Placeholder = '<system>'; ToolTip = 'Remote system to connect to.' }
            '/u'     = @{ Kind = 'Placeholder'; Placeholder = '<domain\user>'; ToolTip = 'User context under which schtasks.exe executes.' }
            '/p'     = @{ Kind = 'Placeholder'; Placeholder = '<password>'; ToolTip = 'Password for the /U user; prompts if omitted.'; Optional = $true }
            '/ru'    = @{ Kind = 'Hint'; ToolTip = 'Run-as user account.' }
            '/rp'    = @{ Kind = 'Placeholder'; Placeholder = '<password>'; ToolTip = 'Password for the run-as user.'; Optional = $true }
            '/tn'    = @{ Kind = 'TaskName'; Placeholder = '<path\taskname>'; ToolTip = 'Task path\name.' }
            '/tr'    = @{ Kind = 'Path'; Extensions = @(); ToolTip = 'Path and file name of the program to run.' }
            '/st'    = @{ Kind = 'Placeholder'; Placeholder = '<HH:mm>'; ToolTip = 'Start time in 24-hour HH:mm format.' }
            '/ri'    = @{ Kind = 'Placeholder'; Placeholder = '<minutes>'; ToolTip = 'Repetition interval in minutes (1 - 599940).' }
            '/et'    = @{ Kind = 'Placeholder'; Placeholder = '<HH:mm>'; ToolTip = 'End time in 24-hour HH:mm format.' }
            '/du'    = @{ Kind = 'Placeholder'; Placeholder = '<HH:mm>'; ToolTip = 'Duration to run the task in HH:mm format.' }
            '/sd'    = @{ Kind = 'Placeholder'; Placeholder = '<mm/dd/yyyy>'; ToolTip = 'First date on which the task runs.' }
            '/ed'    = @{ Kind = 'Placeholder'; Placeholder = '<mm/dd/yyyy>'; ToolTip = 'Last date on which the task runs.' }
            '/rl'    = @{ Kind = 'Hint'; ToolTip = 'Run level for the job.' }
            '/delay' = @{ Kind = 'Placeholder'; Placeholder = '<mmmm:ss>'; ToolTip = 'Delay after the trigger fires (ONSTART, ONLOGON, ONEVENT).' }
            '/fo'    = @{ Kind = 'Hint'; ToolTip = 'Output format.' }
            '/sc'    = @{ Kind = 'Hint'; ToolTip = 'Schedule frequency.' }
            '/mo'    = @{ Kind = 'Modifier'; ToolTip = 'Schedule modifier for the /SC type.' }
            '/d'     = @{ Kind = 'Hint'; ToolTip = 'Day(s) of the week (or day of the month with /SC MONTHLY).' }
            '/m'     = @{ Kind = 'Hint'; ToolTip = 'Month(s) of the year.' }
            '/ec'    = @{ Kind = 'Placeholder'; Placeholder = '<channel-name>'; ToolTip = 'Event channel for OnEvent triggers.' }
            '/i'     = @{ Kind = 'Placeholder'; Placeholder = '<idle-minutes>'; ToolTip = 'Idle time to wait before an ONIDLE task runs (1 - 999 minutes).' }
            '/xml'   = @{ Kind = 'Path'; Extensions = @('.xml'); ToolTip = 'Task XML file.' }
        }
        '/query' = @{
            '/xml' = @{ Kind = 'Hint'; ToolTip = 'ONE writes one valid XML file; omit it for the concatenation of all definitions.'; Optional = $true }
        }
        '/run'   = @{
            '/i' = $null
        }
    }
}

function Get-SchtasksValueSlot {
    param(
        [string]$Subcommand,
        [string]$Option
    )

    $table = Get-SchtasksValueOptionTable
    $optionKey = $Option.ToLowerInvariant()
    if (-not [string]::IsNullOrEmpty($Subcommand)) {
        $subcommandKey = $Subcommand.ToLowerInvariant()
        if ($table.ContainsKey($subcommandKey) -and $table[$subcommandKey].ContainsKey($optionKey)) {
            return $table[$subcommandKey][$optionKey]
        }
    }

    if ($table['*'].ContainsKey($optionKey)) {
        return $table['*'][$optionKey]
    }

    $null
}

function Get-SchtasksStaticModifierMap {
    @{
        'MINUTE'  = @('<1-1439>')
        'HOURLY'  = @('<1-23>')
        'DAILY'   = @('<1-365>')
        'WEEKLY'  = @('<1-52>')
        'MONTHLY' = @('<1-12>', 'FIRST', 'SECOND', 'THIRD', 'FOURTH', 'LAST', 'LASTDAY')
        'ONCE'    = @()
        'ONSTART' = @()
        'ONLOGON' = @()
        'ONIDLE'  = @()
        'ONEVENT' = @('<xpath-event-query>')
    }
}

function Get-SchtasksModifierMap {
    param([string[]]$Lines)

    # Parses the 'Modifiers: Valid values for the /MO switch per schedule type:' block
    # of the /Create help. Numeric ranges become a <min-max> placeholder, keyword
    # lists are offered verbatim, 'No modifiers.' yields an empty list.
    $raw = @{}
    $inBlock = $false
    $currentType = $null

    foreach ($line in $Lines) {
        if ($line -match '^\s*Modifiers:') {
            $inBlock = $true
            continue
        }

        if (-not $inBlock) {
            continue
        }

        if ($line -match '^\s*Examples?:\s*$') {
            break
        }

        if ($line -match '^\s*(?<type>[A-Z]+):\s*(?<rest>.*)$') {
            $currentType = $matches['type']
            $raw[$currentType] = [string]$matches['rest']
            continue
        }

        if ($currentType -and -not [string]::IsNullOrWhiteSpace($line)) {
            $raw[$currentType] += ' ' + $line.Trim()
        }
    }

    $map = @{}
    foreach ($type in $raw.Keys) {
        $text = $raw[$type]
        $values = New-Object System.Collections.Generic.List[string]
        if ($text -match '(\d+)\s*-\s*(\d+)') {
            $values.Add('<' + $matches[1] + '-' + $matches[2] + '>')
        }

        foreach ($keyword in @([regex]::Matches($text, '\b[A-Z]{3,}\b') | ForEach-Object { $_.Value })) {
            $values.Add($keyword)
        }

        if ($values.Count -eq 0 -and $text -match 'XPath') {
            $values.Add('<xpath-event-query>')
        }

        $map[$type] = @($values)
    }

    $map
}

function Get-SchtasksScheduleType {
    param([string[]]$TokensBeforeCurrent)

    $tokens = @($TokensBeforeCurrent)
    for ($index = 0; $index -lt ($tokens.Count - 1); $index++) {
        if ($tokens[$index] -eq '/sc') {
            return $tokens[$index + 1].Trim('"').ToUpperInvariant()
        }
    }

    $null
}

function Get-SchtasksModifierValueList {
    param([string[]]$TokensBeforeCurrent)

    $map = $script:SchtasksCompletionCatalog.ModifiersBySchedule
    if (-not $map -or $map.Count -eq 0) {
        $map = Get-SchtasksStaticModifierMap
    }

    $scheduleType = Get-SchtasksScheduleType -TokensBeforeCurrent $TokensBeforeCurrent
    if ($scheduleType -and $map.ContainsKey($scheduleType)) {
        $values = @($map[$scheduleType])
        if ($values.Count -eq 0) {
            return @([pscustomobject]@{ Value = '<no-modifier>'; ToolTip = "/SC $scheduleType takes no /MO modifier." })
        }

        return @($values | ForEach-Object { [pscustomobject]@{ Value = $_; ToolTip = "/MO value for /SC $scheduleType." } })
    }

    # /SC not typed yet (or unknown): offer the union of every schedule type's modifiers.
    $union = New-Object System.Collections.Generic.List[object]
    foreach ($type in @($map.Keys | Sort-Object)) {
        foreach ($value in @($map[$type])) {
            [void]$union.Add([pscustomobject]@{ Value = $value; ToolTip = "/MO value for /SC $type." })
        }
    }

    @($union.ToArray())
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

        if ($subcommand -eq '/Create') {
            $script:SchtasksCompletionCatalog.ModifiersBySchedule = Get-SchtasksModifierMap -Lines $helpLines
        }
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
    $alwaysQuote = [bool]($InputPath -and $InputPath.StartsWith('"'))

    # Split-Path throws on '', and a trailing separator means "list this directory".
    $parent = '.'
    $leaf = ''
    if (-not [string]::IsNullOrWhiteSpace($cleanInput)) {
        if ($cleanInput.EndsWith('\') -or $cleanInput.EndsWith('/')) {
            $parent = $cleanInput
        } else {
            $candidateParent = Split-Path -Path $cleanInput -Parent
            if (-not [string]::IsNullOrWhiteSpace($candidateParent)) {
                $parent = $candidateParent
            }

            $leaf = Split-Path -Path $cleanInput -Leaf
        }
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore | Where-Object {
        [string]::IsNullOrWhiteSpace($leaf) -or $_.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($AllowedExtensions -and $AllowedExtensions.Count -gt 0) {
        $items = @($items | Where-Object {
            $_.PSIsContainer -or ($AllowedExtensions -contains $_.Extension.ToLowerInvariant())
        })
    }

    foreach ($item in $items) {
        $candidate = if ($parent -eq '.') { $item.Name } elseif ([System.IO.Path]::IsPathRooted($cleanInput)) { $item.FullName } else { Join-Path -Path $parent -ChildPath $item.Name }
        if ($item.PSIsContainer -and -not ($candidate.EndsWith('\') -or $candidate.EndsWith('/'))) {
            $candidate += '\'
        }

        ConvertTo-SchtasksQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
    }
}

function Update-SchtasksTaskNameCache {
    $lastUpdated = $script:SchtasksCompletionCatalog.TaskNameCacheUpdated
    if ($null -ne $lastUpdated) {
        $cacheAge = (Get-Date) - $lastUpdated
        if ($cacheAge.TotalSeconds -lt 60 -and $script:SchtasksCompletionCatalog.TaskNameCache.Count -gt 0) {
            return
        }
    }

    $csvLines = @($null | & schtasks.exe /Query /FO CSV 2>$null)
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
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($cleanPrefix) + '*'

    # Task names carry a leading '\'; match the typed prefix with or without it.
    $script:SchtasksCompletionCatalog.TaskNameCache |
        Where-Object { $_ -like $pattern -or $_.TrimStart('\') -like $pattern } |
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

function Get-SchtasksValueSlotCompletionList {
    param(
        [hashtable]$Slot,
        [string]$Option,
        [string]$Subcommand,
        [string]$CurrentWord,
        [string[]]$TokensBeforeCurrent
    )

    $word = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($word.Trim('"')) + '*'

    switch ($Slot.Kind) {
        'TaskName' {
            $names = @()
            if ($Subcommand -and -not $Subcommand.Equals('/Create', [System.StringComparison]::OrdinalIgnoreCase)) {
                $names = @(Get-SchtasksTaskNameCompletions -WordToComplete $word)
            }

            if ($names.Count -gt 0) {
                return @($names | ForEach-Object { New-SchtasksCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_ })
            }

            if ([string]::IsNullOrWhiteSpace($word)) {
                return @(New-SchtasksCompletionResult -CompletionText $Slot.Placeholder -ResultType 'ParameterValue' -ToolTip $Slot.ToolTip)
            }

            return @()
        }
        'Path' {
            return @(Get-SchtasksPathCompletions -InputPath $word -AllowedExtensions $Slot.Extensions |
                ForEach-Object { New-SchtasksCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_ })
        }
        'Hint' {
            $optionKey = $Option.ToLowerInvariant()
            $hints = @()
            if ($script:SchtasksCompletionCatalog.ValueHintsByOption.ContainsKey($optionKey)) {
                $hints = @($script:SchtasksCompletionCatalog.ValueHintsByOption[$optionKey])
            }

            return @($hints |
                Where-Object { $_ -like $pattern } |
                ForEach-Object { New-SchtasksCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $Slot.ToolTip })
        }
        'Modifier' {
            return @(Get-SchtasksModifierValueList -TokensBeforeCurrent $TokensBeforeCurrent |
                Where-Object { $_.Value -like $pattern } |
                ForEach-Object { New-SchtasksCompletionResult -CompletionText $_.Value -ResultType 'ParameterValue' -ToolTip $_.ToolTip })
        }
        'Placeholder' {
            $text = if ([string]::IsNullOrWhiteSpace($word)) { $Slot.Placeholder } else { $word }
            return @(New-SchtasksCompletionResult -CompletionText $text -ResultType 'ParameterValue' -ToolTip $Slot.ToolTip)
        }
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'schtasks', 'schtasks.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Initialize-SchtasksCompletionCatalog

    $line = $commandAst.ToString()
    $currentWord = if ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        Get-SchtasksCurrentToken -Line $line -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    } else {
        $wordToComplete
    }

    # Only elements that end before the cursor are consumed, so completing inside an
    # earlier token sees the same context as typing it fresh.
    $tokensBeforeCurrent = @(
        $commandAst.CommandElements |
            Select-Object -Skip 1 |
            Where-Object { $_.Extent.EndOffset -lt $cursorPosition } |
            ForEach-Object { $_.Extent.Text }
    )

    $activeSubcommand = Get-SchtasksActiveSubcommand -Tokens $tokensBeforeCurrent -KnownSubcommands $script:SchtasksCompletionCatalog.Subcommands
    $expectedValueOption = Get-SchtasksExpectedValueOption -TokensBeforeCurrent $tokensBeforeCurrent -KnownSubcommands $script:SchtasksCompletionCatalog.Subcommands

    if ($expectedValueOption) {
        $slot = Get-SchtasksValueSlot -Subcommand $activeSubcommand -Option $expectedValueOption
        $yieldsToSwitch = $slot -and $slot.ContainsKey('Optional') -and $slot.Optional -and $currentWord.StartsWith('/')
        if ($slot -and -not $yieldsToSwitch) {
            # A value slot is terminal: never fall through to the option-name list.
            return @(Get-SchtasksValueSlotCompletionList -Slot $slot -Option $expectedValueOption -Subcommand $activeSubcommand -CurrentWord $currentWord -TokensBeforeCurrent $tokensBeforeCurrent)
        }
    }

    if (-not $activeSubcommand) {
        $topSuggestions = @($script:SchtasksCompletionCatalog.Subcommands + '/?')
        if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('/')) {
            return $topSuggestions |
                Sort-Object -Unique |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*') } |
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
            Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*') } |
            ForEach-Object {
                New-SchtasksCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
            }
    }

    @()
}
