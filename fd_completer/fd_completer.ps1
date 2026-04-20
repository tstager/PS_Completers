Set-StrictMode -Version 2.0

if ($true) {
function New-FdCompletionResult {
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

function Get-FdCompletionCatalog {
    $existingCatalog = Get-Variable -Name FdCompletionCatalog -Scope Script -ErrorAction Ignore
    if ($null -ne $existingCatalog) {
        return $existingCatalog.Value
    }

    $script:FdCompletionCatalog = @{
        Initialized   = $false
        CommandName   = $null
        Options       = @()
        OptionByToken = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    }

    $script:FdCompletionCatalog
}

function Resolve-FdCommandName {
    $catalog = Get-FdCompletionCatalog
    if ($catalog.CommandName) {
        return $catalog.CommandName
    }

    $command = Get-Command -Name fd.exe, fd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $catalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $catalog.CommandName
}

function Invoke-FdCapture {
    param([string[]]$Arguments)

    $commandName = Resolve-FdCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>$null)
    } catch {
        @()
    }
}

function Get-FdValueKindMap {
    $map = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $entries = @(
        [pscustomobject]@{ Token = '-c'; Kind = 'ColorWhen' }
        [pscustomobject]@{ Token = '--color'; Kind = 'ColorWhen' }
        [pscustomobject]@{ Token = '--hyperlink'; Kind = 'HyperlinkWhen' }
        [pscustomobject]@{ Token = '-t'; Kind = 'FileType' }
        [pscustomobject]@{ Token = '--type'; Kind = 'FileType' }
        [pscustomobject]@{ Token = '-d'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--max-depth'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--min-depth'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--exact-depth'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '-E'; Kind = 'GlobPattern' }
        [pscustomobject]@{ Token = '--exclude'; Kind = 'GlobPattern' }
        [pscustomobject]@{ Token = '-e'; Kind = 'Extension' }
        [pscustomobject]@{ Token = '--extension'; Kind = 'Extension' }
        [pscustomobject]@{ Token = '-S'; Kind = 'Size' }
        [pscustomobject]@{ Token = '--size'; Kind = 'Size' }
        [pscustomobject]@{ Token = '--changed-within'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--change-newer-than'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--newer'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--changed-after'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--changed-before'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--change-older-than'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--older'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--format'; Kind = 'Format' }
        [pscustomobject]@{ Token = '-x'; Kind = 'CommandTail' }
        [pscustomobject]@{ Token = '--exec'; Kind = 'CommandTail' }
        [pscustomobject]@{ Token = '-X'; Kind = 'CommandTail' }
        [pscustomobject]@{ Token = '--exec-batch'; Kind = 'CommandTail' }
        [pscustomobject]@{ Token = '--batch-size'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--ignore-file'; Kind = 'Path' }
        [pscustomobject]@{ Token = '--ignore-contain'; Kind = 'Name' }
        [pscustomobject]@{ Token = '-j'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--threads'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--max-results'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '-C'; Kind = 'Path' }
        [pscustomobject]@{ Token = '--base-directory'; Kind = 'Path' }
        [pscustomobject]@{ Token = '--path-separator'; Kind = 'PathSeparator' }
        [pscustomobject]@{ Token = '--search-path'; Kind = 'Path' }
        [pscustomobject]@{ Token = '--strip-cwd-prefix'; Kind = 'StripMode' }
        [pscustomobject]@{ Token = '--and'; Kind = 'Pattern' }
    )

    foreach ($entry in $entries) {
        $map[$entry.Token] = $entry.Kind
    }

    $map
}

function Get-FdColorWhenValues { @('auto', 'always', 'never') }
function Get-FdHyperlinkValues { @('auto', 'always', 'never') }
function Get-FdStripModeValues { @('auto', 'always', 'never') }
function Get-FdPathSeparatorValues { @('\', '/') }
function Get-FdFileTypeValues {
    @('f', 'file', 'd', 'dir', 'directory', 'l', 'symlink', 's', 'socket', 'p', 'pipe', 'b', 'block-device', 'c', 'char-device', 'x', 'executable', 'e', 'empty')
}
function Get-FdExtensionValues { @('ps1', 'md', 'json', 'yaml', 'yml', 'txt', 'ts', 'js', 'py', 'rs', 'go', 'zip') }
function Get-FdSizeValues { @('+1k', '-10m', '500b', '1mi', '2g') }
function Get-FdDateValues { @('1day', '2weeks', '10h', '35min', (Get-Date).ToString('yyyy-MM-dd')) }
function Get-FdFormatValues { @('{path}', '{name}', '{size}', '{modified}', '{mode}', '{type}') }

function Initialize-FdCompletionCatalog {
    $catalog = Get-FdCompletionCatalog
    if ($catalog.Initialized) {
        return
    }

    $helpLines = Invoke-FdCapture -Arguments @('--help')
    $valueKindMap = Get-FdValueKindMap

    $pendingTokenPart = $null
    $descriptionLines = [System.Collections.Generic.List[string]]::new()

    $flushPendingSpec = {
        if ([string]::IsNullOrWhiteSpace($pendingTokenPart)) {
            return
        }

        $tokens = @()
        foreach ($fragment in ($pendingTokenPart -split ',\s*')) {
            $token = $fragment.Trim()
            if ($token -notmatch '^-') {
                continue
            }

            if ($token -match '^(--[A-Za-z0-9-]+)(?:\.\.\.)?(?:\[=.*\])?(?:[ =<].*)?$') {
                $token = $matches[1]
            } elseif ($token -match '^(-[A-Za-z0-9?])(?:[ =<].*)?$') {
                $token = $matches[1]
            } elseif ($token -match '^(-\d)$') {
                $token = $matches[1]
            } else {
                continue
            }

            $tokens += $token
        }

        if ($tokens.Count -eq 0) {
            $pendingTokenPart = $null
            $descriptionLines.Clear()
            return
        }

        $description = ($descriptionLines.ToArray() -join ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($description)) {
            $description = $pendingTokenPart
        }

        $spec = [pscustomobject]@{
            Tokens      = @($tokens | Select-Object -Unique)
            Description = $description
            ValueKind   = $null
        }

        foreach ($token in $spec.Tokens) {
            if ($valueKindMap.ContainsKey($token)) {
                $spec.ValueKind = $valueKindMap[$token]
                break
            }
        }

        $catalog.Options += $spec
        foreach ($token in $spec.Tokens) {
            $catalog.OptionByToken[$token] = $spec
        }

        $pendingTokenPart = $null
        $descriptionLines.Clear()
    }

    $inOptions = $false

    foreach ($line in @($helpLines)) {
        if (-not $inOptions) {
            if ($line -eq 'Options:') {
                $inOptions = $true
            }

            continue
        }

        if ($line -match '^\s{2,}(?<tokenPart>(?:--?[A-Za-z0-9?].*))\s*$') {
            & $flushPendingSpec
            $pendingTokenPart = $matches.tokenPart.Trim()
            continue
        }

        if ($null -ne $pendingTokenPart -and $line -match '^\s{10,}(?<description>\S.*)$') {
            $descriptionLines.Add($matches.description.Trim())
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($line) -and $null -ne $pendingTokenPart) {
            & $flushPendingSpec
        }
    }

    & $flushPendingSpec

    $catalog.Initialized = $true
}

function Remove-FdOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-FdQuotedValue {
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

function Test-FdPathLikeInput {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    (Remove-FdOuterQuotes -Value $Value) -match '^(?:\.{1,2}[\\/]|[\\/]|~[\\/]|[A-Za-z]:|\\\\)'
}

function Get-FdCurrentToken {
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

function Get-FdTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-FdArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += Get-FdTokenText -Element $element
        }
    }

    $tokens
}

function Get-FdExpectedValueSpec {
    param([string[]]$TokensBeforeCurrent)

    Initialize-FdCompletionCatalog
    $catalog = Get-FdCompletionCatalog
    if (-not $TokensBeforeCurrent -or $TokensBeforeCurrent.Count -eq 0) {
        return $null
    }

    $lastToken = $TokensBeforeCurrent[-1]
    if ($catalog.OptionByToken.ContainsKey($lastToken) -and $catalog.OptionByToken[$lastToken].ValueKind) {
        return $catalog.OptionByToken[$lastToken]
    }

    $null
}

function Get-FdPathCompletions {
    param([string]$InputPath)

    $typedValue = Remove-FdOuterQuotes -Value $InputPath
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

        [void]$results.Add((New-FdCompletionResult -CompletionText (ConvertTo-FdQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote) -ToolTip $item.FullName))
    }

    @($results.ToArray())
}

function Get-FdValueCompletions {
    param(
        [object]$Spec,
        [string]$CurrentWord
    )

    switch ([string]$Spec.ValueKind) {
        'ColorWhen' {
            return Get-FdColorWhenValues | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'Color output mode.'
            }
        }
        'HyperlinkWhen' {
            return Get-FdHyperlinkValues | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'Hyperlink output mode.'
            }
        }
        'StripMode' {
            return Get-FdStripModeValues | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'Strip ./ prefix behavior.'
            }
        }
        'PathSeparator' {
            return Get-FdPathSeparatorValues | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'Path separator in printed output.'
            }
        }
        'FileType' {
            return Get-FdFileTypeValues | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'File type filter.'
            }
        }
        'Extension' {
            return Get-FdExtensionValues | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'Allowed file extension.'
            }
        }
        'Size' {
            return Get-FdSizeValues | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'File size expression.'
            }
        }
        'DateOrDuration' {
            return Get-FdDateValues | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'Date or duration filter.'
            }
        }
        'Format' {
            return Get-FdFormatValues | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'Output format placeholder.'
            }
        }
        'Path' {
            $results = @(Get-FdPathCompletions -InputPath $CurrentWord)
            if ($results.Count -eq 0) {
                return @(New-FdCompletionResult -CompletionText '<path>' -ToolTip 'Filesystem path value.')
            }
            return $results
        }
        'Integer' {
            return @('1', '2', '4', '8', '16') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'Integer value.'
            }
        }
        'GlobPattern' {
            return @('*.log', '*.tmp', 'node_modules', 'bin') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'Glob pattern.'
            }
        }
        'Pattern' {
            return @('<pattern>') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'Additional required search pattern.'
            }
        }
        'Name' {
            return @('.git', 'node_modules', '.venv') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'Directory marker name.'
            }
        }
        'CommandTail' {
            return @('{}', '{/}', '{//}', '{.}', '{/.}') | Where-Object { $_ -like "$CurrentWord*" } | ForEach-Object {
                New-FdCompletionResult -CompletionText $_ -ToolTip 'fd exec placeholder.'
            }
        }
    }

    @()
}

function Get-FdOptionCompletions {
    param([string]$CurrentWord)

    Initialize-FdCompletionCatalog
    foreach ($spec in (Get-FdCompletionCatalog).Options) {
        foreach ($token in $spec.Tokens) {
            if ($token -like "$CurrentWord*") {
                New-FdCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $spec.Description
            }
        }
    }
}

function Get-FdPositionalCount {
    param([string[]]$TokensBeforeCurrent)

    Initialize-FdCompletionCatalog
    $catalog = Get-FdCompletionCatalog
    $count = 0
    $skipNext = $false

    foreach ($token in @($TokensBeforeCurrent)) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }

        if ($catalog.OptionByToken.ContainsKey($token)) {
            if ($catalog.OptionByToken[$token].ValueKind) {
                $skipNext = $true
            }
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($token) -and -not $token.StartsWith('-')) {
            $count++
        }
    }

    $count
}

function Complete-Fd {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    Initialize-FdCompletionCatalog

    $currentWord = if ($null -eq $WordToComplete) {
        Get-FdCurrentToken -Line $CommandAst.ToString() -CursorPosition $CursorPosition -Fallback $WordToComplete
    } else {
        $WordToComplete
    }

    $tokensBeforeCurrent = @(Get-FdArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $expectedValue = Get-FdExpectedValueSpec -TokensBeforeCurrent $tokensBeforeCurrent
    if ($expectedValue) {
        return @(Get-FdValueCompletions -Spec $expectedValue -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-FdOptionCompletions -CurrentWord $currentWord)
    }

    $positionalCount = Get-FdPositionalCount -TokensBeforeCurrent $tokensBeforeCurrent
    if ($positionalCount -ge 1 -or (Test-FdPathLikeInput -Value $currentWord)) {
        $pathResults = @(Get-FdPathCompletions -InputPath $currentWord)
        if ($pathResults.Count -gt 0) {
            return $pathResults
        }
    }

    if ($positionalCount -eq 0) {
        $results = New-Object System.Collections.Generic.List[object]
        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            [void]$results.Add((New-FdCompletionResult -CompletionText '<pattern>' -ToolTip 'Search pattern (regex by default, glob with --glob).'))
        }

        foreach ($item in @(Get-FdOptionCompletions -CurrentWord $currentWord)) {
            [void]$results.Add($item)
        }

        return @($results.ToArray())
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-FdOptionCompletions -CurrentWord $currentWord)
    }

    @()
}
}

Register-ArgumentCompleter -Native -CommandName @('fd', 'fd.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Fd -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
