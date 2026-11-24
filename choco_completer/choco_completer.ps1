# Chocolatey tab completion for PowerShell
# Live command help is the primary catalog. Local, read-only discovery fills package,
# source, feature, rule, and template value slots. No completion path changes state.

Set-StrictMode -Version Latest

if (-not (Get-Variable -Name ChocoCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:ChocoCompletionCache = @{
        ExecutablePath       = $null
        ExecutablePathProbed = $false
        HelpDataByPath       = @{}
        LocalData            = @{}
        LocalDataTtlSeconds  = 45
    }
}

function Get-ChocoUniqueStrings {
    param([string[]]$Items, [switch]$CaseSensitive)

    $comparer = if ($CaseSensitive) {
        [System.StringComparer]::Ordinal
    } else {
        [System.StringComparer]::OrdinalIgnoreCase
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new($comparer)
    foreach ($item in @($Items)) {
        if (-not [string]::IsNullOrWhiteSpace($item) -and $seen.Add($item)) {
            $item
        }
    }
}

function Test-ChocoArrayContains {
    param([string[]]$Items, [string]$Value)

    foreach ($item in @($Items)) {
        if ($null -ne $item -and $item.Equals($Value, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $false
}

function Test-ChocoOptionToken {
    param([string]$Token)

    -not [string]::IsNullOrEmpty($Token) -and (
        $Token.StartsWith('-') -or
        $Token.StartsWith('/')
    )
}

function New-ChocoSuggestion {
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

function New-ChocoCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ToolTip,
        [string]$ResultType = 'ParameterValue'
    )

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $CompletionText,
        $ResultType,
        $(if ([string]::IsNullOrWhiteSpace($ToolTip)) { $CompletionText } else { $ToolTip })
    )
}

function New-ChocoOptionSpec {
    param(
        [string[]]$Names,
        [string]$Description,
        [bool]$TakesValue
    )

    [pscustomobject]@{
        Names       = @(Get-ChocoUniqueStrings -Items $Names -CaseSensitive)
        Description = if ([string]::IsNullOrWhiteSpace($Description)) { 'Chocolatey option' } else { $Description.Trim() }
        TakesValue  = $TakesValue
    }
}

function Get-ChocoExecutablePath {
    if ($script:ChocoCompletionCache.ExecutablePathProbed) {
        return $script:ChocoCompletionCache.ExecutablePath
    }

    $script:ChocoCompletionCache.ExecutablePathProbed = $true
    foreach ($name in @('choco.exe', 'choco')) {
        $command = Get-Command -Name $name -CommandType Application -ErrorAction Ignore | Select-Object -First 1
        if ($command) {
            $script:ChocoCompletionCache.ExecutablePath = $command.Source
            break
        }
    }

    $script:ChocoCompletionCache.ExecutablePath
}

function Invoke-ChocoCapture {
    param(
        [string[]]$Arguments,
        [int]$TimeoutMilliseconds = 6000
    )

    $executable = Get-ChocoExecutablePath
    if ([string]::IsNullOrWhiteSpace($executable)) {
        return @()
    }

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $executable
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @($Arguments)) {
            [void]$startInfo.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) {
                return @()
            }

            $process.StandardInput.Close()
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit($TimeoutMilliseconds)) {
                try { $process.Kill($true) } catch { Write-Debug -Message $_.Exception.Message }
                return @()
            }

            $text = @(
                $stdoutTask.Result
                $stderrTask.Result
            ) -join "`n"
            $text = $text -replace '\e\[[0-9;?]*[ -/]*[@-~]', ''
            @($text -split '\r?\n' | Select-Object -First 1200)
        } finally {
            $process.Dispose()
        }
    } catch {
        @()
    }
}

function Get-ChocoCanonicalCommand {
    param([string]$Command)

    switch ($Command.ToLowerInvariant()) {
        'features'  { 'feature' }
        'find'      { 'search' }
        'setapikey' { 'apikey' }
        'sources'   { 'source' }
        'templates' { 'template' }
        default     { $Command.ToLowerInvariant() }
    }
}

function Get-ChocoStaticCommands {
    @(
        New-ChocoSuggestion -CompletionText 'apikey' -ToolTip 'Retrieves, saves, or deletes an API key for a source.'
        New-ChocoSuggestion -CompletionText 'cache' -ToolTip 'Manage the local HTTP caches used for queries.'
        New-ChocoSuggestion -CompletionText 'config' -ToolTip 'Retrieve and configure Chocolatey config settings.'
        New-ChocoSuggestion -CompletionText 'export' -ToolTip 'Export the currently installed package list.'
        New-ChocoSuggestion -CompletionText 'feature' -ToolTip 'View and configure Chocolatey features.'
        New-ChocoSuggestion -CompletionText 'features' -ToolTip 'Alias for feature.'
        New-ChocoSuggestion -CompletionText 'find' -ToolTip 'Alias for search.'
        New-ChocoSuggestion -CompletionText 'help' -ToolTip 'Display top-level help.'
        New-ChocoSuggestion -CompletionText 'info' -ToolTip 'Retrieve package information.'
        New-ChocoSuggestion -CompletionText 'install' -ToolTip 'Install packages from configured sources.'
        New-ChocoSuggestion -CompletionText 'license' -ToolTip 'Display Chocolatey license information.'
        New-ChocoSuggestion -CompletionText 'list' -ToolTip 'List local packages.'
        New-ChocoSuggestion -CompletionText 'new' -ToolTip 'Create a new package from a template.'
        New-ChocoSuggestion -CompletionText 'outdated' -ToolTip 'List outdated installed packages.'
        New-ChocoSuggestion -CompletionText 'pack' -ToolTip 'Create a nupkg from package resources.'
        New-ChocoSuggestion -CompletionText 'pin' -ToolTip 'View, add, or remove package pins.'
        New-ChocoSuggestion -CompletionText 'push' -ToolTip 'Push a nupkg to a package source.'
        New-ChocoSuggestion -CompletionText 'rule' -ToolTip 'View package validation rules.'
        New-ChocoSuggestion -CompletionText 'search' -ToolTip 'Search configured package sources.'
        New-ChocoSuggestion -CompletionText 'setapikey' -ToolTip 'Alias for apikey.'
        New-ChocoSuggestion -CompletionText 'source' -ToolTip 'View and configure package sources.'
        New-ChocoSuggestion -CompletionText 'sources' -ToolTip 'Alias for source.'
        New-ChocoSuggestion -CompletionText 'support' -ToolTip 'Display support information.'
        New-ChocoSuggestion -CompletionText 'template' -ToolTip 'View installed package templates.'
        New-ChocoSuggestion -CompletionText 'templates' -ToolTip 'Alias for template.'
        New-ChocoSuggestion -CompletionText 'uninstall' -ToolTip 'Uninstall installed packages.'
        New-ChocoSuggestion -CompletionText 'unpackself' -ToolTip 'Reinstall Chocolatey base files (deprecated).'
        New-ChocoSuggestion -CompletionText 'upgrade' -ToolTip 'Upgrade installed packages.'
    )
}

function Get-ChocoStaticSubcommands {
    param([string]$Command)

    switch ($Command) {
        'apikey'   { @('list', 'add', 'remove') }
        'cache'    { @('list', 'remove') }
        'config'   { @('list', 'get', 'set', 'unset') }
        'feature'  { @('list', 'get', 'disable', 'enable') }
        'license'  { @('info') }
        'pin'      { @('list', 'add', 'remove') }
        'rule'     { @('list', 'get') }
        'source'   { @('list', 'add', 'remove', 'disable', 'enable') }
        'template' { @('list', 'info') }
        default    { @() }
    }
}

function Get-ChocoGlobalFallbackOptions {
    @(
        New-ChocoOptionSpec @('-?', '--help', '-h') 'Print help.' $false
        New-ChocoOptionSpec @('-d', '--debug') 'Show debug output.' $false
        New-ChocoOptionSpec @('-v', '--verbose') 'Show verbose output.' $false
        New-ChocoOptionSpec @('--trace') 'Show trace output.' $false
        New-ChocoOptionSpec @('--nocolor', '--no-color') 'Disable output color.' $false
        New-ChocoOptionSpec @('--acceptlicense', '--accept-license') 'Accept license dialogs automatically.' $false
        New-ChocoOptionSpec @('-y', '--yes', '--confirm') 'Answer confirmation prompts affirmatively.' $false
        New-ChocoOptionSpec @('-f', '--force') 'Force the operation.' $false
        New-ChocoOptionSpec @('--noop', '--whatif', '--what-if') 'Do not make changes.' $false
        New-ChocoOptionSpec @('-r', '--limitoutput', '--limit-output') 'Limit output to essential information.' $false
        New-ChocoOptionSpec @('--include-headers') 'Include headers for limited output.' $false
        New-ChocoOptionSpec @('--timeout', '--execution-timeout') 'Command execution timeout in seconds.' $true
        New-ChocoOptionSpec @('-c', '--cache', '--cachelocation', '--cache-location') 'Download cache location.' $true
        New-ChocoOptionSpec @('--proxy') 'Explicit proxy location.' $true
        New-ChocoOptionSpec @('--proxy-user') 'Proxy user name.' $true
        New-ChocoOptionSpec @('--proxy-password') 'Proxy password.' $true
        New-ChocoOptionSpec @('--proxy-bypass-list') 'Proxy bypass list.' $true
        New-ChocoOptionSpec @('--proxy-bypass-on-local') 'Bypass the proxy for local addresses.' $false
        New-ChocoOptionSpec @('--log-file') 'Additional log file path.' $true
        New-ChocoOptionSpec @('--skipcompatibilitychecks', '--skip-compatibility-checks') 'Skip compatibility checks.' $false
        New-ChocoOptionSpec @('--ignore-http-cache') 'Ignore local HTTP caches for this operation.' $false
    )
}

function Get-ChocoCommandFallbackOptions {
    param([string]$Command)

    $specific = switch ($Command) {
        'apikey' { @(
            New-ChocoOptionSpec @('-s', '--source') 'Package source URL or configured source name.' $true
            New-ChocoOptionSpec @('-k', '--key', '--apikey', '--api-key') 'API key.' $true
        ) }
        'cache' { @(
            New-ChocoOptionSpec @('--expired') 'Remove expired cache entries.' $false
        ) }
        'config' { @(
            New-ChocoOptionSpec @('-n', '--name') 'Configuration key name.' $true
            New-ChocoOptionSpec @('--value') 'Configuration value.' $true
        ) }
        'feature' { @(
            New-ChocoOptionSpec @('-n', '--name') 'Feature name.' $true
        ) }
        'export' { @(
            New-ChocoOptionSpec @('-o', '--output-file-path') 'Path of the exported package file.' $true
            New-ChocoOptionSpec @('--include-version-numbers', '--include-version') 'Include package versions.' $false
        ) }
        'info' { @(
            New-ChocoOptionSpec @('-s', '--source') 'Package source.' $true
            New-ChocoOptionSpec @('-l', '--lo', '--localonly', '--local-only') 'Restrict to local packages.' $false
            New-ChocoOptionSpec @('--version') 'Package version.' $true
            New-ChocoOptionSpec @('--pre', '--prerelease') 'Include prereleases.' $false
        ) }
        'install' { @(
            New-ChocoOptionSpec @('-s', '--source') 'Package source.' $true
            New-ChocoOptionSpec @('--version') 'Package version.' $true
            New-ChocoOptionSpec @('--pre', '--prerelease') 'Include prereleases.' $false
            New-ChocoOptionSpec @('--x86', '--forcex86') 'Force an x86 install.' $false
            New-ChocoOptionSpec @('--ia', '--installargs', '--install-args', '--installarguments', '--install-arguments') 'Arguments passed to the native installer.' $true
            New-ChocoOptionSpec @('--params', '--parameters', '--pkgparameters', '--packageparameters', '--package-parameters') 'Package parameters.' $true
            New-ChocoOptionSpec @('-i', '--ignoredependencies', '--ignore-dependencies') 'Ignore dependencies.' $false
            New-ChocoOptionSpec @('-u', '--user') 'Authenticated source user.' $true
            New-ChocoOptionSpec @('-p', '--password') 'Authenticated source password.' $true
            New-ChocoOptionSpec @('--cert') 'Client certificate path.' $true
            New-ChocoOptionSpec @('--cp', '--certpassword') 'Client certificate password.' $true
        ) }
        'new' { @(
            New-ChocoOptionSpec @('-a', '--auto', '--automaticpackage') 'Automatically gather package information.' $false
            New-ChocoOptionSpec @('-t', '--template', '--template-name') 'Package template name.' $true
            New-ChocoOptionSpec @('-n', '--name') 'Package name.' $true
            New-ChocoOptionSpec @('--version') 'Package version.' $true
            New-ChocoOptionSpec @('--maintainer') 'Package maintainer.' $true
            New-ChocoOptionSpec @('--out', '--outdir', '--outputdirectory', '--output-directory') 'Output directory.' $true
        ) }
        'pack' { @(
            New-ChocoOptionSpec @('--version') 'Package version.' $true
            New-ChocoOptionSpec @('--out', '--outdir', '--outputdirectory', '--output-directory') 'Output directory.' $true
        ) }
        'pin' { @(
            New-ChocoOptionSpec @('-n', '--name') 'Package name.' $true
            New-ChocoOptionSpec @('--version') 'Package version.' $true
            New-ChocoOptionSpec @('--reason') 'Reason for the pin.' $true
        ) }
        'push' { @(
            New-ChocoOptionSpec @('-s', '--source') 'Push destination.' $true
            New-ChocoOptionSpec @('-k', '--key', '--apikey', '--api-key') 'API key.' $true
        ) }
        'rule' { @(
            New-ChocoOptionSpec @('-n', '--name') 'Package rule name.' $true
        ) }
        'source' { @(
            New-ChocoOptionSpec @('-n', '--name') 'Source name.' $true
            New-ChocoOptionSpec @('-s', '--source') 'Source URL or path.' $true
            New-ChocoOptionSpec @('-u', '--user') 'Authenticated source user.' $true
            New-ChocoOptionSpec @('-p', '--password') 'Authenticated source password.' $true
            New-ChocoOptionSpec @('--cert') 'Client certificate path.' $true
            New-ChocoOptionSpec @('--cp', '--certpassword') 'Client certificate password.' $true
            New-ChocoOptionSpec @('--priority') 'Source priority.' $true
        ) }
        'template' { @(
            New-ChocoOptionSpec @('-n', '--name') 'Template name.' $true
        ) }
        { $_ -in @('search', 'list') } { @(
            New-ChocoOptionSpec @('-s', '--source') 'Package source.' $true
            New-ChocoOptionSpec @('--version') 'Package version.' $true
            New-ChocoOptionSpec @('--page') 'Result page.' $true
            New-ChocoOptionSpec @('--page-size') 'Results per page.' $true
            New-ChocoOptionSpec @('--order-by') 'Result sort order.' $true
            New-ChocoOptionSpec @('--pre', '--prerelease') 'Include prereleases.' $false
            New-ChocoOptionSpec @('-e', '--exact') 'Require an exact package match.' $false
        ) }
        { $_ -in @('uninstall', 'upgrade', 'outdated') } { @(
            New-ChocoOptionSpec @('-s', '--source') 'Package source.' $true
            New-ChocoOptionSpec @('--version') 'Package version.' $true
            New-ChocoOptionSpec @('--pre', '--prerelease') 'Include prereleases.' $false
            New-ChocoOptionSpec @('--params', '--parameters', '--pkgparameters', '--packageparameters', '--package-parameters') 'Package parameters.' $true
            New-ChocoOptionSpec @('--except') 'Packages to exclude.' $true
        ) }
        default { @() }
    }

    @((Get-ChocoGlobalFallbackOptions) + @($specific))
}

function ConvertFrom-ChocoHelp {
    param(
        [string[]]$Lines,
        [string]$Command
    )

    $commands = New-Object System.Collections.Generic.List[object]
    $options = New-Object System.Collections.Generic.List[object]
    $subcommands = New-Object System.Collections.Generic.List[string]
    $currentOptionNames = @()
    $currentOptionTakesValue = $false
    $currentDescription = New-Object System.Collections.Generic.List[string]
    $optionLinePattern = '^\s+(?:-\?|[/\-]{1,2}[A-Za-z][A-Za-z0-9-]*)'
    $inOptionSection = $false
    $text = @($Lines) -join "`n"

    foreach ($line in @($Lines)) {
        if ($line -match '^\s*(?:Default\s+)?Options and Switches\s*$') {
            $inOptionSection = $true
            continue
        }

        if ($inOptionSection -and $line -match '^\s*(?:Commands|Examples|Exit Codes|How To Pass Options / Switches|Scripting / Integration.*|Usage)\s*$') {
            if ($currentOptionNames.Count -gt 0) {
                [void]$options.Add((New-ChocoOptionSpec -Names $currentOptionNames -Description ($currentDescription -join ' ') -TakesValue $currentOptionTakesValue))
            }
            $inOptionSection = $false
            $currentOptionNames = @()
            $currentDescription.Clear()
        }

        if ($Command -eq '' -and $line -match '^\s*\*\s+(?<name>[A-Za-z][A-Za-z0-9-]*)\s+-\s+(?<description>.+?)\s*$') {
            [void]$commands.Add((New-ChocoSuggestion -CompletionText $matches['name'] -ToolTip $matches['description']))
            continue
        }

        if ($inOptionSection -and $line -match $optionLinePattern) {
            $tokenMatches = @([regex]::Matches($line, '(?<!\S)(?<name>-\?|[/\-]{1,2}[A-Za-z][A-Za-z0-9-]*)(?:=(?<meta>VALUE|[A-Z][A-Z0-9_-]*))?'))
            $names = @($tokenMatches | ForEach-Object { $_.Groups['name'].Value })
            if ($names.Count -eq 0) {
                continue
            }

            if ($currentOptionNames.Count -gt 0) {
                [void]$options.Add((New-ChocoOptionSpec -Names $currentOptionNames -Description ($currentDescription -join ' ') -TakesValue $currentOptionTakesValue))
            }

            $currentOptionNames = @($names)
            $currentOptionTakesValue = [bool](@($tokenMatches | Where-Object { $_.Groups['meta'].Success }).Count)
            $currentDescription.Clear()
            continue
        }

        if ($currentOptionNames.Count -gt 0 -and $line -match '^\s{4,}(?<description>\S.*?)\s*$') {
            [void]$currentDescription.Add($matches['description'])
        } elseif ($currentOptionNames.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($line) -and $line -notmatch '^\s') {
            [void]$options.Add((New-ChocoOptionSpec -Names $currentOptionNames -Description ($currentDescription -join ' ') -TakesValue $currentOptionTakesValue))
            $currentOptionNames = @()
            $currentDescription.Clear()
        }
    }

    if ($currentOptionNames.Count -gt 0) {
        [void]$options.Add((New-ChocoOptionSpec -Names $currentOptionNames -Description ($currentDescription -join ' ') -TakesValue $currentOptionTakesValue))
    }

    if ($Command -ne '') {
        foreach ($candidate in @(Get-ChocoStaticSubcommands -Command $Command)) {
            $escapedCandidate = [regex]::Escape($candidate)
            $escapedCommand = [regex]::Escape($Command)
            if ($text -match ('(?m)^\s*choco(?:\.exe)?\s+{0}\s+(?:\[)?{1}(?:\b|\]|\|)' -f $escapedCommand, $escapedCandidate)) {
                [void]$subcommands.Add($candidate)
            }
        }

        # A few valid switches are shown only in a command example (for
        # example cache remove --expired and template list --reduce-output).
        $knownOptionNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($option in $options.ToArray()) {
            foreach ($name in @($option.Names)) {
                [void]$knownOptionNames.Add($name)
            }
        }
        foreach ($line in @($Lines)) {
            if ($line -notmatch ('^\s*choco(?:\.exe)?\s+{0}\b' -f [regex]::Escape($Command))) {
                continue
            }

            foreach ($match in [regex]::Matches($line, '(?<!\S)(?<name>(?:--|/)[A-Za-z][A-Za-z0-9-]*)(?:=(?<value>\S+))?')) {
                $name = $match.Groups['name'].Value
                if (-not $knownOptionNames.Add($name)) {
                    continue
                }

                [void]$options.Add((New-ChocoOptionSpec -Names @($name) -Description ('Option documented in choco {0} help examples.' -f $Command) -TakesValue $match.Groups['value'].Success))
            }
        }
    }

    [pscustomobject]@{
        Commands    = @($commands.ToArray())
        Options     = @($options.ToArray())
        Subcommands = @(Get-ChocoUniqueStrings -Items $subcommands.ToArray())
    }
}

function Get-ChocoHelpData {
    param([string[]]$Path)

    $canonicalPath = @($Path | ForEach-Object { Get-ChocoCanonicalCommand -Command $_ })
    $cacheKey = ($canonicalPath -join ' ').ToLowerInvariant()
    if ($script:ChocoCompletionCache.HelpDataByPath.ContainsKey($cacheKey)) {
        return $script:ChocoCompletionCache.HelpDataByPath[$cacheKey]
    }

    $command = if ($canonicalPath.Count -gt 0) { $canonicalPath[0] } else { '' }
    $arguments = if ([string]::IsNullOrWhiteSpace($command)) {
        @('--help')
    } else {
        @($command, '--help')
    }
    $lines = @(Invoke-ChocoCapture -Arguments $arguments)
    $helpData = ConvertFrom-ChocoHelp -Lines $lines -Command $command

    if (@($helpData.Options).Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($command)) {
            $helpData = [pscustomobject]@{
                Commands    = @(Get-ChocoStaticCommands)
                Options     = @((Get-ChocoGlobalFallbackOptions) + (New-ChocoOptionSpec @('--version') 'Print the Chocolatey version.' $false))
                Subcommands = @()
            }
        } else {
            $helpData = [pscustomobject]@{
                Commands    = @()
                Options     = @(Get-ChocoCommandFallbackOptions -Command $command)
                Subcommands = @(Get-ChocoStaticSubcommands -Command $command)
            }
        }
    } elseif ($command -eq '') {
        $liveCommands = @($helpData.Commands)
        if ($liveCommands.Count -eq 0) {
            $helpData.Commands = @(Get-ChocoStaticCommands)
        }
    }

    $script:ChocoCompletionCache.HelpDataByPath[$cacheKey] = $helpData
    $helpData
}

function Get-ChocoOptionByName {
    param(
        [string[]]$Path,
        [string]$Name
    )

    $cleanName = $Name.TrimStart('-', '/')
    foreach ($spec in @((Get-ChocoHelpData -Path $Path).Options)) {
        $cleanNames = @($spec.Names | ForEach-Object { $_.TrimStart('-', '/') })
        if (Test-ChocoArrayContains -Items $cleanNames -Value $cleanName) {
            return $spec
        }
    }

    $null
}

function Get-ChocoSubcommands {
    param([string[]]$Path)

    if (@($Path).Count -ne 1) {
        return @()
    }

    $helpData = Get-ChocoHelpData -Path $Path
    if (@($helpData.Subcommands).Count -gt 0) {
        return @($helpData.Subcommands)
    }

    @(Get-ChocoStaticSubcommands -Command (Get-ChocoCanonicalCommand -Command $Path[0]))
}

function Get-ChocoCommandState {
    param([string[]]$TokensBeforeCurrent)

    $path = New-Object System.Collections.Generic.List[string]
    $positionals = New-Object System.Collections.Generic.List[string]
    $expectingValueOption = $null
    $arguments = if ($TokensBeforeCurrent.Count -gt 1) {
        @($TokensBeforeCurrent[1..($TokensBeforeCurrent.Count - 1)])
    } else {
        @()
    }

    foreach ($token in @($arguments)) {
        if ($null -ne $expectingValueOption) {
            $expectingValueOption = $null
            continue
        }

        if ($token -match '^(?<option>(?:--?|/)[^=]+)=') {
            continue
        }

        if (Test-ChocoOptionToken -Token $token) {
            $spec = Get-ChocoOptionByName -Path @($path.ToArray()) -Name $token
            if ($spec -and $spec.TakesValue) {
                $expectingValueOption = $token
            }
            continue
        }

        if ($path.Count -eq 0) {
            $command = Get-ChocoCanonicalCommand -Command $token
            [void]$path.Add($command)
            continue
        }

        if ($path.Count -eq 1 -and (Test-ChocoArrayContains -Items (Get-ChocoSubcommands -Path @($path.ToArray())) -Value $token)) {
            [void]$path.Add($token.ToLowerInvariant())
            continue
        }

        [void]$positionals.Add($token)
    }

    [pscustomobject]@{
        Path                 = @($path.ToArray())
        Positionals          = @($positionals.ToArray())
        ExpectingValueOption = $expectingValueOption
    }
}

function Get-ChocoTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    $Element.Extent.Text
}

function Get-ChocoCachedLines {
    param(
        [string]$Kind,
        [string[]]$Arguments
    )

    if ($script:ChocoCompletionCache.LocalData.ContainsKey($Kind)) {
        $entry = $script:ChocoCompletionCache.LocalData[$Kind]
        $age = (Get-Date) - $entry.UpdatedAt
        if ($age.TotalSeconds -lt $script:ChocoCompletionCache.LocalDataTtlSeconds) {
            return @($entry.Lines)
        }
    }

    $lines = @(Invoke-ChocoCapture -Arguments $Arguments -TimeoutMilliseconds 7000 | Select-Object -First 1000)
    $script:ChocoCompletionCache.LocalData[$Kind] = @{
        UpdatedAt = Get-Date
        Lines     = @($lines)
    }
    @($lines)
}

function Get-ChocoLocalPackages {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-ChocoCachedLines -Kind 'packages' -Arguments @('list', '--local-only', '--limit-output', '--no-color'))) {
        $fields = @($line -split '\|')
        if ($fields.Count -lt 2 -or $fields[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$' -or [string]::IsNullOrWhiteSpace($fields[1])) {
            continue
        }

        [void]$items.Add([pscustomobject]@{
            Name    = $fields[0]
            Version = $fields[1]
        })
    }

    @($items.ToArray() | Sort-Object Name, Version -Unique)
}

function Get-ChocoLocalPackageNames {
    @(Get-ChocoLocalPackages | Select-Object -ExpandProperty Name -Unique | Sort-Object)
}

function Get-ChocoLocalPackageVersions {
    param([string]$PackageName)

    @(Get-ChocoLocalPackages |
        Where-Object { $_.Name.Equals($PackageName, [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -ExpandProperty Version -Unique |
        Sort-Object -Descending)
}

function Get-ChocoLocalSources {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-ChocoCachedLines -Kind 'sources' -Arguments @('source', 'list', '--limit-output', '--no-color'))) {
        $fields = @($line -split '\|')
        if ($fields.Count -lt 2 -or $fields[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
            continue
        }

        [void]$items.Add([pscustomobject]@{
            Name  = $fields[0]
            Value = $fields[1]
        })
    }

    @($items.ToArray() | Sort-Object Name -Unique)
}

function Get-ChocoLocalFeatures {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-ChocoCachedLines -Kind 'features' -Arguments @('feature', 'list', '--limit-output', '--no-color'))) {
        $fields = @($line -split '\|', 3)
        if ($fields.Count -lt 2 -or $fields[0] -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
            continue
        }

        [void]$items.Add([pscustomobject]@{
            Name        = $fields[0]
            Description = if ($fields.Count -gt 2) { $fields[2] } else { $fields[1] }
        })
    }

    @($items.ToArray() | Sort-Object Name -Unique)
}

function Get-ChocoLocalConfigKeys {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-ChocoCachedLines -Kind 'config' -Arguments @('config', 'list', '--limit-output', '--no-color'))) {
        $fields = @($line -split '\|', 3)
        if ($fields.Count -lt 2 -or $fields[0] -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
            continue
        }

        [void]$items.Add([pscustomobject]@{
            Name        = $fields[0]
            Description = if ($fields.Count -gt 2) { $fields[2] } else { '' }
        })
    }

    @($items.ToArray() | Sort-Object Name -Unique)
}

function Get-ChocoLocalTemplates {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-ChocoCachedLines -Kind 'templates' -Arguments @('template', 'list', '--limit-output', '--no-color'))) {
        $fields = @($line -split '\|')
        if ($fields.Count -lt 2 -or $fields[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
            continue
        }

        [void]$items.Add([pscustomobject]@{
            Name    = $fields[0]
            Version = $fields[1]
        })
    }

    @($items.ToArray() | Sort-Object Name -Unique)
}

function Get-ChocoLocalRules {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-ChocoCachedLines -Kind 'rules' -Arguments @('rule', 'list', '--limit-output', '--no-color'))) {
        $fields = @($line -split '\|', 4)
        if ($fields.Count -lt 3 -or $fields[1] -notmatch '^[A-Z]+[0-9]+$') {
            continue
        }

        [void]$items.Add([pscustomobject]@{
            Name        = $fields[1]
            Description = $fields[2]
        })
    }

    @($items.ToArray() | Sort-Object Name -Unique)
}

function Get-ChocoPathCompletions {
    param(
        [string]$InputPath,
        [string[]]$AllowedExtensions = @(),
        [ValidateSet('Any', 'Directory', 'File')]
        [string]$Kind = 'Any'
    )

    $cleanInput = if ($null -eq $InputPath) { '' } else { $InputPath }
    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    if ($separatorIndex -ge 0) {
        $parentText = $cleanInput.Substring(0, $separatorIndex + 1)
    } elseif ($cleanInput -match '^[A-Za-z]:') {
        $parentText = $cleanInput.Substring(0, 2)
    } else {
        $parentText = ''
    }
    $leaf = $cleanInput.Substring($parentText.Length)
    $parent = if ([string]::IsNullOrEmpty($parentText)) { '.' } else { $parentText }
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($leaf) + '*'
    $extensions = @($AllowedExtensions | ForEach-Object { $_.ToLowerInvariant() })

    foreach ($item in @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)) {
        $itemName = if ($item.PSObject.Properties['PSChildName'] -and -not [string]::IsNullOrWhiteSpace([string]$item.PSChildName)) {
            [string]$item.PSChildName
        } elseif ($item.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$item.Name)) {
            [string]$item.Name
        } else {
            ''
        }
        if ([string]::IsNullOrWhiteSpace($itemName) -or $itemName -notlike $pattern) {
            continue
        }

        if ($Kind -eq 'Directory' -and -not $item.PSIsContainer) {
            continue
        }
        if ($Kind -eq 'File' -and $item.PSIsContainer) {
            # Package path operands often accept source directories as well.
        } elseif (-not $item.PSIsContainer -and $extensions.Count -gt 0 -and $extensions -notcontains $item.Extension.ToLowerInvariant()) {
            continue
        }

        $text = $parentText + $itemName
        if ($item.PSIsContainer) {
            $text += [System.IO.Path]::DirectorySeparatorChar
        }

        $fullNameProperty = $item.PSObject.Properties['FullName']
        $psPathProperty = $item.PSObject.Properties['PSPath']
        $toolTip = if ($null -ne $fullNameProperty -and -not [string]::IsNullOrWhiteSpace([string]$fullNameProperty.Value)) {
            [string]$fullNameProperty.Value
        } elseif ($null -ne $psPathProperty -and -not [string]::IsNullOrWhiteSpace([string]$psPathProperty.Value)) {
            [string]$psPathProperty.Value
        } elseif (-not [string]::IsNullOrWhiteSpace($itemName)) {
            $itemName
        } else {
            $text
        }

        [pscustomobject]@{
            CompletionText = $text
            ToolTip        = $toolTip
            ResultType     = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ProviderItem' }
        }
    }
}

function Get-ChocoNameOptionSuggestions {
    param(
        [string[]]$Path,
        [string]$TypedValue
    )

    $command = if (@($Path).Count -gt 0) { (Get-ChocoCanonicalCommand -Command $Path[0]) } else { '' }
    $subcommand = if (@($Path).Count -gt 1) { $Path[1].ToLowerInvariant() } else { '' }
    $suggestions = New-Object System.Collections.Generic.List[object]

    switch ($command) {
        'apikey' {
            foreach ($source in @(Get-ChocoLocalSources)) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $source.Name -ToolTip $source.Value))
            }
        }
        'config' {
            foreach ($key in @(Get-ChocoLocalConfigKeys)) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $key.Name -ToolTip $key.Description))
            }
        }
        'feature' {
            foreach ($feature in @(Get-ChocoLocalFeatures)) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $feature.Name -ToolTip $feature.Description))
            }
        }
        'pin' {
            foreach ($package in @(Get-ChocoLocalPackageNames)) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $package -ToolTip 'Installed package'))
            }
        }
        'rule' {
            foreach ($rule in @(Get-ChocoLocalRules)) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $rule.Name -ToolTip $rule.Description))
            }
        }
        'source' {
            if ($subcommand -eq 'add') {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<source-name>' -ToolTip 'New source name.'))
            }
            foreach ($source in @(Get-ChocoLocalSources)) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $source.Name -ToolTip $source.Value))
            }
        }
        'template' {
            foreach ($template in @(Get-ChocoLocalTemplates)) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $template.Name -ToolTip ('Template version {0}' -f $template.Version)))
            }
        }
        'new' {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<package-name>' -ToolTip 'Package id to create.'))
        }
    }

    @($suggestions.ToArray())
}

function Test-ChocoPathLike {
    param([string]$Text)

    -not [string]::IsNullOrWhiteSpace($Text) -and (
        $Text.Contains('\') -or
        $Text.Contains('/') -or
        $Text -match '^[A-Za-z]:' -or
        $Text.StartsWith('.') -or
        $Text.StartsWith('~')
    )
}

function Get-ChocoOptionValueSuggestions {
    param(
        [string[]]$Path,
        [string]$Option,
        [string]$TypedValue,
        [string[]]$Positionals
    )

    $cleanOption = $Option.TrimStart('-', '/').ToLowerInvariant()
    $command = if (@($Path).Count -gt 0) { (Get-ChocoCanonicalCommand -Command $Path[0]) } else { '' }
    $suggestions = New-Object System.Collections.Generic.List[object]

    switch ($cleanOption) {
        { $_ -in @('n', 'name') } {
            foreach ($item in @(Get-ChocoNameOptionSuggestions -Path $Path -TypedValue $TypedValue)) {
                if ($item) { [void]$suggestions.Add($item) }
            }
        }
        { $_ -in @('s', 'source') } {
            foreach ($source in @(Get-ChocoLocalSources)) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $source.Name -ToolTip $source.Value))
                if (-not [string]::IsNullOrWhiteSpace($source.Value)) {
                    [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $source.Value -ToolTip ('Configured source {0}' -f $source.Name)))
                }
            }
            foreach ($value in @('ruby', 'cygwin', 'python', 'windowsfeatures')) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $value -ToolTip 'Chocolatey special package source.'))
            }
            foreach ($pathItem in @(Get-ChocoPathCompletions -InputPath $TypedValue -Kind 'Any')) {
                [void]$suggestions.Add($pathItem)
            }
        }
        'version' {
            $packageName = @($Positionals | Select-Object -First 1)
            if ($packageName.Count -gt 0) {
                foreach ($version in @(Get-ChocoLocalPackageVersions -PackageName $packageName[0])) {
                    [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $version -ToolTip ('Installed version of {0}' -f $packageName[0])))
                }
            }
            if ($suggestions.Count -eq 0) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<version>' -ToolTip 'A package version.'))
            }
        }
        { $_ -in @('c', 'cache', 'cachelocation', 'cache-location', 'log-file', 'out', 'outdir', 'outputdirectory', 'output-directory', 'output-file-path') } {
            $kind = if ($_ -in @('out', 'outdir', 'outputdirectory', 'output-directory')) { 'Directory' } else { 'Any' }
            foreach ($pathItem in @(Get-ChocoPathCompletions -InputPath $TypedValue -Kind $kind)) {
                [void]$suggestions.Add($pathItem)
            }
            if ($suggestions.Count -eq 0) {
                $placeholder = if ($kind -eq 'Directory') { '<directory>' } else { '<path>' }
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $placeholder -ToolTip 'A local path.'))
            }
        }
        { $_ -in @('cert') } {
            foreach ($pathItem in @(Get-ChocoPathCompletions -InputPath $TypedValue -AllowedExtensions @('.pfx', '.p12') -Kind 'Any')) {
                [void]$suggestions.Add($pathItem)
            }
            if ($suggestions.Count -eq 0) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<certificate-path>' -ToolTip 'Path to a client certificate.'))
            }
        }
        { $_ -match '^(password|proxy-password|certpassword|cp|key|apikey|api-key)$' } {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<secret>' -ToolTip 'Secret value; deliberately not discovered from local state.'))
        }
        { $_ -in @('user', 'proxy-user', 'u') } {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<username>' -ToolTip 'Authenticated user name.'))
        }
        { $_ -in @('ia', 'installargs', 'install-args', 'installarguments', 'install-arguments', 'ua', 'uninstallargs', 'uninstallarguments', 'uninstall-arguments') } {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<installer-arguments>' -ToolTip 'Arguments passed to the native installer.'))
        }
        { $_ -in @('params', 'parameters', 'pkgparameters', 'packageparameters', 'package-parameters') } {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<package-parameters>' -ToolTip 'Parameters consumed by package scripts.'))
        }
        { $_ -in @('checksumtype', 'checksum-type', 'downloadchecksumtype', 'download-checksum-type', 'checksumtype64', 'checksumtypex64', 'checksum-type-x64', 'downloadchecksumtypex64', 'download-checksum-type-x64') } {
            foreach ($value in @('md5', 'sha1', 'sha256', 'sha512')) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $value -ToolTip 'Checksum algorithm.'))
            }
        }
        'order-by' {
            foreach ($value in @('Id', 'Title', 'Popularity', 'LastPublished', 'Unsorted')) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $value -ToolTip 'Package search ordering.'))
            }
        }
        { $_ -in @('t', 'template', 'template-name') } {
            foreach ($template in @(Get-ChocoLocalTemplates)) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $template.Name -ToolTip ('Template version {0}' -f $template.Version)))
            }
        }
        { $_ -in @('except') } {
            foreach ($package in @(Get-ChocoLocalPackageNames)) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $package -ToolTip 'Installed package to exclude.'))
            }
        }
        'priority' {
            foreach ($value in @('0', '1', '10', '100')) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $value -ToolTip 'Source priority; lower is better.'))
            }
        }
        { $_ -in @('timeout', 'execution-timeout', 'page', 'page-size') } {
            foreach ($value in @('0', '1', '10', '30', '60', '100')) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $value -ToolTip 'Numeric value.'))
            }
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<number>' -ToolTip 'Numeric value.'))
        }
        default {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<value>' -ToolTip "Value for $Option."))
        }
    }

    @($suggestions.ToArray())
}

function Get-ChocoPositionalSuggestions {
    param(
        [string[]]$Path,
        [string[]]$Positionals,
        [string]$TypedValue
    )

    $command = if (@($Path).Count -gt 0) { (Get-ChocoCanonicalCommand -Command $Path[0]) } else { '' }
    $subcommand = if (@($Path).Count -gt 1) { $Path[1].ToLowerInvariant() } else { '' }
    $positionIndex = @($Positionals).Count
    $suggestions = New-Object System.Collections.Generic.List[object]

    if ($command -eq 'help' -and $positionIndex -eq 0) {
        foreach ($item in @(Get-ChocoHelpData -Path @()).Commands) {
            [void]$suggestions.Add($item)
        }
        return @($suggestions.ToArray())
    }

    if ($command -eq 'config' -and $subcommand -in @('get', 'set', 'unset')) {
        if ($positionIndex -eq 0) {
            foreach ($key in @(Get-ChocoLocalConfigKeys)) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $key.Name -ToolTip $key.Description))
            }
        } elseif ($subcommand -eq 'set' -and $positionIndex -eq 1) {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<config-value>' -ToolTip 'New value for the configuration key.'))
        }
        return @($suggestions.ToArray())
    }

    if ($command -eq 'feature' -and $subcommand -in @('get', 'disable', 'enable') -and $positionIndex -eq 0) {
        foreach ($feature in @(Get-ChocoLocalFeatures)) {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $feature.Name -ToolTip $feature.Description))
        }
        return @($suggestions.ToArray())
    }

    if ($command -eq 'rule' -and $subcommand -eq 'get' -and $positionIndex -eq 0) {
        foreach ($rule in @(Get-ChocoLocalRules)) {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $rule.Name -ToolTip $rule.Description))
        }
        return @($suggestions.ToArray())
    }

    if ($command -eq 'template' -and $subcommand -eq 'info' -and $positionIndex -eq 0) {
        foreach ($template in @(Get-ChocoLocalTemplates)) {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $template.Name -ToolTip ('Template version {0}' -f $template.Version)))
        }
        return @($suggestions.ToArray())
    }

    if ($command -eq 'source' -and $subcommand -in @('remove', 'disable', 'enable') -and $positionIndex -eq 0) {
        foreach ($source in @(Get-ChocoLocalSources)) {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $source.Name -ToolTip $source.Value))
        }
        return @($suggestions.ToArray())
    }

    if ($command -eq 'new' -and $positionIndex -eq 0) {
        [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<package-name>' -ToolTip 'Package id to create.'))
        return @($suggestions.ToArray())
    }

    $packageCommands = @('info', 'list', 'outdated', 'install', 'search', 'uninstall', 'upgrade')
    if ($command -in $packageCommands) {
        foreach ($package in @(Get-ChocoLocalPackageNames)) {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $package -ToolTip 'Locally installed package.'))
        }
        if ($command -in @('install', 'upgrade')) {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText 'all' -ToolTip 'All available or installed packages, depending on the command.'))
        }
        if ($command -in @('info', 'install', 'search')) {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<package-id>' -ToolTip 'A package id.'))
        }
    }

    $pathExtensions = switch ($command) {
        'pack'    { @('.nuspec') }
        'push'    { @('.nupkg') }
        'install' { @('.config', '.nuspec', '.nupkg') }
        default   { @() }
    }
    $completePackagePath = $command -in @('pack', 'push') -or (
        $command -eq 'install' -and (
            (Test-ChocoPathLike -Text $TypedValue) -or
            $TypedValue -match '\.(config|nuspec|nupkg)$'
        )
    )
    if ($completePackagePath -or (Test-ChocoPathLike -Text $TypedValue)) {
        foreach ($pathItem in @(Get-ChocoPathCompletions -InputPath $TypedValue -AllowedExtensions $pathExtensions -Kind 'Any')) {
            [void]$suggestions.Add($pathItem)
        }
        if ($suggestions.Count -eq 0 -and $command -in @('pack', 'push')) {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText '<path>' -ToolTip 'A local package path.'))
        }
    }

    @($suggestions.ToArray())
}

function ConvertTo-ChocoCompletionResults {
    param(
        [object[]]$Suggestions,
        [string]$Prefix
    )

    $safePrefix = if ($null -eq $Prefix) { '' } else { $Prefix }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    foreach ($suggestion in @($Suggestions)) {
        if ($null -eq $suggestion -or [string]::IsNullOrWhiteSpace([string]$suggestion.CompletionText)) {
            continue
        }

        $completionText = [string]$suggestion.CompletionText
        if (-not $completionText.StartsWith($safePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (-not $seen.Add($completionText)) {
            continue
        }

        [void]$results.Add((New-ChocoCompletionResult -CompletionText $completionText -ToolTip ([string]$suggestion.ToolTip) -ResultType ([string]$suggestion.ResultType)))
    }

    @($results.ToArray())
}

function Add-ChocoQuote {
    param(
        [object[]]$Results,
        [string]$Quote,
        [string]$ValuePrefix = ''
    )

    foreach ($result in @($Results)) {
        if ($null -eq $result -or -not $result.PSObject.Properties['CompletionText']) {
            continue
        }

        $completionText = [string]$result.CompletionText
        if (-not [string]::IsNullOrEmpty($ValuePrefix) -and $completionText.StartsWith($ValuePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $value = $completionText.Substring($ValuePrefix.Length)
            New-ChocoCompletionResult -CompletionText ($ValuePrefix + (ConvertTo-ChocoQuotedValue -Value $value -QuoteChar $Quote)) -ToolTip $result.ToolTip -ResultType $result.ResultType
        } elseif ([string]::IsNullOrEmpty($Quote) -and $result.ResultType -eq 'ParameterName') {
            $result
        } else {
            New-ChocoCompletionResult -CompletionText (ConvertTo-ChocoQuotedValue -Value $completionText -QuoteChar $Quote) -ToolTip $result.ToolTip -ResultType $result.ResultType
        }
    }
}

function ConvertTo-ChocoQuotedValue {
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrEmpty($Value) -or $Value -match '^<[^<>\s]+>$') {
        return $Value
    }

    if ([string]::IsNullOrEmpty($QuoteChar)) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]|^[-\u2013-\u2015]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-ChocoOptionSuggestions {
    param(
        [string[]]$Path,
        [string]$Prefix
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($spec in @((Get-ChocoHelpData -Path $Path).Options | Sort-Object -Property { $_.Names[0] })) {
        foreach ($name in @($spec.Names)) {
            $candidateNames = if ($Prefix.StartsWith('/')) {
                @('/' + $name.TrimStart('-', '/'))
            } else {
                @($name)
            }

            foreach ($candidateName in @($candidateNames)) {
                if (-not $candidateName.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase) -or -not $seen.Add($candidateName)) {
                    continue
                }

                New-ChocoSuggestion -CompletionText $candidateName -ToolTip $spec.Description -ResultType 'ParameterName'
            }
        }
    }
}

function Get-ChocoCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$WordToComplete
    )

    foreach ($element in @($CommandAst.CommandElements)) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            $length = [Math]::Min($extent.Text.Length, $CursorPosition - $extent.StartOffset)
            if ($length -gt 0) {
                return $extent.Text.Substring(0, $length)
            }
        }
    }

    if ($null -eq $WordToComplete) { '' } else { $WordToComplete }
}

function Split-ChocoTypedToken {
    param([string]$Token)

    $quoteChar = ''
    $value = if ($null -eq $Token) { '' } else { $Token }

    if ($value -match '^(?<option>(?:--?|/)[^=]+)=(?<quote>[''"\u2018-\u201E])(?<typed>.*)$') {
        $quoteChar = $matches['quote']
        $value = $matches['option'] + '=' + $matches['typed']
        if ($value.EndsWith($quoteChar)) {
            $value = $value.Substring(0, $value.Length - 1)
        }
    } elseif ($value.Length -gt 0 -and $value[0] -match '[''"\u2018-\u201E]') {
        $quoteChar = [string]$value[0]
        $value = $value.Substring(1)
        if ($value.EndsWith($quoteChar)) {
            $value = $value.Substring(0, $value.Length - 1)
        }
    }

    [pscustomobject]@{
        Token = $value
        Quote = $quoteChar
    }
}

function Complete-ChocoNative {
    param($wordToComplete, $commandAst, $cursorPosition)

    if ($commandAst.CommandElements.Count -eq 0) {
        return
    }

    $tokensBeforeCurrent = New-Object System.Collections.Generic.List[string]
    foreach ($element in @($commandAst.CommandElements)) {
        $extent = $element.Extent
        $text = Get-ChocoTokenText -Element $element
        if ($extent.EndOffset -lt $cursorPosition) {
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                [void]$tokensBeforeCurrent.Add($text)
            }
            continue
        }
        break
    }

    if ($tokensBeforeCurrent.Count -eq 0) {
        $tokensBeforeCurrent = @((Get-ChocoTokenText -Element $commandAst.CommandElements[0]))
        if ($commandAst.CommandElements.Count -eq 1 -and $cursorPosition -le $commandAst.CommandElements[0].Extent.EndOffset) {
            return
        }
    } else {
        $tokensBeforeCurrent = @($tokensBeforeCurrent.ToArray())
    }

    $typed = Split-ChocoTypedToken -Token (Get-ChocoCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition -WordToComplete $wordToComplete)
    $currentToken = $typed.Token
    $quoteChar = $typed.Quote
    $state = Get-ChocoCommandState -TokensBeforeCurrent $tokensBeforeCurrent
    $suggestions = New-Object System.Collections.Generic.List[object]

    if ($currentToken -match '^(?<option>(?:--?|/)[^=]+)=(?<value>.*)$') {
        $option = $matches['option']
        $typedValue = $matches['value']
        foreach ($item in @(Get-ChocoOptionValueSuggestions -Path $state.Path -Option $option -TypedValue $typedValue -Positionals $state.Positionals)) {
            if ($item) {
                [void]$suggestions.Add((New-ChocoSuggestion -CompletionText ('{0}={1}' -f $option, $item.CompletionText) -ToolTip $item.ToolTip -ResultType $item.ResultType))
            }
        }
        $valuePrefix = '{0}=' -f $option
        Add-ChocoQuote -Results (ConvertTo-ChocoCompletionResults -Suggestions $suggestions -Prefix ($valuePrefix + $typedValue)) -Quote $quoteChar -ValuePrefix $valuePrefix
        return
    }

    if ($null -ne $state.ExpectingValueOption) {
        $items = Get-ChocoOptionValueSuggestions -Path $state.Path -Option $state.ExpectingValueOption -TypedValue $currentToken -Positionals $state.Positionals
        Add-ChocoQuote -Results (ConvertTo-ChocoCompletionResults -Suggestions $items -Prefix $currentToken) -Quote $quoteChar
        return
    }

    $pathCount = @($state.Path).Count
    if (-not (Test-ChocoOptionToken -Token $currentToken) -and $pathCount -eq 0) {
        foreach ($command in @((Get-ChocoHelpData -Path @()).Commands)) {
            [void]$suggestions.Add($command)
        }
    } elseif (-not (Test-ChocoOptionToken -Token $currentToken) -and $pathCount -eq 1 -and @($state.Positionals).Count -eq 0) {
        foreach ($subcommand in @(Get-ChocoSubcommands -Path $state.Path)) {
            [void]$suggestions.Add((New-ChocoSuggestion -CompletionText $subcommand -ToolTip ('choco {0} {1}' -f $state.Path[0], $subcommand)))
        }
    }

    if (-not (Test-ChocoOptionToken -Token $currentToken) -and $pathCount -gt 0) {
        foreach ($item in @(Get-ChocoPositionalSuggestions -Path $state.Path -Positionals $state.Positionals -TypedValue $currentToken)) {
            if ($item) { [void]$suggestions.Add($item) }
        }
    }

    if ([string]::IsNullOrEmpty($currentToken) -or (Test-ChocoOptionToken -Token $currentToken)) {
        foreach ($item in @(Get-ChocoOptionSuggestions -Path $state.Path -Prefix $currentToken)) {
            if ($item) { [void]$suggestions.Add($item) }
        }
    }

    Add-ChocoQuote -Results (ConvertTo-ChocoCompletionResults -Suggestions $suggestions -Prefix $currentToken) -Quote $quoteChar
}

Register-ArgumentCompleter -Native -CommandName @('choco', 'choco.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-ChocoNative -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
