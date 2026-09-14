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

function Remove-MarkItDownOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-MarkItDownQuotedValue {
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

function Get-MarkItDownCurrentToken {
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

    $typedValue = Remove-MarkItDownOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($typedValue)) {
        $parent = '.'
        $leaf = ''
    } elseif ($typedValue.EndsWith('\') -or $typedValue.EndsWith('/')) {
        $parent = $typedValue
        $leaf = ''
    } else {
        $candidateParent = Split-Path -Path $typedValue -Parent
        if ([string]::IsNullOrWhiteSpace($candidateParent)) {
            $parent = '.'
            $leaf = $typedValue
        } else {
            $parent = $candidateParent
            $leaf = Split-Path -Path $typedValue -Leaf
        }
    }

    # Enumerate lazily through .NET so a 30k-entry directory is not
    # materialized: directories first, then files markitdown can convert,
    # then everything else, capped at 200 entries in total.
    $limit = 200
    $basePath = if ([System.IO.Path]::IsPathRooted($parent)) { $parent } else { Join-Path -Path $PWD.ProviderPath -ChildPath $parent }
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
        $pathText = if ($parent -eq '.') { $item.Name } else { Join-Path -Path $parent -ChildPath $item.Name }
        if ($isContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $quotedPath = ConvertTo-MarkItDownQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        $resultType = if ($isContainer) { 'ProviderContainer' } else { 'ProviderItem' }
        New-MarkItDownCompletionResult -CompletionText $quotedPath -ResultType $resultType -ToolTip "${ToolTipPrefix}: $($item.FullName)"
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

    switch ([string]$Spec.ValueKind) {
        'Output' {
            $results = @(Get-MarkItDownPathCompletions -InputPath $CurrentWord -ToolTipPrefix 'Output')
            if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
                $results += New-MarkItDownCompletionResult -CompletionText 'output.md' -ToolTip 'Write markdown output to output.md.'
            }
            return $results
        }
        'Extension' {
            return Get-MarkItDownExtensionSuggestions |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($CurrentWord) + '*') } |
                ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Input extension hint.' }
        }
        'MimeType' {
            return Get-MarkItDownMimeTypeSuggestions |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($CurrentWord) + '*') } |
                ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Input MIME type hint.' }
        }
        'Charset' {
            return Get-MarkItDownCharsetSuggestions |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($CurrentWord) + '*') } |
                ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Input charset hint.' }
        }
        'Endpoint' {
            $suggestions = @('https://<resource>.cognitiveservices.azure.com/')
            return $suggestions |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($CurrentWord) + '*') } |
                ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Azure endpoint URL.' }
        }
        'Analyzer' {
            if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
                return @(New-MarkItDownCompletionResult -CompletionText '<analyzer-id>' -ToolTip 'Content Understanding analyzer ID.')
            }

            return @()
        }
        'FileTypes' {
            return @(Complete-MarkItDownCommaList -Candidates (Get-MarkItDownExtensionSuggestions) -CurrentWord $CurrentWord -ToolTip 'File type routed to Content Understanding.')
        }
    }

    @()
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

    $typedValue = Remove-MarkItDownOuterQuotes -Value $CurrentWord

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

function Complete-MarkItDown {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $currentWord = if ($null -eq $WordToComplete) {
        Get-MarkItDownCurrentToken -Line $CommandAst.ToString() -CursorPosition ($CursorPosition - $CommandAst.Extent.StartOffset) -Fallback $WordToComplete
    } else {
        $WordToComplete
    }

    $tokensBeforeCurrent = @(Get-MarkItDownArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $expectedValue = Get-MarkItDownExpectedValueSpec -TokensBeforeCurrent $tokensBeforeCurrent
    if ($expectedValue) {
        return @(Get-MarkItDownValueCompletions -Spec $expectedValue -CurrentWord $currentWord)
    }

    $attached = Split-MarkItDownAttachedOption -Token $currentWord
    if ($attached) {
        $prefix = $attached.Name + '='
        return @(
            foreach ($item in @(Get-MarkItDownValueCompletions -Spec $attached.Spec -CurrentWord $attached.Value)) {
                New-MarkItDownCompletionResult -CompletionText ($prefix + $item.CompletionText) -ResultType $item.ResultType -ToolTip $item.ToolTip -ListItemText $item.ListItemText
            }
        )
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-MarkItDownOptionCompletions -CurrentWord $currentWord)
    }

    $positionals = @()
    $optionMap = Get-MarkItDownOptionMap
    $skipNext = $false
    foreach ($token in $tokensBeforeCurrent) {
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
        $results = New-Object System.Collections.Generic.List[object]
        foreach ($item in @(Complete-MarkItDownInput -CurrentWord $currentWord)) {
            [void]$results.Add($item)
        }

        foreach ($item in @(Get-MarkItDownOptionCompletions -CurrentWord $currentWord)) {
            [void]$results.Add($item)
        }

        return @($results.ToArray())
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-MarkItDownOptionCompletions -CurrentWord $currentWord)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('markitdown', 'markitdown.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-MarkItDown -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
