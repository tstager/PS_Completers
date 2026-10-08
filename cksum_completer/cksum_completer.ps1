# cksum tab completion for PowerShell
# Static option completion for cksum.exe and cksum.

Set-StrictMode -Version 2.0

function Get-CksumValueKind {
    param([string]$Placeholder)

    switch -Regex ($Placeholder) {
        '^ALGORITHM$' { return 'Algorithm' }
        '^length$' { return 'Length' }
        '^$' { return $null }
        default { return 'Text' }
    }
}

function Get-CksumDefaultAlgorithmList {
    @('sysv', 'bsd', 'crc', 'crc32b', 'md5', 'sha1', 'sha2', 'sha3', 'blake2b', 'sm3', 'sha224', 'sha256', 'sha384', 'sha512', 'blake3', 'shake128', 'shake256')
}

function ConvertTo-CksumOptionSpec {
    param(
        [string]$Token,
        [string]$Description,
        [string]$Placeholder
    )

    [pscustomobject]@{
        Token       = $Token
        Description = $Description
        Placeholder = $Placeholder
        ValueKind   = Get-CksumValueKind -Placeholder $Placeholder
    }
}

function ConvertFrom-CksumHelpText {
    # Parses only the indented option table (clap or GNU style); prose such as the DIGEST
    # bullets ('equivalent to sum -s') is never scanned for option-looking tokens.
    param([string]$HelpText)

    $specs = New-Object System.Collections.Generic.List[object]
    $currentSpecs = @()
    $optionBlockText = New-Object System.Text.StringBuilder

    foreach ($line in ([regex]::Split($HelpText, '\r?\n'))) {
        if ($line -match '^\s{2,8}(?<spec>-\S.*?)(?:\s{2,}(?<desc>\S.*))?\s*$') {
            $spec = $Matches['spec']
            $description = if ($Matches['desc']) { $Matches['desc'].Trim() } else { '' }
            [void]$optionBlockText.Append(' ' + $description)
            $currentSpecs = @()

            $placeholder = ''
            $tokens = @()
            foreach ($part in ($spec -split ',\s*')) {
                if ($part -match '^(?<token>--?[A-Za-z0-9][A-Za-z0-9-]*)(?:(?:[ =]|\[=)<?(?<value>[A-Za-z_][A-Za-z0-9_-]*)>?\]?)?$') {
                    $tokens += $Matches['token']
                    if (-not $placeholder -and $Matches['value']) {
                        $placeholder = $Matches['value']
                    }
                }
            }

            foreach ($token in $tokens) {
                $optionSpec = ConvertTo-CksumOptionSpec -Token $token -Description $description -Placeholder $placeholder
                [void]$specs.Add($optionSpec)
                $currentSpecs += $optionSpec
            }

            continue
        }

        if ($currentSpecs.Count -gt 0 -and $line -match '^\s{10,}(?<text>\S.*?)\s*$') {
            $text = $Matches['text']
            [void]$optionBlockText.Append(' ' + $text)
            foreach ($optionSpec in $currentSpecs) {
                $optionSpec.Description = if ($optionSpec.Description) { $optionSpec.Description + ' ' + $text } else { $text }
            }

            continue
        }

        $currentSpecs = @()
    }

    $algorithmValues = @()
    if ($optionBlockText.ToString() -match '\[possible values:(?<values>[^\]]*)\]') {
        $algorithmValues = @($Matches['values'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    [pscustomobject]@{
        Options         = @($specs.ToArray())
        AlgorithmValues = $algorithmValues
    }
}

function Get-CksumCompletionCatalog {
    # The catalog is keyed on the resolved binary and its write time, so a PATH change or an
    # in-place upgrade re-reads the help. Get-Command runs again only when PATH changes.
    $cache = Get-Variable -Name 'CksumCompletionCatalog' -Scope Script -ErrorAction Ignore
    $cached = if ($null -ne $cache) { $cache.Value } else { $null }

    $searchPath = [string]$env:PATH
    $source = if ($null -ne $cached -and $cached.SearchPath -ceq $searchPath) {
        $cached.Source
    } else {
        $command = Get-Command -Name 'cksum.exe', 'cksum' -ErrorAction Ignore | Select-Object -First 1
        if ($null -ne $command) { [string]$command.Source } else { '' }
    }
    $writeTime = if ($source -and [System.IO.File]::Exists($source)) { [System.IO.File]::GetLastWriteTimeUtc($source) } else { [datetime]::MinValue }

    if ($null -ne $cached -and $cached.Source -ceq $source -and $cached.WriteTime -eq $writeTime) {
        $cached.SearchPath = $searchPath
        return $cached
    }

    $options = @()
    $algorithmValues = @()

    if ($source) {
        $helpOutput = try { $null | & $source --help 2>&1 | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String } catch { '' }
        if (-not [string]::IsNullOrWhiteSpace($helpOutput)) {
            $parsed = ConvertFrom-CksumHelpText -HelpText $helpOutput
            $options = @($parsed.Options)
            $algorithmValues = @($parsed.AlgorithmValues)
        }
    }

    if ($options.Count -eq 0) {
        $options = @(
            ConvertTo-CksumOptionSpec -Token '-a' -Description 'Select the digest type to use.' -Placeholder 'ALGORITHM'
            ConvertTo-CksumOptionSpec -Token '--algorithm' -Description 'Select the digest type to use.' -Placeholder 'ALGORITHM'
            ConvertTo-CksumOptionSpec -Token '--help' -Description 'Display help and exit.'
            ConvertTo-CksumOptionSpec -Token '--version' -Description 'Output version information and exit.'
        )
    }

    if ($algorithmValues.Count -eq 0) {
        $algorithmValues = Get-CksumDefaultAlgorithmList
    }

    $byToken = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($option in $options) {
        if (-not $byToken.ContainsKey($option.Token)) {
            $byToken[$option.Token] = $option
        }
    }

    $catalog = [pscustomobject]@{
        Options         = @($byToken.Values | Sort-Object -Property Token)
        ByToken         = $byToken
        AlgorithmValues = @($algorithmValues)
        LengthValues    = @('224', '256', '384', '512')
        SearchPath      = $searchPath
        Source          = $source
        WriteTime       = $writeTime
    }

    Set-Variable -Name 'CksumCompletionCatalog' -Value $catalog -Scope Script
    $catalog
}

function New-CksumCompletionResult {
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

function Remove-CksumOuterQuotes {
    # Strips the opening quote the user typed (and its closing match, when present) and
    # undoes that quote style's escapes.
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    if ($Value -notmatch '^[''"]') {
        return $Value
    }

    $quote = $Value.Substring(0, 1)
    $inner = $Value.Substring(1)
    if ($inner.EndsWith($quote)) {
        $inner = $inner.Substring(0, $inner.Length - 1)
    }

    if ($quote -eq "'") { $inner.Replace("''", "'") } else { $inner -replace '`(.)', '$1' }
}

function ConvertTo-CksumQuotedValue {
    # Bare when safe and no quote was typed; otherwise in the typed quote style (single by
    # default). Whitespace and argument-mode metacharacters (typographic quotes included)
    # end or split a bare word, a leading '@' or '#' starts a splat or a comment, and a
    # leading dash starts a parameter.
    param(
        [string]$Value,
        [string]$Quote = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $Quote) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$\u2018-\u201E]' -and $Value -notmatch '^[@#\u2013-\u2015-]') {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -eq "'") {
        return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
    }

    '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
}

function Get-CksumCurrentToken {
    # The word under the cursor comes from the parser: an unterminated quote is one element
    # that runs to the cursor, so a quoted path with a space stays whole.
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.StartOffset -lt $CursorPosition -and $element.Extent.EndOffset -ge $CursorPosition) {
            return $element.Extent.Text.Substring(0, $CursorPosition - $element.Extent.StartOffset)
        }
    }

    ''
}

function Get-CksumPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-CksumOuterQuotes -Value $InputPath
    $quote = if ($InputPath -match '^[''"]') { $InputPath.Substring(0, 1) } else { '' }

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]+$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    # The directory part is kept exactly as typed ('.\', './', 'sub/'), so no typed text is lost.
    $typedDirectory = $cleanInput.Substring(0, $cleanInput.LastIndexOfAny([char[]]'\/') + 1)

    foreach ($item in $items) {
        $pathText = if ($typedDirectory) {
            $typedDirectory + $item.Name
        } elseif ($parent -ne '.') {
            Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($item.Name -match '^[\u2013-\u2015-]') {
            # A bare leading dash would parse as a parameter, so name it from the current directory.
            '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        } else {
            $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-CksumQuotedValue -Value $pathText -Quote $quote
        if ($item.PSIsContainer) {
            New-CksumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-CksumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-CksumValueCompletion {
    param(
        [pscustomobject]$OptionSpec,
        [string]$CurrentValue,
        [string]$Prefix = ''
    )

    $catalog = Get-CksumCompletionCatalog
    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $toolTip = if ($OptionSpec.Description) { $OptionSpec.Description } else { $OptionSpec.Token }

    $values = switch ($OptionSpec.ValueKind) {
        'Algorithm' { @($catalog.AlgorithmValues) }
        'Length' { @($catalog.LengthValues) }
        default { @() }
    }

    $results = @(
        foreach ($value in $values) {
            if ($value.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                New-CksumCompletionResult -CompletionText ($Prefix + $value) -ListItemText $value -ResultType 'ParameterValue' -ToolTip $toolTip
            }
        }
    )

    if ($results.Count -gt 0) {
        return $results
    }

    $placeholder = switch ($OptionSpec.ValueKind) {
        'Length' { '<bits>' }
        default { if ($OptionSpec.Placeholder) { '<' + $OptionSpec.Placeholder.ToLowerInvariant() + '>' } else { '<value>' } }
    }
    $completionText = if ($typedValue) { $Prefix + $typedValue } else { $Prefix + $placeholder }
    @(New-CksumCompletionResult -CompletionText $completionText -ListItemText $placeholder -ResultType 'ParameterValue' -ToolTip $toolTip)
}

function Get-CksumOptionCompletion {
    param([string]$CurrentWord)

    $catalog = Get-CksumCompletionCatalog
    foreach ($option in $catalog.Options) {
        if ($option.Token.StartsWith($CurrentWord, [System.StringComparison]::Ordinal)) {
            $toolTip = if ($option.Description) { $option.Description } else { 'Option for cksum.' }
            New-CksumCompletionResult -CompletionText $option.Token -ListItemText $option.Token -ResultType 'ParameterName' -ToolTip $toolTip
        }
    }
}

function Complete-Cksum {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete closes an open quote and spans past the cursor.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $catalog = Get-CksumCompletionCatalog
    $currentWord = Get-CksumCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    # The element that ends before the current word decides whether this is a value slot.
    $previousToken = $null
    foreach ($element in ($commandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.EndOffset -lt $cursorPosition) {
            $previousToken = $element.Extent.Text
        }
    }

    if ($previousToken -and $catalog.ByToken.ContainsKey($previousToken) -and $catalog.ByToken[$previousToken].ValueKind) {
        return @(Get-CksumValueCompletion -OptionSpec $catalog.ByToken[$previousToken] -CurrentValue $currentWord)
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord -match '^(?<option>--[^=]+)=(?<value>.*)$') {
        $optionToken = $Matches['option']
        if ($catalog.ByToken.ContainsKey($optionToken) -and $catalog.ByToken[$optionToken].ValueKind) {
            return @(Get-CksumValueCompletion -OptionSpec $catalog.ByToken[$optionToken] -CurrentValue $Matches['value'] -Prefix ($optionToken + '='))
        }
    }

    if ($currentWord.StartsWith('-')) {
        return @(Get-CksumOptionCompletion -CurrentWord $currentWord)
    }

    Get-CksumPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'cksum', 'cksum.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Cksum -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
