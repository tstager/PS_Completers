# cargo native argument completer for PowerShell
# Help-driven completer for cargo root and subcommand switches with safe local discovery.

Set-StrictMode -Version 2.0

function Get-CargoCompletionCache {
    $cache = Get-Variable -Name CargoCompletionCache -Scope Script -ErrorAction Ignore
    if ($cache) {
        return $cache.Value
    }

    $newCache = @{
        Initialized         = $false
        CommandName         = $null
        CommandResolved     = $false
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
        Projects            = @{}
        Installed           = @{}
    }

    Set-Variable -Name CargoCompletionCache -Scope Script -Value $newCache
    $newCache
}

function Resolve-CargoCommandName {
    $cache = Get-CargoCompletionCache
    if ($cache.CommandResolved) {
        return $cache.CommandName
    }

    $command = Get-Command -Name cargo.exe, cargo -ErrorAction Ignore | Select-Object -First 1
    if ($command) {
        $cache.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $cache.CommandResolved = $true
    $cache.CommandName
}

function Invoke-CargoText {
    param([string[]]$Arguments)

    $commandName = Resolve-CargoCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @($null | & $commandName @Arguments 2>&1 | ForEach-Object { $_.ToString() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })
    } catch {
        @()
    }
}

function Invoke-CargoBoundedText {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    $commandName = Resolve-CargoCommandName
    if (-not $commandName) {
        return $null
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($commandName)
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    # A Tab must never install the toolchain a rust-toolchain.toml names or reach a registry.
    $startInfo.Environment['RUSTUP_AUTO_INSTALL'] = '0'
    $startInfo.Environment['CARGO_NET_OFFLINE'] = 'true'
    $startInfo.Environment['CARGO_TERM_COLOR'] = 'never'

    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(5000)) {
            $process.Kill($true)
            return $null
        }

        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            return $null
        }

        $stdout.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', ''
    } finally {
        $process.Dispose()
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

function ConvertFrom-CargoQuotedPath {
    param([string]$Value)

    # CompleteFilename already quotes paths it considers unsafe; undo that so the
    # path is quoted exactly once, with the quote character the user typed.
    if ($Value.Length -ge 2 -and $Value.StartsWith("'") -and $Value.EndsWith("'")) {
        return $Value.Substring(1, $Value.Length - 2).Replace("''", "'")
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return [regex]::Replace($Value.Substring(1, $Value.Length - 2), '`(.)', '$1')
    }

    $Value
}

function ConvertTo-CargoQuotedPath {
    param(
        [string]$Value,
        [string]$QuoteChar
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (-not $QuoteChar -and $Value -notmatch '[\s{}();,|&<>''"`$]|^[@#]') {
        return $Value
    }

    if ($QuoteChar -eq '"') {
        return '"' + $Value.Replace('`', '``').Replace('"', '`"').Replace('$', '`$') + '"'
    }

    "'" + $Value.Replace("'", "''") + "'"
}

function Get-CargoPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-CargoOuterQuotes -Value $InputPath
    $quoteChar = if (-not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))) { $InputPath.Substring(0, 1) } else { '' }

    [System.Management.Automation.CompletionCompleters]::CompleteFilename($cleanInput) |
        ForEach-Object {
            $completionText = ConvertTo-CargoQuotedPath -Value (ConvertFrom-CargoQuotedPath -Value $_.CompletionText) -QuoteChar $quoteChar
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
        '--config' = @('<KEY=VALUE>', '<path>')
        '--explain' = @('<error-code>')
        '-Z' = @()
    }
}

function Get-CargoCommonValueMap {
    @{
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
                '--registry' = @('<registry>')
            }
        }
        'init' {
            return @{
                '--name' = @('<package-name>')
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
                '--target' = @()
            }
        }
        default {
            return @{}
        }
    }
}

# Value sets for options whose help names the choices only in prose instead of a clap
# '[possible values: ...]' block (cargo-nextest's '--color', cargo-fmt's '--message-format').
# They fill in only where the live help lists no values, so a parsed list always wins.
function Get-CargoEnumFallbackMap {
    param([string]$CommandName)

    $fallbacks = @{ '--color' = @('auto', 'always', 'never') }
    if ($CommandName -eq 'fmt') {
        $fallbacks['--message-format'] = @('short', 'json', 'human')
    }

    $fallbacks
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

        $rustup = Get-Command -Name rustup.exe, rustup -ErrorAction Ignore | Select-Object -First 1
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
        $rustc = Get-Command -Name rustc.exe, rustc -ErrorAction Ignore | Select-Object -First 1
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

        $cache.UnstableFlags = @($flags | Sort-Object -Unique -CaseSensitive)
    }

    $cache.UnstableFlags
}

function Get-CargoOptionValue {
    param(
        [pscustomobject]$State,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if ($State.OptionValues.ContainsKey($name)) {
            return $State.OptionValues[$name]
        }
    }

    $null
}

function Resolve-CargoManifestPath {
    param([pscustomobject]$State)

    $location = (Get-Location -PSProvider FileSystem).ProviderPath
    if ($State.RootDirectory) {
        $location = [System.IO.Path]::GetFullPath($State.RootDirectory, $location)
    }

    $manifestPath = Get-CargoOptionValue -State $State -Names @('--manifest-path', '-m')
    if ($manifestPath) {
        $candidate = [System.IO.Path]::GetFullPath($manifestPath, $location)
        if ([System.IO.File]::Exists($candidate)) {
            return $candidate
        }

        return $null
    }

    # cargo itself walks up from the working directory to the nearest Cargo.toml.
    $directory = [System.IO.DirectoryInfo]::new($location)
    while ($directory) {
        $candidate = [System.IO.Path]::Combine($directory.FullName, 'Cargo.toml')
        if ([System.IO.File]::Exists($candidate)) {
            return $candidate
        }

        $directory = $directory.Parent
    }

    $null
}

function Get-CargoProjectInfo {
    param([pscustomobject]$State)

    $manifest = Resolve-CargoManifestPath -State $State
    if (-not $manifest) {
        return $null
    }

    # Keyed by manifest and its write time, with a short TTL so auto-discovered targets
    # (a new src/bin/*.rs) and lockfile changes are picked up without restarting the shell.
    $cache = Get-CargoCompletionCache
    $key = '{0}|{1}' -f $manifest, [System.IO.File]::GetLastWriteTimeUtc($manifest).Ticks
    $entry = $cache.Projects[$manifest]
    if ($entry -and $entry.Key -eq $key -and $entry.Expires -gt [datetime]::UtcNow) {
        return $entry.Info
    }

    $info = $null
    $json = Invoke-CargoBoundedText -WorkingDirectory ([System.IO.Path]::GetDirectoryName($manifest)) -Arguments @(
        'metadata', '--no-deps', '--format-version', '1', '--offline', '--manifest-path', $manifest
    )

    if ($json -and $json.TrimStart().StartsWith('{')) {
        $metadata = $json | ConvertFrom-Json
        $packages = foreach ($package in @($metadata.packages)) {
            [pscustomobject]@{
                Name         = $package.name
                ManifestPath = $package.manifest_path
                Features     = @($package.features.PSObject.Properties | ForEach-Object { $_.Name })
                Targets      = @($package.targets | ForEach-Object { [pscustomobject]@{ Name = $_.name; Kinds = @($_.kind) } })
                Dependencies = @($package.dependencies | ForEach-Object { if ($_.rename) { $_.rename } else { $_.name } })
            }
        }

        $rootManifest = [System.IO.Path]::Combine($metadata.workspace_root, 'Cargo.toml')
        $profiles = @()
        if ([System.IO.File]::Exists($rootManifest)) {
            $profiles = @([regex]::Matches([System.IO.File]::ReadAllText($rootManifest), '(?m)^\s*\[profile\.(?:"([^"]+)"|([A-Za-z0-9_-]+))\s*\]') |
                ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } })
        }

        $lockFile = [System.IO.Path]::Combine($metadata.workspace_root, 'Cargo.lock')
        $lockNames = @()
        if ([System.IO.File]::Exists($lockFile)) {
            $lockNames = @([regex]::Matches([System.IO.File]::ReadAllText($lockFile), '(?m)^name = "([^"]+)"') |
                ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique -CaseSensitive)
        }

        $info = [pscustomobject]@{
            Manifest  = $manifest
            Packages  = @($packages)
            Profiles  = $profiles
            LockNames = $lockNames
        }
    }

    # A failed or missing source is cached too, so a broken manifest is not re-run on every Tab.
    $cache.Projects[$manifest] = @{
        Key     = $key
        Expires = [datetime]::UtcNow.AddSeconds(30)
        Info    = $info
    }

    $info
}

function Get-CargoSelectedPackage {
    param(
        [pscustomobject]$Info,
        [pscustomobject]$State
    )

    $spec = Get-CargoOptionValue -State $State -Names @('-p', '--package')
    if ($spec) {
        $name = ($spec -split '@')[0]
        $picked = @($Info.Packages | Where-Object { $_.Name -ceq $name })
        if ($picked.Count -gt 0) {
            return $picked
        }
    }

    $own = @($Info.Packages | Where-Object { $_.ManifestPath -eq $Info.Manifest })
    if ($own.Count -gt 0) {
        return $own
    }

    # A virtual workspace root selects every member.
    @($Info.Packages)
}

function Get-CargoInstalledCrate {
    param([pscustomobject]$State)

    $root = Get-CargoOptionValue -State $State -Names @('--root')
    if (-not $root) {
        $root = if ($env:CARGO_INSTALL_ROOT) { $env:CARGO_INSTALL_ROOT } elseif ($env:CARGO_HOME) { $env:CARGO_HOME } else { [System.IO.Path]::Combine($HOME, '.cargo') }
    }

    $location = (Get-Location -PSProvider FileSystem).ProviderPath
    $registry = [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($root, $location), '.crates2.json')
    if (-not [System.IO.File]::Exists($registry)) {
        return $null
    }

    $cache = Get-CargoCompletionCache
    $key = '{0}|{1}' -f $registry, [System.IO.File]::GetLastWriteTimeUtc($registry).Ticks
    $entry = $cache.Installed[$registry]
    if ($entry -and $entry.Key -eq $key) {
        return $entry.Info
    }

    $info = $null
    $text = [System.IO.File]::ReadAllText($registry)
    if ($text.TrimStart().StartsWith('{')) {
        # Keys read 'name version (source)'; bins carry the platform suffix that --bin does not need.
        $installs = @(($text | ConvertFrom-Json).installs.PSObject.Properties)
        $info = [pscustomobject]@{
            Names = @($installs | ForEach-Object { ($_.Name -split ' ')[0] } | Sort-Object -Unique -CaseSensitive)
            Bins  = @($installs | ForEach-Object { $_.Value.bins } | ForEach-Object { $_ -replace '\.exe$', '' } | Sort-Object -Unique -CaseSensitive)
        }
    }

    $cache.Installed[$registry] = @{
        Key  = $key
        Info = $info
    }

    $info
}

function Get-CargoLiveValue {
    param(
        [string]$OptionName,
        [pscustomobject]$State
    )

    # Returns @{ Candidates; ToolTip } from the project underfoot or the install registry, or nothing
    # when there is no live source so the static hint stands.
    $commandName = $State.CommandName

    if ($commandName -eq 'uninstall') {
        $installed = Get-CargoInstalledCrate -State $State
        if (-not $installed) {
            return
        }

        switch -CaseSensitive ($OptionName) {
            { $_ -cin '<operand>', '-p', '--package' } { return @{ Candidates = $installed.Names; ToolTip = 'Installed crate.' } }
            '--bin' { return @{ Candidates = $installed.Bins; ToolTip = 'Installed binary.' } }
        }

        return
    }

    $builtInProfiles = @('dev', 'release', 'test', 'bench')
    if ($commandName -eq 'install') {
        if ($OptionName -ceq '--profile') {
            return @{ Candidates = $builtInProfiles; ToolTip = 'Cargo profile.' }
        }

        return
    }

    if ($commandName -eq 'add' -and $OptionName -cin @('-F', '--features')) {
        return
    }

    if ($OptionName -cnotin @('--profile', '-F', '--features', '-p', '--package', '--exclude', '--bin', '--example', '--test', '--bench', '<operand>')) {
        return
    }

    $info = Get-CargoProjectInfo -State $State
    if ($OptionName -ceq '--profile') {
        $profiles = $builtInProfiles
        if ($info) {
            $profiles = @($builtInProfiles + @($info.Profiles | Where-Object { $_ -cnotin $builtInProfiles }))
        }

        return @{ Candidates = $profiles; ToolTip = 'Cargo profile.' }
    }

    if (-not $info) {
        return
    }

    $targetKinds = @{ '--bin' = 'bin'; '--example' = 'example'; '--test' = 'test'; '--bench' = 'bench' }
    switch -CaseSensitive ($OptionName) {
        { $_ -cin '-F', '--features' } {
            $selected = @(Get-CargoSelectedPackage -Info $info -State $State)
            return @{ Candidates = @($selected | ForEach-Object { $_.Features } | Sort-Object -Unique -CaseSensitive); ToolTip = 'Package feature.' }
        }
        { $_ -cin '-p', '--package', '--exclude' } {
            return @{ Candidates = @($info.Packages | ForEach-Object { $_.Name } | Sort-Object -Unique -CaseSensitive); ToolTip = 'Workspace member.' }
        }
        { $targetKinds.ContainsKey($_) } {
            $kind = $targetKinds[$OptionName]
            $selected = @(Get-CargoSelectedPackage -Info $info -State $State)
            $names = @($selected | ForEach-Object { $_.Targets } | Where-Object { $_.Kinds -ccontains $kind } | ForEach-Object { $_.Name } | Sort-Object -Unique -CaseSensitive)
            return @{ Candidates = $names; ToolTip = "$kind target." }
        }
        '<operand>' {
            if ($commandName -eq 'remove') {
                $selected = @(Get-CargoSelectedPackage -Info $info -State $State)
                return @{ Candidates = @($selected | ForEach-Object { $_.Dependencies } | Sort-Object -Unique -CaseSensitive); ToolTip = 'Dependency.' }
            }

            if ($commandName -eq 'update') {
                if ($info.LockNames.Count -gt 0) {
                    return @{ Candidates = $info.LockNames; ToolTip = 'Locked package.' }
                }

                return @{ Candidates = @(@($info.Packages | ForEach-Object { $_.Name; $_.Dependencies }) | Sort-Object -Unique -CaseSensitive); ToolTip = 'Package.' }
            }
        }
    }
}

function Get-CargoLiveValueCompletion {
    param(
        [string]$OptionName,
        [string]$CurrentWord,
        [hashtable]$Live
    )

    $current = Remove-CargoOuterQuotes -Value $CurrentWord
    if ($OptionName -cin @('-F', '--features')) {
        # PowerShell splits 'a,b' itself and replaces only the segment after the last comma.
        $current = ($current -split ',')[-1]
    }

    foreach ($value in $Live.Candidates) {
        if ($value.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-CargoCompletionResult -CompletionText $value -ListItemText $value -ResultType 'ParameterValue' -ToolTip $Live.ToolTip
        }
    }
}

function Get-CargoCommandNamesFromList {
    $lines = Invoke-CargoText -Arguments @('--list')
    $commands = foreach ($line in $lines) {
        # Third-party subcommands such as binstall and miri print no description at all.
        if ($line -match '^\s{4}([A-Za-z0-9][A-Za-z0-9\-_]*)(\s{2,}.*)?$') {
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

function Get-CargoOptionSpecsFromHelp {
    param([string[]]$Lines)

    # clap indents every option line by 2-7 spaces and wraps descriptions further in, so the flag
    # segment is whatever precedes the first run of two spaces on such a line. Both layouts cargo
    # emits are covered: '  -F, --features <FEATURES>  Desc' and '      --public' with the
    # description on the following line. Description lines indented past the flag column belong to
    # the option above them; clap wraps '[possible values: a, b,' across them, and in the long
    # layout a blank line separates the list from the description.
    $blocks = New-Object System.Collections.Generic.List[object]
    $block = $null
    foreach ($line in @($Lines)) {
        if ($line -match '^ {2,7}-\S') {
            $block = [pscustomobject]@{
                Line = $line
                Text = [System.Text.StringBuilder]::new($line.Trim())
            }
            [void]$blocks.Add($block)
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($block -and $line -match '^ {8,}\S') {
            [void]$block.Text.Append(' ').Append($line.Trim())
            continue
        }

        $block = $null
    }

    $specs = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($block in $blocks) {
        $segment = (($block.Line.Trim() -split '\s{2,}')[0])
        $metaVar = if ($segment -match '\[?<[^>]+>\]?') { $matches[0] } else { '' }
        $values = @()
        if ($metaVar -and $block.Text.ToString() -match '\[possible values:\s*([^\]]*)\]') {
            $values = @($matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        foreach ($match in [regex]::Matches($segment, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)')) {
            $token = $match.Groups[1].Value
            if (-not $seen.Add($token)) {
                continue
            }

            [void]$specs.Add([pscustomobject]@{
                    Token   = $token
                    MetaVar = $metaVar
                    Values  = $values
                })
        }
    }

    @($specs.ToArray())
}

function Get-CargoValueHintTable {
    param(
        [object[]]$Specs,
        [hashtable]$Fallbacks = @{},
        [hashtable[]]$Overlays
    )

    $hints = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)

    foreach ($spec in @($Specs)) {
        if (-not $spec.MetaVar) {
            continue
        }

        if ($spec.Values.Count -gt 0) {
            $hints[$spec.Token] = @($spec.Values)
            continue
        }

        if ($Fallbacks.ContainsKey($spec.Token)) {
            $hints[$spec.Token] = @($Fallbacks[$spec.Token])
            continue
        }

        $name = $spec.MetaVar.Trim([char[]]@('[', ']', '<', '>')).ToLowerInvariant()
        $hints[$spec.Token] = @("<$name>")
    }

    # Only options that help says carry a value get a curated hint, so a bare flag can never
    # swallow the following token. Enumerated values come from clap's own list above.
    foreach ($overlay in @($Overlays)) {
        foreach ($key in $overlay.Keys) {
            if ($hints.ContainsKey($key)) {
                $hints[$key] = @($overlay[$key])
            }
        }
    }

    $hints
}

function Initialize-CargoCompletionCache {
    $cache = Get-CargoCompletionCache
    if ($cache.Initialized) {
        return
    }

    $cache.RootValueMap = Get-CargoRootValueMap
    $cache.CommonValueMap = Get-CargoCommonValueMap

    $rootHelp = Invoke-CargoText -Arguments @('--help')
    $rootSpecs = @(Get-CargoOptionSpecsFromHelp -Lines $rootHelp)
    $cache.RootOptions = @($rootSpecs | ForEach-Object { $_.Token })
    $cache.RootCommands = @(
        Get-CargoRootCommandsFromHelp
        Get-CargoCommandNamesFromList
        'help'
    ) | Sort-Object -Unique

    $cache.CommandMetadata['<root>'] = [pscustomobject]@{
        Options    = @($cache.RootOptions)
        ValueHints = Get-CargoValueHintTable -Specs $rootSpecs -Fallbacks (Get-CargoEnumFallbackMap) -Overlays @($cache.RootValueMap)
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

    # clap's own '<sub> --help' carries both option forms plus the metavar that says whether the
    # option takes a value; 'cargo help <sub>' is a man page that drops the long form of every pair.
    $helpLines = Invoke-CargoText -Arguments @($CommandName, '--help')

    # A subcommand whose help fails (an uninstalled third-party one, for example) yields no specs,
    # and the empty result has to stay an array or it reads back as a single $null element.
    $specs = @(Get-CargoOptionSpecsFromHelp -Lines $helpLines)
    $options = @($specs | ForEach-Object { $_.Token })

    $valueHints = Get-CargoValueHintTable -Specs $specs -Fallbacks (Get-CargoEnumFallbackMap -CommandName $CommandName) -Overlays @(
        $cache.CommonValueMap
        (Get-CargoCommandValueHints -CommandName $CommandName)
    )

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
    $rootDirectory = $null

    for ($i = 0; $i -lt $TokensBeforeCurrent.Count; $i++) {
        $token = Remove-CargoOuterQuotes -Value $TokensBeforeCurrent[$i]
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        if ($pendingOption) {
            if (-not $commandName) {
                if ($pendingOption -ceq '-C') {
                    $rootDirectory = $token
                }

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
                # Hand '--' to the subcommand loop so it can stop treating cargo switches as
                # arguments of the program cargo is about to run.
                $commandTokens.Add($token)
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

            if ($token -cmatch '^-C(.+)$') {
                $rootDirectory = $matches[1]
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
    $optionValues = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $afterDoubleDash = $false

    foreach ($token in $commandTokens) {
        if ($commandPendingOption) {
            $positionals.Add($token)
            $optionValues[$commandPendingOption] = $token
            $commandPendingOption = $null
            continue
        }

        if ($token -eq '--') {
            $afterDoubleDash = $true
            continue
        }

        # '--opt=value' and '-Xvalue' carry their value in the same word, so neither is an operand.
        $attached = if ($afterDoubleDash) { $null } else { Split-CargoAttachedValue -Word $token -Metadata $commandMetadata }
        if ($attached) {
            $optionValues[$attached.Option] = $attached.Value
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
        OptionValues        = $optionValues
        RootDirectory       = $rootDirectory
    }
}

function Test-CargoValueOption {
    param(
        [pscustomobject]$Metadata,
        [string]$Option
    )

    $Metadata.Options -ccontains $Option -and ($Metadata.ValueHints.ContainsKey($Option) -or $Metadata.PathOptions -ccontains $Option)
}

function Split-CargoAttachedValue {
    param(
        [string]$Word,
        [pscustomobject]$Metadata
    )

    # clap accepts '--opt=value' for every value-bearing long option and '-Xvalue' for every
    # value-bearing short one ('cargo -Zbindeps', 'cargo build -prelease-crate').
    if ($Word -cmatch '^(--[A-Za-z0-9][A-Za-z0-9-]*)=(.*)$') {
        $option = $matches[1]
        $value = $matches[2]
        $prefix = "$option="
    }
    elseif ($Word -cmatch '^(-[A-Za-z0-9])(.+)$') {
        $option = $matches[1]
        $value = $matches[2]
        $prefix = $option
    }
    else {
        return $null
    }

    if (-not (Test-CargoValueOption -Metadata $Metadata -Option $option)) {
        return $null
    }

    [pscustomobject]@{
        Option = $option
        Value  = $value
        Prefix = $prefix
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

    $live = Get-CargoLiveValue -OptionName $OptionName -State $State
    if ($live -and @($live.Candidates).Count -gt 0) {
        return @(Get-CargoLiveValueCompletion -OptionName $OptionName -CurrentWord $CurrentWord -Live $live)
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

    # cargo's short flags are case-significant (-V is --version, -v is --verbose), so both the
    # de-duplication and the prefix test have to stay ordinal for single-dash words.
    $comparison = if ($current -match '^-[^-]') {
        [System.StringComparison]::Ordinal
    } else {
        [System.StringComparison]::OrdinalIgnoreCase
    }

    foreach ($option in $Options | Sort-Object -Unique -CaseSensitive) {
        if ($option.StartsWith($current, $comparison)) {
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
        Get-CargoCurrentWord -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $state = Get-CargoState -TokensBeforeCurrent @(Get-CargoArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition)

    if (-not $state.PendingGlobalOption -and -not $state.PendingOption -and -not $state.AfterDoubleDash) {
        $attached = Split-CargoAttachedValue -Word $currentWord -Metadata $state.CommandMetadata
        if ($attached) {
            # After a comma PowerShell replaces only the last list segment, so the prefix stays put.
            $prefix = if ($attached.Value.Contains(',')) { '' } else { $attached.Prefix }
            return @(
                Get-CargoValueCompletions -OptionName $attached.Option -CurrentWord $attached.Value -State $state |
                    ForEach-Object {
                        New-CargoCompletionResult -CompletionText ($prefix + $_.CompletionText) -ListItemText $_.ListItemText -ResultType $_.ResultType -ToolTip $_.ToolTip
                    }
            )
        }
    }

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
        { $_ -in 'remove', 'update', 'uninstall' } {
            $live = Get-CargoLiveValue -OptionName '<operand>' -State $state
            if ($live -and @($live.Candidates).Count -gt 0) {
                return @($optionResults + @(Get-CargoLiveValueCompletion -OptionName '<operand>' -CurrentWord $currentWord -Live $live))
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
