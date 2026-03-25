Set-StrictMode -Version Latest

if (-not (Get-Variable -Name BunCompletionCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:BunCompletionCache = @{
        ExecutablePath       = $null
        ExecutablePathProbed = $false
        HelpDataByPath       = @{}
        PackageJsonByPath    = @{}
        WorkspaceNamesByRoot = @{}
        NodeModulesByRoot    = @{}
        TemplateNamesByRoot  = @{}
        StaticTree           = @{
            ''         = @(
                'run', 'test', 'x', 'repl', 'exec', 'install', 'add', 'remove', 'update', 'audit', 'outdated',
                'link', 'unlink', 'publish', 'patch', 'pm', 'info', 'why', 'list', 'build', 'init', 'create',
                'upgrade', 'feedback'
            )
            'pm'       = @(
                'scan', 'pack', 'bin', 'ls', 'why', 'whoami', 'view', 'version', 'pkg', 'hash',
                'hash-string', 'hash-print', 'cache', 'migrate', 'untrusted', 'trust', 'default-trusted'
            )
            'pm cache' = @('rm')
            'pm pkg'   = @('get', 'set', 'delete', 'fix')
        }
        StaticDescriptions   = @{
            ''         = @{
                'run'      = 'Execute a file, package.json script, package binary, or system command'
                'test'     = 'Run tests with Bun''s built-in test runner'
                'x'        = 'Execute a package binary and install it if needed (bunx)'
                'repl'     = 'Start an interactive Bun REPL'
                'exec'     = 'Run a shell script directly with Bun'
                'install'  = 'Install dependencies from package.json'
                'add'      = 'Add a dependency to package.json'
                'remove'   = 'Remove a dependency from package.json'
                'update'   = 'Update dependencies'
                'audit'    = 'Check installed packages for vulnerabilities'
                'outdated' = 'Display outdated dependencies'
                'link'     = 'Register or link a local package'
                'unlink'   = 'Unregister a previously linked package'
                'publish'  = 'Publish a package to the npm registry'
                'patch'    = 'Prepare a package for patching or save a patch'
                'pm'       = 'Package manager utilities'
                'info'     = 'View package metadata from the registry'
                'why'      = 'Explain why a package is installed'
                'list'     = 'List installed dependencies'
                'build'    = 'Bundle and transpile source files'
                'init'     = 'Initialize a Bun project'
                'create'   = 'Create a project from a template'
                'upgrade'  = 'Upgrade Bun itself'
                'feedback' = 'Send feedback to the Bun team'
            }
            'pm'       = @{
                'scan'            = 'Scan packages in the lockfile for security vulnerabilities'
                'pack'            = 'Create a tarball of the current workspace'
                'bin'             = 'Print the bin directory path'
                'ls'              = 'List dependencies from the lockfile'
                'why'             = 'Show dependency tree explaining why a package is installed'
                'whoami'          = 'Print the current npm username'
                'view'            = 'View package metadata from the registry'
                'version'         = 'Bump package.json version and create a git tag'
                'pkg'             = 'Manage package.json data'
                'hash'            = 'Generate and print the current lockfile hash'
                'hash-string'     = 'Print the string used to hash the lockfile'
                'hash-print'      = 'Print the hash stored in the lockfile'
                'cache'           = 'Print or clear Bun''s cache'
                'migrate'         = 'Migrate another package manager lockfile'
                'untrusted'       = 'Print current untrusted dependencies with scripts'
                'trust'           = 'Trust untrusted dependencies and run their scripts'
                'default-trusted' = 'Print Bun''s default trusted dependencies'
            }
            'pm cache' = @{
                'rm' = 'Clear Bun''s global package cache'
            }
            'pm pkg'   = @{
                'get'    = 'Read package.json values'
                'set'    = 'Update package.json values'
                'delete' = 'Delete package.json values'
                'fix'    = 'Auto-correct common package.json issues'
            }
        }
        StaticAliases        = @{
            ''   = @{
                'i'  = 'install'
                'a'  = 'add'
                'r'  = 'remove'
                'rm' = 'remove'
                'c'  = 'create'
            }
            'pm' = @{
                'list' = 'ls'
            }
        }
        StaticOptionValues   = @{
            '--install'                = @('auto', 'fallback', 'force')
            '--dns-result-order'       = @('verbatim', 'ipv4first', 'ipv6first')
            '--unhandled-rejections'   = @('strict', 'throw', 'warn', 'none', 'warn-with-error-code')
            '--backend'                = @('clonefile', 'hardlink', 'symlink', 'copyfile')
            '--omit'                   = @('dev', 'optional', 'peer')
            '--linker'                 = @('isolated', 'hoisted')
            '--audit-level'            = @('low', 'moderate', 'high', 'critical')
            'run|--shell'              = @('bun', 'system')
            'build|--target'           = @('browser', 'bun', 'node')
            'build|--sourcemap'        = @('linked', 'inline', 'external', 'none')
            'build|--format'           = @('esm', 'cjs', 'iife')
            'build|--packages'         = @('external', 'bundle')
            'build|--jsx-runtime'      = @('automatic', 'classic')
            'build|--env'              = @('disable')
            'test|--coverage-reporter' = @('text', 'lcov')
            'test|--reporter'          = @('junit', 'dots')
            'publish|--access'         = @('public', 'restricted')
            'pm pack|--gzip-level'     = @('0', '1', '2', '3', '4', '5', '6', '7', '8', '9')
            'init|--react'             = @('tailwind', 'shadcn')
        }
        WorkspaceCacheTtlSeconds = 30
        NodeModulesCacheTtlSeconds = 30
        TemplateCacheTtlSeconds = 60
    }
}

function Get-BunTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-BunUniqueStrings {
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

function New-BunSuggestionItem {
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

function New-BunPathData {
    param(
        [string[]]$Commands = @(),
        [hashtable]$CommandDescriptions = @{},
        [string[]]$Options = @(),
        [hashtable]$ValuesByOption = @{},
        [string[]]$OptionsExpectingValue = @()
    )

    @{
        Commands              = Get-BunUniqueStrings -Items $Commands
        CommandDescriptions   = $CommandDescriptions
        Options               = Get-BunUniqueStrings -Items $Options
        ValuesByOption        = $ValuesByOption
        OptionsExpectingValue = Get-BunUniqueStrings -Items $OptionsExpectingValue
    }
}

function Get-BunCacheKey {
    param([string[]]$Path)

    $pathItems = @($Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    (($pathItems | ForEach-Object { $_.ToLowerInvariant() }) -join ' ')
}

function Get-BunExecutablePath {
    if ($script:BunCompletionCache.ExecutablePathProbed) {
        return $script:BunCompletionCache.ExecutablePath
    }

    $script:BunCompletionCache.ExecutablePathProbed = $true
    $script:BunCompletionCache.ExecutablePath = $null

    foreach ($commandName in @('bun.exe', 'bun')) {
        $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue
        if ($command) {
            $script:BunCompletionCache.ExecutablePath = $command.Source
            break
        }
    }

    $script:BunCompletionCache.ExecutablePath
}

function Invoke-BunCapture {
    param([string[]]$Arguments)

    $executablePath = Get-BunExecutablePath
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        return @()
    }

    try {
        @(& $executablePath @Arguments 2>$null)
    } catch {
        @()
    }
}

function Get-BunOptionTokensFromLine {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return @()
    }

    $tokens = foreach ($match in [regex]::Matches($Line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9\-]*)')) {
        $match.Groups[1].Value
    }

    Get-BunUniqueStrings -Items $tokens
}

function Test-BunOptionLineExpectsValue {
    param(
        [string]$Line,
        [string[]]$OptionTokens
    )

    if ([string]::IsNullOrWhiteSpace($Line) -or @($OptionTokens).Count -eq 0) {
        return $false
    }

    foreach ($token in @($OptionTokens)) {
        $escapedToken = [regex]::Escape($token)
        if ($Line -match ('{0}(?:\s*=\s*<[^>]+>|\s+<[^>]+>)' -f $escapedToken)) {
            return $true
        }
    }

    $false
}

function Add-BunPossibleValues {
    param(
        [hashtable]$ValueMap,
        [string[]]$OptionTokens,
        [string]$RawLine
    )

    if (@($OptionTokens).Count -eq 0 -or [string]::IsNullOrWhiteSpace($RawLine)) {
        return
    }

    $values = New-Object System.Collections.Generic.List[string]

    foreach ($match in [regex]::Matches($RawLine, '["'']([^"'']+)["'']')) {
        $candidate = $match.Groups[1].Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            [void]$values.Add($candidate)
        }
    }

    $candidateFragments = New-Object System.Collections.Generic.List[string]
    if ($RawLine -match '(?i)(?:one of|possible values?:|supports either|available:|valid [^:]+:)\s*(.+)$') {
        [void]$candidateFragments.Add($matches[1])
    }

    if ($RawLine -match '\(([^()]+)\)') {
        [void]$candidateFragments.Add($matches[1])
    }

    foreach ($fragment in @($candidateFragments.ToArray())) {
        foreach ($part in ($fragment -split ',|\bor\b|\band/or\b')) {
            $candidate = $part.Trim()
            $candidate = $candidate -replace '\s*\(.*$', ''
            $candidate = $candidate -replace '^(?:default:|default is)\s*', ''
            $candidate = $candidate.Trim('''" .')

            if ([string]::IsNullOrWhiteSpace($candidate)) {
                continue
            }

            if ($candidate -match '^[A-Za-z0-9*._/@:+-]+$') {
                [void]$values.Add($candidate)
            }
        }
    }

    $uniqueValues = Get-BunUniqueStrings -Items $values.ToArray()
    foreach ($token in @($OptionTokens)) {
        if (-not $ValueMap.ContainsKey($token)) {
            $ValueMap[$token] = @()
        }

        $ValueMap[$token] = Get-BunUniqueStrings -Items ($ValueMap[$token] + $uniqueValues)
    }
}

function Get-BunParsedHelpData {
    param([string[]]$HelpLines)

    $commands = New-Object System.Collections.Generic.List[string]
    $commandDescriptions = @{}
    $options = New-Object System.Collections.Generic.List[string]
    $valuesByOption = @{}
    $optionsExpectingValue = New-Object System.Collections.Generic.List[string]
    $section = ''

    foreach ($line in @($HelpLines)) {
        if ($line -match '^\s*Commands:\s*$') {
            $section = 'commands'
            continue
        }

        if ($line -match '^\s*(Flags|Options):\s*$') {
            $section = 'options'
            continue
        }

        if ($line -match '^\s*(Examples|Arguments):\s*$') {
            $section = ''
            continue
        }

        if ($section -eq 'commands') {
            $trimmedLine = $line.Trim()
            if ($trimmedLine.StartsWith('bun ', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            if ($line -match '^\s{2,}([A-Za-z][A-Za-z0-9-]*)\b(?:\s+.+?)?\s{2,}(.+)$') {
                $commandName = $matches[1]
                $description = $matches[2].Trim()
                [void]$commands.Add($commandName)
                $commandDescriptions[$commandName] = $description
            }

            continue
        }

        if ($section -ne 'options') {
            continue
        }

        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
            continue
        }

        $optionTokens = @(Get-BunOptionTokensFromLine -Line $trimmedLine)
        if ($optionTokens.Count -eq 0) {
            continue
        }

        foreach ($token in $optionTokens) {
            [void]$options.Add($token)
        }

        if (Test-BunOptionLineExpectsValue -Line $trimmedLine -OptionTokens $optionTokens) {
            foreach ($token in $optionTokens) {
                [void]$optionsExpectingValue.Add($token)
            }
        }

        Add-BunPossibleValues -ValueMap $valuesByOption -OptionTokens $optionTokens -RawLine $trimmedLine
    }

    New-BunPathData `
        -Commands ($commands.ToArray()) `
        -CommandDescriptions $commandDescriptions `
        -Options ($options.ToArray()) `
        -ValuesByOption $valuesByOption `
        -OptionsExpectingValue ($optionsExpectingValue.ToArray())
}

function Get-BunHelpData {
    param([string[]]$Path)

    $cacheKey = Get-BunCacheKey -Path $Path
    if ($script:BunCompletionCache.HelpDataByPath.ContainsKey($cacheKey)) {
        return $script:BunCompletionCache.HelpDataByPath[$cacheKey]
    }

    $commands = @()
    $commandDescriptions = @{}
    if ($script:BunCompletionCache.StaticTree.ContainsKey($cacheKey)) {
        $commands = @($script:BunCompletionCache.StaticTree[$cacheKey])
    }

    if ($script:BunCompletionCache.StaticDescriptions.ContainsKey($cacheKey)) {
        foreach ($entry in $script:BunCompletionCache.StaticDescriptions[$cacheKey].GetEnumerator()) {
            $commandDescriptions[$entry.Key] = $entry.Value
        }
    }

    $helpData = New-BunPathData -Commands $commands -CommandDescriptions $commandDescriptions

    $helpLines = if (@($Path).Count -eq 0) {
        Invoke-BunCapture -Arguments @('--help')
    } else {
        Invoke-BunCapture -Arguments (@($Path) + '--help')
    }

    if (@($helpLines).Count -gt 0) {
        $parsedData = Get-BunParsedHelpData -HelpLines $helpLines

        foreach ($command in @($parsedData.Commands)) {
            if (-not [string]::IsNullOrWhiteSpace($command)) {
                $helpData.Commands += $command
            }
        }

        foreach ($entry in $parsedData.CommandDescriptions.GetEnumerator()) {
            $helpData.CommandDescriptions[$entry.Key] = $entry.Value
        }

        $helpData.Options += $parsedData.Options
        $helpData.OptionsExpectingValue += $parsedData.OptionsExpectingValue

        foreach ($entry in $parsedData.ValuesByOption.GetEnumerator()) {
            if (-not $helpData.ValuesByOption.ContainsKey($entry.Key)) {
                $helpData.ValuesByOption[$entry.Key] = @()
            }

            $helpData.ValuesByOption[$entry.Key] = Get-BunUniqueStrings -Items ($helpData.ValuesByOption[$entry.Key] + $entry.Value)
        }
    }

    $helpData.Commands = Get-BunUniqueStrings -Items $helpData.Commands
    $helpData.Options = Get-BunUniqueStrings -Items $helpData.Options
    $helpData.OptionsExpectingValue = Get-BunUniqueStrings -Items $helpData.OptionsExpectingValue

    $script:BunCompletionCache.HelpDataByPath[$cacheKey] = $helpData
    $helpData
}

function Find-BunNearestPackageJsonPath {
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

function Get-BunPackageJsonData {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) {
        return $null
    }

    $cacheEntry = if ($script:BunCompletionCache.PackageJsonByPath.ContainsKey($Path)) {
        $script:BunCompletionCache.PackageJsonByPath[$Path]
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

    $script:BunCompletionCache.PackageJsonByPath[$Path] = @{
        LastWriteTimeUtc = $item.LastWriteTimeUtc
        Data             = $data
    }

    $data
}

function Get-BunScriptNames {
    $packageJsonPath = Find-BunNearestPackageJsonPath
    if ([string]::IsNullOrWhiteSpace($packageJsonPath)) {
        return @()
    }

    $packageData = Get-BunPackageJsonData -Path $packageJsonPath
    if ($null -eq $packageData -or -not $packageData.ContainsKey('scripts')) {
        return @()
    }

    $scripts = $packageData['scripts']
    if ($scripts -isnot [System.Collections.IDictionary]) {
        return @()
    }

    @($scripts.Keys | Sort-Object -Unique)
}

function Get-BunWorkspaceNames {
    $packageJsonPath = Find-BunNearestPackageJsonPath
    if ([string]::IsNullOrWhiteSpace($packageJsonPath)) {
        return @()
    }

    $projectRoot = Split-Path -Path $packageJsonPath -Parent
    $cacheKey = $projectRoot.ToLowerInvariant()

    if ($script:BunCompletionCache.WorkspaceNamesByRoot.ContainsKey($cacheKey)) {
        $cacheEntry = $script:BunCompletionCache.WorkspaceNamesByRoot[$cacheKey]
        $cacheAge = (Get-Date) - $cacheEntry.UpdatedAt
        if ($cacheAge.TotalSeconds -lt $script:BunCompletionCache.WorkspaceCacheTtlSeconds) {
            return $cacheEntry.Values
        }
    }

    $packageData = Get-BunPackageJsonData -Path $packageJsonPath
    if ($null -eq $packageData -or -not $packageData.ContainsKey('workspaces')) {
        $script:BunCompletionCache.WorkspaceNamesByRoot[$cacheKey] = @{
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

            $workspaceData = Get-BunPackageJsonData -Path $workspacePackagePath
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
    $script:BunCompletionCache.WorkspaceNamesByRoot[$cacheKey] = @{
        UpdatedAt = Get-Date
        Values    = $values
    }

    $values
}

function Add-BunPropertyPaths {
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
            Add-BunPropertyPaths -Value $Value[$key] -Prefix $path -Depth ($Depth - 1) -Results $Results
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
                Add-BunPropertyPaths -Value $item -Prefix $indexedPrefix -Depth ($Depth - 1) -Results $Results
            }

            $index++
        }
    }
}

function Get-BunPackagePropertyPaths {
    $packageJsonPath = Find-BunNearestPackageJsonPath
    if ([string]::IsNullOrWhiteSpace($packageJsonPath)) {
        return @()
    }

    $packageData = Get-BunPackageJsonData -Path $packageJsonPath
    if ($null -eq $packageData) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[string]
    Add-BunPropertyPaths -Value $packageData -Prefix '' -Depth 4 -Results $results
    Get-BunUniqueStrings -Items $results
}

function Get-BunNodeModulesRoot {
    $packageJsonPath = Find-BunNearestPackageJsonPath
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

function Get-BunInstalledPackageNames {
    $nodeModulesPath = Get-BunNodeModulesRoot
    if ([string]::IsNullOrWhiteSpace($nodeModulesPath)) {
        return @()
    }

    $cacheKey = $nodeModulesPath.ToLowerInvariant()
    if ($script:BunCompletionCache.NodeModulesByRoot.ContainsKey($cacheKey)) {
        $cacheEntry = $script:BunCompletionCache.NodeModulesByRoot[$cacheKey]
        $cacheAge = (Get-Date) - $cacheEntry.UpdatedAt
        if ($cacheAge.TotalSeconds -lt $script:BunCompletionCache.NodeModulesCacheTtlSeconds) {
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
    $script:BunCompletionCache.NodeModulesByRoot[$cacheKey] = @{
        UpdatedAt = Get-Date
        Values    = $values
    }

    $values
}

function Get-BunManifestPackageNames {
    $packageJsonPath = Find-BunNearestPackageJsonPath
    if ([string]::IsNullOrWhiteSpace($packageJsonPath)) {
        return @()
    }

    $packageData = Get-BunPackageJsonData -Path $packageJsonPath
    if ($null -eq $packageData) {
        return @()
    }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($field in @('dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies')) {
        if (-not $packageData.ContainsKey($field)) {
            continue
        }

        $value = $packageData[$field]
        if ($value -is [System.Collections.IDictionary]) {
            foreach ($name in @($value.Keys)) {
                [void]$names.Add([string]$name)
            }
        }
    }

    if ($packageData.ContainsKey('trustedDependencies')) {
        foreach ($name in @($packageData['trustedDependencies'])) {
            if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
                [void]$names.Add([string]$name)
            }
        }
    }

    Get-BunUniqueStrings -Items $names
}

function Get-BunKnownPackageNames {
    Get-BunUniqueStrings -Items ((Get-BunManifestPackageNames) + (Get-BunInstalledPackageNames))
}

function Get-BunNodeModulesBinNames {
    $nodeModulesPath = Get-BunNodeModulesRoot
    if ([string]::IsNullOrWhiteSpace($nodeModulesPath)) {
        return @()
    }

    $binPath = Join-Path -Path $nodeModulesPath -ChildPath '.bin'
    if (-not (Test-Path -LiteralPath $binPath -PathType Container)) {
        return @()
    }

    $names = foreach ($item in @(Get-ChildItem -LiteralPath $binPath -File -ErrorAction SilentlyContinue)) {
        if ($item.BaseName.EndsWith('.cmd', [System.StringComparison]::OrdinalIgnoreCase)) {
            [System.IO.Path]::GetFileNameWithoutExtension($item.BaseName)
        } elseif ($item.Extension -in @('.cmd', '.ps1', '.psm1', '.exe')) {
            $item.BaseName
        } else {
            $item.Name
        }
    }

    Get-BunUniqueStrings -Items $names
}

function Get-BunCreateTemplateNames {
    $currentRoot = (Get-Location).ProviderPath
    $cacheKey = $currentRoot.ToLowerInvariant()

    if ($script:BunCompletionCache.TemplateNamesByRoot.ContainsKey($cacheKey)) {
        $cacheEntry = $script:BunCompletionCache.TemplateNamesByRoot[$cacheKey]
        $cacheAge = (Get-Date) - $cacheEntry.UpdatedAt
        if ($cacheAge.TotalSeconds -lt $script:BunCompletionCache.TemplateCacheTtlSeconds) {
            return $cacheEntry.Values
        }
    }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($basePath in @(
            (Join-Path -Path $HOME -ChildPath '.bun-create'),
            (Join-Path -Path $currentRoot -ChildPath '.bun-create')
        )) {
        if (-not (Test-Path -LiteralPath $basePath -PathType Container)) {
            continue
        }

        foreach ($item in @(Get-ChildItem -LiteralPath $basePath -Directory -ErrorAction SilentlyContinue)) {
            [void]$names.Add($item.Name)
        }
    }

    $values = @($names | Sort-Object -Unique)
    $script:BunCompletionCache.TemplateNamesByRoot[$cacheKey] = @{
        UpdatedAt = Get-Date
        Values    = $values
    }

    $values
}

function Get-BunQuoteCharacter {
    param([string]$InputText)

    if ([string]::IsNullOrEmpty($InputText)) {
        return $null
    }

    if ($InputText.StartsWith('"')) {
        return '"'
    }

    if ($InputText.StartsWith("'")) {
        return "'"
    }

    $null
}

function Remove-BunOuterQuotes {
    param([string]$InputText)

    if ([string]::IsNullOrEmpty($InputText)) {
        return ''
    }

    if ($InputText.Length -ge 2) {
        if (($InputText.StartsWith('"') -and $InputText.EndsWith('"')) -or
            ($InputText.StartsWith("'") -and $InputText.EndsWith("'"))) {
            return $InputText.Substring(1, $InputText.Length - 2)
        }
    }

    $InputText.Trim('"', "'")
}

function ConvertTo-BunQuotedValue {
    param(
        [string]$Value,
        [string]$QuoteCharacter
    )

    if ([string]::IsNullOrWhiteSpace($QuoteCharacter)) {
        if ($Value -match '\s') {
            return '"' + ($Value -replace '"', '\"') + '"'
        }

        return $Value
    }

    if ($QuoteCharacter -eq "'") {
        return "'" + ($Value -replace "'", "''") + "'"
    }

    '"' + ($Value -replace '"', '\"') + '"'
}

function Get-BunPathSuggestions {
    param(
        [string]$InputText,
        [switch]$DirectoryOnly,
        [string[]]$PreferredExtensions = @(),
        [string]$AttachedPrefix = ''
    )

    $text = if ($null -eq $InputText) { '' } else { $InputText }
    $quoteCharacter = Get-BunQuoteCharacter -InputText $text
    $trimmedInput = Remove-BunOuterQuotes -InputText $text

    if ([string]::IsNullOrWhiteSpace($trimmedInput)) {
        $parent = '.'
        $leaf = ''
    } elseif (Test-Path -LiteralPath $trimmedInput -PathType Container) {
        $parent = $trimmedInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $trimmedInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $trimmedInput -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $preferredMap = @{}
    foreach ($extension in @($PreferredExtensions)) {
        if ([string]::IsNullOrWhiteSpace($extension)) {
            continue
        }

        $preferredMap[$extension.ToLowerInvariant()] = $true
    }

    $items = @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)
    if ($DirectoryOnly) {
        $items = @($items | Where-Object { $_.PSIsContainer })
    }

    $sortedItems = @(
        $items | Sort-Object `
            @{ Expression = { -not $_.PSIsContainer } }, `
            @{ Expression = {
                    if ($_.PSIsContainer) {
                        0
                    } elseif ($preferredMap.ContainsKey($_.Extension.ToLowerInvariant())) {
                        0
                    } else {
                        1
                    }
                }
            }, `
            @{ Expression = { $_.Name } }
    )

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($item in $sortedItems) {
        $completionText = if (-not [System.IO.Path]::IsPathRooted($trimmedInput)) {
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

        if (-not [string]::IsNullOrWhiteSpace($quoteCharacter) -or ($completionText -match '\s')) {
            $completionText = ConvertTo-BunQuotedValue -Value $completionText -QuoteCharacter $quoteCharacter
        }

        $toolTip = if ($item.PSIsContainer) {
            'Directory: {0}' -f $item.FullName
        } else {
            $item.FullName
        }

        $suggestion = New-BunSuggestionItem -CompletionText ($AttachedPrefix + $completionText) -ToolTip $toolTip
        if ($suggestion) {
            [void]$results.Add($suggestion)
        }
    }

    @($results.ToArray())
}

function Get-BunStaticOptionsExpectingValue {
    param([string[]]$Path)

    $pathKey = Get-BunCacheKey -Path $Path
    $rootOptions = @(
        '--preload', '-r', '--require', '--import', '--inspect', '--inspect-wait', '--inspect-brk',
        '--cpu-prof-name', '--cpu-prof-dir', '--heap-prof-name', '--heap-prof-dir', '--install',
        '--eval', '-e', '--print', '-p', '--port', '--conditions', '--fetch-preconnect',
        '--max-http-header-size', '--dns-result-order', '--title', '--unhandled-rejections',
        '--console-depth', '--user-agent', '--cron-title', '--cron-period', '--env-file',
        '--cwd', '--config', '-c'
    )

    switch ($pathKey) {
        '' {
            return $rootOptions
        }
        'run' {
            return Get-BunUniqueStrings -Items ($rootOptions + @(
                    '--shell', '--main-fields', '--extension-order', '--tsconfig-override',
                    '--define', '-d', '--drop', '--loader', '-l', '--jsx-factory',
                    '--jsx-fragment', '--jsx-import-source', '--jsx-runtime'
                ))
        }
        'build' {
            return @(
                '--compile-exec-argv', '--compile-executable-path', '--target', '--outdir', '--outfile',
                '--metafile', '--metafile-md', '--sourcemap', '--banner', '--footer', '--format',
                '--root', '--public-path', '--external', '-e', '--allow-unresolved', '--packages',
                '--entry-naming', '--chunk-naming', '--asset-naming', '--conditions', '--env',
                '--windows-icon', '--windows-title', '--windows-publisher', '--windows-version',
                '--windows-description', '--windows-copyright'
            )
        }
        'test' {
            return @(
                '--timeout', '--rerun-each', '--retry', '--seed', '--coverage-reporter', '--coverage-dir',
                '--bail', '-t', '--test-name-pattern', '--reporter', '--reporter-outfile',
                '--max-concurrency', '--path-ignore-patterns'
            )
        }
        'install' { return @('--ca', '--cafile', '--cache-dir', '--cwd', '--backend', '--registry', '--concurrent-scripts', '--network-concurrency', '--omit', '--linker', '--minimum-release-age', '--cpu', '--os', '--config', '-c') }
        'add'     { return @('--ca', '--cafile', '--cache-dir', '--cwd', '--backend', '--registry', '--concurrent-scripts', '--network-concurrency', '--omit', '--linker', '--minimum-release-age', '--cpu', '--os', '--config', '-c') }
        'remove'  { return @('--ca', '--cafile', '--cache-dir', '--cwd', '--backend', '--registry', '--concurrent-scripts', '--network-concurrency', '--omit', '--linker', '--minimum-release-age', '--cpu', '--os', '--config', '-c') }
        'update'  { return @('--ca', '--cafile', '--cache-dir', '--cwd', '--backend', '--registry', '--concurrent-scripts', '--network-concurrency', '--omit', '--linker', '--minimum-release-age', '--cpu', '--os', '--config', '-c', '--filter') }
        'link'    { return @('--ca', '--cafile', '--cache-dir', '--cwd', '--backend', '--registry', '--concurrent-scripts', '--network-concurrency', '--omit', '--linker', '--minimum-release-age', '--cpu', '--os', '--config', '-c') }
        'publish' {
            return @(
                '--ca', '--cafile', '--cache-dir', '--cwd', '--backend', '--registry', '--concurrent-scripts',
                '--network-concurrency', '--omit', '--linker', '--minimum-release-age', '--cpu', '--os',
                '--config', '-c', '--access', '--tag', '--otp', '--auth-type', '--gzip-level'
            )
        }
        'patch' {
            return @(
                '--ca', '--cafile', '--cache-dir', '--cwd', '--backend', '--registry', '--concurrent-scripts',
                '--network-concurrency', '--omit', '--linker', '--minimum-release-age', '--cpu', '--os',
                '--config', '-c', '--patches-dir'
            )
        }
        'outdated' {
            return @(
                '--ca', '--cafile', '--cache-dir', '--cwd', '--backend', '--registry', '--concurrent-scripts',
                '--network-concurrency', '--omit', '--linker', '--minimum-release-age', '--cpu', '--os',
                '--config', '-c', '--filter', '-F'
            )
        }
        'info' {
            return @(
                '--ca', '--cafile', '--cache-dir', '--cwd', '--backend', '--registry', '--concurrent-scripts',
                '--network-concurrency', '--omit', '--linker', '--minimum-release-age', '--cpu', '--os',
                '--config', '-c'
            )
        }
        'audit' {
            return @('--audit-level', '--ignore')
        }
        'why' {
            return @('--depth')
        }
        'init' {
            return @('--react')
        }
        'x' {
            return @('-p', '--package')
        }
        'pm pack' {
            return @('--destination', '--filename', '--gzip-level')
        }
        'pm version' {
            return @('--message', '-m', '--preid')
        }
        default {
            return @()
        }
    }
}

function Get-BunPathOptionKind {
    param([string]$Option)

    if ([string]::IsNullOrWhiteSpace($Option)) {
        return $null
    }

    switch ($Option.ToLowerInvariant()) {
        '--cwd' { 'directory'; break }
        '--cpu-prof-dir' { 'directory'; break }
        '--heap-prof-dir' { 'directory'; break }
        '--outdir' { 'directory'; break }
        '--coverage-dir' { 'directory'; break }
        '--destination' { 'directory'; break }
        '--cache-dir' { 'directory'; break }
        '--patches-dir' { 'directory'; break }
        '--config' { 'file'; break }
        '-c' { 'file'; break }
        '--env-file' { 'file'; break }
        '--preload' { 'file'; break }
        '-r' { 'file'; break }
        '--require' { 'file'; break }
        '--import' { 'file'; break }
        '--tsconfig-override' { 'file'; break }
        '--outfile' { 'file'; break }
        '--metafile' { 'file'; break }
        '--metafile-md' { 'file'; break }
        '--windows-icon' { 'file'; break }
        '--cafile' { 'file'; break }
        '--reporter-outfile' { 'file'; break }
        '--filename' { 'file'; break }
        default { $null }
    }
}

function Get-BunOptionExpectsValue {
    param(
        [string[]]$Path,
        [string]$Option
    )

    if ([string]::IsNullOrWhiteSpace($Option) -or -not $Option.StartsWith('-')) {
        return $false
    }

    $staticOptions = Get-BunStaticOptionsExpectingValue -Path $Path
    foreach ($candidate in @($staticOptions)) {
        if ($candidate.Equals($Option, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $helpData = Get-BunHelpData -Path $Path
    foreach ($candidate in @($helpData.OptionsExpectingValue)) {
        if ($candidate.Equals($Option, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $false
}

function Find-BunSubcommand {
    param(
        [string[]]$Path,
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $helpData = Get-BunHelpData -Path $Path
    foreach ($command in @($helpData.Commands)) {
        if ([string]::IsNullOrWhiteSpace($command)) {
            continue
        }

        if ($command.Equals($Token, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $command
        }
    }

    $pathKey = Get-BunCacheKey -Path $Path
    if ($script:BunCompletionCache.StaticAliases.ContainsKey($pathKey)) {
        foreach ($entry in $script:BunCompletionCache.StaticAliases[$pathKey].GetEnumerator()) {
            if ($entry.Key.Equals($Token, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $entry.Value
            }
        }
    }

    $null
}

function Get-BunEffectiveWordToComplete {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    if ($CommandAst.CommandElements.Count -gt 0) {
        $lastElement = $CommandAst.CommandElements[$CommandAst.CommandElements.Count - 1]
        if ($CursorPosition -gt $lastElement.Extent.EndOffset) {
            return ''
        }
    }

    if (-not [string]::IsNullOrEmpty($WordToComplete)) {
        return $WordToComplete
    }

    if ($CommandAst.CommandElements.Count -eq 0) {
        return $WordToComplete
    }

    $lastElement = $CommandAst.CommandElements[$CommandAst.CommandElements.Count - 1]
    if ($lastElement.Extent.EndOffset -ne $CursorPosition) {
        return $WordToComplete
    }

    Get-BunTokenText -Element $lastElement
}

function Get-BunOptionAssignmentContext {
    param([string]$WordToComplete)

    if ($WordToComplete -match '^(--?[A-Za-z0-9][A-Za-z0-9\-]*)=(.*)$') {
        return @{
            Option      = $matches[1]
            ValuePrefix = $matches[2]
        }
    }

    $null
}

function Get-BunCommandContext {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $hasTrailingSpace = $false
    if ($CommandAst.CommandElements.Count -gt 0) {
        $lastElement = $CommandAst.CommandElements[$CommandAst.CommandElements.Count - 1]
        $hasTrailingSpace = $CursorPosition -gt $lastElement.Extent.EndOffset
    }

    $tokens = New-Object System.Collections.Generic.List[string]
    for ($index = 1; $index -lt $CommandAst.CommandElements.Count; $index++) {
        $element = $CommandAst.CommandElements[$index]
        if ($element.Extent.StartOffset -ge $CursorPosition) {
            continue
        }

        $token = Get-BunTokenText -Element $element
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        [void]$tokens.Add($token)
    }

    $tokensBeforeCurrent = @()
    $previousToken = $null
    if ($hasTrailingSpace) {
        $tokensBeforeCurrent = $tokens.ToArray()
        if ($tokens.Count -gt 0) {
            $previousToken = $tokens[$tokens.Count - 1]
        }
    } elseif ($tokens.Count -gt 0) {
        if ($tokens.Count -gt 1) {
            $tokensBeforeCurrent = $tokens.GetRange(0, $tokens.Count - 1).ToArray()
            $previousToken = $tokens[$tokens.Count - 2]
        }
    }

    $path = New-Object System.Collections.Generic.List[string]
    $positionals = New-Object System.Collections.Generic.List[string]
    $afterDoubleDash = $false
    $expectingValueFor = $null

    foreach ($token in @($tokensBeforeCurrent)) {
        if ($afterDoubleDash) {
            [void]$positionals.Add($token)
            continue
        }

        if ($null -ne $expectingValueFor) {
            $expectingValueFor = $null
            continue
        }

        if ($token -eq '--') {
            $afterDoubleDash = $true
            continue
        }

        if ($token -match '^(--?[A-Za-z0-9][A-Za-z0-9\-]*)=') {
            continue
        }

        if ($token.StartsWith('-')) {
            if (Get-BunOptionExpectsValue -Path $path.ToArray() -Option $token) {
                $expectingValueFor = $token
            }

            continue
        }

        $nextCommand = if ($positionals.Count -eq 0) {
            Find-BunSubcommand -Path $path.ToArray() -Token $token
        } else {
            $null
        }

        if ($nextCommand) {
            [void]$path.Add($nextCommand)
        } else {
            [void]$positionals.Add($token)
        }
    }

    if (-not $hasTrailingSpace -and $expectingValueFor) {
        $previousToken = $expectingValueFor
    }

    @{
        Path            = [string[]]@($path.ToArray())
        Positionals     = [string[]]@($positionals.ToArray())
        PreviousToken   = $previousToken
        AfterDoubleDash = $afterDoubleDash
        HasTrailingSpace = $hasTrailingSpace
    }
}

function Get-BunCommandSuggestions {
    param([string[]]$Path)

    $helpData = Get-BunHelpData -Path $Path
    $items = New-Object System.Collections.Generic.List[object]

    foreach ($command in @($helpData.Commands)) {
        if ([string]::IsNullOrWhiteSpace($command)) {
            continue
        }

        $toolTip = if ($helpData.CommandDescriptions.ContainsKey($command)) {
            $helpData.CommandDescriptions[$command]
        } else {
            $command
        }

        $item = New-BunSuggestionItem -CompletionText $command -ToolTip $toolTip
        if ($item) {
            [void]$items.Add($item)
        }
    }

    @($items.ToArray())
}

function Get-BunOptionSuggestions {
    param([string[]]$Path)

    $helpData = Get-BunHelpData -Path $Path
    $items = New-Object System.Collections.Generic.List[object]

    foreach ($option in @($helpData.Options)) {
        $item = New-BunSuggestionItem -CompletionText $option -ToolTip $option -ResultType 'ParameterName'
        if ($item) {
            [void]$items.Add($item)
        }
    }

    @($items.ToArray())
}

function Get-BunStaticOptionValueSuggestions {
    param(
        [string[]]$Path,
        [string]$Option,
        [string]$AssignmentPrefix = ''
    )

    $items = New-Object System.Collections.Generic.List[object]
    $pathKey = Get-BunCacheKey -Path $Path
    $lookupKeys = @()

    if (-not [string]::IsNullOrWhiteSpace($pathKey)) {
        $lookupKeys += ('{0}|{1}' -f $pathKey, $Option.ToLowerInvariant())
    }

    $lookupKeys += $Option.ToLowerInvariant()

    foreach ($lookupKey in @($lookupKeys)) {
        if (-not $script:BunCompletionCache.StaticOptionValues.ContainsKey($lookupKey)) {
            continue
        }

        foreach ($value in @($script:BunCompletionCache.StaticOptionValues[$lookupKey])) {
            $item = New-BunSuggestionItem -CompletionText ($AssignmentPrefix + $value) -ToolTip ('{0} value' -f $Option)
            if ($item) {
                [void]$items.Add($item)
            }
        }
    }

    @($items.ToArray())
}

function Get-BunHelpOptionValueSuggestions {
    param(
        [string[]]$Path,
        [string]$Option,
        [string]$AssignmentPrefix = ''
    )

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($helpPath in @($Path, @())) {
        $helpData = Get-BunHelpData -Path $helpPath
        if (-not $helpData.ValuesByOption.ContainsKey($Option)) {
            continue
        }

        foreach ($value in @($helpData.ValuesByOption[$Option])) {
            $item = New-BunSuggestionItem -CompletionText ($AssignmentPrefix + $value) -ToolTip ('{0} value' -f $Option)
            if ($item) {
                [void]$items.Add($item)
            }
        }
    }

    @($items.ToArray())
}

function Get-BunOptionValueSuggestions {
    param(
        [string[]]$Path,
        [string[]]$Positionals,
        [string]$Option,
        [string]$WordToComplete,
        [string]$AssignmentPrefix = ''
    )

    $items = New-Object System.Collections.Generic.List[object]
    $normalizedOption = if ([string]::IsNullOrWhiteSpace($Option)) { '' } else { $Option.ToLowerInvariant() }
    $pathKey = Get-BunCacheKey -Path $Path

    foreach ($item in @(Get-BunHelpOptionValueSuggestions -Path $Path -Option $Option -AssignmentPrefix $AssignmentPrefix)) {
        [void]$items.Add($item)
    }

    foreach ($item in @(Get-BunStaticOptionValueSuggestions -Path $Path -Option $Option -AssignmentPrefix $AssignmentPrefix)) {
        [void]$items.Add($item)
    }

    switch ($pathKey) {
        'run' {
            if ($normalizedOption -in @('--filter', '-f')) {
                foreach ($workspace in @(Get-BunWorkspaceNames)) {
                    $item = New-BunSuggestionItem -CompletionText ($AssignmentPrefix + $workspace) -ToolTip 'workspace name'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            }
        }
        'update' {
            if ($normalizedOption -eq '--filter') {
                foreach ($workspace in @(Get-BunWorkspaceNames)) {
                    $item = New-BunSuggestionItem -CompletionText ($AssignmentPrefix + $workspace) -ToolTip 'workspace filter'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            }
        }
        'outdated' {
            if ($normalizedOption -in @('--filter', '-f')) {
                foreach ($workspace in @(Get-BunWorkspaceNames)) {
                    $item = New-BunSuggestionItem -CompletionText ($AssignmentPrefix + $workspace) -ToolTip 'workspace filter'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            }
        }
    }

    $pathOptionKind = Get-BunPathOptionKind -Option $Option
    if ($pathOptionKind -eq 'directory') {
        foreach ($item in @(Get-BunPathSuggestions -InputText $WordToComplete -DirectoryOnly -AttachedPrefix $AssignmentPrefix)) {
            [void]$items.Add($item)
        }
    } elseif ($pathOptionKind -eq 'file') {
        $preferredExtensions = switch ($normalizedOption) {
            '--config' { @('.toml') }
            '-c' { @('.toml') }
            '--env-file' { @('.env') }
            '--preload' { @('.js', '.mjs', '.cjs', '.ts', '.tsx', '.jsx') }
            '-r' { @('.js', '.mjs', '.cjs', '.ts', '.tsx', '.jsx') }
            '--require' { @('.js', '.mjs', '.cjs', '.ts', '.tsx', '.jsx') }
            '--import' { @('.js', '.mjs', '.cjs', '.ts', '.tsx', '.jsx') }
            '--tsconfig-override' { @('.json') }
            '--reporter-outfile' { @('.xml') }
            '--windows-icon' { @('.ico') }
            '--filename' { @('.tgz') }
            default { @() }
        }

        foreach ($item in @(Get-BunPathSuggestions -InputText $WordToComplete -PreferredExtensions $preferredExtensions -AttachedPrefix $AssignmentPrefix)) {
            [void]$items.Add($item)
        }
    }

    @($items.ToArray())
}

function Get-BunPositionalSuggestions {
    param(
        [string[]]$Path,
        [string[]]$Positionals,
        [bool]$AfterDoubleDash
    )

    if ($AfterDoubleDash) {
        return @()
    }

    $items = New-Object System.Collections.Generic.List[object]
    $pathKey = Get-BunCacheKey -Path $Path
    $positionIndex = @($Positionals).Count
    $sourceExtensions = @('.js', '.mjs', '.cjs', '.jsx', '.ts', '.mts', '.cts', '.tsx', '.json')
    $tarballExtensions = @('.tgz', '.tar.gz')

    switch ($pathKey) {
        '' {
            foreach ($scriptName in @(Get-BunScriptNames)) {
                $item = New-BunSuggestionItem -CompletionText $scriptName -ToolTip 'package.json script'
                if ($item) {
                    [void]$items.Add($item)
                }
            }

            foreach ($item in @(Get-BunPathSuggestions -InputText '' -PreferredExtensions $sourceExtensions)) {
                [void]$items.Add($item)
            }
        }
        'run' {
            if ($positionIndex -eq 0) {
                foreach ($scriptName in @(Get-BunScriptNames)) {
                    $item = New-BunSuggestionItem -CompletionText $scriptName -ToolTip 'package.json script'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }

                foreach ($binName in @(Get-BunNodeModulesBinNames)) {
                    $item = New-BunSuggestionItem -CompletionText $binName -ToolTip 'local package binary'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }

                foreach ($item in @(Get-BunPathSuggestions -InputText '' -PreferredExtensions $sourceExtensions)) {
                    [void]$items.Add($item)
                }
            }
        }
        'build' {
            foreach ($item in @(Get-BunPathSuggestions -InputText '' -PreferredExtensions $sourceExtensions)) {
                [void]$items.Add($item)
            }
        }
        'test' {
            foreach ($item in @(Get-BunPathSuggestions -InputText '' -PreferredExtensions $sourceExtensions)) {
                [void]$items.Add($item)
            }
        }
        'init' {
            if ($positionIndex -eq 0) {
                foreach ($item in @(Get-BunPathSuggestions -InputText '' -DirectoryOnly)) {
                    [void]$items.Add($item)
                }
            }
        }
        'create' {
            if ($positionIndex -eq 0) {
                foreach ($templateName in @(Get-BunCreateTemplateNames)) {
                    $item = New-BunSuggestionItem -CompletionText $templateName -ToolTip 'local bun create template'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }

                foreach ($item in @(Get-BunPathSuggestions -InputText '' -PreferredExtensions @('.jsx', '.tsx'))) {
                    [void]$items.Add($item)
                }
            } elseif ($positionIndex -eq 1) {
                foreach ($item in @(Get-BunPathSuggestions -InputText '' -DirectoryOnly)) {
                    [void]$items.Add($item)
                }
            }
        }
        'remove' {
            foreach ($packageName in @(Get-BunKnownPackageNames)) {
                $item = New-BunSuggestionItem -CompletionText $packageName -ToolTip 'known package'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
        'update' {
            foreach ($packageName in @(Get-BunKnownPackageNames)) {
                $item = New-BunSuggestionItem -CompletionText $packageName -ToolTip 'known package'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
        'info' {
            if ($positionIndex -eq 0) {
                foreach ($packageName in @(Get-BunKnownPackageNames)) {
                    $item = New-BunSuggestionItem -CompletionText $packageName -ToolTip 'known package'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            } elseif ($positionIndex -eq 1) {
                foreach ($propertyPath in @(Get-BunPackagePropertyPaths)) {
                    $item = New-BunSuggestionItem -CompletionText $propertyPath -ToolTip 'package.json property path'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            }
        }
        'why' {
            if ($positionIndex -eq 0) {
                foreach ($packageName in @(Get-BunKnownPackageNames)) {
                    $item = New-BunSuggestionItem -CompletionText $packageName -ToolTip 'known package'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            } elseif ($positionIndex -eq 1) {
                foreach ($propertyPath in @(Get-BunPackagePropertyPaths)) {
                    $item = New-BunSuggestionItem -CompletionText $propertyPath -ToolTip 'package.json property path'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            }
        }
        'patch' {
            if ($positionIndex -eq 0) {
                foreach ($packageName in @(Get-BunKnownPackageNames)) {
                    $item = New-BunSuggestionItem -CompletionText $packageName -ToolTip 'known package'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            }
        }
        'outdated' {
            if ($positionIndex -eq 0) {
                foreach ($workspace in @(Get-BunWorkspaceNames)) {
                    $item = New-BunSuggestionItem -CompletionText $workspace -ToolTip 'workspace filter'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }

                foreach ($packageName in @(Get-BunKnownPackageNames)) {
                    $item = New-BunSuggestionItem -CompletionText $packageName -ToolTip 'known package'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            }
        }
        'publish' {
            if ($positionIndex -eq 0) {
                foreach ($item in @(Get-BunPathSuggestions -InputText '' -PreferredExtensions $tarballExtensions)) {
                    [void]$items.Add($item)
                }
            }
        }
        'x' {
            if ($positionIndex -eq 0) {
                foreach ($binName in @(Get-BunNodeModulesBinNames)) {
                    $item = New-BunSuggestionItem -CompletionText $binName -ToolTip 'local package binary'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }

                foreach ($packageName in @(Get-BunKnownPackageNames)) {
                    $item = New-BunSuggestionItem -CompletionText $packageName -ToolTip 'known package'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            }
        }
        'pm view' {
            if ($positionIndex -eq 0) {
                foreach ($packageName in @(Get-BunKnownPackageNames)) {
                    $item = New-BunSuggestionItem -CompletionText $packageName -ToolTip 'known package'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            }
        }
        'pm trust' {
            foreach ($packageName in @(Get-BunKnownPackageNames)) {
                $item = New-BunSuggestionItem -CompletionText $packageName -ToolTip 'known package'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
        'pm version' {
            if ($positionIndex -eq 0) {
                foreach ($value in @('patch', 'minor', 'major', 'prepatch', 'preminor', 'premajor', 'prerelease', 'from-git')) {
                    $item = New-BunSuggestionItem -CompletionText $value -ToolTip 'version increment'
                    if ($item) {
                        [void]$items.Add($item)
                    }
                }
            }
        }
        'pm pkg get' {
            foreach ($propertyPath in @(Get-BunPackagePropertyPaths)) {
                $item = New-BunSuggestionItem -CompletionText $propertyPath -ToolTip 'package.json property path'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
        'pm pkg delete' {
            foreach ($propertyPath in @(Get-BunPackagePropertyPaths)) {
                $item = New-BunSuggestionItem -CompletionText $propertyPath -ToolTip 'package.json property path'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
        'pm pkg set' {
            foreach ($propertyPath in @(Get-BunPackagePropertyPaths)) {
                $item = New-BunSuggestionItem -CompletionText ('{0}=' -f $propertyPath) -ToolTip 'package.json property assignment'
                if ($item) {
                    [void]$items.Add($item)
                }
            }
        }
    }

    @($items.ToArray())
}

function ConvertTo-BunCompletionResults {
    param(
        [object[]]$Items,
        [string]$WordToComplete
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($Items)) {
        if ($null -eq $item -or [string]::IsNullOrWhiteSpace($item.CompletionText)) {
            continue
        }

        if (-not [string]::IsNullOrEmpty($WordToComplete) -and $item.CompletionText -notlike "$WordToComplete*") {
            continue
        }

        if (-not $seen.Add($item.CompletionText)) {
            continue
        }

        [System.Management.Automation.CompletionResult]::new(
            $item.CompletionText,
            $item.CompletionText,
            [System.Management.Automation.CompletionResultType]::$($item.ResultType),
            $item.ToolTip
        )
    }
}

function Complete-Bun {
    param($wordToComplete, $commandAst, $cursorPosition)

    $effectiveWordToComplete = Get-BunEffectiveWordToComplete `
        -WordToComplete $wordToComplete `
        -CommandAst $commandAst `
        -CursorPosition $cursorPosition

    $context = Get-BunCommandContext `
        -WordToComplete $effectiveWordToComplete `
        -CommandAst $commandAst `
        -CursorPosition $cursorPosition

    $path = $context.Path
    $positionals = $context.Positionals
    $previousToken = $context.PreviousToken
    $assignmentContext = Get-BunOptionAssignmentContext -WordToComplete $effectiveWordToComplete

    if ($assignmentContext -and (Get-BunOptionExpectsValue -Path $path -Option $assignmentContext.Option)) {
        $items = Get-BunOptionValueSuggestions `
            -Path $path `
            -Positionals $positionals `
            -Option $assignmentContext.Option `
            -WordToComplete $assignmentContext.ValuePrefix `
            -AssignmentPrefix ('{0}=' -f $assignmentContext.Option)

        ConvertTo-BunCompletionResults -Items $items -WordToComplete $effectiveWordToComplete
        return
    }

    if ($previousToken -and (Get-BunOptionExpectsValue -Path $path -Option $previousToken)) {
        $items = Get-BunOptionValueSuggestions `
            -Path $path `
            -Positionals $positionals `
            -Option $previousToken `
            -WordToComplete $effectiveWordToComplete

        ConvertTo-BunCompletionResults -Items $items -WordToComplete $effectiveWordToComplete
        return
    }

    $items = New-Object System.Collections.Generic.List[object]

    if (-not $context.AfterDoubleDash -and -not $effectiveWordToComplete.StartsWith('-')) {
        if (@($positionals).Count -eq 0) {
            foreach ($item in @(Get-BunCommandSuggestions -Path $path)) {
                [void]$items.Add($item)
            }
        }

        foreach ($item in @(Get-BunPositionalSuggestions -Path $path -Positionals $positionals -AfterDoubleDash $context.AfterDoubleDash)) {
            [void]$items.Add($item)
        }
    }

    if (-not $context.AfterDoubleDash) {
        foreach ($item in @(Get-BunOptionSuggestions -Path $path)) {
            [void]$items.Add($item)
        }
    }

    ConvertTo-BunCompletionResults -Items $items.ToArray() -WordToComplete $effectiveWordToComplete
}

Register-ArgumentCompleter -Native -CommandName 'bun', 'bun.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Bun -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
