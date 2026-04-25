Set-StrictMode -Version 2.0

function Get-RustupCache {
    if (Test-Path -LiteralPath variable:script:RustupCompleterCache) {
        return $script:RustupCompleterCache
    }

    $cache = @{
        CommandPath    = $null
        HelpByKey      = @{}
        Toolchains     = $null
        Targets        = @{}
        Components     = @{}
        HostTriples    = $null
        Profiles       = @('minimal', 'default', 'complete')
        AutoSelfUpdate = @('enable', 'disable', 'check-only')
        AutoInstall    = @('enable', 'disable')
        Shells         = @('bash', 'elvish', 'fish', 'powershell', 'zsh')
        CompletionApps = @('rustup', 'cargo')
    }

    Set-Variable -Name RustupCompleterCache -Scope Script -Value $cache
    $cache
}

function Resolve-RustupCommandPath {
    $cache = Get-RustupCache
    if ($cache.CommandPath) {
        return $cache.CommandPath
    }

    $command = Get-Command -Name 'rustup.exe', 'rustup' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $cache.CommandPath = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $cache.CommandPath
}

function Invoke-RustupText {
    param([string[]]$Arguments)

    $commandPath = Resolve-RustupCommandPath
    if (-not $commandPath) {
        return @()
    }

    try {
        @(& $commandPath @Arguments 2>$null)
    } catch {
        @()
    }
}

function Get-RustupHelpDefinition {
    param([string[]]$CommandPath)

    $normalizedPath = @($CommandPath)
    $cache = Get-RustupCache
    $key = if ($normalizedPath.Count -gt 0) { $normalizedPath -join ' ' } else { '<root>' }
    if ($cache.HelpByKey.ContainsKey($key)) {
        return $cache.HelpByKey[$key]
    }

    $arguments = @()
    if ($normalizedPath.Count -gt 0) {
        $arguments += $normalizedPath
    }
    $arguments += '--help'

    $lines = @(Invoke-RustupText -Arguments $arguments)
    $definition = @{
        Key          = $key
        CommandPath  = $normalizedPath
        Commands     = @()
        CommandMap   = @{}
        Options      = @()
        OptionMap    = @{}
    }

    $section = ''
    foreach ($line in $lines) {
        if ($line -match '^Commands:$') {
            $section = 'Commands'
            continue
        }

        if ($line -match '^Options:$') {
            $section = 'Options'
            continue
        }

        if ($line -match '^[A-Z][A-Za-z ]+:$') {
            $section = ''
            continue
        }

        switch ($section) {
            'Commands' {
                if ($line -match '^\s{2,}([A-Za-z][\w-]*)\s{2,}(.*)$') {
                    $name = $matches[1]
                    $description = $matches[2].Trim()
                    $entry = [pscustomobject]@{
                        Name        = $name
                        Description = $description
                    }
                    $definition.Commands += $entry
                    $definition.CommandMap[$name] = $entry
                }
            }
            'Options' {
                if ($line -match '^\s{2,}(.+?)\s{2,}(.*)$') {
                    $spec = $matches[1].Trim()
                    $description = $matches[2].Trim()
                    $names = @([regex]::Matches($spec, '(?:^|,\s*)((?:--?|\+)[A-Za-z0-9][A-Za-z0-9_-]*|/\?)') | ForEach-Object {
                        $_.Groups[1].Value.Trim()
                    })
                    if ($names.Count -eq 0) {
                        continue
                    }

                    $takesValue = $spec -match '<[^>]+>'
                    $valuePlaceholder = $null
                    if ($takesValue -and $spec -match '<([^>]+)>') {
                        $valuePlaceholder = $matches[1]
                    }

                    $entry = [pscustomobject]@{
                        Names            = $names
                        PrimaryName      = $names[-1]
                        Description      = $description
                        TakesValue       = $takesValue
                        ValuePlaceholder = $valuePlaceholder
                    }
                    $definition.Options += $entry
                    foreach ($name in $names) {
                        $definition.OptionMap[$name] = $entry
                    }
                }
            }
        }
    }

    $cache.HelpByKey[$key] = $definition
    $definition
}

function New-RustupCompletionResult {
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

function ConvertTo-RustupQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + $Value.Replace('`', '``').Replace('"', '`"') + '"'
    }

    $Value
}

function Remove-RustupOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function Get-RustupCurrentToken {
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

function Get-RustupTokensBeforeCursor {
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

function Get-RustupKnownToolchains {
    $cache = Get-RustupCache
    if ($cache.Toolchains) {
        return $cache.Toolchains
    }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Invoke-RustupText -Arguments @('toolchain', 'list'))) {
        if ($line -match '^([^\s]+)') {
            $value = $matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($value) -and -not $names.Contains($value)) {
                $names.Add($value)
            }
        }
    }

    foreach ($fallback in @('stable', 'beta', 'nightly')) {
        if (-not $names.Contains($fallback)) {
            $names.Add($fallback)
        }
    }

    $cache.Toolchains = @($names.ToArray())
    $cache.Toolchains
}

function Get-RustupTargetValues {
    param([bool]$InstalledOnly)

    $cache = Get-RustupCache
    $key = if ($InstalledOnly) { 'installed' } else { 'all' }
    if ($cache.Targets.ContainsKey($key)) {
        return $cache.Targets[$key]
    }

    $args = @('target', 'list')
    if ($InstalledOnly) {
        $args += '--installed'
    }

    $values = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Invoke-RustupText -Arguments $args)) {
        if ($line -match '^([^\s]+)') {
            $value = $matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($value) -and -not $values.Contains($value)) {
                $values.Add($value)
            }
        }
    }

    if (-not $InstalledOnly -and -not $values.Contains('all')) {
        $values.Add('all')
    }

    $cache.Targets[$key] = @($values.ToArray())
    $cache.Targets[$key]
}

function Get-RustupComponentValues {
    param([bool]$InstalledOnly)

    $cache = Get-RustupCache
    $key = if ($InstalledOnly) { 'installed' } else { 'all' }
    if ($cache.Components.ContainsKey($key)) {
        return $cache.Components[$key]
    }

    $args = @('component', 'list')
    if ($InstalledOnly) {
        $args += '--installed'
    }

    $values = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Invoke-RustupText -Arguments $args)) {
        if ($line -match '^([^\s]+)') {
            $value = $matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($value) -and -not $values.Contains($value)) {
                $values.Add($value)
            }
        }
    }

    $cache.Components[$key] = @($values.ToArray())
    $cache.Components[$key]
}

function Get-RustupHostTriples {
    $cache = Get-RustupCache
    if ($cache.HostTriples) {
        return $cache.HostTriples
    }

    $values = New-Object System.Collections.Generic.List[string]
    foreach ($toolchain in (Get-RustupKnownToolchains)) {
        if ($toolchain -match '-([A-Za-z0-9_\.-]+)$') {
            $host = $matches[1]
            if (-not $values.Contains($host)) {
                $values.Add($host)
            }
        }
    }

    foreach ($target in (Get-RustupTargetValues -InstalledOnly $true)) {
        if (-not $values.Contains($target)) {
            $values.Add($target)
        }
    }

    $cache.HostTriples = @($values.ToArray())
    $cache.HostTriples
}

function Get-RustupPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-RustupOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }
        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $inputIsRooted = -not [string]::IsNullOrWhiteSpace($cleanInput) -and [System.IO.Path]::IsPathRooted($cleanInput)
    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like "$leaf*" }

    foreach ($item in ($items | Sort-Object -Property @{ Expression = 'PSIsContainer'; Descending = $true }, Name)) {
        if ($inputIsRooted) {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $pathText = $item.Name
        } else {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $quoted = ConvertTo-RustupQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        $type = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }
        New-RustupCompletionResult -CompletionText $quoted -ListItemText $pathText -ResultType $type -ToolTip $item.FullName
    }
}

function Get-RustupValueCatalog {
    param(
        [string[]]$ContextPath,
        [string]$OptionName,
        [bool]$IsPositional,
        [int]$PositionalIndex = -1
    )

    $key = if ($ContextPath.Count -gt 0) { $ContextPath -join ' ' } else { '<root>' }
    switch ($key) {
        '<root>' {
        }
        'install' {
            if ($IsPositional) { return @(Get-RustupKnownToolchains) }
            switch ($OptionName) {
                '--profile' { return @((Get-RustupCache).Profiles) }
                '--target' { return @(Get-RustupTargetValues -InstalledOnly $false) }
                '--component' { return @(Get-RustupComponentValues -InstalledOnly $false) }
            }
        }
        'toolchain install' {
            if ($IsPositional) { return @(Get-RustupKnownToolchains) }
            switch ($OptionName) {
                '--profile' { return @((Get-RustupCache).Profiles) }
                '--target' { return @(Get-RustupTargetValues -InstalledOnly $false) }
                '--component' { return @(Get-RustupComponentValues -InstalledOnly $false) }
            }
        }
        'toolchain uninstall' { if ($IsPositional) { return @(Get-RustupKnownToolchains) } }
        'default' { if ($IsPositional) { return @('none') + @(Get-RustupKnownToolchains) } }
        'update' { if ($IsPositional) { return @(Get-RustupKnownToolchains) } }
        'target add' {
            if ($IsPositional) { return @(Get-RustupTargetValues -InstalledOnly $false) }
            if ($OptionName -eq '--toolchain') { return @(Get-RustupKnownToolchains) }
        }
        'target remove' {
            if ($IsPositional) { return @(Get-RustupTargetValues -InstalledOnly $true) }
            if ($OptionName -eq '--toolchain') { return @(Get-RustupKnownToolchains) }
        }
        'target list' { if ($OptionName -eq '--toolchain') { return @(Get-RustupKnownToolchains) } }
        'component add' {
            if ($IsPositional) { return @(Get-RustupComponentValues -InstalledOnly $false) }
            switch ($OptionName) {
                '--toolchain' { return @(Get-RustupKnownToolchains) }
                '--target' { return @(Get-RustupTargetValues -InstalledOnly $false) }
            }
        }
        'component remove' {
            if ($IsPositional) { return @(Get-RustupComponentValues -InstalledOnly $true) }
            switch ($OptionName) {
                '--toolchain' { return @(Get-RustupKnownToolchains) }
                '--target' { return @(Get-RustupTargetValues -InstalledOnly $true) }
            }
        }
        'component list' { if ($OptionName -eq '--toolchain') { return @(Get-RustupKnownToolchains) } }
        'toolchain link' {
            if (-not $OptionName -and $IsPositional) { return @('<toolchain-name>') }
        }
        'override set' { if ($IsPositional) { return @(Get-RustupKnownToolchains) } }
        'run' {
            if ($IsPositional -and $PositionalIndex -eq 0) {
                return @(Get-RustupKnownToolchains)
            }
        }
        'doc' {
            if ($OptionName -eq '--toolchain') { return @(Get-RustupKnownToolchains) }
        }
        'which' {
            if ($OptionName -eq '--toolchain') { return @(Get-RustupKnownToolchains) }
            if ($IsPositional) { return @('cargo', 'rustc', 'rustdoc', 'rustfmt', 'clippy-driver') }
        }
        'completions' {
            if ($IsPositional -and $PositionalIndex -eq 0) {
                return @((Get-RustupCache).Shells)
            }
            if ($IsPositional -and $PositionalIndex -eq 1) {
                return @((Get-RustupCache).CompletionApps)
            }
        }
        'set profile' { if ($IsPositional) { return @((Get-RustupCache).Profiles) } }
        'set auto-self-update' { if ($IsPositional) { return @((Get-RustupCache).AutoSelfUpdate) } }
        'set auto-install' { if ($IsPositional) { return @((Get-RustupCache).AutoInstall) } }
        'set default-host' { if ($IsPositional) { return @(Get-RustupHostTriples) } }
    }

    @()
}

function Get-RustupPlaceholderText {
    param(
        [string[]]$ContextPath,
        [string]$OptionName,
        [bool]$IsPositional,
        [int]$PositionalIndex
    )

    $key = if ($ContextPath.Count -gt 0) { $ContextPath -join ' ' } else { '<root>' }
    switch ($key) {
        '<root>' { }
        'toolchain link' {
            if ($IsPositional -and $PositionalIndex -eq 0) { return '<toolchain-name>' }
            if ($IsPositional -and $PositionalIndex -eq 1) { return '<path>' }
        }
        'override set' { if ($OptionName -eq '--path') { return '<path>' } }
        'override unset' { if ($OptionName -eq '--path') { return '<path>' } }
        'run' {
            if ($IsPositional -and $PositionalIndex -eq 1) { return '<command>' }
            if ($IsPositional -and $PositionalIndex -ge 2) { return '<argument>' }
        }
        'doc' { if ($IsPositional) { return '<topic>' } }
    }

    if ($OptionName -eq '--path') {
        return '<path>'
    }

    $null
}

function Get-RustupCommandState {
    param([string[]]$TokensBeforeCurrent)

    $path = New-Object System.Collections.Generic.List[string]
    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingOption = $null
    $pendingOptionPath = @()
    $optionValues = @{}

    foreach ($rawToken in $TokensBeforeCurrent) {
        $token = Remove-RustupOuterQuotes -Value $rawToken
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        if ($pendingOption) {
            $optionValues[$pendingOption] = $token
            $pendingOption = $null
            $pendingOptionPath = @()
            continue
        }

        $definition = Get-RustupHelpDefinition -CommandPath @($path.ToArray())
        if ($token.StartsWith('-') -or $token -eq '/?') {
            if ($definition.OptionMap.ContainsKey($token)) {
                $entry = $definition.OptionMap[$token]
                if ($entry.TakesValue) {
                    $pendingOption = $entry.PrimaryName
                    $pendingOptionPath = @($path.ToArray())
                }
            }
            continue
        }

        if ($token.StartsWith('+') -and $path.Count -eq 0 -and $positionals.Count -eq 0) {
            $positionals.Add($token)
            continue
        }

        if ($definition.CommandMap.ContainsKey($token) -and $positionals.Count -eq 0) {
            $path.Add($token)
            continue
        }

        $positionals.Add($token)
    }

    [pscustomobject]@{
        ContextPath        = @($path.ToArray())
        Positionals        = @($positionals.ToArray())
        PendingOption      = $pendingOption
        PendingOptionPath  = $pendingOptionPath
        OptionValues       = $optionValues
    }
}

function Get-RustupNamedCompletions {
    param(
        [string[]]$Values,
        [string]$CurrentWord,
        [string]$ToolTip,
        [string]$ResultType
    )

    $cleanCurrent = Remove-RustupOuterQuotes -Value $CurrentWord
    foreach ($value in $Values) {
        if ($value.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-RustupCompletionResult -CompletionText $value -ListItemText $value -ResultType $ResultType -ToolTip $ToolTip
        }
    }
}

function Get-RustupValueCompletions {
    param(
        [string[]]$ContextPath,
        [string]$OptionName,
        [bool]$IsPositional,
        [int]$PositionalIndex,
        [string]$CurrentWord
    )

    $values = @(Get-RustupValueCatalog -ContextPath $ContextPath -OptionName $OptionName -IsPositional $IsPositional -PositionalIndex $PositionalIndex)
    if ($values.Count -gt 0) {
        return @(Get-RustupNamedCompletions -Values $values -CurrentWord $CurrentWord -ToolTip 'rustup value' -ResultType 'ParameterValue')
    }

    $placeholder = Get-RustupPlaceholderText -ContextPath $ContextPath -OptionName $OptionName -IsPositional $IsPositional -PositionalIndex $PositionalIndex
    if ($placeholder) {
        if ([string]::IsNullOrWhiteSpace($CurrentWord) -or $placeholder.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            return @(
                New-RustupCompletionResult -CompletionText $placeholder -ListItemText $placeholder -ResultType 'ParameterValue' -ToolTip ('rustup placeholder for ' + $placeholder)
            )
        }
    }

    @()
}

function Complete-Rustup {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-RustupCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $tokensBeforeCurrent = @(Get-RustupTokensBeforeCursor -CommandAst $commandAst -CursorPosition $cursorPosition)
    if (($tokensBeforeCurrent.Count -eq 0) -and ($currentWord -match '^(?i)rustup(?:\.exe)?$')) {
        $currentWord = ''
    } elseif ([string]::IsNullOrEmpty($wordToComplete) -and -not [string]::IsNullOrEmpty($currentWord)) {
        $tokensBeforeCurrent = @($tokensBeforeCurrent + $currentWord)
        $currentWord = ''
    }

    $state = Get-RustupCommandState -TokensBeforeCurrent $tokensBeforeCurrent
    $contextPath = @(
        if ($state.PendingOption) { $state.PendingOptionPath } else { $state.ContextPath }
    )
    $definition = Get-RustupHelpDefinition -CommandPath $contextPath

    if ($state.PendingOption) {
        if ($state.PendingOption -eq '--path') {
            return @(Get-RustupPathCompletions -InputPath $currentWord)
        }

        return @(Get-RustupValueCompletions -ContextPath $contextPath -OptionName $state.PendingOption -IsPositional $false -PositionalIndex -1 -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and ($currentWord.StartsWith('-') -or $currentWord -eq '/')) {
        $cleanCurrent = Remove-RustupOuterQuotes -Value $currentWord
        $optionResults = New-Object System.Collections.Generic.List[object]
        foreach ($option in $definition.Options) {
            foreach ($name in $option.Names) {
                if ($name.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $optionResults.Add((New-RustupCompletionResult -CompletionText $name -ListItemText $name -ResultType 'ParameterName' -ToolTip $option.Description))
                }
            }
        }
        return @($optionResults.ToArray())
    }

    if (($state.ContextPath -join ' ') -eq 'toolchain link' -and $state.Positionals.Count -eq 1) {
        return @(Get-RustupPathCompletions -InputPath $currentWord)
    }

    if ([string]::IsNullOrEmpty($currentWord) -and (($state.ContextPath -join ' ') -eq 'run') -and $state.Positionals.Count -ge 2) {
        return @(
            New-RustupCompletionResult -CompletionText '<argument>' -ListItemText '<argument>' -ResultType 'ParameterValue' -ToolTip 'Additional argument for the command run through rustup.'
        )
    }

    $results = New-Object System.Collections.Generic.List[object]
    $valueResults = @(Get-RustupValueCompletions -ContextPath $state.ContextPath -OptionName $null -IsPositional $true -PositionalIndex $state.Positionals.Count -CurrentWord $currentWord)
    foreach ($item in $valueResults) {
        $results.Add($item)
    }

    if ($state.Positionals.Count -eq 0) {
        foreach ($command in $definition.Commands) {
            if ($command.Name.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                $results.Add((New-RustupCompletionResult -CompletionText $command.Name -ListItemText $command.Name -ResultType 'ParameterValue' -ToolTip $command.Description))
            }
        }
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        foreach ($option in $definition.Options) {
            foreach ($name in $option.Names) {
                $results.Add((New-RustupCompletionResult -CompletionText $name -ListItemText $name -ResultType 'ParameterName' -ToolTip $option.Description))
            }
        }
    }

    @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('rustup', 'rustup.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Rustup -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
