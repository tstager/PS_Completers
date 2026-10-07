using namespace System.Management.Automation
using namespace System.Management.Automation.Language

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name DotnetCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:DotnetCompletionCache = @{
        ExecutableProbed = $false
        ExecutablePath   = $null
        Results          = @{}
    }
}

function Get-DotnetCompletionCache {
    $script:DotnetCompletionCache
}

function Get-DotnetExecutablePath {
    $cache = Get-DotnetCompletionCache
    if ($cache.ExecutableProbed) {
        return $cache.ExecutablePath
    }

    $cache.ExecutableProbed = $true
    $command = @(Get-Command -Name dotnet -CommandType Application -ErrorAction Ignore) |
        Select-Object -First 1
    if ($null -ne $command) {
        $cache.ExecutablePath = $command.Source
    }

    $cache.ExecutablePath
}

function Get-DotnetLiveCompletion {
    param(
        [string]$Text,
        [int]$Position
    )

    # A child inherits the process start directory, which Set-Location never
    # updates; run it in the session's filesystem location, and key the cache by
    # that directory, because project-aware answers (--framework, ...) depend on it.
    # A location that no longer exists cannot start a child, so it is left to the
    # inherited directory.
    $directory = ''
    $location = Get-Location -PSProvider FileSystem -ErrorAction Ignore
    if ($location -and [System.IO.Directory]::Exists($location.ProviderPath)) {
        $directory = $location.ProviderPath
    }

    $cache = Get-DotnetCompletionCache
    $key = "$directory|$Position|$Text"
    if ($cache.Results.ContainsKey($key)) {
        return $cache.Results[$key]
    }

    $executablePath = Get-DotnetExecutablePath
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        $cache.Results[$key] = @()
        return @()
    }

    # 'dotnet complete' is the SDK's own completion engine, so it always matches
    # the installed SDK. It is run with standard input closed and a bounded
    # budget, and every answer is cached, so a slow or hung call cannot stall the
    # prompt or be paid for twice.
    $output = ''
    $process = [System.Diagnostics.Process]::new()
    try {
        $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($executablePath)
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        if ($directory) {
            $process.StartInfo.WorkingDirectory = $directory
        }
        foreach ($argument in @('complete', '--position', $Position.ToString(), $Text)) {
            [void]$process.StartInfo.ArgumentList.Add($argument)
        }

        [void]$process.Start()
        $process.StandardInput.Close()
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()

        if ($process.WaitForExit(2500)) {
            $output = ($standardOutput.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
            [void]$standardError.GetAwaiter().GetResult()
        } else {
            $process.Kill($true)
        }
    } catch {
        $output = ''
    } finally {
        $process.Dispose()
    }

    $values = @([regex]::Split($output, '\r?\n') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cache.Results[$key] = $values
    $values
}

function Test-DotnetOptionToken {
    param([string]$Token)

    -not [string]::IsNullOrEmpty($Token) -and ($Token.StartsWith('-') -or $Token.StartsWith('/'))
}

function Test-DotnetPathOption {
    param([string]$Token)

    $Token -in @(
        '-o', '--output', '--project', '--file', '--config', '--configfile',
        '--package-directory', '--artifacts-path', '--tool-manifest', '--tool-path',
        '--manifest', '--solution', '--runtimeconfig', '--depsfile', '--output-dir'
    )
}

function Get-DotnetProjectCompletion {
    param(
        [string]$WordToComplete,
        [bool]$IncludeDirectories
    )

    @([System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete)) |
        Where-Object {
            ($IncludeDirectories -and $_.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer) -or
            $_.ListItemText -match '\.(?:cs|fs|vb)proj$|\.proj$|\.sln[fx]?$'
        }
}

function Get-DotnetRuntimeIdentifier {
    # The installed SDK ships its portable RID graph as a plain file, so the RIDs
    # are read from disk instead of asking a process; the newest SDK's graph is
    # read once per session.
    $cache = Get-DotnetCompletionCache
    if ($cache.ContainsKey('RuntimeIdentifiers')) {
        return $cache.RuntimeIdentifiers
    }

    $architectures = @('arm', 'arm64', 'armel', 'armv6', 'loongarch64', 'mips64', 'ppc64le', 'riscv64', 's390x', 'wasm', 'x64', 'x86')
    $names = @()
    $executablePath = Get-DotnetExecutablePath
    if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
        $sdkRoot = Join-Path ([System.IO.Path]::GetDirectoryName($executablePath)) 'sdk'
        $graph = @(
            Get-ChildItem -LiteralPath $sdkRoot -Directory -ErrorAction Ignore |
                Where-Object { $_.Name -match '^\d+\.\d+\.\d+' } |
                Sort-Object -Property @{ Expression = { [version]([regex]::Match($_.Name, '^\d+\.\d+\.\d+').Value) } } -Descending |
                ForEach-Object { Join-Path $_.FullName 'PortableRuntimeIdentifierGraph.json' } |
                Where-Object { [System.IO.File]::Exists($_) }
        ) | Select-Object -First 1
        if ($graph) {
            try {
                $names = @((Get-Content -LiteralPath $graph -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).runtimes.PSObject.Properties.Name)
            } catch {
                $names = @()
            }
        }
    }

    if ($names.Count -eq 0) {
        $names = @('linux-arm', 'linux-arm64', 'linux-musl-arm64', 'linux-musl-x64', 'linux-x64', 'osx-arm64', 'osx-x64', 'win-arm64', 'win-x64', 'win-x86')
    }

    $cache.RuntimeIdentifiers = @($names | Where-Object { $_.Contains('-') -and $_.Substring($_.LastIndexOf('-') + 1) -in $architectures } | Sort-Object)
    $cache.RuntimeIdentifiers
}

function Get-DotnetProjectDirectory {
    # The directory a project-relative value is read from: the --project
    # argument when one was given, otherwise the current location.
    param([string[]]$SettledTokens)

    $path = '.'
    for ($i = 0; $i -lt $SettledTokens.Count - 1; $i++) {
        if ($SettledTokens[$i] -eq '--project') {
            $path = $SettledTokens[$i + 1].Trim("'", '"')
        }
    }

    try {
        $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
    } catch {
        return $null
    }

    if ([System.IO.File]::Exists($resolved)) {
        return [pscustomobject]@{ Directory = [System.IO.Path]::GetDirectoryName($resolved); Project = $resolved }
    }

    if ([System.IO.Directory]::Exists($resolved)) {
        return [pscustomobject]@{ Directory = $resolved; Project = $null }
    }

    $null
}

function Get-DotnetLaunchProfile {
    param($Project)

    if ($null -eq $Project) {
        return
    }

    $settings = Join-Path $Project.Directory 'Properties\launchSettings.json'
    if (-not [System.IO.File]::Exists($settings)) {
        return
    }

    try {
        $profiles = (Get-Content -LiteralPath $settings -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).profiles
    } catch {
        return
    }

    if ($null -ne $profiles) {
        @($profiles.PSObject.Properties.Name)
    }
}

function Get-DotnetTargetFramework {
    # The SDK answers --framework inside a project it can evaluate; this covers
    # the rest: the frameworks the project files here declare, else the current
    # target frameworks.
    param($Project)

    $frameworks = @(
        if ($null -ne $Project) {
            $files = if ($Project.Project) {
                @($Project.Project)
            } else {
                @(Get-ChildItem -LiteralPath $Project.Directory -File -Filter '*proj' -ErrorAction Ignore | ForEach-Object FullName)
            }

            foreach ($file in $files) {
                $content = Get-Content -LiteralPath $file -Raw -ErrorAction Ignore
                if ($content) {
                    foreach ($match in [regex]::Matches($content, '<TargetFrameworks?>([^<]*)</TargetFrameworks?>')) {
                        $match.Groups[1].Value -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.Contains('$(') }
                    }
                }
            }
        }
    )

    if ($frameworks.Count -eq 0) {
        $frameworks = @('net10.0', 'net9.0', 'net8.0', 'netstandard2.1', 'netstandard2.0', 'net481', 'net48', 'net472')
    }

    @($frameworks | Select-Object -Unique)
}

function Get-DotnetOptionValue {
    # The values for an option the SDK leaves unanswered. $null means this is not
    # a value slot the table knows; an empty array is a value slot with nothing
    # to offer, which must not fall through to the option list.
    param(
        [string]$Command,
        [string]$Option,
        [string[]]$SettledTokens
    )

    # Option names are case-sensitive: vstest's '--Framework' is not '--framework'.
    switch -CaseSensitive ($Option) {
        '--runtime' {
            return , @(Get-DotnetRuntimeIdentifier)
        }
        '--os' {
            return , @(Get-DotnetRuntimeIdentifier | ForEach-Object { $_.Substring(0, $_.LastIndexOf('-')) } | Sort-Object -Unique)
        }
        '--arch' {
            return , @(Get-DotnetRuntimeIdentifier | ForEach-Object { $_.Substring($_.LastIndexOf('-') + 1) } | Sort-Object -Unique)
        }
        '--launch-profile' {
            return , @(Get-DotnetLaunchProfile -Project (Get-DotnetProjectDirectory -SettledTokens $SettledTokens))
        }
        '--framework' {
            return , @(Get-DotnetTargetFramework -Project (Get-DotnetProjectDirectory -SettledTokens $SettledTokens))
        }
    }

    # Bundled tools are outside the SDK's completion engine, so their value
    # options are listed here; free-form values offer nothing.
    $tool = ($Command -split ';')[1]
    $bundled = @{
        'dev-certs --format'           = @('Pfx', 'Pem')
        'dev-certs --password'         = @()
        'user-jwts --output'           = @('default', 'token', 'json')
        'user-jwts --scheme'           = @()
        'user-jwts --name'             = @()
        'user-jwts --audience'         = @()
        'user-jwts --issuer'           = @()
        'user-jwts --scope'            = @()
        'user-jwts --role'             = @()
        'user-jwts --claim'            = @()
        'user-jwts --not-before'       = @()
        'user-jwts --expires-on'       = @()
        'user-jwts --valid-for'        = @()
        'user-secrets --configuration' = @('Debug', 'Release')
        'user-secrets --id'            = @()
        'watch --configuration'        = @('Debug', 'Release')
        'watch --verbosity'            = @('q', 'quiet', 'm', 'minimal', 'n', 'normal', 'd', 'detailed', 'diag', 'diagnostic')
        'watch --device'               = @()
    }
    $key = "$tool $Option"
    if ($bundled.ContainsKey($key)) {
        return , @($bundled[$key])
    }

    $null
}

function ConvertFrom-DotnetTypedWord {
    # Splits the word typed so far into its value and the opening quote the user
    # typed ('' when bare), undoing that quote style's escapes.
    param([string]$Text)

    $quote = ''
    if ($Text.StartsWith("'") -or $Text.StartsWith('"')) {
        $quote = $Text.Substring(0, 1)
        $Text = $Text.Substring(1)
        if ($Text.EndsWith($quote)) {
            $Text = $Text.Substring(0, $Text.Length - 1)
        }

        $Text = if ($quote -eq "'") { $Text.Replace("''", "'") } else { $Text -replace '`(.)', '$1' }
    }

    [pscustomobject]@{ Value = $Text; Quote = $quote }
}

function ConvertTo-DotnetArgument {
    # Renders a value as one PowerShell argument: bare when safe and no quote was
    # typed, otherwise in the typed quote style (single by default).
    param(
        [string]$Value,
        [string]$Quote
    )

    if (-not $Quote) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$\u2018-\u201E]' -and $Value -notmatch '^[@#]') {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -eq "'") {
        return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
    }

    '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
}

Register-ArgumentCompleter -Native -CommandName 'dotnet' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $commandElements = $commandAst.CommandElements
    $command = @(
        'dotnet'
        for ($i = 1; $i -lt $commandElements.Count; $i++) {
            $element = $commandElements[$i]
            if ($element -isnot [StringConstantExpressionAst] -or
                $element.StringConstantType -ne [StringConstantType]::BareWord -or
                $element.Value.StartsWith('-') -or
                $element.Value -eq $wordToComplete) {
                break
            }
            $element.Value
        }) -join ';'

    $completions = @()
    switch ($command) {
        'dotnet' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--diagnostics', '--diagnostics', [CompletionResultType]::ParameterName, "Enable diagnostic output.")
                [CompletionResult]::new('--diagnostics', '-d', [CompletionResultType]::ParameterName, "Enable diagnostic output.")
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "--version")
                [CompletionResult]::new('--info', '--info', [CompletionResultType]::ParameterName, "--info")
                [CompletionResult]::new('--list-sdks', '--list-sdks', [CompletionResultType]::ParameterName, "--list-sdks")
                [CompletionResult]::new('--list-runtimes', '--list-runtimes', [CompletionResultType]::ParameterName, "--list-runtimes")
                [CompletionResult]::new('build', 'build', [CompletionResultType]::ParameterValue, ".NET Builder")
                [CompletionResult]::new('build-server', 'build-server', [CompletionResultType]::ParameterValue, "Interact with servers started from a build.")
                [CompletionResult]::new('clean', 'clean', [CompletionResultType]::ParameterValue, ".NET Clean Command")
                [CompletionResult]::new('format', 'format', [CompletionResultType]::ParameterValue, "format")
                [CompletionResult]::new('fsi', 'fsi', [CompletionResultType]::ParameterValue, "fsi")
                [CompletionResult]::new('msbuild', 'msbuild', [CompletionResultType]::ParameterValue, ".NET Builder")
                [CompletionResult]::new('new', 'new', [CompletionResultType]::ParameterValue, "Template Instantiation Commands for .NET CLI.")
                [CompletionResult]::new('nuget', 'nuget', [CompletionResultType]::ParameterValue, "nuget")
                [CompletionResult]::new('pack', 'pack', [CompletionResultType]::ParameterValue, ".NET Core NuGet Package Packer")
                [CompletionResult]::new('package', 'package', [CompletionResultType]::ParameterValue, "package")
                [CompletionResult]::new('project', 'project', [CompletionResultType]::ParameterValue, "project")
                [CompletionResult]::new('publish', 'publish', [CompletionResultType]::ParameterValue, "Publisher for the .NET Platform")
                [CompletionResult]::new('reference', 'reference', [CompletionResultType]::ParameterValue, ".NET Remove Command")
                [CompletionResult]::new('restore', 'restore', [CompletionResultType]::ParameterValue, ".NET dependency restorer")
                [CompletionResult]::new('run', 'run', [CompletionResultType]::ParameterValue, ".NET Run Command")
                [CompletionResult]::new('solution', 'solution', [CompletionResultType]::ParameterValue, ".NET modify solution file command")
                [CompletionResult]::new('solution', 'sln', [CompletionResultType]::ParameterValue, ".NET modify solution file command")
                [CompletionResult]::new('store', 'store', [CompletionResultType]::ParameterValue, "Stores the specified assemblies for the .NET Platform. By default, these will be optimized for the target runtime and framework.")
                [CompletionResult]::new('test', 'test', [CompletionResultType]::ParameterValue, ".NET Test Command for VSTest. To use Microsoft.Testing.Platform, opt-in to the Microsoft.Testing.Platform-based command via global.json. For more information, see https://aka.ms/dotnet-test.")
                [CompletionResult]::new('tool', 'tool', [CompletionResultType]::ParameterValue, "Install or work with tools that extend the .NET experience.")
                [CompletionResult]::new('vstest', 'vstest', [CompletionResultType]::ParameterValue, "vstest")
                [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, ".NET CLI help utility")
                [CompletionResult]::new('sdk', 'sdk', [CompletionResultType]::ParameterValue, ".NET SDK Command")
                [CompletionResult]::new('workload', 'workload', [CompletionResultType]::ParameterValue, "Install or work with workloads that extend the .NET experience.")
                [CompletionResult]::new('completions', 'completions', [CompletionResultType]::ParameterValue, "Commands for generating and registering completions for supported shells")
                [CompletionResult]::new('dev-certs', 'dev-certs', [CompletionResultType]::ParameterValue, "Create and manage development certificates.")
                [CompletionResult]::new('user-jwts', 'user-jwts', [CompletionResultType]::ParameterValue, "Manage JSON Web Tokens in development.")
                [CompletionResult]::new('user-secrets', 'user-secrets', [CompletionResultType]::ParameterValue, "Manage development user secrets.")
                [CompletionResult]::new('watch', 'watch', [CompletionResultType]::ParameterValue, "Start a file watcher that runs a command when files change.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;build' {
            $staticCompletions = @(
                [CompletionResult]::new('--use-current-runtime', '--use-current-runtime', [CompletionResultType]::ParameterName, "Use current runtime as the target runtime.")
                [CompletionResult]::new('--use-current-runtime', '--ucr', [CompletionResultType]::ParameterName, "Use current runtime as the target runtime.")
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "The target framework to build for. The target framework must also be specified in the project file.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "The target framework to build for. The target framework must also be specified in the project file.")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The configuration to use for building the project. The default for most projects is `'Debug`'.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The configuration to use for building the project. The default for most projects is `'Debug`'.")
                [CompletionResult]::new('--runtime', '--runtime', [CompletionResultType]::ParameterName, "The target runtime to build for.")
                [CompletionResult]::new('--runtime', '-r', [CompletionResultType]::ParameterName, "The target runtime to build for.")
                [CompletionResult]::new('--version-suffix', '--version-suffix', [CompletionResultType]::ParameterName, "Set the value of the `$(VersionSuffix) property to use when building the project.")
                [CompletionResult]::new('--no-restore', '--no-restore', [CompletionResultType]::ParameterName, "Do not restore the project before building.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '--v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--debug', '--debug', [CompletionResultType]::ParameterName, "--debug")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The output directory to place built artifacts in.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The output directory to place built artifacts in.")
                [CompletionResult]::new('--artifacts-path', '--artifacts-path', [CompletionResultType]::ParameterName, "The artifacts path. All output from the project, including build, publish, and pack output, will go in subfolders under the specified path.")
                [CompletionResult]::new('--no-incremental', '--no-incremental', [CompletionResultType]::ParameterName, "Do not use incremental building.")
                [CompletionResult]::new('--no-dependencies', '--no-dependencies', [CompletionResultType]::ParameterName, "Do not build project-to-project references and only build the specified project.")
                [CompletionResult]::new('--nologo', '--nologo', [CompletionResultType]::ParameterName, "Do not display the startup banner or the copyright message.")
                [CompletionResult]::new('--self-contained', '--self-contained', [CompletionResultType]::ParameterName, "Publish the .NET runtime with your application so the runtime doesn`'t need to be installed on the target machine. The default is `'false.`' However, when targeting .NET 7 or lower, the default is `'true`' if a runtime identifier is specified.")
                [CompletionResult]::new('--self-contained', '--sc', [CompletionResultType]::ParameterName, "Publish the .NET runtime with your application so the runtime doesn`'t need to be installed on the target machine. The default is `'false.`' However, when targeting .NET 7 or lower, the default is `'true`' if a runtime identifier is specified.")
                [CompletionResult]::new('--no-self-contained', '--no-self-contained', [CompletionResultType]::ParameterName, "Publish your application as a framework dependent application. A compatible .NET runtime must be installed on the target machine to run your application.")
                [CompletionResult]::new('--arch', '--arch', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--arch', '-a', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--os', '--os', [CompletionResultType]::ParameterName, "The target operating system.")
                [CompletionResult]::new('--disable-build-servers', '--disable-build-servers', [CompletionResultType]::ParameterName, "Force the command to ignore any persistent build servers.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;build-server' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('shutdown', 'shutdown', [CompletionResultType]::ParameterValue, "Shuts down build servers that are started from dotnet. By default, all servers are shut down.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;build-server;shutdown' {
            $staticCompletions = @(
                [CompletionResult]::new('--msbuild', '--msbuild', [CompletionResultType]::ParameterName, "Shut down the MSBuild build server.")
                [CompletionResult]::new('--vbcscompiler', '--vbcscompiler', [CompletionResultType]::ParameterName, "Shut down the VB/C# compiler build server.")
                [CompletionResult]::new('--razor', '--razor', [CompletionResultType]::ParameterName, "Shut down the Razor build server.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;clean' {
            $staticCompletions = @(
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "The target framework to clean for. The target framework must also be specified in the project file.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "The target framework to clean for. The target framework must also be specified in the project file.")
                [CompletionResult]::new('--runtime', '--runtime', [CompletionResultType]::ParameterName, "The target runtime to clean for.")
                [CompletionResult]::new('--runtime', '-r', [CompletionResultType]::ParameterName, "The target runtime to clean for.")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The configuration to clean for. The default for most projects is `'Debug`'.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The configuration to clean for. The default for most projects is `'Debug`'.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The directory containing the build artifacts to clean.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The directory containing the build artifacts to clean.")
                [CompletionResult]::new('--artifacts-path', '--artifacts-path', [CompletionResultType]::ParameterName, "The artifacts path. All output from the project, including build, publish, and pack output, will go in subfolders under the specified path.")
                [CompletionResult]::new('--nologo', '--nologo', [CompletionResultType]::ParameterName, "Do not display the startup banner or the copyright message.")
                [CompletionResult]::new('--disable-build-servers', '--disable-build-servers', [CompletionResultType]::ParameterName, "Force the command to ignore any persistent build servers.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;format' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;fsi' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;msbuild' {
            $staticCompletions = @(
                [CompletionResult]::new('--disable-build-servers', '--disable-build-servers', [CompletionResultType]::ParameterName, "Force the command to ignore any persistent build servers.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;new' {
            $staticCompletions = @(
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "Location to place the generated output.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "Location to place the generated output.")
                [CompletionResult]::new('--name', '--name', [CompletionResultType]::ParameterName, "The name for the output being created. If no name is specified, the name of the output directory is used.")
                [CompletionResult]::new('--name', '-n', [CompletionResultType]::ParameterName, "The name for the output being created. If no name is specified, the name of the output directory is used.")
                [CompletionResult]::new('--dry-run', '--dry-run', [CompletionResultType]::ParameterName, "Displays a summary of what would happen if the given command line were run if it would result in a template creation.")
                [CompletionResult]::new('--force', '--force', [CompletionResultType]::ParameterName, "Forces content to be generated even if it would change existing files.")
                [CompletionResult]::new('--no-update-check', '--no-update-check', [CompletionResultType]::ParameterName, "Disables checking for the template package updates when instantiating a template.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The project that should be used for context evaluation.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--diagnostics', '--diagnostics', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--diagnostics', '-d', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('create', 'create', [CompletionResultType]::ParameterValue, "Instantiates a template with given short name. An alias of `'dotnet new <template name>`'.")
                [CompletionResult]::new('install', 'install', [CompletionResultType]::ParameterValue, "Installs a template package.")
                [CompletionResult]::new('uninstall', 'uninstall', [CompletionResultType]::ParameterValue, "Uninstalls a template package.")
                [CompletionResult]::new('update', 'update', [CompletionResultType]::ParameterValue, "Checks the currently installed template packages for update, and install the updates.")
                [CompletionResult]::new('search', 'search', [CompletionResultType]::ParameterValue, "Searches for the templates on NuGet.org.")
                [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, "Lists templates containing the specified template name. If no name is specified, lists all templates.")
                [CompletionResult]::new('details', 'details', [CompletionResultType]::ParameterValue, "       Provides the details for specified template package.       The command checks if the package is installed locally, if it was not found, it searches the configured NuGet feeds.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;new;create' {
            $staticCompletions = @(
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "Location to place the generated output.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "Location to place the generated output.")
                [CompletionResult]::new('--name', '--name', [CompletionResultType]::ParameterName, "The name for the output being created. If no name is specified, the name of the output directory is used.")
                [CompletionResult]::new('--name', '-n', [CompletionResultType]::ParameterName, "The name for the output being created. If no name is specified, the name of the output directory is used.")
                [CompletionResult]::new('--dry-run', '--dry-run', [CompletionResultType]::ParameterName, "Displays a summary of what would happen if the given command line were run if it would result in a template creation.")
                [CompletionResult]::new('--force', '--force', [CompletionResultType]::ParameterName, "Forces content to be generated even if it would change existing files.")
                [CompletionResult]::new('--no-update-check', '--no-update-check', [CompletionResultType]::ParameterName, "Disables checking for the template package updates when instantiating a template.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The project that should be used for context evaluation.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--diagnostics', '--diagnostics', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--diagnostics', '-d', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;new;install' {
            $staticCompletions = @(
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--add-source', '--add-source', [CompletionResultType]::ParameterName, "Specifies a NuGet source to use.")
                [CompletionResult]::new('--add-source', '--nuget-source', [CompletionResultType]::ParameterName, "Specifies a NuGet source to use.")
                [CompletionResult]::new('--force', '--force', [CompletionResultType]::ParameterName, "Allows installing template packages from the specified sources even if they would override a template package from another source.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--diagnostics', '--diagnostics', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--diagnostics', '-d', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;new;uninstall' {
            $staticCompletions = @(
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--diagnostics', '--diagnostics', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--diagnostics', '-d', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;new;update' {
            $staticCompletions = @(
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--add-source', '--add-source', [CompletionResultType]::ParameterName, "Specifies a NuGet source to use.")
                [CompletionResult]::new('--add-source', '--nuget-source', [CompletionResultType]::ParameterName, "Specifies a NuGet source to use.")
                [CompletionResult]::new('--check-only', '--check-only', [CompletionResultType]::ParameterName, "Only checks for updates and display the template packages to be updated without applying update.")
                [CompletionResult]::new('--check-only', '--dry-run', [CompletionResultType]::ParameterName, "Only checks for updates and display the template packages to be updated without applying update.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--diagnostics', '--diagnostics', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--diagnostics', '-d', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;new;search' {
            $staticCompletions = @(
                [CompletionResult]::new('--author', '--author', [CompletionResultType]::ParameterName, "Filters the templates based on the template author.")
                [CompletionResult]::new('--language', '--language', [CompletionResultType]::ParameterName, "Filters templates based on language.")
                [CompletionResult]::new('--language', '-lang', [CompletionResultType]::ParameterName, "Filters templates based on language.")
                [CompletionResult]::new('--type', '--type', [CompletionResultType]::ParameterName, "Filters templates based on available types. Predefined values are `"project`" and `"item`".")
                [CompletionResult]::new('--tag', '--tag', [CompletionResultType]::ParameterName, "Filters the templates based on the tag.")
                [CompletionResult]::new('--package', '--package', [CompletionResultType]::ParameterName, "Filters the templates based on NuGet package ID.")
                [CompletionResult]::new('--columns-all', '--columns-all', [CompletionResultType]::ParameterName, "Displays all columns in the output.")
                [CompletionResult]::new('--columns', '--columns', [CompletionResultType]::ParameterName, "Specifies the columns to display in the output. ")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--diagnostics', '--diagnostics', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--diagnostics', '-d', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;new;list' {
            $staticCompletions = @(
                [CompletionResult]::new('--author', '--author', [CompletionResultType]::ParameterName, "Filters the templates based on the template author.")
                [CompletionResult]::new('--language', '--language', [CompletionResultType]::ParameterName, "Filters templates based on language.")
                [CompletionResult]::new('--language', '-lang', [CompletionResultType]::ParameterName, "Filters templates based on language.")
                [CompletionResult]::new('--type', '--type', [CompletionResultType]::ParameterName, "Filters templates based on available types. Predefined values are `"project`" and `"item`".")
                [CompletionResult]::new('--tag', '--tag', [CompletionResultType]::ParameterName, "Filters the templates based on the tag.")
                [CompletionResult]::new('--ignore-constraints', '--ignore-constraints', [CompletionResultType]::ParameterName, "Disables checking if the template meets the constraints to be run.")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "Location to place the generated output.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "Location to place the generated output.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The project that should be used for context evaluation.")
                [CompletionResult]::new('--columns-all', '--columns-all', [CompletionResultType]::ParameterName, "Displays all columns in the output.")
                [CompletionResult]::new('--columns', '--columns', [CompletionResultType]::ParameterName, "Specifies the columns to display in the output. ")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--diagnostics', '--diagnostics', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--diagnostics', '-d', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;new;details' {
            $staticCompletions = @(
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--add-source', '--add-source', [CompletionResultType]::ParameterName, "Specifies a NuGet source to use.")
                [CompletionResult]::new('--add-source', '--nuget-source', [CompletionResultType]::ParameterName, "Specifies a NuGet source to use.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Sets the verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], and diag[nostic].")
                [CompletionResult]::new('--diagnostics', '--diagnostics', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--diagnostics', '-d', [CompletionResultType]::ParameterName, "Enables diagnostic output.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget' {
            $staticCompletions = @(
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "--version")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "--verbosity")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "--verbosity")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('delete', 'delete', [CompletionResultType]::ParameterValue, "delete")
                [CompletionResult]::new('locals', 'locals', [CompletionResultType]::ParameterValue, "locals")
                [CompletionResult]::new('push', 'push', [CompletionResultType]::ParameterValue, "push")
                [CompletionResult]::new('verify', 'verify', [CompletionResultType]::ParameterValue, "verify")
                [CompletionResult]::new('trust', 'trust', [CompletionResultType]::ParameterValue, "trust")
                [CompletionResult]::new('sign', 'sign', [CompletionResultType]::ParameterValue, "sign")
                [CompletionResult]::new('why', 'why', [CompletionResultType]::ParameterValue, "Shows the dependency graph for a particular package for a given project or solution.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;delete' {
            $staticCompletions = @(
                [CompletionResult]::new('--force-english-output', '--force-english-output', [CompletionResultType]::ParameterName, "--force-english-output")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "--source")
                [CompletionResult]::new('--source', '-s', [CompletionResultType]::ParameterName, "--source")
                [CompletionResult]::new('--non-interactive', '--non-interactive', [CompletionResultType]::ParameterName, "--non-interactive")
                [CompletionResult]::new('--api-key', '--api-key', [CompletionResultType]::ParameterName, "--api-key")
                [CompletionResult]::new('--api-key', '-k', [CompletionResultType]::ParameterName, "--api-key")
                [CompletionResult]::new('--no-service-endpoint', '--no-service-endpoint', [CompletionResultType]::ParameterName, "--no-service-endpoint")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;locals' {
            $staticCompletions = @(
                [CompletionResult]::new('--force-english-output', '--force-english-output', [CompletionResultType]::ParameterName, "--force-english-output")
                [CompletionResult]::new('--clear', '--clear', [CompletionResultType]::ParameterName, "--clear")
                [CompletionResult]::new('--clear', '-c', [CompletionResultType]::ParameterName, "--clear")
                [CompletionResult]::new('--list', '--list', [CompletionResultType]::ParameterName, "--list")
                [CompletionResult]::new('--list', '-l', [CompletionResultType]::ParameterName, "--list")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('all', 'all', [CompletionResultType]::ParameterValue, "all")
                [CompletionResult]::new('global-packages', 'global-packages', [CompletionResultType]::ParameterValue, "global-packages")
                [CompletionResult]::new('http-cache', 'http-cache', [CompletionResultType]::ParameterValue, "http-cache")
                [CompletionResult]::new('plugins-cache', 'plugins-cache', [CompletionResultType]::ParameterValue, "plugins-cache")
                [CompletionResult]::new('temp', 'temp', [CompletionResultType]::ParameterValue, "temp")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;push' {
            $staticCompletions = @(
                [CompletionResult]::new('--force-english-output', '--force-english-output', [CompletionResultType]::ParameterName, "--force-english-output")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "--source")
                [CompletionResult]::new('--source', '-s', [CompletionResultType]::ParameterName, "--source")
                [CompletionResult]::new('--symbol-source', '--symbol-source', [CompletionResultType]::ParameterName, "--symbol-source")
                [CompletionResult]::new('--symbol-source', '-ss', [CompletionResultType]::ParameterName, "--symbol-source")
                [CompletionResult]::new('--timeout', '--timeout', [CompletionResultType]::ParameterName, "--timeout")
                [CompletionResult]::new('--timeout', '-t', [CompletionResultType]::ParameterName, "--timeout")
                [CompletionResult]::new('--api-key', '--api-key', [CompletionResultType]::ParameterName, "--api-key")
                [CompletionResult]::new('--api-key', '-k', [CompletionResultType]::ParameterName, "--api-key")
                [CompletionResult]::new('--symbol-api-key', '--symbol-api-key', [CompletionResultType]::ParameterName, "--symbol-api-key")
                [CompletionResult]::new('--symbol-api-key', '-sk', [CompletionResultType]::ParameterName, "--symbol-api-key")
                [CompletionResult]::new('--disable-buffering', '--disable-buffering', [CompletionResultType]::ParameterName, "--disable-buffering")
                [CompletionResult]::new('--disable-buffering', '-d', [CompletionResultType]::ParameterName, "--disable-buffering")
                [CompletionResult]::new('--no-symbols', '--no-symbols', [CompletionResultType]::ParameterName, "--no-symbols")
                [CompletionResult]::new('--no-symbols', '-n', [CompletionResultType]::ParameterName, "--no-symbols")
                [CompletionResult]::new('--no-service-endpoint', '--no-service-endpoint', [CompletionResultType]::ParameterName, "--no-service-endpoint")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--skip-duplicate', '--skip-duplicate', [CompletionResultType]::ParameterName, "--skip-duplicate")
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "--configfile")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;verify' {
            $staticCompletions = @(
                [CompletionResult]::new('--all', '--all', [CompletionResultType]::ParameterName, "--all")
                [CompletionResult]::new('--certificate-fingerprint', '--certificate-fingerprint', [CompletionResultType]::ParameterName, "--certificate-fingerprint")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;trust' {
            $staticCompletions = @(
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "--configfile")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, "list")
                [CompletionResult]::new('author', 'author', [CompletionResultType]::ParameterValue, "author")
                [CompletionResult]::new('repository', 'repository', [CompletionResultType]::ParameterValue, "repository")
                [CompletionResult]::new('source', 'source', [CompletionResultType]::ParameterValue, "source")
                [CompletionResult]::new('certificate', 'certificate', [CompletionResultType]::ParameterValue, "certificate")
                [CompletionResult]::new('remove', 'remove', [CompletionResultType]::ParameterValue, "remove")
                [CompletionResult]::new('sync', 'sync', [CompletionResultType]::ParameterValue, "sync")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;trust;list' {
            $staticCompletions = @(
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "--configfile")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;trust;author' {
            $staticCompletions = @(
                [CompletionResult]::new('--allow-untrusted-root', '--allow-untrusted-root', [CompletionResultType]::ParameterName, "--allow-untrusted-root")
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "--configfile")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;trust;repository' {
            $staticCompletions = @(
                [CompletionResult]::new('--allow-untrusted-root', '--allow-untrusted-root', [CompletionResultType]::ParameterName, "--allow-untrusted-root")
                [CompletionResult]::new('--owners', '--owners', [CompletionResultType]::ParameterName, "--owners")
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "--configfile")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;trust;source' {
            $staticCompletions = @(
                [CompletionResult]::new('--owners', '--owners', [CompletionResultType]::ParameterName, "--owners")
                [CompletionResult]::new('--source-url', '--source-url', [CompletionResultType]::ParameterName, "--source-url")
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "--configfile")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;trust;certificate' {
            $staticCompletions = @(
                [CompletionResult]::new('--allow-untrusted-root', '--allow-untrusted-root', [CompletionResultType]::ParameterName, "--allow-untrusted-root")
                [CompletionResult]::new('--algorithm', '--algorithm', [CompletionResultType]::ParameterName, "--algorithm")
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "--configfile")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;trust;remove' {
            $staticCompletions = @(
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "--configfile")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;trust;sync' {
            $staticCompletions = @(
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "--configfile")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;sign' {
            $staticCompletions = @(
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "--output")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "--output")
                [CompletionResult]::new('--certificate-path', '--certificate-path', [CompletionResultType]::ParameterName, "--certificate-path")
                [CompletionResult]::new('--certificate-store-name', '--certificate-store-name', [CompletionResultType]::ParameterName, "--certificate-store-name")
                [CompletionResult]::new('--certificate-store-location', '--certificate-store-location', [CompletionResultType]::ParameterName, "--certificate-store-location")
                [CompletionResult]::new('--certificate-subject-name', '--certificate-subject-name', [CompletionResultType]::ParameterName, "--certificate-subject-name")
                [CompletionResult]::new('--certificate-fingerprint', '--certificate-fingerprint', [CompletionResultType]::ParameterName, "--certificate-fingerprint")
                [CompletionResult]::new('--certificate-password', '--certificate-password', [CompletionResultType]::ParameterName, "--certificate-password")
                [CompletionResult]::new('--hash-algorithm', '--hash-algorithm', [CompletionResultType]::ParameterName, "--hash-algorithm")
                [CompletionResult]::new('--timestamper', '--timestamper', [CompletionResultType]::ParameterName, "--timestamper")
                [CompletionResult]::new('--timestamp-hash-algorithm', '--timestamp-hash-algorithm', [CompletionResultType]::ParameterName, "--timestamp-hash-algorithm")
                [CompletionResult]::new('--overwrite', '--overwrite', [CompletionResultType]::ParameterName, "--overwrite")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;nuget;why' {
            $staticCompletions = @(
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "The target framework(s) for which dependency graphs are shown.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "The target framework(s) for which dependency graphs are shown.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help and usage information")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help and usage information")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;pack' {
            $staticCompletions = @(
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The output directory to place built packages in.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The output directory to place built packages in.")
                [CompletionResult]::new('--artifacts-path', '--artifacts-path', [CompletionResultType]::ParameterName, "The artifacts path. All output from the project, including build, publish, and pack output, will go in subfolders under the specified path.")
                [CompletionResult]::new('--no-build', '--no-build', [CompletionResultType]::ParameterName, "Do not build the project before packing. Implies --no-restore.")
                [CompletionResult]::new('--include-symbols', '--include-symbols', [CompletionResultType]::ParameterName, "Include packages with symbols in addition to regular packages in output directory.")
                [CompletionResult]::new('--include-source', '--include-source', [CompletionResultType]::ParameterName, "Include PDBs and source files. Source files go into the `'src`' folder in the resulting nuget package.")
                [CompletionResult]::new('--serviceable', '--serviceable', [CompletionResultType]::ParameterName, "Set the serviceable flag in the package. See https://aka.ms/nupkgservicing for more information.")
                [CompletionResult]::new('--serviceable', '-s', [CompletionResultType]::ParameterName, "Set the serviceable flag in the package. See https://aka.ms/nupkgservicing for more information.")
                [CompletionResult]::new('--nologo', '--nologo', [CompletionResultType]::ParameterName, "Do not display the startup banner or the copyright message.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--no-restore', '--no-restore', [CompletionResultType]::ParameterName, "Do not restore the project before building.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '--v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--version-suffix', '--version-suffix', [CompletionResultType]::ParameterName, "Set the value of the `$(VersionSuffix) property to use when building the project.")
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "The version of the package to create")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The configuration to use for building the package. The default is `'Release`'.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The configuration to use for building the package. The default is `'Release`'.")
                [CompletionResult]::new('--disable-build-servers', '--disable-build-servers', [CompletionResultType]::ParameterName, "Force the command to ignore any persistent build servers.")
                [CompletionResult]::new('--use-current-runtime', '--use-current-runtime', [CompletionResultType]::ParameterName, "Use current runtime as the target runtime.")
                [CompletionResult]::new('--use-current-runtime', '--ucr', [CompletionResultType]::ParameterName, "Use current runtime as the target runtime.")
                [CompletionResult]::new('--runtime', '--runtime', [CompletionResultType]::ParameterName, "The target runtime to build for.")
                [CompletionResult]::new('--runtime', '-r', [CompletionResultType]::ParameterName, "The target runtime to build for.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;package' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('search', 'search', [CompletionResultType]::ParameterValue, "Searches one or more package sources for packages that match a search term. If no sources are specified, all sources defined in the NuGet.Config are used.")
                [CompletionResult]::new('add', 'add', [CompletionResultType]::ParameterValue, "Add a NuGet package reference to the project.")
                [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, "List all package references of the project or solution.")
                [CompletionResult]::new('remove', 'remove', [CompletionResultType]::ParameterValue, "Remove a NuGet package reference from the project.")
                [CompletionResult]::new('update', 'update', [CompletionResultType]::ParameterValue, "Update referenced packages in a project or solution.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;package;search' {
            $staticCompletions = @(
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "The package source to search. You can pass multiple ``--source`` options to search multiple package sources. Example: ``--source https://api.nuget.org/v3/index.json``.")
                [CompletionResult]::new('--take', '--take', [CompletionResultType]::ParameterName, "Number of results to return. Default 20.")
                [CompletionResult]::new('--skip', '--skip', [CompletionResultType]::ParameterName, "Number of results to skip, to allow pagination. Default 0.")
                [CompletionResult]::new('--exact-match', '--exact-match', [CompletionResultType]::ParameterName, "Require that the search term exactly match the name of the package. Causes ``--take`` and ``--skip`` options to be ignored.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--prerelease', '--prerelease', [CompletionResultType]::ParameterName, "Include prerelease packages.")
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "The NuGet configuration file. If specified, only the settings from this file will be used. If not specified, the hierarchy of configuration files from the current directory will be used. For more information, see https://docs.microsoft.com/nuget/consume-packages/configuring-nuget-behavior")
                [CompletionResult]::new('--format', '--format', [CompletionResultType]::ParameterName, "Format the output accordingly. Either ``table``, or ``json``. The default value is ``table``.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Display this amount of details in the output: ``normal``, ``minimal``, ``detailed``. The default is ``normal``")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;package;add' {
            $staticCompletions = @(
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "The version of the package to add.")
                [CompletionResult]::new('--version', '-v', [CompletionResultType]::ParameterName, "The version of the package to add.")
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "Add the reference only when targeting a specific framework.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "Add the reference only when targeting a specific framework.")
                [CompletionResult]::new('--no-restore', '--no-restore', [CompletionResultType]::ParameterName, "Add the reference without performing restore preview and compatibility check.")
                [CompletionResult]::new('--no-restore', '-n', [CompletionResultType]::ParameterName, "Add the reference without performing restore preview and compatibility check.")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "The NuGet package source to use during the restore.")
                [CompletionResult]::new('--source', '-s', [CompletionResultType]::ParameterName, "The NuGet package source to use during the restore.")
                [CompletionResult]::new('--package-directory', '--package-directory', [CompletionResultType]::ParameterName, "The directory to restore packages to.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--prerelease', '--prerelease', [CompletionResultType]::ParameterName, "Allows prerelease packages to be installed.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The project file to operate on. If a file is not specified, the command will search the current directory for one.")
                [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, "The file-based app to operate on.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;package;list' {
            $staticCompletions = @(
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--outdated', '--outdated', [CompletionResultType]::ParameterName, "Lists packages that have newer versions. Cannot be combined with `'--deprecated`' or `'--vulnerable`' options.")
                [CompletionResult]::new('--deprecated', '--deprecated', [CompletionResultType]::ParameterName, "Lists packages that have been deprecated. Cannot be combined with `'--vulnerable`' or `'--outdated`' options.")
                [CompletionResult]::new('--vulnerable', '--vulnerable', [CompletionResultType]::ParameterName, "Lists packages that have known vulnerabilities. Cannot be combined with `'--deprecated`' or `'--outdated`' options.")
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "Chooses a framework to show its packages. Use the option multiple times for multiple frameworks.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "Chooses a framework to show its packages. Use the option multiple times for multiple frameworks.")
                [CompletionResult]::new('--include-transitive', '--include-transitive', [CompletionResultType]::ParameterName, "Lists transitive and top-level packages.")
                [CompletionResult]::new('--include-prerelease', '--include-prerelease', [CompletionResultType]::ParameterName, "Consider packages with prerelease versions when searching for newer packages. Requires the `'--outdated`' option.")
                [CompletionResult]::new('--highest-patch', '--highest-patch', [CompletionResultType]::ParameterName, "Consider only the packages with a matching major and minor version numbers when searching for newer packages. Requires the `'--outdated`' option.")
                [CompletionResult]::new('--highest-minor', '--highest-minor', [CompletionResultType]::ParameterName, "Consider only the packages with a matching major version number when searching for newer packages. Requires the `'--outdated`' option.")
                [CompletionResult]::new('--config', '--config', [CompletionResultType]::ParameterName, "The path to the NuGet config file to use. Requires the `'--outdated`', `'--deprecated`' or `'--vulnerable`' option.")
                [CompletionResult]::new('--config', '--configfile', [CompletionResultType]::ParameterName, "The path to the NuGet config file to use. Requires the `'--outdated`', `'--deprecated`' or `'--vulnerable`' option.")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "The NuGet sources to use when searching for newer packages. Requires the `'--outdated`', `'--deprecated`' or `'--vulnerable`' option.")
                [CompletionResult]::new('--source', '-s', [CompletionResultType]::ParameterName, "The NuGet sources to use when searching for newer packages. Requires the `'--outdated`', `'--deprecated`' or `'--vulnerable`' option.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--format', '--format', [CompletionResultType]::ParameterName, "Specifies the output format type for the list packages command.")
                [CompletionResult]::new('--output-version', '--output-version', [CompletionResultType]::ParameterName, "Specifies the version of machine-readable output. Requires the `'--format json`' option.")
                [CompletionResult]::new('--no-restore', '--no-restore', [CompletionResultType]::ParameterName, "Do not restore before running the command.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The project file to operate on. If a file is not specified, the command will search the current directory for one.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;package;remove' {
            $staticCompletions = @(
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The project file to operate on. If a file is not specified, the command will search the current directory for one.")
                [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, "The file-based app to operate on.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;package;update' {
            $staticCompletions = @(
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "Path to a project or solution file, or a directory.")
                [CompletionResult]::new('--vulnerable', '--vulnerable', [CompletionResultType]::ParameterName, "Upgrade packages with known vulnerabilities.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the verbosity level of the command. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the verbosity level of the command. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;project' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('convert', 'convert', [CompletionResultType]::ParameterValue, "Convert a file-based program to a project-based program.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;project;convert' {
            $staticCompletions = @(
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "Location to place the generated output.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "Location to place the generated output.")
                [CompletionResult]::new('--force', '--force', [CompletionResultType]::ParameterName, "Force conversion even if there are malformed directives.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--dry-run', '--dry-run', [CompletionResultType]::ParameterName, "Determines changes without actually modifying the file system")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;publish' {
            $staticCompletions = @(
                [CompletionResult]::new('--use-current-runtime', '--use-current-runtime', [CompletionResultType]::ParameterName, "Use current runtime as the target runtime.")
                [CompletionResult]::new('--use-current-runtime', '--ucr', [CompletionResultType]::ParameterName, "Use current runtime as the target runtime.")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The output directory to place the published artifacts in.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The output directory to place the published artifacts in.")
                [CompletionResult]::new('--artifacts-path', '--artifacts-path', [CompletionResultType]::ParameterName, "The artifacts path. All output from the project, including build, publish, and pack output, will go in subfolders under the specified path.")
                [CompletionResult]::new('--manifest', '--manifest', [CompletionResultType]::ParameterName, "The path to a target manifest file that contains the list of packages to be excluded from the publish step.")
                [CompletionResult]::new('--no-build', '--no-build', [CompletionResultType]::ParameterName, "Do not build the project before publishing. Implies --no-restore.")
                [CompletionResult]::new('--self-contained', '--self-contained', [CompletionResultType]::ParameterName, "Publish the .NET runtime with your application so the runtime doesn`'t need to be installed on the target machine. The default is `'false.`' However, when targeting .NET 7 or lower, the default is `'true`' if a runtime identifier is specified.")
                [CompletionResult]::new('--self-contained', '--sc', [CompletionResultType]::ParameterName, "Publish the .NET runtime with your application so the runtime doesn`'t need to be installed on the target machine. The default is `'false.`' However, when targeting .NET 7 or lower, the default is `'true`' if a runtime identifier is specified.")
                [CompletionResult]::new('--no-self-contained', '--no-self-contained', [CompletionResultType]::ParameterName, "Publish your application as a framework dependent application. A compatible .NET runtime must be installed on the target machine to run your application.")
                [CompletionResult]::new('--nologo', '--nologo', [CompletionResultType]::ParameterName, "Do not display the startup banner or the copyright message.")
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "The target framework to publish for. The target framework has to be specified in the project file.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "The target framework to publish for. The target framework has to be specified in the project file.")
                [CompletionResult]::new('--runtime', '--runtime', [CompletionResultType]::ParameterName, "The target runtime to publish for. This is used when creating a self-contained deployment. The default is to publish a framework-dependent application.")
                [CompletionResult]::new('--runtime', '-r', [CompletionResultType]::ParameterName, "The target runtime to publish for. This is used when creating a self-contained deployment. The default is to publish a framework-dependent application.")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The configuration to publish for. The default is `'Release`' for NET 8.0 projects and above, but `'Debug`' for older projects.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The configuration to publish for. The default is `'Release`' for NET 8.0 projects and above, but `'Debug`' for older projects.")
                [CompletionResult]::new('--version-suffix', '--version-suffix', [CompletionResultType]::ParameterName, "Set the value of the `$(VersionSuffix) property to use when building the project.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--no-restore', '--no-restore', [CompletionResultType]::ParameterName, "Do not restore the project before building.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '--v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--arch', '--arch', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--arch', '-a', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--os', '--os', [CompletionResultType]::ParameterName, "The target operating system.")
                [CompletionResult]::new('--disable-build-servers', '--disable-build-servers', [CompletionResultType]::ParameterName, "Force the command to ignore any persistent build servers.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;reference' {
            $staticCompletions = @(
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The project file to operate on. If a file is not specified, the command will search the current directory for one.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('add', 'add', [CompletionResultType]::ParameterValue, "Add a project-to-project reference to the project.")
                [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, "List all project-to-project references of the project.")
                [CompletionResult]::new('remove', 'remove', [CompletionResultType]::ParameterValue, "Remove a project-to-project reference from the project.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;reference;add' {
            $staticCompletions = @(
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "Add the reference only when targeting a specific framework.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "Add the reference only when targeting a specific framework.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The project file to operate on. If a file is not specified, the command will search the current directory for one.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;reference;list' {
            $staticCompletions = @(
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The project file to operate on. If a file is not specified, the command will search the current directory for one.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;reference;remove' {
            $staticCompletions = @(
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "Remove the reference only when targeting a specific framework.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "Remove the reference only when targeting a specific framework.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The project file to operate on. If a file is not specified, the command will search the current directory for one.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;restore' {
            $staticCompletions = @(
                [CompletionResult]::new('--disable-build-servers', '--disable-build-servers', [CompletionResultType]::ParameterName, "Force the command to ignore any persistent build servers.")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "The NuGet package source to use for the restore.")
                [CompletionResult]::new('--source', '-s', [CompletionResultType]::ParameterName, "The NuGet package source to use for the restore.")
                [CompletionResult]::new('--packages', '--packages', [CompletionResultType]::ParameterName, "The directory to restore packages to.")
                [CompletionResult]::new('--use-current-runtime', '--use-current-runtime', [CompletionResultType]::ParameterName, "Use current runtime as the target runtime.")
                [CompletionResult]::new('--use-current-runtime', '--ucr', [CompletionResultType]::ParameterName, "Use current runtime as the target runtime.")
                [CompletionResult]::new('--disable-parallel', '--disable-parallel', [CompletionResultType]::ParameterName, "Prevent restoring multiple projects in parallel.")
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "The NuGet configuration file to use.")
                [CompletionResult]::new('--no-http-cache', '--no-http-cache', [CompletionResultType]::ParameterName, "Disable Http Caching for packages.")
                [CompletionResult]::new('--ignore-failed-sources', '--ignore-failed-sources', [CompletionResultType]::ParameterName, "Treat package source failures as warnings.")
                [CompletionResult]::new('--force', '--force', [CompletionResultType]::ParameterName, "Force all dependencies to be resolved even if the last restore was successful. This is equivalent to deleting project.assets.json.")
                [CompletionResult]::new('--force', '-f', [CompletionResultType]::ParameterName, "Force all dependencies to be resolved even if the last restore was successful. This is equivalent to deleting project.assets.json.")
                [CompletionResult]::new('--runtime', '--runtime', [CompletionResultType]::ParameterName, "The target runtime to restore packages for.")
                [CompletionResult]::new('--runtime', '-r', [CompletionResultType]::ParameterName, "The target runtime to restore packages for.")
                [CompletionResult]::new('--no-dependencies', '--no-dependencies', [CompletionResultType]::ParameterName, "Do not restore project-to-project references and only restore the specified project.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--artifacts-path', '--artifacts-path', [CompletionResultType]::ParameterName, "The artifacts path. All output from the project, including build, publish, and pack output, will go in subfolders under the specified path.")
                [CompletionResult]::new('--use-lock-file', '--use-lock-file', [CompletionResultType]::ParameterName, "Enables project lock file to be generated and used with restore.")
                [CompletionResult]::new('--locked-mode', '--locked-mode', [CompletionResultType]::ParameterName, "Don`'t allow updating project lock file.")
                [CompletionResult]::new('--lock-file-path', '--lock-file-path', [CompletionResultType]::ParameterName, "Output location where project lock file is written. By default, this is `'PROJECT_ROOT\packages.lock.json`'.")
                [CompletionResult]::new('--force-evaluate', '--force-evaluate', [CompletionResultType]::ParameterName, "Forces restore to reevaluate all dependencies even if a lock file already exists.")
                [CompletionResult]::new('--arch', '--arch', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--arch', '-a', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--os', '--os', [CompletionResultType]::ParameterName, "The target operating system.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;run' {
            $staticCompletions = @(
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The configuration to run for. The default for most projects is `'Debug`'.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The configuration to run for. The default for most projects is `'Debug`'.")
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "The target framework to run for. The target framework must also be specified in the project file.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "The target framework to run for. The target framework must also be specified in the project file.")
                [CompletionResult]::new('--runtime', '--runtime', [CompletionResultType]::ParameterName, "The target runtime to run for.")
                [CompletionResult]::new('--runtime', '-r', [CompletionResultType]::ParameterName, "The target runtime to run for.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The path to the project file to run (defaults to the current directory if there is only one project).")
                [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, "The path to the file-based app to run (can be also passed as the first argument if there is no project in the current directory).")
                [CompletionResult]::new('--launch-profile', '--launch-profile', [CompletionResultType]::ParameterName, "The name of the launch profile (if any) to use when launching the application.")
                [CompletionResult]::new('--launch-profile', '-lp', [CompletionResultType]::ParameterName, "The name of the launch profile (if any) to use when launching the application.")
                [CompletionResult]::new('--no-launch-profile', '--no-launch-profile', [CompletionResultType]::ParameterName, "Do not attempt to use launchSettings.json or [app].run.json to configure the application.")
                [CompletionResult]::new('--no-build', '--no-build', [CompletionResultType]::ParameterName, "Do not build the project before running. Implies --no-restore.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--no-restore', '--no-restore', [CompletionResultType]::ParameterName, "Do not restore the project before building.")
                [CompletionResult]::new('--no-cache', '--no-cache', [CompletionResultType]::ParameterName, "Skip up to date checks and always build the program before running.")
                [CompletionResult]::new('--self-contained', '--self-contained', [CompletionResultType]::ParameterName, "Publish the .NET runtime with your application so the runtime doesn`'t need to be installed on the target machine. The default is `'false.`' However, when targeting .NET 7 or lower, the default is `'true`' if a runtime identifier is specified.")
                [CompletionResult]::new('--self-contained', '--sc', [CompletionResultType]::ParameterName, "Publish the .NET runtime with your application so the runtime doesn`'t need to be installed on the target machine. The default is `'false.`' However, when targeting .NET 7 or lower, the default is `'true`' if a runtime identifier is specified.")
                [CompletionResult]::new('--no-self-contained', '--no-self-contained', [CompletionResultType]::ParameterName, "Publish your application as a framework dependent application. A compatible .NET runtime must be installed on the target machine to run your application.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '--v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--arch', '--arch', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--arch', '-a', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--os', '--os', [CompletionResultType]::ParameterName, "The target operating system.")
                [CompletionResult]::new('--disable-build-servers', '--disable-build-servers', [CompletionResultType]::ParameterName, "Force the command to ignore any persistent build servers.")
                [CompletionResult]::new('--artifacts-path', '--artifacts-path', [CompletionResultType]::ParameterName, "The artifacts path. All output from the project, including build, publish, and pack output, will go in subfolders under the specified path.")
                [CompletionResult]::new('--environment', '--environment', [CompletionResultType]::ParameterName, "Sets the value of an environment variable.  Creates the variable if it does not exist, overrides if it does.  This argument can be specified multiple times to provide multiple variables.  Examples: -e VARIABLE=abc -e VARIABLE=`"value with spaces`" -e VARIABLE=`"value;seperated with;semicolons`" -e VAR1=abc -e VAR2=def -e VAR3=ghi ")
                [CompletionResult]::new('--environment', '-e', [CompletionResultType]::ParameterName, "Sets the value of an environment variable.  Creates the variable if it does not exist, overrides if it does.  This argument can be specified multiple times to provide multiple variables.  Examples: -e VARIABLE=abc -e VARIABLE=`"value with spaces`" -e VARIABLE=`"value;seperated with;semicolons`" -e VAR1=abc -e VAR2=def -e VAR3=ghi ")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;solution' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('add', 'add', [CompletionResultType]::ParameterValue, "Add one or more projects to a solution file.")
                [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, "List all projects in a solution file.")
                [CompletionResult]::new('remove', 'remove', [CompletionResultType]::ParameterValue, "Remove one or more projects from a solution file.")
                [CompletionResult]::new('migrate', 'migrate', [CompletionResultType]::ParameterValue, "Generate a .slnx file from a .sln file.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;solution;add' {
            $staticCompletions = @(
                [CompletionResult]::new('--in-root', '--in-root', [CompletionResultType]::ParameterName, "Place project in root of the solution, rather than creating a solution folder.")
                [CompletionResult]::new('--solution-folder', '--solution-folder', [CompletionResultType]::ParameterName, "The destination solution folder path to add the projects to.")
                [CompletionResult]::new('--solution-folder', '-s', [CompletionResultType]::ParameterName, "The destination solution folder path to add the projects to.")
                [CompletionResult]::new('--include-references', '--include-references', [CompletionResultType]::ParameterName, "Recursively add projects`' ReferencedProjects to solution")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;solution;list' {
            $staticCompletions = @(
                [CompletionResult]::new('--solution-folders', '--solution-folders', [CompletionResultType]::ParameterName, "Display solution folder paths.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;solution;remove' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;solution;migrate' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;store' {
            $staticCompletions = @(
                [CompletionResult]::new('--manifest', '--manifest', [CompletionResultType]::ParameterName, "The XML file that contains the list of packages to be stored.")
                [CompletionResult]::new('--manifest', '-m', [CompletionResultType]::ParameterName, "The XML file that contains the list of packages to be stored.")
                [CompletionResult]::new('--framework-version', '--framework-version', [CompletionResultType]::ParameterName, "The Microsoft.NETCore.App package version that will be used to run the assemblies.")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The output directory to store the given assemblies in.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The output directory to store the given assemblies in.")
                [CompletionResult]::new('--working-dir', '--working-dir', [CompletionResultType]::ParameterName, "The working directory used by the command to execute.")
                [CompletionResult]::new('--working-dir', '-w', [CompletionResultType]::ParameterName, "The working directory used by the command to execute.")
                [CompletionResult]::new('--skip-optimization', '--skip-optimization', [CompletionResultType]::ParameterName, "Skip the optimization phase.")
                [CompletionResult]::new('--skip-symbols', '--skip-symbols', [CompletionResultType]::ParameterName, "Skip creating symbol files which can be used for profiling the optimized assemblies.")
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "The target framework to store packages for. The target framework has to be specified in the project file.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "The target framework to store packages for. The target framework has to be specified in the project file.")
                [CompletionResult]::new('--runtime', '--runtime', [CompletionResultType]::ParameterName, "The target runtime to store packages for.")
                [CompletionResult]::new('--runtime', '-r', [CompletionResultType]::ParameterName, "The target runtime to store packages for.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '--v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--use-current-runtime', '--use-current-runtime', [CompletionResultType]::ParameterName, "Use current runtime as the target runtime.")
                [CompletionResult]::new('--use-current-runtime', '--ucr', [CompletionResultType]::ParameterName, "Use current runtime as the target runtime.")
                [CompletionResult]::new('--disable-build-servers', '--disable-build-servers', [CompletionResultType]::ParameterName, "Force the command to ignore any persistent build servers.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;test' {
            $staticCompletions = @(
                [CompletionResult]::new('--settings', '--settings', [CompletionResultType]::ParameterName, "The settings file to use when running tests.")
                [CompletionResult]::new('--settings', '-s', [CompletionResultType]::ParameterName, "The settings file to use when running tests.")
                [CompletionResult]::new('--list-tests', '--list-tests', [CompletionResultType]::ParameterName, "List the discovered tests instead of running the tests.")
                [CompletionResult]::new('--list-tests', '-t', [CompletionResultType]::ParameterName, "List the discovered tests instead of running the tests.")
                [CompletionResult]::new('--environment', '--environment', [CompletionResultType]::ParameterName, "Sets the value of an environment variable.  Creates the variable if it does not exist, overrides if it does.  This will force the tests to be run in an isolated process.  This argument can be specified multiple times to provide multiple variables.  Examples: -e VARIABLE=abc -e VARIABLE=`"value with spaces`" -e VARIABLE=`"value;seperated with;semicolons`" -e VAR1=abc -e VAR2=def -e VAR3=ghi ")
                [CompletionResult]::new('--environment', '-e', [CompletionResultType]::ParameterName, "Sets the value of an environment variable.  Creates the variable if it does not exist, overrides if it does.  This will force the tests to be run in an isolated process.  This argument can be specified multiple times to provide multiple variables.  Examples: -e VARIABLE=abc -e VARIABLE=`"value with spaces`" -e VARIABLE=`"value;seperated with;semicolons`" -e VAR1=abc -e VAR2=def -e VAR3=ghi ")
                [CompletionResult]::new('--filter', '--filter', [CompletionResultType]::ParameterName, "Run tests that match the given expression.                                         Examples:                                         Run tests with priority set to 1: --filter `"Priority = 1`"                                         Run a test with the specified full name: --filter `"FullyQualifiedName=Namespace.ClassName.MethodName`"                                         Run tests that contain the specified name: --filter `"FullyQualifiedName~Namespace.Class`"                                         See https://aka.ms/vstest-filtering for more information on filtering support.                                         ")
                [CompletionResult]::new('--test-adapter-path', '--test-adapter-path', [CompletionResultType]::ParameterName, "The path to the custom adapters to use for the test run.")
                [CompletionResult]::new('--logger', '--logger', [CompletionResultType]::ParameterName, "The logger to use for test results.                                         Examples:                                         Log in trx format using a unique file name: --logger trx                                         Log in trx format using the specified file name: --logger `"trx;LogFileName=<TestResults.trx>`"                                         See https://aka.ms/vstest-report for more information on logger arguments.")
                [CompletionResult]::new('--logger', '-l', [CompletionResultType]::ParameterName, "The logger to use for test results.                                         Examples:                                         Log in trx format using a unique file name: --logger trx                                         Log in trx format using the specified file name: --logger `"trx;LogFileName=<TestResults.trx>`"                                         See https://aka.ms/vstest-report for more information on logger arguments.")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The output directory to place built artifacts in.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The output directory to place built artifacts in.")
                [CompletionResult]::new('--artifacts-path', '--artifacts-path', [CompletionResultType]::ParameterName, "The artifacts path. All output from the project, including build, publish, and pack output, will go in subfolders under the specified path.")
                [CompletionResult]::new('--diag', '--diag', [CompletionResultType]::ParameterName, "Enable verbose logging to the specified file.")
                [CompletionResult]::new('--diag', '-d', [CompletionResultType]::ParameterName, "Enable verbose logging to the specified file.")
                [CompletionResult]::new('--no-build', '--no-build', [CompletionResultType]::ParameterName, "Do not build the project before testing. Implies --no-restore.")
                [CompletionResult]::new('--results-directory', '--results-directory', [CompletionResultType]::ParameterName, "The directory where the test results will be placed. The specified directory will be created if it does not exist.")
                [CompletionResult]::new('--collect', '--collect', [CompletionResultType]::ParameterName, "The friendly name of the data collector to use for the test run.                                         More info here: https://aka.ms/vstest-collect")
                [CompletionResult]::new('--blame', '--blame', [CompletionResultType]::ParameterName, "Runs the tests in blame mode. This option is helpful in isolating problematic tests that cause the test host to crash or hang, but it does not create a memory dump by default.  When a crash is detected, it creates an sequence file in TestResults/guid/guid_Sequence.xml that captures the order of tests that were run before the crash.  Based on the additional settings, hang dump or crash dump can also be collected.  Example:   Timeout the test run when test takes more than the default timeout of 1 hour, and collect crash dump when the test host exits unexpectedly.   (Crash dumps require additional setup, see below.)   dotnet test --blame-hang --blame-crash Example:   Timeout the test run when a test takes more than 20 minutes and collect hang dump.   dotnet test --blame-hang-timeout 20min ")
                [CompletionResult]::new('--blame-crash', '--blame-crash', [CompletionResultType]::ParameterName, "Runs the tests in blame mode and collects a crash dump when the test host exits unexpectedly. This option depends on the version of .NET used, the type of error, and the operating system.  For exceptions in managed code, a dump will be automatically collected on .NET 5.0 and later versions. It will generate a dump for testhost or any child process that also ran on .NET 5.0 and crashed. Crashes in native code will not generate a dump. This option works on Windows, macOS, and Linux.  Crash dumps in native code, or when targetting .NET Framework, or .NET Core 3.1 and earlier versions, can only be collected on Windows, by using Procdump. A directory that contains procdump.exe and procdump64.exe must be in the PATH or PROCDUMP_PATH environment variable.  The tools can be downloaded here: https://docs.microsoft.com/sysinternals/downloads/procdump  To collect a crash dump from a native application running on .NET 5.0 or later, the usage of Procdump can be forced by setting the VSTEST_DUMP_FORCEPROCDUMP environment variable to 1.  Implies --blame.")
                [CompletionResult]::new('--blame-crash-dump-type', '--blame-crash-dump-type', [CompletionResultType]::ParameterName, "The type of crash dump to be collected. Supported values are full (default) and mini. Implies --blame-crash.")
                [CompletionResult]::new('--blame-crash-collect-always', '--blame-crash-collect-always', [CompletionResultType]::ParameterName, "Enables collecting crash dump on expected as well as unexpected testhost exit.")
                [CompletionResult]::new('--blame-hang', '--blame-hang', [CompletionResultType]::ParameterName, "Run the tests in blame mode and enables collecting hang dump when test exceeds the given timeout.")
                [CompletionResult]::new('--blame-hang-dump-type', '--blame-hang-dump-type', [CompletionResultType]::ParameterName, "The type of crash dump to be collected. The supported values are full (default), mini, and none. When `'none`' is used then test host is terminated on timeout, but no dump is collected. Implies --blame-hang.")
                [CompletionResult]::new('--blame-hang-timeout', '--blame-hang-timeout', [CompletionResultType]::ParameterName, "Per-test timeout, after which hang dump is triggered and the testhost process is terminated. Default is 1h. The timeout value is specified in the following format: 1.5h / 90m / 5400s / 5400000ms. When no unit is used (e.g. 5400000), the value is assumed to be in milliseconds. When used together with data driven tests, the timeout behavior depends on the test adapter used. For xUnit, NUnit and MSTest 2.2.4+ the timeout is renewed after every test case, For MSTest before 2.2.4, the timeout is used for all testcases.")
                [CompletionResult]::new('--nologo', '--nologo', [CompletionResultType]::ParameterName, "Run test(s), without displaying Microsoft Testplatform banner")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The configuration to use for running tests. The default for most projects is `'Debug`'.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The configuration to use for running tests. The default for most projects is `'Debug`'.")
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "The target framework to run tests for. The target framework must also be specified in the project file.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "The target framework to run tests for. The target framework must also be specified in the project file.")
                [CompletionResult]::new('--runtime', '--runtime', [CompletionResultType]::ParameterName, "The target runtime to test for.")
                [CompletionResult]::new('--runtime', '-r', [CompletionResultType]::ParameterName, "The target runtime to test for.")
                [CompletionResult]::new('--no-restore', '--no-restore', [CompletionResultType]::ParameterName, "Do not restore the project before building.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '--v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '/verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--arch', '--arch', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--arch', '-a', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--os', '--os', [CompletionResultType]::ParameterName, "The target operating system.")
                [CompletionResult]::new('--disable-build-servers', '--disable-build-servers', [CompletionResultType]::ParameterName, "Force the command to ignore any persistent build servers.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;tool' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('install', 'install', [CompletionResultType]::ParameterValue, "Install global or local tool. Local tools are added to manifest and restored.")
                [CompletionResult]::new('uninstall', 'uninstall', [CompletionResultType]::ParameterValue, "Uninstall a global tool or local tool.")
                [CompletionResult]::new('update', 'update', [CompletionResultType]::ParameterValue, "Update a global or local tool.")
                [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, "List tools installed globally or locally.")
                [CompletionResult]::new('run', 'run', [CompletionResultType]::ParameterValue, "Run a local tool. Note that this command cannot be used to run a global tool. ")
                [CompletionResult]::new('search', 'search', [CompletionResultType]::ParameterValue, "Search dotnet tools in nuget.org")
                [CompletionResult]::new('restore', 'restore', [CompletionResultType]::ParameterValue, "Restore tools defined in the local tool manifest.")
                [CompletionResult]::new('execute', 'execute', [CompletionResultType]::ParameterValue, "Executes a tool from source without permanently installing it.")
                [CompletionResult]::new('execute', 'exec', [CompletionResultType]::ParameterValue, "Executes a tool from source without permanently installing it.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;tool;install' {
            $staticCompletions = @(
                [CompletionResult]::new('--global', '--global', [CompletionResultType]::ParameterName, "Install the tool for the current user.")
                [CompletionResult]::new('--global', '-g', [CompletionResultType]::ParameterName, "Install the tool for the current user.")
                [CompletionResult]::new('--local', '--local', [CompletionResultType]::ParameterName, "Install the tool and add to the local tool manifest (default).")
                [CompletionResult]::new('--tool-path', '--tool-path', [CompletionResultType]::ParameterName, "The directory where the tool will be installed. The directory will be created if it does not exist.")
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "The version of the tool package to install.")
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "The NuGet configuration file to use.")
                [CompletionResult]::new('--tool-manifest', '--tool-manifest', [CompletionResultType]::ParameterName, "Path to the manifest file.")
                [CompletionResult]::new('--add-source', '--add-source', [CompletionResultType]::ParameterName, "Add an additional NuGet package source to use during installation.")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "Replace all NuGet package sources to use during installation with these.")
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "The target framework to install the tool for.")
                [CompletionResult]::new('--prerelease', '--prerelease', [CompletionResultType]::ParameterName, "Include pre-release packages.")
                [CompletionResult]::new('--disable-parallel', '--disable-parallel', [CompletionResultType]::ParameterName, "Prevent restoring multiple projects in parallel.")
                [CompletionResult]::new('--ignore-failed-sources', '--ignore-failed-sources', [CompletionResultType]::ParameterName, "Treat package source failures as warnings.")
                [CompletionResult]::new('--no-http-cache', '--no-http-cache', [CompletionResultType]::ParameterName, "Do not cache packages and http requests.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--arch', '--arch', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--arch', '-a', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--create-manifest-if-needed', '--create-manifest-if-needed', [CompletionResultType]::ParameterName, "Create a tool manifest if one isn`'t found during tool installation. For information on how manifests are located, see https://aka.ms/dotnet/tools/create-manifest-if-needed")
                [CompletionResult]::new('--allow-downgrade', '--allow-downgrade', [CompletionResultType]::ParameterName, "Allow package downgrade when installing a .NET tool package.")
                [CompletionResult]::new('--allow-roll-forward', '--allow-roll-forward', [CompletionResultType]::ParameterName, "Allow a .NET tool to roll forward to newer versions of the .NET runtime if the runtime it targets isn`'t installed.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;tool;uninstall' {
            $staticCompletions = @(
                [CompletionResult]::new('--global', '--global', [CompletionResultType]::ParameterName, "Uninstall the tool from the current user`'s tools directory.")
                [CompletionResult]::new('--global', '-g', [CompletionResultType]::ParameterName, "Uninstall the tool from the current user`'s tools directory.")
                [CompletionResult]::new('--local', '--local', [CompletionResultType]::ParameterName, "Uninstall the tool and remove it from the local tool manifest.")
                [CompletionResult]::new('--tool-path', '--tool-path', [CompletionResultType]::ParameterName, "The directory containing the tool to uninstall.")
                [CompletionResult]::new('--tool-manifest', '--tool-manifest', [CompletionResultType]::ParameterName, "Path to the manifest file.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;tool;update' {
            $staticCompletions = @(
                [CompletionResult]::new('--global', '--global', [CompletionResultType]::ParameterName, "Install the tool for the current user.")
                [CompletionResult]::new('--global', '-g', [CompletionResultType]::ParameterName, "Install the tool for the current user.")
                [CompletionResult]::new('--local', '--local', [CompletionResultType]::ParameterName, "Install the tool and add to the local tool manifest (default).")
                [CompletionResult]::new('--tool-path', '--tool-path', [CompletionResultType]::ParameterName, "The directory where the tool will be installed. The directory will be created if it does not exist.")
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "The version of the tool package to install.")
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "The NuGet configuration file to use.")
                [CompletionResult]::new('--tool-manifest', '--tool-manifest', [CompletionResultType]::ParameterName, "Path to the manifest file.")
                [CompletionResult]::new('--add-source', '--add-source', [CompletionResultType]::ParameterName, "Add an additional NuGet package source to use during installation.")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "Replace all NuGet package sources to use during installation with these.")
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "The target framework to install the tool for.")
                [CompletionResult]::new('--prerelease', '--prerelease', [CompletionResultType]::ParameterName, "Include pre-release packages.")
                [CompletionResult]::new('--disable-parallel', '--disable-parallel', [CompletionResultType]::ParameterName, "Prevent restoring multiple projects in parallel.")
                [CompletionResult]::new('--ignore-failed-sources', '--ignore-failed-sources', [CompletionResultType]::ParameterName, "Treat package source failures as warnings.")
                [CompletionResult]::new('--no-http-cache', '--no-http-cache', [CompletionResultType]::ParameterName, "Do not cache packages and http requests.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--allow-downgrade', '--allow-downgrade', [CompletionResultType]::ParameterName, "Allow package downgrade when installing a .NET tool package.")
                [CompletionResult]::new('--all', '--all', [CompletionResultType]::ParameterName, "Update all tools.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;tool;list' {
            $staticCompletions = @(
                [CompletionResult]::new('--global', '--global', [CompletionResultType]::ParameterName, "List tools installed for the current user.")
                [CompletionResult]::new('--global', '-g', [CompletionResultType]::ParameterName, "List tools installed for the current user.")
                [CompletionResult]::new('--local', '--local', [CompletionResultType]::ParameterName, "List the tools installed in the local tool manifest.")
                [CompletionResult]::new('--tool-path', '--tool-path', [CompletionResultType]::ParameterName, "The directory containing the tools to list.")
                [CompletionResult]::new('--format', '--format', [CompletionResultType]::ParameterName, "The output format for the list of tools.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;tool;run' {
            $staticCompletions = @(
                [CompletionResult]::new('--allow-roll-forward', '--allow-roll-forward', [CompletionResultType]::ParameterName, "Allow a .NET tool to roll forward to newer versions of the .NET runtime if the runtime it targets isn`'t installed.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;tool;search' {
            $staticCompletions = @(
                [CompletionResult]::new('--detail', '--detail', [CompletionResultType]::ParameterName, "Show detail result of the query.")
                [CompletionResult]::new('--skip', '--skip', [CompletionResultType]::ParameterName, "The number of results to skip, for pagination.")
                [CompletionResult]::new('--take', '--take', [CompletionResultType]::ParameterName, "The number of results to return, for pagination.")
                [CompletionResult]::new('--prerelease', '--prerelease', [CompletionResultType]::ParameterName, "Include pre-release packages.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;tool;restore' {
            $staticCompletions = @(
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "The NuGet configuration file to use.")
                [CompletionResult]::new('--add-source', '--add-source', [CompletionResultType]::ParameterName, "Add an additional NuGet package source to use during installation.")
                [CompletionResult]::new('--tool-manifest', '--tool-manifest', [CompletionResultType]::ParameterName, "Path to the manifest file.")
                [CompletionResult]::new('--disable-parallel', '--disable-parallel', [CompletionResultType]::ParameterName, "Prevent restoring multiple projects in parallel.")
                [CompletionResult]::new('--ignore-failed-sources', '--ignore-failed-sources', [CompletionResultType]::ParameterName, "Treat package source failures as warnings.")
                [CompletionResult]::new('--no-http-cache', '--no-http-cache', [CompletionResultType]::ParameterName, "Do not cache packages and http requests.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;tool;execute' {
            $staticCompletions = @(
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "The version of the tool package to install.")
                [CompletionResult]::new('--yes', '--yes', [CompletionResultType]::ParameterName, "Accept all confirmation prompts using `"yes.`"")
                [CompletionResult]::new('--yes', '-y', [CompletionResultType]::ParameterName, "Accept all confirmation prompts using `"yes.`"")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--allow-roll-forward', '--allow-roll-forward', [CompletionResultType]::ParameterName, "Allow a .NET tool to roll forward to newer versions of the .NET runtime if the runtime it targets isn`'t installed.")
                [CompletionResult]::new('--prerelease', '--prerelease', [CompletionResultType]::ParameterName, "Include pre-release packages.")
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "The NuGet configuration file to use.")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "Replace all NuGet package sources to use during installation with these.")
                [CompletionResult]::new('--add-source', '--add-source', [CompletionResultType]::ParameterName, "Add an additional NuGet package source to use during installation.")
                [CompletionResult]::new('--disable-parallel', '--disable-parallel', [CompletionResultType]::ParameterName, "Prevent restoring multiple projects in parallel.")
                [CompletionResult]::new('--ignore-failed-sources', '--ignore-failed-sources', [CompletionResultType]::ParameterName, "Treat package source failures as warnings.")
                [CompletionResult]::new('--no-http-cache', '--no-http-cache', [CompletionResultType]::ParameterName, "Do not cache packages and http requests.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;vstest' {
            $staticCompletions = @(
                [CompletionResult]::new('--Platform', '--Platform', [CompletionResultType]::ParameterName, "--Platform")
                [CompletionResult]::new('--Framework', '--Framework', [CompletionResultType]::ParameterName, "--Framework")
                [CompletionResult]::new('--logger', '--logger', [CompletionResultType]::ParameterName, "--logger")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;help' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;sdk' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('check', 'check', [CompletionResultType]::ParameterValue, ".NET SDK Check Command")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;sdk;check' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload' {
            $staticCompletions = @(
                [CompletionResult]::new('--info', '--info', [CompletionResultType]::ParameterName, "Display information about installed workloads.")
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "Display the currently installed workload version.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('install', 'install', [CompletionResultType]::ParameterValue, "Install one or more workloads.")
                [CompletionResult]::new('update', 'update', [CompletionResultType]::ParameterValue, "Update all installed workloads.")
                [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, "List workloads available.")
                [CompletionResult]::new('search', 'search', [CompletionResultType]::ParameterValue, "Search for available workloads.")
                [CompletionResult]::new('uninstall', 'uninstall', [CompletionResultType]::ParameterValue, "Uninstall one or more workloads.")
                [CompletionResult]::new('repair', 'repair', [CompletionResultType]::ParameterValue, "Repair workload installations.")
                [CompletionResult]::new('restore', 'restore', [CompletionResultType]::ParameterValue, "Restore workloads required for a project.")
                [CompletionResult]::new('clean', 'clean', [CompletionResultType]::ParameterValue, "Removes workload components that may have been left behind from previous updates and uninstallations.")
                [CompletionResult]::new('config', 'config', [CompletionResultType]::ParameterValue, "Modify or display workload configuration values. To display a value, specify the corresponding command-line option without providing a value.  For example: `"dotnet workload config --update-mode`"")
                [CompletionResult]::new('history', 'history', [CompletionResultType]::ParameterValue, "Shows a history of workload installation actions.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload;install' {
            $staticCompletions = @(
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "The NuGet configuration file to use.")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "The NuGet package source to use during the restore. To specify multiple sources, repeat the option.")
                [CompletionResult]::new('--source', '-s', [CompletionResultType]::ParameterName, "The NuGet package source to use during the restore. To specify multiple sources, repeat the option.")
                [CompletionResult]::new('--include-previews', '--include-previews', [CompletionResultType]::ParameterName, "Allow prerelease workload manifests.")
                [CompletionResult]::new('--skip-manifest-update', '--skip-manifest-update', [CompletionResultType]::ParameterName, "Skip updating the workload manifests.")
                [CompletionResult]::new('--temp-dir', '--temp-dir', [CompletionResultType]::ParameterName, "Specify a temporary directory for this command to download and extract NuGet packages (must be secure).")
                [CompletionResult]::new('--disable-parallel', '--disable-parallel', [CompletionResultType]::ParameterName, "Prevent restoring multiple projects in parallel.")
                [CompletionResult]::new('--ignore-failed-sources', '--ignore-failed-sources', [CompletionResultType]::ParameterName, "Treat package source failures as warnings.")
                [CompletionResult]::new('--no-http-cache', '--no-http-cache', [CompletionResultType]::ParameterName, "Do not cache packages and http requests.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "A workload version to display or one or more workloads and their versions joined by the `'@`' character.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload;update' {
            $staticCompletions = @(
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "The NuGet configuration file to use.")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "The NuGet package source to use during the restore. To specify multiple sources, repeat the option.")
                [CompletionResult]::new('--source', '-s', [CompletionResultType]::ParameterName, "The NuGet package source to use during the restore. To specify multiple sources, repeat the option.")
                [CompletionResult]::new('--include-previews', '--include-previews', [CompletionResultType]::ParameterName, "Allow prerelease workload manifests.")
                [CompletionResult]::new('--temp-dir', '--temp-dir', [CompletionResultType]::ParameterName, "Specify a temporary directory for this command to download and extract NuGet packages (must be secure).")
                [CompletionResult]::new('--from-previous-sdk', '--from-previous-sdk', [CompletionResultType]::ParameterName, "Include workloads installed with earlier SDK versions in update.")
                [CompletionResult]::new('--advertising-manifests-only', '--advertising-manifests-only', [CompletionResultType]::ParameterName, "Only update advertising manifests.")
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "A workload version to display or one or more workloads and their versions joined by the `'@`' character.")
                [CompletionResult]::new('--disable-parallel', '--disable-parallel', [CompletionResultType]::ParameterName, "Prevent restoring multiple projects in parallel.")
                [CompletionResult]::new('--ignore-failed-sources', '--ignore-failed-sources', [CompletionResultType]::ParameterName, "Treat package source failures as warnings.")
                [CompletionResult]::new('--no-http-cache', '--no-http-cache', [CompletionResultType]::ParameterName, "Do not cache packages and http requests.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--from-history', '--from-history', [CompletionResultType]::ParameterName, "Update workloads to a previous version specified by the argument. Use the `'dotnet workload history`' to see available workload history records.")
                [CompletionResult]::new('--manifests-only', '--manifests-only', [CompletionResultType]::ParameterName, "Update to the workload versions specified in the history without changing which workloads are installed. Currently installed workloads will be updated to match the specified history version.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload;list' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload;search' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('version', 'version', [CompletionResultType]::ParameterValue, "`'dotnet workload search version`' has three functions depending on its argument:       1. If no argument is specified, it outputs a list of the latest released workload versions from this feature band. Takes the --take option to specify how many to provide and --format to alter the format.          Example:            dotnet workload search version --take 2 --format json            [{`"workloadVersion`":`"9.0.201`"},{`"workloadVersion`":`"9.0.200.1`"}]       2. If a workload version is provided as an argument, it outputs a table of various workloads and their versions for the specified workload version. Takes the --format option to alter the output format.          Example:            dotnet workload search version 9.0.201            Workload manifest ID                               Manifest feature band      Manifest Version            ------------------------------------------------------------------------------------------------            microsoft.net.workload.emscripten.current          9.0.100-rc.1               9.0.0-rc.1.24430.3            microsoft.net.workload.emscripten.net6             9.0.100-rc.1               9.0.0-rc.1.24430.3            microsoft.net.workload.emscripten.net7             9.0.100-rc.1               9.0.0-rc.1.24430.3            microsoft.net.workload.emscripten.net8             9.0.100-rc.1               9.0.0-rc.1.24430.3            microsoft.net.sdk.android                          9.0.100-rc.1               35.0.0-rc.1.80            microsoft.net.sdk.ios                              9.0.100-rc.1               17.5.9270-net9-rc1            microsoft.net.sdk.maccatalyst                      9.0.100-rc.1               17.5.9270-net9-rc1            microsoft.net.sdk.macos                            9.0.100-rc.1               14.5.9270-net9-rc1            microsoft.net.sdk.maui                             9.0.100-rc.1               9.0.0-rc.1.24453.9            microsoft.net.sdk.tvos                             9.0.100-rc.1               17.5.9270-net9-rc1            microsoft.net.workload.mono.toolchain.current      9.0.100-rc.1               9.0.0-rc.1.24431.7            microsoft.net.workload.mono.toolchain.net6         9.0.100-rc.1               9.0.0-rc.1.24431.7            microsoft.net.workload.mono.toolchain.net7         9.0.100-rc.1               9.0.0-rc.1.24431.7            microsoft.net.workload.mono.toolchain.net8         9.0.100-rc.1               9.0.0-rc.1.24431.7       3. If one or more workloads are provided along with their versions (by joining them with the `'@`' character), it outputs workload versions that match the provided versions. Takes the --take option to specify how many to provide and --format to alter the format.          Example:            dotnet workload search version maui@9.0.0-rc.1.24453.9 ios@17.5.9270-net9-rc1            9.0.201     ")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload;search;version' {
            $staticCompletions = @(
                [CompletionResult]::new('--format', '--format', [CompletionResultType]::ParameterName, "Changes the format of outputted workload versions. Can take `'json`' or `'list`'")
                [CompletionResult]::new('--take', '--take', [CompletionResultType]::ParameterName, "--take")
                [CompletionResult]::new('--include-previews', '--include-previews', [CompletionResultType]::ParameterName, "--include-previews")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload;uninstall' {
            $staticCompletions = @(
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload;repair' {
            $staticCompletions = @(
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "The NuGet configuration file to use.")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "The NuGet package source to use during the restore. To specify multiple sources, repeat the option.")
                [CompletionResult]::new('--source', '-s', [CompletionResultType]::ParameterName, "The NuGet package source to use during the restore. To specify multiple sources, repeat the option.")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--disable-parallel', '--disable-parallel', [CompletionResultType]::ParameterName, "Prevent restoring multiple projects in parallel.")
                [CompletionResult]::new('--ignore-failed-sources', '--ignore-failed-sources', [CompletionResultType]::ParameterName, "Treat package source failures as warnings.")
                [CompletionResult]::new('--no-http-cache', '--no-http-cache', [CompletionResultType]::ParameterName, "Do not cache packages and http requests.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload;restore' {
            $staticCompletions = @(
                [CompletionResult]::new('--configfile', '--configfile', [CompletionResultType]::ParameterName, "The NuGet configuration file to use.")
                [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, "The NuGet package source to use during the restore. To specify multiple sources, repeat the option.")
                [CompletionResult]::new('--source', '-s', [CompletionResultType]::ParameterName, "The NuGet package source to use during the restore. To specify multiple sources, repeat the option.")
                [CompletionResult]::new('--include-previews', '--include-previews', [CompletionResultType]::ParameterName, "Allow prerelease workload manifests.")
                [CompletionResult]::new('--skip-manifest-update', '--skip-manifest-update', [CompletionResultType]::ParameterName, "Skip updating the workload manifests.")
                [CompletionResult]::new('--temp-dir', '--temp-dir', [CompletionResultType]::ParameterName, "Specify a temporary directory for this command to download and extract NuGet packages (must be secure).")
                [CompletionResult]::new('--disable-parallel', '--disable-parallel', [CompletionResultType]::ParameterName, "Prevent restoring multiple projects in parallel.")
                [CompletionResult]::new('--ignore-failed-sources', '--ignore-failed-sources', [CompletionResultType]::ParameterName, "Treat package source failures as warnings.")
                [CompletionResult]::new('--no-http-cache', '--no-http-cache', [CompletionResultType]::ParameterName, "Do not cache packages and http requests.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "A workload version to display or one or more workloads and their versions joined by the `'@`' character.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload;clean' {
            $staticCompletions = @(
                [CompletionResult]::new('--all', '--all', [CompletionResultType]::ParameterName, "Causes clean to remove and uninstall all workload components from all SDK versions.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload;config' {
            $staticCompletions = @(
                [CompletionResult]::new('--update-mode', '--update-mode', [CompletionResultType]::ParameterName, "Controls whether updates should look for workload sets or the latest version of each individual manifest.")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;workload;history' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;completions' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('script', 'script', [CompletionResultType]::ParameterValue, "Generate the completion script for a supported shell")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;completions;script' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show command line help.")
                [CompletionResult]::new('bash', 'bash', [CompletionResultType]::ParameterValue, "Generates a completion script for the Bourne Again SHell (bash).")
                [CompletionResult]::new('fish', 'fish', [CompletionResultType]::ParameterValue, "Generates a completion script for the Fish shell.")
                [CompletionResult]::new('nushell', 'nushell', [CompletionResultType]::ParameterValue, "Generates a completion script for the NuShell shell.")
                [CompletionResult]::new('pwsh', 'pwsh', [CompletionResultType]::ParameterValue, "Generates a completion script for PowerShell Core. These scripts will not work on Windows PowerShell.")
                [CompletionResult]::new('zsh', 'zsh', [CompletionResultType]::ParameterValue, "Generates a completion script for the Zsh shell.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;dev-certs' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('https', 'https', [CompletionResultType]::ParameterValue, "Create, trust, export, import or check the HTTPS development certificate.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;dev-certs;https' {
            $staticCompletions = @(
                [CompletionResult]::new('--export-path', '-ep', [CompletionResultType]::ParameterName, "Full path to the exported certificate")
                [CompletionResult]::new('--export-path', '--export-path', [CompletionResultType]::ParameterName, "Full path to the exported certificate")
                [CompletionResult]::new('--password', '-p', [CompletionResultType]::ParameterName, "Password to use when exporting the certificate with the private key into a pfx file or to encrypt the Pem exported key")
                [CompletionResult]::new('--password', '--password', [CompletionResultType]::ParameterName, "Password to use when exporting the certificate with the private key into a pfx file or to encrypt the Pem exported key")
                [CompletionResult]::new('--no-password', '-np', [CompletionResultType]::ParameterName, "Explicitly request that you don't use a password for the key when exporting a certificate to a PEM format")
                [CompletionResult]::new('--no-password', '--no-password', [CompletionResultType]::ParameterName, "Explicitly request that you don't use a password for the key when exporting a certificate to a PEM format")
                [CompletionResult]::new('--check', '-c', [CompletionResultType]::ParameterName, "Check for the existence of the certificate but do not perform any action")
                [CompletionResult]::new('--check', '--check', [CompletionResultType]::ParameterName, "Check for the existence of the certificate but do not perform any action")
                [CompletionResult]::new('--clean', '--clean', [CompletionResultType]::ParameterName, "Cleans all HTTPS development certificates from the machine.")
                [CompletionResult]::new('--import', '-i', [CompletionResultType]::ParameterName, "Imports the provided HTTPS development certificate into the machine. All other HTTPS developer certificates will be cleared out")
                [CompletionResult]::new('--import', '--import', [CompletionResultType]::ParameterName, "Imports the provided HTTPS development certificate into the machine. All other HTTPS developer certificates will be cleared out")
                [CompletionResult]::new('--format', '--format', [CompletionResultType]::ParameterName, "Export the certificate in the given format. Valid values are Pfx and Pem. Pfx is the default.")
                [CompletionResult]::new('--trust', '-t', [CompletionResultType]::ParameterName, "When not combined with the --check option, trusts the certificate on the current platform, creating one if necessary. When combined with the --check option, validates that there is a certificate and it is trusted.")
                [CompletionResult]::new('--trust', '--trust', [CompletionResultType]::ParameterName, "When not combined with the --check option, trusts the certificate on the current platform, creating one if necessary. When combined with the --check option, validates that there is a certificate and it is trusted.")
                [CompletionResult]::new('--verbose', '-v', [CompletionResultType]::ParameterName, "Display more debug information.")
                [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, "Display more debug information.")
                [CompletionResult]::new('--quiet', '-q', [CompletionResultType]::ParameterName, "Display warnings and errors only.")
                [CompletionResult]::new('--quiet', '--quiet', [CompletionResultType]::ParameterName, "Display warnings and errors only.")
                [CompletionResult]::new('--check-trust-machine-readable', '--check-trust-machine-readable', [CompletionResultType]::ParameterName, "Same as running --check --trust, but output the results in json.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-jwts' {
            $staticCompletions = @(
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('clear', 'clear', [CompletionResultType]::ParameterValue, "Remove all issued JWTs for a project")
                [CompletionResult]::new('create', 'create', [CompletionResultType]::ParameterValue, "Issue a new JSON Web Token")
                [CompletionResult]::new('key', 'key', [CompletionResultType]::ParameterValue, "Display or reset the signing key used to issue JWTs")
                [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, "Lists the JWTs issued for the project")
                [CompletionResult]::new('print', 'print', [CompletionResultType]::ParameterValue, "Print the details of a given JWT")
                [CompletionResult]::new('remove', 'remove', [CompletionResultType]::ParameterValue, "Remove a given JWT")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-jwts;clear' {
            $staticCompletions = @(
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--force', '--force', [CompletionResultType]::ParameterName, "Don't prompt for confirmation before deleting JWTs.")
                [CompletionResult]::new('--appsettings-file', '--appsettings-file', [CompletionResultType]::ParameterName, "The appSettings configuration file to add the test scheme to.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-jwts;create' {
            $staticCompletions = @(
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--scheme', '--scheme', [CompletionResultType]::ParameterName, "The scheme name to use for the generated token. Defaults to 'Bearer'.")
                [CompletionResult]::new('--name', '-n', [CompletionResultType]::ParameterName, "The name of the user to create the JWT for. Defaults to the current environment user.")
                [CompletionResult]::new('--name', '--name', [CompletionResultType]::ParameterName, "The name of the user to create the JWT for. Defaults to the current environment user.")
                [CompletionResult]::new('--audience', '--audience', [CompletionResultType]::ParameterName, "The audiences to create the JWT for. Defaults to the URLs configured in the project's launchSettings.json.")
                [CompletionResult]::new('--issuer', '--issuer', [CompletionResultType]::ParameterName, "The issuer of the JWT. Defaults to 'dotnet-user-jwts'.")
                [CompletionResult]::new('--scope', '--scope', [CompletionResultType]::ParameterName, "A scope claim to add to the JWT. Specify once for each scope.")
                [CompletionResult]::new('--role', '--role', [CompletionResultType]::ParameterName, "A role claim to add to the JWT. Specify once for each role.")
                [CompletionResult]::new('--claim', '--claim', [CompletionResultType]::ParameterName, "Claims to add to the JWT. Specify once for each claim in the format `"name=value`".")
                [CompletionResult]::new('--not-before', '--not-before', [CompletionResultType]::ParameterName, "The UTC date & time the JWT should not be valid before. Defaults to the date & time the JWT is created.")
                [CompletionResult]::new('--expires-on', '--expires-on', [CompletionResultType]::ParameterName, "The UTC date & time the JWT should expire. Defaults to 3 months after the --not-before date.")
                [CompletionResult]::new('--valid-for', '--valid-for', [CompletionResultType]::ParameterName, "The period the JWT should expire after, e.g. '365d'.")
                [CompletionResult]::new('--appsettings-file', '--appsettings-file', [CompletionResultType]::ParameterName, "The appSettings configuration file to add the test scheme to.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-jwts;key' {
            $staticCompletions = @(
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--scheme', '--scheme', [CompletionResultType]::ParameterName, "The scheme name associated with the signing key to be reset or displayed. Defaults to 'Bearer'.")
                [CompletionResult]::new('--issuer', '--issuer', [CompletionResultType]::ParameterName, "The issuer associated with the signing key to be reset or displayed. Defaults to 'dotnet-user-jwts'.")
                [CompletionResult]::new('--reset', '--reset', [CompletionResultType]::ParameterName, "Reset the signing key. This will invalidate all previously issued JWTs for this project.")
                [CompletionResult]::new('--force', '--force', [CompletionResultType]::ParameterName, "Don't prompt for confirmation before resetting the signing key.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-jwts;list' {
            $staticCompletions = @(
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--show-tokens', '--show-tokens', [CompletionResultType]::ParameterName, "Indicates whether JWT base64 strings should be shown.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-jwts;print' {
            $staticCompletions = @(
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--show-all', '--show-all', [CompletionResultType]::ParameterName, "Whether to show all details associated with the JWT.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-jwts;remove' {
            $staticCompletions = @(
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "The path of the project to operate on. Defaults to the project in the current directory.")
                [CompletionResult]::new('--output', '-o', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, "The format to use for displaying output from the command. Can be one of 'default', 'token', or 'json'.")
                [CompletionResult]::new('--appsettings-file', '--appsettings-file', [CompletionResultType]::ParameterName, "The appSettings configuration file to add the test scheme to.")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-secrets' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '-?', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "Show version information")
                [CompletionResult]::new('--verbose', '-v', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--file', '-f', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--id', '--id', [CompletionResultType]::ParameterName, "The user secret ID to use.")
                [CompletionResult]::new('clear', 'clear', [CompletionResultType]::ParameterValue, "Deletes all the application secrets")
                [CompletionResult]::new('init', 'init', [CompletionResultType]::ParameterValue, "Set a user secrets ID to enable secret storage")
                [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, "Lists all the application secrets")
                [CompletionResult]::new('remove', 'remove', [CompletionResultType]::ParameterValue, "Removes the specified user secret")
                [CompletionResult]::new('set', 'set', [CompletionResultType]::ParameterValue, "Sets the user secret to the specified value")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-secrets;clear' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '-?', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--verbose', '-v', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--file', '-f', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--id', '--id', [CompletionResultType]::ParameterName, "The user secret ID to use.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-secrets;init' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '-?', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--verbose', '-v', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--file', '-f', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--id', '--id', [CompletionResultType]::ParameterName, "The user secret ID to use.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-secrets;list' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '-?', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--json', '--json', [CompletionResultType]::ParameterName, "Use json output. JSON is wrapped by '//BEGIN' and '//END'")
                [CompletionResult]::new('--verbose', '-v', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--file', '-f', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--id', '--id', [CompletionResultType]::ParameterName, "The user secret ID to use.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-secrets;remove' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '-?', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--verbose', '-v', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--file', '-f', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--id', '--id', [CompletionResultType]::ParameterName, "The user secret ID to use.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;user-secrets;set' {
            $staticCompletions = @(
                [CompletionResult]::new('--help', '-?', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help information")
                [CompletionResult]::new('--verbose', '-v', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--project', '-p', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "Path to project. Defaults to searching the current directory.")
                [CompletionResult]::new('--file', '-f', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, "Path to file-based app.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The project configuration to use. Defaults to 'Debug'.")
                [CompletionResult]::new('--id', '--id', [CompletionResultType]::ParameterName, "The user secret ID to use.")
            )
            $completions += $staticCompletions
            break
        }
        'dotnet;watch' {
            $staticCompletions = @(
                [CompletionResult]::new('--quiet', '-q', [CompletionResultType]::ParameterName, "Suppresses all output except warnings and errors")
                [CompletionResult]::new('--quiet', '--quiet', [CompletionResultType]::ParameterName, "Suppresses all output except warnings and errors")
                [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--list', '--list', [CompletionResultType]::ParameterName, "Lists all discovered files without starting the watcher.")
                [CompletionResult]::new('--no-hot-reload', '--no-hot-reload', [CompletionResultType]::ParameterName, "Suppress hot reload for supported apps.")
                [CompletionResult]::new('--non-interactive', '--non-interactive', [CompletionResultType]::ParameterName, "Runs dotnet-watch in non-interactive mode. This option is only supported when running with Hot Reload enabled.")
                [CompletionResult]::new('--framework', '-f', [CompletionResultType]::ParameterName, "The target framework to build for. The target framework must also be specified in the project file.")
                [CompletionResult]::new('--framework', '--framework', [CompletionResultType]::ParameterName, "The target framework to build for. The target framework must also be specified in the project file.")
                [CompletionResult]::new('--device', '--device', [CompletionResultType]::ParameterName, "The device identifier to run on (e.g. emulator, simulator, or physical device).")
                [CompletionResult]::new('--project', '--project', [CompletionResultType]::ParameterName, "Defines the path of the project file to run. Use path to the project file, or path to the directory containing the project file.")
                [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, "The path to the file-based app to run.")
                [CompletionResult]::new('--launch-profile', '-lp', [CompletionResultType]::ParameterName, "The name of the launch profile (if any) to use when launching the application.")
                [CompletionResult]::new('--launch-profile', '--launch-profile', [CompletionResultType]::ParameterName, "The name of the launch profile (if any) to use when launching the application.")
                [CompletionResult]::new('--no-launch-profile', '--no-launch-profile', [CompletionResultType]::ParameterName, "Do not attempt to use launchSettings.json or [app].run.json to configure the application.")
                [CompletionResult]::new('--configuration', '-c', [CompletionResultType]::ParameterName, "The configuration to run for. The default for most projects is 'Debug'.")
                [CompletionResult]::new('--configuration', '--configuration', [CompletionResultType]::ParameterName, "The configuration to run for. The default for most projects is 'Debug'.")
                [CompletionResult]::new('--interactive', '--interactive', [CompletionResultType]::ParameterName, "Allows the command to stop and wait for user input or action (for example to complete authentication).")
                [CompletionResult]::new('--no-restore', '--no-restore', [CompletionResultType]::ParameterName, "Do not restore the project before building.")
                [CompletionResult]::new('--self-contained', '--sc', [CompletionResultType]::ParameterName, "Publish the .NET runtime with your application so the runtime doesn't need to be installed on the target machine.")
                [CompletionResult]::new('--self-contained', '--self-contained', [CompletionResultType]::ParameterName, "Publish the .NET runtime with your application so the runtime doesn't need to be installed on the target machine.")
                [CompletionResult]::new('--no-self-contained', '--no-self-contained', [CompletionResultType]::ParameterName, "Publish your application as a framework dependent application.")
                [CompletionResult]::new('--verbosity', '-v', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--verbosity', '--verbosity', [CompletionResultType]::ParameterName, "Set the MSBuild verbosity level. Allowed values are q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].")
                [CompletionResult]::new('--runtime', '-r', [CompletionResultType]::ParameterName, "The target runtime to run for.")
                [CompletionResult]::new('--runtime', '--runtime', [CompletionResultType]::ParameterName, "The target runtime to run for.")
                [CompletionResult]::new('--arch', '-a', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--arch', '--arch', [CompletionResultType]::ParameterName, "The target architecture.")
                [CompletionResult]::new('--os', '--os', [CompletionResultType]::ParameterName, "The target operating system.")
                [CompletionResult]::new('--disable-build-servers', '--disable-build-servers', [CompletionResultType]::ParameterName, "Force the command to ignore any persistent build servers.")
                [CompletionResult]::new('--artifacts-path', '--artifacts-path', [CompletionResultType]::ParameterName, "The artifacts path. All output from the project, including build, publish, and pack output, will go in subfolders under the specified path.")
                [CompletionResult]::new('--help', '-?', [CompletionResultType]::ParameterName, "Show help and usage information")
                [CompletionResult]::new('--help', '-h', [CompletionResultType]::ParameterName, "Show help and usage information")
                [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, "Show help and usage information")
                [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, "Show version information")
                [CompletionResult]::new('run', 'run', [CompletionResultType]::ParameterValue, "Watch the project and rerun 'dotnet run' on changes (the default).")
                [CompletionResult]::new('test', 'test', [CompletionResultType]::ParameterValue, "Watch the project and rerun 'dotnet test' on changes.")
                [CompletionResult]::new('build', 'build', [CompletionResultType]::ParameterValue, "Watch the project and rerun 'dotnet build' on changes.")
            )
            $completions += $staticCompletions
            break
        }
        { $_ -match '^dotnet;watch;(?:run|test|build)(?:;|$)' } {
            # The forwarded command's own options come from the live engine; these
            # are the options dotnet-watch keeps for itself.
            $staticCompletions = @(
                [CompletionResult]::new('--quiet', '-q', [CompletionResultType]::ParameterName, "Suppresses all output except warnings and errors")
                [CompletionResult]::new('--quiet', '--quiet', [CompletionResultType]::ParameterName, "Suppresses all output except warnings and errors")
                [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, "Show verbose output")
                [CompletionResult]::new('--list', '--list', [CompletionResultType]::ParameterName, "Lists all discovered files without starting the watcher.")
                [CompletionResult]::new('--no-hot-reload', '--no-hot-reload', [CompletionResultType]::ParameterName, "Suppress hot reload for supported apps.")
                [CompletionResult]::new('--non-interactive', '--non-interactive', [CompletionResultType]::ParameterName, "Runs dotnet-watch in non-interactive mode. This option is only supported when running with Hot Reload enabled.")
            )
            $completions += $staticCompletions
            break
        }
    }
    $word =if ($null -eq $wordToComplete) { '' } else { $wordToComplete }

    # The vendored table lists every spelling of an option as its own row with the
    # canonical name in CompletionText and the spelling in ListItemText. Match and
    # insert the spelling, so -h is reachable and each alias is a distinct
    # completion rather than N copies of --help.
    $candidates = [ordered]@{}
    foreach ($completion in @($completions)) {
        $name = $completion.ListItemText
        if (-not [string]::IsNullOrWhiteSpace($name) -and -not $candidates.Contains($name)) {
            $candidates[$name] = $completion
        }
    }

    # $cursorPosition is an offset into the whole line; the extent is
    # command-relative and stops at the last token, so a cursor sitting after a
    # trailing space needs the text padded back out to it.
    $relativeCursor = [Math]::Max($cursorPosition - $commandAst.Extent.StartOffset, 0)
    $extentText = $commandAst.Extent.Text
    if ($relativeCursor -gt $extentText.Length) {
        $extentText = $extentText.PadRight($relativeCursor)
    }

    $safeCursor = [Math]::Min($relativeCursor, $extentText.Length)
    # The bundled tools (dev-certs, user-jwts, user-secrets, watch) are outside
    # the SDK's completion engine, which answers them with the root command list.
    # 'watch run|test|build' is the exception: watch forwards the command to the
    # SDK, and the engine answers it exactly as it answers 'dotnet run|test|build'.
    $bundledTool = $command -match '^dotnet;(?:dev-certs|user-jwts|user-secrets|watch)(?:;|$)' -and
        $command -notmatch '^dotnet;watch;(?:run|test|build)(?:;|$)'
    $liveTokens = @(
        if (-not $bundledTool) {
            Get-DotnetLiveCompletion -Text $extentText.Substring(0, $safeCursor) -Position $safeCursor
        }
    )

    $settledTokens = @(
        foreach ($element in @($commandElements | Select-Object -Skip 1)) {
            if ($null -ne $element -and $null -ne $element.Extent -and $element.Extent.EndOffset -lt $cursorPosition) {
                $element.Extent.Text
            }
        }
    )
    $previousToken = if ($settledTokens.Count -gt 0) { $settledTokens[$settledTokens.Count - 1] } else { '' }
    $previousOption = if ($candidates.Contains($previousToken)) { $candidates[$previousToken].CompletionText } else { $previousToken }
    $liveOptionCount = @($liveTokens | Where-Object { Test-DotnetOptionToken -Token $_ }).Count

    if ($liveOptionCount -eq $liveTokens.Count -and (Test-DotnetOptionToken -Token $previousToken)) {
        # A value slot the SDK leaves unanswered (runtime identifiers, launch
        # profiles, ...) gets its values here, or nothing, but never the option list.
        $values = Get-DotnetOptionValue -Command $command -Option $previousOption -SettledTokens $settledTokens
        if ($null -ne $values) {
            $typed = ConvertFrom-DotnetTypedWord -Text $word
            return @(
                foreach ($value in $values) {
                    if ($value.StartsWith($typed.Value, [System.StringComparison]::OrdinalIgnoreCase)) {
                        [CompletionResult]::new((ConvertTo-DotnetArgument -Value $value -Quote $typed.Quote), $value, [CompletionResultType]::ParameterValue, "$previousToken $value")
                    }
                }
            )
        }
    }

    if ($bundledTool -and $previousOption -in @('--file', '--export-path', '--import', '--appsettings-file')) {
        return @([System.Management.Automation.CompletionCompleters]::CompleteFilename($word))
    }

    if ((Test-DotnetPathOption -Token $previousToken) -or ($bundledTool -and $previousOption -eq '--project')) {
        return @(Get-DotnetProjectCompletion -WordToComplete $word -IncludeDirectories $true)
    }

    if ($liveTokens.Count -gt 0 -and $liveOptionCount -eq 0 -and (Test-DotnetOptionToken -Token $previousToken)) {
        # Every live suggestion is a bare value, so this is an option's value slot
        # and the option list must not be repeated into it.
        return @(
            foreach ($token in $liveTokens) {
                if ($token.StartsWith($word, [System.StringComparison]::Ordinal)) {
                    [CompletionResult]::new($token, $token, [CompletionResultType]::ParameterValue, "$previousToken $token")
                }
            }
        )
    }

    foreach ($token in $liveTokens) {
        if (-not $candidates.Contains($token)) {
            $resultType = if (Test-DotnetOptionToken -Token $token) { [CompletionResultType]::ParameterName } else { [CompletionResultType]::ParameterValue }
            $candidates[$token] = [CompletionResult]::new($token, $token, $resultType, $token)
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($name in @($candidates.Keys)) {
        if (-not $name.StartsWith($word, [System.StringComparison]::Ordinal)) {
            continue
        }

        $source = $candidates[$name]
        [void]$results.Add([CompletionResult]::new($name, $name, $source.ResultType, $source.ToolTip))
    }

    $ordered = @($results.ToArray() | Sort-Object -Property ListItemText)

    if (-not (Test-DotnetOptionToken -Token $word)) {
        # Project and solution operands: an empty word offers the projects here, a
        # partial one also walks directories.
        $ordered += @(Get-DotnetProjectCompletion -WordToComplete $word -IncludeDirectories (-not [string]::IsNullOrEmpty($word)))
    }

    $ordered
}
