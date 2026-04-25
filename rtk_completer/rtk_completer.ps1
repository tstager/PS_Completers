Set-StrictMode -Version 2.0

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

        [string]$ValueKind = 'None'
    )

    [pscustomobject]@{
        Names       = $Names
        Description = $Description
        ValueKind   = $ValueKind
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

function Get-RtkRootCommands {
    @(
        New-RtkCommandSpec 'ls' 'List files and directories'
        New-RtkCommandSpec 'tree' 'Display directory tree'
        New-RtkCommandSpec 'read' 'Read files for context'
        New-RtkCommandSpec 'smart' 'Smart tool wrapper'
        New-RtkCommandSpec 'git' 'Run git with rtk defaults'
        New-RtkCommandSpec 'gh' 'Run GitHub CLI with rtk defaults'
        New-RtkCommandSpec 'aws' 'Run AWS CLI with rtk defaults'
        New-RtkCommandSpec 'psql' 'Run psql with rtk defaults'
        New-RtkCommandSpec 'pnpm' 'Run pnpm with rtk defaults'
        New-RtkCommandSpec 'err' 'Explain errors'
        New-RtkCommandSpec 'test' 'Run tests'
        New-RtkCommandSpec 'json' 'Work with JSON'
        New-RtkCommandSpec 'deps' 'Inspect dependencies'
        New-RtkCommandSpec 'env' 'Inspect environment'
        New-RtkCommandSpec 'find' 'Find files'
        New-RtkCommandSpec 'diff' 'Show diffs'
        New-RtkCommandSpec 'log' 'Show logs'
        New-RtkCommandSpec 'dotnet' 'Run dotnet with rtk defaults'
        New-RtkCommandSpec 'docker' 'Run docker with rtk defaults'
        New-RtkCommandSpec 'kubectl' 'Run kubectl with rtk defaults'
        New-RtkCommandSpec 'summary' 'Summarize output'
        New-RtkCommandSpec 'grep' 'Search text'
        New-RtkCommandSpec 'init' 'Initialize rtk configuration'
        New-RtkCommandSpec 'wget' 'Run wget with rtk defaults'
        New-RtkCommandSpec 'wc' 'Count lines, words, or bytes'
        New-RtkCommandSpec 'gain' 'Gain workflow helper'
        New-RtkCommandSpec 'cc-economics' 'Claude Code economics helper'
        New-RtkCommandSpec 'config' 'Manage rtk configuration'
        New-RtkCommandSpec 'vitest' 'Run vitest with rtk defaults'
        New-RtkCommandSpec 'prisma' 'Run prisma with rtk defaults'
        New-RtkCommandSpec 'tsc' 'Run TypeScript compiler with rtk defaults'
        New-RtkCommandSpec 'next' 'Run Next.js with rtk defaults'
        New-RtkCommandSpec 'lint' 'Run lint command'
        New-RtkCommandSpec 'prettier' 'Run prettier with rtk defaults'
        New-RtkCommandSpec 'format' 'Format files'
        New-RtkCommandSpec 'playwright' 'Run Playwright with rtk defaults'
        New-RtkCommandSpec 'cargo' 'Run cargo with rtk defaults'
        New-RtkCommandSpec 'npm' 'Run npm with rtk defaults'
        New-RtkCommandSpec 'npx' 'Run npx with rtk defaults'
        New-RtkCommandSpec 'curl' 'Run curl with rtk defaults'
        New-RtkCommandSpec 'discover' 'Discover project context'
        New-RtkCommandSpec 'session' 'Manage rtk sessions'
        New-RtkCommandSpec 'telemetry' 'Manage telemetry'
        New-RtkCommandSpec 'learn' 'Learn command behavior'
        New-RtkCommandSpec 'proxy' 'Run proxy helper'
        New-RtkCommandSpec 'trust' 'Trust a path or tool'
        New-RtkCommandSpec 'untrust' 'Remove trust'
        New-RtkCommandSpec 'verify' 'Verify environment or configuration'
        New-RtkCommandSpec 'ruff' 'Run ruff with rtk defaults'
        New-RtkCommandSpec 'pytest' 'Run pytest with rtk defaults'
        New-RtkCommandSpec 'mypy' 'Run mypy with rtk defaults'
        New-RtkCommandSpec 'rake' 'Run rake with rtk defaults'
        New-RtkCommandSpec 'rubocop' 'Run rubocop with rtk defaults'
        New-RtkCommandSpec 'rspec' 'Run rspec with rtk defaults'
        New-RtkCommandSpec 'pip' 'Run pip with rtk defaults'
        New-RtkCommandSpec 'go' 'Run go with rtk defaults'
        New-RtkCommandSpec 'gt' 'Run gt with rtk defaults'
        New-RtkCommandSpec 'golangci-lint' 'Run golangci-lint with rtk defaults'
        New-RtkCommandSpec 'hook-audit' 'Audit hooks'
        New-RtkCommandSpec 'rewrite' 'Rewrite command output'
        New-RtkCommandSpec 'hook' 'Run hook helper'
        New-RtkCommandSpec 'help' 'Show help'
    )
}

function Get-RtkGlobalOptions {
    @(
        New-RtkOptionSpec @('-v', '--verbose') 'Enable verbose output'
        New-RtkOptionSpec @('--ultra-compact') 'Use ultra-compact output'
        New-RtkOptionSpec @('--skip-env') 'Skip environment loading'
        New-RtkOptionSpec @('-h', '--help') 'Show help'
        New-RtkOptionSpec @('-V', '--version') 'Show version'
    )
}

function Get-RtkCommandOptions {
    param([string]$Command)

    $options = @(Get-RtkGlobalOptions)

    switch ($Command) {
        'read' {
            $options += @(
                New-RtkOptionSpec @('-l', '--level') 'Compaction level' 'ReadLevel'
                New-RtkOptionSpec @('-m', '--max-lines') 'Maximum lines to read' 'Integer'
                New-RtkOptionSpec @('--tail-lines') 'Read trailing lines' 'Integer'
                New-RtkOptionSpec @('-n', '--line-numbers') 'Show line numbers'
            )
        }
        'git' {
            $options += @(
                New-RtkOptionSpec @('-C') 'Run as if git was started in the specified directory' 'Path'
                New-RtkOptionSpec @('-c') 'Pass a configuration parameter to git' 'KeyValue'
                New-RtkOptionSpec @('--git-dir') 'Set the path to the repository' 'Path'
                New-RtkOptionSpec @('--work-tree') 'Set the path to the working tree' 'Path'
                New-RtkOptionSpec @('--no-pager') 'Do not pipe output into a pager'
                New-RtkOptionSpec @('--no-optional-locks') 'Do not perform optional operations that require locks'
                New-RtkOptionSpec @('--bare') 'Treat the repository as bare'
                New-RtkOptionSpec @('--literal-pathspecs') 'Treat pathspecs literally'
            )
        }
        'config' {
            $options += @(New-RtkOptionSpec @('--create') 'Create configuration file')
        }
    }

    $options
}

function Get-RtkGitCommands {
    @(
        New-RtkCommandSpec 'diff' 'Show changes'
        New-RtkCommandSpec 'log' 'Show commit logs'
        New-RtkCommandSpec 'status' 'Show working tree status'
        New-RtkCommandSpec 'show' 'Show objects'
        New-RtkCommandSpec 'add' 'Add file contents to the index'
        New-RtkCommandSpec 'commit' 'Record changes'
        New-RtkCommandSpec 'push' 'Update remote refs'
        New-RtkCommandSpec 'pull' 'Fetch and integrate changes'
        New-RtkCommandSpec 'branch' 'List, create, or delete branches'
        New-RtkCommandSpec 'fetch' 'Download objects and refs'
        New-RtkCommandSpec 'stash' 'Stash changes'
        New-RtkCommandSpec 'worktree' 'Manage worktrees'
        New-RtkCommandSpec 'help' 'Show git help'
    )
}

function Get-RtkArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements) {
        if ($element.Extent.EndOffset -gt $CursorPosition) {
            continue
        }

        $text = $element.Extent.Text
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $tokens += $text.Trim([char[]]@([char]34, [char]39))
    }

    if ($tokens.Count -le 1) {
        return @()
    }

    $tokens[1..($tokens.Count - 1)]
}

function Get-RtkPathCompletions {
    param(
        [string]$WordToComplete,
        [switch]$DirectoryOnly
    )

    $pathWord = if ([string]::IsNullOrEmpty($WordToComplete)) { '.' } else { $WordToComplete }
    $escaped = $pathWord.Replace("'", "''")
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

        New-RtkCompletionResult $match.CompletionText $match.ToolTip 'ParameterValue' $match.ListItemText
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

function Get-RtkPendingOption {
    param(
        [string[]]$Tokens,
        [object[]]$Options,
        [string]$WordToComplete
    )

    if ($Tokens.Count -eq 0) {
        return $null
    }

    $tokensToInspect = $Tokens
    if ($Tokens.Count -gt 1 -and $Tokens[-1] -eq $WordToComplete) {
        $tokensToInspect = $Tokens[0..($Tokens.Count - 2)]
    }

    $map = Get-RtkOptionMap $Options
    for ($index = $tokensToInspect.Count - 1; $index -ge 0; $index--) {
        $token = $tokensToInspect[$index]
        if (-not $map.ContainsKey($token)) {
            continue
        }

        $option = $map[$token]
        if ($option.ValueKind -eq 'None') {
            return $null
        }

        if ($index -eq ($tokensToInspect.Count - 1)) {
            return $option
        }

        return $null
    }

    $null
}

function Get-RtkClosedValues {
    param([string]$ValueKind)

    switch ($ValueKind) {
        'ReadLevel' { @('none', 'minimal', 'aggressive') }
        default { @() }
    }
}

function Get-RtkValueCompletions {
    param(
        [object]$Option,
        [string]$WordToComplete
    )

    switch ($Option.ValueKind) {
        'Path' {
            Get-RtkPathCompletions -WordToComplete $WordToComplete -DirectoryOnly
        }
        'ReadLevel' {
            Get-RtkClosedValues $Option.ValueKind |
                Where-Object { Test-RtkStartsWith $_ $WordToComplete } |
                ForEach-Object { New-RtkCompletionResult $_ "rtk $($Option.Names[-1]) $_" }
        }
        'Integer' {
            foreach ($value in @('<number>', '10', '50', '100', '200')) {
                if (Test-RtkStartsWith $value $WordToComplete) {
                    New-RtkCompletionResult $value "rtk $($Option.Names[-1]) $value"
                }
            }
        }
        'KeyValue' {
            foreach ($value in @('<name>=<value>', 'core.pager=', 'user.name=', 'user.email=')) {
                if (Test-RtkStartsWith $value $WordToComplete) {
                    New-RtkCompletionResult $value "rtk $($Option.Names[-1]) $value"
                }
            }
        }
    }
}

function Get-RtkOptionCompletions {
    param(
        [object[]]$Options,
        [string]$WordToComplete
    )

    foreach ($option in $Options) {
        foreach ($name in $option.Names) {
            if (Test-RtkStartsWith $name $WordToComplete) {
                New-RtkCompletionResult $name $option.Description 'ParameterName'
            }
        }
    }
}

function Get-RtkCommandContext {
    param([string[]]$Tokens)

    $rootCommands = @(Get-RtkRootCommands).Name
    $command = $null
    $remaining = @()

    for ($index = 0; $index -lt $Tokens.Count; $index++) {
        $token = $Tokens[$index]
        if ($token.StartsWith('-')) {
            continue
        }

        if ($rootCommands -contains $token) {
            $command = $token
            if ($index + 1 -lt $Tokens.Count) {
                $remaining = $Tokens[($index + 1)..($Tokens.Count - 1)]
            }
            break
        }
    }

    [pscustomobject]@{
        Command   = $command
        Remaining = $remaining
    }
}

function Complete-Rtk {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @(Get-RtkArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $context = Get-RtkCommandContext $tokens
    $command = $context.Command
    $options = @(Get-RtkCommandOptions $command)
    $pendingOption = Get-RtkPendingOption -Tokens $tokens -Options $options -WordToComplete $WordToComplete

    if ($null -ne $pendingOption) {
        return Get-RtkValueCompletions -Option $pendingOption -WordToComplete $WordToComplete
    }

    if ($WordToComplete.StartsWith('-')) {
        return Get-RtkOptionCompletions -Options $options -WordToComplete $WordToComplete
    }

    if ($command -eq 'read') {
        return Get-RtkPathCompletions -WordToComplete $WordToComplete
    }

    if ($command -eq 'git') {
        $gitCommandSeen = $false
        foreach ($token in $context.Remaining) {
            if ($token.StartsWith('-')) {
                continue
            }

            if ((Get-RtkGitCommands).Name -contains $token) {
                $gitCommandSeen = $true
                break
            }
        }

        if (-not $gitCommandSeen) {
            return Get-RtkGitCommands |
                Where-Object { Test-RtkStartsWith $_.Name $WordToComplete } |
                ForEach-Object { New-RtkCompletionResult $_.Name $_.Description }
        }

        return @()
    }

    if ($null -eq $command) {
        return Get-RtkRootCommands |
            Where-Object { Test-RtkStartsWith $_.Name $WordToComplete } |
            ForEach-Object { New-RtkCompletionResult $_.Name $_.Description }
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('rtk', 'rtk.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Rtk -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
