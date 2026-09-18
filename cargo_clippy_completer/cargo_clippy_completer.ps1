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
        PathOptions          = @('-m', '--manifest-path', '--target-dir')
        LintOptions          = @('-W', '--warn', '-A', '--allow', '-D', '--deny', '-F', '--forbid')
        LintDescriptions     = @{}
        LintValueMap         = @{}
        UnstableFlags        = @()
        LintNames            = @()
        LintNamesLoaded      = $false
        TargetTriples        = @()
        TargetTriplesLoaded  = $false
        ManifestFacts        = $null
        ManifestLoadedFor    = $null
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
        @(& $commandName @Arguments 2>&1 | ForEach-Object { $_.ToString() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })
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
        @(& $commandName @Arguments 2>&1 | ForEach-Object { $_.ToString() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })
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

    # -F/--forbid and -F/--features are different options, so the table has to be case-exact.
    $result = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)

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

        # clippy writes its lint-level pairs as '-W / --warn [LINT]', cargo writes '-W, --warn'.
        $tokens = @([regex]::Matches($spec, '(?:^|,\s*|\s*/\s*)(-[A-Za-z]|--[A-Za-z0-9][A-Za-z0-9\-]*)') | ForEach-Object { $_.Groups[1].Value })
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
        '-m'               = @('<path>')
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

    $cache.UnstableFlags = @($flags | Sort-Object -Unique -CaseSensitive)
    $cache.UnstableFlags
}

function Get-CargoClippyLintCatalog {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.LintNamesLoaded) {
        return $cache.LintNames
    }

    $cache.LintNamesLoaded = $true

    $driver = Get-Command -Name clippy-driver.exe, clippy-driver -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $driver) {
        return $cache.LintNames
    }

    $raw = try {
        $null | & $driver.Source '-W' 'help' 2>&1 | ForEach-Object { $_.ToString() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' }
    } catch {
        @()
    }

    $lines = @($raw)

    $names = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    [void]$seen.Add('warnings')
    [void]$names.Add([pscustomobject]@{ Name = 'warnings'; ToolTip = 'The group of every lint that is set to warn.' })

    $inGroups = $false
    foreach ($line in $lines) {
        if ($line -match '^Lint groups ') {
            $inGroups = $true
            continue
        }

        if ($line -match '^Lint checks ') {
            $inGroups = $false
            continue
        }

        if ($line -notmatch '^\s+((?:clippy::)?[a-z][a-z0-9_-]*)\s{2,}(\S.*)$') {
            continue
        }

        $name = $matches[1]
        $detail = $matches[2].Trim()
        if ($name -eq 'name' -or -not $seen.Add($name)) {
            continue
        }

        $toolTip = if ($inGroups) { "Lint group: $detail" } else { $detail }
        [void]$names.Add([pscustomobject]@{ Name = $name; ToolTip = $toolTip })
    }

    $cache.LintNames = @($names.ToArray())
    $cache.LintNames
}

function Get-CargoClippyTargetTripleList {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.TargetTriplesLoaded) {
        return $cache.TargetTriples
    }

    $cache.TargetTriplesLoaded = $true

    $rustup = Get-Command -Name rustup.exe, rustup -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($rustup) {
        $raw = try {
            $null | & $rustup.Source 'target' 'list' '--installed' 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        } catch {
            @()
        }

        $cache.TargetTriples = @($raw)
    }

    if (@($cache.TargetTriples).Count -eq 0) {
        $rustc = Get-Command -Name rustc.exe, rustc -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($rustc) {
            $raw = try {
                $null | & $rustc.Source '--print' 'target-list' 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            } catch {
                @()
            }

            $cache.TargetTriples = @($raw)
        }
    }

    $cache.TargetTriples
}

function Get-CargoClippyManifestInfo {
    $cache = Get-CargoClippyCompletionCache

    $manifestPath = $null
    $directory = $PWD.ProviderPath
    while (-not [string]::IsNullOrWhiteSpace($directory)) {
        $candidate = Join-Path -Path $directory -ChildPath 'Cargo.toml'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $manifestPath = $candidate
            break
        }

        $directory = Split-Path -Path $directory -Parent
    }

    if ($cache.ManifestLoadedFor -eq $manifestPath -and $null -ne $cache.ManifestFacts) {
        return $cache.ManifestFacts
    }

    $profiles = New-Object System.Collections.Generic.List[string]
    foreach ($builtIn in @('dev', 'release', 'test', 'bench')) {
        [void]$profiles.Add($builtIn)
    }

    $features = New-Object System.Collections.Generic.List[string]
    $packages = New-Object System.Collections.Generic.List[string]
    $targets = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($kind in @('bin', 'example', 'test', 'bench')) {
        $targets[$kind] = New-Object System.Collections.Generic.List[string]
    }

    $raw = if ($manifestPath) {
        try {
            Get-Content -LiteralPath $manifestPath -ErrorAction Stop
        } catch {
            @()
        }
    } else {
        @()
    }

    $lines = @($raw)

    $section = ''
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[\[?([^\]]+)\]\]?$') {
            $section = $matches[1].Trim()
            if ($section -match '^profile\.([^.]+)') {
                [void]$profiles.Add($matches[1].Trim('"', "'"))
            }
            continue
        }

        if ($trimmed -match '^([A-Za-z0-9_"''.-]+)\s*=') {
            $key = $matches[1].Trim('"', "'")
            switch -Regex ($section) {
                '^features$' { [void]$features.Add($key) }
                '^(package|bin|example|test|bench)$' {
                    if ($key -eq 'name' -and $trimmed -match '=\s*["'']([^"'']+)["'']') {
                        if ($section -eq 'package') {
                            [void]$packages.Add($matches[1])
                        } else {
                            [void]$targets[$section].Add($matches[1])
                        }
                    }
                }
            }
        }
    }

    $facts = [pscustomobject]@{
        Profiles = @($profiles | Sort-Object -Unique -CaseSensitive)
        Features = @($features | Sort-Object -Unique -CaseSensitive)
        Packages = @($packages | Sort-Object -Unique -CaseSensitive)
        Targets  = $targets
    }

    $cache.ManifestFacts = $facts
    $cache.ManifestLoadedFor = $manifestPath
    $facts
}

function Get-CargoClippyDynamicValueList {
    param(
        [string]$OptionName,
        [bool]$AfterDoubleDash
    )

    if ($AfterDoubleDash) {
        return @(Get-CargoClippyLintCatalog)
    }

    if ($OptionName -eq '--explain') {
        return @(Get-CargoClippyLintCatalog)
    }

    if ($OptionName -eq '--target') {
        return @(Get-CargoClippyTargetTripleList | ForEach-Object { [pscustomobject]@{ Name = $_; ToolTip = 'Rust target triple.' } })
    }

    $facts = Get-CargoClippyManifestInfo
    $values = switch ($OptionName) {
        '--profile' { @($facts.Profiles); break }
        '--features' { @($facts.Features); break }
        '-F' { @($facts.Features); break }
        '--package' { @($facts.Packages); break }
        '-p' { @($facts.Packages); break }
        '--exclude' { @($facts.Packages); break }
        '--bin' { @($facts.Targets['bin']); break }
        '--example' { @($facts.Targets['example']); break }
        '--test' { @($facts.Targets['test']); break }
        '--bench' { @($facts.Targets['bench']); break }
        default { @() }
    }

    @($values | ForEach-Object { [pscustomobject]@{ Name = $_; ToolTip = "$OptionName value from the local Cargo.toml." } })
}

function Initialize-CargoClippyCompletionCache {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.Initialized) {
        return
    }

    $clippyLines = Invoke-CargoClippyText -Arguments @('--help')
    $checkLines = Invoke-CargoText -Arguments @('check', '--help')

    $descriptions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in (Get-CargoClippyOptionMetadataFromLines -Lines $checkLines).GetEnumerator()) {
        $descriptions[$entry.Key] = $entry.Value
    }
    foreach ($entry in (Get-CargoClippyOptionMetadataFromLines -Lines $clippyLines).GetEnumerator()) {
        # The lint-level flags clippy documents are only accepted after '--'; keeping them out here
        # also stops clippy's '-F / --forbid' text from overwriting cargo's '-F, --features'.
        if ($cache.LintOptions -ccontains $entry.Key) {
            continue
        }

        $descriptions[$entry.Key] = $entry.Value
    }

    $cache.CommandDescriptions = $descriptions
    $cache.CommandOptions = @($descriptions.Keys + '--') | Sort-Object -Unique -CaseSensitive
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

    $dynamic = @(Get-CargoClippyDynamicValueList -OptionName $OptionName -AfterDoubleDash $AfterDoubleDash |
            Where-Object { $_.Name.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($dynamic.Count -gt 0) {
        return @(
            $dynamic | ForEach-Object {
                New-CargoClippyCompletionResult -CompletionText ($PrefixText + $_.Name) -ListItemText $_.Name -ResultType 'ParameterValue' -ToolTip $_.ToolTip
            }
        )
    }

    $literal = @(
        $valueMap[$OptionName] |
            Where-Object { $_.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object {
                $toolTip = if ($AfterDoubleDash) { 'Clippy lint name.' } else { "$OptionName value" }
                New-CargoClippyCompletionResult -CompletionText ($PrefixText + $_) -ListItemText $_ -ResultType 'ParameterValue' -ToolTip $toolTip
            }
    )
    if ($literal.Count -gt 0) {
        return $literal
    }

    # A free-form value slot must keep what the user typed rather than collapse to nothing, which
    # would hand the slot to PowerShell's filename fallback.
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        $toolTip = if ($AfterDoubleDash) { 'Clippy lint name.' } else { "$OptionName value" }
        return @(New-CargoClippyCompletionResult -CompletionText ($PrefixText + $current) -ListItemText $current -ResultType 'ParameterValue' -ToolTip $toolTip)
    }

    @()
}

function Get-CargoClippyOptionCompletions {
    param(
        [string[]]$Options,
        [object]$Descriptions,
        [string]$CurrentWord
    )

    $current = Remove-CargoClippyOuterQuotes -Value $CurrentWord

    # -V (--version) and -v (--verbose) are different options, so a single-dash word must be
    # matched ordinally or tab would silently rewrite one into the other.
    $comparison = if ($current -match '^-[^-]') {
        [System.StringComparison]::Ordinal
    } else {
        [System.StringComparison]::OrdinalIgnoreCase
    }

    foreach ($option in $Options | Sort-Object -Unique -CaseSensitive) {
        if ($option.StartsWith($current, $comparison)) {
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
        Get-CargoClippyCurrentWord -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
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
