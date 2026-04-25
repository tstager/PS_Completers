# cargo native argument completer for PowerShell
# Help-driven completer for cargo root and subcommand switches with safe local discovery.

Set-StrictMode -Version 2.0

function Get-CargoCompletionCache {
    $cache = Get-Variable -Name CargoCompletionCache -Scope Script -ErrorAction SilentlyContinue
    if ($cache) {
        return $cache.Value
    }

    $newCache = @{
        Initialized         = $false
        CommandName         = $null
        RootCommands        = @()
        RootOptions         = @()
        CommandMetadata     = @{}
        Toolchains          = @()
        Targets             = @()
        UnstableFlags       = @()
        RootValueMap        = @{}
        CommonValueMap      = @{}
        PathOptions         = @('-C', '--config')
        CommandPathOptions  = @{
            '<root>' = @('-C', '--config')
        }
    }

    Set-Variable -Name CargoCompletionCache -Scope Script -Value $newCache
    $newCache
}

function Resolve-CargoCommandName {
    $cache = Get-CargoCompletionCache
    if ($cache.CommandName) {
        return $cache.CommandName
    }

    $command = Get-Command -Name cargo.exe, cargo -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $cache.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $cache.CommandName
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

function New-CargoCompletionResult {
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

function Remove-CargoOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-CargoQuotedPath {
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

function Get-CargoPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-CargoOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    [System.Management.Automation.CompletionCompleters]::CompleteFilename($cleanInput) |
        ForEach-Object {
            $completionText = ConvertTo-CargoQuotedPath -Value $_.CompletionText -AlwaysQuote $alwaysQuote
            New-CargoCompletionResult -CompletionText $completionText -ListItemText $_.ListItemText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }
}

function Get-CargoCurrentWord {
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

function Get-CargoArgumentTokens {
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

function Get-CargoRootValueMap {
    @{
        '--color' = @('auto', 'always', 'never')
        '--config' = @('<KEY=VALUE>', '<path>')
        '--explain' = @('<error-code>')
        '-Z' = @()
    }
}

function Get-CargoCommonValueMap {
    @{
        '--color' = @('auto', 'always', 'never')
        '--message-format' = @('human', 'short', 'json', 'json-diagnostic-short', 'json-diagnostic-rendered-ansi', 'json-render-diagnostics')
        '--profile' = @('<profile>')
        '--target' = @()
        '--target-dir' = @('<path>')
        '--artifact-dir' = @('<path>')
        '--manifest-path' = @('<path>')
        '--config' = @('<KEY=VALUE>', '<path>')
        '-j' = @('<jobs>')
        '--jobs' = @('<jobs>')
        '-F' = @('<features>')
        '--features' = @('<features>')
        '-p' = @('<package-spec>')
        '--package' = @('<package-spec>')
        '--exclude' = @('<package-spec>')
        '--bin' = @('<target-name>')
        '--example' = @('<target-name>')
        '--test' = @('<target-name>')
        '--bench' = @('<target-name>')
        '--timings' = @('<format>')
    }
}

function Get-CargoCommandValueHints {
    param([string]$CommandName)

    switch ($CommandName) {
        'add' {
            return @{
                '--rename' = @('<crate-name>')
                '--registry' = @('<registry>')
                '--target' = @()
                '--path' = @('<path>')
                '--git' = @('<url>')
                '--branch' = @('<branch>')
                '--tag' = @('<tag>')
                '--rev' = @('<rev>')
                '--features' = @('<features>')
                '--base' = @('dev-dependencies', 'build-dependencies', 'dependencies')
                '--public' = @('true', 'false')
            }
        }
        'install' {
            return @{
                '--version' = @('<version>')
                '--git' = @('<url>')
                '--branch' = @('<branch>')
                '--tag' = @('<tag>')
                '--rev' = @('<rev>')
                '--path' = @('<path>')
                '--root' = @('<path>')
                '--registry' = @('<registry>')
                '--target' = @()
                '--profile' = @('<profile>')
                '--bin' = @('<binary-name>')
                '--example' = @('<example-name>')
                '--features' = @('<features>')
            }
        }
        'new' {
            return @{
                '--name' = @('<package-name>')
                '--vcs' = @('git', 'hg', 'pijul', 'fossil', 'none')
                '--registry' = @('<registry>')
            }
        }
        'init' {
            return @{
                '--name' = @('<package-name>')
                '--vcs' = @('git', 'hg', 'pijul', 'fossil', 'none')
                '--registry' = @('<registry>')
            }
        }
        'publish' {
            return @{
                '--registry' = @('<registry>')
                '--token' = @('<token>')
                '--target' = @()
            }
        }
        'login' {
            return @{
                '--registry' = @('<registry>')
                '--token' = @('<token>')
            }
        }
        'owner' {
            return @{
                '--registry' = @('<registry>')
                '--token' = @('<token>')
                '--add' = @('<user>')
                '--remove' = @('<user>')
            }
        }
        'search' {
            return @{
                '--limit' = @('<count>')
                '--registry' = @('<registry>')
                '--index' = @('<url>')
            }
        }
        'test' {
            return @{
                '--message-format' = @('human', 'short', 'json', 'json-diagnostic-short', 'json-diagnostic-rendered-ansi', 'json-render-diagnostics')
                '--target' = @()
            }
        }
        default {
            return @{}
        }
    }
}

function Get-CargoCommandPathOptions {
    param([string]$CommandName)

    switch ($CommandName) {
        'build' { @('--manifest-path', '--target-dir', '--artifact-dir', '--config') }
        'check' { @('--manifest-path', '--target-dir', '--artifact-dir', '--config') }
        'clean' { @('--manifest-path', '--target-dir', '--config') }
        'doc' { @('--manifest-path', '--target-dir', '--config') }
        'run' { @('--manifest-path', '--target-dir', '--config') }
        'test' { @('--manifest-path', '--target-dir', '--config') }
        'bench' { @('--manifest-path', '--target-dir', '--config') }
        'update' { @('--manifest-path', '--config') }
        'search' { @('--config') }
        'publish' { @('--manifest-path', '--config') }
        'install' { @('--path', '--root', '--config') }
        'uninstall' { @('--root', '--config') }
        'metadata' { @('--manifest-path', '--config') }
        'locate-project' { @('--manifest-path', '--config') }
        'package' { @('--manifest-path', '--target-dir', '--config') }
        'new' { @('--config') }
        'init' { @('--config') }
        'config' { @('--config') }
        default { @('--config') }
    }
}

function Get-CargoToolchainCompletions {
    param([string]$CurrentWord)

    $cache = Get-CargoCompletionCache
    if ($cache.Toolchains.Count -eq 0) {
        $lines = @(Invoke-CargoText -Arguments @('+stable', '--version'))
        if ($lines.Count -gt 0) {
            $cache.Toolchains += 'stable'
        }

        $rustup = Get-Command -Name rustup.exe, rustup -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($rustup) {
            try {
                $cache.Toolchains += @(& $rustup.Source 'toolchain' 'list' 2>$null |
                    ForEach-Object { ($_ -replace '\s+\([^)]*\)$', '').Trim() } |
                    Where-Object { $_ })
            } catch {
            }
        }

        $cache.Toolchains = @($cache.Toolchains | Sort-Object -Unique)
    }

    foreach ($toolchain in $cache.Toolchains) {
        $completion = "+$toolchain"
        if ($completion.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-CargoCompletionResult -CompletionText $completion -ListItemText $completion -ResultType 'ParameterValue' -ToolTip 'Rustup toolchain override.'
        }
    }
}

function Get-CargoTargetValues {
    $cache = Get-CargoCompletionCache
    if ($cache.Targets.Count -eq 0) {
        $rustc = Get-Command -Name rustc.exe, rustc -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($rustc) {
            try {
                $cache.Targets = @(& $rustc.Source '--print' 'target-list' 2>$null | Where-Object { $_ } | Sort-Object -Unique)
            } catch {
                $cache.Targets = @()
            }
        }
    }

    $cache.Targets
}

function Get-CargoUnstableFlags {
    $cache = Get-CargoCompletionCache
    if ($cache.UnstableFlags.Count -eq 0) {
        $lines = Invoke-CargoText -Arguments @('-Z', 'help')
        $flags = foreach ($line in $lines) {
            if ($line -match '^\s+-Z\s+([a-z0-9][a-z0-9\-]*)\b') {
                $matches[1]
            }
        }

        $cache.UnstableFlags = @($flags | Sort-Object -Unique)
    }

    $cache.UnstableFlags
}

function Get-CargoCommandNamesFromList {
    $lines = Invoke-CargoText -Arguments @('--list')
    $commands = foreach ($line in $lines) {
        if ($line -match '^\s{4}([A-Za-z0-9][A-Za-z0-9\-_]*)\s{2,}.*$') {
            $matches[1]
        }
    }

    @($commands | Sort-Object -Unique)
}

function Get-CargoRootCommandsFromHelp {
    $lines = Invoke-CargoText -Arguments @('--help')
    $commands = foreach ($line in $lines) {
        if ($line -match '^\s{4}([A-Za-z0-9][A-Za-z0-9\-_]*)\s*,?\s*([A-Za-z0-9][A-Za-z0-9\-_]*)?\s{2,}.*$') {
            $matches[1]
            if ($matches[2]) {
                $matches[2]
            }
        }
    }

    @($commands | Sort-Object -Unique)
}

function Get-CargoOptionsFromHelp {
    param([string[]]$Lines)

    $options = foreach ($line in $Lines) {
        if ($line -match '^\s{2,}((?:-[A-Za-z][A-Za-z0-9]?|--[A-Za-z0-9][A-Za-z0-9\-]*)(?:,\s*(?:-[A-Za-z][A-Za-z0-9]?|--[A-Za-z0-9][A-Za-z0-9\-]*))*)\b') {
            foreach ($token in ($matches[1] -split ',\s*')) {
                $cleanToken = $token.Trim()
                if ($cleanToken -match '^(?<name>-[A-Za-z][A-Za-z0-9]?|--[A-Za-z0-9][A-Za-z0-9\-]*)$') {
                    $matches['name']
                }
            }
        }
    }

    @($options | Sort-Object -Unique)
}

function Initialize-CargoCompletionCache {
    $cache = Get-CargoCompletionCache
    if ($cache.Initialized) {
        return
    }

    $cache.RootValueMap = Get-CargoRootValueMap
    $cache.CommonValueMap = Get-CargoCommonValueMap

    $rootHelp = Invoke-CargoText -Arguments @('--help')
    $cache.RootOptions = Get-CargoOptionsFromHelp -Lines $rootHelp
    $cache.RootCommands = @(
        Get-CargoRootCommandsFromHelp
        Get-CargoCommandNamesFromList
        'help'
    ) | Sort-Object -Unique

    $cache.CommandMetadata['<root>'] = [pscustomobject]@{
        Options    = @($cache.RootOptions)
        ValueHints = $cache.RootValueMap
        PathOptions = @($cache.PathOptions)
    }

    $cache.Initialized = $true
}

function Get-CargoCommandMetadata {
    param([string]$CommandName)

    Initialize-CargoCompletionCache
    $cache = Get-CargoCompletionCache
    $lookupName = if ([string]::IsNullOrWhiteSpace($CommandName)) { '<root>' } else { $CommandName }

    if ($cache.CommandMetadata.ContainsKey($lookupName)) {
        return $cache.CommandMetadata[$lookupName]
    }

    $helpLines = Invoke-CargoText -Arguments @('help', $CommandName)
    $options = Get-CargoOptionsFromHelp -Lines $helpLines

    $valueHints = @{}
    foreach ($key in $cache.CommonValueMap.Keys) {
        $valueHints[$key] = @($cache.CommonValueMap[$key])
    }

    $commandValueHints = Get-CargoCommandValueHints -CommandName $CommandName
    foreach ($key in $commandValueHints.Keys) {
        $valueHints[$key] = @($commandValueHints[$key])
    }

    if ($options -contains '-Z') {
        $valueHints['-Z'] = @()
    }

    $metadata = [pscustomobject]@{
        Options     = @($options)
        ValueHints  = $valueHints
        PathOptions = @(Get-CargoCommandPathOptions -CommandName $CommandName)
    }

    $cache.CommandMetadata[$lookupName] = $metadata
    $metadata
}

function Get-CargoState {
    param([string[]]$TokensBeforeCurrent)

    Initialize-CargoCompletionCache
    $cache = Get-CargoCompletionCache

    $globalOptionsWithValues = @('+toolchain', '--config', '--color', '--explain', '-Z', '-C')
    $rootCommands = @($cache.RootCommands)
    $commandName = $null
    $commandTokens = New-Object System.Collections.Generic.List[string]
    $pendingOption = $null
    $sawDoubleDash = $false

    for ($i = 0; $i -lt $TokensBeforeCurrent.Count; $i++) {
        $token = Remove-CargoOuterQuotes -Value $TokensBeforeCurrent[$i]
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        if ($pendingOption) {
            if (-not $commandName) {
                $pendingOption = $null
                continue
            }

            $commandTokens.Add($token)
            $pendingOption = $null
            continue
        }

        if ($sawDoubleDash) {
            $commandTokens.Add($token)
            continue
        }

        if ($token -eq '--') {
            if ($commandName) {
                $sawDoubleDash = $true
            }
            else {
                $pendingOption = $null
            }
            continue
        }

        if (-not $commandName) {
            if ($token.StartsWith('+')) {
                continue
            }

            if ($token -match '^(--config|--color|--explain|-Z|-C)$') {
                $pendingOption = $token
                continue
            }

            if ($token.StartsWith('-')) {
                continue
            }

            if ($rootCommands -contains $token) {
                $commandName = $token
                continue
            }

            continue
        }

        $commandTokens.Add($token)
    }

    $commandMetadata = Get-CargoCommandMetadata -CommandName $commandName
    $commandPendingOption = $null
    $positionals = New-Object System.Collections.Generic.List[string]
    $afterDoubleDash = $false

    foreach ($token in $commandTokens) {
        if ($commandPendingOption) {
            $positionals.Add($token)
            $commandPendingOption = $null
            continue
        }

        if ($token -eq '--') {
            $afterDoubleDash = $true
            continue
        }

        if (-not $afterDoubleDash -and $token -in $commandMetadata.Options) {
            if ($commandMetadata.ValueHints.ContainsKey($token) -or $commandMetadata.PathOptions -contains $token) {
                $commandPendingOption = $token
                continue
            }

            continue
        }

        $positionals.Add($token)
    }

    [pscustomobject]@{
        CommandName         = $commandName
        CommandMetadata     = $commandMetadata
        PendingGlobalOption = $pendingOption
        PendingOption       = $commandPendingOption
        Positionals         = @($positionals)
        AfterDoubleDash     = $afterDoubleDash
    }
}

function Get-CargoValueCompletions {
    param(
        [string]$OptionName,
        [string]$CurrentWord,
        [pscustomobject]$State
    )

    $current = Remove-CargoOuterQuotes -Value $CurrentWord

    switch ($OptionName) {
        '+toolchain' {
            return @(Get-CargoToolchainCompletions -CurrentWord $CurrentWord)
        }
        '-C' {
            return @(Get-CargoPathCompletions -InputPath $CurrentWord)
        }
        '--config' {
            $results = @()
            $results += @(Get-CargoPathCompletions -InputPath $CurrentWord)
            foreach ($placeholder in @('<KEY=VALUE>')) {
                if ($placeholder.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $results += New-CargoCompletionResult -CompletionText $placeholder -ListItemText $placeholder -ResultType 'ParameterValue' -ToolTip 'Cargo configuration override.'
                }
            }
            return @($results)
        }
        '--target' {
            return @(
                Get-CargoTargetValues |
                    Where-Object { $_.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase) } |
                    ForEach-Object {
                        New-CargoCompletionResult -CompletionText $_ -ListItemText $_ -ResultType 'ParameterValue' -ToolTip 'Rust target triple.'
                    }
            )
        }
        '-Z' {
            return @(
                Get-CargoUnstableFlags |
                    Where-Object { $_.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase) } |
                    ForEach-Object {
                        New-CargoCompletionResult -CompletionText $_ -ListItemText $_ -ResultType 'ParameterValue' -ToolTip 'Cargo unstable flag.'
                    }
            )
        }
    }

    if ($State.CommandMetadata.PathOptions -contains $OptionName) {
        return @(Get-CargoPathCompletions -InputPath $CurrentWord)
    }

    if ($State.CommandMetadata.ValueHints.ContainsKey($OptionName)) {
        return @(
            $State.CommandMetadata.ValueHints[$OptionName] |
                Where-Object { $_.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase) } |
                ForEach-Object {
                    New-CargoCompletionResult -CompletionText $_ -ListItemText $_ -ResultType 'ParameterValue' -ToolTip "$OptionName value"
                }
        )
    }

    @()
}

function Get-CargoOptionCompletions {
    param(
        [string[]]$Options,
        [string]$CurrentWord
    )

    $current = Remove-CargoOuterQuotes -Value $CurrentWord
    foreach ($option in $Options | Sort-Object -Unique) {
        if ($option.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-CargoCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip $option
        }
    }
}

function Get-CargoCommandCompletions {
    param([string]$CurrentWord)

    Initialize-CargoCompletionCache
    $cache = Get-CargoCompletionCache
    $current = Remove-CargoOuterQuotes -Value $CurrentWord

    foreach ($command in $cache.RootCommands) {
        if ($command.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-CargoCompletionResult -CompletionText $command -ListItemText $command -ResultType 'ParameterValue' -ToolTip 'cargo subcommand'
        }
    }
}

function Complete-Cargo {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-CargoCompletionCache

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-CargoCurrentWord -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $state = Get-CargoState -TokensBeforeCurrent @(Get-CargoArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition)

    if (-not $state.CommandName) {
        if ($state.PendingGlobalOption) {
            return @(Get-CargoValueCompletions -OptionName $state.PendingGlobalOption -CurrentWord $currentWord -State $state)
        }

        if ($currentWord.StartsWith('+')) {
            return @(Get-CargoToolchainCompletions -CurrentWord $currentWord)
        }

        $results = @()
        if ($currentWord.StartsWith('-')) {
            return @(Get-CargoOptionCompletions -Options $state.CommandMetadata.Options -CurrentWord $currentWord)
        }
        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            $results += @(Get-CargoOptionCompletions -Options $state.CommandMetadata.Options -CurrentWord '')
        }
        $results += @(Get-CargoCommandCompletions -CurrentWord $currentWord)
        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            $results += @(Get-CargoToolchainCompletions -CurrentWord '')
        }

        return @($results)
    }

    if ($state.CommandName -eq 'help' -and $state.Positionals.Count -eq 0 -and -not $state.PendingOption) {
        if ($currentWord.StartsWith('-')) {
            return @(Get-CargoOptionCompletions -Options $state.CommandMetadata.Options -CurrentWord $currentWord)
        }

        $results = @()
        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            $results += @(Get-CargoOptionCompletions -Options $state.CommandMetadata.Options -CurrentWord '')
        }
        $results += @(Get-CargoCommandCompletions -CurrentWord $currentWord)
        return @($results)
    }

    if ($state.PendingOption) {
        return @(Get-CargoValueCompletions -OptionName $state.PendingOption -CurrentWord $currentWord -State $state)
    }

    if ($state.AfterDoubleDash) {
        return @()
    }

    $optionResults = @()
    if ($currentWord.StartsWith('-')) {
        return @(Get-CargoOptionCompletions -Options $state.CommandMetadata.Options -CurrentWord $currentWord)
    }
    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        $optionResults = @(Get-CargoOptionCompletions -Options $state.CommandMetadata.Options -CurrentWord '')
    }

    switch ($state.CommandName) {
        'new' {
            if ($state.Positionals.Count -eq 0) {
                return @($optionResults + @(Get-CargoPathCompletions -InputPath $currentWord))
            }
        }
        'init' {
            if ($state.Positionals.Count -eq 0) {
                return @($optionResults + @(Get-CargoPathCompletions -InputPath $currentWord))
            }
        }
        'install' {
            if ($state.Positionals.Count -eq 0) {
                $results = @()
                $results += @(Get-CargoPathCompletions -InputPath $currentWord)
                if ('<crate>'.StartsWith((Remove-CargoOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                    $results += New-CargoCompletionResult -CompletionText '<crate>' -ListItemText '<crate>' -ResultType 'ParameterValue' -ToolTip 'Crate name or path.'
                }

                return @($optionResults + $results)
            }
        }
        'uninstall' {
            if ($state.Positionals.Count -eq 0) {
                if ('<crate>'.StartsWith((Remove-CargoOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                    return @($optionResults + @(New-CargoCompletionResult -CompletionText '<crate>' -ListItemText '<crate>' -ResultType 'ParameterValue' -ToolTip 'Installed crate name.'))
                }
            }
        }
        'search' {
            if ($state.Positionals.Count -eq 0) {
                if ('<query>'.StartsWith((Remove-CargoOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                    return @($optionResults + @(New-CargoCompletionResult -CompletionText '<query>' -ListItemText '<query>' -ResultType 'ParameterValue' -ToolTip 'Search query.'))
                }
            }
        }
        'test' {
            if ($state.Positionals.Count -eq 0) {
                if ('<test-filter>'.StartsWith((Remove-CargoOuterQuotes -Value $currentWord), [System.StringComparison]::OrdinalIgnoreCase)) {
                    return @($optionResults + @(New-CargoCompletionResult -CompletionText '<test-filter>' -ListItemText '<test-filter>' -ResultType 'ParameterValue' -ToolTip 'Optional test name filter.'))
                }
            }
        }
    }

    @($optionResults)
}

Register-ArgumentCompleter -Native -CommandName @('cargo', 'cargo.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Cargo -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
