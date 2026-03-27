# zip tab completion for PowerShell
# Builds a help-driven option catalog for Info-ZIP zip and adds path/value completion.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name ZipCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ZipCompletionCatalog = @{
        Initialized          = $false
        CommandName          = $null
        Options              = @()
        OptionInfoByKey      = @{}
        ValueOptionKeys      = @()
        PatternListOptionKeys = @()
    }
}

function Resolve-ZipCommandName {
    if ($script:ZipCompletionCatalog.CommandName) {
        return $script:ZipCompletionCatalog.CommandName
    }

    $command = Get-Command -Name zip.exe, zip -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $script:ZipCompletionCatalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $script:ZipCompletionCatalog.CommandName
}

function Test-ZipCommandAvailable {
    [bool](Resolve-ZipCommandName)
}

function Invoke-ZipHelpText {
    $commandName = Resolve-ZipCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(
            & $commandName -h 2>$null
            & $commandName -h2 2>$null
            & $commandName -so 2>$null
        )
    } catch {
        @()
    }
}

function New-ZipCompletionResult {
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

function Remove-ZipOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return $Value
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-ZipQuotedValue {
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

function Get-ZipStaticOptionMetadata {
    @(
        @{
            Key            = '-b'
            Display        = '-b path'
            CompletionText = '-b'
            Description    = 'Create or update the temporary archive in the specified directory.'
            ValueKind      = 'Directory'
        }
        @{
            Key            = '--temp-path'
            Display        = '--temp-path=path'
            CompletionText = '--temp-path'
            Description    = 'Long option form for the temporary archive directory path.'
            ValueKind      = 'Directory'
        }
        @{
            Key            = '-t'
            Display        = '-t date'
            CompletionText = '-t'
            Description    = 'Exclude files before the specified date.'
            ValueKind      = 'Date'
            Suggestions    = @()
        }
        @{
            Key            = '-tt'
            Display        = '-tt date'
            CompletionText = '-tt'
            Description    = 'Include files before the specified date.'
            ValueKind      = 'Date'
            Suggestions    = @()
        }
        @{
            Key            = '-n'
            Display        = '-n suffixes'
            CompletionText = '-n'
            Description    = 'Do not compress files with the specified suffix list.'
            ValueKind      = 'SuffixList'
            Suggestions    = @('.zip', '.7z', '.gz', '.bz2', '.jpg:.jpeg:.png:.gif', '.mp3:.mp4:.avi:.mkv')
        }
        @{
            Key            = '-P'
            Display        = '-P password'
            CompletionText = '-P'
            Description    = 'Provide the archive password on the command line.'
            ValueKind      = 'Text'
        }
        @{
            Key            = '-s'
            Display        = '-s size'
            CompletionText = '-s'
            Description    = 'Create a split archive using the specified split size.'
            ValueKind      = 'List'
            Suggestions    = @('64k', '700m', '1g', '2g', '4g', '0', '-')
        }
        @{
            Key            = '-Z'
            Display        = '-Z method'
            CompletionText = '-Z'
            Description    = 'Set the compression method.'
            ValueKind      = 'List'
            Suggestions    = @('store', 'deflate', 'bzip2')
        }
        @{
            Key            = '--out'
            Display        = '--out archive'
            CompletionText = '--out'
            Description    = 'Write the result to a new output archive.'
            ValueKind      = 'ArchivePath'
        }
        @{
            Key            = '--output-file'
            Display        = '--output-file archive'
            CompletionText = '--output-file'
            Description    = 'Write the result to a new output archive.'
            ValueKind      = 'ArchivePath'
        }
        @{
            Key            = '-lf'
            Display        = '-lf path'
            CompletionText = '-lf'
            Description    = 'Open the specified log file path.'
            ValueKind      = 'Path'
        }
        @{
            Key            = '-TT'
            Display        = '-TT command'
            CompletionText = '-TT'
            Description    = 'Use the specified command to test the archive.'
            ValueKind      = 'Text'
        }
        @{
            Key            = '-x'
            Display        = '-x pattern pattern ...'
            CompletionText = '-x'
            Description    = 'Exclude archive paths matching the supplied patterns.'
            ValueKind      = 'PatternList'
        }
        @{
            Key            = '-i'
            Display        = '-i pattern pattern ...'
            CompletionText = '-i'
            Description    = 'Include only archive paths matching the supplied patterns.'
            ValueKind      = 'PatternList'
        }
        @{
            Key            = '--exclude'
            Display        = '--exclude pattern pattern ...'
            CompletionText = '--exclude'
            Description    = 'Long option form for exclude pattern lists.'
            ValueKind      = 'PatternList'
        }
        @{
            Key            = '--include'
            Display        = '--include pattern pattern ...'
            CompletionText = '--include'
            Description    = 'Long option form for include pattern lists.'
            ValueKind      = 'PatternList'
        }
        @{
            Key            = '--copy'
            Display        = '--copy'
            CompletionText = '--copy'
            Description    = 'Copy mode: select archive entries to copy into a new archive.'
        }
    )
}

function Get-ZipCanonicalOptionKey {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    if ($Token.StartsWith('--')) {
        return 'long:' + $Token.ToLowerInvariant()
    }

    if ($Token.StartsWith('-') -and $Token.Length -gt 1) {
        $encoded = ([System.Text.Encoding]::UTF8.GetBytes($Token) | ForEach-Object { $_.ToString('X2') }) -join ''
        return 'short:' + $encoded
    }

    $null
}

function Add-ZipOptionRecord {
    param(
        [hashtable]$Catalog,
        [hashtable]$Metadata,
        [switch]$Overwrite
    )

    $rawToken = $null
    if ($Metadata.ContainsKey('Token') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.Token)) {
        $rawToken = [string]$Metadata.Token
    } elseif ($Metadata.ContainsKey('Key') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.Key)) {
        $rawToken = [string]$Metadata.Key
    }

    $key = Get-ZipCanonicalOptionKey -Token $rawToken
    if ([string]::IsNullOrWhiteSpace($key)) {
        return
    }

    if (-not $Catalog.ContainsKey($key)) {
        $Catalog[$key] = @{}
    }

    foreach ($propertyName in $Metadata.Keys) {
        $propertyValue = $Metadata[$propertyName]
        if ($null -eq $propertyValue) {
            continue
        }

        if ($Catalog[$key].ContainsKey($propertyName)) {
            if ($Overwrite) {
                $Catalog[$key][$propertyName] = $propertyValue
                continue
            }

            if ([string]::IsNullOrWhiteSpace([string]$Catalog[$key][$propertyName]) -and -not [string]::IsNullOrWhiteSpace([string]$propertyValue)) {
                $Catalog[$key][$propertyName] = $propertyValue
            }
        } else {
            $Catalog[$key][$propertyName] = $propertyValue
        }
    }

    $Catalog[$key]['Key'] = $key
    if (-not $Catalog[$key].ContainsKey('Token')) {
        $Catalog[$key]['Token'] = $rawToken
    }

    if (-not $Catalog[$key].ContainsKey('CompletionText')) {
        $Catalog[$key]['CompletionText'] = $rawToken
    }

    if (-not $Catalog[$key].ContainsKey('Display')) {
        $Catalog[$key]['Display'] = $Catalog[$key]['CompletionText']
    }
}

function Get-ZipHelpOptionMetadata {
    param([string[]]$Lines)

    $catalog = @{}

    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or -not $trimmed.StartsWith('-')) {
            continue
        }

        if ($trimmed -match '^(?<start>-\d)\s+to\s+(?<end>-\d)\b') {
            $start = [int]($matches['start'].Substring(1))
            $end = [int]($matches['end'].Substring(1))
            foreach ($number in $start..$end) {
                Add-ZipOptionRecord -Catalog $catalog -Metadata @{
                    Key            = "-$number"
                    Display        = "-$number"
                    CompletionText = "-$number"
                    Description    = $trimmed
                }
            }
        }

        foreach ($match in [regex]::Matches($trimmed, '(?<!\w)(--?[A-Za-z][A-Za-z0-9-]*|-\d|-\$|-!|-@)(?=(?:[=\s,.)]|$))')) {
            $token = $match.Groups[1].Value
            if ($token -in @('--longopt', '--longoption')) {
                continue
            }

            Add-ZipOptionRecord -Catalog $catalog -Metadata @{
                Key            = $token
                Display        = $token
                CompletionText = $token
                Description    = $trimmed
            }
        }
    }

    $catalog
}

function Get-ZipStructuredValueKind {
    param(
        [string]$ValueCode,
        [string]$Token,
        [string]$LongName,
        [string]$Description
    )

    $normalizedValueCode = if ($null -eq $ValueCode) { '' } else { $ValueCode.Trim().ToLowerInvariant() }
    $normalizedToken = if ($null -eq $Token) { '' } else { $Token.ToLowerInvariant() }
    $normalizedLongName = if ($null -eq $LongName) { '' } else { $LongName.ToLowerInvariant() }
    $normalizedDescription = if ($null -eq $Description) { '' } else { $Description.ToLowerInvariant() }

    if ($normalizedValueCode -eq 'list') {
        if ($normalizedToken -in @('-i', '-x') -or $normalizedLongName -in @('include', 'exclude')) {
            return 'PatternList'
        }

        return 'List'
    }

    if ($normalizedValueCode -ne 'req') {
        return $null
    }

    if ($normalizedToken -eq '-b' -or $normalizedLongName -eq 'temp-path' -or $normalizedDescription -match '\btemp archive\b.*\bdir\b') {
        return 'Directory'
    }

    if ($normalizedToken -in @('-t', '-tt') -or $normalizedDescription -match '\bdate\b') {
        return 'Date'
    }

    if ($normalizedToken -eq '-n' -or $normalizedDescription -match '\bsuffix') {
        return 'SuffixList'
    }

    if ($normalizedToken -eq '-o' -or $normalizedToken -eq '-O' -or $normalizedLongName -in @('output-file', 'out') -or $normalizedDescription -match '\bzipfile\b') {
        return 'ArchivePath'
    }

    if ($normalizedToken -eq '-lf' -or $normalizedLongName -eq 'logfile-path' -or $normalizedDescription -match '\bpath\b') {
        return 'Path'
    }

    if ($normalizedToken -eq '-s' -or $normalizedLongName -eq 'split-size' -or $normalizedToken -eq '-Z' -or $normalizedLongName -eq 'compression-method') {
        return 'List'
    }

    return 'Text'
}

function Get-ZipStructuredDisplay {
    param(
        [string]$Token,
        [string]$ValueCode,
        [string]$Description
    )

    $display = $Token
    $normalizedValueCode = if ($null -eq $ValueCode) { '' } else { $ValueCode.Trim().ToLowerInvariant() }
    $normalizedDescription = if ($null -eq $Description) { '' } else { $Description.ToLowerInvariant() }

    if ($normalizedValueCode -eq 'req') {
        $placeholder = 'value'
        if ($normalizedDescription -match '\bdate\b') {
            $placeholder = 'date'
        } elseif ($normalizedDescription -match '\bpassword\b') {
            $placeholder = 'password'
        } elseif ($normalizedDescription -match '\bmethod\b') {
            $placeholder = 'method'
        } elseif ($normalizedDescription -match '\bsize\b') {
            $placeholder = 'size'
        } elseif ($normalizedDescription -match '\bpath\b' -or $normalizedDescription -match '\bdir\b') {
            $placeholder = 'path'
        } elseif ($normalizedDescription -match '\bzipfile\b' -or $normalizedDescription -match '\barchive\b') {
            $placeholder = 'archive'
        } elseif ($normalizedDescription -match '\bcommand\b') {
            $placeholder = 'command'
        }

        if ($Token.StartsWith('--')) {
            return $Token + '=' + $placeholder
        }

        return $Token + ' ' + $placeholder
    }

    if ($normalizedValueCode -eq 'list') {
        return $Token + ' pattern pattern ...'
    }

    $display
}

function Get-ZipStructuredOptionMetadata {
    param([string[]]$Lines)

    $catalog = @{}
    $availableOptionsIndex = -1
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index].Trim().Equals('available options:', [System.StringComparison]::OrdinalIgnoreCase)) {
            $availableOptionsIndex = $index
            break
        }
    }

    if ($availableOptionsIndex -lt 0 -or ($availableOptionsIndex + 2) -ge $Lines.Count) {
        return $catalog
    }

    $headerLine = $Lines[$availableOptionsIndex + 1]
    $shortStart = $headerLine.IndexOf('sh')
    $longStart = $headerLine.IndexOf('long')
    $valueStart = $headerLine.IndexOf('val')
    $negStart = $headerLine.IndexOf('neg')
    $descriptionStart = $headerLine.IndexOf('description')
    if ($shortStart -lt 0 -or $longStart -lt 0 -or $valueStart -lt 0 -or $negStart -lt 0 -or $descriptionStart -lt 0) {
        return $catalog
    }

    for ($index = $availableOptionsIndex + 3; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^___BEGIN___' -or $line -match '^PS\s') {
            break
        }

        $paddedLine = $line.PadRight($descriptionStart)
        $shortName = $paddedLine.Substring($shortStart, $longStart - $shortStart).Trim()
        $longName = $paddedLine.Substring($longStart, $valueStart - $longStart).Trim()
        $valueCode = $paddedLine.Substring($valueStart, $negStart - $valueStart).Trim()
        $description = if ($paddedLine.Length -gt $descriptionStart) {
            $paddedLine.Substring($descriptionStart).Trim()
        } else {
            ''
        }

        if ([string]::IsNullOrWhiteSpace($shortName) -and [string]::IsNullOrWhiteSpace($longName)) {
            continue
        }

        foreach ($token in @(
            if (-not [string]::IsNullOrWhiteSpace($shortName) -and $shortName -ne '--') { '-' + $shortName }
            if (-not [string]::IsNullOrWhiteSpace($longName) -and $longName -ne '----') { '--' + $longName }
        )) {
            if ([string]::IsNullOrWhiteSpace($token)) {
                continue
            }

            $metadata = @{
                Key            = $token
                Token          = $token
                CompletionText = $token
                Display        = Get-ZipStructuredDisplay -Token $token -ValueCode $valueCode -Description $description
                Description    = $description
            }

            $valueKind = Get-ZipStructuredValueKind -ValueCode $valueCode -Token $token -LongName $longName -Description $description
            if (-not [string]::IsNullOrWhiteSpace($valueKind)) {
                $metadata['ValueKind'] = $valueKind
            }

            Add-ZipOptionRecord -Catalog $catalog -Metadata $metadata
        }
    }

    $catalog
}

function Initialize-ZipCompletionCatalog {
    if ($script:ZipCompletionCatalog.Initialized) {
        return
    }

    $catalog = @{}
    $helpLines = Invoke-ZipHelpText
    if ($helpLines -and $helpLines.Count -gt 0) {
        foreach ($entry in (Get-ZipHelpOptionMetadata -Lines $helpLines).Values) {
            Add-ZipOptionRecord -Catalog $catalog -Metadata $entry
        }

        foreach ($entry in (Get-ZipStructuredOptionMetadata -Lines $helpLines).Values) {
            Add-ZipOptionRecord -Catalog $catalog -Metadata $entry
        }
    }

    $today = Get-Date
    $dateSuggestions = @(
        $today.ToString('MMddyyyy')
        $today.ToString('yyyy-MM-dd')
        $today.AddDays(-1).ToString('MMddyyyy')
        $today.AddDays(-7).ToString('yyyy-MM-dd')
        '01012024'
        '2024-01-01'
    ) | Sort-Object -Unique

    foreach ($metadata in Get-ZipStaticOptionMetadata) {
        $entry = @{} + $metadata
        if ($entry.ContainsKey('ValueKind') -and $entry['ValueKind'] -eq 'Date') {
            $entry.Suggestions = $dateSuggestions
        }

        Add-ZipOptionRecord -Catalog $catalog -Metadata $entry -Overwrite
    }

    $script:ZipCompletionCatalog.Options = @(
        foreach ($entry in $catalog.Values) {
            [pscustomobject]$entry
        }
    ) | Sort-Object -CaseSensitive -Property CompletionText, Display -Unique

    $script:ZipCompletionCatalog.OptionInfoByKey = @{}
    $valueKeys = New-Object System.Collections.Generic.List[string]
    $patternKeys = New-Object System.Collections.Generic.List[string]

    foreach ($option in $script:ZipCompletionCatalog.Options) {
        $script:ZipCompletionCatalog.OptionInfoByKey[$option.Key] = $option

        if ($option.PSObject.Properties.Name -contains 'ValueKind') {
            $valueKeys.Add([string]$option.Key)
            if ($option.ValueKind -eq 'PatternList') {
                $patternKeys.Add([string]$option.Key)
            }
        }
    }

    $script:ZipCompletionCatalog.ValueOptionKeys = @($valueKeys | Sort-Object -Unique)
    $script:ZipCompletionCatalog.PatternListOptionKeys = @($patternKeys | Sort-Object -Unique)
    $script:ZipCompletionCatalog.Initialized = $true
}

function Get-ZipCurrentToken {
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

function Get-ZipCompletedArguments {
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

function Get-ZipExactOptionKey {
    param([string]$Token)

    $cleanToken = Remove-ZipOuterQuotes $Token
    if ([string]::IsNullOrWhiteSpace($cleanToken) -or $cleanToken -eq '--') {
        return $null
    }

    $lookup = Get-ZipCanonicalOptionKey -Token $cleanToken
    if ([string]::IsNullOrWhiteSpace($lookup)) {
        return $null
    }

    if ($script:ZipCompletionCatalog.OptionInfoByKey.ContainsKey($lookup)) {
        return $lookup
    }

    $null
}

function Get-ZipInlineValueMatch {
    param(
        [string]$Token,
        [bool]$TreatExactShortValueOptionAsInline = $false
    )

    $cleanToken = Remove-ZipOuterQuotes $Token
    if ([string]::IsNullOrWhiteSpace($cleanToken) -or -not $cleanToken.StartsWith('-') -or $cleanToken -eq '--' -or $cleanToken -eq '-') {
        return $null
    }

    if ($TreatExactShortValueOptionAsInline) {
        $exactOptionKey = Get-ZipExactOptionKey -Token $cleanToken
        if ($exactOptionKey -and ($script:ZipCompletionCatalog.ValueOptionKeys -contains $exactOptionKey)) {
            $exactOptionInfo = $script:ZipCompletionCatalog.OptionInfoByKey[$exactOptionKey]
            $exactTokenText = [string]$exactOptionInfo.CompletionText
            if ($exactTokenText.StartsWith('-') -and -not $exactTokenText.StartsWith('--')) {
                return [pscustomobject]@{
                    OptionKey = $exactOptionKey
                    Prefix    = $exactTokenText
                    Value     = ''
                }
            }
        }
    }

    $valueKeys = @($script:ZipCompletionCatalog.ValueOptionKeys |
        Sort-Object { $_.Length } -Descending)

    foreach ($optionKey in $valueKeys) {
        $optionInfo = $script:ZipCompletionCatalog.OptionInfoByKey[$optionKey]
        $tokenText = [string]$optionInfo.CompletionText

        $comparison = if ($tokenText.StartsWith('--')) {
            [System.StringComparison]::OrdinalIgnoreCase
        } else {
            [System.StringComparison]::Ordinal
        }

        if (-not $cleanToken.StartsWith($tokenText, $comparison)) {
            continue
        }

        if ($cleanToken.Length -eq $tokenText.Length) {
            if ($TreatExactShortValueOptionAsInline -and $tokenText.StartsWith('-') -and -not $tokenText.StartsWith('--')) {
                return [pscustomobject]@{
                    OptionKey = $optionKey
                    Prefix    = $tokenText
                    Value     = ''
                }
            }

            continue
        }

        if ($tokenText.StartsWith('--')) {
            if ($cleanToken.Length -le $tokenText.Length -or $cleanToken[$tokenText.Length] -ne '=') {
                continue
            }

            return [pscustomobject]@{
                OptionKey = $optionKey
                Prefix    = $tokenText + '='
                Value     = $cleanToken.Substring($tokenText.Length + 1)
            }
        }

        $prefix = $tokenText
        $value = $cleanToken.Substring($tokenText.Length)
        if ($value.StartsWith('=')) {
            $prefix += '='
            $value = $value.Substring(1)
        }

        return [pscustomobject]@{
            OptionKey = $optionKey
            Prefix    = $prefix
            Value     = $value
        }
    }

    $null
}

function Test-ZipLooksLikeOption {
    param([string]$Token)

    $cleanToken = Remove-ZipOuterQuotes $Token
    -not [string]::IsNullOrWhiteSpace($cleanToken) -and $cleanToken.StartsWith('-') -and $cleanToken -ne '-' -and $cleanToken -ne '--'
}

function Test-ZipShouldCompleteOptions {
    param([string]$Token)

    $cleanToken = Remove-ZipOuterQuotes $Token
    -not [string]::IsNullOrWhiteSpace($cleanToken) -and $cleanToken.StartsWith('-')
}

function Get-ZipCompletionContext {
    param([string[]]$Arguments)

    $positionals = New-Object System.Collections.Generic.List[string]
    $expectingValueOption = $null
    $patternListOption = $null
    $literalMode = $false

    foreach ($argument in $Arguments) {
        $cleanArgument = Remove-ZipOuterQuotes $argument
        $reprocessArgument = $true

        while ($reprocessArgument) {
            $reprocessArgument = $false

            if ($literalMode) {
                $positionals.Add($argument)
                break
            }

            if ($null -ne $expectingValueOption) {
                $expectingValueOption = $null
                break
            }

            if ($null -ne $patternListOption) {
                if ($cleanArgument -eq '@') {
                    $patternListOption = $null
                    break
                }

                if ($cleanArgument -eq '--') {
                    $patternListOption = $null
                    $literalMode = $true
                    break
                }

                if (Test-ZipLooksLikeOption -Token $cleanArgument) {
                    $patternListOption = $null
                    $reprocessArgument = $true
                    continue
                }

                break
            }

            if ($cleanArgument -eq '--') {
                $literalMode = $true
                break
            }

            $inlineValueMatch = Get-ZipInlineValueMatch -Token $cleanArgument
            if ($inlineValueMatch) {
                if ($script:ZipCompletionCatalog.PatternListOptionKeys -contains $inlineValueMatch.OptionKey) {
                    $patternListOption = $inlineValueMatch.OptionKey
                }

                break
            }

            $exactOptionKey = Get-ZipExactOptionKey -Token $cleanArgument
            if ($exactOptionKey) {
                $optionInfo = $script:ZipCompletionCatalog.OptionInfoByKey[$exactOptionKey]
                if (($optionInfo.PSObject.Properties.Name -contains 'ValueKind') -and $optionInfo.ValueKind -eq 'PatternList') {
                    $patternListOption = $exactOptionKey
                } elseif ($script:ZipCompletionCatalog.ValueOptionKeys -contains $exactOptionKey) {
                    $expectingValueOption = $exactOptionKey
                }

                break
            }

            $positionals.Add($argument)
            break
        }
    }

    [pscustomobject]@{
        Positionals          = @($positionals)
        ExpectingValueOption = $expectingValueOption
        PatternListOption    = $patternListOption
        LiteralMode          = $literalMode
    }
}

function Get-ZipUniqueCompletions {
    param([System.Management.Automation.CompletionResult[]]$Results)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $unique = @()

    foreach ($result in $Results) {
        if ($null -eq $result) {
            continue
        }

        if (-not $seen.Add($result.CompletionText)) {
            continue
        }
        $unique += $result
    }

    $unique
}

function Get-ZipPathCompletions {
    param(
        [string]$InputPath,
        [string]$Kind = 'Any',
        [string]$CompletionPrefix = ''
    )

    $cleanInput = Remove-ZipOuterQuotes $InputPath
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

        $quotedPath = ConvertTo-ZipQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        $completionText = $CompletionPrefix + $quotedPath
        $listItemText = $CompletionPrefix + $pathText

        New-ZipCompletionResult `
            -CompletionText $completionText `
            -ListItemText $listItemText `
            -ResultType 'ParameterValue' `
            -ToolTip $item.FullName
    }
}

function Get-ZipArchivePathCompletions {
    param(
        [string]$InputPath,
        [string]$CompletionPrefix = ''
    )

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    foreach ($result in @(Get-ZipPathCompletions -InputPath $InputPath -Kind 'Any' -CompletionPrefix $CompletionPrefix)) {
        $results.Add($result)
    }

    $cleanInput = Remove-ZipOuterQuotes $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))
    if (-not [string]::IsNullOrWhiteSpace($cleanInput) -and
        -not ($cleanInput -match '[\\/]$') -and
        -not $cleanInput.EndsWith('.zip', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not ($cleanInput -match '[\*\?]')) {
        $archiveSuggestion = ConvertTo-ZipQuotedValue -Value ($cleanInput + '.zip') -AlwaysQuote $alwaysQuote
        $results.Add(
            (New-ZipCompletionResult `
                -CompletionText ($CompletionPrefix + $archiveSuggestion) `
                -ListItemText ($CompletionPrefix + ($cleanInput + '.zip')) `
                -ResultType 'ParameterValue' `
                -ToolTip 'Suggested archive path')
        )
    }

    @(Get-ZipUniqueCompletions -Results $results)
}

function Get-ZipPrefixedSuggestions {
    param(
        [string]$Prefix,
        [string]$CurrentValue,
        [string[]]$Suggestions,
        [string]$ToolTip
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    foreach ($suggestion in ($Suggestions | Sort-Object -Unique)) {
        if ($suggestion.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            $tokenText = $Prefix + $suggestion
            New-ZipCompletionResult -CompletionText $tokenText -ListItemText $tokenText -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }
}

function Get-ZipSeparatedSuggestions {
    param(
        [string]$Prefix,
        [string]$CurrentValue,
        [string[]]$Suggestions,
        [string]$ToolTip
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $separatorIndex = [Math]::Max($typedValue.LastIndexOf(':'), $typedValue.LastIndexOf(';'))
    $valuePrefix = ''
    $currentSegment = $typedValue

    if ($separatorIndex -ge 0) {
        $valuePrefix = $typedValue.Substring(0, $separatorIndex + 1)
        $currentSegment = $typedValue.Substring($separatorIndex + 1)
    }

    foreach ($suggestion in ($Suggestions | Sort-Object -Unique)) {
        if ($suggestion.StartsWith($currentSegment, [System.StringComparison]::OrdinalIgnoreCase)) {
            $tokenText = $Prefix + $valuePrefix + $suggestion
            New-ZipCompletionResult -CompletionText $tokenText -ListItemText $tokenText -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }
}

function Get-ZipPatternCompletions {
    param(
        [string]$CurrentValue,
        [string]$CompletionPrefix = ''
    )

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    foreach ($result in @(Get-ZipPathCompletions -InputPath $CurrentValue -Kind 'Any' -CompletionPrefix $CompletionPrefix)) {
        $results.Add($result)
    }

    $cleanValue = Remove-ZipOuterQuotes $CurrentValue
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentValue) -and ($CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'"))
    if ([string]::IsNullOrWhiteSpace($cleanValue)) {
        foreach ($wildcardSuggestion in @('*', '*.*', '*.zip', '*.log', '*.tmp')) {
            $results.Add(
                (New-ZipCompletionResult `
                    -CompletionText ($CompletionPrefix + $wildcardSuggestion) `
                    -ListItemText ($CompletionPrefix + $wildcardSuggestion) `
                    -ResultType 'ParameterValue' `
                    -ToolTip 'Wildcard pattern')
            )
        }
    }

    foreach ($directoryResult in @(Get-ZipPathCompletions -InputPath $CurrentValue -Kind 'Directory')) {
        $directoryText = $directoryResult.CompletionText
        $directoryTip = $directoryResult.ToolTip
        $patternText = $directoryText.TrimEnd('\', '/') + '\*'
        $quotedPattern = ConvertTo-ZipQuotedValue -Value $patternText -AlwaysQuote $alwaysQuote
        $results.Add(
            (New-ZipCompletionResult `
                -CompletionText ($CompletionPrefix + $quotedPattern) `
                -ListItemText ($CompletionPrefix + $patternText) `
                -ResultType 'ParameterValue' `
                -ToolTip ($directoryTip + ' (directory wildcard)'))
        )
    }

    @(Get-ZipUniqueCompletions -Results $results)
}

function Get-ZipValueCompletions {
    param(
        [string]$OptionKey,
        [string]$CurrentValue,
        [string]$CompletionPrefix = ''
    )

    $optionInfo = $script:ZipCompletionCatalog.OptionInfoByKey[$OptionKey]
    if (-not $optionInfo) {
        return @()
    }

    switch ([string]$optionInfo.ValueKind) {
        'Directory' {
            return @(Get-ZipPathCompletions -InputPath $CurrentValue -Kind 'Directory' -CompletionPrefix $CompletionPrefix)
        }
        'ArchivePath' {
            return @(Get-ZipArchivePathCompletions -InputPath $CurrentValue -CompletionPrefix $CompletionPrefix)
        }
        'Path' {
            return @(Get-ZipPathCompletions -InputPath $CurrentValue -Kind 'Any' -CompletionPrefix $CompletionPrefix)
        }
        'Date' {
            return @(Get-ZipPrefixedSuggestions -Prefix $CompletionPrefix -CurrentValue $CurrentValue -Suggestions $optionInfo.Suggestions -ToolTip $optionInfo.Description)
        }
        'SuffixList' {
            return @(Get-ZipSeparatedSuggestions -Prefix $CompletionPrefix -CurrentValue $CurrentValue -Suggestions $optionInfo.Suggestions -ToolTip $optionInfo.Description)
        }
        'List' {
            return @(Get-ZipPrefixedSuggestions -Prefix $CompletionPrefix -CurrentValue $CurrentValue -Suggestions $optionInfo.Suggestions -ToolTip $optionInfo.Description)
        }
        'PatternList' {
            return @(Get-ZipPatternCompletions -CurrentValue $CurrentValue -CompletionPrefix $CompletionPrefix)
        }
    }

    @()
}

function Get-ZipOptionCompletions {
    param([string]$WordToComplete)

    $cleanWord = if ([string]::IsNullOrWhiteSpace($WordToComplete)) {
        ''
    } else {
        Remove-ZipOuterQuotes $WordToComplete
    }

    $longOnly = $cleanWord.StartsWith('--')
    $shortOnly = -not $longOnly -and $cleanWord.StartsWith('-')

    foreach ($option in $script:ZipCompletionCatalog.Options) {
        $completionText = [string]$option.CompletionText
        $displayText = [string]$option.Display
        if ($longOnly -and -not $completionText.StartsWith('--')) {
            continue
        }

        if ($shortOnly -and $completionText.StartsWith('--')) {
            continue
        }

        if ($completionText.StartsWith($cleanWord, [System.StringComparison]::OrdinalIgnoreCase) -or
            $displayText.StartsWith($cleanWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-ZipCompletionResult `
                -CompletionText $completionText `
                -ListItemText $displayText `
                -ResultType 'ParameterName' `
                -ToolTip $option.Description
        }
    }
}

function Complete-Zip {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if (-not (Test-ZipCommandAvailable)) {
        return @()
    }

    Initialize-ZipCompletionCatalog

    $currentWord = if ($null -eq $wordToComplete) { '' } else { $wordToComplete }
    if ([string]::IsNullOrWhiteSpace($currentWord) -and $cursorPosition -le $commandAst.Extent.EndOffset) {
        $currentWord = Get-ZipCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $completedArguments = @(Get-ZipCompletedArguments -CommandAst $commandAst -CursorPosition $cursorPosition)
    $context = Get-ZipCompletionContext -Arguments $completedArguments

    if (-not $context.LiteralMode) {
        $inlineValueMatch = Get-ZipInlineValueMatch -Token $currentWord -TreatExactShortValueOptionAsInline $true
        if ($inlineValueMatch) {
            $inlineCompletions = @(Get-ZipValueCompletions -OptionKey $inlineValueMatch.OptionKey -CurrentValue $inlineValueMatch.Value -CompletionPrefix $inlineValueMatch.Prefix)
            if ($inlineCompletions.Count -gt 0) {
                return $inlineCompletions
            }
        }

        if ($null -ne $context.ExpectingValueOption) {
            return @(Get-ZipValueCompletions -OptionKey $context.ExpectingValueOption -CurrentValue $currentWord)
        }

        if ($null -ne $context.PatternListOption) {
            if (-not [string]::IsNullOrEmpty($currentWord) -and (Test-ZipLooksLikeOption -Token $currentWord)) {
                return @(Get-ZipOptionCompletions -WordToComplete $currentWord)
            }

            return @(Get-ZipPatternCompletions -CurrentValue $currentWord)
        }

        if (-not [string]::IsNullOrEmpty($currentWord) -and (Test-ZipShouldCompleteOptions -Token $currentWord)) {
            return @(Get-ZipOptionCompletions -WordToComplete $currentWord)
        }
    }

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    $positionalCount = $context.Positionals.Count

    if ($positionalCount -eq 0) {
        foreach ($result in @(Get-ZipArchivePathCompletions -InputPath $currentWord)) {
            $results.Add($result)
        }
    } else {
        foreach ($result in @(Get-ZipPathCompletions -InputPath $currentWord -Kind 'Any')) {
            $results.Add($result)
        }
    }

    if (-not $context.LiteralMode -and [string]::IsNullOrWhiteSpace($currentWord)) {
        foreach ($result in @(Get-ZipOptionCompletions -WordToComplete $currentWord)) {
            $results.Add($result)
        }
    }

    @(Get-ZipUniqueCompletions -Results $results)
}

Register-ArgumentCompleter -Native -CommandName 'zip', 'zip.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Zip -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
