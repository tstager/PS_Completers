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

function Split-RustfmtPathToken {
    param([string]$Value)

    # Split on the last separator instead of Split-Path: Split-Path throws on an
    # empty string, and on a trailing separator it returns the directory itself
    # as the leaf, which makes tab-walking a tree impossible.
    if ([string]::IsNullOrEmpty($Value)) {
        return [pscustomobject]@{ Prefix = ''; Parent = '.'; Leaf = '' }
    }

    if ($Value -match '^[A-Za-z]:$') {
        return [pscustomobject]@{ Prefix = $Value; Parent = ($Value + [IO.Path]::DirectorySeparatorChar); Leaf = '' }
    }

    $index = $Value.LastIndexOfAny([char[]]@('\', '/'))
    if ($index -lt 0) {
        return [pscustomobject]@{ Prefix = ''; Parent = '.'; Leaf = $Value }
    }

    $prefix = $Value.Substring(0, $index + 1)
    [pscustomobject]@{ Prefix = $prefix; Parent = $prefix; Leaf = $Value.Substring($index + 1) }
}

function Get-RustfmtPathCompletions {
    param(
        [string]$CurrentToken,
        [bool]$DirectoriesOnly = $false,
        [bool]$FilesOnly = $false,
        [bool]$RustSourceOnly = $false
    )

    $raw = if ($null -eq $CurrentToken) { '' } else { $CurrentToken }
    $clean = Remove-RustfmtOuterQuotes -Value $raw
    $split = Split-RustfmtPathToken -Value $clean
    $leaf = $split.Leaf
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    try {
        $items = Get-ChildItem -LiteralPath $split.Parent -Force -ErrorAction Stop
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

        if ($RustSourceOnly -and -not $item.PSIsContainer -and $item.Extension -ne '.rs') {
            continue
        }

        if ($leaf -and -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $completionPath = $split.Prefix + $item.Name
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
        [pscustomobject]@{ Token = '--check'; Aliases = @('--check'); Description = 'Run in check mode.'; ValueKinds = @(); AttachedValueKind = '' }
        [pscustomobject]@{ Token = '--emit'; Aliases = @('--emit'); Description = 'Choose emitted output.'; ValueKinds = @('Emit'); AttachedValueKind = 'Emit' }
        [pscustomobject]@{ Token = '--backup'; Aliases = @('--backup'); Description = 'Backup modified files.'; ValueKinds = @(); AttachedValueKind = '' }
        [pscustomobject]@{ Token = '--config-path'; Aliases = @('--config-path'); Description = 'Path used to search for rustfmt.toml.'; ValueKinds = @('ConfigPath'); AttachedValueKind = 'ConfigPath' }
        [pscustomobject]@{ Token = '--edition'; Aliases = @('--edition'); Description = 'Rust edition to use.'; ValueKinds = @('Edition'); AttachedValueKind = 'Edition' }
        [pscustomobject]@{ Token = '--style-edition'; Aliases = @('--style-edition'); Description = 'Style Guide edition.'; ValueKinds = @('StyleEdition'); AttachedValueKind = 'StyleEdition' }
        [pscustomobject]@{ Token = '--color'; Aliases = @('--color'); Description = 'Colored output mode.'; ValueKinds = @('Color'); AttachedValueKind = 'Color' }
        [pscustomobject]@{ Token = '--print-config'; Aliases = @('--print-config'); Description = 'Print config to a path or stdout.'; ValueKinds = @('PrintConfigMode', 'PrintConfigPath'); AttachedValueKind = 'PrintConfigMode' }
        [pscustomobject]@{ Token = '-l'; Aliases = @('-l', '--files-with-diff'); Description = 'Print names of mismatched files.'; ValueKinds = @(); AttachedValueKind = '' }
        [pscustomobject]@{ Token = '--config'; Aliases = @('--config'); Description = 'Set config key/value pairs on the command line.'; ValueKinds = @('ConfigOverride'); AttachedValueKind = 'ConfigOverride' }
        [pscustomobject]@{ Token = '-v'; Aliases = @('-v', '--verbose'); Description = 'Verbose output.'; ValueKinds = @(); AttachedValueKind = '' }
        [pscustomobject]@{ Token = '-q'; Aliases = @('-q', '--quiet'); Description = 'Less output.'; ValueKinds = @(); AttachedValueKind = '' }
        [pscustomobject]@{ Token = '-V'; Aliases = @('-V', '--version'); Description = 'Show version information.'; ValueKinds = @(); AttachedValueKind = '' }
        # rustfmt spells the help topic `-h [=TOPIC]`: it is attached-only, so it
        # must not be offered as a detached token.
        [pscustomobject]@{ Token = '-h'; Aliases = @('-h', '--help'); Description = 'Show help or help about a topic.'; ValueKinds = @(); AttachedValueKind = 'HelpTopic' }
    )

    # Ordinal: -v (verbose) and -V (version) are different options, and a
    # case-insensitive map silently keeps only one of them.
    $aliasLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($switch in $switches) {
        foreach ($alias in $switch.Aliases) {
            $aliasLookup[$alias] = $switch
        }
    }

    $topHelp = Invoke-RustfmtText -Arguments @('--help')
    foreach ($line in $topHelp) {
        if ($line -match '^\s+(-\w(?:,\s+--[A-Za-z0-9\-]+)?|--[A-Za-z0-9\-]+)\b') {
            $tokenGroup = $matches[1]
            foreach ($token in ($tokenGroup -split ',\s*')) {
                if ($aliasLookup.ContainsKey($token)) {
                    $spec = $aliasLookup[$token]
                    if ($line -match '\s{2,}(\S.*)$') {
                        $spec.Description = $matches[1].Trim()
                    }
                }
            }
        }
    }

    # `rustfmt --help=config` right-aligns each key against its type and default:
    #     newline_style [Auto|Windows|Unix|Native] Default: Auto
    #                   Unix or Windows line endings
    # Anchoring on the type and the Default column is what separates a real key
    # from the first word of a wrapped description line.
    $configKeys = New-Object System.Collections.Generic.List[object]
    foreach ($line in (Invoke-RustfmtText -Arguments @('--help=config'))) {
        if ($line -notmatch '^\s*(?<key>[a-z_][a-z0-9_]*)\s+(?<type>\[[^\]]+\]|<[^>]+>)\s+Default:\s*(?<default>.*)$') {
            continue
        }

        # Capture before any further -match call replaces $matches.
        $keyName = $matches.key
        $type = $matches.type
        $keyDefault = $matches.default.Trim()

        $values = @()
        if ($type -match '^\[(?<alts>.+)\]$') {
            # Only single-token values are insertable; rustfmt annotates some
            # enum members, for example "2027 (unstable)".
            $values = @($matches.alts -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z0-9_.-]+$' })
        } elseif ($type -match '(?i)boolean') {
            $values = @('true', 'false')
        }

        [void]$configKeys.Add([pscustomobject]@{
                Name    = $keyName
                Type    = $type
                Values  = $values
                Default = $keyDefault
            })
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
        ConfigKeys       = @($configKeys.ToArray() | Sort-Object -Property Name -Unique)
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
        'InputFile' { return Get-RustfmtPathCompletions -CurrentToken $raw -RustSourceOnly $true }
        'ConfigOverride' {
            # `--config` takes key1=val1,key2=val2...: only the segment after the
            # last comma is being completed, and every completion has to carry the
            # segments the user already typed.
            $commaIndex = $clean.LastIndexOf(',')
            $carried = if ($commaIndex -ge 0) { $clean.Substring(0, $commaIndex + 1) } else { '' }
            $segment = if ($commaIndex -ge 0) { $clean.Substring($commaIndex + 1) } else { $clean }

            if ($segment -match '^(?<key>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)$') {
                foreach ($suggestion in (Get-RustfmtConfigValueSuggestions -Key $matches.key -ValuePrefix $matches.value -Carried $carried)) {
                    [void]$results.Add($suggestion)
                }
            } else {
                foreach ($entry in $catalog.ConfigKeys) {
                    if ($entry.Name.StartsWith($segment, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $toolTip = "$($entry.Name) $($entry.Type) Default: $($entry.Default)"
                        [void]$results.Add((New-RustfmtCompletionResult -CompletionText ($carried + $entry.Name + '=') -ToolTip $toolTip -ListItemText ($entry.Name + '=')))
                    }
                }
            }
        }
    }

    @($results.ToArray())
}

function Get-RustfmtConfigValueSuggestions {
    param(
        [string]$Key,
        [string]$ValuePrefix,
        [string]$Carried = ''
    )

    $catalog = Get-RustfmtCatalog
    $entry = $null
    foreach ($candidate in $catalog.ConfigKeys) {
        if ([string]::Equals($candidate.Name, $Key, [System.StringComparison]::OrdinalIgnoreCase)) {
            $entry = $candidate
            break
        }
    }

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    $values = if ($null -eq $entry) { @() } else { @($entry.Values) }

    foreach ($value in $values) {
        if ($value.StartsWith($ValuePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-RustfmtCompletionResult -CompletionText ($Carried + $Key + '=' + $value) -ToolTip "rustfmt config value for $Key" -ListItemText $value))
        }
    }

    # A free-form key (an integer or a string) only gets a placeholder, and only
    # while the value is still empty, so a partly typed value is never replaced.
    if ($results.Count -eq 0 -and [string]::IsNullOrEmpty($ValuePrefix) -and -not [string]::IsNullOrWhiteSpace($Key)) {
        $toolTip = if ($null -eq $entry) { "rustfmt config value for $Key" } else { "$($entry.Name) $($entry.Type) Default: $($entry.Default)" }
        [void]$results.Add((New-RustfmtCompletionResult -CompletionText ($Carried + $Key + '=<value>') -ToolTip $toolTip -ListItemText '<value>'))
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

        if ($clean -match '^(--?[A-Za-z0-9][A-Za-z0-9\-]*)=(.*)$') {
            $optionName = $matches[1]
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

        if ($catalog.AliasLookup.ContainsKey($clean)) {
            $spec = $catalog.AliasLookup[$clean]
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

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($switch in $catalog.Switches) {
        foreach ($alias in $switch.Aliases) {
            # Ordinal: -V must not be rewritten to -v on the way out.
            if ($alias.StartsWith($clean, [System.StringComparison]::Ordinal) -and $seen.Add($alias)) {
                [void]$results.Add((New-RustfmtCompletionResult -CompletionText $alias -ResultType 'ParameterName' -ToolTip $switch.Description -ListItemText $alias))
            }
        }
    }

    @($results.ToArray() | Sort-Object -Property CompletionText -CaseSensitive)
}

Register-ArgumentCompleter -Native -CommandName @('rustfmt', 'rustfmt.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    # $cursorPosition is an offset into the whole input line, while
    # $commandAst.Extent.Text is command-relative.
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    $tokenState = Get-RustfmtTokenState -Line $commandAst.Extent.Text -CursorPosition $relativeCursor
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
    if ($cleanCurrent -match '^(--?[A-Za-z0-9][A-Za-z0-9\-]*)=(.*)$') {
        $catalog = Get-RustfmtCatalog
        $optionName = $matches[1]
        $attachedValue = $matches[2]
        if ($catalog.AliasLookup.ContainsKey($optionName)) {
            $spec = $catalog.AliasLookup[$optionName]
            if (-not [string]::IsNullOrEmpty($spec.AttachedValueKind)) {
                # Keep the "--opt=" prefix on every suggestion so accepting one
                # does not delete the option name.
                return @(
                    Get-RustfmtValueSuggestions -ValueKind $spec.AttachedValueKind -CurrentToken $attachedValue |
                        ForEach-Object {
                            New-RustfmtCompletionResult -CompletionText ($optionName + '=' + $_.CompletionText) -ResultType $_.ResultType -ToolTip $_.ToolTip -ListItemText $_.ListItemText
                        }
                )
            }
        }

        return @()
    }

    if ($cleanCurrent.StartsWith('-')) {
        return Get-RustfmtSwitchSuggestions -CurrentToken $currentToken
    }

    if ([string]::IsNullOrEmpty($cleanCurrent)) {
        # The operand slot is reachable from a bare TAB: offer the switches and
        # the files rustfmt actually formats.
        return @(
            @(Get-RustfmtSwitchSuggestions -CurrentToken $currentToken) +
            @(Get-RustfmtValueSuggestions -ValueKind 'InputFile' -CurrentToken $currentToken)
        )
    }

    Get-RustfmtValueSuggestions -ValueKind 'InputFile' -CurrentToken $currentToken
}
