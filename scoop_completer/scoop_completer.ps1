<#
.SYNOPSIS
    Registers a native PowerShell argument completer for Scoop.

.DESCRIPTION
    Provides a hybrid, static-first native argument completer for `scoop`,
    `scoop.cmd`, and `scoop.ps1`.

    The completer covers:
    - top-level Scoop commands and nested command families
    - documented switches and enums like `--arch`
    - cached local completion for installed apps, buckets, shims, aliases, and config keys
    - path-aware completion for manifest, import, and shim-path slots
    - placeholder-oriented suggestions for free-form query, URL, and command values

    The script is safe to dot-source multiple times and keeps its top level
    compatible with `Import-CompleterScript`.
#>

Set-StrictMode -Version Latest

function New-ScoopCompletionResult {
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

function New-ScoopOptionSpec {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [string]$ValueKind,
        [switch]$OptionalValue
    )

    foreach ($token in @($Tokens)) {
        [pscustomobject]@{
            Token         = $token
            Description   = $Description
            ValueKind     = $ValueKind
            OptionalValue = [bool]$OptionalValue
        }
    }
}

function New-ScoopCommandSpec {
    param(
        [string]$Path,
        [string]$Description,
        [string[]]$Subcommands,
        [object[]]$Options,
        [string[]]$Positionals
    )

    [pscustomobject]@{
        Path        = if ($null -eq $Path) { '' } else { $Path }
        Description = $Description
        Subcommands = @($Subcommands)
        Options     = @($Options)
        Positionals = @($Positionals)
    }
}

function Test-ScoopCacheFresh {
    param(
        [datetime]$LoadedAt,
        [int]$TtlSeconds
    )

    if ($LoadedAt -eq [datetime]::MinValue) {
        return $false
    }

    ((Get-Date) - $LoadedAt).TotalSeconds -lt $TtlSeconds
}

function Get-ScoopUniqueStrings {
    param([string[]]$Items)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $results = New-Object System.Collections.Generic.List[string]

    foreach ($item in @($Items)) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        if ($seen.Add($item)) {
            [void]$results.Add($item)
        }
    }

    @($results.ToArray())
}

function Get-ScoopCompletionCache {
    if (-not (Get-Variable -Name ScoopCompletionCache -Scope Script -ErrorAction Ignore)) {
        $installOptions = @(
            New-ScoopOptionSpec -Tokens @('-g', '--global') -Description 'Install the app globally.'
            New-ScoopOptionSpec -Tokens @('-i', '--independent') -Description 'Do not install dependencies automatically.'
            New-ScoopOptionSpec -Tokens @('-k', '--no-cache') -Description 'Do not use the download cache.'
            New-ScoopOptionSpec -Tokens @('-s', '--skip-hash-check') -Description 'Skip hash validation.'
            New-ScoopOptionSpec -Tokens @('-u', '--no-update-scoop') -Description 'Do not update Scoop before installing.'
            New-ScoopOptionSpec -Tokens @('-a', '--arch') -Description 'Use the specified architecture.' -ValueKind 'Arch'
        )
        $downloadOptions = @(
            New-ScoopOptionSpec -Tokens @('-g', '--global') -Description 'Download for a globally installed app.'
            New-ScoopOptionSpec -Tokens @('-i', '--independent') -Description 'Do not install dependencies automatically.'
            New-ScoopOptionSpec -Tokens @('-k', '--no-cache') -Description 'Do not use the download cache.'
            New-ScoopOptionSpec -Tokens @('-s', '--skip-hash-check') -Description 'Skip hash verification.'
            New-ScoopOptionSpec -Tokens @('-u', '--no-update-scoop') -Description 'Do not update Scoop before downloading.'
            New-ScoopOptionSpec -Tokens @('-a', '--arch') -Description 'Use the specified architecture.' -ValueKind 'Arch'
        )
        $updateOptions = @(
            New-ScoopOptionSpec -Tokens @('-f', '--force') -Description 'Force update even when there is no newer version.'
            New-ScoopOptionSpec -Tokens @('-g', '--global') -Description 'Update a globally installed app.'
            New-ScoopOptionSpec -Tokens @('-i', '--independent') -Description 'Do not install dependencies automatically.'
            New-ScoopOptionSpec -Tokens @('-k', '--no-cache') -Description 'Do not use the download cache.'
            New-ScoopOptionSpec -Tokens @('-s', '--skip-hash-check') -Description 'Skip hash validation.'
            New-ScoopOptionSpec -Tokens @('-q', '--quiet') -Description 'Hide extraneous messages.'
            New-ScoopOptionSpec -Tokens @('-a', '--all') -Description 'Update all apps.'
        )
        $cleanupOptions = @(
            New-ScoopOptionSpec -Tokens @('-a', '--all') -Description 'Cleanup all apps.'
            New-ScoopOptionSpec -Tokens @('-g', '--global') -Description 'Cleanup a globally installed app.'
            New-ScoopOptionSpec -Tokens @('-k', '--cache') -Description 'Remove outdated download cache.'
        )
        $holdOptions = @(
            New-ScoopOptionSpec -Tokens @('-g', '--global') -Description 'Target globally installed apps.'
        )
        $shimOptions = @(
            New-ScoopOptionSpec -Tokens @('-g', '--global') -Description 'Manipulate global shim(s).'
        )

        $commandSpecs = @(
            New-ScoopCommandSpec -Path '' -Description 'Scoop package manager.' -Subcommands @(
                'alias', 'bucket', 'cache', 'cat', 'checkup', 'cleanup', 'config', 'create', 'depends', 'download',
                'export', 'help', 'hold', 'home', 'import', 'info', 'install', 'list', 'prefix', 'reset', 'search',
                'shim', 'status', 'unhold', 'uninstall', 'update', 'virustotal', 'which'
            ) -Options @() -Positionals @()
            New-ScoopCommandSpec -Path 'alias' -Description 'Manage scoop aliases.' -Subcommands @('add', 'rm', 'list') -Options @() -Positionals @()
            New-ScoopCommandSpec -Path 'alias add' -Description 'Add a Scoop alias.' -Subcommands @() -Options @() -Positionals @('AliasNameNew', 'AliasCommand', 'Description')
            New-ScoopCommandSpec -Path 'alias rm' -Description 'Remove a Scoop alias.' -Subcommands @() -Options @() -Positionals @('AliasName')
            New-ScoopCommandSpec -Path 'alias list' -Description 'List Scoop aliases.' -Subcommands @() -Options @(
                New-ScoopOptionSpec -Tokens @('-v', '--verbose') -Description 'Show alias descriptions and headers.'
            ) -Positionals @()
            New-ScoopCommandSpec -Path 'bucket' -Description 'Manage Scoop buckets.' -Subcommands @('add', 'list', 'known', 'rm') -Options @() -Positionals @()
            New-ScoopCommandSpec -Path 'bucket add' -Description 'Add a bucket.' -Subcommands @() -Options @() -Positionals @('KnownBucketName', 'RepoOrUrl')
            New-ScoopCommandSpec -Path 'bucket list' -Description 'List installed buckets.' -Subcommands @() -Options @() -Positionals @()
            New-ScoopCommandSpec -Path 'bucket known' -Description 'List known buckets.' -Subcommands @() -Options @() -Positionals @()
            New-ScoopCommandSpec -Path 'bucket rm' -Description 'Remove a bucket.' -Subcommands @() -Options @() -Positionals @('CurrentBucket')
            New-ScoopCommandSpec -Path 'cache' -Description 'Show or clear the download cache.' -Subcommands @('show', 'rm') -Options @() -Positionals @()
            New-ScoopCommandSpec -Path 'cache show' -Description 'Show cache entries.' -Subcommands @() -Options @() -Positionals @('CacheApp')
            New-ScoopCommandSpec -Path 'cache rm' -Description 'Remove cached entries.' -Subcommands @() -Options @(
                New-ScoopOptionSpec -Tokens @('-a', '--all') -Description 'Remove all cached entries.'
            ) -Positionals @('CacheAppOrAll')
            New-ScoopCommandSpec -Path 'cat' -Description 'Show manifest content for an app.' -Subcommands @() -Options @() -Positionals @('ManifestApp')
            New-ScoopCommandSpec -Path 'checkup' -Description 'Run diagnostic checks.' -Subcommands @() -Options @() -Positionals @()
            New-ScoopCommandSpec -Path 'cleanup' -Description 'Remove old app versions.' -Subcommands @() -Options $cleanupOptions -Positionals @('InstalledAppOrAll')
            New-ScoopCommandSpec -Path 'config' -Description 'Get or set Scoop configuration.' -Subcommands @('rm') -Options @() -Positionals @('ConfigKey', 'ConfigValue')
            New-ScoopCommandSpec -Path 'config rm' -Description 'Remove a Scoop configuration value.' -Subcommands @() -Options @() -Positionals @('ConfigKey')
            New-ScoopCommandSpec -Path 'create' -Description 'Create a custom app manifest.' -Subcommands @() -Options @() -Positionals @('Url')
            New-ScoopCommandSpec -Path 'depends' -Description 'List app dependencies.' -Subcommands @() -Options @() -Positionals @('ManifestApp')
            New-ScoopCommandSpec -Path 'download' -Description 'Download apps into the cache.' -Subcommands @() -Options $downloadOptions -Positionals @('InstallTarget')
            New-ScoopCommandSpec -Path 'export' -Description 'Export installed apps and buckets.' -Subcommands @() -Options @(
                New-ScoopOptionSpec -Tokens @('-c', '--config') -Description 'Export the Scoop configuration file too.'
            ) -Positionals @()
            New-ScoopCommandSpec -Path 'help' -Description 'Show help for a command.' -Subcommands @() -Options @() -Positionals @('HelpTopic')
            New-ScoopCommandSpec -Path 'hold' -Description 'Hold an app to disable updates.' -Subcommands @() -Options $holdOptions -Positionals @('InstalledApp')
            New-ScoopCommandSpec -Path 'home' -Description 'Open an app homepage.' -Subcommands @() -Options @() -Positionals @('ManifestApp')
            New-ScoopCommandSpec -Path 'import' -Description 'Import apps and buckets from a Scoopfile.' -Subcommands @() -Options @() -Positionals @('ScoopFile')
            New-ScoopCommandSpec -Path 'info' -Description 'Display information about an app.' -Subcommands @() -Options @(
                New-ScoopOptionSpec -Tokens @('-v', '--verbose') -Description 'Show full paths and URLs.'
            ) -Positionals @('ManifestApp')
            New-ScoopCommandSpec -Path 'install' -Description 'Install apps.' -Subcommands @() -Options $installOptions -Positionals @('InstallTarget')
            New-ScoopCommandSpec -Path 'list' -Description 'List installed apps.' -Subcommands @() -Options @() -Positionals @('InstalledAppQuery')
            New-ScoopCommandSpec -Path 'prefix' -Description 'Return the path to an app.' -Subcommands @() -Options @() -Positionals @('InstalledApp')
            New-ScoopCommandSpec -Path 'reset' -Description 'Reset an app or switch active version.' -Subcommands @() -Options @() -Positionals @('InstalledAppOrAll')
            New-ScoopCommandSpec -Path 'search' -Description 'Search available apps.' -Subcommands @() -Options @() -Positionals @('Query')
            New-ScoopCommandSpec -Path 'shim' -Description 'Manipulate Scoop shims.' -Subcommands @('add', 'rm', 'list', 'info', 'alter') -Options @() -Positionals @()
            New-ScoopCommandSpec -Path 'shim add' -Description 'Add a custom shim.' -Subcommands @() -Options $shimOptions -Positionals @('ShimNameNew', 'CommandPath', 'PassthroughArg')
            New-ScoopCommandSpec -Path 'shim rm' -Description 'Remove one or more shims.' -Subcommands @() -Options $shimOptions -Positionals @('ShimName')
            New-ScoopCommandSpec -Path 'shim list' -Description 'List shims.' -Subcommands @() -Options $shimOptions -Positionals @('ShimName')
            New-ScoopCommandSpec -Path 'shim info' -Description 'Show shim information.' -Subcommands @() -Options $shimOptions -Positionals @('ShimName')
            New-ScoopCommandSpec -Path 'shim alter' -Description 'Alternate a shim target source.' -Subcommands @() -Options $shimOptions -Positionals @('ShimName')
            New-ScoopCommandSpec -Path 'status' -Description 'Show status and check for updates.' -Subcommands @() -Options @(
                New-ScoopOptionSpec -Tokens @('-l', '--local') -Description 'Check only locally installed apps and skip remote checks.'
            ) -Positionals @()
            New-ScoopCommandSpec -Path 'unhold' -Description 'Unhold an app.' -Subcommands @() -Options $holdOptions -Positionals @('InstalledApp')
            New-ScoopCommandSpec -Path 'uninstall' -Description 'Uninstall an app.' -Subcommands @() -Options @(
                New-ScoopOptionSpec -Tokens @('-g', '--global') -Description 'Uninstall a globally installed app.'
                New-ScoopOptionSpec -Tokens @('-p', '--purge') -Description 'Remove all persistent data.'
            ) -Positionals @('InstalledApp')
            New-ScoopCommandSpec -Path 'update' -Description 'Update apps or Scoop itself.' -Subcommands @() -Options $updateOptions -Positionals @('InstalledAppOrAll')
            New-ScoopCommandSpec -Path 'virustotal' -Description 'Look up app hashes or URLs on VirusTotal.' -Subcommands @() -Options @(
                New-ScoopOptionSpec -Tokens @('-a', '--all') -Description 'Check all installed apps.'
                New-ScoopOptionSpec -Tokens @('-s', '--scan') -Description 'Send unknown packages for analysis.'
                New-ScoopOptionSpec -Tokens @('-n', '--no-depends') -Description 'Do not include dependencies.'
                New-ScoopOptionSpec -Tokens @('-u', '--no-update-scoop') -Description 'Do not update Scoop before checking.'
                New-ScoopOptionSpec -Tokens @('-p', '--passthru') -Description 'Return reports as objects.'
            ) -Positionals @('InstalledAppOrAll')
            New-ScoopCommandSpec -Path 'which' -Description 'Locate a Scoop shim or executable.' -Subcommands @() -Options @() -Positionals @('ShimName')
        )

        $specLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($spec in $commandSpecs) {
            $specLookup[$spec.Path] = $spec
        }

        $script:ScoopCompletionCache = @{
            ExecutablePath         = $null
            ExecutablePathProbed   = $false
            SpecLookup             = $specLookup
            RuntimeCacheTtlSeconds = 60
            ManifestCacheTtlSeconds = 300
            ConfigCacheTtlSeconds  = 300
            InstalledApps          = @()
            InstalledAppsLoadedAt  = [datetime]::MinValue
            KnownBuckets           = @()
            KnownBucketsLoadedAt   = [datetime]::MinValue
            CurrentBuckets         = @()
            CurrentBucketsLoadedAt = [datetime]::MinValue
            ShimNames              = @()
            ShimNamesLoadedAt      = [datetime]::MinValue
            AliasNames             = @()
            AliasNamesLoadedAt     = [datetime]::MinValue
            CacheAppNames          = @()
            CacheAppNamesLoadedAt  = [datetime]::MinValue
            ScoopRootPath          = $null
            ManifestAppNames       = @()
            ManifestAppNamesLoadedAt = [datetime]::MinValue
            ConfigSpecs            = @()
            ConfigSpecsLoadedAt    = [datetime]::MinValue
        }
    }

    $script:ScoopCompletionCache
}

function Resolve-ScoopCommandName {
    $cache = Get-ScoopCompletionCache
    if ($cache.ExecutablePathProbed) {
        return $cache.ExecutablePath
    }

    $cache.ExecutablePathProbed = $true
    $cache.ExecutablePath = $null

    foreach ($name in @('scoop.cmd', 'scoop', 'scoop.ps1')) {
        $command = Get-Command -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            $cache.ExecutablePath = if ($command.Source) { $command.Source } else { $command.Name }
            break
        }
    }

    $cache.ExecutablePath
}

function Invoke-ScoopCapture {
    param([string[]]$Arguments)

    $commandName = Resolve-ScoopCommandName
    if ([string]::IsNullOrWhiteSpace($commandName)) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>$null 3>$null 4>$null 5>$null 6>$null)
    } catch {
        @()
    }
}

function Get-ScoopRootPath {
    $cache = Get-ScoopCompletionCache
    if (-not [string]::IsNullOrWhiteSpace($cache.ScoopRootPath)) {
        return $cache.ScoopRootPath
    }

    $commandName = Resolve-ScoopCommandName
    if (-not [string]::IsNullOrWhiteSpace($commandName)) {
        $shimDirectory = Split-Path -Path $commandName -Parent
        if (-not [string]::IsNullOrWhiteSpace($shimDirectory)) {
            $leaf = Split-Path -Path $shimDirectory -Leaf
            if ($leaf -ieq 'shims') {
                $cache.ScoopRootPath = Split-Path -Path $shimDirectory -Parent
                return $cache.ScoopRootPath
            }
        }
    }

    $cache.ScoopRootPath = Join-Path -Path $HOME -ChildPath 'scoop'
    $cache.ScoopRootPath
}

function Remove-ScoopOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function Remove-ScoopAnsiEscapeSequences {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    [regex]::Replace($Value, '\x1b\[[0-9;?]*[ -/]*[@-~]', '')
}

function ConvertTo-ScoopQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + ($Value.Replace('`', '``').Replace('"', '`"')) + '"'
    }

    $Value
}

function Test-ScoopPathLikeInput {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $cleanValue = Remove-ScoopOuterQuotes -Value $Value
    $cleanValue -match '^(?:\.{1,2}[\\/]|[\\/]|~[\\/]|[A-Za-z]:|\\\\)'
}

function Get-ScoopTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-ScoopCurrentToken {
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

function Get-ScoopArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += Get-ScoopTokenText -Element $element
        }
    }

    $tokens
}

function ConvertFrom-ScoopTableFirstColumn {
    param([object[]]$Lines)

    $values = New-Object System.Collections.Generic.List[string]
    $inTable = $false

    foreach ($line in @($Lines)) {
        if ($null -eq $line) {
            continue
        }

        if ($line -isnot [string] -and $line.PSObject.Properties['Name']) {
            $name = [string]$line.Name
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                [void]$values.Add($name)
            }
            continue
        }

        $line = Remove-ScoopAnsiEscapeSequences -Value $line.ToString()
        if (-not $inTable) {
            if ($line -match '^\s*Name\b') {
                $inTable = $true
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*-{2,}') {
            continue
        }

        if ($line -match '^\s*(?<name>\S+)') {
            [void]$values.Add($matches['name'])
        }
    }

    Get-ScoopUniqueStrings -Items @($values.ToArray())
}

function Get-ScoopInstalledApps {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.InstalledAppsLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.InstalledApps
    }

    $cache.InstalledApps = ConvertFrom-ScoopTableFirstColumn -Lines (Invoke-ScoopCapture -Arguments @('list'))
    $cache.InstalledAppsLoadedAt = Get-Date
    $cache.InstalledApps
}

function Get-ScoopKnownBuckets {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.KnownBucketsLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.KnownBuckets
    }

    $names = foreach ($line in @(Invoke-ScoopCapture -Arguments @('bucket', 'known'))) {
        $trimmed = (Remove-ScoopAnsiEscapeSequences -Value $line).Trim()
        if ($trimmed -match '^[A-Za-z0-9._-]+$') {
            $trimmed
        }
    }

    $cache.KnownBuckets = Get-ScoopUniqueStrings -Items $names
    $cache.KnownBucketsLoadedAt = Get-Date
    $cache.KnownBuckets
}

function Get-ScoopCurrentBuckets {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.CurrentBucketsLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.CurrentBuckets
    }

    $cache.CurrentBuckets = ConvertFrom-ScoopTableFirstColumn -Lines (Invoke-ScoopCapture -Arguments @('bucket', 'list'))
    $cache.CurrentBucketsLoadedAt = Get-Date
    $cache.CurrentBuckets
}

function Get-ScoopShimNames {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.ShimNamesLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.ShimNames
    }

    $cache.ShimNames = ConvertFrom-ScoopTableFirstColumn -Lines (Invoke-ScoopCapture -Arguments @('shim', 'list'))
    $cache.ShimNamesLoadedAt = Get-Date
    $cache.ShimNames
}

function Get-ScoopAliasNames {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.AliasNamesLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.AliasNames
    }

    $lines = Invoke-ScoopCapture -Arguments @('alias', 'list')
    if (@($lines) -match 'No alias found') {
        $cache.AliasNames = @()
    } else {
        $cache.AliasNames = ConvertFrom-ScoopTableFirstColumn -Lines $lines
    }

    $cache.AliasNamesLoadedAt = Get-Date
    $cache.AliasNames
}

function Get-ScoopCacheAppNames {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.CacheAppNamesLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.CacheAppNames
    }

    $lines = Invoke-ScoopCapture -Arguments @('cache', 'show')
    $names = ConvertFrom-ScoopTableFirstColumn -Lines $lines
    if (-not $names -or $names.Count -eq 0) {
        $names = Get-ScoopInstalledApps
    }

    $cache.CacheAppNames = $names
    $cache.CacheAppNamesLoadedAt = Get-Date
    $cache.CacheAppNames
}

function Get-ScoopManifestAppNames {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.ManifestAppNamesLoadedAt -TtlSeconds $cache.ManifestCacheTtlSeconds) {
        return $cache.ManifestAppNames
    }

    $rootPath = Get-ScoopRootPath
    $bucketPattern = Join-Path -Path $rootPath -ChildPath 'buckets\*\bucket\*.json'
    $names = Get-ChildItem -Path $bucketPattern -ErrorAction SilentlyContinue |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }

    $cache.ManifestAppNames = Get-ScoopUniqueStrings -Items $names
    $cache.ManifestAppNamesLoadedAt = Get-Date
    $cache.ManifestAppNames
}

function Get-ScoopConfigSpecs {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.ConfigSpecsLoadedAt -TtlSeconds $cache.ConfigCacheTtlSeconds) {
        return $cache.ConfigSpecs
    }

    $cache.ConfigSpecs = @(
        [pscustomobject]@{ Name = 'use_external_7zip'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'use_lessmsi'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'use_sqlite_cache'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'no_junction'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'scoop_repo'; Hint = 'Repository URL.'; Values = @(); Placeholder = '<git-repository-url>' }
        [pscustomobject]@{ Name = 'scoop_branch'; Hint = 'master|develop'; Values = @('master', 'develop'); Placeholder = $null }
        [pscustomobject]@{ Name = 'proxy'; Hint = 'Proxy setting.'; Values = @('default', 'none', 'currentuser@default'); Placeholder = '<username:password@host:port>' }
        [pscustomobject]@{ Name = 'autostash_on_conflict'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'default_architecture'; Hint = '64bit|32bit|arm64'; Values = @('64bit', '32bit', 'arm64'); Placeholder = $null }
        [pscustomobject]@{ Name = 'debug'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'force_update'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'show_update_log'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'show_manifest'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'shim'; Hint = 'kiennq|scoopcs|71'; Values = @('kiennq', 'scoopcs', '71'); Placeholder = $null }
        [pscustomobject]@{ Name = 'root_path'; Hint = 'Path to Scoop root.'; Values = @(); Placeholder = '<path>' }
        [pscustomobject]@{ Name = 'global_path'; Hint = 'Path to global Scoop root.'; Values = @(); Placeholder = '<path>' }
        [pscustomobject]@{ Name = 'cache_path'; Hint = 'Download cache path.'; Values = @(); Placeholder = '<path>' }
        [pscustomobject]@{ Name = 'gh_token'; Hint = 'GitHub API token.'; Values = @(); Placeholder = '<value>' }
        [pscustomobject]@{ Name = 'virustotal_api_key'; Hint = 'VirusTotal API key.'; Values = @(); Placeholder = '<value>' }
        [pscustomobject]@{ Name = 'cat_style'; Hint = 'bat --style value.'; Values = @(); Placeholder = '<bat-style>' }
        [pscustomobject]@{ Name = 'ignore_running_processes'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'private_hosts'; Hint = 'JSON-like host list.'; Values = @(); Placeholder = '<json-array>' }
        [pscustomobject]@{ Name = 'hold_update_until'; Hint = 'Disable self-updates until this date.'; Values = @(); Placeholder = '<date>' }
        [pscustomobject]@{ Name = 'update_nightly'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'use_isolated_path'; Hint = '$true|$false|[string]'; Values = @('$true', '$false'); Placeholder = '<env-var-name>' }
        [pscustomobject]@{ Name = 'aria2-enabled'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'aria2-warning-enabled'; Hint = '$true|$false'; Values = @('$true', '$false'); Placeholder = $null }
        [pscustomobject]@{ Name = 'aria2-retry-wait'; Hint = 'Retry wait seconds.'; Values = @(); Placeholder = '<seconds>' }
        [pscustomobject]@{ Name = 'aria2-split'; Hint = 'Connection count.'; Values = @(); Placeholder = '<count>' }
        [pscustomobject]@{ Name = 'aria2-max-connection-per-server'; Hint = 'Connection count per server.'; Values = @(); Placeholder = '<count>' }
        [pscustomobject]@{ Name = 'aria2-min-split-size'; Hint = 'Minimum split size.'; Values = @(); Placeholder = '<size>' }
        [pscustomobject]@{ Name = 'aria2-options'; Hint = 'Additional aria2 options.'; Values = @(); Placeholder = '<json-array>' }
    )

    $cache.ConfigSpecsLoadedAt = Get-Date
    $cache.ConfigSpecs
}
function Get-ScoopCommandSpec {
    param([string]$PathKey)

    $cache = Get-ScoopCompletionCache
    if ($cache.SpecLookup.ContainsKey($PathKey)) {
        return $cache.SpecLookup[$PathKey]
    }

    $null
}

function Find-ScoopOptionSpec {
    param(
        [string]$PathKey,
        [string]$Token
    )

    $spec = Get-ScoopCommandSpec -PathKey $PathKey
    foreach ($option in @($spec.Options)) {
        if ($option.Token.Equals($Token, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $option
        }
    }

    $null
}

function Get-ScoopCommandState {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $currentToken = if ($CursorPosition -gt $CommandAst.Extent.EndOffset) { '' } else { $WordToComplete }
    $tokens = Get-ScoopArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition

    $pathTokens = New-Object System.Collections.Generic.List[string]
    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingOption = $null
    $afterDoubleDash = $false
    $pathKey = ''

    foreach ($token in @($tokens)) {
        if ($afterDoubleDash) {
            [void]$positionals.Add($token)
            continue
        }

        if ($pendingOption) {
            $pendingOption = $null
            continue
        }

        if ($token -eq '--') {
            $afterDoubleDash = $true
            continue
        }

        if ($token -match '^(?<option>--[A-Za-z0-9-]+)=(?<value>.*)$') {
            $option = Find-ScoopOptionSpec -PathKey $pathKey -Token $matches['option']
            if ($option) {
                continue
            }
        }

        if ($token.StartsWith('-') -and $token -ne '-') {
            $option = Find-ScoopOptionSpec -PathKey $pathKey -Token $token
            if ($option) {
                if ($option.ValueKind -and -not $option.OptionalValue) {
                    $pendingOption = $option
                }
                continue
            }
        }

        if ($pathTokens.Count -eq 0) {
            $rootSpec = Get-ScoopCommandSpec -PathKey ''
            if ($rootSpec.Subcommands -contains $token) {
                [void]$pathTokens.Add($token)
                $pathKey = $token
                continue
            }
        } else {
            $currentSpec = Get-ScoopCommandSpec -PathKey $pathKey
            if ($currentSpec -and $currentSpec.Subcommands -contains $token) {
                [void]$pathTokens.Add($token)
                $pathKey = [string]::Join(' ', $pathTokens)
                continue
            }
        }

        [void]$positionals.Add($token)
    }

    [pscustomobject]@{
        PathKey       = $pathKey
        CurrentToken  = $currentToken
        Positionals   = @($positionals.ToArray())
        PendingOption = $pendingOption
        AfterDoubleDash = $afterDoubleDash
    }
}

function Get-ScoopPathCompletions {
    param(
        [string]$InputPath,
        [string]$Prefix = '',
        [switch]$DirectoriesOnly
    )

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and $InputPath.StartsWith('"')

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput.EndsWith('\') -or $cleanInput.EndsWith('/')) {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }
        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $items = @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)
    if ($DirectoriesOnly) {
        $items = @($items | Where-Object { $_.PSIsContainer })
    }

    foreach ($item in $items) {
        $completionText = if ($cleanInput -and -not [System.IO.Path]::IsPathRooted($cleanInput)) {
            if ($parent -eq '.') {
                $item.Name
            } else {
                Join-Path -Path $parent -ChildPath $item.Name
            }
        } else {
            $item.FullName
        }

        if ($item.PSIsContainer -and -not $completionText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionText += [System.IO.Path]::DirectorySeparatorChar
        }

        $completionText = ConvertTo-ScoopQuotedValue -Value $completionText -AlwaysQuote $alwaysQuote
        $completionText = $Prefix + $completionText

        New-ScoopCompletionResult -CompletionText $completionText -ToolTip $item.FullName -ListItemText $item.Name
    }
}

function New-ScoopLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-ScoopCompletionResult -CompletionText ($Prefix + $Placeholder) -ToolTip $ToolTip -ListItemText $Placeholder
        )
    }

    @(
        New-ScoopCompletionResult -CompletionText ($Prefix + $CurrentValue) -ToolTip $ToolTip -ListItemText $CurrentValue
    )
}

function Get-ScoopDistinctResults {
    param([object[]]$Results)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($result in @($Results)) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.Add($result.CompletionText)) {
            $result
        }
    }
}

function Get-ScoopStringValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [switch]$SuggestWhenEmpty,
        [string]$Prefix = ''
    )

    $typedValue = Remove-ScoopOuterQuotes -Value $CurrentValue
    $results = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrWhiteSpace($typedValue)) {
        if ($Placeholder) {
            [void]$results.Add((New-ScoopCompletionResult -CompletionText ($Prefix + $Placeholder) -ToolTip $ToolTip -ListItemText $Placeholder))
        }

        if ($SuggestWhenEmpty) {
            foreach ($value in @($Values)) {
                if ([string]::IsNullOrWhiteSpace($value)) {
                    continue
                }
                [void]$results.Add((New-ScoopCompletionResult -CompletionText ($Prefix + $value) -ToolTip $ToolTip -ListItemText $value))
            }
        }

        return @(Get-ScoopDistinctResults -Results @($results.ToArray()))
    }

    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }

        if ($value.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-ScoopCompletionResult -CompletionText ($Prefix + $value) -ToolTip $ToolTip -ListItemText $value))
        }
    }

    @(Get-ScoopDistinctResults -Results @($results.ToArray()))
}

function Get-ScoopInstallTargetResults {
    param([string]$CurrentValue)

    $value = Remove-ScoopOuterQuotes -Value $CurrentValue
    if ([string]::IsNullOrWhiteSpace($value)) {
        return New-ScoopLiteralValueResults -CurrentValue '' -Placeholder '<app-or-manifest>' -ToolTip 'Scoop app name, local manifest path, or manifest URL.'
    }

    if ($value -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
        return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<manifest-url>' -ToolTip 'Manifest URL.'
    }

    if ($value -match '^(?<base>.+)@(?<suffix>[^@]*)$') {
        $base = $matches['base']
        $suffix = $matches['suffix']
        if (Test-ScoopPathLikeInput -Value $base) {
            $results = foreach ($result in @(Get-ScoopPathCompletions -InputPath $base)) {
                $updatedValue = ConvertTo-ScoopQuotedValue -Value ((Remove-ScoopOuterQuotes -Value $result.CompletionText) + '@' + $suffix) -AlwaysQuote ($result.CompletionText.StartsWith('"') -and $result.CompletionText.EndsWith('"'))
                New-ScoopCompletionResult -CompletionText $updatedValue -ToolTip $result.ToolTip -ListItemText ($result.ListItemText + '@' + $suffix)
            }
            return @(Get-ScoopDistinctResults -Results $results)
        }

        $manifestResults = Get-ScoopStringValueResults -Values (Get-ScoopManifestAppNames) -CurrentValue $base -Placeholder $null -ToolTip 'Locally available manifest name.'
        foreach ($result in @($manifestResults)) {
            New-ScoopCompletionResult -CompletionText ($result.CompletionText + '@' + $suffix) -ToolTip $result.ToolTip -ListItemText ($result.ListItemText + '@' + $suffix)
        }
        return
    }

    if (Test-ScoopPathLikeInput -Value $value) {
        return Get-ScoopPathCompletions -InputPath $CurrentValue
    }

    Get-ScoopStringValueResults -Values (Get-ScoopManifestAppNames) -CurrentValue $CurrentValue -Placeholder '<app-or-manifest>' -ToolTip 'Locally available manifest name.'
}

function Get-ScoopConfigValueResults {
    param(
        [string]$ConfigKey,
        [string]$CurrentValue
    )

    $spec = Get-ScoopConfigSpecs | Where-Object { $_.Name -eq $ConfigKey } | Select-Object -First 1
    if (-not $spec) {
        return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<value>' -ToolTip "Value for '$ConfigKey'."
    }

    if ($ConfigKey -in @('root_path', 'global_path', 'cache_path')) {
        if (Test-ScoopPathLikeInput -Value $CurrentValue) {
            return Get-ScoopPathCompletions -InputPath $CurrentValue -DirectoriesOnly
        }

        return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<path>' -ToolTip "Path value for '$ConfigKey'."
    }

    if (@($spec.Values).Count -gt 0) {
        $results = New-Object System.Collections.Generic.List[object]
        foreach ($item in @(Get-ScoopStringValueResults -Values $spec.Values -CurrentValue $CurrentValue -Placeholder $spec.Placeholder -ToolTip $spec.Hint -SuggestWhenEmpty)) {
            [void]$results.Add($item)
        }
        return @(Get-ScoopDistinctResults -Results @($results.ToArray()))
    }

    $placeholder = if ($spec.Placeholder) { $spec.Placeholder } else { '<value>' }
    New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder $placeholder -ToolTip $spec.Hint
}

function Get-ScoopValueResults {
    param(
        [string]$ValueKind,
        [string]$CurrentValue,
        [pscustomobject]$State,
        [string]$Prefix = ''
    )

    switch ($ValueKind) {
        'Arch' { return Get-ScoopStringValueResults -Values @('32bit', '64bit', 'arm64') -CurrentValue $CurrentValue -Placeholder $null -ToolTip 'Supported architecture.' -SuggestWhenEmpty -Prefix $Prefix }
        'InstalledApp' { return Get-ScoopStringValueResults -Values (Get-ScoopInstalledApps) -CurrentValue $CurrentValue -Placeholder '<app>' -ToolTip 'Installed Scoop app.' -SuggestWhenEmpty -Prefix $Prefix }
        'InstalledAppQuery' { return Get-ScoopStringValueResults -Values (Get-ScoopInstalledApps) -CurrentValue $CurrentValue -Placeholder '<query>' -ToolTip 'Installed app query.' -SuggestWhenEmpty -Prefix $Prefix }
        'InstalledAppOrAll' {
            return Get-ScoopStringValueResults -Values (@('*') + (Get-ScoopInstalledApps)) -CurrentValue $CurrentValue -Placeholder '<app>' -ToolTip 'Installed Scoop app or *.' -SuggestWhenEmpty -Prefix $Prefix
        }
        'ManifestApp' {
            $combined = Get-ScoopUniqueStrings -Items ((Get-ScoopInstalledApps) + (Get-ScoopManifestAppNames))
            return Get-ScoopStringValueResults -Values $combined -CurrentValue $CurrentValue -Placeholder '<app>' -ToolTip 'Scoop app name.' -Prefix $Prefix
        }
        'InstallTarget' { return Get-ScoopInstallTargetResults -CurrentValue $CurrentValue }
        'KnownBucketName' { return Get-ScoopStringValueResults -Values (Get-ScoopKnownBuckets) -CurrentValue $CurrentValue -Placeholder '<bucket>' -ToolTip 'Known Scoop bucket.' -SuggestWhenEmpty -Prefix $Prefix }
        'CurrentBucket' { return Get-ScoopStringValueResults -Values (Get-ScoopCurrentBuckets) -CurrentValue $CurrentValue -Placeholder '<bucket>' -ToolTip 'Installed Scoop bucket.' -SuggestWhenEmpty -Prefix $Prefix }
        'AliasName' { return Get-ScoopStringValueResults -Values (Get-ScoopAliasNames) -CurrentValue $CurrentValue -Placeholder '<alias>' -ToolTip 'Defined Scoop alias.' -SuggestWhenEmpty -Prefix $Prefix }
        'AliasNameNew' { return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<alias-name>' -ToolTip 'New alias name.' -Prefix $Prefix }
        'AliasCommand' { return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<command>' -ToolTip 'Alias command text.' -Prefix $Prefix }
        'Description' { return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<description>' -ToolTip 'Free-form description.' -Prefix $Prefix }
        'CacheApp' { return Get-ScoopStringValueResults -Values (Get-ScoopCacheAppNames) -CurrentValue $CurrentValue -Placeholder '<app>' -ToolTip 'Cached app name.' -SuggestWhenEmpty -Prefix $Prefix }
        'CacheAppOrAll' { return Get-ScoopStringValueResults -Values (@('*') + (Get-ScoopCacheAppNames)) -CurrentValue $CurrentValue -Placeholder '<app>' -ToolTip 'Cached app name or *.' -SuggestWhenEmpty -Prefix $Prefix }
        'ConfigKey' {
            $keys = Get-ScoopConfigSpecs | ForEach-Object { $_.Name }
            return Get-ScoopStringValueResults -Values $keys -CurrentValue $CurrentValue -Placeholder '<config-key>' -ToolTip 'Scoop config key.' -SuggestWhenEmpty -Prefix $Prefix
        }
        'ConfigValue' {
            $configKey = if ($State.PathKey -eq 'config') { $State.Positionals[0] } else { $null }
            return Get-ScoopConfigValueResults -ConfigKey $configKey -CurrentValue $CurrentValue
        }
        'Url' { return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<url>' -ToolTip 'URL value.' -Prefix $Prefix }
        'RepoOrUrl' {
            if (Test-ScoopPathLikeInput -Value $CurrentValue) {
                return Get-ScoopPathCompletions -InputPath $CurrentValue
            }
            return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<repo-url>' -ToolTip 'Bucket repository URL or local path.' -Prefix $Prefix
        }
        'ScoopFile' {
            if (Test-ScoopPathLikeInput -Value $CurrentValue) {
                return Get-ScoopPathCompletions -InputPath $CurrentValue
            }
            return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<path-or-url-to-scoopfile.json>' -ToolTip 'Scoopfile path or URL.' -Prefix $Prefix
        }
        'HelpTopic' {
            $rootSpec = Get-ScoopCommandSpec -PathKey ''
            return Get-ScoopStringValueResults -Values $rootSpec.Subcommands -CurrentValue $CurrentValue -Placeholder '<command>' -ToolTip 'Scoop command name.' -SuggestWhenEmpty -Prefix $Prefix
        }
        'CommandPath' {
            if (Test-ScoopPathLikeInput -Value $CurrentValue) {
                return Get-ScoopPathCompletions -InputPath $CurrentValue
            }
            return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<command-path>' -ToolTip 'Path to the shim target command.' -Prefix $Prefix
        }
        'PassthroughArg' { return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<arg>' -ToolTip 'Argument passed through after the shim target.' -Prefix $Prefix }
        'ShimName' { return Get-ScoopStringValueResults -Values (Get-ScoopShimNames) -CurrentValue $CurrentValue -Placeholder '<shim>' -ToolTip 'Existing Scoop shim.' -SuggestWhenEmpty -Prefix $Prefix }
        'ShimNameNew' { return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<shim-name>' -ToolTip 'New shim name.' -Prefix $Prefix }
        'Query' { return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<query>' -ToolTip 'Free-form search query.' -Prefix $Prefix }
        default { return @() }
    }
}

function Write-ScoopSubcommandResults {
    param(
        [string]$PathKey,
        [string]$CurrentToken
    )

    $spec = Get-ScoopCommandSpec -PathKey $PathKey
    foreach ($subcommand in @($spec.Subcommands)) {
        if ([string]::IsNullOrWhiteSpace($CurrentToken) -or $subcommand.StartsWith($CurrentToken, [System.StringComparison]::OrdinalIgnoreCase)) {
            $childPath = if ([string]::IsNullOrWhiteSpace($PathKey)) { $subcommand } else { $PathKey + ' ' + $subcommand }
            $childSpec = Get-ScoopCommandSpec -PathKey $childPath
            $toolTip = if ($childSpec) { $childSpec.Description } else { $subcommand }
            New-ScoopCompletionResult -CompletionText $subcommand -ToolTip $toolTip -ListItemText $subcommand
        }
    }
}

function Write-ScoopOptionResults {
    param(
        [string]$PathKey,
        [string]$CurrentToken
    )

    $spec = Get-ScoopCommandSpec -PathKey $PathKey
    if (-not $spec) {
        return
    }

    $results = foreach ($option in @($spec.Options)) {
        if ([string]::IsNullOrWhiteSpace($CurrentToken) -or $option.Token.StartsWith($CurrentToken, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-ScoopCompletionResult -CompletionText $option.Token -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $option.Token
        }
    }

    Get-ScoopDistinctResults -Results @($results)
}

function Write-ScoopOperandResults {
    param([pscustomobject]$State)

    $spec = Get-ScoopCommandSpec -PathKey $State.PathKey
    if (-not $spec) {
        return
    }

    if ($State.AfterDoubleDash) {
        return Get-ScoopValueResults -ValueKind 'PassthroughArg' -CurrentValue $State.CurrentToken -State $State
    }

    if ($spec.Path -eq 'config' -and $State.Positionals.Count -eq 0) {
        $results = @(
            @(Write-ScoopSubcommandResults -PathKey $State.PathKey -CurrentToken $State.CurrentToken)
            @(Get-ScoopValueResults -ValueKind 'ConfigKey' -CurrentValue $State.CurrentToken -State $State)
        )
        return Get-ScoopDistinctResults -Results $results
    }

    if ($spec.Subcommands.Count -gt 0 -and $State.Positionals.Count -eq 0) {
        return Write-ScoopSubcommandResults -PathKey $State.PathKey -CurrentToken $State.CurrentToken
    }

    $positionIndex = $State.Positionals.Count
    if ($positionIndex -ge $spec.Positionals.Count -and $spec.Positionals.Count -gt 0) {
        $positionIndex = $spec.Positionals.Count - 1
    }

    if ($positionIndex -lt 0 -or $spec.Positionals.Count -eq 0) {
        return @()
    }

    $valueKind = $spec.Positionals[$positionIndex]
    Get-ScoopValueResults -ValueKind $valueKind -CurrentValue $State.CurrentToken -State $State
}

function Complete-ScoopNative {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $state = Get-ScoopCommandState -WordToComplete $WordToComplete -CommandAst $CommandAst -CursorPosition $CursorPosition

    if ($state.CurrentToken -match '^(?<option>--[A-Za-z0-9-]+)=(?<value>.*)$') {
        $inlineOption = Find-ScoopOptionSpec -PathKey $state.PathKey -Token $matches['option']
        if ($inlineOption -and $inlineOption.ValueKind) {
            return Get-ScoopValueResults -ValueKind $inlineOption.ValueKind -CurrentValue $matches['value'] -State $state -Prefix ($matches['option'] + '=')
        }
    }

    if ($state.PendingOption) {
        return Get-ScoopValueResults -ValueKind $state.PendingOption.ValueKind -CurrentValue $state.CurrentToken -State $state
    }

    if (-not $state.AfterDoubleDash -and $state.CurrentToken.StartsWith('-')) {
        return Write-ScoopOptionResults -PathKey $state.PathKey -CurrentToken $state.CurrentToken
    }

    Write-ScoopOperandResults -State $state
}

Register-ArgumentCompleter -Native -CommandName @('scoop', 'scoop.ps1', 'scoop.cmd') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-ScoopNative -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}

