Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name SedCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SedCompletionCatalog = @{
        Initialized        = $false
        ProbedExecutable   = $false
        ExecutablePath     = $null
        HelpOptionTokens   = @()
        OptionDefinitions  = @()
        OptionTokenMap     = @{}
        OptionSuggestions  = @()
        LocalesInitialized = $false
        LocaleEntries      = @()
        ScriptHints        = @(
            [pscustomobject]@{ Text = 's///'; ToolTip = 'Substitute text' }
            [pscustomobject]@{ Text = 'p'; ToolTip = 'Print the current pattern space' }
            [pscustomobject]@{ Text = 'd'; ToolTip = 'Delete the current pattern space' }
            [pscustomobject]@{ Text = 'q'; ToolTip = 'Quit sed' }
        )
        LineLengthHints    = @('40', '70', '72', '80', '120')
        InPlaceSuffixHints = @('.bak', '.orig', '.old', '~')
    }
}

function New-SedCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip = $CompletionText,
        [string]$ListItemText = $CompletionText
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

function New-SedStringSet {
    return ,([System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal))
}

function New-SedStringObjectMap {
    return ,([System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal))
}

function Get-SedCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback = ''
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') {
        return ''
    }

    $tokenStart = 0
    $inSingleQuote = $false
    $inDoubleQuote = $false

    for ($index = 0; $index -lt $prefix.Length; $index++) {
        $character = $prefix[$index]
        if (($character -eq '`') -and $inDoubleQuote -and (($index + 1) -lt $prefix.Length)) {
            $index++
            continue
        }

        if (($character -eq "'") -and -not $inDoubleQuote) {
            if ($inSingleQuote -and (($index + 1) -lt $prefix.Length) -and ($prefix[$index + 1] -eq "'")) {
                $index++
                continue
            }

            $inSingleQuote = -not $inSingleQuote
            continue
        }

        if (($character -eq '"') -and -not $inSingleQuote) {
            $inDoubleQuote = -not $inDoubleQuote
            continue
        }

        if ([char]::IsWhiteSpace($character) -and -not $inSingleQuote -and -not $inDoubleQuote) {
            $tokenStart = $index + 1
        }
    }

    if ($tokenStart -lt $prefix.Length) {
        return $prefix.Substring($tokenStart)
    }

    $Fallback
}

function Get-SedQuoteCharacter {
    param([string]$InputText)

    if ([string]::IsNullOrEmpty($InputText)) {
        return $null
    }

    if ($InputText.StartsWith("'", [System.StringComparison]::Ordinal)) {
        return "'"
    }

    if ($InputText.StartsWith('"', [System.StringComparison]::Ordinal)) {
        return '"'
    }

    $null
}

function Remove-SedOuterQuotes {
    param([string]$InputText)

    $quoteCharacter = Get-SedQuoteCharacter -InputText $InputText
    if ($null -eq $quoteCharacter) {
        return $InputText
    }

    $unquoted = $InputText.Substring(1)
    if ($unquoted.EndsWith($quoteCharacter, [System.StringComparison]::Ordinal)) {
        $unquoted = $unquoted.Substring(0, $unquoted.Length - 1)
    }

    if ($quoteCharacter -eq "'") {
        return $unquoted.Replace("''", "'")
    }

    if ($quoteCharacter -eq '"') {
        return $unquoted.Replace('`"', '"')
    }

    $unquoted
}

function ConvertTo-SedQuotedValue {
    param(
        [string]$Value,
        [string]$QuoteCharacter
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    $effectiveQuote = $QuoteCharacter
    if ([string]::IsNullOrEmpty($effectiveQuote)) {
        $effectiveQuote = '"'
    }

    if (($effectiveQuote -eq "'") -and $Value.Contains("'")) {
        $effectiveQuote = '"'
    }

    if ($effectiveQuote -eq '"') {
        $escapedValue = $Value.Replace('`', '``').Replace('$', '`$').Replace('"', '`"')
        return '"' + $escapedValue + '"'
    }

    if ($effectiveQuote -eq "'") {
        return "'" + $Value.Replace("'", "''") + "'"
    }

    '"' + $Value + '"'
}

function Get-SedExecutablePath {
    param([string]$CommandName = 'sed')

    if ($script:SedCompletionCatalog.ProbedExecutable) {
        return $script:SedCompletionCatalog.ExecutablePath
    }

    $script:SedCompletionCatalog.ProbedExecutable = $true

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($CommandName)) {
        $leafName = Split-Path -Leaf $CommandName
        if (-not [string]::IsNullOrWhiteSpace($leafName)) {
            $candidates += $leafName
        }
    }

    $candidates += @('sed.exe', 'sed')

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($command) {
            $script:SedCompletionCatalog.ExecutablePath = $command.Source
            break
        }
    }

    $script:SedCompletionCatalog.ExecutablePath
}

function Get-SedHelpText {
    param([string]$CommandName = 'sed')

    $executablePath = Get-SedExecutablePath -CommandName $CommandName
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        return ''
    }

    try {
        ((& $executablePath --help 2>$null) -join "`n")
    } catch {
        ''
    }
}

function Get-SedHelpOptionTokens {
    param([string]$HelpText)

    if ([string]::IsNullOrWhiteSpace($HelpText)) {
        return @()
    }

    $matches = [regex]::Matches(
        $HelpText,
        '(?<!\w)(--[a-z][a-z\-]*)(?:\[[^\]]+\])?(?:=[^\s,]+)?|(?<!\w)(-[A-Za-z])(?:\[[^\]]+\])?'
    )

    $seen = New-SedStringSet
    $results = New-Object System.Collections.Generic.List[string]

    foreach ($match in $matches) {
        $token = $match.Value
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        $token = ($token -replace '(?:\[[^\]]+\])?(?:=[^\s,]+)?$', '')
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        if ($seen.Contains($token)) {
            continue
        }

        [void]$seen.Add($token)
        [void]$results.Add($token)
    }

    @($results.ToArray())
}

function Get-SedStaticOptionDefinitions {
    @(
        @{
            Canonical = '-n'
            Tokens = @('-n', '--quiet', '--silent')
            Description = 'Suppress automatic printing of pattern space'
            ValueMode = 'None'
            ValueKind = 'None'
        }
        @{
            Canonical = '--debug'
            Tokens = @('--debug')
            Description = 'Annotate program execution'
            ValueMode = 'None'
            ValueKind = 'None'
        }
        @{
            Canonical = '-e'
            Tokens = @('-e', '--expression')
            Description = 'Add the script to the commands to be executed'
            ValueMode = 'Required'
            ValueKind = 'ScriptText'
            ShortAllowsSeparate = $true
            ShortAllowsAttached = $true
            LongAllowsSeparate = $true
            LongAllowsEquals = $true
            ExplicitScriptSource = $true
        }
        @{
            Canonical = '-f'
            Tokens = @('-f', '--file')
            Description = 'Add the contents of script-file to the commands to be executed'
            ValueMode = 'Required'
            ValueKind = 'SourceFile'
            ShortAllowsSeparate = $true
            ShortAllowsAttached = $true
            LongAllowsSeparate = $true
            LongAllowsEquals = $true
            ExplicitScriptSource = $true
        }
        @{
            Canonical = '-i'
            Tokens = @('-i', '--in-place')
            Description = 'Edit files in place; optional suffix creates backup files'
            ValueMode = 'Optional'
            ValueKind = 'InPlaceSuffix'
            ShortAllowsSeparate = $false
            ShortAllowsAttached = $true
            LongAllowsSeparate = $false
            LongAllowsEquals = $true
        }
        @{
            Canonical = '-b'
            Tokens = @('-b', '--binary')
            Description = 'Open files in binary mode'
            ValueMode = 'None'
            ValueKind = 'None'
        }
        @{
            Canonical = '-C'
            Tokens = @('-C', '--ignore-locale')
            Description = 'Ignore system locale and operate in the default C locale'
            ValueMode = 'None'
            ValueKind = 'None'
        }
        @{
            Canonical = '--locale'
            Tokens = @('--locale')
            Description = 'Use the specified locale name'
            ValueMode = 'Required'
            ValueKind = 'Locale'
            LongAllowsSeparate = $true
            LongAllowsEquals = $true
        }
        @{
            Canonical = '-l'
            Tokens = @('-l', '--line-length')
            Description = 'Specify the desired line-wrap length for the l command'
            ValueMode = 'Required'
            ValueKind = 'LineLength'
            ShortAllowsSeparate = $true
            ShortAllowsAttached = $true
            LongAllowsSeparate = $true
            LongAllowsEquals = $true
        }
        @{
            Canonical = '--posix'
            Tokens = @('--posix')
            Description = 'Disable all GNU extensions'
            ValueMode = 'None'
            ValueKind = 'None'
        }
        @{
            Canonical = '-E'
            Tokens = @('-E', '-r', '--regexp-extended')
            Description = 'Use extended regular expressions in the script'
            ValueMode = 'None'
            ValueKind = 'None'
        }
        @{
            Canonical = '-s'
            Tokens = @('-s', '--separate')
            Description = 'Consider files as separate instead of one continuous stream'
            ValueMode = 'None'
            ValueKind = 'None'
        }
        @{
            Canonical = '--sandbox'
            Tokens = @('--sandbox')
            Description = 'Disable e/r/w commands in sandbox mode'
            ValueMode = 'None'
            ValueKind = 'None'
        }
        @{
            Canonical = '-u'
            Tokens = @('-u', '--unbuffered')
            Description = 'Load and flush smaller chunks of data'
            ValueMode = 'None'
            ValueKind = 'None'
        }
        @{
            Canonical = '-z'
            Tokens = @('-z', '--null-data', '--zero-terminated')
            Description = 'Separate lines by NUL characters'
            ValueMode = 'None'
            ValueKind = 'None'
        }
        @{
            Canonical = '--help'
            Tokens = @('--help')
            Description = 'Display help and exit'
            ValueMode = 'None'
            ValueKind = 'None'
        }
        @{
            Canonical = '--version'
            Tokens = @('--version')
            Description = 'Output version information and exit'
            ValueMode = 'None'
            ValueKind = 'None'
        }
    )
}

function Initialize-SedLocaleCache {
    if ($script:SedCompletionCatalog.LocalesInitialized) {
        return
    }

    $script:SedCompletionCatalog.LocalesInitialized = $true

    $seen = @{}
    $entries = New-Object System.Collections.Generic.List[object]
    $cultureTypes = [System.Globalization.CultureTypes]::SpecificCultures -bor [System.Globalization.CultureTypes]::NeutralCultures

    foreach ($culture in [System.Globalization.CultureInfo]::GetCultures($cultureTypes)) {
        $name = $culture.Name
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        foreach ($candidate in @($name, ($name -replace '-', '_'))) {
            if ([string]::IsNullOrWhiteSpace($candidate) -or ($candidate -eq 'POSIX')) {
                continue
            }

            if ($seen.ContainsKey($candidate)) {
                continue
            }

            $seen[$candidate] = $true
            [void]$entries.Add(
                [pscustomobject]@{
                    Text = $candidate
                    ToolTip = 'Locale name ({0})' -f $culture.DisplayName
                }
            )
        }
    }

    $script:SedCompletionCatalog.LocaleEntries = @($entries.ToArray() | Sort-Object Text -Unique)
}

function Initialize-SedCompletionCatalog {
    param([string]$CommandName = 'sed')

    if ($script:SedCompletionCatalog.Initialized) {
        return
    }

    $helpText = Get-SedHelpText -CommandName $CommandName
    $helpTokens = @(Get-SedHelpOptionTokens -HelpText $helpText)
    $helpTokenMap = New-SedStringSet
    foreach ($token in $helpTokens) {
        [void]$helpTokenMap.Add($token)
    }

    $supplementalTokenMap = New-SedStringSet
    [void]$supplementalTokenMap.Add('--zero-terminated')

    $definitions = New-Object System.Collections.Generic.List[hashtable]
    $tokenMap = New-SedStringObjectMap
    $suggestions = New-Object System.Collections.Generic.List[object]

    foreach ($definition in Get-SedStaticOptionDefinitions) {
        $tokens = New-Object System.Collections.Generic.List[string]
        foreach ($token in @($definition.Tokens)) {
            if (($helpTokens.Count -eq 0) -or $helpTokenMap.Contains($token) -or $supplementalTokenMap.Contains($token)) {
                [void]$tokens.Add($token)
            }
        }

        if ($tokens.Count -eq 0) {
            continue
        }

        $resolvedDefinition = @{}
        foreach ($key in $definition.Keys) {
            if ($key -eq 'Tokens') {
                $resolvedDefinition[$key] = @($tokens.ToArray())
            } else {
                $resolvedDefinition[$key] = $definition[$key]
            }
        }

        [void]$definitions.Add($resolvedDefinition)

        foreach ($token in $resolvedDefinition.Tokens) {
            $tokenMap[$token] = $resolvedDefinition
            [void]$suggestions.Add(
                [pscustomobject]@{
                    CompletionText = $token
                    ToolTip = $resolvedDefinition.Description
                }
            )
        }
    }

    $script:SedCompletionCatalog.HelpOptionTokens = $helpTokens
    $script:SedCompletionCatalog.OptionDefinitions = @($definitions.ToArray())
    $script:SedCompletionCatalog.OptionTokenMap = $tokenMap
    $script:SedCompletionCatalog.OptionSuggestions = @($suggestions.ToArray())
    $script:SedCompletionCatalog.Initialized = $true
}

function Get-SedOptionDefinition {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    if ($script:SedCompletionCatalog.OptionTokenMap.ContainsKey($Token)) {
        return $script:SedCompletionCatalog.OptionTokenMap[$Token]
    }

    $null
}

function New-SedParseState {
    @{
        EndOfOptions = $false
        PendingSeparateOption = $null
        ExplicitScriptSource = $false
        ImplicitScriptConsumed = $false
    }
}

function Update-SedStateFromValue {
    param(
        [hashtable]$State,
        [hashtable]$Definition,
        [string]$Value
    )

    if ($null -eq $Definition) {
        return
    }

    if ($Definition.ContainsKey('ExplicitScriptSource') -and $Definition.ExplicitScriptSource) {
        $State.ExplicitScriptSource = $true
    }
}

function Update-SedStateFromOption {
    param(
        [hashtable]$State,
        [hashtable]$Definition
    )

    if ($null -eq $Definition) {
        return
    }
}

function Parse-SedShortCompletedToken {
    param(
        [string]$Token,
        [hashtable]$State
    )

    if ([string]::IsNullOrWhiteSpace($Token) -or ($Token.Length -lt 2)) {
        return
    }

    $definition = Get-SedOptionDefinition -Token $Token
    if ($definition) {
        switch ($definition.ValueMode) {
            'Required' {
                if ($definition.ContainsKey('ShortAllowsSeparate') -and $definition.ShortAllowsSeparate) {
                    $State.PendingSeparateOption = $definition.Canonical
                }
            }
            'Optional' {
                Update-SedStateFromOption -State $State -Definition $definition
            }
            default {
                Update-SedStateFromOption -State $State -Definition $definition
            }
        }

        return
    }

    if ($Token.Length -le 2) {
        return
    }

    $prefix = $Token.Substring(0, 2)
    $attachedDefinition = Get-SedOptionDefinition -Token $prefix
    if (-not $attachedDefinition) {
        return
    }

    if (-not ($attachedDefinition.ContainsKey('ShortAllowsAttached') -and $attachedDefinition.ShortAllowsAttached)) {
        return
    }

    $attachedValue = $Token.Substring(2)
    switch ($attachedDefinition.ValueMode) {
        'Required' {
            Update-SedStateFromValue -State $State -Definition $attachedDefinition -Value $attachedValue
        }
        'Optional' {
            Update-SedStateFromValue -State $State -Definition $attachedDefinition -Value $attachedValue
        }
    }
}

function Update-SedParseState {
    param([string[]]$CompletedTokens)

    $state = New-SedParseState

    foreach ($token in @($CompletedTokens)) {
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        if ($state.PendingSeparateOption) {
            $pendingDefinition = Get-SedOptionDefinition -Token $state.PendingSeparateOption
            Update-SedStateFromValue -State $state -Definition $pendingDefinition -Value $token
            $state.PendingSeparateOption = $null
            continue
        }

        if (-not $state.EndOfOptions -and ($token -eq '--')) {
            $state.EndOfOptions = $true
            continue
        }

        if (-not $state.EndOfOptions) {
            if ($token.StartsWith('--', [System.StringComparison]::Ordinal)) {
                $equalsIndex = $token.IndexOf('=')
                $optionToken = if ($equalsIndex -ge 0) { $token.Substring(0, $equalsIndex) } else { $token }
                $definition = Get-SedOptionDefinition -Token $optionToken

                if ($definition) {
                    switch ($definition.ValueMode) {
                        'Required' {
                            if (($equalsIndex -ge 0) -and $definition.ContainsKey('LongAllowsEquals') -and $definition.LongAllowsEquals) {
                                $valueText = $token.Substring($equalsIndex + 1)
                                Update-SedStateFromValue -State $state -Definition $definition -Value $valueText
                            } elseif ($definition.ContainsKey('LongAllowsSeparate') -and $definition.LongAllowsSeparate) {
                                $state.PendingSeparateOption = $definition.Canonical
                            }
                        }
                        'Optional' {
                            if (($equalsIndex -ge 0) -and $definition.ContainsKey('LongAllowsEquals') -and $definition.LongAllowsEquals) {
                                $valueText = $token.Substring($equalsIndex + 1)
                                Update-SedStateFromValue -State $state -Definition $definition -Value $valueText
                            } else {
                                Update-SedStateFromOption -State $state -Definition $definition
                            }
                        }
                        default {
                            Update-SedStateFromOption -State $state -Definition $definition
                        }
                    }

                    continue
                }
            } elseif ($token.StartsWith('-', [System.StringComparison]::Ordinal) -and ($token -ne '-')) {
                Parse-SedShortCompletedToken -Token $token -State $state
                continue
            }
        }

        if (-not $state.ExplicitScriptSource -and -not $state.ImplicitScriptConsumed) {
            $state.ImplicitScriptConsumed = $true
            continue
        }
    }

    $state
}

function Get-SedPathCompletions {
    param(
        [string]$InputText,
        [string]$AttachedPrefix = '',
        [string[]]$PreferredExtensions = @()
    )

    $text = if ($null -eq $InputText) { '' } else { $InputText }
    $quoteCharacter = Get-SedQuoteCharacter -InputText $text
    $trimmedInput = Remove-SedOuterQuotes -InputText $text

    if ([string]::IsNullOrWhiteSpace($trimmedInput)) {
        $parent = '.'
        $leaf = ''
    } elseif (Test-Path -LiteralPath $trimmedInput -PathType Container) {
        $parent = $trimmedInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $trimmedInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $trimmedInput -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $quoteResult = -not [string]::IsNullOrEmpty($quoteCharacter)

    $preferredMap = @{}
    foreach ($extension in @($PreferredExtensions)) {
        if ([string]::IsNullOrWhiteSpace($extension)) {
            continue
        }

        $preferredMap[$extension] = $true
    }

    $items = @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)
    $sortedItems = @(
        $items | Sort-Object `
            @{ Expression = { -not $_.PSIsContainer } }, `
            @{ Expression = {
                    if ($_.PSIsContainer) {
                        0
                    } elseif ($preferredMap.ContainsKey($_.Extension)) {
                        0
                    } else {
                        1
                    }
                }
            }, `
            @{ Expression = { $_.Name } }
    )

    foreach ($item in $sortedItems) {
        $completionText = if ($trimmedInput -and -not [System.IO.Path]::IsPathRooted($trimmedInput)) {
            if ($parent -eq '.') {
                $item.Name
            } else {
                Join-Path -Path $parent -ChildPath $item.Name
            }
        } else {
            $item.FullName
        }

        if ($item.PSIsContainer -and -not $completionText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionText += [System.IO.Path]::DirectorySeparatorChar
        }

        if ($quoteResult -or ($completionText -match '\s')) {
            $completionText = ConvertTo-SedQuotedValue -Value $completionText -QuoteCharacter $quoteCharacter
        }

        $toolTip = if ($item.PSIsContainer) {
            'Directory: {0}' -f $item.FullName
        } else {
            $item.FullName
        }

        New-SedCompletionResult -CompletionText ($AttachedPrefix + $completionText) -ResultType 'ParameterValue' -ToolTip $toolTip
    }
}

function Get-SedSimpleValueCompletions {
    param(
        [object[]]$Values,
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    $word = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }

    foreach ($value in @($Values)) {
        $text = if ($value -is [string]) { $value } else { $value.Text }
        $toolTip = if ($value -is [string]) { $value } else { $value.ToolTip }
        if ([string]::IsNullOrWhiteSpace($word) -or $text.StartsWith($word, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-SedCompletionResult -CompletionText ($AttachedPrefix + $text) -ResultType 'ParameterValue' -ToolTip $toolTip
        }
    }
}

function Get-SedInPlaceSuffixCompletions {
    param(
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    $word = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }
    foreach ($suffix in @($script:SedCompletionCatalog.InPlaceSuffixHints)) {
        if ([string]::IsNullOrWhiteSpace($word) -or $suffix.StartsWith($word, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-SedCompletionResult -CompletionText ($AttachedPrefix + $suffix) -ResultType 'ParameterValue' -ToolTip ('Use backup suffix {0}' -f $suffix)
        }
    }
}

function Get-SedLocaleCompletions {
    param(
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    Initialize-SedLocaleCache
    Get-SedSimpleValueCompletions -Values $script:SedCompletionCatalog.LocaleEntries -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix
}

function Get-SedScriptHintCompletions {
    param(
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    Get-SedSimpleValueCompletions -Values $script:SedCompletionCatalog.ScriptHints -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix
}

function Get-SedValueCompletions {
    param(
        [hashtable]$Definition,
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    if ($null -eq $Definition) {
        return @()
    }

    switch ($Definition.ValueKind) {
        'ScriptText' {
            return @(Get-SedScriptHintCompletions -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix)
        }
        'SourceFile' {
            return @(Get-SedPathCompletions -InputText $CurrentWord -AttachedPrefix $AttachedPrefix -PreferredExtensions @('.sed'))
        }
        'Locale' {
            return @(Get-SedLocaleCompletions -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix)
        }
        'LineLength' {
            return @(Get-SedSimpleValueCompletions -Values $script:SedCompletionCatalog.LineLengthHints -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix)
        }
        'InPlaceSuffix' {
            return @(Get-SedInPlaceSuffixCompletions -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix)
        }
        default {
            return @()
        }
    }
}

function Get-SedOptionCompletions {
    param([string]$CurrentWord)

    $word = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    $seen = New-SedStringSet

    if ([string]::IsNullOrWhiteSpace($word) -or '--'.StartsWith($word, [System.StringComparison]::Ordinal)) {
        [void]$seen.Add('--')
        [void]$results.Add(
            (New-SedCompletionResult -CompletionText '--' -ResultType 'ParameterName' -ToolTip 'End option parsing')
        )
    }

    foreach ($candidate in $script:SedCompletionCatalog.OptionSuggestions) {
        if ($candidate.CompletionText.StartsWith($word, [System.StringComparison]::Ordinal)) {
            if ($seen.Contains($candidate.CompletionText)) {
                continue
            }

            [void]$seen.Add($candidate.CompletionText)
            [void]$results.Add(
                (New-SedCompletionResult -CompletionText $candidate.CompletionText -ResultType 'ParameterName' -ToolTip $candidate.ToolTip)
            )
        }
    }

    @($results.ToArray())
}

function Get-SedPositionalCompletions {
    param(
        [hashtable]$State,
        [string]$CurrentWord
    )

    if (-not $State.ExplicitScriptSource -and -not $State.ImplicitScriptConsumed) {
        return @()
    }

    @(Get-SedPathCompletions -InputText $CurrentWord)
}

function Complete-SedNative {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    [object[]]$commandElements = @($CommandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    if ($commandElements.Count -eq 0) {
        return
    }

    Initialize-SedCompletionCatalog -CommandName $commandElements[0]

    $line = $CommandAst.ToString()
    $hasTrailingSpace =
        (([string]::IsNullOrEmpty($WordToComplete) -and ($CursorPosition -ge $line.Length)) -or
        ($line -match '\s$'))
    $currentWord = if ($hasTrailingSpace) {
        ''
    } elseif ([string]::IsNullOrWhiteSpace($WordToComplete)) {
        Get-SedCurrentToken -Line $line -CursorPosition $CursorPosition -Fallback $WordToComplete
    } else {
        $WordToComplete
    }
    [object[]]$argumentTokens = if ($commandElements.Count -gt 1) {
        @($commandElements[1..($commandElements.Count - 1)])
    } else {
        @()
    }

    [object[]]$completedTokens = if ($hasTrailingSpace) {
        @($argumentTokens)
    } elseif ($argumentTokens.Count -gt 1) {
        @($argumentTokens[0..($argumentTokens.Count - 2)])
    } else {
        @()
    }

    $effectiveCurrentToken = $currentWord
    if (-not [string]::IsNullOrEmpty($currentWord) -and ($argumentTokens.Count -gt 0)) {
        $lastArgumentToken = [string]$argumentTokens[$argumentTokens.Count - 1]
        if (
            -not [string]::IsNullOrEmpty($lastArgumentToken) -and
            ($lastArgumentToken.Length -gt $currentWord.Length) -and
            $lastArgumentToken.EndsWith($currentWord, [System.StringComparison]::Ordinal)
        ) {
            $effectiveCurrentToken = $lastArgumentToken
        }
    }

    $state = Update-SedParseState -CompletedTokens $completedTokens

    if ($state.PendingSeparateOption) {
        $pendingDefinition = Get-SedOptionDefinition -Token $state.PendingSeparateOption
        return @(Get-SedValueCompletions -Definition $pendingDefinition -CurrentWord $currentWord)
    }

    if (
        -not $state.EndOfOptions -and
        [string]::IsNullOrEmpty($currentWord) -and
        -not $state.ExplicitScriptSource -and
        -not $state.ImplicitScriptConsumed
    ) {
        return @(Get-SedOptionCompletions -CurrentWord $currentWord)
    }

    if (-not $state.EndOfOptions -and $effectiveCurrentToken.StartsWith('--', [System.StringComparison]::Ordinal)) {
        $equalsIndex = $effectiveCurrentToken.IndexOf('=')
        if ($equalsIndex -ge 0) {
            $optionToken = $effectiveCurrentToken.Substring(0, $equalsIndex)
            $valueText = $effectiveCurrentToken.Substring($equalsIndex + 1)
            $definition = Get-SedOptionDefinition -Token $optionToken
            if ($definition -and $definition.ContainsKey('LongAllowsEquals') -and $definition.LongAllowsEquals) {
                return @(Get-SedValueCompletions -Definition $definition -CurrentWord $valueText -AttachedPrefix ($optionToken + '='))
            }
        }

        return @(Get-SedOptionCompletions -CurrentWord $effectiveCurrentToken)
    }

    if (-not $state.EndOfOptions -and $effectiveCurrentToken.StartsWith('-', [System.StringComparison]::Ordinal) -and ($effectiveCurrentToken -ne '-')) {
        if ($effectiveCurrentToken.Length -gt 2) {
            $shortToken = $effectiveCurrentToken.Substring(0, 2)
            $definition = Get-SedOptionDefinition -Token $shortToken
            if ($definition -and $definition.ContainsKey('ShortAllowsAttached') -and $definition.ShortAllowsAttached) {
                $attachedText = $effectiveCurrentToken.Substring(2)
                return @(Get-SedValueCompletions -Definition $definition -CurrentWord $attachedText -AttachedPrefix $shortToken)
            }
        }

        return @(Get-SedOptionCompletions -CurrentWord $effectiveCurrentToken)
    }

    if (-not $state.EndOfOptions -and ($effectiveCurrentToken -eq '-')) {
        return @(Get-SedOptionCompletions -CurrentWord $effectiveCurrentToken)
    }

    @(Get-SedPositionalCompletions -State $state -CurrentWord $currentWord)
}

Register-ArgumentCompleter -Native -CommandName @('sed', 'sed.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-SedNative -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
