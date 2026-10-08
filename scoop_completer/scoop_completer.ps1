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
        # libexec/scoop-download.ps1: getopt $args 'fsua:' 'force', 'skip-hash-check', 'no-update-scoop', 'arch='
        $downloadOptions = @(
            New-ScoopOptionSpec -Tokens @('-f', '--force') -Description 'Force download even when the file already exists in the cache.'
            New-ScoopOptionSpec -Tokens @('-s', '--skip-hash-check') -Description 'Skip hash verification.'
            New-ScoopOptionSpec -Tokens @('-u', '--no-update-scoop') -Description 'Do not update Scoop before downloading.'
            New-ScoopOptionSpec -Tokens @('-a', '--arch') -Description 'Use the specified architecture.' -ValueKind 'Arch'
        )
        $helpOptions = @(
            New-ScoopOptionSpec -Tokens @('-h', '--help', '/?') -Description 'Show help for this command.'
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
            ) -Options @(
                $helpOptions
                New-ScoopOptionSpec -Tokens @('-v', '--version') -Description 'Show the Scoop version.'
            ) -Positionals @()
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
            New-ScoopCommandSpec -Path 'depends' -Description 'List app dependencies.' -Subcommands @() -Options @(
                New-ScoopOptionSpec -Tokens @('-a', '--arch') -Description 'Use the specified architecture.' -ValueKind 'Arch'
            ) -Positionals @('ManifestApp')
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
            New-ScoopCommandSpec -Path 'reset' -Description 'Reset an app or switch active version.' -Subcommands @() -Options @(
                New-ScoopOptionSpec -Tokens @('-a', '--all') -Description 'Reset all apps.'
            ) -Positionals @('InstalledAppOrAll')
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
            # bin/scoop.ps1 routes -h/--help//? as the first argument of every subcommand to 'help'.
            if ($spec.Path -ne '') {
                $spec.Options = @($spec.Options) + $helpOptions
            }

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
            ScoopConfig            = $null
            ScoopConfigLoadedAt    = [datetime]::MinValue
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
        $command = Get-Command -Name $name -ErrorAction Ignore | Select-Object -First 1
        if ($command) {
            $cache.ExecutablePath = if ($command.Source) { $command.Source } else { $command.Name }
            break
        }
    }

    $cache.ExecutablePath
}

function Get-ScoopInstallRoot {
    # The root scoop itself runs from (<root>\shims\scoop.*), like lib/core.ps1's "$PSScriptRoot\..\..\..\..".
    $commandName = Resolve-ScoopCommandName
    if (-not [string]::IsNullOrWhiteSpace($commandName)) {
        $shimDirectory = Split-Path -Path $commandName -Parent
        if (-not [string]::IsNullOrWhiteSpace($shimDirectory) -and (Split-Path -Path $shimDirectory -Leaf) -ieq 'shims') {
            return Split-Path -Path $shimDirectory -Parent
        }
    }

    $null
}

function Get-ScoopRootPath {
    # Same precedence as lib/core.ps1's $scoopdir: $env:SCOOP, root_path, the install root, then ~\scoop.
    @(
        $env:SCOOP
        Get-ScoopConfigText -Name 'root_path'
        Get-ScoopInstallRoot
        Join-Path -Path ([System.Environment]::GetFolderPath('UserProfile')) -ChildPath 'scoop'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
}

function Remove-ScoopOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
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

function Get-ScoopConfig {
    # Scoop's own config.json, read for directory overrides and alias names only (never values).
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.ScoopConfigLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.ScoopConfig
    }

    # Same lookup as lib/core.ps1: the portable <install root>\config.json wins over the per-user file.
    $configHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path -Path ([System.Environment]::GetFolderPath('UserProfile')) -ChildPath '.config' }
    $configPath = Join-Path -Path $configHome -ChildPath 'scoop\config.json'
    $installRoot = Get-ScoopInstallRoot
    if ($installRoot -and (Test-Path -LiteralPath (Join-Path -Path $installRoot -ChildPath 'config.json') -PathType Leaf)) {
        $configPath = Join-Path -Path $installRoot -ChildPath 'config.json'
    }

    $cache.ScoopConfig = $null
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        try {
            $cache.ScoopConfig = [System.IO.File]::ReadAllText($configPath) | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Debug "scoop config '$configPath' could not be read: $($_.Exception.Message)"
        }
    }

    $cache.ScoopConfigLoadedAt = Get-Date
    $cache.ScoopConfig
}

function Get-ScoopConfigText {
    param([string]$Name)

    $config = Get-ScoopConfig
    if ($null -eq $config) {
        return $null
    }

    $property = $config.PSObject.Properties[$Name]
    if ($property -and $property.Value -is [string] -and -not [string]::IsNullOrWhiteSpace($property.Value)) {
        return $property.Value
    }

    $null
}

function Get-ScoopBaseDirectory {
    # The user root plus the global root, resolved like lib/core.ps1's $scoopdir and $globaldir.
    $globalPath = @(
        $env:SCOOP_GLOBAL
        Get-ScoopConfigText -Name 'global_path'
        Join-Path -Path ([System.Environment]::GetFolderPath('CommonApplicationData')) -ChildPath 'scoop'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1

    @((Get-ScoopRootPath), $globalPath)
}

function Get-ScoopInstalledApps {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.InstalledAppsLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.InstalledApps
    }

    # Mirrors 'scoop list' (installed_apps for user then global), which skips scoop itself.
    $names = foreach ($baseDirectory in @(Get-ScoopBaseDirectory)) {
        foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path -Path $baseDirectory -ChildPath 'apps') -Directory -ErrorAction Ignore)) {
            if ($directory.Name -ne 'scoop') {
                $directory.Name
            }
        }
    }

    $cache.InstalledApps = Get-ScoopUniqueStrings -Items $names
    $cache.InstalledAppsLoadedAt = Get-Date
    $cache.InstalledApps
}

function Get-ScoopKnownBuckets {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.KnownBucketsLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.KnownBuckets
    }

    # 'scoop bucket known' prints the property names of the buckets.json shipped with scoop itself, in file order.
    $installRoot = Get-ScoopInstallRoot
    if (-not $installRoot) {
        $installRoot = Get-ScoopRootPath
    }
    $bucketsFile = Join-Path -Path $installRoot -ChildPath 'apps\scoop\current\buckets.json'
    $names = @()
    if (Test-Path -LiteralPath $bucketsFile -PathType Leaf) {
        try {
            $knownRepos = [System.IO.File]::ReadAllText($bucketsFile) | ConvertFrom-Json -ErrorAction Stop
            $names = @($knownRepos.PSObject.Properties | ForEach-Object { $_.Name })
        } catch {
            Write-Debug "scoop buckets.json '$bucketsFile' could not be read: $($_.Exception.Message)"
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

    # Mirrors Get-LocalBucket: the bucket directories, known buckets first in buckets.json order.
    $bucketsDirectory = Join-Path -Path (Get-ScoopRootPath) -ChildPath 'buckets'
    $local = @(Get-ChildItem -LiteralPath $bucketsDirectory -Directory -ErrorAction Ignore | ForEach-Object { $_.Name })
    $known = @(Get-ScoopKnownBuckets | Where-Object { $local -contains $_ })

    $cache.CurrentBuckets = Get-ScoopUniqueStrings -Items ($known + $local)
    $cache.CurrentBucketsLoadedAt = Get-Date
    $cache.CurrentBuckets
}

function Get-ScoopShimNames {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.ShimNamesLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.ShimNames
    }

    # Mirrors 'scoop shim list': *.shim and *.ps1 base names under the user and global shims directories.
    $names = foreach ($baseDirectory in @(Get-ScoopBaseDirectory)) {
        Get-ChildItem -LiteralPath (Join-Path -Path $baseDirectory -ChildPath 'shims') -Recurse -File -Include '*.shim', '*.ps1' -ErrorAction Ignore |
            ForEach-Object { $_.BaseName }
    }

    $cache.ShimNames = Get-ScoopUniqueStrings -Items $names
    $cache.ShimNamesLoadedAt = Get-Date
    $cache.ShimNames
}

function Get-ScoopAliasNames {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.AliasNamesLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.AliasNames
    }

    # 'scoop alias list' prints the names of the config 'alias' object, sorted; any other JSON value has no aliases.
    $names = @()
    $config = Get-ScoopConfig
    if ($null -ne $config -and $config.PSObject.Properties['alias'] -and $config.alias -is [System.Management.Automation.PSCustomObject]) {
        $names = @($config.alias.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
    }

    $cache.AliasNames = Get-ScoopUniqueStrings -Items $names
    $cache.AliasNamesLoadedAt = Get-Date
    $cache.AliasNames
}

function Get-ScoopCacheAppNames {
    $cache = Get-ScoopCompletionCache
    if (Test-ScoopCacheFresh -LoadedAt $cache.CacheAppNamesLoadedAt -TtlSeconds $cache.RuntimeCacheTtlSeconds) {
        return $cache.CacheAppNames
    }

    # Mirrors 'scoop cache show': '<app>#<version>#<hash>' files in $SCOOP_CACHE, cache_path or <root>\cache.
    $cacheDirectory = @(
        $env:SCOOP_CACHE
        Get-ScoopConfigText -Name 'cache_path'
        Join-Path -Path (Get-ScoopRootPath) -ChildPath 'cache'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1

    $names = Get-ScoopUniqueStrings -Items @(
        Get-ChildItem -LiteralPath $cacheDirectory -File -Filter '*#*' -ErrorAction Ignore |
            ForEach-Object { $_.Name.Substring(0, $_.Name.IndexOf('#')) }
    )
    if (@($names).Count -eq 0) {
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
    $names = Get-ChildItem -Path $bucketPattern -ErrorAction Ignore |
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

        if (($token.StartsWith('-') -and $token -ne '-') -or $token -eq '/?') {
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

function Get-ScoopAppVersionList {
    # Versions available for app@version: the installed version directories plus the manifest version.
    param([string]$AppName)

    $name = $AppName
    if ($name.Contains('/')) {
        $name = $name.Substring($name.LastIndexOf('/') + 1)
    }

    if ([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\*?\[\]]') {
        return @()
    }

    $rootPath = Get-ScoopRootPath
    $versions = New-Object System.Collections.Generic.List[string]

    $appDirectory = Join-Path -Path $rootPath -ChildPath ('apps\' + $name)
    foreach ($directory in @(Get-ChildItem -LiteralPath $appDirectory -Directory -ErrorAction Ignore)) {
        if ($directory.Name -ne 'current') {
            [void]$versions.Add($directory.Name)
        }
    }

    foreach ($manifest in @(Get-ChildItem -Path (Join-Path -Path $rootPath -ChildPath ('buckets\*\bucket\' + $name + '.json')) -ErrorAction Ignore)) {
        try {
            $manifestObject = Get-Content -LiteralPath $manifest.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($manifestObject.PSObject.Properties['version'] -and $manifestObject.version) {
                [void]$versions.Add([string]$manifestObject.version)
            }
        } catch {
            Write-Debug "scoop manifest '$($manifest.FullName)' could not be read: $($_.Exception.Message)"
        }
    }

    Get-ScoopUniqueStrings -Items @($versions.ToArray())
}

function Get-ScoopAppAtVersionResult {
    # Completes the '<app>@<version>' form: the base name is kept and the app's versions are offered.
    param(
        [string]$CurrentValue,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $value = Remove-ScoopOuterQuotes -Value $CurrentValue
    if ($value -notmatch '^(?<base>[^@]+)@(?<suffix>[^@]*)$') {
        return @()
    }

    $base = $matches['base']
    $suffix = $matches['suffix']
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($version in @(Get-ScoopAppVersionList -AppName $base)) {
        if ($version.StartsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-ScoopCompletionResult -CompletionText ($Prefix + $base + '@' + $version) -ToolTip ('Version ' + $version + ' of ' + $base + '.') -ListItemText ($base + '@' + $version)))
        }
    }

    if ($results.Count -eq 0) {
        [void]$results.Add((New-ScoopCompletionResult -CompletionText ($Prefix + $base + '@' + '<version>') -ToolTip $ToolTip -ListItemText ($base + '@<version>')))
    }

    @(Get-ScoopDistinctResults -Results @($results.ToArray()))
}

function Get-ScoopBucketScopedManifestNameList {
    # '<bucket>/<app>' scopes the manifest scan to that bucket and keeps the prefix on every result.
    param([string]$CurrentValue)

    $value = Remove-ScoopOuterQuotes -Value $CurrentValue
    if ($value -notmatch '^(?<bucket>[A-Za-z0-9._-]+)/(?<app>[^/@]*)$') {
        return @()
    }

    $bucket = $matches['bucket']
    $rootPath = Get-ScoopRootPath
    $bucketPattern = Join-Path -Path $rootPath -ChildPath ('buckets\' + $bucket + '\bucket\*.json')
    $names = @(Get-ChildItem -Path $bucketPattern -ErrorAction Ignore | ForEach-Object { $bucket + '/' + [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })
    Get-ScoopUniqueStrings -Items $names
}

function Get-ScoopAppNameResult {
    # Shared app-name slot: handles '<app>@<version>' and '<bucket>/<app>' before plain name matching.
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [switch]$SuggestWhenEmpty,
        [string]$Prefix = ''
    )

    $value = Remove-ScoopOuterQuotes -Value $CurrentValue
    if ($value -match '^[^@]+@[^@]*$') {
        return Get-ScoopAppAtVersionResult -CurrentValue $CurrentValue -ToolTip $ToolTip -Prefix $Prefix
    }

    if ($value -match '^[A-Za-z0-9._-]+/') {
        return Get-ScoopStringValueResults -Values (Get-ScoopBucketScopedManifestNameList -CurrentValue $CurrentValue) -CurrentValue $CurrentValue -Placeholder $null -ToolTip $ToolTip -Prefix $Prefix
    }

    Get-ScoopStringValueResults -Values $Values -CurrentValue $CurrentValue -Placeholder $Placeholder -ToolTip $ToolTip -SuggestWhenEmpty:$SuggestWhenEmpty -Prefix $Prefix
}

function Get-ScoopInstallTargetResults {
    param([string]$CurrentValue)

    $value = Remove-ScoopOuterQuotes -Value $CurrentValue
    # Empty word: the placeholder plus the first 200 local manifests (install skips installed apps); all of them once typed.
    if ([string]::IsNullOrWhiteSpace($value)) {
        return Get-ScoopStringValueResults -Values @(Get-ScoopManifestAppNames | Select-Object -First 200) -CurrentValue $CurrentValue -Placeholder '<app-or-manifest>' -ToolTip 'Scoop app name, local manifest path, or manifest URL.' -SuggestWhenEmpty
    }

    if ($value -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
        return New-ScoopLiteralValueResults -CurrentValue $CurrentValue -Placeholder '<manifest-url>' -ToolTip 'Manifest URL.'
    }

    if ($value -match '^(?<base>.+)@(?<suffix>[^@]*)$' -and (Test-ScoopPathLikeInput -Value $matches['base'])) {
        $base = $matches['base']
        $suffix = $matches['suffix']
        $results = foreach ($result in @(Get-ScoopPathCompletions -InputPath $base)) {
            $updatedValue = ConvertTo-ScoopQuotedValue -Value ((Remove-ScoopOuterQuotes -Value $result.CompletionText) + '@' + $suffix) -AlwaysQuote ($result.CompletionText.StartsWith('"') -and $result.CompletionText.EndsWith('"'))
            New-ScoopCompletionResult -CompletionText $updatedValue -ToolTip $result.ToolTip -ListItemText ($result.ListItemText + '@' + $suffix)
        }
        return @(Get-ScoopDistinctResults -Results $results)
    }

    if (Test-ScoopPathLikeInput -Value $value) {
        return Get-ScoopPathCompletions -InputPath $CurrentValue
    }

    Get-ScoopAppNameResult -Values (Get-ScoopManifestAppNames) -CurrentValue $CurrentValue -Placeholder '<app-or-manifest>' -ToolTip 'Locally available manifest name.'
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
        'InstalledApp' { return Get-ScoopAppNameResult -Values (Get-ScoopInstalledApps) -CurrentValue $CurrentValue -Placeholder '<app>' -ToolTip 'Installed Scoop app.' -SuggestWhenEmpty -Prefix $Prefix }
        'InstalledAppQuery' { return Get-ScoopStringValueResults -Values (Get-ScoopInstalledApps) -CurrentValue $CurrentValue -Placeholder '<query>' -ToolTip 'Installed app query.' -SuggestWhenEmpty -Prefix $Prefix }
        'InstalledAppOrAll' {
            return Get-ScoopAppNameResult -Values (@('*') + (Get-ScoopInstalledApps)) -CurrentValue $CurrentValue -Placeholder '<app>' -ToolTip 'Installed Scoop app or *.' -SuggestWhenEmpty -Prefix $Prefix
        }
        'ManifestApp' {
            # Empty word: the (small) installed list; once typed: installed plus every local manifest.
            if ([string]::IsNullOrWhiteSpace((Remove-ScoopOuterQuotes -Value $CurrentValue))) {
                return Get-ScoopStringValueResults -Values (Get-ScoopInstalledApps) -CurrentValue $CurrentValue -Placeholder '<app>' -ToolTip 'Scoop app name.' -SuggestWhenEmpty -Prefix $Prefix
            }

            $combined = Get-ScoopUniqueStrings -Items ((Get-ScoopInstalledApps) + (Get-ScoopManifestAppNames))
            return Get-ScoopAppNameResult -Values $combined -CurrentValue $CurrentValue -Placeholder '<app>' -ToolTip 'Scoop app name.' -Prefix $Prefix
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

    # scoop's getopt rejects '--arch=64bit'; only the space-separated form is completed.
    if ($state.PendingOption) {
        return Get-ScoopValueResults -ValueKind $state.PendingOption.ValueKind -CurrentValue $state.CurrentToken -State $state
    }

    if (-not $state.AfterDoubleDash -and ($state.CurrentToken.StartsWith('-') -or $state.CurrentToken.StartsWith('/'))) {
        return Write-ScoopOptionResults -PathKey $state.PathKey -CurrentToken $state.CurrentToken
    }

    Write-ScoopOperandResults -State $state
}

Register-ArgumentCompleter -Native -CommandName @('scoop', 'scoop.ps1', 'scoop.cmd') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-ScoopNative -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}

