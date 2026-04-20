Set-StrictMode -Version 2.0

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
    @(
        [pscustomobject]@{ Tokens = @('-h', '--help');              ValueKind = $null;      Description = 'Show help message and exit.' }
        [pscustomobject]@{ Tokens = @('-v', '--version');           ValueKind = $null;      Description = 'Show version number and exit.' }
        [pscustomobject]@{ Tokens = @('-o', '--output');            ValueKind = 'Output';   Description = 'Write converted markdown to a file.' }
        [pscustomobject]@{ Tokens = @('-x', '--extension');         ValueKind = 'Extension'; Description = 'Hint the input extension when reading from stdin.' }
        [pscustomobject]@{ Tokens = @('-m', '--mime-type');         ValueKind = 'MimeType'; Description = 'Hint the input MIME type.' }
        [pscustomobject]@{ Tokens = @('-c', '--charset');           ValueKind = 'Charset';  Description = 'Hint the input charset.' }
        [pscustomobject]@{ Tokens = @('-d', '--use-docintel');      ValueKind = $null;      Description = 'Use Azure Document Intelligence extraction.' }
        [pscustomobject]@{ Tokens = @('-e', '--endpoint');          ValueKind = 'Endpoint'; Description = 'Document Intelligence endpoint URL.' }
        [pscustomobject]@{ Tokens = @('-p', '--use-plugins');       ValueKind = $null;      Description = 'Enable installed third-party plugins.' }
        [pscustomobject]@{ Tokens = @('--list-plugins');            ValueKind = $null;      Description = 'List installed third-party plugins.' }
        [pscustomobject]@{ Tokens = @('--keep-data-uris');          ValueKind = $null;      Description = 'Preserve data URIs in the output.' }
    )
}

function Get-MarkItDownOptionMap {
    $map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)

    foreach ($spec in Get-MarkItDownOptionSpecs) {
        foreach ($token in $spec.Tokens) {
            $map[$token] = $spec
        }
    }

    $map
}

function Get-MarkItDownExtensionSuggestions {
    @(
        'pdf',
        'docx',
        'pptx',
        'xlsx',
        'html',
        'htm',
        'csv',
        'json',
        'xml',
        'txt',
        'md'
    )
}

function Get-MarkItDownMimeTypeSuggestions {
    @(
        'application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'text/plain',
        'text/html',
        'text/csv',
        'application/json',
        'application/xml'
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

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$leaf*" } | Sort-Object -Property Name)) {
        $pathText = if ($parent -eq '.') { $item.Name } else { Join-Path -Path $parent -ChildPath $item.Name }
        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $quotedPath = ConvertTo-MarkItDownQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        [void]$results.Add((New-MarkItDownCompletionResult -CompletionText $quotedPath -ToolTip "${ToolTipPrefix}: $($item.FullName)"))
    }

    if ($results.Count -eq 0) {
        [void]$results.Add((New-MarkItDownCompletionResult -CompletionText '<path>' -ToolTip 'Path to an input or output file.'))
    }

    @($results.ToArray())
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
                Where-Object { $_ -like "$CurrentWord*" } |
                ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Input extension hint.' }
        }
        'MimeType' {
            return Get-MarkItDownMimeTypeSuggestions |
                Where-Object { $_ -like "$CurrentWord*" } |
                ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Input MIME type hint.' }
        }
        'Charset' {
            return Get-MarkItDownCharsetSuggestions |
                Where-Object { $_ -like "$CurrentWord*" } |
                ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Input charset hint.' }
        }
        'Endpoint' {
            $suggestions = @('https://<resource>.cognitiveservices.azure.com/')
            return $suggestions |
                Where-Object { $_ -like "$CurrentWord*" } |
                ForEach-Object { New-MarkItDownCompletionResult -CompletionText $_ -ToolTip 'Azure Document Intelligence endpoint.' }
        }
    }

    @()
}

function Get-MarkItDownOptionCompletions {
    param([string]$CurrentWord)

    foreach ($spec in Get-MarkItDownOptionSpecs) {
        foreach ($token in $spec.Tokens) {
            if ($token -like "$CurrentWord*") {
                New-MarkItDownCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $spec.Description
            }
        }
    }
}

function Complete-MarkItDown {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $currentWord = if ($null -eq $WordToComplete) {
        Get-MarkItDownCurrentToken -Line $CommandAst.ToString() -CursorPosition $CursorPosition -Fallback $WordToComplete
    } else {
        $WordToComplete
    }

    $tokensBeforeCurrent = @(Get-MarkItDownArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $expectedValue = Get-MarkItDownExpectedValueSpec -TokensBeforeCurrent $tokensBeforeCurrent
    if ($expectedValue) {
        return @(Get-MarkItDownValueCompletions -Spec $expectedValue -CurrentWord $currentWord)
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

        $positionals += $token
    }

    if ($positionals.Count -eq 0) {
        $results = New-Object System.Collections.Generic.List[object]
        foreach ($item in @(Get-MarkItDownPathCompletions -InputPath $currentWord -ToolTipPrefix 'Input')) {
            [void]$results.Add($item)
        }

        if ($results.Count -eq 0 -or [string]::IsNullOrWhiteSpace($currentWord)) {
            [void]$results.Add((New-MarkItDownCompletionResult -CompletionText '<filename>' -ToolTip 'Input file to convert. Omit to read from stdin.'))
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
