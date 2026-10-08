# wc tab completion for PowerShell
# Builds a help-driven option catalog for wc.exe and adds value-aware completion.
# The catalog parser is format-agnostic: it understands both the clap-based coreutils
# synopsis style (`-x, --long <PLACEHOLDER>` with separate-token placeholders) and the
# GNU wc style (`--long=PLACEHOLDER` with attached placeholders), so the same script
# adapts to whichever build (uutils coreutils or GNU coreutils) resolves first on PATH.

Set-StrictMode -Version 2.0

function New-WcCompletionResult {
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

function Get-WcTotalValues {
    @('auto', 'always', 'only', 'never')
}

function Get-WcCompletionCatalog {
    if (Get-Variable -Name WcCompletionCatalog -Scope Script -ErrorAction Ignore) {
        return $script:WcCompletionCatalog
    }

    $script:WcCompletionCatalog = @{
        Initialized   = $false
        CommandName   = $null
        Options       = @()
        OptionByToken = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        TotalValues   = Get-WcTotalValues
    }

    $script:WcCompletionCatalog
}

function Resolve-WcCommandName {
    $catalog = Get-WcCompletionCatalog
    if ($catalog.CommandName) {
        return $catalog.CommandName
    }

    $command = Get-Command -Name wc.exe, wc -ErrorAction Ignore | Select-Object -First 1
    if ($command) {
        $catalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $catalog.CommandName
}

function Invoke-WcCapture {
    param([string[]]$Arguments)

    $commandName = Resolve-WcCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })
    } catch {
        @()
    }
}

function Remove-WcOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertFrom-WcTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    $tokens[0].Value
}

function ConvertTo-WcQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default). PowerShell reads ' and
    # U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes.
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $QuoteChar) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]' -and $Value -notmatch '^[-\u2013-\u2015]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-WcTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-WcCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The word as typed, cut from the element under the cursor: PowerShell hands a quoted
    # word over unescaped, and the parser keeps an unterminated quoted word as one element.
    foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    ''
}

function Get-WcArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += Get-WcTokenText -Element $element
        }
    }

    $tokens
}

function Get-WcValueKind {
    param(
        [string]$Token,
        [string]$Placeholder
    )

    $tokenKey = if ($Token.StartsWith('--')) { $Token.ToLowerInvariant() } else { $Token }
    $placeholderKey = if ([string]::IsNullOrWhiteSpace($Placeholder)) { '' } else { $Placeholder.ToUpperInvariant() }

    switch -CaseSensitive ($tokenKey) {
        '--files0-from' { return 'FilesFrom' }
        '--total' { return 'Total' }
    }

    switch ($placeholderKey) {
        'F' { return 'FilesFrom' }
        'WHEN' { return 'Total' }
    }

    $null
}

function Get-WcCanonicalOptionKey {
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

function ConvertFrom-WcOptionSpecLine {
    param([string]$Line)

    $results = New-Object System.Collections.Generic.List[object]

    # Separate the option synopsis from any inline description. Both GNU and clap help
    # put the description after a run of two or more spaces, so cut at the first such gap.
    $specPart = ($Line -replace '^\s+', '')
    $description = ''
    if ($specPart -match '^(?<spec>.*?\S)\s{2,}(?<desc>\S.*)$') {
        $specPart = $matches['spec']
        $description = $matches['desc'].Trim()
    }
    $specPart = $specPart.TrimEnd()

    # Trim a trailing comma left by split alias lines.
    $specLine = $specPart.TrimEnd(',').Trim()
    if ([string]::IsNullOrWhiteSpace($specLine)) {
        return @($results.ToArray())
    }

    $parts = $specLine -split ',\s+', 2

    if ($parts.Count -eq 2 -and $parts[0].Trim().StartsWith('-') -and -not $parts[0].Trim().StartsWith('--')) {
        $shortPart = $parts[0].Trim()
        $longPart = $parts[1].Trim()

        if ($shortPart -match '^(?<token>-[A-Za-z0-9])(?:[= ]\[?(?<value>[^\]\s]+)\]?)?$') {
            [void]$results.Add([pscustomobject]@{
                    Token       = $matches['token']
                    DisplayText = $shortPart
                    Placeholder = $matches['value']
                    Description = $description
                })
        }

        if ($longPart -match '^(?<token>--[A-Za-z0-9][A-Za-z0-9\-]*)(?:\[?[= ]\<?(?<value>[^\]\s>]+)\>?\]?)?$') {
            [void]$results.Add([pscustomobject]@{
                    Token       = $matches['token']
                    DisplayText = $longPart
                    Placeholder = $matches['value']
                    Description = $description
                })
        }
    } elseif ($specLine -match '^(?<token>--[A-Za-z0-9][A-Za-z0-9\-]*)(?:\[?[= ]\<?(?<value>[^\]\s>]+)\>?\]?)?$') {
        [void]$results.Add([pscustomobject]@{
                Token       = $matches['token']
                DisplayText = $specLine
                Placeholder = $matches['value']
                Description = $description
            })
    } elseif ($specLine -match '^(?<token>-[A-Za-z0-9])(?:[= ]\[?(?<value>[^\]\s]+)\]?)?$') {
        # Short-only option line.
        [void]$results.Add([pscustomobject]@{
                Token       = $matches['token']
                DisplayText = $specLine
                Placeholder = $matches['value']
                Description = $description
            })
    }

    @($results.ToArray())
}

function Add-WcOptionSpec {
    param(
        [string]$Token,
        [string]$DisplayText,
        [string]$Description,
        [string]$Placeholder
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return
    }

    $catalog = Get-WcCompletionCatalog
    $key = Get-WcCanonicalOptionKey -Token $Token
    if ($catalog.OptionByToken.ContainsKey($key)) {
        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            $catalog.OptionByToken[$key].Description = $Description
        }
        return
    }

    $catalog.OptionByToken[$key] = [pscustomobject]@{
        Token       = $Token
        DisplayText = if ([string]::IsNullOrWhiteSpace($DisplayText)) { $Token } else { $DisplayText }
        Description = $Description
        Placeholder = $Placeholder
        ValueKind   = Get-WcValueKind -Token $Token -Placeholder $Placeholder
    }

    $catalog.Options += $catalog.OptionByToken[$key]
}

function Initialize-WcCompletionCatalog {
    $catalog = Get-WcCompletionCatalog
    if ($catalog.Initialized) {
        return
    }

    $helpLines = Invoke-WcCapture -Arguments @('--help')
    $currentKeys = @()

    foreach ($line in @($helpLines)) {
        # A synopsis line is indented and begins (after indent) with an option token:
        #   short pair "-x, --long", long-only "    --long", or short-only "  -I".
        $isSynopsis = ($line -match '^\s{2,}-[A-Za-z](?:[, =\[]|$)' -or $line -match '^\s{2,}--[A-Za-z0-9]')

        if ($isSynopsis) {
            $parsed = @(ConvertFrom-WcOptionSpecLine -Line $line)
            if ($parsed.Count -gt 0) {
                $currentKeys = @()

                foreach ($spec in $parsed) {
                    Add-WcOptionSpec -Token $spec.Token -DisplayText $spec.DisplayText -Description $spec.Description -Placeholder $spec.Placeholder
                    $currentKeys += Get-WcCanonicalOptionKey -Token $spec.Token
                }

                continue
            }
        }

        if ($currentKeys.Count -gt 0 -and $line -match '^\s{8,}(?<text>\S.*)$') {
            $continuation = $matches['text'].Trim()
            foreach ($key in $currentKeys) {
                $option = $catalog.OptionByToken[$key]
                if ([string]::IsNullOrWhiteSpace($option.Description)) {
                    $option.Description = $continuation
                } else {
                    $option.Description += ' ' + $continuation
                }
            }

            continue
        }

        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\S') {
            $currentKeys = @()
        }
    }

    $catalog.Initialized = $true
}

function Get-WcPathCompletions {
    param(
        [string]$InputPath,
        [string]$Prefix = '',
        [switch]$DirectoriesOnly
    )

    $cleanInput = ConvertFrom-WcTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # Keep the directory part exactly as typed (.\, ./, ..\, C:\ ...) and complete the leaf.
    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    $typedDirectory = $cleanInput.Substring(0, $separatorIndex + 1)
    $leaf = $cleanInput.Substring($separatorIndex + 1)
    $parent = if ($typedDirectory) { $typedDirectory } else { '.' }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $items = @(Get-ChildItem -LiteralPath $parent -Filter $filter -ErrorAction Ignore)
    if ($DirectoriesOnly) {
        $items = @($items | Where-Object { $_.PSIsContainer })
    }

    foreach ($item in $items) {
        $completionText = if ($typedDirectory) {
            $typedDirectory + $item.Name
        } elseif ($item.Name -match '^[-@#\u2013-\u2015]') {
            # A bare name that starts with a dash, '@' or '#' would read as a parameter,
            # a splat or a comment, so anchor it to the current directory.
            '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        } else {
            $item.Name
        }

        if ($item.PSIsContainer -and -not $completionText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionText += [System.IO.Path]::DirectorySeparatorChar
        }

        $completionText = $Prefix + (ConvertTo-WcQuotedValue -Value $completionText -QuoteChar $quoteChar)

        New-WcCompletionResult -CompletionText $completionText -ListItemText $item.Name -ResultType 'ParameterValue' -ToolTip $item.FullName
    }
}

function New-WcLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-WcCompletionResult -CompletionText ($Prefix + $Placeholder) -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-WcCompletionResult -CompletionText ($Prefix + $CurrentValue) -ListItemText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-WcEnumValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }

    foreach ($value in @($Values)) {
        if ($value -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*')) {
            New-WcCompletionResult -CompletionText ($Prefix + $value) -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }
}

function Get-WcEnumOrLiteralValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $results = @(Get-WcEnumValueResults -Values $Values -CurrentValue $CurrentValue -ToolTip $ToolTip -Prefix $Prefix)
    if ($results.Count -gt 0) {
        return $results
    }

    New-WcLiteralValueResults -CurrentValue $CurrentValue -Placeholder $Placeholder -ToolTip $ToolTip -Prefix $Prefix
}

function Get-WcPathValueResults {
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
        [void]$results.Add((New-WcCompletionResult -CompletionText ($Prefix + '-') -ResultType 'ParameterValue' -ToolTip 'Read this value from standard input.'))
    }

    foreach ($item in @(Get-WcPathCompletions -InputPath $typedValue -Prefix $Prefix -DirectoriesOnly:$DirectoriesOnly)) {
        [void]$results.Add($item)
    }

    if ($results.Count -gt 0) {
        return @($results.ToArray())
    }

    New-WcLiteralValueResults -CurrentValue $typedValue -Placeholder $Placeholder -ToolTip $ToolTip -Prefix $Prefix
}

function Get-WcValueCompletions {
    param(
        [pscustomobject]$OptionSpec,
        [string]$CurrentValue,
        [string]$Prefix = ''
    )

    $catalog = Get-WcCompletionCatalog
    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $toolTip = if ([string]::IsNullOrWhiteSpace($OptionSpec.Description)) { $OptionSpec.DisplayText } else { $OptionSpec.Description }

    switch ($OptionSpec.ValueKind) {
        'Total' {
            return @(Get-WcEnumOrLiteralValueResults -Values $catalog.TotalValues -CurrentValue (ConvertFrom-WcTypedWord -Value $typedValue) -Placeholder '<when>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'FilesFrom' {
            return @(Get-WcPathValueResults -CurrentValue $typedValue -Placeholder '<F>' -ToolTip $toolTip -Prefix $Prefix -AllowStdinSentinel)
        }
        default {
            return New-WcLiteralValueResults -CurrentValue $typedValue -Placeholder '<value>' -ToolTip $toolTip -Prefix $Prefix
        }
    }
}

function Get-WcOptionKey {
    param([string]$Token)

    $cleanToken = Remove-WcOuterQuotes -Value $Token
    if ($cleanToken -match '^(--[A-Za-z0-9][A-Za-z0-9\-]*)') {
        return Get-WcCanonicalOptionKey -Token $matches[1]
    }

    if ($cleanToken -match '^(-[^=\s]+)$') {
        return Get-WcCanonicalOptionKey -Token $matches[1]
    }

    $null
}

function Get-WcCompletionContext {
    param([string[]]$TokensBeforeCurrent)

    Initialize-WcCompletionCatalog
    $catalog = Get-WcCompletionCatalog

    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingOption = $null
    $endOfOptions = $false

    foreach ($token in @($TokensBeforeCurrent)) {
        $cleanToken = Remove-WcOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($pendingOption) {
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

        if ($cleanToken -match '^(--[^=]+)=(.*)$') {
            $lookup = Get-WcCanonicalOptionKey -Token $matches[1]
            if ($catalog.OptionByToken.ContainsKey($lookup)) {
                continue
            }
        }

        $lookup = Get-WcOptionKey -Token $cleanToken
        if ($lookup -and $catalog.OptionByToken.ContainsKey($lookup)) {
            $option = $catalog.OptionByToken[$lookup]

            # Both value-bearing wc options (--total and --files0-from) always consume their
            # value, so a separate-token form opens a pending value slot.
            if ($option.ValueKind) {
                $pendingOption = $option
            }
            continue
        }

        # Unknown leading-`-` tokens (short clusters such as -lw, unknown flags) are treated as
        # consumed boolean switches: they neither become positionals nor open a pending value slot.
        if ($cleanToken.StartsWith('-')) {
            continue
        }

        $positionals.Add($cleanToken)
    }

    [pscustomobject]@{
        PendingOption = $pendingOption
        EndOfOptions  = $endOfOptions
        Positionals   = @($positionals)
    }
}

function Get-WcOptionCompletions {
    param([string]$CurrentWord)

    Initialize-WcCompletionCatalog
    $catalog = Get-WcCompletionCatalog
    $cleanCurrent = Remove-WcOuterQuotes -Value $CurrentWord

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
        New-WcCompletionResult -CompletionText $option.Token -ListItemText $option.DisplayText -ResultType 'ParameterName' -ToolTip $toolTip
    }
}

function Get-WcPositionalCompletions {
    param([string]$CurrentWord)

    # wc operands are uniformly file paths; the stdin `-` sentinel is also valid here.
    @(Get-WcPathValueResults -CurrentValue $CurrentWord -Placeholder '<file>' -ToolTip 'File to count (or - for standard input).' -AllowStdinSentinel)
}

Register-ArgumentCompleter -Native -CommandName 'wc', 'wc.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    if ($wordToComplete -isnot [string]) {
        $wordToComplete = [string]$wordToComplete
    }

    Initialize-WcCompletionCatalog
    $catalog = Get-WcCompletionCatalog

    # A cursor on a fresh token after trailing whitespace sits in no element, so the
    # current token is empty and terminal/positional routing runs.
    $currentToken = Get-WcCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition
    $tokensBeforeCurrent = Get-WcArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition
    $context = Get-WcCompletionContext -TokensBeforeCurrent $tokensBeforeCurrent

    if ($currentToken -match '^(--[^=]+)=(.*)$') {
        $optionKey = Get-WcCanonicalOptionKey -Token $matches[1]
        $valuePrefix = $matches[2]
        if ($catalog.OptionByToken.ContainsKey($optionKey)) {
            $optionSpec = $catalog.OptionByToken[$optionKey]
            if ($optionSpec.ValueKind) {
                return @(Get-WcValueCompletions -OptionSpec $optionSpec -CurrentValue $valuePrefix -Prefix ($matches[1] + '='))
            }
        }
    }

    if ($context.PendingOption) {
        return @(Get-WcValueCompletions -OptionSpec $context.PendingOption -CurrentValue $currentToken)
    }

    if ($currentToken.StartsWith('-')) {
        return @(Get-WcOptionCompletions -CurrentWord $wordToComplete)
    }

    @(Get-WcPositionalCompletions -CurrentWord $currentToken)
}
