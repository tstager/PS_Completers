# 7z tab completion for PowerShell
# Builds completion data from 7z built-in help.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name SevenZipCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:SevenZipCompletionCatalog = @{
        Initialized         = $false
        HelpCommand         = $null
        Commands            = @()
        CommandDescriptions = @{}
        SwitchTokens        = @()
        SwitchDescriptions  = @{}
        ValueHintsBySwitch  = @{}
        ValueSwitches       = @()
        PathLikeSwitches    = @('-o', '-w')
        ArchiveTypeSwitches = @('-t', '-stx')
        MethodSwitches      = @('-m', '-mx', '-mmt')
        ArchiveTypes        = @()
        ArchiveTypesLoaded  = $false
    }
}

function Resolve-SevenZipHelpCommand {
    if ($script:SevenZipCompletionCatalog.HelpCommand) {
        return $script:SevenZipCompletionCatalog.HelpCommand
    }

    $command = Get-Command -Name 7z.exe, 7z -ErrorAction Ignore | Select-Object -First 1
    if ($command) {
        $script:SevenZipCompletionCatalog.HelpCommand = $command.Name
    }

    $script:SevenZipCompletionCatalog.HelpCommand
}

function Invoke-SevenZipHelpText {
    $commandName = Resolve-SevenZipHelpCommand
    if (-not $commandName) {
        return @()
    }

    try {
        @($null | & $commandName --help 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })
    } catch {
        @()
    }
}

function Get-SevenZipNormalizedHelpText {
    param([string[]]$Lines)

    if (-not $Lines -or $Lines.Count -eq 0) {
        return ''
    }

    $text = $Lines -join "`n"
    foreach ($marker in @('Usage:', '<Commands>', '<Switches>')) {
        $text = $text -replace [regex]::Escape($marker), ("`n" + $marker)
    }

    $text.Trim()
}

function Get-SevenZipHelpSectionLines {
    param(
        [string[]]$Lines,
        [string]$StartHeader,
        [string]$EndHeader
    )

    $text = Get-SevenZipNormalizedHelpText -Lines $Lines
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }

    $startPattern = [regex]::Escape($StartHeader)
    if ([string]::IsNullOrWhiteSpace($EndHeader)) {
        $pattern = "(?s)$startPattern\s*(.*)$"
    } else {
        $endPattern = [regex]::Escape($EndHeader)
        $pattern = "(?s)$startPattern\s*(.*?)(?=$endPattern)"
    }

    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) {
        return @()
    }

    @($match.Groups[1].Value -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-SevenZipCommandEntryList {
    param([string[]]$Lines)

    $commandLines = Get-SevenZipHelpSectionLines -Lines $Lines -StartHeader '<Commands>' -EndHeader '<Switches>'
    foreach ($line in $commandLines) {
        if ($line -match '^\s*([a-z][a-z0-9]*)\s*:\s*(.*)$') {
            @{ Token = $matches[1]; Description = $matches[2].Trim() }
        }
    }
}

function Get-SevenZipSwitchEntryList {
    param([string[]]$Lines)

    # A switch line is '<token><syntax> : <description>' where the syntax part is the
    # value grammar 7-Zip prints, e.g. '{o|e|p}{0|1|2}', '[r[-|0]][m[-|2]]{@listfile|!wildcard}'.
    $switchLines = Get-SevenZipHelpSectionLines -Lines $Lines -StartHeader '<Switches>'
    foreach ($line in $switchLines) {
        if ($line -match '^\s*(?<token>--|-[A-Za-z][A-Za-z0-9]*)(?<syntax>[\[{][^\s:]*)?\s*:\s*(?<description>.*)$') {
            @{
                Token       = $matches['token']
                Syntax      = if ($matches['syntax']) { $matches['syntax'] } else { '' }
                Description = $matches['description'].Trim()
            }
        }
    }
}

# --- Value syntax grammar -------------------------------------------------------------------
#
# The syntax after a switch token is parsed into a tree of items:
#   @{ Kind = 'Literal';     Text = 'r' }
#   @{ Kind = 'Placeholder'; Name = 'Size'; Type = 'Numeric' | 'Text' | 'File' }
#   @{ Kind = 'Group';       Optional = $true/$false; Alternatives = @(@(items), @(items), ...) }
# '{...}' is a required group, '[...]' an optional one, '|' separates alternatives, a lone
# '{Word}' is a metavariable placeholder, 'N'/'#' are numeric placeholders and '@name'/'!name'
# are a sigil followed by a file or wildcard placeholder.

function ConvertTo-SevenZipSyntaxItemList {
    param([string]$LiteralRun)

    if ([string]::IsNullOrEmpty($LiteralRun)) {
        return @()
    }

    if ($LiteralRun -match '^(?<sigil>[@!])(?<name>[A-Za-z][A-Za-z0-9]*)$') {
        return @(
            @{ Kind = 'Literal'; Text = $matches['sigil'] }
            @{ Kind = 'Placeholder'; Name = $matches['name']; Type = 'File' }
        )
    }

    if ($LiteralRun -eq 'N') {
        return @(@{ Kind = 'Placeholder'; Name = 'N'; Type = 'Numeric' })
    }

    if ($LiteralRun -match '^(?<text>[^#]*)#$') {
        return @(
            (ConvertTo-SevenZipSyntaxItemList -LiteralRun $matches['text'])
            @{ Kind = 'Placeholder'; Name = '#'; Type = 'Numeric' }
        )
    }

    if ($LiteralRun -cmatch '^[A-Z][A-Za-z]{3,}$') {
        $type = if ($LiteralRun -eq 'Size') { 'Numeric' } else { 'Text' }
        return @(@{ Kind = 'Placeholder'; Name = $LiteralRun; Type = $type })
    }

    @(@{ Kind = 'Literal'; Text = $LiteralRun })
}

function Read-SevenZipSyntaxSequence {
    param(
        [hashtable]$Reader,
        [string]$StopChars
    )

    $items = New-Object System.Collections.Generic.List[object]
    $text = $Reader.Text

    while ($Reader.Position -lt $text.Length) {
        $char = $text[$Reader.Position]
        if ($StopChars.IndexOf($char) -ge 0) {
            break
        }

        if ($char -eq '{' -or $char -eq '[') {
            $group = Read-SevenZipSyntaxGroup -Reader $Reader
            if ($null -ne $group) {
                [void]$items.Add($group)
            }

            continue
        }

        $start = $Reader.Position
        while ($Reader.Position -lt $text.Length -and '{[|]}'.IndexOf($text[$Reader.Position]) -lt 0) {
            $Reader.Position++
        }

        foreach ($item in @(ConvertTo-SevenZipSyntaxItemList -LiteralRun $text.Substring($start, $Reader.Position - $start))) {
            [void]$items.Add($item)
        }
    }

    @($items.ToArray())
}

function Read-SevenZipSyntaxGroup {
    param([hashtable]$Reader)

    $text = $Reader.Text
    $open = $text[$Reader.Position]
    $optional = $open -eq '['
    $close = if ($optional) { ']' } else { '}' }
    $Reader.Position++

    $alternatives = New-Object System.Collections.Generic.List[object]
    while ($true) {
        $sequence = @(Read-SevenZipSyntaxSequence -Reader $Reader -StopChars '|]}')
        [void]$alternatives.Add($sequence)

        if ($Reader.Position -lt $text.Length -and $text[$Reader.Position] -eq '|') {
            $Reader.Position++
            continue
        }

        break
    }

    if ($Reader.Position -lt $text.Length -and $text[$Reader.Position] -eq $close) {
        $Reader.Position++
    }

    if ($alternatives.Count -eq 1) {
        $only = @($alternatives[0])
        if ($only.Count -eq 1 -and $only[0].Kind -eq 'Literal') {
            $literal = [string]$only[0].Text

            # '[0-3]' is a numeric range; '{Word}' on its own is a metavariable, not a value.
            if ($literal -match '^(\d+)-(\d+)$' -and [int]$matches[1] -le [int]$matches[2]) {
                $alternatives.Clear()
                foreach ($number in ([int]$matches[1])..([int]$matches[2])) {
                    [void]$alternatives.Add(@(@{ Kind = 'Literal'; Text = $number.ToString() }))
                }
            } elseif (-not $optional) {
                $type = if ($literal -eq 'Size') { 'Numeric' } else { 'Text' }
                return @{ Kind = 'Placeholder'; Name = $literal; Type = $type }
            }
        }
    }

    @{ Kind = 'Group'; Optional = $optional; Alternatives = @($alternatives.ToArray()) }
}

function ConvertFrom-SevenZipSwitchSyntax {
    param([string]$Syntax)

    if ([string]::IsNullOrWhiteSpace($Syntax)) {
        return @()
    }

    $reader = @{ Text = $Syntax; Position = 0 }
    @(Read-SevenZipSyntaxSequence -Reader $reader -StopChars '')
}

function Get-SevenZipSyntaxCandidateList {
    param(
        $Pending,
        [string]$Prefix,
        [string]$Typed,
        [bool]$Extended,
        [System.Collections.Generic.List[object]]$Sink
    )

    # Walks the grammar against the typed value. Items matched by typed text are consumed; once
    # the typed text is exhausted the walk extends through literals and required groups and
    # emits a candidate when it stops (end of grammar, an optional group, or a placeholder).
    # Reaching the end of the grammar with the typed text fully consumed is a complete value too
    # (nothing at all for '-sns[-]', '-' for '-r[-|0]'), so it is emitted as well.
    # $Pending stays untyped: a typed [object[]] binder rejects the nested hashtable arrays.
    $pendingItems = @($Pending)
    if ($pendingItems.Count -eq 0) {
        if ([string]::IsNullOrEmpty($Typed)) {
            [void]$Sink.Add(@{ Kind = 'Value'; Text = $Prefix })
        }

        return
    }

    $item = $pendingItems[0]
    $rest = @($pendingItems | Select-Object -Skip 1)

    switch ($item.Kind) {
        'Literal' {
            $literal = [string]$item.Text
            if ($Typed.StartsWith($literal, [System.StringComparison]::OrdinalIgnoreCase)) {
                Get-SevenZipSyntaxCandidateList -Pending $rest -Prefix ($Prefix + $literal) -Typed $Typed.Substring($literal.Length) -Extended $Extended -Sink $Sink
            } elseif ($literal.StartsWith($Typed, [System.StringComparison]::OrdinalIgnoreCase)) {
                Get-SevenZipSyntaxCandidateList -Pending $rest -Prefix ($Prefix + $literal) -Typed '' -Extended $true -Sink $Sink
            }
        }
        'Placeholder' {
            switch ($item.Type) {
                'Numeric' {
                    if ($Typed -match '^\d+') {
                        Get-SevenZipSyntaxCandidateList -Pending $rest -Prefix ($Prefix + $matches[0]) -Typed $Typed.Substring($matches[0].Length) -Extended $Extended -Sink $Sink
                    } elseif ($Extended -and [string]::IsNullOrEmpty($Typed)) {
                        [void]$Sink.Add(@{ Kind = 'Value'; Text = $Prefix })
                    }
                }
                'File' {
                    if ($Extended -and [string]::IsNullOrEmpty($Typed)) {
                        [void]$Sink.Add(@{ Kind = 'Value'; Text = ($Prefix + '<' + $item.Name + '>') })
                    } elseif (-not $Extended) {
                        [void]$Sink.Add(@{ Kind = 'File'; Prefix = $Prefix; Typed = $Typed })
                    }
                }
                default {
                    if ($Extended -and [string]::IsNullOrEmpty($Typed)) {
                        [void]$Sink.Add(@{ Kind = 'Value'; Text = $Prefix })
                    }
                }
            }
        }
        'Group' {
            if ($item.Optional -and $Extended) {
                if ([string]::IsNullOrEmpty($Typed)) {
                    [void]$Sink.Add(@{ Kind = 'Value'; Text = $Prefix })
                }

                return
            }

            foreach ($alternative in @($item.Alternatives)) {
                Get-SevenZipSyntaxCandidateList -Pending (@($alternative) + $rest) -Prefix $Prefix -Typed $Typed -Extended $Extended -Sink $Sink
            }

            if ($item.Optional) {
                Get-SevenZipSyntaxCandidateList -Pending $rest -Prefix $Prefix -Typed $Typed -Extended $Extended -Sink $Sink
            }
        }
    }
}

function Get-SevenZipArchiveTypeList {
    if ($script:SevenZipCompletionCatalog.ArchiveTypesLoaded) {
        return $script:SevenZipCompletionCatalog.ArchiveTypes
    }

    $script:SevenZipCompletionCatalog.ArchiveTypesLoaded = $true

    $commandName = Resolve-SevenZipHelpCommand
    if (-not $commandName) {
        return $script:SevenZipCompletionCatalog.ArchiveTypes
    }

    $raw = try {
        $null | & $commandName i 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' }
    } catch {
        @()
    }

    # The 'Formats:' table lists one archive format per line as
    # '<index> <flags>  <Name>  <extensions>  <signature>'. The flag column can contain spaces, so
    # the name is the first single-word field that is neither the index nor the dotted flag string.
    $inFormats = $false
    $names = foreach ($line in @($raw)) {
        if ($line -match '^Formats:') {
            $inFormats = $true
            continue
        }

        if ($inFormats -and $line -match '^\S') {
            $inFormats = $false
        }

        if (-not $inFormats) {
            continue
        }

        foreach ($field in @($line -split '\s{2,}')) {
            $words = @($field.Trim() -split '\s+' | Where-Object { $_ })
            if ($words.Count -eq 0) {
                continue
            }

            $first = $words[0]
            if ($first -match '^\d+$' -or $first -match '^[.]+$') {
                continue
            }

            if ($first -match '^[A-Za-z0-9][A-Za-z0-9]*$') {
                $first.ToLowerInvariant()
                break
            }
        }
    }

    $script:SevenZipCompletionCatalog.ArchiveTypes = @(@($names) | Sort-Object -Unique)
    $script:SevenZipCompletionCatalog.ArchiveTypes
}

function Initialize-SevenZipCompletionCatalog {
    if ($script:SevenZipCompletionCatalog.Initialized) {
        return
    }

    $helpLines = Invoke-SevenZipHelpText
    if ($helpLines -and $helpLines.Count -gt 0) {
        $commandDescriptions = @{}
        foreach ($entry in @(Get-SevenZipCommandEntryList -Lines $helpLines)) {
            $commandDescriptions[$entry.Token] = $entry.Description
        }

        $switchDescriptions = @{}
        $valueHints = @{}
        foreach ($entry in @(Get-SevenZipSwitchEntryList -Lines $helpLines)) {
            $switchDescriptions[$entry.Token] = $entry.Description
            $items = @(ConvertFrom-SevenZipSwitchSyntax -Syntax $entry.Syntax)
            if ($items.Count -gt 0) {
                $valueHints[$entry.Token.ToLowerInvariant()] = $items
            }
        }

        $script:SevenZipCompletionCatalog.Commands = @($commandDescriptions.Keys | Sort-Object -Unique)
        $script:SevenZipCompletionCatalog.CommandDescriptions = $commandDescriptions
        $script:SevenZipCompletionCatalog.SwitchTokens = @($switchDescriptions.Keys | Sort-Object -Unique)
        $script:SevenZipCompletionCatalog.SwitchDescriptions = $switchDescriptions
        $script:SevenZipCompletionCatalog.ValueHintsBySwitch = $valueHints
    }

    # 7-Zip only accepts switch values attached to the switch ('-tzip', '-oC:\out'); there is no
    # space-separated and no '--switch=value' form, so only the inline shape is completed.
    $script:SevenZipCompletionCatalog.ValueSwitches = @(
        @(
            $script:SevenZipCompletionCatalog.ValueHintsBySwitch.Keys
            $script:SevenZipCompletionCatalog.PathLikeSwitches
            $script:SevenZipCompletionCatalog.ArchiveTypeSwitches
            $script:SevenZipCompletionCatalog.MethodSwitches
        ) | Sort-Object -Unique | Sort-Object Length -Descending
    )

    $script:SevenZipCompletionCatalog.Initialized = $true
}

function Get-SevenZipDescription {
    param([string]$Token)

    foreach ($table in @($script:SevenZipCompletionCatalog.SwitchDescriptions, $script:SevenZipCompletionCatalog.CommandDescriptions)) {
        if ($table.ContainsKey($Token) -and -not [string]::IsNullOrWhiteSpace($table[$Token])) {
            return $table[$Token]
        }
    }

    $Token
}

function New-SevenZipCompletionResult {
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

function Get-SevenZipLineTokens {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    # Tokenise the command text rather than CommandElements: PowerShell splits '-oC:\dir' into a
    # parameter '-oC:' plus an argument, which loses the switch. The token under the cursor is
    # the current word (its full text, even when the cursor sits inside it); text to the right of
    # it is ignored.
    # The command extent excludes trailing whitespace, so a cursor past its end is after a space.
    $safeCursor = [Math]::Max($CursorPosition, 0)
    $tokens = New-Object System.Collections.Generic.List[string]
    $current = ''
    $currentStart = $safeCursor
    $afterWhitespace = $true

    # A quoted run of either kind (even unterminated, typographic quotes included) stays inside
    # its word, as PowerShell reads it; so does a backtick-escaped character.
    $wordPattern = '(?:`.?|[^\s`"''\u2018-\u201E]|["\u201C-\u201E](?:`.?|[^`"\u201C-\u201E])*["\u201C-\u201E]?|[''\u2018-\u201B][^''\u2018-\u201B]*[''\u2018-\u201B]?)+'
    foreach ($match in [regex]::Matches($Line, $wordPattern)) {
        if ($match.Index -ge $safeCursor) {
            break
        }

        $end = $match.Index + $match.Length
        if ($end -ge $safeCursor) {
            $current = $match.Value
            $currentStart = $match.Index
            $afterWhitespace = $false
            break
        }

        [void]$tokens.Add($match.Value)
    }

    @{
        Before          = @($tokens.ToArray())
        Current         = $current
        CurrentStart    = $currentStart
        AfterWhitespace = $afterWhitespace
    }
}

function Get-SevenZipReplacementStart {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    # PowerShell replaces only its own token under the cursor, and it ends a parameter token at a
    # colon ('-oC:' then '\Users') and a word at a leading '@'. Right after such a colon it
    # inserts at the cursor instead.
    $parseTokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$parseTokens, [ref]$parseErrors)
    foreach ($token in $parseTokens) {
        $extent = $token.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::Parameter -and
                $token.Text.EndsWith(':') -and $CursorPosition -eq $extent.EndOffset) {
                return $CursorPosition
            }

            return $extent.StartOffset
        }
    }

    $CursorPosition
}

function Test-SevenZipHasOptionTerminator {
    param([string[]]$TokensBeforeCurrent)

    foreach ($token in $TokensBeforeCurrent) {
        if ($token -eq '--') {
            return $true
        }
    }

    $false
}

function Get-SevenZipActiveCommand {
    param(
        [string[]]$Tokens,
        [string[]]$KnownCommands
    )

    $known = @{}
    foreach ($command in $KnownCommands) {
        $known[$command.ToLowerInvariant()] = $command
    }

    foreach ($token in $Tokens) {
        if ($token -eq '--') {
            break
        }

        $lookup = $token.ToLowerInvariant()
        if ($known.ContainsKey($lookup)) {
            return $known[$lookup]
        }
    }

    $null
}

function Get-SevenZipInlineValueSwitch {
    param(
        [string]$Token,
        [string[]]$KnownValueSwitches
    )

    if ([string]::IsNullOrWhiteSpace($Token) -or -not $Token.StartsWith('-') -or $Token -eq '--') {
        return $null
    }

    foreach ($switchToken in $KnownValueSwitches) {
        if ($Token.Length -ge $switchToken.Length -and
            $Token.Substring(0, $switchToken.Length).Equals($switchToken, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $switchToken
        }
    }

    $null
}

function Get-SevenZipTypedQuote {
    # The quote character the user opened the word with ('' when bare); PowerShell reads the
    # typographic quotes as quotes too.
    param([string]$Value)

    if ($Value -match '^[''"\u2018-\u201E]') {
        return $Value.Substring(0, 1)
    }

    ''
}

function ConvertFrom-SevenZipTypedWord {
    # The value of typed text without its quotes and that quote style's escapes.
    param([string]$Value)

    $quote = Get-SevenZipTypedQuote -Value $Value
    if (-not $quote) {
        return $Value -replace '`(.)', '$1'
    }

    $body = $Value.Substring(1)
    if ($quote -match '[''\u2018-\u201B]') {
        $inner = ([regex]::Match($body, '^(?:[^''\u2018-\u201B]|[''\u2018-\u201B]{2})*')).Value
        return $inner -replace '([''\u2018-\u201B])[''\u2018-\u201B]', '$1'
    }

    $inner = ([regex]::Match($body, '^(?:`.?|[^`"\u201C-\u201E]|["\u201C-\u201E]{2})*')).Value
    ($inner -replace '(["\u201C-\u201E])["\u201C-\u201E]', '$1') -replace '`(.)', '$1'
}

function ConvertTo-SevenZipQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the typed quote style (single by default). Whitespace and argument-mode
    # metacharacters (the typographic quotes included) end, split or expand a bare word. Right
    # after switch text ('-o', '-i!') a '.' or '[' also ends PowerShell's parameter token, which
    # hands 7-Zip the switch and the path as two arguments.
    param(
        [string]$Value,
        [string]$Quote,
        [switch]$AfterSwitch
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $Quote) {
        if (-not ($AfterSwitch -and $Value -match '[.\[]') -and $Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -match '[''\u2018-\u201B]') {
        return $Quote + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $Quote
    }

    $Quote + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $Quote
}

function ConvertFrom-SevenZipCompletedPath {
    # CompleteFilename answers with a path already quoted or escaped for PowerShell; the parser
    # recovers the text (it undoes every doubled quote, typographic ones included). A quoted
    # answer is also wildcard-escaped for a cmdlet's -Path ('tick``dir', 'br`[1`]'), which a
    # native command would receive literally.
    param([string]$CompletionText)

    $ast = [System.Management.Automation.Language.Parser]::ParseInput('x ' + $CompletionText, [ref]$null, [ref]$null)
    $command = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    if ($command -and $command.CommandElements.Count -eq 2 -and
        $command.CommandElements[1] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        $constant = $command.CommandElements[1]
        if ($constant.StringConstantType -eq [System.Management.Automation.Language.StringConstantType]::BareWord) {
            return $constant.Value
        }

        return [System.Management.Automation.WildcardPattern]::Unescape($constant.Value)
    }

    $CompletionText
}

function Get-SevenZipDirectoryCompletions {
    param(
        [string]$InputPath,
        [string]$SwitchPrefix = '',
        [int]$KeptLength = 0
    )

    # PowerShell keeps the first $KeptLength characters of the value (it ends a parameter token
    # at a drive colon, as in '-oC:' then '\Users') and replaces the rest, which keeps the quote
    # the user opened it with.
    $keptText = $InputPath.Substring(0, [Math]::Min([Math]::Max($KeptLength, 0), $InputPath.Length))
    $typedText = $InputPath.Substring($keptText.Length)
    $typedQuote = Get-SevenZipTypedQuote -Value $typedText
    $keptValue = ConvertFrom-SevenZipTypedWord -Value $keptText
    $cleanInput = $keptValue + (ConvertFrom-SevenZipTypedWord -Value $typedText)
    # After a kept drive colon the path is a word of its own; otherwise it continues the switch.
    $head = $SwitchPrefix + $keptText
    $afterSwitch = $head.StartsWith('-') -and -not $head.EndsWith(':')
    # A bare drive ('D:') means that drive's root, and a trailing separator means "list the
    # children of this directory"; Split-Path would hand either one back as the leaf.
    if ($cleanInput -match '^[A-Za-z]:$') {
        $cleanInput += [System.IO.Path]::DirectorySeparatorChar
    }

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

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }

    Get-ChildItem -LiteralPath $parent -Filter $filter -Directory -ErrorAction Ignore |
        ForEach-Object {
            $path = if ($cleanInput -and -not [System.IO.Path]::IsPathRooted($cleanInput)) {
                if ($parent -eq '.') {
                    $_.Name
                } else {
                    Join-Path -Path $parent -ChildPath $_.Name
                }
            } else {
                $_.FullName
            }

            if (-not $path.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
                $path += [System.IO.Path]::DirectorySeparatorChar
            }

            if (-not $path.StartsWith($keptValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                return
            }

            $completionText = $head + (ConvertTo-SevenZipQuotedValue -Value $path.Substring($keptValue.Length) -Quote $typedQuote -AfterSwitch:$afterSwitch)
            New-SevenZipCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $_.FullName
        }
}

function Get-SevenZipFileCompletionList {
    param(
        [string]$InputPath,
        [string]$Prefix = '',
        [int]$KeptLength = 0
    )

    # CompleteFilename quotes for a cmdlet's -Path, and its quotes would cover only the path, not
    # a prefix ('-i@', '-ir!') that must sit outside them so PowerShell hands 7-Zip one argument
    # with the switch text intact. So it gets the plain typed path, and its answer is unwrapped
    # and quoted here, once, in the quote typed. PowerShell keeps the first $KeptLength
    # characters of the path ('-i@C:' ends its parameter token) and replaces only the rest.
    $keptText = $InputPath.Substring(0, [Math]::Min([Math]::Max($KeptLength, 0), $InputPath.Length))
    $typedText = $InputPath.Substring($keptText.Length)
    $typedQuote = Get-SevenZipTypedQuote -Value $typedText
    $keptValue = ConvertFrom-SevenZipTypedWord -Value $keptText
    $cleanInput = $keptValue + (ConvertFrom-SevenZipTypedWord -Value $typedText)
    $head = $Prefix + $keptText
    $afterSwitch = $head.StartsWith('-') -and -not $head.EndsWith(':')

    foreach ($item in @([System.Management.Automation.CompletionCompleters]::CompleteFilename($cleanInput))) {
        $path = ConvertFrom-SevenZipCompletedPath -CompletionText $item.CompletionText
        if (-not $path.StartsWith($keptValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ([string]::IsNullOrEmpty($Prefix)) {
            $completionText = $keptText + (ConvertTo-SevenZipQuotedValue -Value $path.Substring($keptValue.Length) -Quote $typedQuote -AfterSwitch:$afterSwitch)
            [System.Management.Automation.CompletionResult]::new($completionText, $item.ListItemText, $item.ResultType, $item.ToolTip)
            continue
        }

        $completionText = if ($Prefix -eq '@') {
            # A bare word cannot start with '@' (PowerShell reads a splat), so the '@' of a list
            # file goes inside the quotes.
            ConvertTo-SevenZipQuotedValue -Value ($Prefix + $path) -Quote $typedQuote
        } else {
            $head + (ConvertTo-SevenZipQuotedValue -Value $path.Substring($keptValue.Length) -Quote $typedQuote -AfterSwitch:$afterSwitch)
        }

        New-SevenZipCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $item.ToolTip
    }
}

function Get-SevenZipMethodValueCompletionList {
    param(
        [string]$SwitchToken,
        [string]$TypedValue
    )

    # -m parameters are documented in the 7-Zip manual rather than in --help, so the
    # commonly used keys and their value sets are static.
    $onOff = @('on', 'off')
    $levels = @('0', '1', '3', '5', '7', '9')
    $threadCounts = @('off', 'on', '1', [Environment]::ProcessorCount.ToString())
    $parameterValues = [ordered]@{
        'x'  = @{ Values = $levels; ToolTip = 'Compression level (0 store ... 9 ultra)' }
        '0'  = @{ Values = @('LZMA2', 'LZMA', 'PPMd', 'BZip2', 'Deflate', 'Deflate64', 'Copy'); ToolTip = 'Compression method for the main stream' }
        's'  = @{ Values = $onOff; ToolTip = 'Solid archive mode' }
        'f'  = @{ Values = $onOff; ToolTip = 'Executable filters (BCJ, ARM64 ...)' }
        'hc' = @{ Values = $onOff; ToolTip = 'Header compression' }
        'he' = @{ Values = $onOff; ToolTip = 'Header encryption' }
        'mt' = @{ Values = $threadCounts; ToolTip = 'Multithreading: on, off or thread count' }
        'd'  = @{ Values = @('16m', '32m', '64m', '128m', '256m', '512m', '1g'); ToolTip = 'Dictionary size' }
        'fb' = @{ Values = @('32', '64', '128', '273'); ToolTip = 'Fast bytes' }
        'qs' = @{ Values = $onOff; ToolTip = 'Sort files by type in solid archives' }
        'tm' = @{ Values = $onOff; ToolTip = 'Store last modified timestamps' }
        'tc' = @{ Values = $onOff; ToolTip = 'Store creation timestamps' }
        'ta' = @{ Values = $onOff; ToolTip = 'Store last access timestamps' }
    }

    # '-mx9' and '-mx=9' are both accepted; keep whatever separator was typed.
    $separator = ''
    $typed = $TypedValue
    if ($typed.StartsWith('=')) {
        $separator = '='
        $typed = $typed.Substring(1)
    }

    $candidates = New-Object System.Collections.Generic.List[object]

    # '-mx[N]' and '-mmt[N]' are complete without a value; offer the bare switch first.
    if ($TypedValue -eq '' -and $SwitchToken -ne '-m') {
        [void]$candidates.Add(@{ Text = $SwitchToken; ToolTip = Get-SevenZipDescription -Token $SwitchToken })
    }

    switch ($SwitchToken.ToLowerInvariant()) {
        '-mx' {
            foreach ($level in $levels) {
                [void]$candidates.Add(@{ Text = $SwitchToken + $separator + $level; ToolTip = 'Compression level: -mx1 (fastest) ... -mx9 (ultra)' })
            }
        }
        '-mmt' {
            foreach ($count in $threadCounts) {
                [void]$candidates.Add(@{ Text = $SwitchToken + $separator + $count; ToolTip = 'Number of CPU threads' })
            }
        }
        '-m' {
            $equalsIndex = $typed.IndexOf('=')
            if ($equalsIndex -lt 0) {
                foreach ($key in $parameterValues.Keys) {
                    [void]$candidates.Add(@{ Text = $SwitchToken + $key + '='; ToolTip = $parameterValues[$key].ToolTip })
                }
            } else {
                $key = $typed.Substring(0, $equalsIndex)
                if ($parameterValues.Contains($key)) {
                    foreach ($value in $parameterValues[$key].Values) {
                        [void]$candidates.Add(@{ Text = $SwitchToken + $key + '=' + $value; ToolTip = $parameterValues[$key].ToolTip })
                    }
                }
            }
        }
    }

    foreach ($candidate in $candidates.ToArray()) {
        if ($candidate.Text.StartsWith($SwitchToken + $TypedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-SevenZipCompletionResult -CompletionText $candidate.Text -ResultType 'ParameterValue' -ToolTip $candidate.ToolTip
        }
    }
}

function Get-SevenZipValueHintCompletionList {
    param(
        [string]$SwitchToken,
        [string]$TypedValue,
        [int]$KeptLength = 0
    )

    $switchKey = $SwitchToken.ToLowerInvariant()
    if (-not $script:SevenZipCompletionCatalog.ValueHintsBySwitch.ContainsKey($switchKey)) {
        return @()
    }

    $sink = New-Object System.Collections.Generic.List[object]
    $null = Get-SevenZipSyntaxCandidateList -Pending $script:SevenZipCompletionCatalog.ValueHintsBySwitch[$switchKey] -Prefix '' -Typed $TypedValue -Extended $false -Sink $sink

    # The value exactly as typed (the bare switch when nothing follows it) goes first, so Tab on a
    # finished '-sns' keeps it instead of inserting the longer, inverted '-sns-'.
    # 7-Zip's switch table gives '-u' a one-character minimum that its all-optional grammar
    # ('-u[-][p#]...') does not show: a bare '-u' fails with 'Too short switch'. The other
    # all-optional switches (-bb, -r, -scrc, -seml, -si, -sfx, -sns, -spf, -ssc, -w) parse bare.
    $bareRejected = $switchKey -eq '-u'
    $candidates = @($sink.ToArray() |
        Where-Object { -not ($bareRejected -and $_.Kind -eq 'Value' -and $_.Text -eq '') } |
        Sort-Object -Stable -Property {
            -not ($_.Kind -eq 'Value' -and [string]::Equals($_.Text, $TypedValue, [System.StringComparison]::OrdinalIgnoreCase))
        })

    $description = Get-SevenZipDescription -Token $SwitchToken
    $seen = @{}
    foreach ($candidate in $candidates) {
        if ($candidate.Kind -eq 'File') {
            $filePrefix = $SwitchToken + $candidate.Prefix
            foreach ($item in @(Get-SevenZipFileCompletionList -InputPath $candidate.Typed -Prefix $filePrefix -KeptLength ($KeptLength - $filePrefix.Length))) {
                if (-not $seen.ContainsKey($item.CompletionText)) {
                    $seen[$item.CompletionText] = $true
                    $item
                }
            }

            continue
        }

        $completionText = $SwitchToken + $candidate.Text
        if ($seen.ContainsKey($completionText)) {
            continue
        }

        $seen[$completionText] = $true
        New-SevenZipCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip ($completionText + ' : ' + $description)
    }
}

function Get-SevenZipSwitchCompletionList {
    param([string]$CurrentWord)

    $script:SevenZipCompletionCatalog.SwitchTokens |
        Where-Object { [string]::IsNullOrEmpty($CurrentWord) -or $_.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object {
            New-SevenZipCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip (Get-SevenZipDescription -Token $_)
        }
}

function Get-SevenZipCommandCompletionList {
    param([string]$CurrentWord)

    $script:SevenZipCompletionCatalog.Commands |
        Where-Object { [string]::IsNullOrEmpty($CurrentWord) -or $_.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object {
            New-SevenZipCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip (Get-SevenZipDescription -Token $_)
        }
}

function Get-SevenZipCompletionResultList {
    param(
        [string]$currentWord,
        [string[]]$tokensBeforeCurrent,
        [int]$keptLength
    )

    $hasOptionTerminator = Test-SevenZipHasOptionTerminator -TokensBeforeCurrent $tokensBeforeCurrent
    $activeCommand = Get-SevenZipActiveCommand -Tokens $tokensBeforeCurrent -KnownCommands $script:SevenZipCompletionCatalog.Commands

    if (-not $hasOptionTerminator) {
        $inlineValueSwitch = Get-SevenZipInlineValueSwitch -Token $currentWord -KnownValueSwitches $script:SevenZipCompletionCatalog.ValueSwitches
        if ($inlineValueSwitch) {
            $typedValue = $currentWord.Substring($inlineValueSwitch.Length)
            $switchKey = $inlineValueSwitch.ToLowerInvariant()

            if ($script:SevenZipCompletionCatalog.PathLikeSwitches -contains $switchKey) {
                return Get-SevenZipDirectoryCompletions -InputPath $typedValue -SwitchPrefix $inlineValueSwitch -KeptLength ($keptLength - $inlineValueSwitch.Length)
            }

            if ($script:SevenZipCompletionCatalog.ArchiveTypeSwitches -contains $switchKey) {
                return Get-SevenZipArchiveTypeList |
                    Where-Object { $_.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase) } |
                    ForEach-Object {
                        New-SevenZipCompletionResult -CompletionText ($inlineValueSwitch + $_) -ResultType 'ParameterValue' -ToolTip "Archive type $_"
                    }
            }

            $valueResults = New-Object System.Collections.Generic.List[object]
            if ($script:SevenZipCompletionCatalog.MethodSwitches -contains $switchKey) {
                foreach ($result in @(Get-SevenZipMethodValueCompletionList -SwitchToken $inlineValueSwitch -TypedValue $typedValue)) {
                    [void]$valueResults.Add($result)
                }
            } else {
                foreach ($result in @(Get-SevenZipValueHintCompletionList -SwitchToken $inlineValueSwitch -TypedValue $typedValue -KeptLength $keptLength)) {
                    [void]$valueResults.Add($result)
                }
            }

            # A switch whose documented value is only a metavariable ('-p{Password}') has nothing
            # to offer; keep completing the switch name itself instead of going silent.
            if ($valueResults.Count -gt 0 -or -not [string]::IsNullOrEmpty($typedValue)) {
                return $valueResults.ToArray()
            }
        }
    }

    if (-not $activeCommand) {
        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            $commandResults = @(Get-SevenZipCommandCompletionList -CurrentWord '')
            $switchResults = if ($hasOptionTerminator) {
                @()
            } else {
                @(Get-SevenZipSwitchCompletionList -CurrentWord '')
            }

            return @($commandResults + $switchResults)
        }

        if (-not $hasOptionTerminator -and $currentWord.StartsWith('-')) {
            return Get-SevenZipSwitchCompletionList -CurrentWord $currentWord
        }

        if (-not $hasOptionTerminator -and $currentWord.StartsWith('@')) {
            return Get-SevenZipFileCompletionList -InputPath $currentWord.Substring(1) -Prefix '@' -KeptLength ($keptLength - 1)
        }

        return Get-SevenZipCommandCompletionList -CurrentWord $currentWord
    }

    if (-not $hasOptionTerminator -and $currentWord.StartsWith('-')) {
        return Get-SevenZipSwitchCompletionList -CurrentWord $currentWord
    }

    # Everything after the command is <archive_name> then <file_names>, so this is a path slot;
    # '@listfile' names a file holding the file list.
    if (-not $hasOptionTerminator -and $currentWord.StartsWith('@')) {
        return Get-SevenZipFileCompletionList -InputPath $currentWord.Substring(1) -Prefix '@' -KeptLength ($keptLength - 1)
    }

    $fileResults = @(Get-SevenZipFileCompletionList -InputPath $currentWord -KeptLength $keptLength)
    if (-not $hasOptionTerminator -and [string]::IsNullOrWhiteSpace($currentWord)) {
        $switchResults = @(Get-SevenZipSwitchCompletionList -CurrentWord '')
        return @($switchResults + $fileResults)
    }

    $fileResults
}

function Complete-SevenZip {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-SevenZipCompletionCatalog

    # $cursorPosition indexes the whole input line; the command text is command-relative.
    $line = $commandAst.Extent.Text
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    $lineTokens = Get-SevenZipLineTokens -Line $line -CursorPosition $relativeCursor
    $tokensBeforeCurrent = @($lineTokens.Before | Select-Object -Skip 1)
    $currentWord = if ($lineTokens.AfterWhitespace) {
        ''
    } elseif (-not [string]::IsNullOrEmpty($lineTokens.Current)) {
        $lineTokens.Current
    } else {
        $wordToComplete
    }

    # PowerShell replaces only the tail of a word it splits ('-oC:' then '\Users\Tr'); that kept
    # head comes off every completion so it is not typed twice.
    $keptLength = 0
    if (-not $lineTokens.AfterWhitespace) {
        $replacementStart = Get-SevenZipReplacementStart -Line $line -CursorPosition $relativeCursor
        $keptLength = [Math]::Min([Math]::Max($replacementStart - $lineTokens.CurrentStart, 0), $currentWord.Length)
    }

    $results = @(Get-SevenZipCompletionResultList -currentWord $currentWord -tokensBeforeCurrent $tokensBeforeCurrent -keptLength $keptLength)
    if ($keptLength -eq 0) {
        return $results
    }

    $keptText = $currentWord.Substring(0, $keptLength)
    foreach ($result in $results) {
        $text = $result.CompletionText
        if ($text.Length -gt $keptLength -and $text.StartsWith($keptText, [System.StringComparison]::OrdinalIgnoreCase)) {
            [System.Management.Automation.CompletionResult]::new($text.Substring($keptLength), $result.ListItemText, $result.ResultType, $result.ToolTip)
        }
    }
}

Register-ArgumentCompleter -Native -CommandName '7z', '7z.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-SevenZip -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
