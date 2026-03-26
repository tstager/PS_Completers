# reg tab completion for PowerShell
# Builds a help-driven subcommand catalog and value-aware completion for reg.exe.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name RegCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:RegCompletionCatalog = @{
        Initialized      = $false
        CommandName      = $null
        RootKeys         = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
        RemoteRootKeys   = @('HKLM', 'HKU')
        RootLongNames    = @{
            'HKLM' = 'HKEY_LOCAL_MACHINE'
            'HKCU' = 'HKEY_CURRENT_USER'
            'HKCR' = 'HKEY_CLASSES_ROOT'
            'HKU'  = 'HKEY_USERS'
            'HKCC' = 'HKEY_CURRENT_CONFIG'
        }
        RootCanonicalByAlias = @{
            'HKLM'               = 'HKLM'
            'HKCU'               = 'HKCU'
            'HKCR'               = 'HKCR'
            'HKU'                = 'HKU'
            'HKCC'               = 'HKCC'
            'HKEY_LOCAL_MACHINE' = 'HKLM'
            'HKEY_CURRENT_USER'  = 'HKCU'
            'HKEY_CLASSES_ROOT'  = 'HKCR'
            'HKEY_USERS'         = 'HKU'
            'HKEY_CURRENT_CONFIG' = 'HKCC'
        }
        RootProviderPaths = @{
            'HKLM' = 'Registry::HKEY_LOCAL_MACHINE'
            'HKCU' = 'Registry::HKEY_CURRENT_USER'
            'HKCR' = 'Registry::HKEY_CLASSES_ROOT'
            'HKU'  = 'Registry::HKEY_USERS'
            'HKCC' = 'Registry::HKEY_CURRENT_CONFIG'
        }
        RootKeyToolTips  = @{
            'HKLM' = 'HKEY_LOCAL_MACHINE'
            'HKCU' = 'HKEY_CURRENT_USER'
            'HKCR' = 'HKEY_CLASSES_ROOT'
            'HKU'  = 'HKEY_USERS'
            'HKCC' = 'HKEY_CURRENT_CONFIG'
        }
        QueryTypes       = @('REG_SZ', 'REG_MULTI_SZ', 'REG_EXPAND_SZ', 'REG_DWORD', 'REG_QWORD', 'REG_BINARY', 'REG_NONE')
        AddTypes         = @('REG_SZ', 'REG_MULTI_SZ', 'REG_EXPAND_SZ', 'REG_DWORD', 'REG_QWORD', 'REG_BINARY', 'REG_NONE')
        SeparatorHints   = @('\0', '#', ';', ',', '|', ':')
        FlagsActions     = @('QUERY', 'SET')
        FlagsSetTokens   = @('DONT_VIRTUALIZE', 'DONT_SILENT_FAIL', 'RECURSE_FLAG')
        Subcommands      = @()
        CommandInfoByKey = @{}
    }
}

function Resolve-RegCommandName {
    if ($script:RegCompletionCatalog.CommandName) {
        return $script:RegCompletionCatalog.CommandName
    }

    $command = Get-Command -Name reg.exe, reg -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $script:RegCompletionCatalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $script:RegCompletionCatalog.CommandName
}

function Test-RegCommandAvailable {
    [bool](Resolve-RegCommandName)
}

function Invoke-RegHelpText {
    param([string[]]$Arguments)

    $commandName = Resolve-RegCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments '/?' 2>$null)
    } catch {
        @()
    }
}

function New-RegCompletionResult {
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

function New-RegLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$ToolTip
    )

    if ([string]::IsNullOrEmpty($CurrentValue)) {
        return @(
            New-RegCompletionResult -CompletionText ' ' -ListItemText '<value>' -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-RegCompletionResult -CompletionText $CurrentValue -ListItemText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Remove-RegOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return $Value
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-RegQuotedValue {
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

function Get-RegStaticCommandSpecs {
    @{
        'query' = @{
            Name        = 'QUERY'
            Description = 'Query keys, values, and data under a registry path.'
            Positionals = @('KeyPath')
            AllowRemote = $true
            AllowedRoots = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG QUERY.' }
                @{ Token = '/v'; ValueKind = 'ValueName'; Description = 'Query a specific value name under the selected key.' }
                @{ Token = '/ve'; Description = 'Query the default value name.' }
                @{ Token = '/s'; Description = 'Query recursively.' }
                @{ Token = '/f'; ValueKind = 'SearchPattern'; Description = 'Search for matching data or patterns.' }
                @{ Token = '/k'; Description = 'Search in key names only.' }
                @{ Token = '/d'; Description = 'Search in data only.' }
                @{ Token = '/c'; Description = 'Use case-sensitive matching.' }
                @{ Token = '/e'; Description = 'Return exact matches only.' }
                @{ Token = '/t'; ValueKind = 'QueryType'; Description = 'Restrict the search to a registry value type.' }
                @{ Token = '/z'; Description = 'Show numeric type information.' }
                @{ Token = '/se'; ValueKind = 'Separator'; Description = 'Specify the REG_MULTI_SZ separator character.' }
                @{ Token = '/reg:32'; Description = 'Use the 32-bit registry view.' }
                @{ Token = '/reg:64'; Description = 'Use the 64-bit registry view.' }
            )
        }
        'add' = @{
            Name        = 'ADD'
            Description = 'Add a registry key or value.'
            Positionals = @('KeyPath')
            AllowRemote = $true
            AllowedRoots = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG ADD.' }
                @{ Token = '/v'; ValueKind = 'ValueName'; Description = 'Specify the value name to add.' }
                @{ Token = '/ve'; Description = 'Use the default value name.' }
                @{ Token = '/t'; ValueKind = 'AddType'; Description = 'Specify the value data type.' }
                @{ Token = '/s'; ValueKind = 'Separator'; Description = 'Specify the separator for REG_MULTI_SZ data.' }
                @{ Token = '/d'; ValueKind = 'Data'; Description = 'Specify the data to write.' }
                @{ Token = '/f'; Description = 'Overwrite without prompting.' }
                @{ Token = '/reg:32'; Description = 'Use the 32-bit registry view.' }
                @{ Token = '/reg:64'; Description = 'Use the 64-bit registry view.' }
            )
        }
        'delete' = @{
            Name        = 'DELETE'
            Description = 'Delete a registry key or value.'
            Positionals = @('KeyPath')
            AllowRemote = $true
            AllowedRoots = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG DELETE.' }
                @{ Token = '/v'; ValueKind = 'ValueName'; Description = 'Delete a specific value name.' }
                @{ Token = '/ve'; Description = 'Delete the default value name.' }
                @{ Token = '/va'; Description = 'Delete all values under the key.' }
                @{ Token = '/f'; Description = 'Delete without prompting.' }
                @{ Token = '/reg:32'; Description = 'Use the 32-bit registry view.' }
                @{ Token = '/reg:64'; Description = 'Use the 64-bit registry view.' }
            )
        }
        'copy' = @{
            Name        = 'COPY'
            Description = 'Copy a registry key to another location.'
            Positionals = @('KeyPath', 'KeyPath')
            AllowRemote = $true
            AllowedRoots = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG COPY.' }
                @{ Token = '/s'; Description = 'Copy subkeys and values recursively.' }
                @{ Token = '/f'; Description = 'Overwrite without prompting.' }
                @{ Token = '/reg:32'; Description = 'Use the 32-bit registry view.' }
                @{ Token = '/reg:64'; Description = 'Use the 64-bit registry view.' }
            )
        }
        'save' = @{
            Name        = 'SAVE'
            Description = 'Save a registry key to a hive file.'
            Positionals = @('KeyPath', 'HiveFilePath')
            AllowRemote = $false
            AllowedRoots = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG SAVE.' }
                @{ Token = '/y'; Description = 'Overwrite the destination file without prompting.' }
                @{ Token = '/reg:32'; Description = 'Use the 32-bit registry view.' }
                @{ Token = '/reg:64'; Description = 'Use the 64-bit registry view.' }
            )
        }
        'restore' = @{
            Name        = 'RESTORE'
            Description = 'Restore a hive file into a registry key.'
            Positionals = @('KeyPath', 'HiveFilePath')
            AllowRemote = $false
            AllowedRoots = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG RESTORE.' }
                @{ Token = '/reg:32'; Description = 'Use the 32-bit registry view.' }
                @{ Token = '/reg:64'; Description = 'Use the 64-bit registry view.' }
            )
        }
        'load' = @{
            Name        = 'LOAD'
            Description = 'Load a hive file under HKLM or HKU.'
            Positionals = @('LoadKeyPath', 'HiveFilePath')
            AllowRemote = $false
            AllowedRoots = @('HKLM', 'HKU')
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG LOAD.' }
                @{ Token = '/reg:32'; Description = 'Use the 32-bit registry view.' }
                @{ Token = '/reg:64'; Description = 'Use the 64-bit registry view.' }
            )
        }
        'unload' = @{
            Name        = 'UNLOAD'
            Description = 'Unload a hive previously loaded under HKLM or HKU.'
            Positionals = @('LoadKeyPath')
            AllowRemote = $false
            AllowedRoots = @('HKLM', 'HKU')
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG UNLOAD.' }
            )
        }
        'compare' = @{
            Name        = 'COMPARE'
            Description = 'Compare two registry keys or values.'
            Positionals = @('KeyPath', 'KeyPath')
            AllowRemote = $true
            AllowedRoots = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG COMPARE.' }
                @{ Token = '/v'; ValueKind = 'ValueName'; Description = 'Compare a specific value name.' }
                @{ Token = '/ve'; Description = 'Compare the default value name.' }
                @{ Token = '/s'; Description = 'Compare recursively.' }
                @{ Token = '/oa'; Description = 'Output both differences and matches.' }
                @{ Token = '/od'; Description = 'Output only differences.' }
                @{ Token = '/os'; Description = 'Output only matches.' }
                @{ Token = '/on'; Description = 'Suppress output.' }
                @{ Token = '/reg:32'; Description = 'Use the 32-bit registry view.' }
                @{ Token = '/reg:64'; Description = 'Use the 64-bit registry view.' }
            )
        }
        'export' = @{
            Name        = 'EXPORT'
            Description = 'Export a registry key to a .reg file.'
            Positionals = @('KeyPath', 'RegFilePath')
            AllowRemote = $false
            AllowedRoots = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG EXPORT.' }
                @{ Token = '/y'; Description = 'Overwrite the destination file without prompting.' }
                @{ Token = '/reg:32'; Description = 'Use the 32-bit registry view.' }
                @{ Token = '/reg:64'; Description = 'Use the 64-bit registry view.' }
            )
        }
        'import' = @{
            Name        = 'IMPORT'
            Description = 'Import registry data from a .reg file.'
            Positionals = @('RegFilePath')
            AllowRemote = $false
            AllowedRoots = @()
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG IMPORT.' }
                @{ Token = '/reg:32'; Description = 'Use the 32-bit registry view.' }
                @{ Token = '/reg:64'; Description = 'Use the 64-bit registry view.' }
            )
        }
        'flags' = @{
            Name        = 'FLAGS'
            Description = 'Query or set virtualization flags under HKLM\Software.'
            Positionals = @('FlagsKeyPath', 'FlagsAction')
            AllowRemote = $false
            AllowedRoots = @('HKLM')
            Options     = @(
                @{ Token = '/?'; Description = 'Show help for REG FLAGS.' }
                @{ Token = '/reg:32'; Description = 'Use the 32-bit registry view.' }
                @{ Token = '/reg:64'; Description = 'Use the 64-bit registry view.' }
            )
        }
    }
}

function Get-RegOptionDescriptionMap {
    param([string[]]$Lines)

    $map = @{}
    $currentKeys = @()

    foreach ($line in $Lines) {
        if ($line -match '^\s*Examples?:\s*$') {
            break
        }

        if ($line -match '^\s*Return Code:') {
            $currentKeys = @()
            continue
        }

        $match = [regex]::Match($line, '^\s*(?<head>(?:/[A-Za-z0-9:?]+(?:\s*\|\s*)?)+)\s{2,}(?<description>\S.*)$')
        if ($match.Success) {
            $tokens = @([regex]::Matches($match.Groups['head'].Value, '/[A-Za-z0-9:?]+') | ForEach-Object { $_.Value })
            $description = $match.Groups['description'].Value.Trim()
            $currentKeys = @()

            foreach ($token in $tokens) {
                $key = $token.ToLowerInvariant()
                $map[$key] = @{
                    Token       = $token
                    Description = $description
                }
                $currentKeys += $key
            }

            continue
        }

        if ($currentKeys.Count -gt 0 -and $line -match '^\s{2,}(?<continuation>\S.*)$') {
            $continuation = $matches['continuation'].Trim()
            foreach ($key in $currentKeys) {
                if (-not $map[$key]['Description'].EndsWith($continuation, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $map[$key]['Description'] += ' ' + $continuation
                }
            }

            continue
        }

        $currentKeys = @()
    }

    $map
}

function Initialize-RegCompletionCatalog {
    if ($script:RegCompletionCatalog.Initialized) {
        return
    }

    $specs = Get-RegStaticCommandSpecs
    $commandInfoByKey = @{}
    $subcommands = @()

    foreach ($specKey in ($specs.Keys | Sort-Object)) {
        $spec = $specs[$specKey]
        $helpLines = Invoke-RegHelpText -Arguments @($spec.Name)
        $helpOptionMap = Get-RegOptionDescriptionMap -Lines $helpLines

        $options = @()
        $optionInfoByKey = @{}

        foreach ($optionSpec in $spec.Options) {
            $token = [string]$optionSpec.Token
            $lookup = $token.ToLowerInvariant()
            $entry = [ordered]@{
                Token       = $token
                Description = if ($helpOptionMap.ContainsKey($lookup)) { $helpOptionMap[$lookup]['Description'] } else { $optionSpec.Description }
            }

            if ($optionSpec.ContainsKey('ValueKind')) {
                $entry['ValueKind'] = $optionSpec.ValueKind
            }

            $option = [pscustomobject]$entry
            $options += $option
            $optionInfoByKey[$lookup] = $option
        }

        foreach ($helpEntry in $helpOptionMap.GetEnumerator()) {
            if ($optionInfoByKey.ContainsKey($helpEntry.Key)) {
                continue
            }

            $option = [pscustomobject]@{
                Token       = $helpEntry.Value.Token
                Description = $helpEntry.Value.Description
            }
            $options += $option
            $optionInfoByKey[$helpEntry.Key] = $option
        }

        $commandInfoByKey[$specKey] = [pscustomobject]@{
            Key            = $specKey
            Name           = $spec.Name
            Description    = $spec.Description
            Positionals    = @($spec.Positionals)
            AllowRemote    = [bool]$spec.AllowRemote
            AllowedRoots   = @($spec.AllowedRoots)
            Options        = @($options | Sort-Object -Property Token -Unique)
            OptionInfoByKey = $optionInfoByKey
        }
        $subcommands += [pscustomobject]@{
            Key            = $specKey
            CompletionText = $spec.Name
            Description    = $spec.Description
        }
    }

    $script:RegCompletionCatalog.CommandInfoByKey = $commandInfoByKey
    $script:RegCompletionCatalog.Subcommands = @($subcommands | Sort-Object -Property CompletionText)
    $script:RegCompletionCatalog.Initialized = $true
}

function Get-RegCurrentToken {
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-RegOptionInfo {
    param(
        [string]$SubcommandKey,
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($SubcommandKey) -or [string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $commandInfo = $script:RegCompletionCatalog.CommandInfoByKey[$SubcommandKey]
    if (-not $commandInfo) {
        return $null
    }

    $lookup = (Remove-RegOuterQuotes -Value $Token).ToLowerInvariant()
    if ($commandInfo.OptionInfoByKey.ContainsKey($lookup)) {
        return $commandInfo.OptionInfoByKey[$lookup]
    }

    $null
}

function New-RegCompletionState {
    @{
        SubcommandKey    = $null
        Positionals      = @()
        PrimaryKeyPath   = $null
        SecondaryKeyPath = $null
        PendingValueKind = $null
        PendingOptionKey = $null
        SeenOptionKeys   = @()
        FlagsAction      = $null
        FlagsSetTokens   = @()
    }
}

function Get-RegNextPositionalKind {
    param([hashtable]$State)

    if (-not $State.SubcommandKey) {
        return 'Subcommand'
    }

    if ($State.SubcommandKey -eq 'flags') {
        if ($State.Positionals.Count -eq 0) {
            return 'FlagsKeyPath'
        }

        if (-not $State.FlagsAction) {
            return 'FlagsAction'
        }

        if ($State.FlagsAction -eq 'SET') {
            return 'FlagsSetToken'
        }

        return $null
    }

    $commandInfo = $script:RegCompletionCatalog.CommandInfoByKey[$State.SubcommandKey]
    if (-not $commandInfo) {
        return $null
    }

    if ($State.Positionals.Count -lt $commandInfo.Positionals.Count) {
        return $commandInfo.Positionals[$State.Positionals.Count]
    }

    $null
}

function Add-RegPositionalValue {
    param(
        [hashtable]$State,
        [string]$Value
    )

    $nextKind = Get-RegNextPositionalKind -State $State
    if (-not $nextKind) {
        return
    }

    if ($nextKind -eq 'FlagsAction') {
        $State.FlagsAction = $Value.ToUpperInvariant()
        $State.Positionals += $Value
        return
    }

    if ($nextKind -eq 'FlagsSetToken') {
        $upperValue = $Value.ToUpperInvariant()
        if ($script:RegCompletionCatalog.FlagsSetTokens -contains $upperValue) {
            $State.FlagsSetTokens += $upperValue
        }
        return
    }

    $State.Positionals += $Value
    if (-not $State.PrimaryKeyPath -and $nextKind -like '*KeyPath') {
        $State.PrimaryKeyPath = $Value
    } elseif (-not $State.SecondaryKeyPath -and $nextKind -like '*KeyPath') {
        $State.SecondaryKeyPath = $Value
    }
}

function Get-RegCompletionState {
    param([string[]]$Tokens)

    $state = New-RegCompletionState
    foreach ($token in $Tokens) {
        $cleanToken = Remove-RegOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        $reprocessToken = $true
        while ($reprocessToken) {
            $reprocessToken = $false

            if ($state.PendingValueKind) {
                if ($state.SubcommandKey -eq 'query' -and
                    $state.PendingOptionKey -eq '/v' -and
                    $state.SeenOptionKeys -contains '/f' -and
                    $cleanToken.StartsWith('/')) {
                    $queryOption = Get-RegOptionInfo -SubcommandKey $state.SubcommandKey -Token $cleanToken
                    if ($queryOption) {
                        $state.PendingValueKind = $null
                        $state.PendingOptionKey = $null
                        $reprocessToken = $true
                        continue
                    }
                }

                $state.PendingValueKind = $null
                $state.PendingOptionKey = $null
                break
            }

            if (-not $state.SubcommandKey) {
                if ($cleanToken.StartsWith('/')) {
                    break
                }

                $lookup = $cleanToken.ToLowerInvariant()
                if ($script:RegCompletionCatalog.CommandInfoByKey.ContainsKey($lookup)) {
                    $state.SubcommandKey = $lookup
                }

                break
            }

            if ($cleanToken.StartsWith('/')) {
                $optionInfo = Get-RegOptionInfo -SubcommandKey $state.SubcommandKey -Token $cleanToken
                if ($optionInfo) {
                    $state.SeenOptionKeys += ([string]$optionInfo.Token).ToLowerInvariant()
                    if ($optionInfo.PSObject.Properties.Name -contains 'ValueKind') {
                        $state.PendingValueKind = [string]$optionInfo.ValueKind
                        $state.PendingOptionKey = [string]$optionInfo.Token
                    }
                }

                break
            }

            if ($state.SubcommandKey -eq 'flags' -and $state.FlagsAction -eq 'SET') {
                $upperToken = $cleanToken.ToUpperInvariant()
                if ($script:RegCompletionCatalog.FlagsSetTokens -contains $upperToken) {
                    $state.FlagsSetTokens += $upperToken
                    break
                }
            }

            Add-RegPositionalValue -State $state -Value $cleanToken
            break
        }
    }

    $state
}

function Get-RegHintCompletions {
    param(
        [string[]]$Hints,
        [string]$CurrentValue,
        [string]$ToolTip
    )

    $cleanCurrent = Remove-RegOuterQuotes -Value $CurrentValue
    foreach ($hint in ($Hints | Sort-Object -Unique)) {
        if ($hint.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-RegCompletionResult -CompletionText $hint -ListItemText $hint -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }
}

function Get-RegFileCompletions {
    param(
        [string]$InputPath,
        [string[]]$AllowedExtensions,
        [string]$SuggestedExtension
    )

    $cleanInput = Remove-RegOuterQuotes -Value $InputPath
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

    if ($AllowedExtensions -and $AllowedExtensions.Count -gt 0) {
        $items = $items | Where-Object {
            $_.PSIsContainer -or ($AllowedExtensions -contains $_.Extension.ToLowerInvariant())
        }
    }

    foreach ($item in ($items | Sort-Object -Property @{ Expression = 'PSIsContainer'; Descending = $true }, Name)) {
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

        $quotedPath = ConvertTo-RegQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        New-RegCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ParameterValue' -ToolTip $item.FullName
    }

    if (-not [string]::IsNullOrWhiteSpace($SuggestedExtension) -and
        -not [string]::IsNullOrWhiteSpace($cleanInput) -and
        -not ($cleanInput -match '[\\/]$') -and
        -not ($cleanInput -match '[\*\?]') -and
        -not [System.IO.Path]::HasExtension($cleanInput)) {
        $suggested = ConvertTo-RegQuotedValue -Value ($cleanInput + $SuggestedExtension) -AlwaysQuote $alwaysQuote
        New-RegCompletionResult -CompletionText $suggested -ListItemText ($cleanInput + $SuggestedExtension) -ResultType 'ParameterValue' -ToolTip 'Suggested file path'
    }
}

function Get-RegRootSuggestions {
    param(
        [string]$CurrentValue,
        [string[]]$AllowedRoots
    )

    $cleanCurrent = Remove-RegOuterQuotes -Value $CurrentValue
    $preferLongNames = $cleanCurrent.StartsWith('HKEY_', [System.StringComparison]::OrdinalIgnoreCase)
    foreach ($root in $AllowedRoots) {
        $displayRoot = if ($preferLongNames) { $script:RegCompletionCatalog.RootLongNames[$root] } else { $root }
        $candidate = $displayRoot + '\'
        if ($candidate.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase) -or
            $displayRoot.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-RegCompletionResult -CompletionText $candidate -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip $script:RegCompletionCatalog.RootKeyToolTips[$root]
        }
    }
}

function Get-RegProviderPathFromKeyPath {
    param([string]$KeyPath)

    $cleanKeyPath = Remove-RegOuterQuotes -Value $KeyPath
    if ([string]::IsNullOrWhiteSpace($cleanKeyPath) -or $cleanKeyPath.StartsWith('\\')) {
        return $null
    }

    $root, $rest = $cleanKeyPath -split '\\', 2
    $rootAlias = $root.ToUpperInvariant()
    if (-not $script:RegCompletionCatalog.RootCanonicalByAlias.ContainsKey($rootAlias)) {
        return $null
    }

    $canonicalRoot = $script:RegCompletionCatalog.RootCanonicalByAlias[$rootAlias]
    if ([string]::IsNullOrWhiteSpace($rest)) {
        return $script:RegCompletionCatalog.RootProviderPaths[$canonicalRoot]
    }

    $script:RegCompletionCatalog.RootProviderPaths[$canonicalRoot] + '\' + $rest
}

function Get-RegRegistryKeyCompletions {
    param(
        [string]$CurrentValue,
        [string[]]$AllowedRoots,
        [bool]$AllowRemote
    )

    $cleanCurrent = Remove-RegOuterQuotes -Value $CurrentValue
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentValue) -and ($CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanCurrent)) {
        return @(Get-RegRootSuggestions -CurrentValue '' -AllowedRoots $AllowedRoots)
    }

    if ($cleanCurrent.StartsWith('\\')) {
        if (-not $AllowRemote) {
            return @()
        }

        $remoteMatch = [regex]::Match($cleanCurrent, '^\\\\(?<machine>[^\\]*)(?:\\(?<rest>.*))?$')
        if (-not $remoteMatch.Success) {
            return @()
        }

        $machine = $remoteMatch.Groups['machine'].Value
        $rest = $remoteMatch.Groups['rest'].Value
        if ([string]::IsNullOrWhiteSpace($machine)) {
            return @()
        }

        if ([string]::IsNullOrWhiteSpace($rest)) {
            foreach ($root in $script:RegCompletionCatalog.RemoteRootKeys) {
                $candidate = '\\' + $machine + '\' + $root + '\'
                $quoted = ConvertTo-RegQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
                New-RegCompletionResult -CompletionText $quoted -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Remote root key ' + $root)
            }

            return
        }

        $remoteRoots = @($script:RegCompletionCatalog.RemoteRootKeys | Where-Object {
                ($_.StartsWith($rest, [System.StringComparison]::OrdinalIgnoreCase)) -or
                (($rest + '\').StartsWith($_ + '\', [System.StringComparison]::OrdinalIgnoreCase))
            })
        foreach ($root in $remoteRoots) {
            $candidate = '\\' + $machine + '\' + $root + '\'
            $quoted = ConvertTo-RegQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
            New-RegCompletionResult -CompletionText $quoted -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Remote root key ' + $root)
        }

        return
    }

    if ($cleanCurrent -notmatch '\\') {
        return @(Get-RegRootSuggestions -CurrentValue $cleanCurrent -AllowedRoots $AllowedRoots)
    }

    $segments = $cleanCurrent -split '\\', 2
    $typedRootText = $segments[0]
    $typedRoot = $typedRootText.ToUpperInvariant()
    if (-not $script:RegCompletionCatalog.RootCanonicalByAlias.ContainsKey($typedRoot)) {
        return @(Get-RegRootSuggestions -CurrentValue $cleanCurrent -AllowedRoots $AllowedRoots)
    }

    $canonicalRoot = $script:RegCompletionCatalog.RootCanonicalByAlias[$typedRoot]
    if ($AllowedRoots -notcontains $canonicalRoot) {
        return @()
    }

    $displayRoot = if ($typedRoot.StartsWith('HKEY_', [System.StringComparison]::OrdinalIgnoreCase)) {
        $script:RegCompletionCatalog.RootLongNames[$canonicalRoot]
    } else {
        $canonicalRoot
    }

    $remainder = if ($segments.Count -gt 1) { $segments[1] } else { '' }
    if ([string]::IsNullOrWhiteSpace($remainder)) {
        $providerPath = $script:RegCompletionCatalog.RootProviderPaths[$canonicalRoot]
        $leaf = ''
        $prefixPath = ''
    } elseif ($remainder.EndsWith('\')) {
        $providerPath = $script:RegCompletionCatalog.RootProviderPaths[$canonicalRoot] + '\' + $remainder.TrimEnd('\')
        $leaf = ''
        $prefixPath = $remainder.TrimEnd('\')
    } else {
        $lastSeparator = $remainder.LastIndexOf('\')
        if ($lastSeparator -lt 0) {
            $providerPath = $script:RegCompletionCatalog.RootProviderPaths[$canonicalRoot]
            $leaf = $remainder
            $prefixPath = ''
        } else {
            $prefixPath = $remainder.Substring(0, $lastSeparator)
            $leaf = $remainder.Substring($lastSeparator + 1)
            $providerPath = $script:RegCompletionCatalog.RootProviderPaths[$canonicalRoot] + '\' + $prefixPath
        }
    }

    $children = @(Get-ChildItem -LiteralPath $providerPath -ErrorAction SilentlyContinue)
    foreach ($child in ($children | Sort-Object -Property PSChildName)) {
        $childName = [string]$child.PSChildName
        if (-not $childName.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidate = if ([string]::IsNullOrWhiteSpace($prefixPath)) {
            $displayRoot + '\' + $childName + '\'
        } else {
            $displayRoot + '\' + $prefixPath + '\' + $childName + '\'
        }

        $quotedCandidate = ConvertTo-RegQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        New-RegCompletionResult -CompletionText $quotedCandidate -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Registry key ' + $candidate.TrimEnd('\'))
    }
}

function Get-RegFlagsKeyCompletions {
    param([string]$CurrentValue)

    $cleanCurrent = Remove-RegOuterQuotes -Value $CurrentValue
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentValue) -and ($CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'"))

    $flagsRoot = if ($cleanCurrent.StartsWith('HKEY_', [System.StringComparison]::OrdinalIgnoreCase)) {
        'HKEY_LOCAL_MACHINE\Software\'
    } else {
        'HKLM\Software\'
    }

    if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or
        $flagsRoot.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
        $candidate = ConvertTo-RegQuotedValue -Value $flagsRoot -AlwaysQuote $alwaysQuote
        New-RegCompletionResult -CompletionText $candidate -ListItemText $flagsRoot -ResultType 'ParameterValue' -ToolTip 'Restricted root for REG FLAGS'
    }

    if ($cleanCurrent.StartsWith('HKLM\Software', [System.StringComparison]::OrdinalIgnoreCase) -or
        $cleanCurrent.StartsWith('HKEY_LOCAL_MACHINE\Software', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @(Get-RegRegistryKeyCompletions -CurrentValue $CurrentValue -AllowedRoots @('HKLM') -AllowRemote:$false)
    }

    @()
}

function Get-RegValueNameCompletions {
    param(
        [string]$KeyPath,
        [string]$CurrentValue
    )

    if ([string]::IsNullOrWhiteSpace($KeyPath) -or $KeyPath.StartsWith('\\')) {
        return @(New-RegLiteralValueResults -CurrentValue $CurrentValue -ToolTip 'Registry value name.')
    }

    $providerPath = Get-RegProviderPathFromKeyPath -KeyPath $KeyPath
    if (-not $providerPath) {
        return @(New-RegLiteralValueResults -CurrentValue $CurrentValue -ToolTip 'Registry value name.')
    }

    $item = Get-Item -LiteralPath $providerPath -ErrorAction SilentlyContinue
    if (-not $item) {
        return @(New-RegLiteralValueResults -CurrentValue $CurrentValue -ToolTip 'Registry value name.')
    }

    $cleanCurrent = Remove-RegOuterQuotes -Value $CurrentValue
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentValue) -and ($CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'"))
    $results = @()
    foreach ($propertyName in @($item.Property | Sort-Object -Unique)) {
        if (-not $propertyName.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $completionText = ConvertTo-RegQuotedValue -Value $propertyName -AlwaysQuote $alwaysQuote
        $results += New-RegCompletionResult -CompletionText $completionText -ListItemText $propertyName -ResultType 'ParameterValue' -ToolTip ('Value name under ' + $KeyPath)
    }

    if ($results.Count -eq 0) {
        return @(New-RegLiteralValueResults -CurrentValue $CurrentValue -ToolTip 'Registry value name.')
    }

    $results
}

function Get-RegOptionCompletions {
    param(
        [string]$SubcommandKey,
        [string]$CurrentValue
    )

    $commandInfo = $script:RegCompletionCatalog.CommandInfoByKey[$SubcommandKey]
    if (-not $commandInfo) {
        return @()
    }

    $cleanCurrent = Remove-RegOuterQuotes -Value $CurrentValue
    foreach ($option in $commandInfo.Options) {
        if ($option.Token.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-RegCompletionResult -CompletionText $option.Token -ListItemText $option.Token -ResultType 'ParameterName' -ToolTip $option.Description
        }
    }
}

function Get-RegSubcommandCompletions {
    param([string]$CurrentValue)

    $cleanCurrent = Remove-RegOuterQuotes -Value $CurrentValue
    foreach ($subcommand in $script:RegCompletionCatalog.Subcommands) {
        if ($subcommand.CompletionText.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-RegCompletionResult -CompletionText $subcommand.CompletionText -ListItemText $subcommand.CompletionText -ResultType 'ParameterValue' -ToolTip $subcommand.Description
        }
    }

    if ('/?'.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
        New-RegCompletionResult -CompletionText '/?' -ListItemText '/?' -ResultType 'ParameterName' -ToolTip 'Show REG help.'
    }
}

function Invoke-RegValueCompletion {
    param(
        [string]$ValueKind,
        [string]$CurrentValue,
        [hashtable]$State
    )

    switch ($ValueKind) {
        'KeyPath' {
            $commandInfo = $script:RegCompletionCatalog.CommandInfoByKey[$State.SubcommandKey]
            return @(Get-RegRegistryKeyCompletions -CurrentValue $CurrentValue -AllowedRoots $commandInfo.AllowedRoots -AllowRemote $commandInfo.AllowRemote)
        }
        'LoadKeyPath' {
            return @(Get-RegRegistryKeyCompletions -CurrentValue $CurrentValue -AllowedRoots @('HKLM', 'HKU') -AllowRemote:$false)
        }
        'FlagsKeyPath' {
            return @(Get-RegFlagsKeyCompletions -CurrentValue $CurrentValue)
        }
        'RegFilePath' {
            return @(Get-RegFileCompletions -InputPath $CurrentValue -AllowedExtensions @('.reg') -SuggestedExtension '.reg')
        }
        'HiveFilePath' {
            return @(Get-RegFileCompletions -InputPath $CurrentValue -AllowedExtensions @('.hiv') -SuggestedExtension '.hiv')
        }
        'ValueName' {
            return @(Get-RegValueNameCompletions -KeyPath $State.PrimaryKeyPath -CurrentValue $CurrentValue)
        }
        'QueryType' {
            return @(Get-RegHintCompletions -Hints $script:RegCompletionCatalog.QueryTypes -CurrentValue $CurrentValue -ToolTip 'Registry query type.')
        }
        'AddType' {
            return @(Get-RegHintCompletions -Hints $script:RegCompletionCatalog.AddTypes -CurrentValue $CurrentValue -ToolTip 'Registry value type.')
        }
        'Separator' {
            $results = @(Get-RegHintCompletions -Hints $script:RegCompletionCatalog.SeparatorHints -CurrentValue $CurrentValue -ToolTip 'Separator character.')
            if ($results.Count -gt 0) {
                return $results
            }

            return @(New-RegLiteralValueResults -CurrentValue $CurrentValue -ToolTip 'Separator character.')
        }
        'SearchPattern' {
            $results = @()
            foreach ($hint in @(Get-RegHintCompletions -Hints @('*') -CurrentValue $CurrentValue -ToolTip 'Search pattern.')) {
                $results += $hint
            }
            $results += @(New-RegLiteralValueResults -CurrentValue $CurrentValue -ToolTip 'Search pattern.')
            return @($results)
        }
        'Data' {
            return @(New-RegLiteralValueResults -CurrentValue $CurrentValue -ToolTip 'Registry data value.')
        }
        'FlagsAction' {
            return @(Get-RegHintCompletions -Hints $script:RegCompletionCatalog.FlagsActions -CurrentValue $CurrentValue -ToolTip 'REG FLAGS action.')
        }
        'FlagsSetToken' {
            $remaining = @($script:RegCompletionCatalog.FlagsSetTokens | Where-Object { $State.FlagsSetTokens -notcontains $_ })
            return @(Get-RegHintCompletions -Hints $remaining -CurrentValue $CurrentValue -ToolTip 'REG FLAGS setting.')
        }
    }

    @()
}

function Complete-Reg {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if (-not (Test-RegCommandAvailable)) {
        return @()
    }

    Initialize-RegCompletionCatalog

    $line = $commandAst.ToString()
    $prefixLength = [Math]::Min([Math]::Max($cursorPosition, 0), $line.Length)
    $linePrefix = $line.Substring(0, $prefixLength)
    $tokens = @([regex]::Matches($linePrefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)
    $currentWord = if ($hasTrailingSpace) { '' } else { Get-RegCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete }

    [object[]]$argumentTokens = if ($tokens.Count -gt 1) {
        @($tokens[1..($tokens.Count - 1)])
    } else {
        @()
    }

    [object[]]$completedTokens = if ($hasTrailingSpace) {
        @($argumentTokens)
    } elseif ($argumentTokens.Count -gt 0) {
        @($argumentTokens[0..($argumentTokens.Count - 2)])
    } else {
        @()
    }

    $state = Get-RegCompletionState -Tokens $completedTokens

    if (-not $state.SubcommandKey) {
        return @(Get-RegSubcommandCompletions -CurrentValue $currentWord)
    }

    if ($state.PendingValueKind) {
        return @(Invoke-RegValueCompletion -ValueKind $state.PendingValueKind -CurrentValue $currentWord -State $state)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('/')) {
        return @(Get-RegOptionCompletions -SubcommandKey $state.SubcommandKey -CurrentValue $currentWord)
    }

    $nextPositionalKind = Get-RegNextPositionalKind -State $state
    if ($nextPositionalKind) {
        return @(Invoke-RegValueCompletion -ValueKind $nextPositionalKind -CurrentValue $currentWord -State $state)
    }

    if ($state.SubcommandKey -eq 'flags' -and $state.FlagsAction -eq 'SET' -and (-not [string]::IsNullOrWhiteSpace($currentWord))) {
        return @(Invoke-RegValueCompletion -ValueKind 'FlagsSetToken' -CurrentValue $currentWord -State $state)
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-RegOptionCompletions -SubcommandKey $state.SubcommandKey -CurrentValue $currentWord)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'reg', 'reg.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Reg -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
