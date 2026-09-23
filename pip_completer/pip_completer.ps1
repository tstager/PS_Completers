Set-StrictMode -Version Latest

if (-not (Get-Variable -Name PipCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:PipCompletionCache = @{
        Executables = @{}
        Help        = @{}
        Choices     = @{}
    }
}

function Get-PipStaticCommands {
    # Fallback for when pip is not installed; the installed pip's `pip --help` replaces it.
    [ordered]@{
        install    = 'Install packages.'
        lock       = 'Generate a lock file.'
        download   = 'Download packages.'
        uninstall  = 'Uninstall packages.'
        freeze     = 'Output installed packages in requirements format.'
        inspect    = 'Inspect the python environment.'
        list       = 'List installed packages.'
        show       = 'Show information about installed packages.'
        check      = 'Verify installed packages have compatible dependencies.'
        config     = 'Manage local and global configuration.'
        search     = 'Search PyPI for packages.'
        cache      = "Inspect and manage pip's wheel cache."
        index      = 'Inspect information available from package indexes.'
        wheel      = 'Build wheels from your requirements.'
        hash       = 'Compute hashes of package archives.'
        completion = 'A helper command used for command completion.'
        debug      = 'Show information useful for debugging.'
        help       = 'Show help for commands.'
    }
}

function Get-PipStaticGeneralOptions {
    # Fallback general options: names, metavariable (empty for switches), description.
    @(
        @('-h', '--help'), '', 'Show help.'
        @('--debug'), '', 'Let unhandled exceptions propagate outside the main subroutine.'
        @('--isolated'), '', 'Run pip in an isolated mode, ignoring environment variables and user configuration.'
        @('--require-virtualenv'), '', 'Allow pip to only run in a virtual environment.'
        @('--python'), 'python', 'Run pip with the specified Python interpreter.'
        @('-v', '--verbose'), '', 'Give more output.'
        @('-V', '--version'), '', 'Show version and exit.'
        @('-q', '--quiet'), '', 'Give less output.'
        @('--log'), 'path', 'Path to a verbose appending log.'
        @('--no-input'), '', 'Disable prompting for input.'
        @('--keyring-provider'), 'keyring_provider', 'Enable the credential lookup via the keyring library. [auto, disabled, import, subprocess]'
        @('--proxy'), 'proxy', 'Specify a proxy in the form scheme://[user:passwd@]proxy.server:port.'
        @('--retries'), 'retries', 'Maximum attempts to establish a new HTTP connection.'
        @('--timeout'), 'sec', 'Set the socket timeout.'
        @('--exists-action'), 'action', 'Default action when a path already exists.'
        @('--trusted-host'), 'hostname', 'Mark this host or host:port pair as trusted.'
        @('--cert'), 'path', 'Path to PEM-encoded CA certificate bundle.'
        @('--client-cert'), 'path', 'Path to SSL client certificate.'
        @('--cache-dir'), 'dir', 'Store the cache data in <dir>.'
        @('--no-cache-dir'), '', 'Disable the cache.'
        @('--disable-pip-version-check'), '', "Don't periodically check PyPI for a new version of pip."
        @('--no-color'), '', 'Suppress colored output.'
        @('--use-feature'), 'feature', 'Enable new functionality, that may be backward incompatible.'
        @('--use-deprecated'), 'feature', 'Enable deprecated functionality, that will be removed in the future.'
    )
}

function Get-PipStaticOptionValues {
    param([string]$Command, [string]$Option)

    # Value sets pip documents in prose rather than as a bracketed list; keyed '<command>|<option>'
    # first, then '|<option>' for every command.
    $table = @{
        'list|--format'      = @(@('columns', 'Aligned columns (default).'), @('freeze', 'Requirements format.'), @('json', 'JSON.'))
        'cache|--format'     = @(@('human', 'Human-readable listing (default).'), @('abspath', 'Absolute file paths.'))
        '|--exists-action'   = @(@('s', 'switch'), @('i', 'ignore'), @('w', 'wipe'), @('b', 'backup'), @('a', 'abort'))
        '|--upgrade-strategy' = @(@('only-if-needed', 'Upgrade dependencies only when they no longer satisfy the requirement (default).'), @('eager', 'Upgrade dependencies regardless.'))
        '|--algorithm'       = @(@('sha256', 'SHA-256 (default).'), @('sha384', 'SHA-384.'), @('sha512', 'SHA-512.'))
        '|--implementation'  = @(@('cp', 'CPython.'), @('pp', 'PyPy.'), @('py', 'Implementation-agnostic wheels.'), @('jy', 'Jython.'), @('ip', 'IronPython.'))
        '|--no-binary'       = @(@(':all:', 'All packages.'), @(':none:', 'Empty the set.'))
        '|--only-binary'     = @(@(':all:', 'All packages.'), @(':none:', 'Empty the set.'))
        '|--all-releases'    = @(@(':all:', 'All packages.'), @(':none:', 'Empty the set.'))
        '|--only-final'      = @(@(':all:', 'All packages.'), @(':none:', 'Empty the set.'))
        '|--refresh-package' = @(, @(':all:', 'All packages.'))
        '|--index-url'       = @(, @('https://pypi.org/simple', 'The default index.'))
    }

    foreach ($key in @("$Command|$Option", "|$Option")) {
        if ($table.ContainsKey($key)) {
            return @(foreach ($pair in $table[$key]) { New-PipItem $pair[0] $pair[1] })
        }
    }

    $null
}

function Resolve-PipExecutable {
    param([string]$CommandName)

    $name = if ([string]::IsNullOrWhiteSpace($CommandName)) { 'pip' } else { $CommandName }
    # Keyed on PATH too: activating a virtual environment changes which pip answers.
    $key = '{0}|{1}' -f $name.ToLowerInvariant(), $env:PATH
    if ($script:PipCompletionCache.Executables.ContainsKey($key)) {
        return $script:PipCompletionCache.Executables[$key]
    }

    $command = Get-Command -Name $name -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    $path = if ($command) { $command.Source } else { $null }
    $script:PipCompletionCache.Executables[$key] = $path
    $path
}

function Invoke-PipProcess {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [hashtable]$Environment = @{}
    )

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $Executable
        foreach ($argument in $Arguments) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        # No network self-check, no prompts, and a wide help layout so descriptions stay on one line.
        $startInfo.Environment['PIP_DISABLE_PIP_VERSION_CHECK'] = '1'
        $startInfo.Environment['PIP_NO_INPUT'] = '1'
        $startInfo.Environment['COLUMNS'] = '1000'
        foreach ($name in $Environment.Keys) {
            $startInfo.Environment[$name] = $Environment[$name]
        }

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $process.StandardInput.Close()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) {
                try { $process.Kill($true) } catch { Write-Debug -Message $_.Exception.Message }
                return $null
            }

            @{
                Output = ($outputTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
                Error  = ($errorTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
            }
        } finally {
            $process.Dispose()
        }
    } catch {
        $null
    }
}

function New-PipItem {
    param([string]$Value, [string]$Tooltip)

    [pscustomobject]@{ Value = $Value; Tooltip = $Tooltip }
}

function New-PipOptionRecord {
    param([string[]]$Names, [string]$Metavar, [string]$Description)

    $long = @($Names | Where-Object { $_.StartsWith('--') } | Select-Object -First 1)
    @{
        Names       = @($Names)
        Long        = if ($long.Count -gt 0) { $long[0] } else { $Names[0] }
        Metavar     = $Metavar
        Description = $Description
    }
}

function ConvertFrom-PipHelp {
    param([string]$Text)

    $commands = [ordered]@{}
    $actions = [ordered]@{}
    $options = [System.Collections.Generic.List[hashtable]]::new()
    $section = ''
    $inSubcommands = $false
    $current = $null
    $currentCommand = $null

    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^([A-Z][A-Za-z ]*):') {
            $section = $Matches[1]
            $current = $null
            $currentCommand = $null
            $inSubcommands = $false
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            $current = $null
            continue
        }

        if ($section -eq 'Commands') {
            if ($line -match '^  ([a-z][a-z0-9-]*)\s{2,}(\S.*?)\s*$') {
                $currentCommand = $Matches[1]
                $commands[$currentCommand] = $Matches[2]
            } elseif ($currentCommand -and $line -notmatch '^\s{2}\S') {
                $commands[$currentCommand] = ('{0} {1}' -f $commands[$currentCommand], $line.Trim())
            }
            continue
        }

        if ($section -eq 'Description') {
            if ($line -match '^\s+Subcommands:\s*$') {
                $inSubcommands = $true
            } elseif ($inSubcommands -and $line -match '^\s+- ([a-z][a-z0-9-]*): (.+?)\s*$') {
                $actions[$Matches[1]] = $Matches[2]
            }
            continue
        }

        if ($section -notlike '*Options') {
            continue
        }

        if ($line -match '^  (?<names>-[^\s,<]+(?:, -[^\s,<]+)*)(?: <(?<meta>[^>]+)>)?(?:\s{2,}(?<desc>\S.*?))?\s*$') {
            $meta = if ($Matches.ContainsKey('meta')) { $Matches['meta'] } else { '' }
            $desc = if ($Matches.ContainsKey('desc')) { $Matches['desc'] } else { '' }
            $current = New-PipOptionRecord -Names ($Matches['names'] -split ', ') -Metavar $meta -Description $desc
            $options.Add($current)
        } elseif ($current -and $line -match '^\s{4,}(\S.*?)\s*$') {
            $current.Description = ('{0} {1}' -f $current.Description, $Matches[1]).Trim()
        }
    }

    New-PipHelpData -Commands $commands -Actions $actions -Options $options.ToArray()
}

function New-PipHelpData {
    param(
        [System.Collections.IDictionary]$Commands,
        [System.Collections.IDictionary]$Actions,
        [hashtable[]]$Options
    )

    # Ordinal: pip has case-distinct short flags (-v/-V, -u/-U, -c/-C, -i/-I).
    $byName = [System.Collections.Generic.Dictionary[string, hashtable]]::new([System.StringComparer]::Ordinal)
    foreach ($option in @($Options)) {
        if ($option.Description -match '\[([a-z0-9][\w-]*(?:,\s*[\w-]+)+)\]') {
            $option.Choices = @($Matches[1] -split ',\s*')
        } else {
            $option.Choices = @()
        }

        foreach ($name in $option.Names) {
            if (-not $byName.ContainsKey($name)) {
                $byName[$name] = $option
            }
        }
    }

    @{
        Commands = $Commands
        Actions  = $Actions
        Options  = @($Options)
        ByName   = $byName
    }
}

function Get-PipStaticHelp {
    param([string]$Command)

    $general = Get-PipStaticGeneralOptions
    $options = for ($index = 0; $index -lt $general.Count; $index += 3) {
        New-PipOptionRecord -Names $general[$index] -Metavar $general[$index + 1] -Description $general[$index + 2]
    }

    $commands = if ($Command) { [ordered]@{} } else { Get-PipStaticCommands }
    $actions = switch ($Command) {
        'cache' { [ordered]@{ dir = 'Show the cache directory.'; info = 'Show information about the cache.'; list = 'List filenames of packages stored in the cache.'; remove = 'Remove one or more package from the cache.'; purge = 'Remove all items from the cache.' } }
        'config' { [ordered]@{ list = 'List the active configuration.'; edit = 'Edit the configuration file in an editor.'; get = 'Get the value associated with command.option.'; set = 'Set the command.option=value.'; unset = 'Unset the value associated with command.option.'; debug = 'List the configuration files and values defined under them.' } }
        default { [ordered]@{} }
    }

    New-PipHelpData -Commands $commands -Actions $actions -Options @($options)
}

function Get-PipHelp {
    param([string]$Executable, [string]$Command)

    if (-not $Executable) {
        return Get-PipStaticHelp -Command $Command
    }

    $key = '{0}|{1}' -f $Executable, $Command
    if ($script:PipCompletionCache.Help.ContainsKey($key)) {
        return $script:PipCompletionCache.Help[$key]
    }

    $arguments = if ($Command) { @($Command, '--help') } else { @('--help') }
    $result = Invoke-PipProcess -Executable $Executable -Arguments $arguments
    $help = if ($result -and $result.Output -match '(?m)^Usage:') {
        ConvertFrom-PipHelp -Text $result.Output
    } else {
        Get-PipStaticHelp -Command $Command
    }

    # `pip index` documents its one action only in the Usage line.
    if ($Command -eq 'index' -and $help.Actions.Count -eq 0) {
        $help.Actions['versions'] = 'Show the available versions of a package.'
    }

    $script:PipCompletionCache.Help[$key] = $help
    $help
}

function Get-PipOptionChoicesFromPip {
    param([string]$Executable, [string]$Option)

    # pip lists --use-feature/--use-deprecated choices only in its own parse error, which it
    # raises before running anything.
    if (-not $Executable) {
        return @()
    }

    $key = '{0}|{1}' -f $Executable, $Option
    if ($script:PipCompletionCache.Choices.ContainsKey($key)) {
        return $script:PipCompletionCache.Choices[$key]
    }

    $choices = @()
    $result = Invoke-PipProcess -Executable $Executable -Arguments @("$Option=__pip_completer_probe__", '--version')
    if ($result -and $result.Error -match '\(choose from ([^)]*)\)') {
        $choices = @([regex]::Matches($Matches[1], "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    }

    $script:PipCompletionCache.Choices[$key] = $choices
    $choices
}

function Get-PipInstalledPackages {
    param([string]$Executable)

    # pip's own completion protocol lists the installed distributions of the environment it runs in.
    if (-not $Executable) {
        return @()
    }

    $result = Invoke-PipProcess -Executable $Executable -Arguments @() -Environment @{
        PIP_AUTO_COMPLETE = '1'
        COMP_WORDS        = 'pip show '
        COMP_CWORD        = '2'
    }
    if (-not $result) {
        return @()
    }

    @($result.Output -split '\s+' | Where-Object { $_ } | Sort-Object -Unique)
}

function Resolve-PipOption {
    param([hashtable]$Help, [string]$Token)

    $name = $Token
    if ($name.StartsWith('--') -and $name.Contains('=')) {
        $name = $name.Substring(0, $name.IndexOf('='))
    }

    if ($Help.ByName.ContainsKey($name)) {
        return $Help.ByName[$name]
    }

    # optparse accepts any unambiguous abbreviation of a long option.
    if ($name.StartsWith('--') -and $name.Length -gt 2) {
        $candidates = @($Help.Options | Where-Object { $_.Long.StartsWith($name, [System.StringComparison]::Ordinal) })
        if ($candidates.Count -eq 1) {
            return $candidates[0]
        }
    }

    $null
}

function Test-PipPathOption {
    param([hashtable]$Option)

    # -f/--find-links takes a directory as often as a URL, so it keeps filesystem completion.
    $Option.Metavar -in @('file', 'dir', 'path', 'path/url', 'python', 'editor') -or $Option.Long -eq '--find-links'
}

function Get-PipOptionValues {
    param([string]$Executable, [string]$Command, [hashtable]$Option)

    if ($Option.Long -eq '--exclude') {
        return @(Get-PipInstalledPackages -Executable $Executable | ForEach-Object { New-PipItem $_ 'Installed package' })
    }

    if ($Option.Long -in @('--use-feature', '--use-deprecated')) {
        return @(Get-PipOptionChoicesFromPip -Executable $Executable -Option $Option.Long | ForEach-Object { New-PipItem $_ $Option.Description })
    }

    $static = Get-PipStaticOptionValues -Command $Command -Option $Option.Long
    if ($static) {
        return @($static)
    }

    if (@($Option.Choices).Count -gt 0) {
        return @($Option.Choices | ForEach-Object { New-PipItem $_ $Option.Description })
    }

    New-PipItem "<$($Option.Metavar)>" $Option.Description
}

function Get-PipPathValues {
    param([string]$InputPath)

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        $parent = '.'
        $leaf = ''
    } elseif ($InputPath -match '[\\/]$') {
        $parent = $InputPath
        $leaf = ''
    } else {
        $parent = Split-Path -Path $InputPath -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }
        $leaf = Split-Path -Path $InputPath -Leaf
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $pattern = [System.Management.Automation.WildcardPattern]::Escape($leaf) + '*'
    foreach ($item in @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction Ignore | Where-Object { $_.Name -like $pattern } | Sort-Object -Property Name)) {
        $text = if ($parent -eq '.' -and -not $InputPath.StartsWith('.')) { $item.Name } else { Join-Path -Path $parent -ChildPath $item.Name }
        if ($item.PSIsContainer) {
            $text += [System.IO.Path]::DirectorySeparatorChar
        }
        New-PipItem $text $item.FullName
    }
}

function Get-PipConfigKeys {
    param([string]$Executable, [string]$Word)

    $root = Get-PipHelp -Executable $Executable -Command ''
    if (-not $Word.Contains('.')) {
        return @(@('global') + @($root.Commands.Keys) | ForEach-Object { New-PipItem "$_." "Options under [$_]" })
    }

    $section = $Word.Substring(0, $Word.IndexOf('.'))
    @(Get-PipConfigSectionOptions -Executable $Executable -Section $section | Where-Object { $_.Long.StartsWith('--') -and $_.Long -notin @('--help', '--version') } | ForEach-Object {
        New-PipItem ('{0}.{1}' -f $section, $_.Long.Substring(2)) $_.Description
    })
}

function Get-PipConfigSectionOptions {
    param([string]$Executable, [string]$Section)

    # [global] applies to every command; general plus install options cover what it is used for
    # (index-url, trusted-host, timeout, progress-bar, ...) without running every command's help.
    $root = Get-PipHelp -Executable $Executable -Command ''
    $commands = if ($Section -eq 'global') { @('', 'install') } elseif ($root.Commands.Contains($Section)) { @($Section) } else { @() }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($command in $commands) {
        foreach ($option in (Get-PipHelp -Executable $Executable -Command $command).Options) {
            if ($seen.Add($option.Long)) {
                $option
            }
        }
    }
}

function Get-PipConfigValues {
    param([string]$Executable, [string]$Key)

    if ($Key -notmatch '^([a-z][a-z0-9-]*)\.([a-z0-9][a-z0-9-]*)$') {
        return @()
    }

    $section = $Matches[1]
    $name = '--' + $Matches[2]
    $option = Get-PipConfigSectionOptions -Executable $Executable -Section $section | Where-Object { $name -in $_.Names } | Select-Object -First 1
    if (-not $option -or (Test-PipPathOption -Option $option)) {
        return @()
    }

    if ([string]::IsNullOrEmpty($option.Metavar)) {
        return @((New-PipItem 'true' $option.Description), (New-PipItem 'false' $option.Description))
    }

    Get-PipOptionValues -Executable $Executable -Command $section -Option $option
}

function New-PipCompletionResults {
    param(
        [object[]]$Items,
        [string]$Word,
        [string]$Prefix = '',
        [System.Management.Automation.CompletionResultType]$ResultType = [System.Management.Automation.CompletionResultType]::ParameterValue,
        [switch]$CaseSensitive
    )

    $comparison = if ($CaseSensitive) { [System.StringComparison]::Ordinal } else { [System.StringComparison]::OrdinalIgnoreCase }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $Items) {
        $value = $item.Value
        if ([string]::IsNullOrEmpty($value) -or -not $value.StartsWith($Word, $comparison) -or -not $seen.Add($value)) {
            continue
        }

        $text = $Prefix + $value
        $completion = if ($text -match '[\s''"`$&(){};,|<>@#]' -and $ResultType -ne [System.Management.Automation.CompletionResultType]::ParameterName -and -not $value.StartsWith('<')) {
            "'" + $text.Replace("'", "''") + "'"
        } else {
            $text
        }
        $tooltip = if ([string]::IsNullOrWhiteSpace($item.Tooltip)) { $value } else { $item.Tooltip }
        [System.Management.Automation.CompletionResult]::new($completion, $value, $ResultType, $tooltip)
    }
}

function Get-PipTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    $Element.Extent.Text
}

function Complete-Pip {
    param([string]$WordToComplete, $CommandAst, [int]$CursorPosition)

    $executable = Resolve-PipExecutable -CommandName (Get-PipTokenText -Element $CommandAst.CommandElements[0])
    $root = Get-PipHelp -Executable $executable -Command ''

    # Offsets are absolute on both sides, so no rebasing is needed for these comparisons.
    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.StartOffset -ge $CursorPosition -or $element.Extent.EndOffset -ge $CursorPosition) {
            break
        }
        $tokens.Add((Get-PipTokenText -Element $element))
    }

    $command = $null
    $help = $root
    $operands = [System.Collections.Generic.List[string]]::new()
    $pending = $null
    foreach ($token in $tokens) {
        if ($pending) {
            $pending = $null
            continue
        }

        if ($token.StartsWith('-') -and $token.Length -gt 1) {
            $option = Resolve-PipOption -Help $help -Token $token
            $attached = $token.Contains('=') -or (-not $token.StartsWith('--') -and $token.Length -gt 2)
            if ($option -and $option.Metavar -and -not $attached) {
                $pending = $option
            }
            continue
        }

        if (-not $command) {
            $command = $token
            if ($root.Commands.Contains($token)) {
                $help = Get-PipHelp -Executable $executable -Command $token
            }
            continue
        }

        $operands.Add($token)
    }

    $word = $WordToComplete
    $valueType = [System.Management.Automation.CompletionResultType]::ParameterValue

    if ($pending) {
        if (Test-PipPathOption -Option $pending) {
            # Path slot: PowerShell's own filesystem completion is the intended answer.
            return
        }
        New-PipCompletionResults -Items (Get-PipOptionValues -Executable $executable -Command $command -Option $pending) -Word $word
        return
    }

    if ($word -match '^(--[A-Za-z0-9][A-Za-z0-9-]*)=(.*)$') {
        $option = Resolve-PipOption -Help $help -Token $Matches[1]
        $valuePrefix = $Matches[2]
        if (-not $option -or -not $option.Metavar) {
            return
        }

        $prefix = $option.Long + '='
        $values = if (Test-PipPathOption -Option $option) {
            Get-PipPathValues -InputPath $valuePrefix
        } else {
            Get-PipOptionValues -Executable $executable -Command $command -Option $option
        }
        New-PipCompletionResults -Items $values -Word $valuePrefix -Prefix $prefix
        return
    }

    $optionItems = @($help.Options | ForEach-Object {
        $option = $_
        $option.Names | ForEach-Object { New-PipItem $_ $option.Description }
    })

    if ($word.StartsWith('-')) {
        New-PipCompletionResults -Items $optionItems -Word $word -ResultType ParameterName -CaseSensitive
        return
    }

    if (-not $command) {
        New-PipCompletionResults -Items @($root.Commands.GetEnumerator() | ForEach-Object { New-PipItem $_.Key $_.Value }) -Word $word
        return
    }

    $operandItems = $null
    switch ($command) {
        'help' {
            if ($operands.Count -eq 0) {
                $operandItems = @($root.Commands.GetEnumerator() | ForEach-Object { New-PipItem $_.Key $_.Value })
            }
        }
        { $_ -in @('uninstall', 'show') } {
            $typed = @($operands)
            $operandItems = @(Get-PipInstalledPackages -Executable $executable | Where-Object { $_ -notin $typed } | ForEach-Object { New-PipItem $_ 'Installed package' })
        }
        { $_ -in @('install', 'download', 'wheel', 'lock', 'hash') } {
            # Requirement specifiers, local projects and archives: leave it to filesystem completion.
            return
        }
        'search' {
            if ($operands.Count -eq 0) { $operandItems = @(New-PipItem '<query>' 'Search term') }
        }
        default {
            if ($help.Actions.Count -gt 0) {
                if ($operands.Count -eq 0) {
                    $operandItems = @($help.Actions.GetEnumerator() | ForEach-Object { New-PipItem $_.Key $_.Value })
                } else {
                    $action = $operands[0]
                    $slot = $operands.Count - 1
                    if ($command -eq 'config' -and $action -in @('get', 'set', 'unset') -and $slot -eq 0) {
                        $operandItems = @(Get-PipConfigKeys -Executable $executable -Word $word)
                    } elseif ($command -eq 'config' -and $action -eq 'set' -and $slot -eq 1) {
                        $operandItems = @(Get-PipConfigValues -Executable $executable -Key $operands[1])
                    } elseif ($command -eq 'cache' -and $action -in @('list', 'remove') -and $slot -eq 0) {
                        $operandItems = @(New-PipItem '<pattern>' 'A glob expression or a package name')
                    } elseif ($command -eq 'index' -and $action -eq 'versions' -and $slot -eq 0) {
                        $operandItems = @(New-PipItem '<package>' 'Package name to look up on the index')
                    }
                }
            }
        }
    }

    if ($null -ne $operandItems) {
        New-PipCompletionResults -Items $operandItems -Word $word -ResultType $valueType
        return
    }

    if ([string]::IsNullOrEmpty($word)) {
        New-PipCompletionResults -Items $optionItems -Word $word -ResultType ParameterName -CaseSensitive
    }
}

Register-ArgumentCompleter -Native -CommandName @('pip', 'pip.exe', 'pip3', 'pip3.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pip -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
