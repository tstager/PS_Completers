# grep tab completion for PowerShell
# Builds a help-driven option catalog for grep.exe and adds value-aware completion.
# The catalog parser is format-agnostic: it understands both the clap-based coreutils
# synopsis style (`-x, --long <PLACEHOLDER>` with inline [possible values: ...]) and
# GNU grep 3.x style (`--long=PLACEHOLDER` with inline descriptions, no --group-separator),
# so the same script adapts to whichever build resolves first on PATH.

Set-StrictMode -Version 2.0

function New-GrepCompletionResult {
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

function Get-GrepBinaryFilesValues {
    @('binary', 'text', 'without-match')
}

function Get-GrepDirectoriesValues {
    @('read', 'skip', 'recurse')
}

function Get-GrepDevicesValues {
    @('read', 'skip')
}

function Get-GrepColorWhenValues {
    @('always', 'never', 'auto')
}

function Get-GrepCompletionCatalog {
    if (Get-Variable -Name GrepCompletionCatalog -Scope Script -ErrorAction Ignore) {
        return $script:GrepCompletionCatalog
    }

    $script:GrepCompletionCatalog = @{
        Initialized        = $false
        CommandName        = $null
        Options            = @()
        OptionByToken      = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        BinaryFilesValues  = Get-GrepBinaryFilesValues
        DirectoriesValues  = Get-GrepDirectoriesValues
        DevicesValues      = Get-GrepDevicesValues
        ColorWhenValues    = Get-GrepColorWhenValues
    }

    $script:GrepCompletionCatalog
}

function Resolve-GrepCommandName {
    $catalog = Get-GrepCompletionCatalog
    if ($catalog.CommandName) {
        return $catalog.CommandName
    }

    $command = Get-Command -Name grep.exe, grep -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $catalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $catalog.CommandName
}

function Invoke-GrepCapture {
    param([string[]]$Arguments)

    $commandName = Resolve-GrepCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>$null)
    } catch {
        @()
    }
}

function Remove-GrepOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-GrepQuotedValue {
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

function Get-GrepTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-GrepCurrentToken {
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

function Get-GrepArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += Get-GrepTokenText -Element $element
        }
    }

    $tokens
}

function Get-GrepValueKind {
    param(
        [string]$Token,
        [string]$Placeholder
    )

    $tokenKey = if ($Token.StartsWith('--')) { $Token.ToLowerInvariant() } else { $Token }
    $placeholderKey = if ([string]::IsNullOrWhiteSpace($Placeholder)) { '' } else { $Placeholder.ToUpperInvariant() }

    switch -CaseSensitive ($tokenKey) {
        '-m' { return 'Number' }
        '--max-count' { return 'Number' }
        '-A' { return 'Number' }
        '--after-context' { return 'Number' }
        '-B' { return 'Number' }
        '--before-context' { return 'Number' }
        '-C' { return 'Number' }
        '--context' { return 'Number' }
        '--binary-files' { return 'BinaryFiles' }
        '-d' { return 'DirectoriesAction' }
        '--directories' { return 'DirectoriesAction' }
        '-D' { return 'DevicesAction' }
        '--devices' { return 'DevicesAction' }
        '--color' { return 'ColorWhen' }
        '--include' { return 'Glob' }
        '--exclude' { return 'Glob' }
        '--exclude-dir' { return 'Glob' }
        '-e' { return 'Pattern' }
        '--regexp' { return 'Pattern' }
        '-f' { return 'PatternFilePathOrStdin' }
        '--file' { return 'PatternFilePathOrStdin' }
        '--exclude-from' { return 'FilePath' }
        '--label' { return 'Label' }
        '--group-separator' { return 'Separator' }
    }

    switch ($placeholderKey) {
        'NUM' { return 'Number' }
        'GLOB' { return 'Glob' }
        'FILE' { return 'FilePath' }
        'PATTERNS' { return 'Pattern' }
        'LABEL' { return 'Label' }
        'SEP' { return 'Separator' }
        'WHEN' { return 'ColorWhen' }
        'TYPE' { return 'BinaryFiles' }
    }

    $null
}

function Get-GrepCanonicalOptionKey {
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

function ConvertFrom-GrepOptionSpecLine {
    param([string]$Line)

    $results = New-Object System.Collections.Generic.List[object]

    # Separate the option synopsis from any inline description. Both GNU and clap help
    # put the description after a run of two or more spaces, so cut at the first such gap.
    $specPart = ($Line -replace '^\s+', '')
    if ($specPart -match '^(?<spec>.*?\S)\s{2,}\S') {
        $specPart = $matches['spec']
    }
    $specPart = $specPart.TrimEnd()

    # Trim a trailing comma left by split alias lines such as "--color[=WHEN],".
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
                })
        }

        if ($longPart -match '^(?<token>--[A-Za-z0-9][A-Za-z0-9\-]*)(?:\[?[= ]\<?(?<value>[^\]\s>]+)\>?\]?)?$') {
            [void]$results.Add([pscustomobject]@{
                    Token       = $matches['token']
                    DisplayText = $longPart
                    Placeholder = $matches['value']
                })
        }
    } elseif ($specLine -match '^(?<token>--[A-Za-z0-9][A-Za-z0-9\-]*)(?:\[?[= ]\<?(?<value>[^\]\s>]+)\>?\]?)?$') {
        [void]$results.Add([pscustomobject]@{
                Token       = $matches['token']
                DisplayText = $specLine
                Placeholder = $matches['value']
            })
    } elseif ($specLine -match '^(?<token>-[A-Za-z0-9])(?:[= ]\[?(?<value>[^\]\s]+)\]?)?$') {
        # Short-only option line such as "  -I  equivalent to --binary-files=without-match".
        [void]$results.Add([pscustomobject]@{
                Token       = $matches['token']
                DisplayText = $specLine
                Placeholder = $matches['value']
            })
    }

    @($results.ToArray())
}

function Add-GrepOptionSpec {
    param(
        [string]$Token,
        [string]$DisplayText,
        [string]$Description,
        [string]$Placeholder
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return
    }

    $catalog = Get-GrepCompletionCatalog
    $key = Get-GrepCanonicalOptionKey -Token $Token
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
        ValueKind   = Get-GrepValueKind -Token $Token -Placeholder $Placeholder
    }

    $catalog.Options += $catalog.OptionByToken[$key]
}

function Initialize-GrepCompletionCatalog {
    $catalog = Get-GrepCompletionCatalog
    if ($catalog.Initialized) {
        return
    }

    $helpLines = Invoke-GrepCapture -Arguments @('--help')
    $currentKeys = @()

    foreach ($line in @($helpLines)) {
        # A synopsis line is indented and begins (after indent) with an option token:
        #   short pair "-x, --long", long-only "    --long", or short-only "  -I".
        # The "-NUM" pseudo option (grep context shortcut) is intentionally skipped.
        $isSynopsis = ($line -match '^\s{2,}-[A-Za-z](?:[, =\[]|$)' -or $line -match '^\s{2,}--[A-Za-z0-9]') -and
            ($line -notmatch '^\s{2,}-NUM\b')

        if ($isSynopsis) {
            $parsed = @(ConvertFrom-GrepOptionSpecLine -Line $line)
            if ($parsed.Count -gt 0) {
                $currentKeys = @()

                foreach ($spec in $parsed) {
                    Add-GrepOptionSpec -Token $spec.Token -DisplayText $spec.DisplayText -Description $spec.DisplayText -Placeholder $spec.Placeholder
                    $currentKeys += Get-GrepCanonicalOptionKey -Token $spec.Token
                }

                continue
            }
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

    $catalog.Initialized = $true
}

function Get-GrepPathCompletions {
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
        $completionText = if ($cleanInput -and -not [System.IO.Path]::IsPathRooted($cleanInput)) {
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

        $completionText = ConvertTo-GrepQuotedValue -Value $completionText -AlwaysQuote $alwaysQuote
        $completionText = $Prefix + $completionText

        New-GrepCompletionResult -CompletionText $completionText -ListItemText $item.Name -ResultType 'ParameterValue' -ToolTip $item.FullName
    }
}

function New-GrepLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-GrepCompletionResult -CompletionText ($Prefix + $Placeholder) -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-GrepCompletionResult -CompletionText ($Prefix + $CurrentValue) -ListItemText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-GrepEnumValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }

    foreach ($value in @($Values)) {
        if ($value -like "$typedValue*") {
            New-GrepCompletionResult -CompletionText ($Prefix + $value) -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }
}

function Get-GrepEnumOrLiteralValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $results = @(Get-GrepEnumValueResults -Values $Values -CurrentValue $CurrentValue -ToolTip $ToolTip -Prefix $Prefix)
    if ($results.Count -gt 0) {
        return $results
    }

    New-GrepLiteralValueResults -CurrentValue $CurrentValue -Placeholder $Placeholder -ToolTip $ToolTip -Prefix $Prefix
}

function Get-GrepPathValueResults {
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

    if ($AllowStdinSentinel -and ('-' -like "$typedValue*")) {
        [void]$results.Add((New-GrepCompletionResult -CompletionText ($Prefix + '-') -ResultType 'ParameterValue' -ToolTip 'Read this value from standard input.'))
    }

    foreach ($item in @(Get-GrepPathCompletions -InputPath $typedValue -Prefix $Prefix -DirectoriesOnly:$DirectoriesOnly)) {
        [void]$results.Add($item)
    }

    if ($results.Count -gt 0) {
        return @($results.ToArray())
    }

    New-GrepLiteralValueResults -CurrentValue $typedValue -Placeholder $Placeholder -ToolTip $ToolTip -Prefix $Prefix
}

function Get-GrepValueCompletions {
    param(
        [pscustomobject]$OptionSpec,
        [string]$CurrentValue,
        [string]$Prefix = ''
    )

    $catalog = Get-GrepCompletionCatalog
    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $toolTip = if ([string]::IsNullOrWhiteSpace($OptionSpec.Description)) { $OptionSpec.DisplayText } else { $OptionSpec.Description }

    switch ($OptionSpec.ValueKind) {
        'Pattern' {
            return New-GrepLiteralValueResults -CurrentValue $typedValue -Placeholder '<pattern>' -ToolTip $toolTip -Prefix $Prefix
        }
        'Glob' {
            return New-GrepLiteralValueResults -CurrentValue $typedValue -Placeholder '<glob>' -ToolTip $toolTip -Prefix $Prefix
        }
        'Label' {
            return New-GrepLiteralValueResults -CurrentValue $typedValue -Placeholder '<label>' -ToolTip $toolTip -Prefix $Prefix
        }
        'Separator' {
            return New-GrepLiteralValueResults -CurrentValue $typedValue -Placeholder '<sep>' -ToolTip $toolTip -Prefix $Prefix
        }
        'PatternFilePathOrStdin' {
            return @(Get-GrepPathValueResults -CurrentValue $typedValue -Placeholder '<pattern-file>' -ToolTip $toolTip -Prefix $Prefix -AllowStdinSentinel)
        }
        'FilePath' {
            return @(Get-GrepPathValueResults -CurrentValue $typedValue -Placeholder '<file>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'BinaryFiles' {
            return @(Get-GrepEnumOrLiteralValueResults -Values $catalog.BinaryFilesValues -CurrentValue $typedValue -Placeholder '<type>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'DirectoriesAction' {
            return @(Get-GrepEnumOrLiteralValueResults -Values $catalog.DirectoriesValues -CurrentValue $typedValue -Placeholder '<action>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'DevicesAction' {
            return @(Get-GrepEnumOrLiteralValueResults -Values $catalog.DevicesValues -CurrentValue $typedValue -Placeholder '<action>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'ColorWhen' {
            return @(Get-GrepEnumOrLiteralValueResults -Values $catalog.ColorWhenValues -CurrentValue $typedValue -Placeholder '<when>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'Number' {
            return @(Get-GrepEnumOrLiteralValueResults -Values @('0', '1', '2', '5', '10', '100') -CurrentValue $typedValue -Placeholder '<num>' -ToolTip $toolTip -Prefix $Prefix)
        }
        default {
            return New-GrepLiteralValueResults -CurrentValue $typedValue -Placeholder '<value>' -ToolTip $toolTip -Prefix $Prefix
        }
    }
}

function Get-GrepOptionKey {
    param([string]$Token)

    $cleanToken = Remove-GrepOuterQuotes -Value $Token
    if ($cleanToken -match '^(--[A-Za-z0-9][A-Za-z0-9\-]*)') {
        return Get-GrepCanonicalOptionKey -Token $matches[1]
    }

    if ($cleanToken -match '^(-[^=\s]+)$') {
        return Get-GrepCanonicalOptionKey -Token $matches[1]
    }

    $null
}

function Get-GrepAttachedShortOption {
    param([string]$Token)

    $cleanToken = Remove-GrepOuterQuotes -Value $Token
    if ($cleanToken -match '^(?<flag>-(?:e|f|m|A|B|C|D|d))(?<value>.+)$') {
        [pscustomobject]@{
            Flag  = $matches['flag']
            Value = $matches['value']
        }
        return
    }

    $null
}

function Get-GrepCompletionContext {
    param([string[]]$TokensBeforeCurrent)

    Initialize-GrepCompletionCatalog
    $catalog = Get-GrepCompletionCatalog

    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingOption = $null
    $endOfOptions = $false
    $hasPatternSource = $false

    foreach ($token in @($TokensBeforeCurrent)) {
        $cleanToken = Remove-GrepOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($pendingOption) {
            if ($pendingOption.ValueKind -in @('Pattern', 'PatternFilePathOrStdin')) {
                $hasPatternSource = $true
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

        $attached = Get-GrepAttachedShortOption -Token $cleanToken
        $attachedKey = if ($attached) { Get-GrepCanonicalOptionKey -Token $attached.Flag } else { $null }
        if ($attachedKey -and $catalog.OptionByToken.ContainsKey($attachedKey)) {
            $option = $catalog.OptionByToken[$attachedKey]
            if ($option.ValueKind -in @('Pattern', 'PatternFilePathOrStdin')) {
                $hasPatternSource = $true
            }
            continue
        }

        if ($cleanToken -match '^(--[^=]+)=(.*)$') {
            $lookup = Get-GrepCanonicalOptionKey -Token $matches[1]
            if ($catalog.OptionByToken.ContainsKey($lookup)) {
                $option = $catalog.OptionByToken[$lookup]
                if ($option.ValueKind -in @('Pattern', 'PatternFilePathOrStdin')) {
                    $hasPatternSource = $true
                }
                continue
            }
        }

        $lookup = Get-GrepOptionKey -Token $cleanToken
        if ($lookup -and $catalog.OptionByToken.ContainsKey($lookup)) {
            $option = $catalog.OptionByToken[$lookup]

            # --color is an optional-value flag (--color[=<WHEN>]); a bare --color does not consume the
            # next token as its value, so it must not become a pending value option.
            if ($option.ValueKind -and $option.Token -ne '--color') {
                $pendingOption = $option
            }
            continue
        }

        # Unknown leading-`-` tokens (short clusters such as -rni, unknown flags) are treated as
        # consumed boolean switches: they neither become positionals nor open a pending value slot.
        if ($cleanToken.StartsWith('-')) {
            continue
        }

        $positionals.Add($cleanToken)
    }

    [pscustomobject]@{
        PendingOption    = $pendingOption
        EndOfOptions     = $endOfOptions
        HasPatternSource = $hasPatternSource
        Positionals      = @($positionals)
    }
}

function Get-GrepOptionCompletions {
    param([string]$CurrentWord)

    Initialize-GrepCompletionCatalog
    $catalog = Get-GrepCompletionCatalog
    $cleanCurrent = Remove-GrepOuterQuotes -Value $CurrentWord

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
        New-GrepCompletionResult -CompletionText $option.Token -ListItemText $option.DisplayText -ResultType 'ParameterName' -ToolTip $toolTip
    }
}

function Get-GrepPositionalCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$Context
    )

    if ($Context.HasPatternSource -or $Context.Positionals.Count -gt 0) {
        return @(Get-GrepPathValueResults -CurrentValue $CurrentWord -Placeholder '<file>' -ToolTip 'File or directory to search.')
    }

    New-GrepLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<pattern>' -ToolTip 'Pattern to search for.'
}

Register-ArgumentCompleter -Native -CommandName 'grep', 'grep.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    if ($wordToComplete -isnot [string]) {
        $wordToComplete = [string]$wordToComplete
    }

    Initialize-GrepCompletionCatalog
    $catalog = Get-GrepCompletionCatalog

    # When the cursor sits past the parsed command extent the user is on a fresh
    # token after trailing whitespace, which $commandAst.Extent.Text has trimmed
    # away. Treat that as an empty current token so terminal/positional routing
    # runs instead of falling through to the option-name branch.
    $currentToken = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-GrepCurrentToken -Line $commandAst.Extent.Text -CursorPosition $cursorPosition -Fallback $wordToComplete
    }
    $tokensBeforeCurrent = Get-GrepArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition
    $context = Get-GrepCompletionContext -TokensBeforeCurrent $tokensBeforeCurrent

    if ($currentToken -match '^(--[^=]+)=(.*)$') {
        $optionKey = Get-GrepCanonicalOptionKey -Token $matches[1]
        $valuePrefix = $matches[2]
        if ($catalog.OptionByToken.ContainsKey($optionKey)) {
            $optionSpec = $catalog.OptionByToken[$optionKey]
            if ($optionSpec.ValueKind) {
                return @(Get-GrepValueCompletions -OptionSpec $optionSpec -CurrentValue $valuePrefix -Prefix ($matches[1] + '='))
            }
        }
    }

    if ($currentToken -match '^(?<flag>-(?:e|f|m|A|B|C|D|d))(?<value>.+)$') {
        $optionKey = Get-GrepCanonicalOptionKey -Token $matches['flag']
        if ($catalog.OptionByToken.ContainsKey($optionKey)) {
            return @(Get-GrepValueCompletions -OptionSpec $catalog.OptionByToken[$optionKey] -CurrentValue $matches['value'] -Prefix $matches['flag'])
        }
    }

    if ($context.PendingOption) {
        return @(Get-GrepValueCompletions -OptionSpec $context.PendingOption -CurrentValue $wordToComplete)
    }

    if ($currentToken.StartsWith('-')) {
        return @(Get-GrepOptionCompletions -CurrentWord $wordToComplete)
    }

    @(Get-GrepPositionalCompletions -CurrentWord $wordToComplete -Context $context)
}
