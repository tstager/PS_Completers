# netsh tab completion for PowerShell
# Builds a lazy hierarchical catalog from netsh built-in help.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name NetshCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:NetshCompletionCatalog = @{
        Initialized      = $false
        NodesByKey       = @{}
        LoadedKeys       = @{}
        ContextPathsByKey = @{}
        GlobalOptions    = @()
        GlobalOptionMap  = @{}
    }
}

function New-NetshCompletionResult {
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

function Test-NetshCommandAvailable {
    [bool](Get-Command -Name netsh.exe -ErrorAction SilentlyContinue)
}

function Get-NetshPathKey {
    param([string[]]$PathTokens)

    $PathTokens = @($PathTokens)
    if (-not $PathTokens -or $PathTokens.Count -eq 0) {
        return '__ROOT__'
    }

    (($PathTokens | ForEach-Object { $_.ToLowerInvariant() }) -join [string][char]31)
}

function Get-NetshPathText {
    param([string[]]$PathTokens)

    (@($PathTokens) -join ' ').Trim()
}

function Get-NetshNode {
    param(
        [string[]]$PathTokens,
        [switch]$Create
    )

    $key = Get-NetshPathKey -PathTokens $PathTokens
    if (-not $script:NetshCompletionCatalog.NodesByKey.ContainsKey($key)) {
        if (-not $Create) {
            return $null
        }

        $script:NetshCompletionCatalog.NodesByKey[$key] = @{
            PathTokens        = @($PathTokens)
            NextTokens        = [ordered]@{}
            UsageSuggestions  = [ordered]@{}
            ValueHintsByTag   = @{}
        }
    }

    $script:NetshCompletionCatalog.NodesByKey[$key]
}

function Add-NetshSuggestion {
    param(
        [string[]]$PathTokens,
        [ValidateSet('NextTokens', 'UsageSuggestions')]
        [string]$CollectionName,
        [string]$CompletionText,
        [string]$ToolTip,
        [string]$ResultType = 'ParameterValue'
    )

    if ([string]::IsNullOrWhiteSpace($CompletionText)) {
        return
    }

    $node = Get-NetshNode -PathTokens $PathTokens -Create
    $collection = $node[$CollectionName]
    $key = $CompletionText.ToLowerInvariant()

    if (-not $collection.Contains($key)) {
        $collection[$key] = [pscustomobject]@{
            CompletionText = $CompletionText
            ToolTip        = $ToolTip
            ResultType     = $ResultType
        }
    }
}

function Add-NetshValueHints {
    param(
        [string[]]$PathTokens,
        [string]$Tag,
        [string[]]$Values
    )

    if ([string]::IsNullOrWhiteSpace($Tag) -or -not $Values -or $Values.Count -eq 0) {
        return
    }

    $node = Get-NetshNode -PathTokens $PathTokens -Create
    $tagKey = $Tag.ToLowerInvariant()

    if (-not $node.ValueHintsByTag.ContainsKey($tagKey)) {
        $node.ValueHintsByTag[$tagKey] = @()
    }

    $node.ValueHintsByTag[$tagKey] = @(
        $node.ValueHintsByTag[$tagKey] + $Values |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function Add-NetshContextPath {
    param([string[]]$PathTokens)

    if (-not $PathTokens -or $PathTokens.Count -eq 0) {
        return
    }

    $key = Get-NetshPathKey -PathTokens $PathTokens
    if (-not $script:NetshCompletionCatalog.ContextPathsByKey.ContainsKey($key)) {
        $script:NetshCompletionCatalog.ContextPathsByKey[$key] = @($PathTokens)
    }
}

function Invoke-NetshHelpText {
    param([string[]]$PathTokens)

    if (-not (Test-NetshCommandAvailable)) {
        return @()
    }

    try {
        if ($PathTokens -and $PathTokens.Count -gt 0) {
            @(& netsh.exe @PathTokens '/?' 2>$null)
        } else {
            @(& netsh.exe '/?' 2>$null)
        }
    } catch {
        @()
    }
}

function ConvertTo-NetshLogicalLines {
    param([string[]]$Lines)

    if (-not $Lines -or $Lines.Count -eq 0) {
        return @()
    }

    $text = ($Lines -join [Environment]::NewLine)
    foreach ($marker in @(
            'Commands in this context:',
            'The following sub-contexts are available:',
            'Usage:',
            'Parameters:',
            'Remarks:',
            'Examples:',
            'To view help for a command,'
        )) {
        $pattern = '(?<![\r\n])' + [regex]::Escape($marker)
        $text = [regex]::Replace($text, $pattern, [Environment]::NewLine + $marker)
    }

    @(
        $text -split '\r?\n' |
            ForEach-Object { $_.TrimEnd() }
    )
}

function Get-NetshHelpSections {
    param([string[]]$HelpLines)

    $sections = @{
        CommandEntries = @()
        Subcontexts    = @()
        UsageLines     = @()
        ParameterLines = @()
    }

    $logicalLines = ConvertTo-NetshLogicalLines -Lines $HelpLines
    $section = ''

    foreach ($line in $logicalLines) {
        if ($line -match '^\s*Commands in this context:\s*$') {
            $section = 'commands'
            continue
        }

        if ($line -match '^\s*The following sub-contexts are available:\s*$') {
            $section = 'subcontexts'
            continue
        }

        if ($line -match '^\s*Usage:\s*(.*)$') {
            $section = 'usage'
            $sections.UsageLines += ('Usage: ' + $matches[1].TrimEnd())
            continue
        }

        if ($line -match '^\s*Parameters:\s*$') {
            $section = 'parameters'
            continue
        }

        if ($line -match '^\s*(Remarks|Examples):\s*$' -or $line -match '^\s*To view help for a command,') {
            $section = ''
            continue
        }

        switch ($section) {
            'commands' {
                if ($line -match '^\s*(.+?)\s+-\s+(.+?)\s*$') {
                    $sections.CommandEntries += [pscustomobject]@{
                        Phrase      = $matches[1].Trim()
                        Description = $matches[2].Trim()
                    }
                }
            }
            'subcontexts' {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $sections.Subcontexts += @(
                        $line.Trim() -split '\s+' |
                            Where-Object { $_ }
                    )
                }
            }
            'usage' {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $sections.UsageLines += $line.TrimEnd()
                }
            }
            'parameters' {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $sections.ParameterLines += $line.TrimEnd()
                }
            }
        }
    }

    $sections.Subcontexts = @($sections.Subcontexts | Sort-Object -Unique)
    $sections
}

function Test-NetshContextDescription {
    param([string]$Description)

    if ([string]::IsNullOrWhiteSpace($Description)) {
        return $false
    }

    $Description -match "Changes to the [`'‘’]?netsh .+[`'‘’]? context\."
}

function Add-NetshCommandPhrase {
    param(
        [string[]]$BasePathTokens,
        [string[]]$PhraseTokens,
        [string]$Description
    )

    $BasePathTokens = @($BasePathTokens)
    $PhraseTokens = @($PhraseTokens)
    if (-not $PhraseTokens -or $PhraseTokens.Count -eq 0) {
        return
    }

    for ($index = 0; $index -lt $PhraseTokens.Count; $index++) {
        $parentPath = @($BasePathTokens)
        if ($index -gt 0) {
            $parentPath += $PhraseTokens[0..($index - 1)]
        }

        Add-NetshSuggestion -PathTokens $parentPath -CollectionName NextTokens -CompletionText $PhraseTokens[$index] -ToolTip $Description
    }
}

function Get-NetshRelativePhraseTokens {
    param(
        [string[]]$PathTokens,
        [string[]]$PhraseTokens
    )

    $PathTokens = @($PathTokens)
    $PhraseTokens = @($PhraseTokens)
    if ($PathTokens.Count -eq 0 -or $PhraseTokens.Count -eq 0) {
        return @($PhraseTokens)
    }

    $maxOverlap = [Math]::Min($PathTokens.Count, $PhraseTokens.Count - 1)
    for ($length = $maxOverlap; $length -ge 1; $length--) {
        $pathSlice = @($PathTokens[($PathTokens.Count - $length)..($PathTokens.Count - 1)])
        $phraseSlice = @($PhraseTokens[0..($length - 1)])
        if ((($pathSlice | ForEach-Object { $_.ToLowerInvariant() }) -join [char]31) -eq (($phraseSlice | ForEach-Object { $_.ToLowerInvariant() }) -join [char]31)) {
            return @($PhraseTokens[$length..($PhraseTokens.Count - 1)])
        }
    }

    @($PhraseTokens)
}

function Get-NetshUsageTags {
    param(
        [string[]]$UsageLines,
        [string[]]$ParameterLines
    )

    $tags = New-Object System.Collections.Generic.List[string]

    foreach ($line in @($UsageLines + $ParameterLines)) {
        foreach ($match in [regex]::Matches($line, '([A-Za-z][A-Za-z0-9-]*)=')) {
            $tags.Add(($match.Groups[1].Value + '='))
        }
    }

    @($tags | Sort-Object -Unique)
}

function Get-NetshUsageLiteralValues {
    param(
        [string[]]$UsageLines,
        [string[]]$PathTokens
    )

    $UsageLines = @($UsageLines)
    $PathTokens = @($PathTokens)
    if (-not $UsageLines -or $UsageLines.Count -eq 0) {
        return @()
    }

    $excluded = @{}
    foreach ($token in $PathTokens) {
        $excluded[$token.ToLowerInvariant()] = $true
    }

    foreach ($token in @('usage', 'parameters', 'remarks', 'examples')) {
        $excluded[$token] = $true
    }

    $normalizedText = ($UsageLines -join ' ')
    $normalizedText = [regex]::Replace($normalizedText, '<[^>]+>', ' ')
    $normalizedText = $normalizedText -replace '\[[^\]]*\,\.\.\.\]', ' '

    $values = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($normalizedText, '(?<![A-Za-z0-9-])([A-Za-z][A-Za-z0-9-]*(?:\|[A-Za-z][A-Za-z0-9-]*)+)(?![A-Za-z0-9-])')) {
        foreach ($value in ($match.Groups[1].Value -split '\|')) {
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $candidate = $value.Trim()
                $lookup = $candidate.ToLowerInvariant()
                if (-not $excluded.ContainsKey($lookup)) {
                    $values.Add($candidate)
                }
            }
        }
    }

    @($values | Sort-Object -Unique)
}

function Get-NetshParameterValueHints {
    param([string[]]$ParameterLines)

    $valueHints = @{}
    $currentTag = $null

    foreach ($line in $ParameterLines) {
        if ($line -match '^\s*([A-Za-z][A-Za-z0-9-]*)\s+-\s+One of the following values:\s*$') {
            $currentTag = $matches[1].ToLowerInvariant()
            if (-not $valueHints.ContainsKey($currentTag)) {
                $valueHints[$currentTag] = @()
            }
            continue
        }

        if ($line -match '^\s*([A-Za-z][A-Za-z0-9-]*)\s+-') {
            $currentTag = $null
            continue
        }

        if (-not $currentTag) {
            continue
        }

        if ($line -match '^\s*([A-Za-z][A-Za-z0-9-]*)\s*:') {
            $valueHints[$currentTag] += $matches[1]
        }
    }

    foreach ($key in @($valueHints.Keys)) {
        $valueHints[$key] = @($valueHints[$key] | Sort-Object -Unique)
    }

    $valueHints
}

function Update-NetshCatalogFromHelp {
    param(
        [string[]]$PathTokens,
        [string[]]$HelpLines
    )

    $node = Get-NetshNode -PathTokens $PathTokens -Create
    if (-not $HelpLines -or $HelpLines.Count -eq 0) {
        return
    }

    $sections = Get-NetshHelpSections -HelpLines $HelpLines
    $subcontextLookup = @{}
    foreach ($subcontext in $sections.Subcontexts) {
        $subcontextLookup[$subcontext.ToLowerInvariant()] = $true
        $contextPath = @($PathTokens + $subcontext)
        Add-NetshSuggestion -PathTokens $PathTokens -CollectionName NextTokens -CompletionText $subcontext -ToolTip ("Changes to the 'netsh {0}' context." -f (Get-NetshPathText -PathTokens $contextPath))
        Add-NetshContextPath -PathTokens $contextPath
    }

    foreach ($entry in $sections.CommandEntries) {
        $phraseTokens = @(
            Get-NetshRelativePhraseTokens -PathTokens $PathTokens -PhraseTokens @(
                $entry.Phrase -split '\s+' |
                    Where-Object { $_ }
            )
        )

        if ($phraseTokens.Count -eq 0) {
            continue
        }

        Add-NetshCommandPhrase -BasePathTokens $PathTokens -PhraseTokens $phraseTokens -Description $entry.Description

        $isContext = $false
        if ($subcontextLookup.ContainsKey($phraseTokens[-1].ToLowerInvariant())) {
            $isContext = $true
        } elseif (Test-NetshContextDescription -Description $entry.Description) {
            $isContext = $true
        }

        if ($isContext) {
            Add-NetshContextPath -PathTokens @($PathTokens + $phraseTokens)
        }
    }

    $tags = Get-NetshUsageTags -UsageLines $sections.UsageLines -ParameterLines $sections.ParameterLines
    foreach ($tag in $tags) {
        Add-NetshSuggestion -PathTokens $PathTokens -CollectionName UsageSuggestions -CompletionText $tag -ToolTip ("Parameter tag for netsh {0}." -f (Get-NetshPathText -PathTokens $PathTokens))
    }

    $literals = Get-NetshUsageLiteralValues -UsageLines $sections.UsageLines -PathTokens $PathTokens
    foreach ($literal in $literals) {
        Add-NetshSuggestion -PathTokens $PathTokens -CollectionName UsageSuggestions -CompletionText $literal -ToolTip ("Literal value accepted by netsh {0}." -f (Get-NetshPathText -PathTokens $PathTokens))
    }

    $valueHints = Get-NetshParameterValueHints -ParameterLines $sections.ParameterLines
    foreach ($tagKey in $valueHints.Keys) {
        Add-NetshValueHints -PathTokens $PathTokens -Tag $tagKey -Values $valueHints[$tagKey]
    }
}

function Ensure-NetshPathLoaded {
    param([string[]]$PathTokens)

    $key = Get-NetshPathKey -PathTokens $PathTokens
    if ($script:NetshCompletionCatalog.LoadedKeys.ContainsKey($key)) {
        return
    }

    $helpLines = Invoke-NetshHelpText -PathTokens $PathTokens
    Update-NetshCatalogFromHelp -PathTokens $PathTokens -HelpLines $helpLines
    $script:NetshCompletionCatalog.LoadedKeys[$key] = $true
}

function Initialize-NetshCompletionCatalog {
    if ($script:NetshCompletionCatalog.Initialized) {
        return
    }

    $script:NetshCompletionCatalog.GlobalOptions = @(
        [pscustomobject]@{ Token = '-a'; ExpectsValue = $true; ValueKind = 'Path';    ToolTip = 'Specifies an alias file to use.' },
        [pscustomobject]@{ Token = '-c'; ExpectsValue = $true; ValueKind = 'Context'; ToolTip = 'Changes to the specified netsh context.' },
        [pscustomobject]@{ Token = '-r'; ExpectsValue = $true; ValueKind = 'Text';    ToolTip = 'Runs the command on a remote machine.' },
        [pscustomobject]@{ Token = '-u'; ExpectsValue = $true; ValueKind = 'Text';    ToolTip = 'Specifies the user name for a remote connection.' },
        [pscustomobject]@{ Token = '-p'; ExpectsValue = $true; ValueKind = 'Password'; ToolTip = 'Specifies the password for a remote connection, or * to prompt.' },
        [pscustomobject]@{ Token = '-f'; ExpectsValue = $true; ValueKind = 'Path';    ToolTip = 'Runs commands from a script file.' },
        [pscustomobject]@{ Token = '/?'; ExpectsValue = $false; ValueKind = 'None';   ToolTip = 'Displays netsh help.' }
    )

    $optionMap = @{}
    foreach ($option in $script:NetshCompletionCatalog.GlobalOptions) {
        $optionMap[$option.Token.ToLowerInvariant()] = $option
    }

    $script:NetshCompletionCatalog.GlobalOptionMap = $optionMap
    Ensure-NetshPathLoaded -PathTokens @()
    $script:NetshCompletionCatalog.Initialized = $true
}

function ConvertTo-NetshQuotedValue {
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

function ConvertTo-NetshQuotedPath {
    param([string]$Path)

    ConvertTo-NetshQuotedValue -Value $Path
}

function Get-NetshCurrentToken {
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"|"[^"]*$|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-NetshTokensBeforeCurrent {
    param(
        [string[]]$Tokens,
        [string]$CurrentWord,
        [bool]$HasTrailingSpace
    )

    if ($HasTrailingSpace) {
        return @($Tokens)
    }

    if (-not $Tokens -or $Tokens.Count -eq 0) {
        return @()
    }

    if (-not [string]::IsNullOrEmpty($CurrentWord)) {
        for ($suffixLength = 1; $suffixLength -le $Tokens.Count; $suffixLength++) {
            $suffix = (@($Tokens | Select-Object -Last $suffixLength) -join '')
            if ($suffix -eq $CurrentWord) {
                $prefixLength = $Tokens.Count - $suffixLength
                if ($prefixLength -le 0) {
                    return @()
                }

                return @($Tokens | Select-Object -First $prefixLength)
            }
        }
    }

    if ($Tokens.Count -gt 1) {
        return @($Tokens | Select-Object -First ($Tokens.Count - 1))
    }

    @()
}

function ConvertTo-NetshContextTokens {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    @(
        $Value.Trim('"') -split '\s+' |
            Where-Object { $_ }
    )
}

function Get-NetshExpectedGlobalOption {
    param([string[]]$TokensBeforeCurrent)

    if (-not $TokensBeforeCurrent -or $TokensBeforeCurrent.Count -eq 0) {
        return $null
    }

    $lastToken = $TokensBeforeCurrent[-1].ToLowerInvariant()
    if ($script:NetshCompletionCatalog.GlobalOptionMap.ContainsKey($lastToken)) {
        $option = $script:NetshCompletionCatalog.GlobalOptionMap[$lastToken]
        if ($option.ExpectsValue) {
            return $option
        }
    }

    $null
}

function Get-NetshParsedState {
    param([string[]]$Tokens)

    $Tokens = @($Tokens)
    $contextTokens = New-Object System.Collections.Generic.List[string]
    $commandTokens = New-Object System.Collections.Generic.List[string]

    for ($index = 0; $index -lt $Tokens.Count; $index++) {
        $token = $Tokens[$index]
        $lookup = $token.ToLowerInvariant()

        if (-not $script:NetshCompletionCatalog.GlobalOptionMap.ContainsKey($lookup)) {
            $commandTokens.Add($token)
            continue
        }

        $option = $script:NetshCompletionCatalog.GlobalOptionMap[$lookup]
        if (-not $option.ExpectsValue) {
            $commandTokens.Add($token)
            continue
        }

        if ($index -ge ($Tokens.Count - 1)) {
            continue
        }

        $valueToken = $Tokens[$index + 1]
        if ($lookup -eq '-c') {
            foreach ($contextToken in (ConvertTo-NetshContextTokens -Value $valueToken)) {
                $contextTokens.Add($contextToken)
            }
        }

        $index++
    }

    [pscustomobject]@{
        ContextTokens = @($contextTokens.ToArray())
        CommandTokens = @($commandTokens.ToArray())
    }
}

function Resolve-NetshCommandPath {
    param(
        [string[]]$BasePathTokens,
        [string[]]$Tokens
    )

    $BasePathTokens = @($BasePathTokens)
    $Tokens = @($Tokens)
    $path = @($BasePathTokens)
    $consumedCount = 0

    while ($consumedCount -lt $Tokens.Count) {
        Ensure-NetshPathLoaded -PathTokens $path
        $node = Get-NetshNode -PathTokens $path
        if (-not $node -or $node.NextTokens.Count -eq 0) {
            break
        }

        $lookup = $Tokens[$consumedCount].ToLowerInvariant()
        if (-not $node.NextTokens.Contains($lookup)) {
            break
        }

        $path += $node.NextTokens[$lookup].CompletionText
        $consumedCount++
    }

    $remaining = @()
    if ($consumedCount -lt $Tokens.Count) {
        $remaining = @($Tokens[$consumedCount..($Tokens.Count - 1)])
    }

    [pscustomobject]@{
        PathTokens    = @($path)
        ConsumedCount = $consumedCount
        Remaining     = @($remaining)
    }
}

function Get-NetshFilePathCompletions {
    param([string]$InputPath)

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    $parentPath = Split-Path -Path $cleanInput -Parent
    if ([string]::IsNullOrWhiteSpace($parentPath)) {
        $parentPath = '.'
    }

    $leaf = Split-Path -Path $cleanInput -Leaf
    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }

    @(
        Get-ChildItem -Path $parentPath -Filter $filter -ErrorAction SilentlyContinue |
            ForEach-Object { ConvertTo-NetshQuotedPath -Path $_.FullName }
    )
}

function Get-NetshContextValueCompletions {
    param([string]$WordToComplete)

    $alwaysQuote = $false
    $prefix = $WordToComplete
    if ($prefix.StartsWith('"')) {
        $alwaysQuote = $true
    }

    $prefix = $prefix.Trim('"')
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($contextPath in $script:NetshCompletionCatalog.ContextPathsByKey.Values) {
        $contextPath = @($contextPath)
        $pathText = Get-NetshPathText -PathTokens $contextPath
        if ([string]::IsNullOrWhiteSpace($prefix) -or $pathText -like "$prefix*") {
            $completionText = ConvertTo-NetshQuotedValue -Value $pathText -AlwaysQuote:$alwaysQuote
            if ($contextPath.Count -gt 1) {
                $completionText = ConvertTo-NetshQuotedValue -Value $pathText -AlwaysQuote:$true
            }

            $results.Add([pscustomobject]@{
                    CompletionText = $completionText
                    ToolTip        = "Changes to the 'netsh $pathText' context."
                    ResultType     = 'ParameterValue'
                })
        }
    }

    @(
        $results |
            Sort-Object -Property CompletionText -Unique
    )
}

function Get-NetshGlobalOptionSuggestions {
    param([string]$WordToComplete)

    $results = foreach ($option in $script:NetshCompletionCatalog.GlobalOptions) {
        if ([string]::IsNullOrWhiteSpace($WordToComplete) -or $option.Token -like "$WordToComplete*") {
            [pscustomobject]@{
                CompletionText = $option.Token
                ToolTip        = $option.ToolTip
                ResultType     = 'ParameterName'
            }
        }
    }

    @($results | Sort-Object -Property CompletionText -Unique)
}

function Get-NetshCollectionSuggestions {
    param(
        [System.Collections.IDictionary]$Collection,
        [string]$WordToComplete
    )

    if (-not $Collection) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $Collection.Values) {
        if ([string]::IsNullOrWhiteSpace($WordToComplete) -or $entry.CompletionText -like "$WordToComplete*") {
            $results.Add($entry)
        }
    }

    @($results.ToArray())
}

function Get-NetshInlineTagValueSuggestions {
    param(
        [hashtable]$ValueHintsByTag,
        [string]$WordToComplete
    )

    if (-not $ValueHintsByTag -or [string]::IsNullOrWhiteSpace($WordToComplete)) {
        return @()
    }

    if ($WordToComplete -notmatch '^(?<Tag>[A-Za-z][A-Za-z0-9-]*)=(?<Value>.*)$') {
        return @()
    }

    $tagKey = $matches.Tag.ToLowerInvariant()
    $valuePrefix = $matches.Value
    if (-not $ValueHintsByTag.ContainsKey($tagKey)) {
        return @()
    }

    $results = foreach ($value in $ValueHintsByTag[$tagKey]) {
        if ([string]::IsNullOrWhiteSpace($valuePrefix) -or $value -like "$valuePrefix*") {
            [pscustomobject]@{
                CompletionText = "$($matches.Tag)=$value"
                ToolTip        = "Accepted value for $($matches.Tag)= in netsh."
                ResultType     = 'ParameterValue'
            }
        }
    }

    @($results | Sort-Object -Property CompletionText -Unique)
}

Register-ArgumentCompleter -Native -CommandName 'netsh', 'netsh.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Initialize-NetshCompletionCatalog

    $line = $commandAst.Extent.Text
    $currentWord = if ([string]::IsNullOrEmpty($wordToComplete)) { '' } else { Get-NetshCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete }
    $tokens = @($commandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text })
    $safeCursor = [Math]::Min([Math]::Max($cursorPosition, 0), $line.Length)
    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete) -or ($line.Substring(0, $safeCursor) -match '\s$')
    $tokensBeforeCurrent = Get-NetshTokensBeforeCurrent -Tokens $tokens -CurrentWord $currentWord -HasTrailingSpace:$hasTrailingSpace

    $expectedOption = Get-NetshExpectedGlobalOption -TokensBeforeCurrent $tokensBeforeCurrent
    if ($expectedOption) {
        switch ($expectedOption.ValueKind) {
            'Path' {
                foreach ($path in (Get-NetshFilePathCompletions -InputPath $currentWord)) {
                    [System.Management.Automation.CompletionResult]::new($path, $path, 'ProviderItem', $path)
                }
                return
            }
            'Context' {
                foreach ($item in (Get-NetshContextValueCompletions -WordToComplete $currentWord)) {
                    New-NetshCompletionResult -CompletionText $item.CompletionText -ResultType $item.ResultType -ToolTip $item.ToolTip
                }
                return
            }
            'Password' {
                if ([string]::IsNullOrWhiteSpace($currentWord) -or '*' -like "$currentWord*") {
                    New-NetshCompletionResult -CompletionText '*' -ResultType 'ParameterValue' -ToolTip 'Prompt for the password.'
                }
                return
            }
        }
    }

    $parsedState = Get-NetshParsedState -Tokens $tokensBeforeCurrent
    Ensure-NetshPathLoaded -PathTokens $parsedState.ContextTokens
    $resolved = Resolve-NetshCommandPath -BasePathTokens $parsedState.ContextTokens -Tokens $parsedState.CommandTokens
    Ensure-NetshPathLoaded -PathTokens $resolved.PathTokens
    $activeNode = Get-NetshNode -PathTokens $resolved.PathTokens
    if (-not $activeNode) {
        $activeNode = Get-NetshNode -PathTokens $resolved.PathTokens -Create
    }

    $resultMap = [ordered]@{}
    $candidateItems = New-Object System.Collections.Generic.List[object]

    if ($currentWord -like '-*' -or ($resolved.PathTokens.Count -eq 0 -and $resolved.Remaining.Count -eq 0)) {
        foreach ($item in (Get-NetshGlobalOptionSuggestions -WordToComplete $currentWord)) {
            $candidateItems.Add($item)
        }
    }

    if (-not ($currentWord -like '-*')) {
        foreach ($item in (Get-NetshCollectionSuggestions -Collection $activeNode.NextTokens -WordToComplete $currentWord)) {
            $candidateItems.Add($item)
        }

        foreach ($item in (Get-NetshCollectionSuggestions -Collection $activeNode.UsageSuggestions -WordToComplete $currentWord)) {
            $candidateItems.Add($item)
        }

        foreach ($item in (Get-NetshInlineTagValueSuggestions -ValueHintsByTag $activeNode.ValueHintsByTag -WordToComplete $currentWord)) {
            $candidateItems.Add($item)
        }
    }

    foreach ($item in $candidateItems) {
        $key = $item.CompletionText.ToLowerInvariant()
        if (-not $resultMap.Contains($key)) {
            $resultMap[$key] = New-NetshCompletionResult -CompletionText $item.CompletionText -ResultType $item.ResultType -ToolTip $item.ToolTip
        }
    }

    $resultMap.Values
}
