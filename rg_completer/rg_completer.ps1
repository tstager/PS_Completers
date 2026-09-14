# rg tab completion for PowerShell
# Builds a help-driven option catalog for rg.exe and adds value-aware completion.

Set-StrictMode -Version 2.0

function New-RgCompletionResult {
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

function Get-RgUniqueStrings {
    param([string[]]$Items)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $results = New-Object System.Collections.Generic.List[string]

    foreach ($item in @($Items)) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        if ($seen.Add($item)) {
            [void]$results.Add($item)
        }
    }

    @($results.ToArray())
}

function Get-RgDefaultEncodingSuggestions {
    @(
        'auto',
        'none',
        'utf-8',
        'utf8',
        'utf-16',
        'utf-16le',
        'utf-16be',
        'utf-32',
        'utf-32le',
        'utf-32be',
        'ascii',
        'latin1',
        'windows-1252',
        'shift_jis',
        'euc-jp',
        'gbk',
        'big5'
    )
}

function Get-RgGenerateKinds {
    @(
        'man',
        'complete-bash',
        'complete-zsh',
        'complete-fish',
        'complete-powershell'
    )
}

function Get-RgHyperlinkFormats {
    @(
        'default',
        'none',
        'cursor',
        'file',
        'grep+',
        'kitty',
        'macvim',
        'textmate',
        'vscode',
        'vscode-insiders',
        'vscodium'
    )
}

function Get-RgColorWhenValues {
    @('never', 'auto', 'always', 'ansi')
}

function Get-RgSortValues {
    @('none', 'path', 'modified', 'accessed', 'created')
}

function Get-RgColorSpecSuggestions {
    @(
        'path:fg:cyan',
        'line:fg:green',
        'column:fg:yellow',
        'match:fg:magenta',
        'highlight:bg:yellow',
        'highlight:fg:black',
        'path:none'
    )
}

function Get-RgCompletionCatalog {
    if (Get-Variable -Name RgCompletionCatalog -Scope Script -ErrorAction Ignore) {
        return $script:RgCompletionCatalog
    }

    $script:RgCompletionCatalog = @{
        Initialized          = $false
        CommandName          = $null
        Options              = @()
        OptionByToken        = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        TypeNames            = @()
        EncodingSuggestions  = Get-RgDefaultEncodingSuggestions
        GenerateKinds        = Get-RgGenerateKinds
        HyperlinkFormats     = Get-RgHyperlinkFormats
        ColorWhenValues      = Get-RgColorWhenValues
        SortValues           = Get-RgSortValues
        ColorSpecSuggestions = Get-RgColorSpecSuggestions
    }

    $script:RgCompletionCatalog
}

function Resolve-RgCommandName {
    $catalog = Get-RgCompletionCatalog
    if ($catalog.CommandName) {
        return $catalog.CommandName
    }

    $command = Get-Command -Name rg.exe, rg -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $catalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $catalog.CommandName
}

function Invoke-RgCapture {
    param([string[]]$Arguments)

    $commandName = Resolve-RgCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>$null)
    } catch {
        @()
    }
}

function Remove-RgOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-RgQuotedValue {
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

function Test-RgPathLikeInput {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $cleanValue = Remove-RgOuterQuotes -Value $Value
    $cleanValue -match '^(?:\.{1,2}[\\/]|[\\/]|~[\\/]|[A-Za-z]:|\\\\)'
}

function Get-RgTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-RgCurrentToken {
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

function Get-RgArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += Get-RgTokenText -Element $element
        }
    }

    $tokens
}

function Get-RgValueKind {
    param(
        [string]$Token,
        [string]$Placeholder
    )

    $tokenKey = if ($Token.StartsWith('--')) { $Token.ToLowerInvariant() } else { $Token }
    $placeholderKey = if ([string]::IsNullOrWhiteSpace($Placeholder)) { '' } else { $Placeholder.ToUpperInvariant() }

    switch -CaseSensitive ($tokenKey) {
        '-e' { return 'Pattern' }
        '--regexp' { return 'Pattern' }
        '-f' { return 'PatternFilePathOrStdin' }
        '--file' { return 'PatternFilePathOrStdin' }
        '-g' { return 'Glob' }
        '--glob' { return 'Glob' }
        '--iglob' { return 'Glob' }
        '--pre-glob' { return 'Glob' }
        '-t' { return 'FileType' }
        '--type' { return 'FileType' }
        '-T' { return 'FileType' }
        '--type-not' { return 'FileType' }
        '--type-clear' { return 'FileType' }
        '--type-add' { return 'TypeSpec' }
        '-E' { return 'Encoding' }
        '--encoding' { return 'Encoding' }
        '--engine' { return 'Engine' }
        '--sort' { return 'Sort' }
        '--sortr' { return 'Sort' }
        '--color' { return 'ColorWhen' }
        '--colors' { return 'ColorSpec' }
        '--generate' { return 'GenerateKind' }
        '--hyperlink-format' { return 'HyperlinkFormat' }
        '--path-separator' { return 'PathSeparator' }
        '--context-separator' { return 'Separator' }
        '--field-context-separator' { return 'Separator' }
        '--field-match-separator' { return 'Separator' }
        '--pre' { return 'Command' }
        '--ignore-file' { return 'FilePath' }
        '-r' { return 'Replacement' }
        '--replace' { return 'Replacement' }
        '-A' { return 'Number' }
        '--after-context' { return 'Number' }
        '-B' { return 'Number' }
        '--before-context' { return 'Number' }
        '-C' { return 'Number' }
        '--context' { return 'Number' }
        '-j' { return 'Number' }
        '--threads' { return 'Number' }
        '-m' { return 'Number' }
        '--max-count' { return 'Number' }
        '-M' { return 'Number' }
        '--max-columns' { return 'Number' }
        '--max-depth' { return 'Number' }
        '--dfa-size-limit' { return 'Size' }
        '--regex-size-limit' { return 'Size' }
        '--max-filesize' { return 'Size' }
    }

    switch ($placeholderKey) {
        'PATTERN' { return 'Pattern' }
        'PATTERNFILE' { return 'PatternFilePathOrStdin' }
        'PATH' { return 'Path' }
        'TYPE' { return 'FileType' }
        'TYPESPEC' { return 'TypeSpec' }
        'ENCODING' { return 'Encoding' }
        'ENGINE' { return 'Engine' }
        'SORTBY' { return 'Sort' }
        'WHEN' { return 'ColorWhen' }
        'COLOR_SPEC' { return 'ColorSpec' }
        'KIND' { return 'GenerateKind' }
        'FORMAT' { return 'HyperlinkFormat' }
        'SEPARATOR' { return 'Separator' }
        'COMMAND' { return 'Command' }
        'GLOB' { return 'Glob' }
        'NUM' { return 'Number' }
        'NUM+SUFFIX?' { return 'Size' }
    }

    $null
}

function Get-RgCanonicalOptionKey {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    if ($Token.StartsWith('--')) {
        return 'long:' + $Token.ToLowerInvariant()
    }

    if ($Token.StartsWith('-')) {
        return 'short:' + $Token
    }

    $null
}

function ConvertFrom-RgOptionSpecLine {
    param([string]$Line)

    $specLine = $Line.Trim()
    $parts = $specLine -split ',\s+', 2
    $results = New-Object System.Collections.Generic.List[object]

    if ($parts.Count -eq 2) {
        $shortPart = $parts[0].Trim()
        $longPart = $parts[1].Trim()

        if ($shortPart -match '^(?<token>-[^,\s]+)(?:\s+(?<value>\S+))?$') {
            [void]$results.Add([pscustomobject]@{
                    Token        = $matches['token']
                    DisplayText  = $shortPart
                    Placeholder  = $matches['value']
                })
        }

        if ($longPart -match '^(?<token>--[A-Za-z0-9][A-Za-z0-9\-]*)(?:[= ](?<value>\S+))?$') {
            [void]$results.Add([pscustomobject]@{
                    Token        = $matches['token']
                    DisplayText  = $longPart
                    Placeholder  = $matches['value']
                })
        }
    } elseif ($specLine -match '^(?<token>--[A-Za-z0-9][A-Za-z0-9\-]*)(?:[= ](?<value>\S+))?$') {
        [void]$results.Add([pscustomobject]@{
                Token        = $matches['token']
                DisplayText  = $specLine
                Placeholder  = $matches['value']
            })
    }

    @($results.ToArray())
}

function Add-RgOptionSpec {
    param(
        [string]$Token,
        [string]$DisplayText,
        [string]$Description,
        [string]$Placeholder
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return
    }

    $catalog = Get-RgCompletionCatalog
    $key = Get-RgCanonicalOptionKey -Token $Token
    if ($catalog.OptionByToken.ContainsKey($key)) {
        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            $catalog.OptionByToken[$key].Description = $Description
        }
        return
    }

    $catalog.OptionByToken[$key] = [pscustomobject]@{
        Token        = $Token
        DisplayText  = if ([string]::IsNullOrWhiteSpace($DisplayText)) { $Token } else { $DisplayText }
        Description  = $Description
        Placeholder  = $Placeholder
        ValueKind    = Get-RgValueKind -Token $Token -Placeholder $Placeholder
    }

    $catalog.Options += $catalog.OptionByToken[$key]
}

function Initialize-RgCompletionCatalog {
    $catalog = Get-RgCompletionCatalog
    if ($catalog.Initialized) {
        return
    }

    $helpLines = Invoke-RgCapture -Arguments @('--help')
    $currentKeys = @()
    $lastOptionKey = $null

    foreach ($line in @($helpLines)) {
        if ($line -match '^\s*(?:-[^,\s]+(?:\s+\S+)?\,\s+)?--[A-Za-z0-9][A-Za-z0-9\-]*(?:[= ]\S+)?\s*$') {
            $currentKeys = @()

            foreach ($parsed in @(ConvertFrom-RgOptionSpecLine -Line $line)) {
                Add-RgOptionSpec -Token $parsed.Token -DisplayText $parsed.DisplayText -Description $parsed.DisplayText -Placeholder $parsed.Placeholder
                $currentKeys += Get-RgCanonicalOptionKey -Token $parsed.Token
            }

            if ($currentKeys.Count -gt 0) {
                $lastOptionKey = $currentKeys[-1]
            }

            continue
        }

        # Hidden aliases (--maxdepth for --max-depth) are documented only in the prose paragraphs.
        if ($lastOptionKey -and $line -match 'alternative spelling for this flag is (?<alias>--[A-Za-z0-9][A-Za-z0-9\-]*)') {
            $aliasToken = $matches['alias']
            $primary = $catalog.OptionByToken[$lastOptionKey]
            Add-RgOptionSpec -Token $aliasToken -DisplayText $aliasToken -Description ('Alternative spelling of ' + $primary.Token + '.') -Placeholder $primary.Placeholder
        }

        if ($currentKeys.Count -gt 0 -and $line -match '^\s{8,}(?<text>\S.*)$') {
            $continuation = $matches['text'].Trim()
            foreach ($key in $currentKeys) {
                $option = $catalog.OptionByToken[$key]
                if ([string]::IsNullOrWhiteSpace($option.Description) -or $option.Description -eq $option.DisplayText) {
                    $option.Description = $continuation
                } elseif (-not $option.Description.EndsWith($continuation, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $option.Description += ' ' + $continuation
                }
            }

            continue
        }

        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\S') {
            $currentKeys = @()
        }
    }

    # ripgrep prints negation and alias spellings (--no-*, --maxdepth, --ignore, ...) only in
    # prose, so harvest the remaining accepted flags from its own generated completion script.
    $generated = @(Invoke-RgCapture -Arguments @('--generate', 'complete-powershell'))
    foreach ($line in $generated) {
        if ($line -match "\[CompletionResult\]::new\('(?<token>--?[A-Za-z0-9][A-Za-z0-9\-]*)',\s*'[^']*',\s*\[CompletionResultType\]::ParameterName,\s*'(?<desc>(?:[^']|'')*)'\)") {
            $description = $matches['desc'].Replace("''", "'")
            $key = Get-RgCanonicalOptionKey -Token $matches['token']
            if (-not $catalog.OptionByToken.ContainsKey($key)) {
                Add-RgOptionSpec -Token $matches['token'] -DisplayText $matches['token'] -Description $description
            }
        }
    }

    $catalog.TypeNames = Get-RgUniqueStrings -Items (
        Invoke-RgCapture -Arguments @('--type-list') |
            ForEach-Object {
                if ($_ -match '^\s*([A-Za-z0-9][A-Za-z0-9+-]*)\s*:') {
                    $matches[1]
                }
            }
    )

    $catalog.Initialized = $true
}

function Get-RgPathCompletions {
    param(
        [string]$InputPath,
        [string]$Prefix = '',
        [switch]$DirectoriesOnly
    )

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and $InputPath.StartsWith('"')

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput.EndsWith('\') -or $cleanInput.EndsWith('/')) {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }
        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $items = @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)
    if ($DirectoriesOnly) {
        $items = @($items | Where-Object { $_.PSIsContainer })
    }

    foreach ($item in $items) {
        $completionText = if (-not [System.IO.Path]::IsPathRooted($cleanInput)) {
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

        $completionText = ConvertTo-RgQuotedValue -Value $completionText -AlwaysQuote $alwaysQuote
        $completionText = $Prefix + $completionText

        New-RgCompletionResult -CompletionText $completionText -ListItemText $item.Name -ResultType 'ParameterValue' -ToolTip $item.FullName
    }
}

function New-RgLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-RgCompletionResult -CompletionText ($Prefix + $Placeholder) -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-RgCompletionResult -CompletionText ($Prefix + $CurrentValue) -ListItemText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-RgEnumValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }

    foreach ($value in @($Values)) {
        if ($value -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*')) {
            New-RgCompletionResult -CompletionText ($Prefix + $value) -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }
}

function Get-RgEnumOrLiteralValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $results = @(Get-RgEnumValueResults -Values $Values -CurrentValue $CurrentValue -ToolTip $ToolTip -Prefix $Prefix)
    if ($results.Count -gt 0) {
        return $results
    }

    New-RgLiteralValueResults -CurrentValue $CurrentValue -Placeholder $Placeholder -ToolTip $ToolTip -Prefix $Prefix
}

function Get-RgPathValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = '',
        [switch]$DirectoriesOnly,
        [switch]$AllowStdinSentinel
    )

    $results = New-Object System.Collections.Generic.List[object]
    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }

    if ($AllowStdinSentinel -and ('-' -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*'))) {
        [void]$results.Add((New-RgCompletionResult -CompletionText ($Prefix + '-') -ResultType 'ParameterValue' -ToolTip 'Read this value from standard input.'))
    }

    foreach ($item in @(Get-RgPathCompletions -InputPath $typedValue -Prefix $Prefix -DirectoriesOnly:$DirectoriesOnly)) {
        [void]$results.Add($item)
    }

    if ($results.Count -gt 0) {
        return @($results.ToArray())
    }

    New-RgLiteralValueResults -CurrentValue $typedValue -Placeholder $Placeholder -ToolTip $ToolTip -Prefix $Prefix
}

function Get-RgTypeValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $catalog = Get-RgCompletionCatalog
    $results = @(Get-RgEnumValueResults -Values $catalog.TypeNames -CurrentValue $CurrentValue -ToolTip $ToolTip -Prefix $Prefix)
    if ($results.Count -gt 0) {
        return $results
    }

    New-RgLiteralValueResults -CurrentValue $CurrentValue -Placeholder $Placeholder -ToolTip $ToolTip -Prefix $Prefix
}

function Get-RgTypeSpecValueResults {
    param(
        [string]$CurrentValue,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $catalog = Get-RgCompletionCatalog
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($typeName in @($catalog.TypeNames | Select-Object -First 12)) {
        foreach ($candidate in @("${typeName}:*.ext", "${typeName}:include:cpp,py,md")) {
            if (-not [string]::IsNullOrWhiteSpace($CurrentValue) -and $candidate -notlike "$CurrentValue*") {
                continue
            }
            [void]$results.Add((New-RgCompletionResult -CompletionText ($Prefix + $candidate) -ResultType 'ParameterValue' -ToolTip $ToolTip))
        }
    }

    if ($results.Count -gt 0) {
        return @($results.ToArray())
    }

    New-RgLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<type:glob>' -ToolTip $ToolTip -Prefix $Prefix
}

function Get-RgValueCompletions {
    param(
        [pscustomobject]$OptionSpec,
        [string]$CurrentValue,
        [string]$Prefix = ''
    )

    $catalog = Get-RgCompletionCatalog
    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $toolTip = if ([string]::IsNullOrWhiteSpace($OptionSpec.Description)) { $OptionSpec.DisplayText } else { $OptionSpec.Description }

    switch ($OptionSpec.ValueKind) {
        'Pattern' {
            return New-RgLiteralValueResults -CurrentValue $typedValue -Placeholder '<pattern>' -ToolTip $toolTip -Prefix $Prefix
        }
        'Replacement' {
            return New-RgLiteralValueResults -CurrentValue $typedValue -Placeholder '<replacement>' -ToolTip $toolTip -Prefix $Prefix
        }
        'Glob' {
            return New-RgLiteralValueResults -CurrentValue $typedValue -Placeholder '<glob>' -ToolTip $toolTip -Prefix $Prefix
        }
        'PatternFilePathOrStdin' {
            return @(Get-RgPathValueResults -CurrentValue $typedValue -Placeholder '<pattern-file>' -ToolTip $toolTip -Prefix $Prefix -AllowStdinSentinel)
        }
        'FilePath' {
            return @(Get-RgPathValueResults -CurrentValue $typedValue -Placeholder '<file>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'Path' {
            return @(Get-RgPathValueResults -CurrentValue $typedValue -Placeholder '<path>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'FileType' {
            return @(Get-RgTypeValueResults -CurrentValue $typedValue -Placeholder '<type>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'TypeSpec' {
            return @(Get-RgTypeSpecValueResults -CurrentValue $typedValue -ToolTip $toolTip -Prefix $Prefix)
        }
        'Encoding' {
            return @(Get-RgEnumOrLiteralValueResults -Values $catalog.EncodingSuggestions -CurrentValue $typedValue -Placeholder '<encoding>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'Engine' {
            return @(Get-RgEnumOrLiteralValueResults -Values @('default', 'pcre2', 'auto') -CurrentValue $typedValue -Placeholder '<engine>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'Sort' {
            return @(Get-RgEnumOrLiteralValueResults -Values $catalog.SortValues -CurrentValue $typedValue -Placeholder '<sort>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'ColorWhen' {
            return @(Get-RgEnumOrLiteralValueResults -Values $catalog.ColorWhenValues -CurrentValue $typedValue -Placeholder '<when>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'ColorSpec' {
            return @(Get-RgEnumOrLiteralValueResults -Values $catalog.ColorSpecSuggestions -CurrentValue $typedValue -Placeholder '<color-spec>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'GenerateKind' {
            return @(Get-RgEnumOrLiteralValueResults -Values $catalog.GenerateKinds -CurrentValue $typedValue -Placeholder '<kind>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'HyperlinkFormat' {
            return @(Get-RgEnumOrLiteralValueResults -Values $catalog.HyperlinkFormats -CurrentValue $typedValue -Placeholder '<format>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'PathSeparator' {
            return @(Get-RgEnumOrLiteralValueResults -Values @('/', '\') -CurrentValue $typedValue -Placeholder '<separator>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'Separator' {
            return New-RgLiteralValueResults -CurrentValue $typedValue -Placeholder '<separator>' -ToolTip $toolTip -Prefix $Prefix
        }
        'Command' {
            return New-RgLiteralValueResults -CurrentValue $typedValue -Placeholder '<command>' -ToolTip $toolTip -Prefix $Prefix
        }
        'Number' {
            return @(Get-RgEnumOrLiteralValueResults -Values @('0', '1', '2', '4', '8', '16', '32', '64', '120') -CurrentValue $typedValue -Placeholder '<number>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'Size' {
            return @(Get-RgEnumOrLiteralValueResults -Values @('64K', '1M', '10M', '100M', '1G') -CurrentValue $typedValue -Placeholder '<size>' -ToolTip $toolTip -Prefix $Prefix)
        }
        default {
            return New-RgLiteralValueResults -CurrentValue $typedValue -Placeholder '<value>' -ToolTip $toolTip -Prefix $Prefix
        }
    }
}

function Get-RgOptionKey {
    param([string]$Token)

    $cleanToken = Remove-RgOuterQuotes -Value $Token
    if ($cleanToken -match '^(--[A-Za-z0-9][A-Za-z0-9\-]*)') {
        return Get-RgCanonicalOptionKey -Token $matches[1]
    }

    if ($cleanToken -match '^(-[^=\s]+)$') {
        return Get-RgCanonicalOptionKey -Token $matches[1]
    }

    $null
}

function Resolve-RgShortToken {
    # Decomposes a single-dash token into known short flags. A value-taking flag ends the
    # cluster and the remainder of the token is its attached value (-tpy, -A5, -iA5).
    param([string]$Token)

    $cleanToken = Remove-RgOuterQuotes -Value $Token
    if ($cleanToken.Length -lt 2 -or -not $cleanToken.StartsWith('-') -or $cleanToken.StartsWith('--')) {
        return $null
    }

    $catalog = Get-RgCompletionCatalog
    $flags = New-Object System.Collections.Generic.List[object]
    $valueOption = $null
    $value = ''
    $prefix = '-'

    for ($index = 1; $index -lt $cleanToken.Length; $index++) {
        $key = Get-RgCanonicalOptionKey -Token ('-' + $cleanToken[$index])
        if (-not $catalog.OptionByToken.ContainsKey($key)) {
            return $null
        }

        $option = $catalog.OptionByToken[$key]
        $flags.Add($option)
        $prefix += $cleanToken[$index]
        if ($option.ValueKind) {
            $valueOption = $option
            $value = $cleanToken.Substring($index + 1)
            break
        }
    }

    [pscustomobject]@{
        Flags       = @($flags.ToArray())
        ValueOption = $valueOption
        Value       = $value
        Prefix      = $prefix
    }
}

function Get-RgShortClusterCompletion {
    param([pscustomobject]$Cluster)

    $catalog = Get-RgCompletionCatalog
    $present = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($flag in $Cluster.Flags) {
        [void]$present.Add($flag.Token)
    }

    New-RgCompletionResult -CompletionText $Cluster.Prefix -ResultType 'ParameterName' -ToolTip ('Flags: ' + (($Cluster.Flags | ForEach-Object { $_.Token }) -join ' '))

    foreach ($option in $catalog.Options) {
        if ($option.Token.Length -ne 2 -or $option.Token.StartsWith('--') -or $present.Contains($option.Token)) {
            continue
        }

        $toolTip = if ([string]::IsNullOrWhiteSpace($option.Description)) { $option.DisplayText } else { $option.Description }
        New-RgCompletionResult -CompletionText ($Cluster.Prefix + $option.Token.Substring(1)) -ListItemText ($Cluster.Prefix + $option.Token.Substring(1)) -ResultType 'ParameterName' -ToolTip $toolTip
    }
}

function Get-RgCompletionContext {
    param([string[]]$TokensBeforeCurrent)

    Initialize-RgCompletionCatalog
    $catalog = Get-RgCompletionCatalog

    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingOption = $null
    $endOfOptions = $false
    $filesMode = $false
    $hasPatternSource = $false
    $terminalMode = $false

    foreach ($token in @($TokensBeforeCurrent)) {
        $cleanToken = Remove-RgOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($pendingOption) {
            if ($pendingOption.ValueKind -in @('Pattern', 'PatternFilePathOrStdin')) {
                $hasPatternSource = $true
            }
            if ($pendingOption.Token -eq '--generate') {
                $terminalMode = $true
            }
            $pendingOption = $null
            continue
        }

        if ($endOfOptions) {
            $positionals.Add($cleanToken)
            continue
        }

        if ($cleanToken -eq '--') {
            $endOfOptions = $true
            continue
        }

        $cluster = if ($cleanToken.Length -gt 2) { Resolve-RgShortToken -Token $cleanToken } else { $null }
        if ($cluster) {
            foreach ($flag in $cluster.Flags) {
                if ($flag.Token -in @('-h', '-V')) {
                    $terminalMode = $true
                }
            }

            if ($cluster.ValueOption) {
                if ($cluster.Value.Length -gt 0) {
                    if ($cluster.ValueOption.ValueKind -in @('Pattern', 'PatternFilePathOrStdin')) {
                        $hasPatternSource = $true
                    }
                } else {
                    $pendingOption = $cluster.ValueOption
                }
            }
            continue
        }

        if ($cleanToken -match '^(--[^=]+)=(.*)$') {
            $lookup = Get-RgCanonicalOptionKey -Token $matches[1]
            if ($catalog.OptionByToken.ContainsKey($lookup)) {
                $option = $catalog.OptionByToken[$lookup]
                if ($option.ValueKind -in @('Pattern', 'PatternFilePathOrStdin')) {
                    $hasPatternSource = $true
                }
                if ($option.Token -eq '--generate') {
                    $terminalMode = $true
                }
                continue
            }
        }

        $lookup = Get-RgOptionKey -Token $cleanToken
        if ($lookup -and $catalog.OptionByToken.ContainsKey($lookup)) {
            $option = $catalog.OptionByToken[$lookup]
            if ($option.Token -eq '--files') {
                $filesMode = $true
            }
            if ($option.Token -in @('-h', '--help', '-V', '--version', '--pcre2-version', '--type-list')) {
                $terminalMode = $true
            }

            if ($option.ValueKind) {
                $pendingOption = $option
            }
            continue
        }

        $positionals.Add($cleanToken)
    }

    [pscustomobject]@{
        PendingOption    = $pendingOption
        EndOfOptions     = $endOfOptions
        FilesMode        = $filesMode
        HasPatternSource = $hasPatternSource
        TerminalMode     = $terminalMode
        Positionals      = @($positionals)
    }
}

function Get-RgOptionCompletions {
    param([string]$CurrentWord)

    Initialize-RgCompletionCatalog
    $catalog = Get-RgCompletionCatalog
    $cleanCurrent = Remove-RgOuterQuotes -Value $CurrentWord

    foreach ($option in $catalog.Options) {
        $matchesPrefix = $false
        if ([string]::IsNullOrWhiteSpace($cleanCurrent)) {
            $matchesPrefix = $true
        } elseif ($cleanCurrent.StartsWith('--')) {
            $matchesPrefix = $option.Token.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)
        } else {
            $matchesPrefix = $option.Token.StartsWith($cleanCurrent, [System.StringComparison]::Ordinal)
        }

        if (-not $matchesPrefix) {
            continue
        }

        $toolTip = if ([string]::IsNullOrWhiteSpace($option.Description)) { $option.DisplayText } else { $option.Description }
        New-RgCompletionResult -CompletionText $option.Token -ListItemText $option.DisplayText -ResultType 'ParameterName' -ToolTip $toolTip
    }
}

function Get-RgPositionalCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$Context
    )

    if ($Context.TerminalMode -and -not $Context.FilesMode) {
        return @()
    }

    if ($Context.FilesMode -or $Context.HasPatternSource -or $Context.Positionals.Count -gt 0) {
        return @(Get-RgPathValueResults -CurrentValue $CurrentWord -Placeholder '<path>' -ToolTip 'File or directory path to search.')
    }

    New-RgLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<pattern>' -ToolTip 'Regular expression or literal pattern to search.'
}

Register-ArgumentCompleter -Native -CommandName 'rg', 'rg.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    if ($wordToComplete -isnot [string]) {
        $wordToComplete = [string]$wordToComplete
    }

    Initialize-RgCompletionCatalog
    $catalog = Get-RgCompletionCatalog

    # The AST extent stops at the last token, so an empty $wordToComplete is the only reliable
    # signal that the cursor sits after whitespace and a fresh slot is being completed.
    $currentToken = if ([string]::IsNullOrEmpty($wordToComplete)) {
        ''
    } else {
        Get-RgCurrentToken -Line $commandAst.Extent.Text -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }
    $tokensBeforeCurrent = Get-RgArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition
    $context = Get-RgCompletionContext -TokensBeforeCurrent $tokensBeforeCurrent

    if ($currentToken -match '^(--[^=]+)=(.*)$') {
        $optionKey = Get-RgCanonicalOptionKey -Token $matches[1]
        $valuePrefix = $matches[2]
        if ($catalog.OptionByToken.ContainsKey($optionKey)) {
            $optionSpec = $catalog.OptionByToken[$optionKey]
            if ($optionSpec.ValueKind) {
                return @(Get-RgValueCompletions -OptionSpec $optionSpec -CurrentValue $valuePrefix -Prefix ($matches[1] + '='))
            }
        }
    }

    if ($currentToken.Length -gt 2 -and -not $context.EndOfOptions) {
        $cluster = Resolve-RgShortToken -Token $currentToken
        if ($cluster) {
            if ($cluster.ValueOption) {
                return @(Get-RgValueCompletions -OptionSpec $cluster.ValueOption -CurrentValue $cluster.Value -Prefix $cluster.Prefix)
            }

            return @(Get-RgShortClusterCompletion -Cluster $cluster)
        }
    }

    if ($context.PendingOption) {
        return @(Get-RgValueCompletions -OptionSpec $context.PendingOption -CurrentValue $currentToken)
    }

    if ($currentToken.StartsWith('-') -and -not $context.EndOfOptions) {
        return @(Get-RgOptionCompletions -CurrentWord $currentToken)
    }

    @(Get-RgPositionalCompletions -CurrentWord $currentToken -Context $context)
}
