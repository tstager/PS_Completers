Set-StrictMode -Version Latest

function Get-NpmCompletionCache {
    if (-not (Get-Variable -Name NpmCompletionCache -Scope Script -ErrorAction SilentlyContinue)) {
        $script:NpmCompletionCache = @{
                ExecutablePath          = $null
                ExecutablePathProbed    = $false
                HelpDataByPath          = @{}
                DiscoveredCommandAliasesByPath = @{}
                PackageJsonByPath       = @{}
                WorkspaceNamesByRoot    = @{}
                NodeModulesByRoot       = @{}
                ConfigKeys              = @()
                ConfigKeysLoaded        = $false
                StaticTree              = @{
                    ''            = @(
                        'access', 'adduser', 'audit', 'bugs', 'cache', 'ci', 'completion', 'config', 'dedupe', 'deprecate',
                        'diff', 'dist-tag', 'docs', 'doctor', 'edit', 'exec', 'explain', 'explore', 'find-dupes', 'fund',
                        'get', 'help', 'help-search', 'init', 'install', 'install-ci-test', 'install-test', 'link', 'll',
                        'login', 'logout', 'ls', 'org', 'outdated', 'owner', 'pack', 'ping', 'pkg', 'prefix', 'profile',
                        'prune', 'publish', 'query', 'rebuild', 'repo', 'restart', 'root', 'run', 'sbom', 'search', 'set',
                        'shrinkwrap', 'star', 'stars', 'start', 'stop', 'team', 'test', 'token', 'trust', 'undeprecate',
                        'uninstall', 'unpublish', 'unstar', 'update', 'version', 'view', 'whoami'
                    )
                    'access'      = @('list', 'get', 'set', 'grant', 'revoke')
                    'access list' = @('packages', 'collaborators')
                    'access get'  = @('status')
                    'cache'       = @('add', 'clean', 'ls', 'verify', 'npx')
                    'cache npx'   = @('ls', 'rm', 'info')
                    'config'      = @('set', 'get', 'delete', 'list', 'edit', 'fix')
                    'dist-tag'    = @('add', 'rm', 'ls')
                    'org'         = @('set', 'rm', 'ls')
                    'owner'       = @('add', 'rm', 'ls')
                    'pkg'         = @('set', 'get', 'delete', 'fix')
                    'profile'     = @('enable-2fa', 'disable-2fa', 'get', 'set')
                    'team'        = @('create', 'destroy', 'add', 'rm', 'ls')
                }
                StaticCommandAliases    = @{
                    ''       = @{
                        'c'          = 'config'
                        'dist-tags'  = 'dist-tag'
                        'author'     = 'owner'
                        'ogr'        = 'org'
                        'x'          = 'exec'
                        'run-script' = 'run'
                        'rum'        = 'run'
                        'urn'        = 'run'
                        'find'       = 'search'
                        's'          = 'search'
                        'se'         = 'search'
                        'add'        = 'install'
                        'i'          = 'install'
                        'in'         = 'install'
                        'ins'        = 'install'
                        'inst'       = 'install'
                        'insta'      = 'install'
                        'instal'     = 'install'
                        'isnt'       = 'install'
                        'isnta'      = 'install'
                        'isntal'     = 'install'
                        'isntall'    = 'install'
                        'unlink'     = 'uninstall'
                        'remove'     = 'uninstall'
                        'rm'         = 'uninstall'
                        'r'          = 'uninstall'
                        'un'         = 'uninstall'
                        'info'       = 'view'
                        'show'       = 'view'
                        'v'          = 'view'
                    }
                    'config' = @{
                        'ls' = 'list'
                    }
                }
                StaticOptionValues      = @{
                    '--location'                 = @('global', 'user', 'project')
                    'config|--location'          = @('global', 'user', 'project')
                    'install|--install-strategy' = @('hoisted', 'nested', 'shallow', 'linked')
                    'install|--omit'             = @('dev', 'optional', 'peer')
                    'install|--include'          = @('prod', 'dev', 'optional', 'peer')
                    'install|--allow-git'        = @('all', 'none', 'root')
                    'publish|--access'           = @('restricted', 'public')
                    'search|--color'             = @('always')
                }
                StaticPositionalValues  = @{
                    'access set|0'        = @('status=public', 'status=private', 'mfa=none', 'mfa=publish', 'mfa=automation')
                    'access grant|0'      = @('read-only', 'read-write')
                    'profile enable-2fa|0' = @('auth-only', 'auth-and-writes')
                    'org set|2'           = @('developer', 'admin', 'owner')
                }
                OptionAliases           = $null
                OptionsExpectingValue   = @(
                    '--access', '--allow-git', '--before', '--cache', '--call', '--cpu', '--editor', '--expect-result-count',
                    '--include', '--install-strategy', '--libc', '--location', '--min-release-age', '--omit', '--os',
                    '--otp', '--package', '--provenance-file', '--registry', '--script-shell', '--searchlimit',
                    '--searchexclude', '--searchopts', '--tag', '--workspace', '-L', '-c', '-w'
                )
                WorkspaceCacheTtlSeconds = 30
                NodeModulesCacheTtlSeconds = 30
                ConfigKeyCacheTtlSeconds = 300
                ConfigKeysLoadedAt      = [datetime]::MinValue
        }

        $script:NpmCompletionCache.OptionAliases = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
        $script:NpmCompletionCache.OptionAliases['-L'] = '--location'
        $script:NpmCompletionCache.OptionAliases['-w'] = '--workspace'
    }

    $script:NpmCompletionCache
}

function Get-NpmTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-NpmUniqueStrings {
    param(
        [string[]]$Items,
        [switch]$CaseSensitive
    )

    $stringComparer = if ($CaseSensitive) {
        [System.StringComparer]::Ordinal
    } else {
        [System.StringComparer]::OrdinalIgnoreCase
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new($stringComparer)
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

function Test-NpmStringArrayContains {
    param(
        [string[]]$Items,
        [string]$Value,
        [switch]$CaseSensitive
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $stringComparison = if ($CaseSensitive) {
        [System.StringComparison]::Ordinal
    } else {
        [System.StringComparison]::OrdinalIgnoreCase
    }

    foreach ($item in @($Items)) {
        if ($null -ne $item -and $item.Equals($Value, $stringComparison)) {
            return $true
        }
    }

    $false
}

function New-NpmCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $CompletionText,
        $ResultType,
        $ToolTip
    )
}

function New-NpmSuggestionItem {
    param(
        [string]$CompletionText,
        [string]$ToolTip,
        [string]$ResultType = 'ParameterValue'
    )

    if ([string]::IsNullOrWhiteSpace($CompletionText)) {
        return $null
    }

    [pscustomobject]@{
        CompletionText = $CompletionText
        ToolTip        = if ([string]::IsNullOrWhiteSpace($ToolTip)) { $CompletionText } else { $ToolTip }
        ResultType     = $ResultType
    }
}

function Get-NpmCacheKey {
    param([string[]]$Path)

    $pathItems = @($Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    (($pathItems | ForEach-Object { $_.ToLowerInvariant() }) -join ' ')
}

function Get-NpmExecutablePath {
    if ((Get-NpmCompletionCache).ExecutablePathProbed) {
        return (Get-NpmCompletionCache).ExecutablePath
    }

    (Get-NpmCompletionCache).ExecutablePathProbed = $true
    (Get-NpmCompletionCache).ExecutablePath = $null

    foreach ($commandName in @('npm.cmd', 'npm', 'npm.exe')) {
        $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue
        if ($command) {
            (Get-NpmCompletionCache).ExecutablePath = $command.Source
            break
        }
    }

    (Get-NpmCompletionCache).ExecutablePath
}

function ConvertTo-NpmCmdArgument {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    if ($Value -match '[\s"&|<>^()]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    $Value
}

function Invoke-NpmCommandCapture {
    param([string[]]$Arguments)

    $npmPath = Get-NpmExecutablePath
    if ([string]::IsNullOrWhiteSpace($npmPath)) {
        return @()
    }

    $processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processStartInfo.UseShellExecute = $false
    $processStartInfo.RedirectStandardOutput = $true
    $processStartInfo.RedirectStandardError = $true
    $processStartInfo.CreateNoWindow = $true

    if ($npmPath.EndsWith('.cmd', [System.StringComparison]::OrdinalIgnoreCase)) {
        $processStartInfo.FileName = 'cmd.exe'
        $argumentText = (@($Arguments) | ForEach-Object { ConvertTo-NpmCmdArgument -Value $_ }) -join ' '
        $commandText = if ([string]::IsNullOrWhiteSpace($argumentText)) {
            '""{0}""' -f $npmPath
        } else {
            '""{0}" {1}"' -f $npmPath, $argumentText
        }
        $processStartInfo.Arguments = '/d /c {0}' -f $commandText
    } else {
        $processStartInfo.FileName = $npmPath
        foreach ($argument in @($Arguments)) {
            [void]$processStartInfo.ArgumentList.Add($argument)
        }
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processStartInfo

    try {
        if (-not $process.Start()) {
            return @()
        }

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
    } finally {
        $process.Dispose()
    }

    @(
        ($stdout, $stderr) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_ -split '\r?\n' }
    )
}

function Get-NpmNormalizedHelpLines {
    param([string[]]$Arguments)

    $rawOutput = @(Invoke-NpmCommandCapture -Arguments (@($Arguments) + '--help'))

    if (-not $rawOutput -or $rawOutput.Count -eq 0) {
        return @()
    }

    $text = $rawOutput -join "`n"
    $text = $text -replace '[\x00-\x08\x0B-\x1F\x7F]', "`n"
    $text = [regex]::Replace(
        $text,
        '(?<!\r?\n)(?=Usage:|Options:|All commands:|Specify configs|More configuration info:|Configuration fields:|Run "|alias:|aliases:)',
        "`n"
    )

    @(
        $text -split '\r?\n' |
            ForEach-Object { $_.TrimEnd() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-NpmOptionTokensFromText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $tokens = foreach ($match in [regex]::Matches($Text, '(?<![\w-])(--[A-Za-z0-9][A-Za-z0-9-]*|-[A-Za-z])(?![\w-])')) {
        $match.Groups[1].Value
    }

    Get-NpmUniqueStrings -Items $tokens -CaseSensitive
}

function Add-NpmValueHints {
    param(
        [hashtable]$ValueMap,
        [string[]]$OptionTokens,
        [string]$ValueText
    )

    if ([string]::IsNullOrWhiteSpace($ValueText)) {
        return
    }

    $values = @(
        $ValueText -split '\|' |
            ForEach-Object { $_.Trim(' ', '[', ']', '(', ')', '"', "'") } |
            Where-Object { $_ -match '^[A-Za-z0-9][A-Za-z0-9._:-]*$' }
    )

    if (-not $values -or $values.Count -eq 0) {
        return
    }

    foreach ($token in @($OptionTokens)) {
        if (-not $ValueMap.ContainsKey($token)) {
            $ValueMap[$token] = @()
        }

        $ValueMap[$token] = Get-NpmUniqueStrings -Items (@($ValueMap[$token]) + @($values))
    }
}

function New-NpmHelpData {
    @{
        Commands             = @()
        Aliases              = @()
        Options              = @()
        ValuesByOption       = @{}
        OptionsExpectingValue = @()
    }
}

function Add-NpmUsageCommands {
    param(
        [hashtable]$HelpData,
        [string[]]$Path,
        [string]$UsageText
    )

    if ([string]::IsNullOrWhiteSpace($UsageText)) {
        return
    }

    $usage = $UsageText.Trim()
    if ($usage -notmatch '^\s*npm\b') {
        return
    }

    $tokens = @([regex]::Matches($usage, '\S+') | ForEach-Object { $_.Value })
    if ($tokens.Count -le 1) {
        return
    }

    $remaining = @($tokens[1..($tokens.Count - 1)])
    $pathMatched = $true

    foreach ($segment in @($Path)) {
        if ($remaining.Count -eq 0 -or -not $remaining[0].Equals($segment, [System.StringComparison]::OrdinalIgnoreCase)) {
            $pathMatched = $false
            break
        }

        if ($remaining.Count -eq 1) {
            $remaining = @()
        } else {
            $remaining = @($remaining[1..($remaining.Count - 1)])
        }
    }

    if (-not $pathMatched -or $remaining.Count -eq 0) {
        return
    }

    $nextToken = $remaining[0].Trim('[', ']', '(', ')')
    if ($nextToken -match '^[A-Za-z][A-Za-z0-9-]*$') {
        $HelpData.Commands = Get-NpmUniqueStrings -Items (@($HelpData.Commands) + @($nextToken))
    }
}

function Add-NpmOptionMetadata {
    param(
        [hashtable]$HelpData,
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    $optionTokens = @(Get-NpmOptionTokensFromText -Text $Text)
    if ($optionTokens.Count -eq 0) {
        return
    }

    $HelpData.Options = Get-NpmUniqueStrings -Items (@($HelpData.Options) + @($optionTokens)) -CaseSensitive

    foreach ($chunkMatch in [regex]::Matches($Text, '\[(?<chunk>[^\]]+)\]')) {
        $chunk = $chunkMatch.Groups['chunk'].Value
        $chunkTokens = @(Get-NpmOptionTokensFromText -Text $chunk)
        if ($chunkTokens.Count -eq 0) {
            continue
        }

        if ($chunk -match '<(?<value>[^>]+)>') {
            $valueText = $matches['value']
            $HelpData.OptionsExpectingValue = Get-NpmUniqueStrings -Items (@($HelpData.OptionsExpectingValue) + @($chunkTokens)) -CaseSensitive

            if ($valueText -match '\|') {
                Add-NpmValueHints -ValueMap $HelpData.ValuesByOption -OptionTokens $chunkTokens -ValueText $valueText
            }

            continue
        }

        foreach ($literalMatch in [regex]::Matches($chunk, '(?<token>--[A-Za-z0-9][A-Za-z0-9-]*)\s+(?<literal>[A-Za-z][A-Za-z0-9-]*)')) {
            Add-NpmValueHints -ValueMap $HelpData.ValuesByOption -OptionTokens @($literalMatch.Groups['token'].Value) -ValueText $literalMatch.Groups['literal'].Value
        }
    }

    if ($Text -match '^\s*(--[A-Za-z0-9][A-Za-z0-9-]*|-[A-Za-z])\s*$') {
        return
    }
}

function Get-NpmHelpData {
    param([string[]]$Path)

    $cacheKey = Get-NpmCacheKey -Path $Path
    if ((Get-NpmCompletionCache).HelpDataByPath.ContainsKey($cacheKey)) {
        return (Get-NpmCompletionCache).HelpDataByPath[$cacheKey]
    }

    if (@($Path).Count -gt 1 -and -not (Get-NpmCompletionCache).StaticTree.ContainsKey($cacheKey)) {
        $parentPath = @($Path[0..($Path.Count - 2)])
        $helpData = Get-NpmHelpData -Path $parentPath
        (Get-NpmCompletionCache).HelpDataByPath[$cacheKey] = $helpData
        return $helpData
    }

    $helpData = New-NpmHelpData
    if (@($Path).Count -eq 0) {
        (Get-NpmCompletionCache).HelpDataByPath[$cacheKey] = $helpData
        return $helpData
    }

    $lines = Get-NpmNormalizedHelpLines -Arguments $Path

    $inUsage = $false
    $inOptions = $false

    foreach ($line in @($lines)) {
        $trimmed = $line.Trim()

        if ($trimmed -match '^(?:alias|aliases):\s*(?<aliases>.+)$') {
            $aliases = @(
                $matches['aliases'] -split ',' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -match '^[A-Za-z][A-Za-z0-9-]*$' }
            )

            $helpData.Aliases = @(Get-NpmUniqueStrings -Items (@($helpData.Aliases) + $aliases))
        }

        if ($trimmed -match '^Usage:\s*(.*)$') {
            $inUsage = $true
            $inOptions = $false

            if (-not [string]::IsNullOrWhiteSpace($matches[1])) {
                Add-NpmUsageCommands -HelpData $helpData -Path $Path -UsageText $matches[1]
                Add-NpmOptionMetadata -HelpData $helpData -Text $matches[1]
            }

            continue
        }

        if ($trimmed -match '^Options:\s*(.*)$') {
            $inUsage = $false
            $inOptions = $true

            if (-not [string]::IsNullOrWhiteSpace($matches[1])) {
                Add-NpmOptionMetadata -HelpData $helpData -Text $matches[1]
            }

            continue
        }

        if ($trimmed -match '^(Run "|alias:|aliases:|Specify configs|More configuration info:|Configuration fields:|All commands:)') {
            $inUsage = $false
            $inOptions = $false
        }

        if ($inUsage) {
            Add-NpmUsageCommands -HelpData $helpData -Path $Path -UsageText $trimmed
            Add-NpmOptionMetadata -HelpData $helpData -Text $trimmed
            continue
        }

        if ($inOptions) {
            Add-NpmOptionMetadata -HelpData $helpData -Text $trimmed
        }
    }

    if (@($Path).Count -gt 0 -and @($helpData.Aliases).Count -gt 0) {
        $parentPath = if ($Path.Count -gt 1) {
            @($Path[0..($Path.Count - 2)])
        } else {
            @()
        }

        $parentKey = Get-NpmCacheKey -Path $parentPath
        if (-not (Get-NpmCompletionCache).DiscoveredCommandAliasesByPath.ContainsKey($parentKey)) {
            (Get-NpmCompletionCache).DiscoveredCommandAliasesByPath[$parentKey] = @{}
        }

        $aliasMap = (Get-NpmCompletionCache).DiscoveredCommandAliasesByPath[$parentKey]
        $canonicalCommand = $Path[-1]
        foreach ($alias in @($helpData.Aliases)) {
            if (-not $alias.Equals($canonicalCommand, [System.StringComparison]::OrdinalIgnoreCase)) {
                $aliasMap[$alias] = $canonicalCommand
            }
        }
    }

    (Get-NpmCompletionCache).HelpDataByPath[$cacheKey] = $helpData
    $helpData
}

function Get-NpmCommandAliasMap {
    param([string[]]$Path)

    $cacheKey = Get-NpmCacheKey -Path $Path

    $aliasMap = @{}
    if ((Get-NpmCompletionCache).StaticCommandAliases.ContainsKey($cacheKey)) {
        foreach ($entry in (Get-NpmCompletionCache).StaticCommandAliases[$cacheKey].GetEnumerator()) {
            $aliasMap[$entry.Key] = $entry.Value
        }
    }

    if ((Get-NpmCompletionCache).DiscoveredCommandAliasesByPath.ContainsKey($cacheKey)) {
        foreach ($entry in (Get-NpmCompletionCache).DiscoveredCommandAliasesByPath[$cacheKey].GetEnumerator()) {
            $aliasMap[$entry.Key] = $entry.Value
        }
    }

    $aliasMap
}

function Get-NpmCanonicalSubcommands {
    param([string[]]$Path)

    $cacheKey = Get-NpmCacheKey -Path $Path
    $staticCommands = if ((Get-NpmCompletionCache).StaticTree.ContainsKey($cacheKey)) {
        @((Get-NpmCompletionCache).StaticTree[$cacheKey])
    } else {
        @()
    }

    if (@($Path).Count -gt 0 -and -not (Get-NpmCompletionCache).StaticTree.ContainsKey($cacheKey)) {
        return $staticCommands
    }

    $helpData = Get-NpmHelpData -Path $Path
    Get-NpmUniqueStrings -Items ($staticCommands + $helpData.Commands)
}

function Get-NpmSubcommands {
    param([string[]]$Path)

    $canonicalCommands = @(Get-NpmCanonicalSubcommands -Path $Path)
    $aliasNames = @((Get-NpmCommandAliasMap -Path $Path).Keys)
    Get-NpmUniqueStrings -Items ($canonicalCommands + $aliasNames)
}

function Resolve-NpmSubcommandToken {
    param(
        [string[]]$Path,
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    foreach ($command in @(Get-NpmCanonicalSubcommands -Path $Path)) {
        if ($command.Equals($Token, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $command
        }
    }

    foreach ($entry in (Get-NpmCommandAliasMap -Path $Path).GetEnumerator()) {
        if ($entry.Key.Equals($Token, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $entry.Value
        }
    }

    $null
}

function Normalize-NpmOptionName {
    param([string]$Option)

    if ([string]::IsNullOrWhiteSpace($Option)) {
        return $Option
    }

    if ((Get-NpmCompletionCache).OptionAliases.ContainsKey($Option)) {
        return (Get-NpmCompletionCache).OptionAliases[$Option]
    }

    $Option.ToLowerInvariant()
}

function Test-NpmOptionRequiresValue {
    param(
        [string[]]$Path,
        [string]$Option
    )

    if ([string]::IsNullOrWhiteSpace($Option)) {
        return $false
    }

    $normalizedOption = Normalize-NpmOptionName -Option $Option
    if ((Test-NpmStringArrayContains -Items (Get-NpmCompletionCache).OptionsExpectingValue -Value $Option -CaseSensitive) -or
        (Test-NpmStringArrayContains -Items (Get-NpmCompletionCache).OptionsExpectingValue -Value $normalizedOption -CaseSensitive)) {
        return $true
    }

    $helpData = Get-NpmHelpData -Path $Path
    (Test-NpmStringArrayContains -Items $helpData.OptionsExpectingValue -Value $Option -CaseSensitive) -or
    (Test-NpmStringArrayContains -Items $helpData.OptionsExpectingValue -Value $normalizedOption -CaseSensitive)
}

function Find-NpmNearestPackageJsonPath {
    $currentPath = (Get-Location).ProviderPath

    while (-not [string]::IsNullOrWhiteSpace($currentPath)) {
        $candidate = Join-Path -Path $currentPath -ChildPath 'package.json'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }

        $parent = Split-Path -Path $currentPath -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $currentPath) {
            break
        }

        $currentPath = $parent
    }

    $null
}

function Get-NpmPackageJsonData {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) {
        return $null
    }

    $cacheEntry = if ((Get-NpmCompletionCache).PackageJsonByPath.ContainsKey($Path)) {
        (Get-NpmCompletionCache).PackageJsonByPath[$Path]
    } else {
        $null
    }

    if ($cacheEntry -and $cacheEntry.LastWriteTimeUtc -eq $item.LastWriteTimeUtc) {
        return $cacheEntry.Data
    }

    $data = $null
    try {
        $data = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    } catch {
        $data = $null
    }

    (Get-NpmCompletionCache).PackageJsonByPath[$Path] = @{
        LastWriteTimeUtc = $item.LastWriteTimeUtc
        Data             = $data
    }

    $data
}

function Get-NpmScriptNames {
    $packageJsonPath = Find-NpmNearestPackageJsonPath
    if ([string]::IsNullOrWhiteSpace($packageJsonPath)) {
        return @()
    }

    $packageData = Get-NpmPackageJsonData -Path $packageJsonPath
    if ($null -eq $packageData -or -not $packageData.ContainsKey('scripts')) {
        return @()
    }

    $scripts = $packageData['scripts']
    if ($scripts -isnot [System.Collections.IDictionary]) {
        return @()
    }

    @($scripts.Keys | Sort-Object -Unique)
}

function Get-NpmWorkspaceNames {
    $packageJsonPath = Find-NpmNearestPackageJsonPath
    if ([string]::IsNullOrWhiteSpace($packageJsonPath)) {
        return @()
    }

    $projectRoot = Split-Path -Path $packageJsonPath -Parent
    $cacheKey = $projectRoot.ToLowerInvariant()

    if ((Get-NpmCompletionCache).WorkspaceNamesByRoot.ContainsKey($cacheKey)) {
        $cacheEntry = (Get-NpmCompletionCache).WorkspaceNamesByRoot[$cacheKey]
        $cacheAge = (Get-Date) - $cacheEntry.UpdatedAt
        if ($cacheAge.TotalSeconds -lt (Get-NpmCompletionCache).WorkspaceCacheTtlSeconds) {
            return $cacheEntry.Values
        }
    }

    $packageData = Get-NpmPackageJsonData -Path $packageJsonPath
    if ($null -eq $packageData -or -not $packageData.ContainsKey('workspaces')) {
        (Get-NpmCompletionCache).WorkspaceNamesByRoot[$cacheKey] = @{
            UpdatedAt = Get-Date
            Values    = @()
        }
        return @()
    }

    $workspacePatterns = @()
    $workspaces = $packageData['workspaces']
    if ($workspaces -is [System.Collections.IDictionary] -and $workspaces.ContainsKey('packages')) {
        $workspacePatterns = @($workspaces['packages'])
    } elseif ($workspaces -is [System.Collections.IEnumerable] -and $workspaces -isnot [string]) {
        $workspacePatterns = @($workspaces)
    }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in @($workspacePatterns)) {
        if ([string]::IsNullOrWhiteSpace([string]$pattern)) {
            continue
        }

        $resolvedPaths = @(Resolve-Path -Path (Join-Path -Path $projectRoot -ChildPath ([string]$pattern)) -ErrorAction SilentlyContinue)
        foreach ($resolvedPath in $resolvedPaths) {
            $item = Get-Item -LiteralPath $resolvedPath.ProviderPath -ErrorAction SilentlyContinue
            if (-not $item) {
                continue
            }

            $workspacePackagePath = if ($item.PSIsContainer) {
                Join-Path -Path $item.FullName -ChildPath 'package.json'
            } elseif ($item.Name -eq 'package.json') {
                $item.FullName
            } else {
                $null
            }

            if ([string]::IsNullOrWhiteSpace($workspacePackagePath) -or -not (Test-Path -LiteralPath $workspacePackagePath -PathType Leaf)) {
                continue
            }

            $workspaceData = Get-NpmPackageJsonData -Path $workspacePackagePath
            if ($null -eq $workspaceData) {
                continue
            }

            $workspaceName = if ($workspaceData.ContainsKey('name') -and -not [string]::IsNullOrWhiteSpace([string]$workspaceData['name'])) {
                [string]$workspaceData['name']
            } else {
                Split-Path -Path (Split-Path -Path $workspacePackagePath -Parent) -Leaf
            }

            [void]$names.Add($workspaceName)
        }
    }

    $values = @($names | Sort-Object -Unique)
    (Get-NpmCompletionCache).WorkspaceNamesByRoot[$cacheKey] = @{
        UpdatedAt = Get-Date
        Values    = $values
    }

    $values
}

function Add-NpmPropertyPaths {
    param(
        [object]$Value,
        [string]$Prefix,
        [int]$Depth,
        [System.Collections.Generic.List[string]]$Results
    )

    if ($Depth -le 0 -or $null -eq $Value) {
        return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys | Sort-Object)) {
            $keyText = [string]$key
            $path = if ([string]::IsNullOrWhiteSpace($Prefix)) { $keyText } else { '{0}.{1}' -f $Prefix, $keyText }
            [void]$Results.Add($path)
            Add-NpmPropertyPaths -Value $Value[$key] -Prefix $path -Depth ($Depth - 1) -Results $Results
        }

        return
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
            [void]$Results.Add('{0}[]' -f $Prefix)
        }

        $index = 0
        foreach ($item in $Value) {
            if ($index -ge 3) {
                break
            }

            if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
                $indexedPrefix = '{0}[{1}]' -f $Prefix, $index
                [void]$Results.Add($indexedPrefix)
                Add-NpmPropertyPaths -Value $item -Prefix $indexedPrefix -Depth ($Depth - 1) -Results $Results
            }

            $index++
        }
    }
}

function Get-NpmPackagePropertyPaths {
    $packageJsonPath = Find-NpmNearestPackageJsonPath
    if ([string]::IsNullOrWhiteSpace($packageJsonPath)) {
        return @()
    }

    $packageData = Get-NpmPackageJsonData -Path $packageJsonPath
    if ($null -eq $packageData) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[string]
    Add-NpmPropertyPaths -Value $packageData -Prefix '' -Depth 4 -Results $results
    Get-NpmUniqueStrings -Items $results
}

function Get-NpmNodeModulesRoot {
    $packageJsonPath = Find-NpmNearestPackageJsonPath
    $currentPath = if ([string]::IsNullOrWhiteSpace($packageJsonPath)) {
        (Get-Location).ProviderPath
    } else {
        Split-Path -Path $packageJsonPath -Parent
    }

    while (-not [string]::IsNullOrWhiteSpace($currentPath)) {
        $candidate = Join-Path -Path $currentPath -ChildPath 'node_modules'
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return $candidate
        }

        $parent = Split-Path -Path $currentPath -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $currentPath) {
            break
        }

        $currentPath = $parent
    }

    $null
}

function Get-NpmInstalledPackageNames {
    $nodeModulesPath = Get-NpmNodeModulesRoot
    if ([string]::IsNullOrWhiteSpace($nodeModulesPath)) {
        return @()
    }

    $cacheKey = $nodeModulesPath.ToLowerInvariant()
    if ((Get-NpmCompletionCache).NodeModulesByRoot.ContainsKey($cacheKey)) {
        $cacheEntry = (Get-NpmCompletionCache).NodeModulesByRoot[$cacheKey]
        $cacheAge = (Get-Date) - $cacheEntry.UpdatedAt
        if ($cacheAge.TotalSeconds -lt (Get-NpmCompletionCache).NodeModulesCacheTtlSeconds) {
            return $cacheEntry.Values
        }
    }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(Get-ChildItem -LiteralPath $nodeModulesPath -Directory -ErrorAction SilentlyContinue)) {
        if ($item.Name -eq '.bin') {
            continue
        }

        if ($item.Name.StartsWith('@', [System.StringComparison]::Ordinal)) {
            foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Directory -ErrorAction SilentlyContinue)) {
                [void]$names.Add("$($item.Name)/$($child.Name)")
            }
            continue
        }

        [void]$names.Add($item.Name)
    }

    $values = @($names | Sort-Object -Unique)
    (Get-NpmCompletionCache).NodeModulesByRoot[$cacheKey] = @{
        UpdatedAt = Get-Date
        Values    = $values
    }

    $values
}

function Update-NpmConfigKeys {
    $cacheAge = (Get-Date) - (Get-NpmCompletionCache).ConfigKeysLoadedAt
    if ((Get-NpmCompletionCache).ConfigKeysLoaded -and $cacheAge.TotalSeconds -lt (Get-NpmCompletionCache).ConfigKeyCacheTtlSeconds) {
        return
    }

    if ([string]::IsNullOrWhiteSpace((Get-NpmExecutablePath))) {
        (Get-NpmCompletionCache).ConfigKeys = @()
        (Get-NpmCompletionCache).ConfigKeysLoaded = $true
        (Get-NpmCompletionCache).ConfigKeysLoadedAt = Get-Date
        return
    }

    $rawOutput = @(Invoke-NpmCommandCapture -Arguments @('config', 'ls', '-l'))

    $keys = foreach ($line in @($rawOutput)) {
        if ($line -match '^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*=') {
            $matches[1]
        }
    }

    (Get-NpmCompletionCache).ConfigKeys = @($keys | Sort-Object -Unique)
    (Get-NpmCompletionCache).ConfigKeysLoaded = $true
    (Get-NpmCompletionCache).ConfigKeysLoadedAt = Get-Date
}

function Get-NpmConfigKeys {
    Update-NpmConfigKeys
    (Get-NpmCompletionCache).ConfigKeys
}

function Get-NpmCommandState {
    param([string[]]$TokensBeforeCurrent)

    $path = New-Object System.Collections.Generic.List[string]
    $positionals = New-Object System.Collections.Generic.List[string]
    $expectingValueOption = $null
    $afterDoubleDash = $false

    $remainingTokens = if ($TokensBeforeCurrent.Count -gt 1) {
        @($TokensBeforeCurrent[1..($TokensBeforeCurrent.Count - 1)])
    } else {
        @()
    }

    foreach ($token in @($remainingTokens)) {
        if ($afterDoubleDash) {
            [void]$positionals.Add($token)
            continue
        }

        if ($null -ne $expectingValueOption) {
            $expectingValueOption = $null
            continue
        }

        if ($token -eq '--') {
            $afterDoubleDash = $true
            continue
        }

        if ($token -match '^(--[^=]+)=(.*)$') {
            continue
        }

        if ($token.StartsWith('-')) {
            if (Test-NpmOptionRequiresValue -Path $path -Option $token) {
                $expectingValueOption = $token
            }
            continue
        }

        $matchingSubcommand = Resolve-NpmSubcommandToken -Path $path -Token $token

        if ($matchingSubcommand) {
            [void]$path.Add($matchingSubcommand)
            continue
        }

        [void]$positionals.Add($token)
    }

    [pscustomobject]@{
        Path                 = @($path.ToArray())
        Positionals          = @($positionals.ToArray())
        ExpectingValueOption = $expectingValueOption
        AfterDoubleDash      = $afterDoubleDash
    }
}

function Get-NpmOptionSuggestions {
    param([string[]]$Path)

    $helpData = Get-NpmHelpData -Path $Path
    foreach ($option in @(Get-NpmUniqueStrings -Items $helpData.Options -CaseSensitive | Sort-Object -CaseSensitive)) {
        New-NpmSuggestionItem -CompletionText $option -ToolTip ('npm option {0}' -f $option) -ResultType 'ParameterName'
    }
}

function Get-NpmValueSuggestionsForOption {
    param(
        [string[]]$Path,
        [string]$Option
    )

    $pathKey = Get-NpmCacheKey -Path $Path
    $normalizedOption = Normalize-NpmOptionName -Option $Option
    $helpData = Get-NpmHelpData -Path $Path
    $items = New-Object System.Collections.Generic.List[object]
    $lookupKeys = @(
        $Option
        $normalizedOption
        ('{0}|{1}' -f $pathKey, $Option)
        ('{0}|{1}' -f $pathKey, $normalizedOption)
    )

    foreach ($lookupKey in $lookupKeys) {
        if ($helpData.ValuesByOption.ContainsKey($lookupKey)) {
            foreach ($value in @($helpData.ValuesByOption[$lookupKey])) {
                $item = New-NpmSuggestionItem -CompletionText $value -ToolTip ('{0} value' -f $normalizedOption)
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }

        if ((Get-NpmCompletionCache).StaticOptionValues.ContainsKey($lookupKey)) {
            foreach ($value in @((Get-NpmCompletionCache).StaticOptionValues[$lookupKey])) {
                $item = New-NpmSuggestionItem -CompletionText $value -ToolTip ('{0} value' -f $normalizedOption)
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
    }

    switch ($normalizedOption) {
        '--workspace' {
            foreach ($workspace in @(Get-NpmWorkspaceNames)) {
                $item = New-NpmSuggestionItem -CompletionText $workspace -ToolTip 'workspace name'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
        '--package' {
            foreach ($packageName in @(Get-NpmInstalledPackageNames)) {
                $item = New-NpmSuggestionItem -CompletionText $packageName -ToolTip 'installed package'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
    }

    @($items.ToArray())
}

function Get-NpmPositionalSuggestions {
    param(
        [string[]]$Path,
        [string[]]$Positionals,
        [bool]$AfterDoubleDash
    )

    if ($AfterDoubleDash) {
        return @()
    }

    $items = New-Object System.Collections.Generic.List[object]
    $pathKey = Get-NpmCacheKey -Path $Path
    $positionIndex = $Positionals.Count

    $staticPositionalKey = '{0}|{1}' -f $pathKey, $positionIndex
    if ((Get-NpmCompletionCache).StaticPositionalValues.ContainsKey($staticPositionalKey)) {
        foreach ($value in @((Get-NpmCompletionCache).StaticPositionalValues[$staticPositionalKey])) {
            $item = New-NpmSuggestionItem -CompletionText $value -ToolTip ('npm {0} value' -f $pathKey)
            if ($item) {
                [void]$items.Add($item)
            }
        }
    }

    if ($pathKey -eq 'run' -and $positionIndex -eq 0) {
        foreach ($scriptName in @(Get-NpmScriptNames)) {
            $item = New-NpmSuggestionItem -CompletionText $scriptName -ToolTip 'package.json script'
            if ($item) {
                [void]$items.Add($item)
            }
        }
    }

    if ($Path.Count -ge 2 -and $Path[0] -eq 'config' -and $Path[1] -in @('get', 'set', 'delete')) {
        $configKeys = @(Get-NpmConfigKeys)
        if ($Path[1] -eq 'set') {
            foreach ($key in $configKeys) {
                $item = New-NpmSuggestionItem -CompletionText ('{0}=' -f $key) -ToolTip 'npm config key'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        } else {
            foreach ($key in $configKeys) {
                $item = New-NpmSuggestionItem -CompletionText $key -ToolTip 'npm config key'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
    }

    if ($Path.Count -ge 2 -and $Path[0] -eq 'pkg' -and $Path[1] -in @('get', 'set', 'delete')) {
        $propertyPaths = @(Get-NpmPackagePropertyPaths)
        if ($Path[1] -eq 'set') {
            foreach ($propertyPath in $propertyPaths) {
                $item = New-NpmSuggestionItem -CompletionText ('{0}=' -f $propertyPath) -ToolTip 'package.json property path'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        } else {
            foreach ($propertyPath in $propertyPaths) {
                $item = New-NpmSuggestionItem -CompletionText $propertyPath -ToolTip 'package.json property path'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
    }

    $packageNameCommands = @('install', 'uninstall', 'update', 'outdated', 'ls', 'explain')
    if ($Path.Count -ge 1 -and $Path[0] -in $packageNameCommands) {
        foreach ($packageName in @(Get-NpmInstalledPackageNames)) {
            $item = New-NpmSuggestionItem -CompletionText $packageName -ToolTip 'installed package'
            if ($item) {
                [void]$items.Add($item)
            }
        }
    }

    if ($Path.Count -ge 2 -and $Path[0] -eq 'owner') {
        $positionForPackage = switch ($Path[1]) {
            'ls' { 0 }
            default { 1 }
        }

        if ($positionIndex -eq $positionForPackage) {
            foreach ($packageName in @(Get-NpmInstalledPackageNames)) {
                $item = New-NpmSuggestionItem -CompletionText $packageName -ToolTip 'installed package'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
    }

    if ($Path.Count -ge 2 -and $Path[0] -eq 'dist-tag' -and $positionIndex -eq 0) {
        foreach ($packageName in @(Get-NpmInstalledPackageNames)) {
            $item = New-NpmSuggestionItem -CompletionText $packageName -ToolTip 'installed package'
            if ($item) {
                [void]$items.Add($item)
            }
        }
    }

    @($items.ToArray())
}

function ConvertTo-NpmCompletionResults {
    param(
        [object[]]$Items,
        [string]$Prefix
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    $safePrefix = if ($null -eq $Prefix) { '' } else { $Prefix }

    foreach ($item in @($Items)) {
        if ($null -eq $item) {
            continue
        }

        $completionText = [string]$item.CompletionText
        if ([string]::IsNullOrWhiteSpace($completionText)) {
            continue
        }

        if (-not $completionText.StartsWith($safePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if (-not $seen.Add($completionText)) {
            continue
        }

        [void]$results.Add((New-NpmCompletionResult -CompletionText $completionText -ResultType $item.ResultType -ToolTip $item.ToolTip))
    }

    @($results.ToArray())
}

function Complete-NpmNative {
    param($wordToComplete, $commandAst, $cursorPosition)

    $elements = @(
        $commandAst.CommandElements |
            ForEach-Object { Get-NpmTokenText -Element $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($elements.Count -eq 0) {
        return
    }

    $prefixLength = [Math]::Max(0, [Math]::Min($cursorPosition - $commandAst.Extent.StartOffset, $commandAst.Extent.Text.Length))
    $linePrefix = $commandAst.Extent.Text.Substring(0, $prefixLength)
    $hasTrailingSpace = ($cursorPosition -gt $commandAst.Extent.EndOffset) -or ($linePrefix -match '\s$')

    if ([string]::IsNullOrEmpty($wordToComplete) -and $hasTrailingSpace) {
        $tokensBeforeCurrent = @($elements)
        $currentToken = ''
    } else {
        $tokensBeforeCurrent = if ($elements.Count -gt 1) {
            @($elements[0..($elements.Count - 2)])
        } else {
            @()
        }

        if (@($tokensBeforeCurrent).Count -eq 0 -and $elements.Count -gt 0) {
            $tokensBeforeCurrent = @($elements[0])
        }

        $currentToken = if ([string]::IsNullOrEmpty($wordToComplete)) {
            $elements[-1]
        } else {
            $wordToComplete
        }
    }

    $state = Get-NpmCommandState -TokensBeforeCurrent $tokensBeforeCurrent
    $suggestions = New-Object System.Collections.Generic.List[object]

    if ($currentToken -match '^(--[^=]+)=(.*)$') {
        $optionName = $matches[1]
        $valuePrefix = $matches[2]

        foreach ($item in @(Get-NpmValueSuggestionsForOption -Path $state.Path -Option $optionName)) {
            if ($null -ne $item) {
                [void]$suggestions.Add((New-NpmSuggestionItem -CompletionText ('{0}={1}' -f $optionName, $item.CompletionText) -ToolTip $item.ToolTip))
            }
        }

        ConvertTo-NpmCompletionResults -Items $suggestions -Prefix ('{0}={1}' -f $optionName, $valuePrefix)
        return
    }

    if ($null -ne $state.ExpectingValueOption) {
        $valueSuggestions = Get-NpmValueSuggestionsForOption -Path $state.Path -Option $state.ExpectingValueOption
        ConvertTo-NpmCompletionResults -Items $valueSuggestions -Prefix $currentToken
        return
    }

    if ([string]::IsNullOrEmpty($currentToken) -or $currentToken.StartsWith('-')) {
        foreach ($optionSuggestion in @(Get-NpmOptionSuggestions -Path $state.Path)) {
            if ($null -ne $optionSuggestion) {
                [void]$suggestions.Add($optionSuggestion)
            }
        }
    }

    if (-not $state.AfterDoubleDash -and -not $currentToken.StartsWith('-') -and $state.Positionals.Count -eq 0) {
        $subcommandAliases = Get-NpmCommandAliasMap -Path $state.Path
        foreach ($subcommand in @(Get-NpmSubcommands -Path $state.Path)) {
            $canonicalSubcommand = if ($subcommandAliases.ContainsKey($subcommand)) {
                $subcommandAliases[$subcommand]
            } else {
                $subcommand
            }

            $toolTip = if ($subcommandAliases.ContainsKey($subcommand)) {
                'npm alias for {0}' -f $canonicalSubcommand
            } else {
                'npm {0} command' -f $canonicalSubcommand
            }

            $item = New-NpmSuggestionItem -CompletionText $subcommand -ToolTip $toolTip
            if ($item) {
                [void]$suggestions.Add($item)
            }
        }
    }

    if (-not $currentToken.StartsWith('-')) {
        foreach ($positionalSuggestion in @(Get-NpmPositionalSuggestions -Path $state.Path -Positionals $state.Positionals -AfterDoubleDash $state.AfterDoubleDash)) {
            if ($null -ne $positionalSuggestion) {
                [void]$suggestions.Add($positionalSuggestion)
            }
        }
    }

    ConvertTo-NpmCompletionResults -Items $suggestions -Prefix $currentToken
}

Register-ArgumentCompleter -Native -CommandName @('npm', 'npm.ps1', 'npm.cmd', 'npm.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-NpmNative -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
