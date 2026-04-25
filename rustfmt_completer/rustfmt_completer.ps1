<#
.SYNOPSIS
    Registers a native PowerShell argument completer for rustfmt.

.DESCRIPTION
    Provides a help-driven native completer for `rustfmt` and `rustfmt.exe`.

    The completer keeps its top level compatible with `Import-CompleterScript` by
    limiting top-level content to `Set-StrictMode`, function definitions, and one
    literal `Register-ArgumentCompleter -Native` call.
#>

Set-StrictMode -Version 2.0

function New-RustfmtCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip = $CompletionText,
        [string]$ListItemText = $CompletionText
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

function Get-RustfmtTokenState {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    if ($null -eq $Line) {
        $Line = ''
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    $tokens = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    $quoteChar = [char]0

    foreach ($character in $prefix.ToCharArray()) {
        if (($character -eq [char]34) -or ($character -eq [char]39)) {
            if ($quoteChar -eq [char]0) {
                $quoteChar = $character
            } elseif ($quoteChar -eq $character) {
                $quoteChar = [char]0
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and $quoteChar -eq [char]0) {
            if ($builder.Length -gt 0) {
                [void]$tokens.Add($builder.ToString())
                [void]$builder.Clear()
            }

            continue
        }

        [void]$builder.Append($character)
    }

    $hasTrailingSpace = $prefix -match '\s$'
    if ($builder.Length -gt 0) {
        [void]$tokens.Add($builder.ToString())
    }

    if ($hasTrailingSpace) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens.ToArray())
            CurrentToken        = ''
        }
    }

    if ($tokens.Count -gt 0) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
            CurrentToken        = $tokens[$tokens.Count - 1]
        }
    }

    [pscustomobject]@{
        TokensBeforeCurrent = @()
        CurrentToken        = ''
    }
}

function Remove-RustfmtOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2) {
        if ($Value.StartsWith('"') -and $Value.EndsWith('"')) {
            return $Value.Substring(1, $Value.Length - 2).Replace('`"', '"')
        }

        if ($Value.StartsWith("'") -and $Value.EndsWith("'")) {
            return $Value.Substring(1, $Value.Length - 2).Replace("''", "'")
        }
    }

    $Value.TrimStart('"', "'")
}

function ConvertTo-RustfmtQuotedValue {
    param(
        [string]$Value,
        [string]$OriginalToken = ''
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    $needsQuote = $Value -match '\s'
    $preferSingle = $OriginalToken.StartsWith("'")

    if (-not $needsQuote -and -not $OriginalToken.StartsWith('"') -and -not $preferSingle) {
        return $Value
    }

    if ($preferSingle -and -not $Value.Contains("'")) {
        return "'" + $Value + "'"
    }

    '"' + $Value.Replace('`', '``').Replace('"', '`"') + '"'
}

function Get-RustfmtPathCompletions {
    param(
        [string]$CurrentToken,
        [bool]$DirectoriesOnly = $false,
        [bool]$FilesOnly = $false
    )

    $raw = if ($null -eq $CurrentToken) { '' } else { $CurrentToken }
    $clean = Remove-RustfmtOuterQuotes -Value $raw

    $parentText = Split-Path -Path $clean -Parent
    $leaf = Split-Path -Path $clean -Leaf
    if ([string]::IsNullOrEmpty($parentText)) {
        $parentText = '.'
        $leaf = $clean
    }

    $literalParent = if ([string]::IsNullOrWhiteSpace($parentText)) { '.' } else { $parentText }
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    try {
        $items = Get-ChildItem -LiteralPath $literalParent -Force -ErrorAction Stop
    } catch {
        return @()
    }

    foreach ($item in $items) {
        if ($DirectoriesOnly -and -not $item.PSIsContainer) {
            continue
        }

        if ($FilesOnly -and $item.PSIsContainer) {
            continue
        }

        if ($leaf -and -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $completionPath = if ($parentText -eq '.') {
            $item.Name
        } else {
            Join-Path -Path $parentText -ChildPath $item.Name
        }

        if ($item.PSIsContainer) {
            $completionPath += [IO.Path]::DirectorySeparatorChar
        }

        $quoted = ConvertTo-RustfmtQuotedValue -Value $completionPath -OriginalToken $raw
        [void]$results.Add((New-RustfmtCompletionResult -CompletionText $quoted -ResultType 'ParameterValue' -ToolTip $item.FullName -ListItemText $item.Name))
    }

    @($results.ToArray() | Sort-Object ListItemText)
}

function Get-RustfmtCommandPath {
    if (Test-Path -LiteralPath variable:script:RustfmtCommandPath) {
        return $script:RustfmtCommandPath
    }

    $command = Get-Command -Name rustfmt.exe, rustfmt -ErrorAction SilentlyContinue | Select-Object -First 1
    $script:RustfmtCommandPath = if ($command) {
        if ($command.Source) { $command.Source } else { $command.Name }
    } else {
        $null
    }

    $script:RustfmtCommandPath
}

function Invoke-RustfmtText {
    param([string[]]$Arguments)

    $commandPath = Get-RustfmtCommandPath
    if (-not $commandPath) {
        return @()
    }

    try {
        @(& $commandPath @Arguments 2>$null)
    } catch {
        @()
    }
}

function Get-RustfmtCatalog {
    if (Test-Path -LiteralPath variable:script:RustfmtCompletionCatalog) {
        return $script:RustfmtCompletionCatalog
    }

    $switches = @(
        [pscustomobject]@{ Token = '--check'; Aliases = @('--check'); Description = 'Run in check mode.'; ValueKinds = @() }
        [pscustomobject]@{ Token = '--emit'; Aliases = @('--emit'); Description = 'Choose emitted output.'; ValueKinds = @('Emit') }
        [pscustomobject]@{ Token = '--backup'; Aliases = @('--backup'); Description = 'Backup modified files.'; ValueKinds = @() }
        [pscustomobject]@{ Token = '--config-path'; Aliases = @('--config-path'); Description = 'Path used to search for rustfmt.toml.'; ValueKinds = @('ConfigPath') }
        [pscustomobject]@{ Token = '--edition'; Aliases = @('--edition'); Description = 'Rust edition to use.'; ValueKinds = @('Edition') }
        [pscustomobject]@{ Token = '--style-edition'; Aliases = @('--style-edition'); Description = 'Style Guide edition.'; ValueKinds = @('StyleEdition') }
        [pscustomobject]@{ Token = '--color'; Aliases = @('--color'); Description = 'Colored output mode.'; ValueKinds = @('Color') }
        [pscustomobject]@{ Token = '--print-config'; Aliases = @('--print-config'); Description = 'Print config to a path or stdout.'; ValueKinds = @('PrintConfigMode', 'PrintConfigPath') }
        [pscustomobject]@{ Token = '-l'; Aliases = @('-l', '--files-with-diff'); Description = 'Print names of mismatched files.'; ValueKinds = @() }
        [pscustomobject]@{ Token = '--config'; Aliases = @('--config'); Description = 'Set config key/value pairs on the command line.'; ValueKinds = @('ConfigOverride') }
        [pscustomobject]@{ Token = '-v'; Aliases = @('-v', '--verbose'); Description = 'Verbose output.'; ValueKinds = @() }
        [pscustomobject]@{ Token = '-q'; Aliases = @('-q', '--quiet'); Description = 'Less output.'; ValueKinds = @() }
        [pscustomobject]@{ Token = '-V'; Aliases = @('-V', '--version'); Description = 'Show version information.'; ValueKinds = @() }
        [pscustomobject]@{ Token = '-h'; Aliases = @('-h', '--help'); Description = 'Show help or help topic.'; ValueKinds = @('HelpTopic') }
    )

    $aliasLookup = @{}
    foreach ($switch in $switches) {
        foreach ($alias in $switch.Aliases) {
            $aliasLookup[$alias.ToLowerInvariant()] = $switch
        }
    }

    $topHelp = Invoke-RustfmtText -Arguments @('--help')
    foreach ($line in $topHelp) {
        if ($line -match '^\s+(-\w(?:,\s+--[A-Za-z0-9\-]+)?|--[A-Za-z0-9\-]+)\b') {
            $tokenGroup = $matches[1]
            foreach ($token in ($tokenGroup -split ',\s*')) {
                $key = $token.ToLowerInvariant()
                if ($aliasLookup.ContainsKey($key)) {
                    $spec = $aliasLookup[$key]
                    if ($line -match '\s{2,}(.*)$') {
                        $spec.Description = $matches[1].Trim()
                    }
                }
            }
        }
    }

    $configKeys = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Invoke-RustfmtText -Arguments @('--help=config'))) {
        if ($line -match '^\s{2,}([a-z_][a-z0-9_]*)\b') {
            [void]$configKeys.Add($matches[1])
        }
    }

    $script:RustfmtCompletionCatalog = [pscustomobject]@{
        Switches         = $switches
        AliasLookup      = $aliasLookup
        EmitModes        = @('files', 'stdout')
        Editions         = @('2015', '2018', '2021', '2024')
        StyleEditions    = @('2015', '2018', '2021', '2024')
        Colors           = @('always', 'never', 'auto')
        PrintConfigModes = @('default', 'minimal', 'current')
        HelpTopics       = @('config')
        ConfigKeys       = @($configKeys.ToArray() | Sort-Object -Unique)
    }

    $script:RustfmtCompletionCatalog
}

function Get-RustfmtValueSuggestions {
    param(
        [string]$ValueKind,
        [string]$CurrentToken
    )

    $catalog = Get-RustfmtCatalog
    $raw = if ($null -eq $CurrentToken) { '' } else { $CurrentToken }
    $clean = Remove-RustfmtOuterQuotes -Value $raw
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    switch ($ValueKind) {
        'Emit' {
            foreach ($value in $catalog.EmitModes) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustfmtCompletionResult -CompletionText $value -ToolTip 'rustfmt emit mode'))
                }
            }
        }
        'Edition' {
            foreach ($value in $catalog.Editions) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustfmtCompletionResult -CompletionText $value -ToolTip 'Rust edition'))
                }
            }
        }
        'StyleEdition' {
            foreach ($value in $catalog.StyleEditions) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustfmtCompletionResult -CompletionText $value -ToolTip 'Style Guide edition'))
                }
            }
        }
        'Color' {
            foreach ($value in $catalog.Colors) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustfmtCompletionResult -CompletionText $value -ToolTip 'Color mode'))
                }
            }
        }
        'PrintConfigMode' {
            foreach ($value in $catalog.PrintConfigModes) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustfmtCompletionResult -CompletionText $value -ToolTip 'rustfmt --print-config mode'))
                }
            }
        }
        'HelpTopic' {
            foreach ($value in $catalog.HelpTopics) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustfmtCompletionResult -CompletionText $value -ToolTip 'rustfmt help topic'))
                }
            }
        }
        'ConfigPath' { return Get-RustfmtPathCompletions -CurrentToken $raw -DirectoriesOnly $true }
        'PrintConfigPath' { return Get-RustfmtPathCompletions -CurrentToken $raw }
        'InputFile' { return Get-RustfmtPathCompletions -CurrentToken $raw -FilesOnly $true }
        'ConfigOverride' {
            if ($clean -match '^([^=,]+)=(.*)$') {
                $key = $matches[1]
                $prefix = $matches[2]
                foreach ($suggestion in (Get-RustfmtConfigValueSuggestions -Key $key -ValuePrefix $prefix)) {
                    [void]$results.Add($suggestion)
                }
            } else {
                foreach ($value in $catalog.ConfigKeys) {
                    if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                        [void]$results.Add((New-RustfmtCompletionResult -CompletionText ($value + '=') -ToolTip 'rustfmt config key'))
                    }
                }
                if (($results.Count -eq 0) -and $clean) {
                    [void]$results.Add((New-RustfmtCompletionResult -CompletionText ($clean + '=') -ToolTip 'Custom rustfmt config key'))
                }
            }
        }
    }

    @($results.ToArray())
}

function Get-RustfmtConfigValueSuggestions {
    param(
        [string]$Key,
        [string]$ValuePrefix
    )

    $values = switch ($Key) {
        'edition' { @('2015', '2018', '2021', '2024') }
        'style_edition' { @('2015', '2018', '2021', '2024') }
        'newline_style' { @('Auto', 'Windows', 'Unix', 'Native') }
        'use_small_heuristics' { @('Off', 'Max', 'Default') }
        'match_arm_leading_pipes' { @('Always', 'Never', 'Preserve') }
        'fn_params_layout' { @('Compressed', 'Tall', 'Vertical') }
        'hard_tabs' { @('true', 'false') }
        'reorder_imports' { @('true', 'false') }
        'reorder_modules' { @('true', 'false') }
        'remove_nested_parens' { @('true', 'false') }
        'merge_derives' { @('true', 'false') }
        'use_try_shorthand' { @('true', 'false') }
        'use_field_init_shorthand' { @('true', 'false') }
        'force_explicit_abi' { @('true', 'false') }
        'disable_all_formatting' { @('true', 'false') }
        'print_misformatted_file_names' { @('true', 'false') }
        default { @() }
    }

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    foreach ($value in $values) {
        if ($value.StartsWith($ValuePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-RustfmtCompletionResult -CompletionText ($Key + '=' + $value) -ToolTip 'rustfmt config value'))
        }
    }

    if (($results.Count -eq 0) -and -not [string]::IsNullOrWhiteSpace($Key)) {
        [void]$results.Add((New-RustfmtCompletionResult -CompletionText ($Key + '=<value>') -ToolTip 'rustfmt config placeholder'))
    }

    @($results.ToArray())
}

function Get-RustfmtState {
    param([string[]]$TokensBeforeCurrent)

    $catalog = Get-RustfmtCatalog
    $pendingKinds = New-Object System.Collections.Generic.Queue[string]
    $operandCount = 0

    foreach ($token in $TokensBeforeCurrent) {
        $clean = Remove-RustfmtOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($clean)) {
            continue
        }

        if ($pendingKinds.Count -gt 0) {
            [void]$pendingKinds.Dequeue()
            continue
        }

        if ($clean -match '^(--[A-Za-z0-9\-]+)=(.*)$') {
            $optionName = $matches[1].ToLowerInvariant()
            if ($catalog.AliasLookup.ContainsKey($optionName)) {
                $spec = $catalog.AliasLookup[$optionName]
                if ($spec.ValueKinds.Count -gt 1) {
                    for ($index = 1; $index -lt $spec.ValueKinds.Count; $index++) {
                        $pendingKinds.Enqueue($spec.ValueKinds[$index])
                    }
                }
            }
            continue
        }

        $lookup = $clean.ToLowerInvariant()
        if ($catalog.AliasLookup.ContainsKey($lookup)) {
            $spec = $catalog.AliasLookup[$lookup]
            foreach ($kind in $spec.ValueKinds) {
                $pendingKinds.Enqueue($kind)
            }
            continue
        }

        if ($clean.StartsWith('-')) {
            continue
        }

        $operandCount++
    }

    [pscustomobject]@{
        PendingKinds = $pendingKinds
        OperandCount = $operandCount
    }
}

function Get-RustfmtSwitchSuggestions {
    param([string]$CurrentToken)

    $catalog = Get-RustfmtCatalog
    $clean = Remove-RustfmtOuterQuotes -Value $CurrentToken
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    foreach ($switch in $catalog.Switches) {
        foreach ($alias in $switch.Aliases) {
            if ($alias.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-RustfmtCompletionResult -CompletionText $alias -ResultType 'ParameterName' -ToolTip $switch.Description -ListItemText $alias))
            }
        }
    }

    @($results.ToArray() | Sort-Object CompletionText -Unique)
}

Register-ArgumentCompleter -Native -CommandName @('rustfmt', 'rustfmt.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $tokenState = Get-RustfmtTokenState -Line $commandAst.ToString() -CursorPosition $cursorPosition
    $currentToken = if ($null -eq $tokenState.CurrentToken) { $wordToComplete } else { $tokenState.CurrentToken }
    $tokensBeforeCurrent = @($tokenState.TokensBeforeCurrent)
    if ([string]::IsNullOrEmpty($wordToComplete) -and -not [string]::IsNullOrEmpty($currentToken)) {
        $tokensBeforeCurrent = @($tokensBeforeCurrent + $currentToken)
        $currentToken = ''
    }
    $tokensBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip 1)
    $state = Get-RustfmtState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.PendingKinds.Count -gt 0) {
        return Get-RustfmtValueSuggestions -ValueKind $state.PendingKinds.Peek() -CurrentToken $currentToken
    }

    $cleanCurrent = Remove-RustfmtOuterQuotes -Value $currentToken
    if ($cleanCurrent -match '^(--[A-Za-z0-9\-]+)=(.*)$') {
        $catalog = Get-RustfmtCatalog
        $optionName = $matches[1].ToLowerInvariant()
        if ($catalog.AliasLookup.ContainsKey($optionName)) {
            $spec = $catalog.AliasLookup[$optionName]
            if ($spec.ValueKinds.Count -gt 0) {
                return Get-RustfmtValueSuggestions -ValueKind $spec.ValueKinds[0] -CurrentToken $matches[2]
            }
        }
    }

    if ($cleanCurrent.StartsWith('-') -or [string]::IsNullOrEmpty($cleanCurrent)) {
        return Get-RustfmtSwitchSuggestions -CurrentToken $currentToken
    }

    Get-RustfmtValueSuggestions -ValueKind 'InputFile' -CurrentToken $currentToken
}
