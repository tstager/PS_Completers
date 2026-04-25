Set-StrictMode -Version 2.0

if ($true) {
function Get-CargoBinstallCompleterCache {
    if (Test-Path -LiteralPath variable:script:CargoBinstallCompleterCache) {
        return $script:CargoBinstallCompleterCache
    }

    $cache = @{
        CommandPath    = $null
        HelpDefinition = $null
        TargetTriples  = $null
    }

    Set-Variable -Name CargoBinstallCompleterCache -Scope Script -Value $cache
    $cache
}

function Resolve-CargoBinstallCommandPath {
    $cache = Get-CargoBinstallCompleterCache
    if ($cache.CommandPath) {
        return $cache.CommandPath
    }

    $command = Get-Command -Name 'cargo-binstall.exe', 'cargo-binstall' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $cache.CommandPath = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $cache.CommandPath
}

function Invoke-CargoBinstallText {
    param([string[]]$Arguments)

    $commandPath = Resolve-CargoBinstallCommandPath
    if (-not $commandPath) {
        return @()
    }

    try {
        @(& $commandPath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    } catch {
        @()
    }
}

function Get-CargoBinstallHelpDefinition {
    $cache = Get-CargoBinstallCompleterCache
    if ($cache.HelpDefinition) {
        return $cache.HelpDefinition
    }

    $definition = @{
        Options               = @()
        OptionMap             = @{}
        PositionalPlaceholder = '<crate[@version]>'
    }

    $lines = @(Invoke-CargoBinstallText -Arguments @('--help'))
    $currentEntry = $null

    foreach ($line in $lines) {
        if ($line -match '^\s{2,}(?<spec>(?:(?:-[A-Za-z0-9?],\s*)?--[A-Za-z0-9][A-Za-z0-9\-]*|-[A-Za-z0-9?])(?:\s+<[^>]+>)?(?:\.\.\.)?)\s*$') {
            if ($currentEntry) {
                $definition.Options += $currentEntry
                foreach ($name in $currentEntry.Names) {
                    $definition.OptionMap[$name] = $currentEntry
                }
            }

            $spec = $matches['spec'].Trim()
            $names = @([regex]::Matches($spec, '(?:^|,\s*)(--[A-Za-z0-9][A-Za-z0-9\-]*|-[A-Za-z0-9?])') | ForEach-Object {
                $_.Groups[1].Value
            })
            $takesValue = $spec -match '<(?<placeholder>[^>]+)>'
            $placeholder = if ($takesValue) { '<' + $matches['placeholder'] + '>' } else { $null }

            $currentEntry = [pscustomobject]@{
                Names            = $names
                PrimaryName      = $names[-1]
                Description      = ''
                TakesValue       = $takesValue
                ValuePlaceholder = $placeholder
            }

            continue
        }

        if ($line -match '^\s{2,}\[crate\[@version\]\]\.\.\.$') {
            $definition.PositionalPlaceholder = '<crate[@version]>'
            continue
        }

        if ($currentEntry) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                $definition.Options += $currentEntry
                foreach ($name in $currentEntry.Names) {
                    $definition.OptionMap[$name] = $currentEntry
                }

                $currentEntry = $null
                continue
            }

            if ($line -match '^\S') {
                $definition.Options += $currentEntry
                foreach ($name in $currentEntry.Names) {
                    $definition.OptionMap[$name] = $currentEntry
                }

                $currentEntry = $null
            }
            elseif ((-not $currentEntry.Description) -and $line -match '^\s{2,}(?<description>\S.*)$') {
                $currentEntry = [pscustomobject]@{
                    Names            = $currentEntry.Names
                    PrimaryName      = $currentEntry.PrimaryName
                    Description      = $matches['description'].Trim()
                    TakesValue       = $currentEntry.TakesValue
                    ValuePlaceholder = $currentEntry.ValuePlaceholder
                }
            }
        }
    }

    if ($currentEntry) {
        $definition.Options += $currentEntry
        foreach ($name in $currentEntry.Names) {
            $definition.OptionMap[$name] = $currentEntry
        }
    }

    $cache.HelpDefinition = $definition
    $definition
}

function Get-CargoBinstallTargetTriples {
    $cache = Get-CargoBinstallCompleterCache
    if ($cache.TargetTriples) {
        return $cache.TargetTriples
    }

    $rustc = Get-Command -Name 'rustc.exe', 'rustc' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $rustc) {
        $cache.TargetTriples = @()
        return $cache.TargetTriples
    }

    try {
        $cache.TargetTriples = @(& $rustc.Source '--print' 'target-list' 2>$null | Where-Object { $_ } | Sort-Object -Unique)
    } catch {
        $cache.TargetTriples = @()
    }

    $cache.TargetTriples
}

function New-CargoBinstallCompletionResult {
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

function Remove-CargoBinstallOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-CargoBinstallQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + $Value.Replace('`', '``').Replace('"', '`"') + '"'
    }

    $Value
}

function Get-CargoBinstallCurrentToken {
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

function Get-CargoBinstallTokensBeforeCursor {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens.Add($element.Extent.Text)
        }
    }

    @($tokens.ToArray())
}

function Get-CargoBinstallPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-CargoBinstallOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    [System.Management.Automation.CompletionCompleters]::CompleteFilename($cleanInput) |
        ForEach-Object {
            $completionText = ConvertTo-CargoBinstallQuotedValue -Value $_.CompletionText -AlwaysQuote $alwaysQuote
            New-CargoBinstallCompletionResult -CompletionText $completionText -ListItemText $_.ListItemText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }
}

function Get-CargoBinstallPlaceholderCompletion {
    param(
        [string]$Placeholder,
        [string]$CurrentWord,
        [string]$ToolTip
    )

    $completionText = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { $Placeholder } else { $CurrentWord }
    New-CargoBinstallCompletionResult -CompletionText $completionText -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
}

function Get-CargoBinstallNamedValueCompletions {
    param(
        [string[]]$Values,
        [string]$CurrentWord,
        [string]$ToolTip
    )

    $cleanCurrent = Remove-CargoBinstallOuterQuotes -Value $CurrentWord
    foreach ($value in $Values) {
        if ($value.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-CargoBinstallCompletionResult -CompletionText $value -ListItemText $value -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }
}

function Get-CargoBinstallDelimitedValueCompletions {
    param(
        [string[]]$Values,
        [string]$CurrentWord,
        [string]$ToolTip
    )

    $cleanCurrent = Remove-CargoBinstallOuterQuotes -Value $CurrentWord
    $segments = @(if ([string]::IsNullOrWhiteSpace($cleanCurrent)) { '' } else { $cleanCurrent.Split(',') })
    $selected = if ($segments.Count -gt 1) { @($segments[0..($segments.Count - 2)] | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { @() }
    $fragment = $segments[-1].Trim()
    $prefix = if ($segments.Count -gt 1) { (($segments[0..($segments.Count - 2)] | ForEach-Object { $_.Trim() }) -join ',') + ',' } else { '' }

    foreach ($value in $Values) {
        if (($selected -contains $value) -or (-not $value.StartsWith($fragment, [System.StringComparison]::OrdinalIgnoreCase))) {
            continue
        }

        $completionText = $prefix + $value
        New-CargoBinstallCompletionResult -CompletionText $completionText -ListItemText $completionText -ResultType 'ParameterValue' -ToolTip $ToolTip
    }
}

function Get-CargoBinstallOptionValueCompletions {
    param(
        [string]$OptionName,
        [string]$CurrentWord
    )

    switch ($OptionName) {
        '--manifest-path' { return @(Get-CargoBinstallPathCompletions -InputPath $CurrentWord) }
        '--bin-dir' { return @(Get-CargoBinstallPathCompletions -InputPath $CurrentWord) }
        '--install-path' { return @(Get-CargoBinstallPathCompletions -InputPath $CurrentWord) }
        '--root' { return @(Get-CargoBinstallPathCompletions -InputPath $CurrentWord) }
        '--root-certificates' { return @(Get-CargoBinstallPathCompletions -InputPath $CurrentWord) }
        '--settings' { return @(Get-CargoBinstallPathCompletions -InputPath $CurrentWord) }
        '--pkg-fmt' { return @(Get-CargoBinstallNamedValueCompletions -Values @('tar', 'tbz2', 'tgz', 'txz', 'tzstd', 'zip', 'bin') -CurrentWord $CurrentWord -ToolTip 'cargo-binstall package format') }
        '--strategies' { return @(Get-CargoBinstallDelimitedValueCompletions -Values @('crate-meta-data', 'quick-install', 'compile') -CurrentWord $CurrentWord -ToolTip 'cargo-binstall strategy list') }
        '--disable-strategies' { return @(Get-CargoBinstallDelimitedValueCompletions -Values @('crate-meta-data', 'quick-install', 'compile') -CurrentWord $CurrentWord -ToolTip 'cargo-binstall strategy list') }
        '--min-tls-version' { return @(Get-CargoBinstallNamedValueCompletions -Values @('1.2', '1.3') -CurrentWord $CurrentWord -ToolTip 'Minimum TLS version') }
        '--log-level' { return @(Get-CargoBinstallNamedValueCompletions -Values @('trace', 'debug', 'info', 'warn', 'error', 'off') -CurrentWord $CurrentWord -ToolTip 'Utility log level') }
        '--targets' {
            $targetTriples = @(Get-CargoBinstallTargetTriples)
            if ($targetTriples.Count -gt 0) {
                return @(Get-CargoBinstallDelimitedValueCompletions -Values $targetTriples -CurrentWord $CurrentWord -ToolTip 'Rust target triples')
            }
        }
    }

    $definition = Get-CargoBinstallHelpDefinition
    if ($definition.OptionMap.ContainsKey($OptionName)) {
        $entry = $definition.OptionMap[$OptionName]
        if ($entry.ValuePlaceholder) {
            return @(
                Get-CargoBinstallPlaceholderCompletion -Placeholder $entry.ValuePlaceholder -CurrentWord $CurrentWord -ToolTip ("cargo-binstall value for $OptionName")
            )
        }
    }

    @()
}

function Get-CargoBinstallOptionCompletions {
    param([string]$CurrentWord)

    $definition = Get-CargoBinstallHelpDefinition
    $cleanCurrent = Remove-CargoBinstallOuterQuotes -Value $CurrentWord

    foreach ($entry in $definition.Options) {
        foreach ($name in $entry.Names) {
            if ($name.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
                New-CargoBinstallCompletionResult -CompletionText $name -ListItemText $name -ResultType 'ParameterName' -ToolTip $entry.Description
            }
        }
    }
}

function Get-CargoBinstallPositionalCompletions {
    param([string]$CurrentWord)

    $definition = Get-CargoBinstallHelpDefinition
    @(
        Get-CargoBinstallPlaceholderCompletion -Placeholder $definition.PositionalPlaceholder -CurrentWord $CurrentWord -ToolTip 'crate name or crate@version'
    )
}

function Get-CargoBinstallState {
    param([string[]]$TokensBeforeCurrent)

    $definition = Get-CargoBinstallHelpDefinition
    $pendingOption = $null
    $positionals = New-Object System.Collections.Generic.List[string]
    $afterDoubleDash = $false

    foreach ($rawToken in $TokensBeforeCurrent) {
        $token = Remove-CargoBinstallOuterQuotes -Value $rawToken
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        if ($pendingOption) {
            $pendingOption = $null
            continue
        }

        if ($afterDoubleDash) {
            $positionals.Add($token)
            continue
        }

        if ($token -eq '--') {
            $afterDoubleDash = $true
            continue
        }

        if ($definition.OptionMap.ContainsKey($token)) {
            $entry = $definition.OptionMap[$token]
            if ($entry.TakesValue) {
                $pendingOption = $entry.PrimaryName
            }
            continue
        }

        if ($token.StartsWith('-')) {
            continue
        }

        $positionals.Add($token)
    }

    [pscustomobject]@{
        PendingOption  = $pendingOption
        Positionals    = @($positionals.ToArray())
        AfterDoubleDash = $afterDoubleDash
    }
}

function Complete-CargoBinstall {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-CargoBinstallCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $tokensBeforeCurrent = @(Get-CargoBinstallTokensBeforeCursor -CommandAst $commandAst -CursorPosition $cursorPosition)
    if (($tokensBeforeCurrent.Count -eq 0) -and ($currentWord -match '^(?i)cargo-binstall(?:\.exe)?$')) {
        $currentWord = ''
    }

    $state = Get-CargoBinstallState -TokensBeforeCurrent $tokensBeforeCurrent
    if ($state.PendingOption) {
        return @(Get-CargoBinstallOptionValueCompletions -OptionName $state.PendingOption -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-CargoBinstallOptionCompletions -CurrentWord $currentWord)
    }

    $results = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrEmpty($currentWord)) {
        foreach ($item in (Get-CargoBinstallOptionCompletions -CurrentWord '')) {
            $results.Add($item)
        }
    }

    foreach ($item in (Get-CargoBinstallPositionalCompletions -CurrentWord $currentWord)) {
        $results.Add($item)
    }

    @($results.ToArray())
}

}

Register-ArgumentCompleter -Native -CommandName @('cargo-binstall', 'cargo-binstall.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-CargoBinstall -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
