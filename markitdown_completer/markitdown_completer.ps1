Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name MarkItDownCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:MarkItDownCompletionCache = @{
        OptionSpecs = $null
        OptionMap   = $null
    }
}

function New-MarkItDownCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $ListItemText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Get-MarkItDownOptionSpecs {
    $cache = $script:MarkItDownCompletionCache
    if ($null -eq $cache.OptionSpecs) {
        $cache.OptionSpecs = @(
            [pscustomobject]@{ Tokens = @('-h', '--help');                            ValueKind = $null;       Description = 'Show help message and exit.' }
            [pscustomobject]@{ Tokens = @('-v', '--version');                         ValueKind = $null;       Description = 'Show version number and exit.' }
            [pscustomobject]@{ Tokens = @('-o', '--output');                          ValueKind = 'Output';    Description = 'Write converted markdown to a file.' }
            [pscustomobject]@{ Tokens = @('-x', '--extension');                       ValueKind = 'Extension'; Description = 'Hint the input extension when reading from stdin.' }
            [pscustomobject]@{ Tokens = @('-m', '--mime-type');                       ValueKind = 'MimeType';  Description = 'Hint the input MIME type.' }
            [pscustomobject]@{ Tokens = @('-c', '--charset');                         ValueKind = 'Charset';   Description = 'Hint the input charset.' }
            [pscustomobject]@{ Tokens = @('-d', '--use-docintel');                    ValueKind = $null;       Description = 'Use Azure Document Intelligence extraction (requires --endpoint).' }
            [pscustomobject]@{ Tokens = @('--use-cu', '--use-content-understanding'); ValueKind = $null;       Description = 'Use Azure Content Understanding extraction (requires --cu-endpoint).' }
            [pscustomobject]@{ Tokens = @('-e', '--endpoint');                        ValueKind = 'Endpoint';  Description = 'Document Intelligence endpoint URL.' }
            [pscustomobject]@{ Tokens = @('--cu-endpoint');                           ValueKind = 'Endpoint';  Description = 'Content Understanding endpoint URL.' }
            [pscustomobject]@{ Tokens = @('--cu-analyzer');                           ValueKind = 'Analyzer';  Description = 'Content Understanding analyzer ID (auto-selected by file type when omitted).' }
            [pscustomobject]@{ Tokens = @('--cu-file-types');                         ValueKind = 'FileTypes'; Description = 'Comma-separated file types routed to Content Understanding (e.g. pdf,jpeg,mp4).' }
            [pscustomobject]@{ Tokens = @('-p', '--use-plugins');                     ValueKind = $null;       Description = 'Enable installed third-party plugins.' }
            [pscustomobject]@{ Tokens = @('--list-plugins');                          ValueKind = $null;       Description = 'List installed third-party plugins.' }
            [pscustomobject]@{ Tokens = @('--keep-data-uris');                        ValueKind = $null;       Description = 'Preserve data URIs in the output.' }
        )
    }

    $cache.OptionSpecs
}

function Get-MarkItDownOptionMap {
    $cache = $script:MarkItDownCompletionCache
    if ($null -eq $cache.OptionMap) {
        $map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($spec in Get-MarkItDownOptionSpecs) {
            foreach ($token in $spec.Tokens) {
                $map[$token] = $spec
            }
        }

        $cache.OptionMap = $map
    }

    $cache.OptionMap
}

function Get-MarkItDownExtensionSuggestions {
    # Every ACCEPTED_FILE_EXTENSIONS entry across markitdown 0.1.7's converters.
    @(
        'pdf', 'docx', 'pptx', 'xlsx', 'xls', 'csv', 'json', 'jsonl', 'ipynb',
        'html', 'htm', 'xhtml', 'xml', 'rss', 'atom',
        'txt', 'text', 'md', 'markdown', 'rtf', 'epub', 'zip', 'eml', 'msg',
        'jpg', 'jpeg', 'jpe', 'png', 'bmp', 'tiff', 'heic', 'heif',
        'mp3', 'wav', 'flac', 'ogg', 'aac', 'm4a', 'wma',
        'mp4', 'm4v', 'mov', 'mkv', 'avi', 'webm', 'flv', 'wmv'
    )
}

function Get-MarkItDownCuFileTypeTable {
    # ContentUnderstandingFileType values in markitdown 0.1.8; --cu-file-types
    # rejects anything else with 'Unknown file type'.
    @(
        'pdf', 'docx', 'pptx', 'xlsx', 'html', 'txt', 'md', 'rtf', 'xml',
        'eml', 'msg',
        'jpeg', 'png', 'bmp', 'tiff', 'heif',
        'mp4', 'm4v', 'mov', 'avi', 'mkv', 'webm', 'flv', 'wmv',
        'wav', 'mp3', 'm4a', 'flac', 'ogg', 'aac', 'wma'
    )
}

function Get-MarkItDownMimeTypeSuggestions {
    # Every ACCEPTED_MIME_TYPE_PREFIXES entry across markitdown 0.1.7's converters.
    @(
        'application/pdf',
        'application/x-pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.presentationml',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-excel',
        'application/excel',
        'application/vnd.ms-outlook',
        'application/json',
        'application/xml',
        'application/xhtml',
        'application/xhtml+xml',
        'application/atom',
        'application/atom+xml',
        'application/rss',
        'application/rss+xml',
        'application/csv',
        'application/markdown',
        'application/rtf',
        'application/epub',
        'application/epub+zip',
        'application/x-epub+zip',
        'application/zip',
        'text/plain',
        'text/html',
        'text/csv',
        'text/xml',
        'text/markdown',
        'text/rtf',
        'message/rfc822',
        'image/jpeg',
        'image/png',
        'image/bmp',
        'image/tiff',
        'image/heic',
        'image/heif',
        'image/svg+xml',
        'audio/mpeg',
        'audio/mp3',
        'audio/mp4',
        'audio/m4a',
        'audio/x-m4a',
        'audio/wav',
        'audio/x-wav',
        'audio/flac',
        'audio/x-flac',
        'audio/ogg',
        'audio/aac',
        'audio/x-ms-wma',
        'video/mp4',
        'video/x-m4v',
        'video/quicktime',
        'video/x-matroska',
        'video/x-msvideo',
        'video/webm',
        'video/x-flv',
        'video/x-ms-wmv'
    )
}

function Get-MarkItDownCharsetSuggestions {
    @(
        'utf-8',
        'utf-16',
        'utf-16le',
        'utf-16be',
        'utf-32',
        'ascii',
        'latin1',
        'windows-1252'
    )
}

function Get-MarkItDownUriSchemeTable {
    @('https://', 'http://', 'file:///', 'data:')
}

function ConvertFrom-MarkItDownTypedWord {
    # Splits the text typed so far into its value and the opening quote the
    # user typed ('' when bare, otherwise ' or "), undoing that quote style's
    # escapes. PowerShell treats U+2018-U+201B as single quotes and
    # U+201C-U+201E as double quotes; a doubled quote keeps its second
    # character, as the parser does.
    param([string]$Text)

    $single = '[''\u2018-\u201B]'
    $double = '["\u201C-\u201E]'
    $quoteClass = if ($Text -match "^$single") { $single } elseif ($Text -match "^$double") { $double }
    if (-not $quoteClass) {
        return [pscustomobject]@{ Value = $Text; Quote = '' }
    }

    $value = [System.Text.StringBuilder]::new()
    for ($i = 1; $i -lt $Text.Length; $i++) {
        $char = [string]$Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { [string]$Text[$i + 1] } else { '' }
        if ($quoteClass -eq $double -and $char -eq '`' -and $next) {
            $i++
            [void]$value.Append($next)
        } elseif ($char -match $quoteClass) {
            if ($next -notmatch $quoteClass) {
                break
            }

            $i++
            [void]$value.Append($next)
        } else {
            [void]$value.Append($char)
        }
    }

    $quote = if ($quoteClass -eq $single) { "'" } else { '"' }
    [pscustomobject]@{ Value = $value.ToString(); Quote = $quote }
}

function ConvertTo-MarkItDownArgument {
    # Renders a value as one PowerShell argument: bare when safe and no quote
    # was typed, otherwise in the typed quote style (single by default).
    # Whitespace and argument-mode metacharacters (including the typographic
    # quotes) end or split a bare word, and a leading '@' or '#' would start a
    # splat or a comment.
    param(
        [string]$Value,
        [string]$Quote
    )

    if (-not $Quote) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$\u2018-\u201E]' -and $Value -notmatch '^[@#]') {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -eq "'") {
        return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
    }

    '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
}

function Get-MarkItDownTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-MarkItDownArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += Get-MarkItDownTokenText -Element $element
        }
    }

    $tokens
}

function Split-MarkItDownAttachedOption {
    param([string]$Token)

    # Returns the option spec and attached value for '--opt=value' tokens,
    # or $null when the token is not an attached, value-bearing option.
    if ([string]::IsNullOrEmpty($Token) -or -not $Token.StartsWith('-') -or -not $Token.Contains('=')) {
        return $null
    }

    $separator = $Token.IndexOf('=')
    $name = $Token.Substring(0, $separator)
    $optionMap = Get-MarkItDownOptionMap
    if (-not $optionMap.ContainsKey($name) -or -not $optionMap[$name].ValueKind) {
        return $null
    }

    [pscustomobject]@{
        Name  = $name
        Spec  = $optionMap[$name]
        Value = $Token.Substring($separator + 1)
    }
}

function Get-MarkItDownExpectedValueSpec {
    param([string[]]$TokensBeforeCurrent)

    if (-not $TokensBeforeCurrent -or $TokensBeforeCurrent.Count -eq 0) {
        return $null
    }

    $optionMap = Get-MarkItDownOptionMap
    $lastToken = $TokensBeforeCurrent[-1]
    if ($optionMap.ContainsKey($lastToken) -and $optionMap[$lastToken].ValueKind) {
        return $optionMap[$lastToken]
    }

    $null
}

function Get-MarkItDownPathCompletions {
    param(
        [string]$InputPath,
        [string]$ToolTipPrefix = 'Path'
    )

    $typed = ConvertFrom-MarkItDownTypedWord -Text $InputPath
    $typedValue = $typed.Value

    # An empty $parent means the current directory with no typed folder part,
    # so candidates stay bare names; a typed folder part (even '.\') is kept.
    if ([string]::IsNullOrWhiteSpace($typedValue)) {
        $parent = ''
        $leaf = ''
    } elseif ($typedValue.EndsWith('\') -or $typedValue.EndsWith('/')) {
        $parent = $typedValue
        $leaf = ''
    } else {
        $parent = Split-Path -Path $typedValue -Parent
        $leaf = if ($parent) { Split-Path -Path $typedValue -Leaf } else { $typedValue }
    }

    # Enumerate lazily through .NET so a 30k-entry directory is not
    # materialized: directories first, then files markitdown can convert,
    # then everything else, capped at 200 entries in total.
    $limit = 200
    $basePath = if (-not $parent) { $PWD.ProviderPath } elseif ([System.IO.Path]::IsPathRooted($parent)) { $parent } else { Join-Path -Path $PWD.ProviderPath -ChildPath $parent }
    try {
        $directory = [System.IO.DirectoryInfo]::new($basePath)
        if (-not $directory.Exists) {
            return
        }

        $pattern = $leaf + '*'
        $hidden = [System.IO.FileAttributes]::Hidden
        $convertible = [System.Collections.Generic.HashSet[string]]::new([string[]](Get-MarkItDownExtensionSuggestions), [System.StringComparer]::OrdinalIgnoreCase)

        $directories = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $directory.EnumerateDirectories($pattern)) {
            if (($entry.Attributes -band $hidden) -eq $hidden) { continue }
            [void]$directories.Add($entry)
            if ($directories.Count -ge $limit) { break }
        }

        $preferred = New-Object System.Collections.Generic.List[object]
        $others = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $directory.EnumerateFiles($pattern)) {
            if (($entry.Attributes -band $hidden) -eq $hidden) { continue }
            if ($convertible.Contains($entry.Extension.TrimStart('.'))) {
                [void]$preferred.Add($entry)
                if ($preferred.Count -ge $limit) { break }
            } elseif ($others.Count -lt $limit) {
                [void]$others.Add($entry)
            }
        }
    } catch {
        return
    }

    $items = @(
        @($directories | Sort-Object -Property Name) +
        @($preferred | Sort-Object -Property Name) +
        @($others | Sort-Object -Property Name)
    ) | Select-Object -First $limit

    foreach ($item in $items) {
        $isContainer = $item -is [System.IO.DirectoryInfo]
        $pathText = if ($parent) { Join-Path -Path $parent -ChildPath $item.Name } else { $item.Name }
        if ($isContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $completionText = ConvertTo-MarkItDownArgument -Value $pathText -Quote $typed.Quote
        $resultType = if ($isContainer) { 'ProviderContainer' } else { 'ProviderItem' }
        New-MarkItDownCompletionResult -CompletionText $completionText -ResultType $resultType -ListItemText $pathText -ToolTip "${ToolTipPrefix}: $($item.FullName)"
    }
}

function Complete-MarkItDownCommaList {
    param(
        [string[]]$Candidates,
        [string]$CurrentWord,
        [string]$ToolTip
    )

    $prefix = ''
    $segment = $CurrentWord
    $selected = @()
    if ($CurrentWord -like '*,*') {
        $lastComma = $CurrentWord.LastIndexOf(',')
        $prefix = $CurrentWord.Substring(0, $lastComma + 1)
        $segment = $CurrentWord.Substring($lastComma + 1)
        $selected = @($prefix.TrimEnd(',').Split(',') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    foreach ($candidate in $Candidates) {
        if ($selected -contains $candidate) {
            continue
        }

        if ($candidate -like ([System.Management.Automation.WildcardPattern]::Escape($segment) + '*')) {
            New-MarkItDownCompletionResult -CompletionText ($prefix + $candidate) -ListItemText $candidate -ToolTip $ToolTip
        }
    }
}

function Get-MarkItDownValueCompletions {
    param(
        [object]$Spec,
        [string]$CurrentWord
    )

    if ($Spec.ValueKind -eq 'Output') {
        $results = @(Get-MarkItDownPathCompletions -InputPath $CurrentWord -ToolTipPrefix 'Output')
        if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
            $results += New-MarkItDownCompletionResult -CompletionText 'output.md' -ToolTip 'Write markdown output to output.md.'
        }
        return $results
    }

    # Match on the unquoted value; a quote the user typed is kept below.
    $typed = ConvertFrom-MarkItDownTypedWord -Text $CurrentWord
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($typed.Value) + '*'
    $results = @(
        switch ([string]$Spec.ValueKind) {
            'Extension' {
                Get-MarkItDownExtensionSuggestions | Where-Object { $_ -like $pattern } |
                    ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Input extension hint.' }
            }
            'MimeType' {
                Get-MarkItDownMimeTypeSuggestions | Where-Object { $_ -like $pattern } |
                    ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Input MIME type hint.' }
            }
            'Charset' {
                Get-MarkItDownCharsetSuggestions | Where-Object { $_ -like $pattern } |
                    ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Input charset hint.' }
            }
            'Endpoint' {
                @('https://<resource>.cognitiveservices.azure.com/') | Where-Object { $_ -like $pattern } |
                    ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Azure endpoint URL.' }
            }
            'Analyzer' {
                if ([string]::IsNullOrWhiteSpace($typed.Value)) {
                    New-MarkItDownCompletionResult -CompletionText '<analyzer-id>' -ToolTip 'Content Understanding analyzer ID.'
                }
            }
            'FileTypes' {
                Complete-MarkItDownCommaList -Candidates (Get-MarkItDownCuFileTypeTable) -CurrentWord $typed.Value -ToolTip 'File type routed to Content Understanding.'
            }
        }
    )

    if (-not $typed.Quote) {
        return $results
    }

    foreach ($item in $results) {
        $completionText = ConvertTo-MarkItDownArgument -Value $item.CompletionText -Quote $typed.Quote
        New-MarkItDownCompletionResult -CompletionText $completionText -ResultType $item.ResultType -ToolTip $item.ToolTip -ListItemText $item.ListItemText
    }
}

function Get-MarkItDownOptionCompletions {
    param([string]$CurrentWord)

    foreach ($spec in Get-MarkItDownOptionSpecs) {
        foreach ($token in $spec.Tokens) {
            if ($token -like ([System.Management.Automation.WildcardPattern]::Escape($CurrentWord) + '*')) {
                New-MarkItDownCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $spec.Description
            }
        }
    }
}

function Complete-MarkItDownInput {
    param([string]$CurrentWord)

    $typedValue = (ConvertFrom-MarkItDownTypedWord -Text $CurrentWord).Value

    # A URI operand (http:, https:, file:, data:) is never a local listing.
    if ($typedValue -match '^[A-Za-z][A-Za-z0-9+.-]*:(//|$)' -and $typedValue -notmatch '^[A-Za-z]:[\\/]?$') {
        foreach ($scheme in Get-MarkItDownUriSchemeTable) {
            if ($scheme -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*')) {
                New-MarkItDownCompletionResult -CompletionText $scheme -ToolTip 'Convert a remote or data URI.'
            }
        }

        return
    }

    Get-MarkItDownPathCompletions -InputPath $CurrentWord -ToolTipPrefix 'Input'

    if ($typedValue -match '^[a-z]*$') {
        foreach ($scheme in Get-MarkItDownUriSchemeTable) {
            if ($scheme -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*')) {
                New-MarkItDownCompletionResult -CompletionText $scheme -ToolTip 'Convert a remote or data URI.'
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($typedValue)) {
        New-MarkItDownCompletionResult -CompletionText '<filename>' -ToolTip 'Input file to convert. Omit to read from stdin.'
    }
}

function Get-MarkItDownArgumentValue {
    # The value a native command receives for $Text written as one argument:
    # a string's value, or an unquoted comma list joined with commas. Anything
    # else (a quoted list element, an expression) yields $null.
    param([string]$Text)

    $ast = [System.Management.Automation.Language.Parser]::ParseInput("x $Text", [ref]$null, [ref]$null)
    $command = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    $elements = @($command.CommandElements | Select-Object -Skip 1)
    if ($elements.Count -ne 1) {
        return $null
    }

    $element = $elements[0]
    if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $element.Value
    }

    if ($element -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $parts = @($element.Elements)
        if (@($parts | Where-Object { $_ -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or $_.StringConstantType -ne 'BareWord' }).Count -eq 0) {
            return (($parts | ForEach-Object Value) -join ',')
        }
    }

    $null
}

function Select-MarkItDownSegmentCompletion {
    # Inside an unquoted comma list PowerShell replaces only the segment after
    # the last comma and hands a native command the list joined with commas.
    # A candidate is kept when its value extends the typed list and the rest
    # stays bare, so the accepted line is still one argument with that value.
    param(
        [object[]]$Results,
        [string]$SegmentPrefix
    )

    foreach ($item in $Results) {
        $value = Get-MarkItDownArgumentValue -Text $item.CompletionText
        if ($null -eq $value -or -not $value.StartsWith($SegmentPrefix, [System.StringComparison]::Ordinal)) {
            continue
        }

        $rest = $value.Substring($SegmentPrefix.Length)
        $unsafe = @($rest.Split(',') | Where-Object { -not $_ -or (ConvertTo-MarkItDownArgument -Value $_) -cne $_ })
        if ($unsafe.Count -gt 0) {
            continue
        }

        New-MarkItDownCompletionResult -CompletionText $rest -ResultType $item.ResultType -ToolTip $item.ToolTip -ListItemText $item.ListItemText
    }
}

function Get-MarkItDownWordCompletion {
    param(
        [string]$CurrentWord,
        [string[]]$TokensBeforeCurrent
    )

    $expectedValue = Get-MarkItDownExpectedValueSpec -TokensBeforeCurrent $TokensBeforeCurrent
    if ($expectedValue) {
        return @(Get-MarkItDownValueCompletions -Spec $expectedValue -CurrentWord $CurrentWord)
    }

    $attached = Split-MarkItDownAttachedOption -Token $CurrentWord
    if ($attached) {
        $prefix = $attached.Name + '='
        return @(
            foreach ($item in @(Get-MarkItDownValueCompletions -Spec $attached.Spec -CurrentWord $attached.Value)) {
                New-MarkItDownCompletionResult -CompletionText ($prefix + $item.CompletionText) -ResultType $item.ResultType -ToolTip $item.ToolTip -ListItemText $item.ListItemText
            }
        )
    }

    if (-not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('-')) {
        return @(Get-MarkItDownOptionCompletions -CurrentWord $CurrentWord)
    }

    $positionals = @()
    $optionMap = Get-MarkItDownOptionMap
    $skipNext = $false
    foreach ($token in $TokensBeforeCurrent) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }

        if ($optionMap.ContainsKey($token)) {
            if ($optionMap[$token].ValueKind) {
                $skipNext = $true
            }
            continue
        }

        if (Split-MarkItDownAttachedOption -Token $token) {
            continue
        }

        $positionals += $token
    }

    if ($positionals.Count -eq 0) {
        return @(
            Complete-MarkItDownInput -CurrentWord $CurrentWord
            Get-MarkItDownOptionCompletions -CurrentWord $CurrentWord
        )
    }

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        return @(Get-MarkItDownOptionCompletions -CurrentWord $CurrentWord)
    }

    @()
}

function Complete-MarkItDown {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # PowerShell hands a quoted word over re-quoted ("'it" arrives as "'it'")
    # and drops the quote inside an attached "--opt='it", while it replaces
    # the whole word as typed; so the word is read from the element under the
    # cursor. An unquoted comma list ('--opt=a,b', or 'a,' which parses as an
    # error expression) is the exception: PowerShell replaces only the segment
    # after the last comma, so the whole element is completed and the
    # candidates are cut back to that segment.
    $currentWord = $WordToComplete
    $segmentPrefix = ''
    $cursorElement = $CommandAst.CommandElements | Select-Object -Skip 1 |
        Where-Object { $_.Extent.StartOffset -lt $CursorPosition -and $_.Extent.EndOffset -ge $CursorPosition } |
        Select-Object -First 1
    if ($cursorElement) {
        $elementText = $cursorElement.Extent.Text.Substring(0, $CursorPosition - $cursorElement.Extent.StartOffset)
        $isList = $cursorElement -is [System.Management.Automation.Language.ArrayLiteralAst] -or
            $cursorElement -is [System.Management.Automation.Language.ErrorExpressionAst]
        if (-not $isList) {
            $currentWord = $elementText
        } elseif ($elementText.EndsWith(',' + $WordToComplete, [System.StringComparison]::Ordinal)) {
            $currentWord = $elementText
            $segmentPrefix = $elementText.Substring(0, $elementText.Length - $WordToComplete.Length)
        }
    }

    $tokensBeforeCurrent = @(Get-MarkItDownArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $results = @(Get-MarkItDownWordCompletion -CurrentWord $currentWord -TokensBeforeCurrent $tokensBeforeCurrent)
    if (-not $segmentPrefix) {
        return $results
    }

    $segmentResults = @(Select-MarkItDownSegmentCompletion -Results $results -SegmentPrefix $segmentPrefix)
    if ($segmentResults.Count -eq 0 -and $WordToComplete) {
        # Echo the typed segment so PowerShell's filename fallback adds no
        # candidate that would break the list; an empty segment cannot be
        # echoed (PowerShell rejects an empty completion text).
        return @(New-MarkItDownCompletionResult -CompletionText $WordToComplete -ToolTip 'Nothing continues this comma list; quote the whole value to complete a name that contains a comma.')
    }

    $segmentResults
}

Register-ArgumentCompleter -Native -CommandName @('markitdown', 'markitdown.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-MarkItDown -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
