# tar tab completion for PowerShell
# Provides mode-aware completion for Windows bsdtar.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name TarCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:TarCompletionCatalog = @{
        Initialized       = $false
        CommandName       = $null
        AllModes          = @('c', 'r', 't', 'u', 'x')
        ModeEntries       = @()
        ModeByAlias       = @{}
        OptionEntries     = @()
        OptionByAlias     = @{}
        ShortOptionByChar = @{}
        ShortValueByChar  = @{}
        FormatValues      = @('ustar', 'pax', 'cpio', 'shar')
        BlockSizeHints    = @('1', '10', '20', '64', '128')
        MtimeHints        = @()
        DefaultPatterns   = @('*', '*/*', '*.txt', '*.log')
    }
}

function Resolve-TarCommandName {
    if ($script:TarCompletionCatalog.CommandName) {
        return $script:TarCompletionCatalog.CommandName
    }

    $command = Get-Command -Name tar.exe, tar -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $script:TarCompletionCatalog.CommandName = $command.Name
    }

    $script:TarCompletionCatalog.CommandName
}

function New-TarCompletionResult {
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

function Remove-TarOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return $Value
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-TarQuotedValue {
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

function Test-TarStartsWith {
    param(
        [string]$Value,
        [string]$Prefix
    )

    if ([string]::IsNullOrEmpty($Prefix)) {
        return $true
    }

    $Value.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-TarValueKind {
    param([object]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties['ValueKind']
    if ($property) {
        return [string]$property.Value
    }

    $null
}

function Initialize-TarCompletionCatalog {
    if ($script:TarCompletionCatalog.Initialized) {
        return
    }

    $modeSpecs = @(
        @{ Canonical = 'c'; Aliases = @('-c', '--create'); Description = 'Create a new archive.' }
        @{ Canonical = 'r'; Aliases = @('-r', '--append'); Description = 'Append files to an existing archive.' }
        @{ Canonical = 't'; Aliases = @('-t', '--list'); Description = 'List archive contents.' }
        @{ Canonical = 'u'; Aliases = @('-u', '--update'); Description = 'Update archive entries that are newer on disk.' }
        @{ Canonical = 'x'; Aliases = @('-x', '--extract'); Description = 'Extract files from an archive.' }
    )

    $optionSpecs = @(
        @{
            Canonical   = '-b'
            Aliases     = @('-b', '--block-size')
            ShortName   = 'b'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Use the specified number of 512-byte records per I/O block.'
            ValueKind   = 'BlockSize'
        }
        @{
            Canonical   = '-f'
            Aliases     = @('-f', '--file')
            ShortName   = 'f'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Read the archive from or write the archive to the specified file.'
            ValueKind   = 'ArchivePath'
        }
        @{
            Canonical   = '-v'
            Aliases     = @('-v')
            ShortName   = 'v'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Operate verbosely.'
        }
        @{
            Canonical   = '-w'
            Aliases     = @('-w')
            ShortName   = 'w'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Interactively confirm each action.'
        }
        @{
            Canonical   = '-C'
            Aliases     = @('-C', '--cd', '--directory')
            ShortName   = 'C'
            Modes       = @('c', 'r', 'u', 'x')
            Description = 'Change to a directory before processing later files or before extracting.'
            ValueKind   = 'DirectoryPath'
        }
        @{
            Canonical   = '-a'
            Aliases     = @('-a', '--auto-compress')
            ShortName   = 'a'
            Modes       = @('c')
            Description = 'Choose compression from the archive file suffix.'
        }
        @{
            Canonical   = '-z'
            Aliases     = @('-z', '--gzip')
            ShortName   = 'z'
            Modes       = @('c')
            Description = 'Compress the archive with gzip.'
        }
        @{
            Canonical   = '-j'
            Aliases     = @('-j', '--bzip', '--bzip2', '--bunzip2')
            ShortName   = 'j'
            Modes       = @('c')
            Description = 'Compress the archive with bzip2.'
        }
        @{
            Canonical   = '-J'
            Aliases     = @('-J', '--xz')
            ShortName   = 'J'
            Modes       = @('c')
            Description = 'Compress the archive with xz.'
        }
        @{
            Canonical   = '--lzma'
            Aliases     = @('--lzma')
            Modes       = @('c')
            Description = 'Compress the archive with lzma.'
        }
        @{
            Canonical   = '--format'
            Aliases     = @('--format')
            Modes       = @('c', 'r', 'u')
            Description = 'Select the archive format.'
            ValueKind   = 'Format'
        }
        @{
            Canonical   = '--exclude'
            Aliases     = @('--exclude')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Skip files or archive entries that match a pattern.'
            ValueKind   = 'Pattern'
        }
        @{
            Canonical   = '--mtime'
            Aliases     = @('--mtime')
            Modes       = @('c', 'r', 'u')
            Description = 'Set modification times for added files.'
            ValueKind   = 'DateTime'
        }
        @{
            Canonical   = '--clamp-mtime'
            Aliases     = @('--clamp-mtime')
            Modes       = @('c', 'r', 'u')
            Description = 'Only apply --mtime when a file is newer than the requested time.'
        }
        @{
            Canonical   = '-k'
            Aliases     = @('-k', '--keep-old-files')
            ShortName   = 'k'
            Modes       = @('x')
            Description = 'Do not overwrite existing files when extracting.'
        }
        @{
            Canonical   = '-m'
            Aliases     = @('-m', '--modification-time')
            ShortName   = 'm'
            Modes       = @('x')
            Description = 'Do not restore modification times when extracting.'
        }
        @{
            Canonical   = '-O'
            Aliases     = @('-O')
            ShortName   = 'O'
            Modes       = @('x')
            Description = 'Write extracted entries to stdout instead of restoring them to disk.'
        }
        @{
            Canonical   = '-p'
            Aliases     = @('-p')
            ShortName   = 'p'
            Modes       = @('x')
            Description = 'Restore permissions, owner data, ACLs, and file flags when extracting.'
        }
    )

    $modeEntries = @()
    $modeByAlias = @{}
    foreach ($modeSpec in $modeSpecs) {
        foreach ($alias in $modeSpec.Aliases) {
            $modeEntries += [pscustomobject]@{
                Canonical      = $modeSpec.Canonical
                CompletionText = $alias
                Description    = $modeSpec.Description
            }
            $modeByAlias[$alias.ToLowerInvariant()] = $modeSpec.Canonical
        }
    }

    $optionEntries = @()
    $optionByAlias = @{}
    $shortOptionByChar = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::Ordinal)
    $shortValueByChar = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::Ordinal)
    foreach ($optionSpec in $optionSpecs) {
        $specObject = [pscustomobject]$optionSpec
        foreach ($alias in $specObject.Aliases) {
            $valueKind = Get-TarValueKind -InputObject $specObject
            $entry = [pscustomobject]@{
                Canonical      = $specObject.Canonical
                CompletionText = $alias
                Description    = $specObject.Description
                Modes          = @($specObject.Modes)
                ValueKind      = $valueKind
            }
            $optionEntries += $entry
            $optionByAlias[$alias.ToLowerInvariant()] = $entry
        }

        if ($specObject.PSObject.Properties.Name -contains 'ShortName') {
            $shortName = [string]$specObject.ShortName
            if (-not [string]::IsNullOrWhiteSpace($shortName)) {
                $shortOptionByChar[$shortName] = $specObject
                if ($specObject.PSObject.Properties.Name -contains 'ValueKind') {
                    $shortValueByChar[$shortName] = $specObject
                }
            }
        }
    }

    $now = Get-Date
    $mtimeHints = @(
        $now.ToString('yyyy-MM-dd')
        $now.ToString('yyyy-MM-ddTHH:mm:ss')
        $now.ToString('o')
        $now.AddDays(-1).ToString('yyyy-MM-dd')
        $now.AddDays(-7).ToString('yyyy-MM-dd')
        '2024-01-01'
        '2024-01-01T00:00:00'
    ) | Sort-Object -Unique

    $script:TarCompletionCatalog.ModeEntries = @($modeEntries)
    $script:TarCompletionCatalog.ModeByAlias = $modeByAlias
    $script:TarCompletionCatalog.OptionEntries = @($optionEntries)
    $script:TarCompletionCatalog.OptionByAlias = $optionByAlias
    $script:TarCompletionCatalog.ShortOptionByChar = $shortOptionByChar
    $script:TarCompletionCatalog.ShortValueByChar = $shortValueByChar
    $script:TarCompletionCatalog.MtimeHints = @($mtimeHints)
    $script:TarCompletionCatalog.Initialized = $true
}

function Get-TarCurrentToken {
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

function Test-TarBareBundle {
    param(
        [string]$Token,
        [string]$KnownMode
    )

    if ([string]::IsNullOrWhiteSpace($Token) -or $Token.StartsWith('-', [System.StringComparison]::Ordinal)) {
        return $false
    }

    $mode = $KnownMode
    for ($index = 0; $index -lt $Token.Length; $index++) {
        $character = [string]$Token[$index]
        if ((-not $mode) -and $index -eq 0 -and $script:TarCompletionCatalog.AllModes -ccontains $character) {
            $mode = $character
            continue
        }

        if ($script:TarCompletionCatalog.ShortValueByChar.ContainsKey($character) -or $script:TarCompletionCatalog.ShortOptionByChar.ContainsKey($character)) {
            continue
        }

        return $false
    }

    $true
}

function Get-TarParsedTokenInfo {
    param(
        [string]$Token,
        [string]$KnownMode
    )

    $result = [ordered]@{
        Mode         = $KnownMode
        PendingValue = $null
        IsPositional = $true
    }

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return [pscustomobject]$result
    }

    if ($Token.StartsWith('--', [System.StringComparison]::Ordinal)) {
        $match = [regex]::Match($Token, '^(--[^=]+)(?:=(.*))?$')
        if (-not $match.Success) {
            return [pscustomobject]$result
        }

        $name = $match.Groups[1].Value
        $lookup = $name.ToLowerInvariant()
        if ((-not $KnownMode) -and $script:TarCompletionCatalog.ModeByAlias.ContainsKey($lookup)) {
            $result.Mode = $script:TarCompletionCatalog.ModeByAlias[$lookup]
            $result.IsPositional = $false
            return [pscustomobject]$result
        }

        if ($script:TarCompletionCatalog.OptionByAlias.ContainsKey($lookup)) {
            $result.IsPositional = $false
            $option = $script:TarCompletionCatalog.OptionByAlias[$lookup]
            $valueKind = Get-TarValueKind -InputObject $option
            if (-not [string]::IsNullOrWhiteSpace($valueKind) -and -not $match.Groups[2].Success) {
                $result.PendingValue = $valueKind
            }

            return [pscustomobject]$result
        }

        return [pscustomobject]$result
    }

    if ($Token.StartsWith('-', [System.StringComparison]::Ordinal) -and -not $Token.StartsWith('--', [System.StringComparison]::Ordinal) -and $Token.Length -gt 1) {
        $result.IsPositional = $false
        $bundle = $Token.Substring(1)
        $mode = $KnownMode

        for ($index = 0; $index -lt $bundle.Length; $index++) {
            $character = [string]$bundle[$index]
            if ((-not $mode) -and $index -eq 0 -and $script:TarCompletionCatalog.AllModes -ccontains $character) {
                $mode = $character
                $result.Mode = $mode
                continue
            }

            if ($script:TarCompletionCatalog.ShortValueByChar.ContainsKey($character)) {
                if ($index -eq ($bundle.Length - 1)) {
                    $result.PendingValue = $script:TarCompletionCatalog.ShortValueByChar[$character].ValueKind
                }

                return [pscustomobject]$result
            }

            if ($script:TarCompletionCatalog.ShortOptionByChar.ContainsKey($character)) {
                continue
            }

            return [pscustomobject]$result
        }

        return [pscustomobject]$result
    }

    if (Test-TarBareBundle -Token $Token -KnownMode $KnownMode) {
        $result.IsPositional = $false
        $bundle = $Token
        $mode = $KnownMode

        for ($index = 0; $index -lt $bundle.Length; $index++) {
            $character = [string]$bundle[$index]
            if ((-not $mode) -and $index -eq 0 -and $script:TarCompletionCatalog.AllModes -ccontains $character) {
                $mode = $character
                $result.Mode = $mode
                continue
            }

            if ($script:TarCompletionCatalog.ShortValueByChar.ContainsKey($character)) {
                if ($index -eq ($bundle.Length - 1)) {
                    $result.PendingValue = $script:TarCompletionCatalog.ShortValueByChar[$character].ValueKind
                }

                return [pscustomobject]$result
            }

            if ($script:TarCompletionCatalog.ShortOptionByChar.ContainsKey($character)) {
                continue
            }

            return [pscustomobject]$result
        }

        return [pscustomobject]$result
    }

    [pscustomobject]$result
}

function Get-TarCompletionState {
    param([string[]]$Tokens)

    $state = [ordered]@{
        Mode             = $null
        PendingValue     = $null
        OptionTerminated = $false
        Positionals      = @()
    }

    $positionals = New-Object System.Collections.Generic.List[string]
    foreach ($token in $Tokens) {
        if ($state.PendingValue) {
            $state.PendingValue = $null
            continue
        }

        if ($state.OptionTerminated) {
            $positionals.Add($token)
            continue
        }

        if ($token -eq '--') {
            $state.OptionTerminated = $true
            continue
        }

        $parsed = Get-TarParsedTokenInfo -Token $token -KnownMode $state.Mode
        if ($parsed.Mode) {
            $state.Mode = $parsed.Mode
        }

        if ($parsed.PendingValue) {
            $state.PendingValue = $parsed.PendingValue
            continue
        }

        if ($parsed.IsPositional) {
            $positionals.Add($token)
        }
    }

    $state.Positionals = @($positionals)
    [pscustomobject]$state
}

function Get-TarCurrentValueContext {
    param(
        [string]$Token,
        [string]$KnownMode
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    if ($Token.StartsWith('--', [System.StringComparison]::Ordinal)) {
        $match = [regex]::Match($Token, '^(--[^=]+)=(.*)$')
        if (-not $match.Success) {
            return $null
        }

        $lookup = $match.Groups[1].Value.ToLowerInvariant()
        if (-not $script:TarCompletionCatalog.OptionByAlias.ContainsKey($lookup)) {
            return $null
        }

        $option = $script:TarCompletionCatalog.OptionByAlias[$lookup]
        $valueKind = Get-TarValueKind -InputObject $option
        if ([string]::IsNullOrWhiteSpace($valueKind)) {
            return $null
        }

        return [pscustomobject]@{
            ValueKind    = $valueKind
            Prefix       = $match.Groups[1].Value + '='
            CurrentValue = $match.Groups[2].Value
            Mode         = $KnownMode
        }
    }

    if ($Token.StartsWith('-', [System.StringComparison]::Ordinal) -and -not $Token.StartsWith('--', [System.StringComparison]::Ordinal) -and $Token.Length -gt 1) {
        $bundle = $Token.Substring(1)
        $mode = $KnownMode

        for ($index = 0; $index -lt $bundle.Length; $index++) {
            $character = [string]$bundle[$index]
            if ((-not $mode) -and $index -eq 0 -and $script:TarCompletionCatalog.AllModes -ccontains $character) {
                $mode = $character
                continue
            }

            if (-not $script:TarCompletionCatalog.ShortValueByChar.ContainsKey($character)) {
                if ($script:TarCompletionCatalog.ShortOptionByChar.ContainsKey($character)) {
                    continue
                }

                return $null
            }

            $currentValue = ''
            if ($index -lt ($bundle.Length - 1)) {
                $currentValue = $bundle.Substring($index + 1)
            }

            return [pscustomobject]@{
                ValueKind    = $script:TarCompletionCatalog.ShortValueByChar[$character].ValueKind
                Prefix       = '-' + $bundle.Substring(0, $index + 1)
                CurrentValue = $currentValue
                Mode         = $mode
            }
        }
    }

    if (Test-TarBareBundle -Token $Token -KnownMode $KnownMode) {
        $bundle = $Token
        $mode = $KnownMode

        for ($index = 0; $index -lt $bundle.Length; $index++) {
            $character = [string]$bundle[$index]
            if ((-not $mode) -and $index -eq 0 -and $script:TarCompletionCatalog.AllModes -ccontains $character) {
                $mode = $character
                continue
            }

            if (-not $script:TarCompletionCatalog.ShortValueByChar.ContainsKey($character)) {
                if ($script:TarCompletionCatalog.ShortOptionByChar.ContainsKey($character)) {
                    continue
                }

                return $null
            }

            $currentValue = ''
            if ($index -lt ($bundle.Length - 1)) {
                $currentValue = $bundle.Substring($index + 1)
            }

            return [pscustomobject]@{
                ValueKind    = $script:TarCompletionCatalog.ShortValueByChar[$character].ValueKind
                Prefix       = $bundle.Substring(0, $index + 1)
                CurrentValue = $currentValue
                Mode         = $mode
            }
        }
    }

    $null
}

function Get-TarModeCompletionResults {
    param([string]$CurrentValue)

    foreach ($entry in $script:TarCompletionCatalog.ModeEntries) {
        if (Test-TarStartsWith -Value $entry.CompletionText -Prefix $CurrentValue) {
            New-TarCompletionResult -CompletionText $entry.CompletionText -ResultType 'ParameterName' -ToolTip $entry.Description
        }
    }
}

function Get-TarOptionCompletionResults {
    param(
        [string]$Mode,
        [string]$CurrentValue
    )

    foreach ($entry in $script:TarCompletionCatalog.OptionEntries) {
        if (($entry.Modes -contains $Mode) -and (Test-TarStartsWith -Value $entry.CompletionText -Prefix $CurrentValue)) {
            New-TarCompletionResult -CompletionText $entry.CompletionText -ResultType 'ParameterName' -ToolTip $entry.Description
        }
    }
}

function Get-TarSimpleValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$ToolTipPrefix,
        [string]$Prefix
    )

    $alwaysQuote = $CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'")
    $cleanCurrent = Remove-TarOuterQuotes -Value $CurrentValue
    foreach ($value in ($Values | Sort-Object -Unique)) {
        if (Test-TarStartsWith -Value $value -Prefix $cleanCurrent) {
            $completionText = ConvertTo-TarQuotedValue -Value $value -AlwaysQuote:$alwaysQuote
            if ($Prefix) {
                $completionText = $Prefix + $completionText
            }

            $toolTip = if ([string]::IsNullOrWhiteSpace($ToolTipPrefix)) { $value } else { $ToolTipPrefix + ': ' + $value }
            New-TarCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $toolTip
        }
    }
}

function Get-TarPathCompletionResults {
    param(
        [string]$CurrentValue,
        [string]$Prefix,
        [switch]$DirectoryOnly,
        [string]$ToolTipPrefix = 'Path'
    )

    $startedQuoted = $CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'")
    $pathText = Remove-TarOuterQuotes -Value $CurrentValue
    $isRootDrive = $pathText -match '^[A-Za-z]:$'

    if ([string]::IsNullOrEmpty($pathText)) {
        $searchBase = '.'
        $leaf = ''
        $useParentInCompletion = $false
    }
    elseif ($isRootDrive) {
        $searchBase = $pathText + '\'
        $leaf = ''
        $useParentInCompletion = $true
    }
    elseif ($pathText.EndsWith('\') -or $pathText.EndsWith('/')) {
        $searchBase = $pathText
        $leaf = ''
        $useParentInCompletion = $true
    }
    else {
        $parentPath = Split-Path -Path $pathText -Parent
        $leaf = Split-Path -Path $pathText -Leaf
        if ([string]::IsNullOrEmpty($parentPath)) {
            $searchBase = '.'
            $useParentInCompletion = $false
        }
        else {
            $searchBase = $parentPath
            $useParentInCompletion = $true
        }
    }

    $items = @(Get-ChildItem -LiteralPath $searchBase -ErrorAction SilentlyContinue |
            Sort-Object -Property @{ Expression = 'PSIsContainer'; Descending = $true }, Name)

    foreach ($item in $items) {
        if ($DirectoryOnly -and -not $item.PSIsContainer) {
            continue
        }

        if (-not (Test-TarStartsWith -Value $item.Name -Prefix $leaf)) {
            continue
        }

        $candidate = if ($useParentInCompletion) {
            Join-Path -Path $searchBase -ChildPath $item.Name
        }
        else {
            $item.Name
        }

        if ($item.PSIsContainer) {
            $candidate += [System.IO.Path]::DirectorySeparatorChar
        }

        $completionText = ConvertTo-TarQuotedValue -Value $candidate -AlwaysQuote:$startedQuoted
        if ($Prefix) {
            $completionText = $Prefix + $completionText
        }

        $toolTip = $ToolTipPrefix
        if ($item.PSIsContainer) {
            $toolTip += ' directory'
        }
        else {
            $toolTip += ' file'
        }

        New-TarCompletionResult -CompletionText $completionText -ResultType 'ProviderItem' -ToolTip $toolTip
    }
}

function Get-TarPatternCompletionResults {
    param(
        [string]$CurrentValue,
        [string]$Prefix,
        [string]$ToolTipPrefix = 'Pattern'
    )

    $alwaysQuote = $CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'")
    $cleanCurrent = Remove-TarOuterQuotes -Value $CurrentValue
    $suggestions = New-Object System.Collections.Generic.List[string]

    foreach ($defaultPattern in $script:TarCompletionCatalog.DefaultPatterns) {
        $suggestions.Add($defaultPattern)
    }

    if (-not [string]::IsNullOrWhiteSpace($cleanCurrent)) {
        $suggestions.Add($cleanCurrent)

        if ($cleanCurrent -notmatch '[\*\?\[]') {
            $suggestions.Add($cleanCurrent + '*')
            $suggestions.Add('*' + $cleanCurrent + '*')
            if ($cleanCurrent -notmatch '[/\\]$') {
                $suggestions.Add($cleanCurrent + '/*')
            }
        }
    }

    foreach ($value in ($suggestions | Sort-Object -Unique)) {
        if (Test-TarStartsWith -Value $value -Prefix $cleanCurrent) {
            $completionText = ConvertTo-TarQuotedValue -Value $value -AlwaysQuote:$alwaysQuote
            if ($Prefix) {
                $completionText = $Prefix + $completionText
            }

            New-TarCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip ($ToolTipPrefix + ': ' + $value)
        }
    }
}

function Invoke-TarValueCompletion {
    param(
        [string]$ValueKind,
        [string]$CurrentValue,
        [string]$Prefix
    )

    switch ($ValueKind) {
        'ArchivePath' {
            Get-TarPathCompletionResults -CurrentValue $CurrentValue -Prefix $Prefix -ToolTipPrefix 'Archive path'
            break
        }
        'DirectoryPath' {
            Get-TarPathCompletionResults -CurrentValue $CurrentValue -Prefix $Prefix -DirectoryOnly -ToolTipPrefix 'Directory path'
            break
        }
        'Format' {
            Get-TarSimpleValueResults -Values $script:TarCompletionCatalog.FormatValues -CurrentValue $CurrentValue -ToolTipPrefix 'Archive format' -Prefix $Prefix
            break
        }
        'DateTime' {
            Get-TarSimpleValueResults -Values $script:TarCompletionCatalog.MtimeHints -CurrentValue $CurrentValue -ToolTipPrefix 'Modification time' -Prefix $Prefix
            break
        }
        'BlockSize' {
            Get-TarSimpleValueResults -Values $script:TarCompletionCatalog.BlockSizeHints -CurrentValue $CurrentValue -ToolTipPrefix '512-byte record count' -Prefix $Prefix
            break
        }
        'Pattern' {
            Get-TarPatternCompletionResults -CurrentValue $CurrentValue -Prefix $Prefix -ToolTipPrefix 'Pattern'
            break
        }
    }
}

function Invoke-TarPositionalCompletion {
    param(
        [string]$Mode,
        [string]$CurrentValue,
        [bool]$IncludeOptions
    )

    $results = @()
    $seen = @{}

    if ($IncludeOptions) {
        foreach ($option in (Get-TarOptionCompletionResults -Mode $Mode -CurrentValue '')) {
            if (-not $seen.ContainsKey($option.CompletionText)) {
                $seen[$option.CompletionText] = $true
                $results += $option
            }
        }
    }

    if ($Mode -in @('c', 'r', 'u')) {
        if ($CurrentValue.StartsWith('@')) {
            foreach ($item in (Get-TarPathCompletionResults -CurrentValue $CurrentValue.Substring(1) -Prefix '@' -ToolTipPrefix 'Source archive')) {
                if (-not $seen.ContainsKey($item.CompletionText)) {
                    $seen[$item.CompletionText] = $true
                    $results += $item
                }
            }
        }
        else {
            foreach ($item in (Get-TarPathCompletionResults -CurrentValue $CurrentValue -ToolTipPrefix 'Archive input')) {
                if (-not $seen.ContainsKey($item.CompletionText)) {
                    $seen[$item.CompletionText] = $true
                    $results += $item
                }
            }
        }
    }
    elseif ($Mode -in @('t', 'x')) {
        foreach ($item in (Get-TarPatternCompletionResults -CurrentValue $CurrentValue -ToolTipPrefix 'Archive entry pattern')) {
            if (-not $seen.ContainsKey($item.CompletionText)) {
                $seen[$item.CompletionText] = $true
                $results += $item
            }
        }
    }

    @($results)
}

function Complete-Tar {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if (-not (Resolve-TarCommandName)) {
        return
    }

    Initialize-TarCompletionCatalog

    $line = $commandAst.ToString()
    $prefixLength = [Math]::Min([Math]::Max($cursorPosition, 0), $line.Length)
    $linePrefix = $line.Substring(0, $prefixLength)
    $tokens = @([regex]::Matches($linePrefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    $hasTrailingSpace = ($linePrefix -match '\s$') -or ($cursorPosition -gt $line.Length)
    $currentToken = if ($hasTrailingSpace) { '' } else { Get-TarCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete }

    [object[]]$argumentTokens = if ($tokens.Count -gt 1) {
        @($tokens[1..($tokens.Count - 1)])
    }
    else {
        @()
    }

    [object[]]$completedTokens = if ($hasTrailingSpace) {
        @($argumentTokens)
    }
    elseif ($argumentTokens.Count -gt 1) {
        @($argumentTokens[0..($argumentTokens.Count - 2)])
    }
    else {
        @()
    }

    $state = Get-TarCompletionState -Tokens $completedTokens

    if (-not $hasTrailingSpace) {
        $currentValueContext = Get-TarCurrentValueContext -Token $currentToken -KnownMode $state.Mode
        if ($currentValueContext) {
            Invoke-TarValueCompletion -ValueKind $currentValueContext.ValueKind -CurrentValue $currentValueContext.CurrentValue -Prefix $currentValueContext.Prefix
            return
        }
    }

    if ($state.PendingValue) {
        Invoke-TarValueCompletion -ValueKind $state.PendingValue -CurrentValue $currentToken -Prefix ''
        return
    }

    if (-not $state.Mode) {
        Get-TarModeCompletionResults -CurrentValue $currentToken
        return
    }

    if ((-not $state.OptionTerminated) -and $currentToken.StartsWith('-')) {
        Get-TarOptionCompletionResults -Mode $state.Mode -CurrentValue $currentToken
        return
    }

    Invoke-TarPositionalCompletion -Mode $state.Mode -CurrentValue $currentToken -IncludeOptions:((-not $state.OptionTerminated) -and [string]::IsNullOrEmpty($currentToken))
}

Initialize-TarCompletionCatalog

Register-ArgumentCompleter -Native -CommandName 'tar', 'tar.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Tar -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
