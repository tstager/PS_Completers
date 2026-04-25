# cargo-clippy native argument completer for PowerShell
# Help-driven completer for cargo-clippy.exe using local cargo/clippy help text.

Set-StrictMode -Version 2.0

if ($true) {
function Get-CargoClippyCompletionCache {
    $cache = Get-Variable -Name CargoClippyCompletionCache -Scope Script -ErrorAction Ignore
    if ($null -ne $cache) {
        return $cache.Value
    }

    $newCache = @{
        Initialized          = $false
        CargoClippyCommand   = $null
        CargoCommand         = $null
        CommandOptions       = @()
        CommandDescriptions  = @{}
        CommandValueMap      = @{}
        PathOptions          = @('--manifest-path', '--target-dir')
        LintOptions          = @('-W', '--warn', '-A', '--allow', '-D', '--deny', '-F', '--forbid')
        LintDescriptions     = @{}
        LintValueMap         = @{}
        UnstableFlags        = @()
    }

    Set-Variable -Name CargoClippyCompletionCache -Scope Script -Value $newCache
    $newCache
}

function Resolve-CargoClippyCommandName {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.CargoClippyCommand) {
        return $cache.CargoClippyCommand
    }

    $command = Get-Command -Name cargo-clippy.exe, cargo-clippy -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $cache.CargoClippyCommand = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $cache.CargoClippyCommand
}

function Resolve-CargoCommandName {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.CargoCommand) {
        return $cache.CargoCommand
    }

    $command = Get-Command -Name cargo.exe, cargo -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $cache.CargoCommand = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $cache.CargoCommand
}

function Invoke-CargoClippyText {
    param([string[]]$Arguments)

    $commandName = Resolve-CargoClippyCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    } catch {
        @()
    }
}

function Invoke-CargoText {
    param([string[]]$Arguments)

    $commandName = Resolve-CargoCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    } catch {
        @()
    }
}

function New-CargoClippyCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ListItemText,
        [string]$ResultType,
        [string]$ToolTip
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

function Remove-CargoClippyOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-CargoClippyQuotedPath {
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

function Get-CargoClippyPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-CargoClippyOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    [System.Management.Automation.CompletionCompleters]::CompleteFilename($cleanInput) |
        ForEach-Object {
            $completionText = ConvertTo-CargoClippyQuotedPath -Value $_.CompletionText -AlwaysQuote $alwaysQuote
            New-CargoClippyCompletionResult -CompletionText $completionText -ListItemText $_.ListItemText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }
}

function Get-CargoClippyCurrentWord {
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

function Get-CargoClippyArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += $element.Extent.Text
        }
    }

    $tokens
}

function Get-CargoClippyOptionMetadataFromLines {
    param([string[]]$Lines)

    $result = @{}

    foreach ($line in $Lines) {
        $trimmedLine = $line.TrimStart()
        $parts = $trimmedLine -split '\s{2,}', 2
        if ($parts.Count -lt 2) {
            continue
        }

        $spec = $parts[0].Trim()
        $description = $parts[1].Trim()
        if (-not $spec.StartsWith('-')) {
            continue
        }

        $tokens = @([regex]::Matches($spec, '(?:^|,\s*)(-[A-Za-z]|--[A-Za-z0-9][A-Za-z0-9\-]*)') | ForEach-Object { $_.Groups[1].Value })
        if ($tokens.Count -eq 0) {
            continue
        }

        foreach ($token in $tokens) {
            if (-not $result.ContainsKey($token)) {
                $result[$token] = $description
            }
        }
    }

    $result
}

function Get-CargoClippyCommandValueMap {
    @{
        '--color'          = @('auto', 'always', 'never')
        '--config'         = @('<KEY=VALUE>', '<path>')
        '--explain'        = @('<lint>')
        '--message-format' = @('human', 'short', 'json', 'json-diagnostic-short', 'json-diagnostic-rendered-ansi', 'json-render-diagnostics')
        '--package'        = @('<package-spec>')
        '-p'               = @('<package-spec>')
        '--exclude'        = @('<package-spec>')
        '--bin'            = @('<target-name>')
        '--example'        = @('<target-name>')
        '--test'           = @('<target-name>')
        '--bench'          = @('<target-name>')
        '--features'       = @('<features>')
        '-F'               = @('<features>')
        '--profile'        = @('<profile-name>')
        '--target'         = @('<target-triple>')
        '--manifest-path'  = @('<path>')
        '--target-dir'     = @('<path>')
        '--jobs'           = @('<jobs>')
        '-j'               = @('<jobs>')
        '-Z'               = @()
    }
}

function Get-CargoClippyLintValueMap {
    @{
        '-W'      = @('<lint>', 'clippy::<lint>')
        '--warn'  = @('<lint>', 'clippy::<lint>')
        '-A'      = @('<lint>', 'clippy::<lint>')
        '--allow' = @('<lint>', 'clippy::<lint>')
        '-D'      = @('<lint>', 'clippy::<lint>')
        '--deny'  = @('<lint>', 'clippy::<lint>')
        '-F'      = @('<lint>', 'clippy::<lint>')
        '--forbid' = @('<lint>', 'clippy::<lint>')
    }
}

function Get-CargoClippyUnstableFlags {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.UnstableFlags.Count -gt 0) {
        return $cache.UnstableFlags
    }

    $lines = Invoke-CargoText -Arguments @('-Z', 'help')
    $flags = foreach ($line in $lines) {
        if ($line -match '^\s+-Z\s+([a-z0-9][a-z0-9\-]*)\b') {
            $matches[1]
        }
    }

    $cache.UnstableFlags = @($flags | Sort-Object -Unique)
    $cache.UnstableFlags
}

function Initialize-CargoClippyCompletionCache {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.Initialized) {
        return
    }

    $clippyLines = Invoke-CargoClippyText -Arguments @('--help')
    $checkLines = Invoke-CargoText -Arguments @('check', '--help')

    $descriptions = @{}
    foreach ($entry in (Get-CargoClippyOptionMetadataFromLines -Lines $checkLines).GetEnumerator()) {
        $descriptions[$entry.Key] = $entry.Value
    }
    foreach ($entry in (Get-CargoClippyOptionMetadataFromLines -Lines $clippyLines).GetEnumerator()) {
        $descriptions[$entry.Key] = $entry.Value
    }

    $cache.CommandDescriptions = $descriptions
    $cache.CommandOptions = @($descriptions.Keys + '--') | Sort-Object -Unique
    $cache.CommandValueMap = Get-CargoClippyCommandValueMap
    $cache.LintDescriptions = @{
        '-W'       = 'Set lint warnings.'
        '--warn'   = 'Set lint warnings.'
        '-A'       = 'Set lint allowed.'
        '--allow'  = 'Set lint allowed.'
        '-D'       = 'Set lint denied.'
        '--deny'   = 'Set lint denied.'
        '-F'       = 'Set lint forbidden.'
        '--forbid' = 'Set lint forbidden.'
    }
    $cache.LintValueMap = Get-CargoClippyLintValueMap
    $cache.Initialized = $true
}

function Get-CargoClippyState {
    param([string[]]$TokensBeforeCurrent)

    Initialize-CargoClippyCompletionCache
    $cache = Get-CargoClippyCompletionCache

    $pendingOption = $null
    $afterDoubleDash = $false

    foreach ($token in $TokensBeforeCurrent) {
        $cleanToken = Remove-CargoClippyOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($pendingOption) {
            $pendingOption = $null
            continue
        }

        if ($afterDoubleDash) {
            if ($cleanToken -match '^(--[A-Za-z0-9][A-Za-z0-9\-]*)=(.*)$') {
                continue
            }

            if ($cache.LintValueMap.ContainsKey($cleanToken)) {
                $pendingOption = $cleanToken
            }
            continue
        }

        if ($cleanToken -eq '--') {
            $afterDoubleDash = $true
            continue
        }

        if ($cleanToken -match '^(--[A-Za-z0-9][A-Za-z0-9\-]*)=(.*)$') {
            continue
        }

        if ($cache.CommandValueMap.ContainsKey($cleanToken) -or $cache.PathOptions -contains $cleanToken) {
            $pendingOption = $cleanToken
        }
    }

    [pscustomobject]@{
        PendingOption   = $pendingOption
        AfterDoubleDash = $afterDoubleDash
    }
}

function Get-CargoClippyInlineValueState {
    param(
        [string]$CurrentWord,
        [bool]$AfterDoubleDash
    )

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        return $null
    }

    if ($CurrentWord -match '^(--[A-Za-z0-9][A-Za-z0-9\-]*)=(.*)$') {
        $optionName = $matches[1]
        $currentValue = $matches[2]
        return [pscustomobject]@{
            OptionName   = $optionName
            ValuePrefix  = $currentValue
            PrefixText   = "$optionName="
            AfterDoubleDash = $AfterDoubleDash
        }
    }

    $null
}

function Get-CargoClippyValueCompletions {
    param(
        [string]$OptionName,
        [string]$CurrentWord,
        [bool]$AfterDoubleDash,
        [string]$PrefixText = ''
    )

    Initialize-CargoClippyCompletionCache
    $cache = Get-CargoClippyCompletionCache
    $current = Remove-CargoClippyOuterQuotes -Value $CurrentWord

    if ($OptionName -eq '-Z' -and -not $AfterDoubleDash) {
        return @(
            Get-CargoClippyUnstableFlags |
                Where-Object { $_.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase) } |
                ForEach-Object {
                    New-CargoClippyCompletionResult -CompletionText ($PrefixText + $_) -ListItemText $_ -ResultType 'ParameterValue' -ToolTip 'Cargo unstable flag.'
                }
        )
    }

    if (-not $AfterDoubleDash -and $cache.PathOptions -contains $OptionName) {
        return @(
            Get-CargoClippyPathCompletions -InputPath $CurrentWord |
                ForEach-Object {
                    New-CargoClippyCompletionResult -CompletionText ($PrefixText + $_.CompletionText) -ListItemText $_.ListItemText -ResultType $_.ResultType -ToolTip $_.ToolTip
                }
        )
    }

    if ($OptionName -eq '--config' -and -not $AfterDoubleDash) {
        $results = @()
        $results += @(
            Get-CargoClippyPathCompletions -InputPath $CurrentWord |
                ForEach-Object {
                    New-CargoClippyCompletionResult -CompletionText ($PrefixText + $_.CompletionText) -ListItemText $_.ListItemText -ResultType $_.ResultType -ToolTip $_.ToolTip
                }
        )

        foreach ($hint in $cache.CommandValueMap[$OptionName]) {
            if ($hint.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase)) {
                $results += New-CargoClippyCompletionResult -CompletionText ($PrefixText + $hint) -ListItemText $hint -ResultType 'ParameterValue' -ToolTip 'Cargo config override.'
            }
        }

        return @($results)
    }

    $valueMap = if ($AfterDoubleDash) { $cache.LintValueMap } else { $cache.CommandValueMap }
    if (-not $valueMap.ContainsKey($OptionName)) {
        return @()
    }

    @(
        $valueMap[$OptionName] |
            Where-Object { $_.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object {
                $toolTip = if ($AfterDoubleDash) { 'Clippy lint name.' } else { "$OptionName value" }
                New-CargoClippyCompletionResult -CompletionText ($PrefixText + $_) -ListItemText $_ -ResultType 'ParameterValue' -ToolTip $toolTip
            }
    )
}

function Get-CargoClippyOptionCompletions {
    param(
        [string[]]$Options,
        [hashtable]$Descriptions,
        [string]$CurrentWord
    )

    $current = Remove-CargoClippyOuterQuotes -Value $CurrentWord
    foreach ($option in $Options | Sort-Object -Unique) {
        if ($option.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase)) {
            $resultType = if ($option -eq '--') { 'ParameterValue' } else { 'ParameterName' }
            $toolTip = if ($Descriptions.ContainsKey($option)) { $Descriptions[$option] } else { 'Pass remaining arguments to Clippy/rustc.' }
            New-CargoClippyCompletionResult -CompletionText $option -ListItemText $option -ResultType $resultType -ToolTip $toolTip
        }
    }
}

function Complete-CargoClippy {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-CargoClippyCompletionCache
    $cache = Get-CargoClippyCompletionCache

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-CargoClippyCurrentWord -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $state = Get-CargoClippyState -TokensBeforeCurrent @(Get-CargoClippyArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition)
    $inlineValue = Get-CargoClippyInlineValueState -CurrentWord $currentWord -AfterDoubleDash $state.AfterDoubleDash
    if ($inlineValue) {
        return @(Get-CargoClippyValueCompletions -OptionName $inlineValue.OptionName -CurrentWord $inlineValue.ValuePrefix -AfterDoubleDash $inlineValue.AfterDoubleDash -PrefixText $inlineValue.PrefixText)
    }

    if ($state.PendingOption) {
        return @(Get-CargoClippyValueCompletions -OptionName $state.PendingOption -CurrentWord $currentWord -AfterDoubleDash $state.AfterDoubleDash)
    }

    if ($state.AfterDoubleDash) {
        if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('-')) {
            return @(Get-CargoClippyOptionCompletions -Options $cache.LintOptions -Descriptions $cache.LintDescriptions -CurrentWord $currentWord)
        }

        @()
        return
    }

    if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('-')) {
        return @(Get-CargoClippyOptionCompletions -Options $cache.CommandOptions -Descriptions $cache.CommandDescriptions -CurrentWord $currentWord)
    }

    @()
}

}

Register-ArgumentCompleter -Native -CommandName @('cargo-clippy', 'cargo-clippy.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-CargoClippy -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
