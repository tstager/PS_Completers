Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name RtkCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:RtkCompletionCache = @{
        ExecutableResolved = $false
        Executable         = $null
        Nodes              = @{}
    }
}

function New-RtkCompletionResult {
    param(
        [Parameter(Mandatory)]
        [string]$CompletionText,

        [string]$ToolTip,

        [string]$ResultType = 'ParameterValue',

        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Test-RtkStartsWith {
    param(
        [string]$Candidate,
        [string]$Prefix
    )

    [string]::IsNullOrEmpty($Prefix) -or $Candidate.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function New-RtkOptionSpec {
    param(
        [Parameter(Mandatory)]
        [string[]]$Names,

        [string]$Description,

        [string]$ValueKind = 'None',

        [string]$Metavar = '',

        [string[]]$Values = @()
    )

    [pscustomobject]@{
        Names       = $Names
        Description = $Description
        ValueKind   = $ValueKind
        Metavar     = $Metavar
        Values      = @($Values)
    }
}

function New-RtkCommandSpec {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Description
    )

    [pscustomobject]@{
        Name        = $Name
        Description = $Description
    }
}

function ConvertTo-RtkArgumentSpec {
    param(
        [Parameter(Mandatory)]
        [string]$Metavar,

        [string]$Description,

        [string]$ValueKind = 'Text',

        [string[]]$Values = @(),

        [bool]$Variadic = $false
    )

    [pscustomobject]@{
        Metavar     = $Metavar
        Description = $Description
        ValueKind   = $ValueKind
        Values      = @($Values)
        Variadic    = $Variadic
    }
}

function ConvertTo-RtkNode {
    param(
        [object[]]$Commands = @(),
        [object[]]$Options = @(),
        [object[]]$Arguments = @(),
        [string]$Source = 'static'
    )

    [pscustomobject]@{
        Commands  = @($Commands)
        Options   = @($Options)
        Arguments = @($Arguments)
        Source    = $Source
    }
}

function Get-RtkRootCommands {
    @(
        New-RtkCommandSpec -Name 'ls' -Description 'List directory contents with token-optimized output'
        New-RtkCommandSpec -Name 'tree' -Description 'Directory tree with token-optimized output'
        New-RtkCommandSpec -Name 'read' -Description 'Read file with intelligent filtering'
        New-RtkCommandSpec -Name 'smart' -Description 'Generate 2-line technical summary'
        New-RtkCommandSpec -Name 'git' -Description 'Git commands with compact output'
        New-RtkCommandSpec -Name 'gh' -Description 'GitHub CLI (gh) commands with token-optimized output'
        New-RtkCommandSpec -Name 'glab' -Description 'GitLab CLI (glab) commands with token-optimized output'
        New-RtkCommandSpec -Name 'aws' -Description 'AWS CLI with compact output'
        New-RtkCommandSpec -Name 'psql' -Description 'PostgreSQL client with compact output'
        New-RtkCommandSpec -Name 'pnpm' -Description 'pnpm commands with ultra-compact output'
        New-RtkCommandSpec -Name 'err' -Description 'Run command and show only errors/warnings'
        New-RtkCommandSpec -Name 'test' -Description 'Run tests and show only failures'
        New-RtkCommandSpec -Name 'json' -Description 'Show JSON (compact values by default)'
        New-RtkCommandSpec -Name 'deps' -Description 'Summarize project dependencies'
        New-RtkCommandSpec -Name 'env' -Description 'Show environment variables (filtered)'
        New-RtkCommandSpec -Name 'find' -Description 'Find files with compact tree output'
        New-RtkCommandSpec -Name 'diff' -Description 'Ultra-condensed diff (only changed lines)'
        New-RtkCommandSpec -Name 'log' -Description 'Filter and deduplicate log output'
        New-RtkCommandSpec -Name 'dotnet' -Description '.NET commands with compact output'
        New-RtkCommandSpec -Name 'docker' -Description 'Docker commands with compact output'
        New-RtkCommandSpec -Name 'kubectl' -Description 'Kubectl commands with compact output'
        New-RtkCommandSpec -Name 'oc' -Description 'OpenShift CLI (oc) commands with compact output'
        New-RtkCommandSpec -Name 'summary' -Description 'Run command and show heuristic summary'
        New-RtkCommandSpec -Name 'grep' -Description 'Compact grep - strips whitespace, truncates, groups by file'
        New-RtkCommandSpec -Name 'rg' -Description 'Compact ripgrep - runs rg natively'
        New-RtkCommandSpec -Name 'init' -Description 'Initialize rtk instructions for assistant CLI usage'
        New-RtkCommandSpec -Name 'wget' -Description 'Download with compact output'
        New-RtkCommandSpec -Name 'wc' -Description 'Word/line/byte count with compact output'
        New-RtkCommandSpec -Name 'gain' -Description 'Show token savings summary and history'
        New-RtkCommandSpec -Name 'cc-economics' -Description 'Claude Code economics analysis'
        New-RtkCommandSpec -Name 'config' -Description 'Show or create configuration file'
        New-RtkCommandSpec -Name 'jest' -Description 'Jest commands with compact output'
        New-RtkCommandSpec -Name 'vitest' -Description 'Vitest commands with compact output'
        New-RtkCommandSpec -Name 'ctest' -Description 'CTest with compact output'
        New-RtkCommandSpec -Name 'prisma' -Description 'Prisma commands with compact output'
        New-RtkCommandSpec -Name 'tsc' -Description 'TypeScript compiler with grouped error output'
        New-RtkCommandSpec -Name 'next' -Description 'Next.js build with compact output'
        New-RtkCommandSpec -Name 'lint' -Description 'ESLint with grouped rule violations'
        New-RtkCommandSpec -Name 'prettier' -Description 'Prettier format checker with compact output'
        New-RtkCommandSpec -Name 'format' -Description 'Universal format checker'
        New-RtkCommandSpec -Name 'playwright' -Description 'Playwright E2E tests with compact output'
        New-RtkCommandSpec -Name 'cargo' -Description 'Cargo commands with compact output'
        New-RtkCommandSpec -Name 'npm' -Description 'npm run with filtered output'
        New-RtkCommandSpec -Name 'npx' -Description 'npx with intelligent routing'
        New-RtkCommandSpec -Name 'bun' -Description 'Bun runtime commands with compact output'
        New-RtkCommandSpec -Name 'bunx' -Description 'bunx with passthrough + auto-filter'
        New-RtkCommandSpec -Name 'curl' -Description 'Curl with auto-JSON detection and schema output'
        New-RtkCommandSpec -Name 'discover' -Description 'Discover missed RTK savings from Claude Code history'
        New-RtkCommandSpec -Name 'session' -Description 'Show RTK adoption across Claude Code sessions'
        New-RtkCommandSpec -Name 'telemetry' -Description 'Manage telemetry consent and data'
        New-RtkCommandSpec -Name 'learn' -Description 'Learn CLI corrections from Claude Code error history'
        New-RtkCommandSpec -Name 'run' -Description 'Execute a shell command via sh -c'
        New-RtkCommandSpec -Name 'proxy' -Description 'Execute command without filtering but track usage'
        New-RtkCommandSpec -Name 'pipe' -Description 'Read stdin, apply filter, print filtered output'
        New-RtkCommandSpec -Name 'trust' -Description 'Trust project-local TOML filters in current directory'
        New-RtkCommandSpec -Name 'untrust' -Description 'Revoke trust for project-local TOML filters'
        New-RtkCommandSpec -Name 'verify' -Description 'Verify hook integrity and run TOML filter inline tests'
        New-RtkCommandSpec -Name 'ruff' -Description 'Ruff linter/formatter with compact output'
        New-RtkCommandSpec -Name 'pytest' -Description 'Pytest test runner with compact output'
        New-RtkCommandSpec -Name 'mypy' -Description 'Mypy type checker with grouped error output'
        New-RtkCommandSpec -Name 'php' -Description 'PHP command runner with compact output'
        New-RtkCommandSpec -Name 'phpunit' -Description 'PHPUnit test runner with compact output'
        New-RtkCommandSpec -Name 'phpstan' -Description 'PHPStan analyzer with compact output'
        New-RtkCommandSpec -Name 'pest' -Description 'Pest test runner with compact output'
        New-RtkCommandSpec -Name 'paratest' -Description 'ParaTest parallel test runner with compact output'
        New-RtkCommandSpec -Name 'ecs' -Description 'EasyCodingStandard (ECS) code style fixer with compact output'
        New-RtkCommandSpec -Name 'pint' -Description 'Laravel Pint code style fixer with compact output'
        New-RtkCommandSpec -Name 'phpt' -Description 'PHP run-tests.php (.phpt) with compact summary'
        New-RtkCommandSpec -Name 'rake' -Description 'Rake/Rails test with compact Minitest output'
        New-RtkCommandSpec -Name 'rubocop' -Description 'RuboCop linter with compact output'
        New-RtkCommandSpec -Name 'rspec' -Description 'RSpec test runner with compact output'
        New-RtkCommandSpec -Name 'pip' -Description 'Pip package manager with compact output'
        New-RtkCommandSpec -Name 'uv' -Description 'uv run with compact output'
        New-RtkCommandSpec -Name 'deno' -Description 'Deno runtime commands with compact output'
        New-RtkCommandSpec -Name 'go' -Description 'Go commands with compact output'
        New-RtkCommandSpec -Name 'sbt' -Description 'SBT (Scala Build Tool) commands with compact output'
        New-RtkCommandSpec -Name 'gt' -Description 'Graphite (gt) stacked PR commands with compact output'
        New-RtkCommandSpec -Name 'golangci-lint' -Description 'golangci-lint wrapper with compact run support'
        New-RtkCommandSpec -Name 'gradlew' -Description 'Android Gradle wrapper with compact output'
        New-RtkCommandSpec -Name 'mvn' -Description 'Apache Maven wrapper with compact output'
        New-RtkCommandSpec -Name 'mvnd' -Description 'Maven Daemon (mvnd) with compact output'
        New-RtkCommandSpec -Name 'hook-audit' -Description 'Show hook rewrite audit metrics'
        New-RtkCommandSpec -Name 'rewrite' -Description 'Rewrite a raw command to its RTK equivalent'
        New-RtkCommandSpec -Name 'hook' -Description 'Hook processors for LLM CLI tools'
        New-RtkCommandSpec -Name 'help' -Description 'Print this message or the help of the given subcommand(s)'
    )
}

function Get-RtkGlobalOptions {
    @(
        New-RtkOptionSpec -Names @('-v', '--verbose') -Description 'Verbosity level (-v, -vv, -vvv)'
        New-RtkOptionSpec -Names @('--ultra-compact') -Description 'Ultra-compact mode: ASCII icons, inline format'
        New-RtkOptionSpec -Names @('--skip-env') -Description 'Set SKIP_ENV_VALIDATION=1 for child processes'
        New-RtkOptionSpec -Names @('-h', '--help') -Description 'Print help'
        New-RtkOptionSpec -Names @('-V', '--version') -Description 'Print version'
    )
}

function Get-RtkCommonOptionTable {
    @(
        New-RtkOptionSpec -Names @('--ultra-compact') -Description 'Ultra-compact mode: ASCII icons, inline format'
        New-RtkOptionSpec -Names @('--skip-env') -Description 'Set SKIP_ENV_VALIDATION=1 for child processes'
        New-RtkOptionSpec -Names @('-h', '--help') -Description 'Print help'
    )
}

function Get-RtkGitCommands {
    @(
        New-RtkCommandSpec -Name 'diff' -Description 'Condensed diff output'
        New-RtkCommandSpec -Name 'log' -Description 'One-line commit history'
        New-RtkCommandSpec -Name 'status' -Description 'Compact status'
        New-RtkCommandSpec -Name 'show' -Description 'Compact show'
        New-RtkCommandSpec -Name 'add' -Description 'Add files'
        New-RtkCommandSpec -Name 'commit' -Description 'Commit'
        New-RtkCommandSpec -Name 'checkout' -Description 'Checkout branch or restore paths'
        New-RtkCommandSpec -Name 'push' -Description 'Push'
        New-RtkCommandSpec -Name 'pull' -Description 'Pull'
        New-RtkCommandSpec -Name 'branch' -Description 'Compact branch listing'
        New-RtkCommandSpec -Name 'fetch' -Description 'Fetch'
        New-RtkCommandSpec -Name 'stash' -Description 'Stash management (list, show, pop, apply, drop)'
        New-RtkCommandSpec -Name 'worktree' -Description 'Compact worktree listing'
        New-RtkCommandSpec -Name 'help' -Description 'Print this message or the help of the given subcommand(s)'
    )
}

function Get-RtkStaticNode {
    param([string[]]$Path)

    $common = @(Get-RtkCommonOptionTable)
    $key = ($Path -join ' ')

    switch ($key) {
        '' {
            return ConvertTo-RtkNode -Commands (Get-RtkRootCommands) -Options (Get-RtkGlobalOptions)
        }
        'read' {
            $options = @(
                New-RtkOptionSpec -Names @('-l', '--level') -Description 'Filter: none (default, full content), minimal, aggressive' -ValueKind 'Enum' -Metavar 'LEVEL' -Values @('none', 'minimal', 'aggressive')
                New-RtkOptionSpec -Names @('-m', '--max-lines') -Description 'Max lines' -ValueKind 'Integer' -Metavar 'MAX_LINES'
                New-RtkOptionSpec -Names @('--tail-lines') -Description 'Keep only last N lines' -ValueKind 'Integer' -Metavar 'TAIL_LINES'
                New-RtkOptionSpec -Names @('-n', '--line-numbers') -Description 'Show line numbers'
            ) + $common
            return ConvertTo-RtkNode -Options $options -Arguments @(ConvertTo-RtkArgumentSpec -Metavar 'FILES' -Description 'Files to read' -ValueKind 'Path' -Variadic $true)
        }
        'git' {
            $options = @(
                New-RtkOptionSpec -Names @('-C') -Description 'Change to directory before executing' -ValueKind 'Directory' -Metavar 'DIRECTORY'
                New-RtkOptionSpec -Names @('-c') -Description 'Git configuration override (key=value)' -ValueKind 'KeyValue' -Metavar 'CONFIG_OVERRIDE'
                New-RtkOptionSpec -Names @('--git-dir') -Description 'Set the path to the .git directory' -ValueKind 'Path' -Metavar 'GIT_DIR'
                New-RtkOptionSpec -Names @('--work-tree') -Description 'Set the path to the working tree' -ValueKind 'Path' -Metavar 'WORK_TREE'
                New-RtkOptionSpec -Names @('--no-pager') -Description 'Disable pager'
                New-RtkOptionSpec -Names @('--no-optional-locks') -Description 'Skip optional locks'
                New-RtkOptionSpec -Names @('--bare') -Description 'Treat repository as bare'
                New-RtkOptionSpec -Names @('--literal-pathspecs') -Description 'Treat pathspecs literally'
            ) + $common
            return ConvertTo-RtkNode -Commands (Get-RtkGitCommands) -Options $options
        }
        'telemetry' {
            $commands = @(
                New-RtkCommandSpec -Name 'status' -Description 'Show telemetry status'
                New-RtkCommandSpec -Name 'enable' -Description 'Enable telemetry'
                New-RtkCommandSpec -Name 'disable' -Description 'Disable telemetry'
                New-RtkCommandSpec -Name 'forget' -Description 'Forget telemetry data'
                New-RtkCommandSpec -Name 'help' -Description 'Print this message or the help of the given subcommand(s)'
            )
            return ConvertTo-RtkNode -Commands $commands -Options $common
        }
        'hook' {
            $commands = @(
                New-RtkCommandSpec -Name 'claude' -Description 'Process Claude Code PreToolUse hook'
                New-RtkCommandSpec -Name 'cursor' -Description 'Process Cursor Agent hook'
                New-RtkCommandSpec -Name 'gemini' -Description 'Process Gemini CLI BeforeTool hook'
                New-RtkCommandSpec -Name 'copilot' -Description 'Process Copilot preToolUse hook'
                New-RtkCommandSpec -Name 'droid' -Description 'Process Factory Droid PreToolUse hook'
                New-RtkCommandSpec -Name 'vibe' -Description 'Process Mistral Vibe CLI pre_tool hook'
                New-RtkCommandSpec -Name 'check' -Description 'Check how a command would be rewritten by the hook engine'
                New-RtkCommandSpec -Name 'help' -Description 'Print this message or the help of the given subcommand(s)'
            )
            return ConvertTo-RtkNode -Commands $commands -Options $common
        }
        'config' {
            return ConvertTo-RtkNode -Options (@(New-RtkOptionSpec -Names @('--create') -Description 'Create default config file') + $common)
        }
        'json' {
            $options = @(
                New-RtkOptionSpec -Names @('-d', '--depth') -Description 'Max depth' -ValueKind 'Integer' -Metavar 'DEPTH'
                New-RtkOptionSpec -Names @('--keys-only') -Description 'Show keys only'
            ) + $common
            return ConvertTo-RtkNode -Options $options -Arguments @(ConvertTo-RtkArgumentSpec -Metavar 'FILE' -Description 'JSON file' -ValueKind 'Path')
        }
        default {
            return ConvertTo-RtkNode -Options $common -Arguments @(ConvertTo-RtkArgumentSpec -Metavar 'ARGS' -Description 'Arguments passed through' -ValueKind 'Path' -Variadic $true)
        }
    }
}

function Get-RtkExecutable {
    $cache = $script:RtkCompletionCache
    if (-not $cache.ExecutableResolved) {
        $cache.ExecutableResolved = $true
        $command = Get-Command -Name 'rtk' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
        if ($command) {
            $cache.Executable = $command.Source
        }
    }

    $cache.Executable
}

function Invoke-RtkHelp {
    param([string[]]$Path)

    $executable = Get-RtkExecutable
    if (-not $executable) {
        return $null
    }

    $arguments = if ($Path.Count -eq 0) { @('--help') } else { @('help') + $Path }

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $executable
        foreach ($argument in $arguments) {
            $startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $process.StandardInput.Close()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) {
                $process.Kill()
                return $null
            }

            $text = ($outputTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', '') + ($errorTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
            if ([string]::IsNullOrWhiteSpace($text)) {
                return $null
            }

            return $text
        } finally {
            $process.Dispose()
        }
    } catch {
        return $null
    }
}

function ConvertFrom-RtkEnumeratedDescription {
    param([string]$Description)

    if ([string]::IsNullOrWhiteSpace($Description)) {
        return @()
    }

    $text = $Description -replace '\s*\[default:[^\]]*\]', ''
    $text = $text -replace '\([^)]*\)', ''
    if ($text -notmatch ':\s*([^:]+)$') {
        return @()
    }

    $values = @()
    foreach ($part in ($Matches[1] -split ',')) {
        $candidate = $part.Trim().TrimEnd('.')
        if ([string]::IsNullOrEmpty($candidate)) {
            continue
        }

        if ($candidate -notmatch '^[A-Za-z0-9][A-Za-z0-9_.+-]*$') {
            return @()
        }

        $values += $candidate
    }

    if ($values.Count -lt 2 -or $values.Count -gt 16) {
        return @()
    }

    $values
}

function Get-RtkValueKind {
    param(
        [string]$Metavar,
        [string[]]$Values
    )

    if (@($Values).Count -gt 0) {
        return 'Enum'
    }

    if ([string]::IsNullOrEmpty($Metavar)) {
        return 'None'
    }

    if ($Metavar -match '^(DIRECTORY|DIR|CWD|FOLDER)$') {
        return 'Directory'
    }

    if ($Metavar -match '(^|_)(FILE|FILES|PATH|PATHS|OUTPUT|DIR|DIRECTORY)$|^ARGS$') {
        return 'Path'
    }

    if ($Metavar -match '(^|_)(N|NUM|NUMBER|COUNT|LINES|LEN|LENGTH|DEPTH|LIMIT|MAX|MIN|SIZE|WIDTH)$|^MAX') {
        return 'Integer'
    }

    if ($Metavar -match 'OVERRIDE|KEY_VALUE|KV$') {
        return 'KeyValue'
    }

    'Text'
}

function ConvertFrom-RtkHelp {
    param([string]$Text)

    $commands = @()
    $options = @()
    $arguments = @()

    $section = ''
    $entries = @()
    $current = $null

    foreach ($rawLine in ($Text -split "`r?`n")) {
        $line = $rawLine.TrimEnd()

        if ($line -match '^(Commands|Options|Arguments|Usage):\s*(.*)$') {
            if ($current) { $entries += $current; $current = $null }
            $section = $Matches[1]
            continue
        }

        if ($section -eq '' -or $section -eq 'Usage') {
            continue
        }

        if ($line -match '^\S') {
            # A new unindented block ends the current section.
            if ($current) { $entries += $current; $current = $null }
            $section = ''
            continue
        }

        $startsEntry = switch ($section) {
            'Options' { $line -match '^\s{2,7}-\S' }
            'Arguments' { $line -match '^\s{2}[<\[]' }
            default { $line -match '^\s{2}\S' -and $line -notmatch '^\s{3}' }
        }

        if ($startsEntry) {
            if ($current) { $entries += $current }
            $current = [pscustomobject]@{
                Section = $section
                Head    = $line
                Body    = @()
            }
            continue
        }

        if ($current) {
            $current.Body += $line
        }
    }

    if ($current) { $entries += $current }

    foreach ($entry in $entries) {
        $head = $entry.Head
        $bodyText = ''
        $bulletValues = @()
        $inlineValues = @()
        $inPossibleValues = $false

        foreach ($bodyLine in $entry.Body) {
            $trimmed = $bodyLine.Trim()
            if ($trimmed -match '^Possible values:') {
                $inPossibleValues = $true
                continue
            }

            if ($inPossibleValues) {
                if ($trimmed -match '^-\s+([^:\s]+)') {
                    $bulletValues += $Matches[1]
                    continue
                }

                if ($trimmed -eq '') {
                    continue
                }

                if ($trimmed -notmatch '^\[') {
                    $inPossibleValues = $false
                }
            }

            if ($trimmed -ne '') {
                $bodyText = if ($bodyText) { "$bodyText $trimmed" } else { $trimmed }
            }
        }

        if ($bodyText -match '\[possible values:\s*([^\]]+)\]') {
            $inlineValues = @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        if ($head -match '\[possible values:\s*([^\]]+)\]') {
            $inlineValues = @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        switch ($entry.Section) {
            'Commands' {
                if ($head -match '^\s{2}(\S+)\s*(.*)$') {
                    $commands += New-RtkCommandSpec $Matches[1] $Matches[2].Trim()
                }
            }
            'Options' {
                if ($head -match '^\s{2,7}(-[^\s<,]+(?:,\s+-[^\s<,]+)*)(?:\s+(?:<([^>]+)>|\[=<([^>]+)>\]))?(?:\s{2,}(\S.*))?$') {
                    $names = @($Matches[1] -split ',\s*' | ForEach-Object { $_.Trim().TrimEnd('.') } | Where-Object { $_ })
                    $metavar = if ($Matches[2]) { $Matches[2] } elseif ($Matches[3]) { $Matches[3] } else { '' }
                    $description = if ($Matches[4]) { $Matches[4].Trim() } else { '' }
                    if ($bodyText) {
                        $description = if ($description) { "$description $bodyText" } else { $bodyText }
                    }

                    $values = @()
                    if ($bulletValues.Count -gt 0) {
                        $values = $bulletValues
                    } elseif ($inlineValues.Count -gt 0) {
                        $values = $inlineValues
                    } elseif ($metavar) {
                        $values = @(ConvertFrom-RtkEnumeratedDescription $description)
                    }

                    $kind = Get-RtkValueKind -Metavar $metavar -Values $values
                    $options += New-RtkOptionSpec -Names $names -Description ($description -replace '\s*\[possible values:[^\]]*\]', '') -ValueKind $kind -Metavar $metavar -Values $values
                }
            }
            'Arguments' {
                if ($head -match '^\s{2}(?:<([^>]+)>|\[([^\]]+)\])(\.\.\.)?(?:\s{2,}(\S.*))?$') {
                    $metavar = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
                    $variadic = [bool]$Matches[3]
                    $description = if ($Matches[4]) { $Matches[4].Trim() } else { '' }
                    if ($bodyText) {
                        $description = if ($description) { "$description $bodyText" } else { $bodyText }
                    }

                    $values = @()
                    if ($bulletValues.Count -gt 0) {
                        $values = $bulletValues
                    } elseif ($inlineValues.Count -gt 0) {
                        $values = $inlineValues
                    } else {
                        $values = @(ConvertFrom-RtkEnumeratedDescription $description)
                    }

                    $kind = Get-RtkValueKind -Metavar $metavar -Values $values
                    if ($kind -eq 'None') { $kind = 'Text' }
                    $arguments += ConvertTo-RtkArgumentSpec -Metavar $metavar -Description $description -ValueKind $kind -Values $values -Variadic $variadic
                }
            }
        }
    }

    if ($commands.Count -eq 0 -and $options.Count -eq 0 -and $arguments.Count -eq 0) {
        return $null
    }

    ConvertTo-RtkNode -Commands $commands -Options $options -Arguments $arguments -Source 'help'
}

function Get-RtkNode {
    param([string[]]$Path = @())

    $cache = $script:RtkCompletionCache
    $key = ($Path -join ' ')
    if ($cache.Nodes.ContainsKey($key)) {
        return $cache.Nodes[$key]
    }

    $node = $null
    $helpText = Invoke-RtkHelp -Path $Path
    if ($helpText) {
        $node = ConvertFrom-RtkHelp -Text $helpText
    }

    if (-not $node) {
        $node = Get-RtkStaticNode -Path $Path
    }

    $cache.Nodes[$key] = $node
    $node
}

function Get-RtkArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    $first = $true
    foreach ($element in $CommandAst.CommandElements) {
        if ($first) {
            $first = $false
            continue
        }

        if ($element.Extent.EndOffset -ge $CursorPosition) {
            continue
        }

        $text = $element.Extent.Text
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $tokens += $text.Trim([char[]]@([char]34, [char]39))
    }

    $tokens
}

function Get-RtkCurrentWord {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    foreach ($element in $CommandAst.CommandElements) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $extent.EndOffset -gt $CursorPosition) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset).TrimStart([char[]]@([char]34, [char]39))
        }
    }

    $WordToComplete
}

function Get-RtkPathCompletions {
    param(
        [string]$WordToComplete,
        [switch]$DirectoryOnly
    )

    if ([string]::IsNullOrEmpty($WordToComplete)) {
        $items = @(Get-ChildItem -LiteralPath '.' -Force -ErrorAction SilentlyContinue |
            Sort-Object -Property @{ Expression = { -not $_.PSIsContainer } }, Name |
            Select-Object -First 200)

        foreach ($item in $items) {
            if ($DirectoryOnly -and -not $item.PSIsContainer) {
                continue
            }

            $text = '.\' + $item.Name
            if ($text -match '[\s''"`$\[\]{}(),;&|]') {
                $text = "'" + $text.Replace("'", "''") + "'"
            }

            $type = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ProviderItem' }
            New-RtkCompletionResult -CompletionText $text -ToolTip $item.FullName -ResultType $type -ListItemText $item.Name
        }

        return
    }

    $escaped = $WordToComplete.Replace("'", "''")
    $script = "'$escaped'"

    try {
        $result = [System.Management.Automation.CommandCompletion]::CompleteInput($script, $script.Length, $null)
    } catch {
        return @()
    }

    foreach ($match in $result.CompletionMatches) {
        if ($DirectoryOnly -and $match.ResultType -ne 'ProviderContainer') {
            continue
        }

        New-RtkCompletionResult -CompletionText $match.CompletionText -ToolTip $match.ToolTip -ResultType 'ParameterValue' -ListItemText $match.ListItemText
    }
}

function Get-RtkOptionMap {
    param([object[]]$Options)

    $map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($option in $Options) {
        foreach ($name in $option.Names) {
            $map[$name] = $option
        }
    }

    $map
}

function Get-RtkValueCompletions {
    param(
        [string]$ValueKind,
        [string[]]$Values,
        [string]$Metavar,
        [string]$WordToComplete,
        [string]$Prefix = '',
        [string]$ToolTipPrefix = ''
    )

    $candidates = @()
    switch ($ValueKind) {
        'Path' {
            foreach ($result in @(Get-RtkPathCompletions -WordToComplete $WordToComplete)) {
                if ($Prefix) {
                    New-RtkCompletionResult -CompletionText ($Prefix + $result.CompletionText) -ToolTip $result.ToolTip -ResultType 'ParameterValue' -ListItemText $result.ListItemText
                } else {
                    $result
                }
            }
            return
        }
        'Directory' {
            foreach ($result in @(Get-RtkPathCompletions -WordToComplete $WordToComplete -DirectoryOnly)) {
                if ($Prefix) {
                    New-RtkCompletionResult -CompletionText ($Prefix + $result.CompletionText) -ToolTip $result.ToolTip -ResultType 'ParameterValue' -ListItemText $result.ListItemText
                } else {
                    $result
                }
            }
            return
        }
        'Enum' {
            $candidates = @($Values)
        }
        'Integer' {
            $candidates = @('<number>', '10', '50', '100', '200')
        }
        'KeyValue' {
            $candidates = @('<name>=<value>', 'core.pager=', 'user.name=', 'user.email=')
        }
        default {
            $placeholder = if ($Metavar) { '<' + $Metavar.ToLowerInvariant() + '>' } else { '<value>' }
            $candidates = @($placeholder)
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-RtkStartsWith $candidate $WordToComplete) {
            $toolTip = if ($ToolTipPrefix) { "$ToolTipPrefix $candidate" } else { $candidate }
            New-RtkCompletionResult -CompletionText ($Prefix + $candidate) -ToolTip $toolTip -ResultType 'ParameterValue' -ListItemText $candidate
        }
    }
}

function Complete-RtkOptionValue {
    param(
        [object]$Option,
        [string]$WordToComplete,
        [string]$Prefix = ''
    )

    Get-RtkValueCompletions -ValueKind $Option.ValueKind -Values $Option.Values -Metavar $Option.Metavar -WordToComplete $WordToComplete -Prefix $Prefix -ToolTipPrefix "rtk $($Option.Names[-1])"
}

function Get-RtkOptionCompletions {
    param(
        [object[]]$Options,
        [string]$WordToComplete
    )

    foreach ($option in $Options) {
        foreach ($name in $option.Names) {
            if (Test-RtkStartsWith $name $WordToComplete) {
                $listText = if ($option.Metavar) { "$name <$($option.Metavar)>" } else { $name }
                New-RtkCompletionResult -CompletionText $name -ToolTip $option.Description -ResultType 'ParameterName' -ListItemText $listText
            }
        }
    }
}

function Complete-RtkCommandName {
    param(
        [object[]]$Commands,
        [string]$WordToComplete
    )

    foreach ($command in $Commands) {
        if (Test-RtkStartsWith $command.Name $WordToComplete) {
            New-RtkCompletionResult -CompletionText $command.Name -ToolTip $command.Description
        }
    }
}

function Get-RtkCommandContext {
    param([string[]]$Tokens)

    $path = @()
    $node = Get-RtkNode -Path @()
    $positionals = @()
    $pendingOption = $null
    $descending = $true
    $optionsEnded = $false

    foreach ($token in $Tokens) {
        if ($null -ne $pendingOption) {
            $pendingOption = $null
            continue
        }

        if (-not $optionsEnded -and $token -eq '--') {
            $optionsEnded = $true
            $descending = $false
            continue
        }

        if (-not $optionsEnded -and $token.StartsWith('-') -and $token.Length -gt 1) {
            $name = $token
            $attached = $false
            $separator = $token.IndexOf('=')
            if ($separator -gt 0) {
                $name = $token.Substring(0, $separator)
                $attached = $true
            }

            $map = Get-RtkOptionMap $node.Options
            if (-not $attached -and $map.ContainsKey($name) -and $map[$name].ValueKind -ne 'None') {
                $pendingOption = $map[$name]
            }

            continue
        }

        if ($descending -and @($node.Commands | Where-Object { $_.Name -eq $token }).Count -gt 0) {
            $path += $token
            $node = Get-RtkNode -Path $path
            continue
        }

        $descending = $false
        $positionals += $token
    }

    [pscustomobject]@{
        Path          = $path
        Node          = $node
        Positionals   = $positionals
        PendingOption = $pendingOption
        Descending    = $descending
        OptionsEnded  = $optionsEnded
    }
}

function Get-RtkArgumentSpecForIndex {
    param(
        [object]$Node,
        [int]$Index
    )

    $arguments = @($Node.Arguments)
    if ($arguments.Count -eq 0) {
        return $null
    }

    if ($Index -lt $arguments.Count) {
        return $arguments[$Index]
    }

    $last = $arguments[$arguments.Count - 1]
    if ($last.Variadic) {
        return $last
    }

    $null
}

function Complete-Rtk {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @(Get-RtkArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $word = Get-RtkCurrentWord -WordToComplete $WordToComplete -CommandAst $CommandAst -CursorPosition $CursorPosition
    $context = Get-RtkCommandContext -Tokens $tokens
    $node = $context.Node

    if ($null -ne $context.PendingOption) {
        return Complete-RtkOptionValue -Option $context.PendingOption -WordToComplete $word
    }

    if (-not $context.OptionsEnded -and $word -match '^(--?[^=\s]+)=(.*)$') {
        $name = $Matches[1]
        $valueWord = $Matches[2]
        $map = Get-RtkOptionMap $node.Options
        if ($map.ContainsKey($name) -and $map[$name].ValueKind -ne 'None') {
            return Complete-RtkOptionValue -Option $map[$name] -WordToComplete $valueWord -Prefix ($name + '=')
        }

        return @()
    }

    if (-not $context.OptionsEnded -and $word.StartsWith('-')) {
        return Get-RtkOptionCompletions -Options $node.Options -WordToComplete $word
    }

    if ($context.Path.Count -gt 0 -and $context.Path[0] -eq 'help') {
        $helpNode = Get-RtkNode -Path @()
        $helpPath = @()
        foreach ($positional in $context.Positionals) {
            if (@($helpNode.Commands | Where-Object { $_.Name -eq $positional }).Count -eq 0) {
                return @()
            }

            $helpPath += $positional
            $helpNode = Get-RtkNode -Path $helpPath
        }

        return Complete-RtkCommandName -Commands $helpNode.Commands -WordToComplete $word
    }

    if ($context.Descending -and @($node.Commands).Count -gt 0) {
        return Complete-RtkCommandName -Commands $node.Commands -WordToComplete $word
    }

    $argument = Get-RtkArgumentSpecForIndex -Node $node -Index $context.Positionals.Count
    if ($null -ne $argument) {
        $kind = $argument.ValueKind
        if ($kind -eq 'Text' -and $context.Positionals.Count -gt 0) {
            $kind = 'Path'
        }

        return Get-RtkValueCompletions -ValueKind $kind -Values $argument.Values -Metavar $argument.Metavar -WordToComplete $word -ToolTipPrefix $argument.Description
    }

    if ([string]::IsNullOrEmpty($word) -and -not $context.OptionsEnded) {
        return Get-RtkOptionCompletions -Options $node.Options -WordToComplete '--'
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('rtk', 'rtk.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Rtk -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
