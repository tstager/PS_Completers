<#
.SYNOPSIS
Registers GitHub CLI (`gh`) tab-completion through the installed `gh` executable.

.DESCRIPTION
This script registers importer-safe native completers for `gh` and `gh.exe`.
The generated completion script is resolved lazily at completion time, cached,
and then invoked through the installed GitHub CLI's own PowerShell completer.

Run once per session, or dot-source it from your PowerShell profile.
#>

Set-StrictMode -Version Latest

function Get-GhCliCommandPath {
    $cachedPath = Get-Variable -Name GhCliCommandPath -Scope Script -ErrorAction Ignore
    if ($null -ne $cachedPath) {
        return $cachedPath.Value
    }

    $ghCommand = Get-Command -Name 'gh', 'gh.exe' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    $script:GhCliCommandPath = if ($null -ne $ghCommand) { $ghCommand.Source } else { $null }
    $script:GhCliCommandPath
}

function Get-GhCliGeneratedCompletionScript {
    # A completion callback must stay silent: diagnostics go to the verbose stream only.
    $ghCommandPath = Get-GhCliCommandPath
    if ([string]::IsNullOrWhiteSpace($ghCommandPath)) {
        Write-Verbose 'GitHub CLI (gh) was not found in PATH.'
        return $null
    }

    try {
        $completionScript = $null | & $ghCommandPath completion -s powershell 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String

        if ([string]::IsNullOrWhiteSpace($completionScript)) {
            Write-Verbose 'gh returned an empty completion script.'
            return $null
        }

        return $completionScript
    } catch {
        Write-Verbose ("Failed to load gh completion: {0}" -f $_.Exception.Message)
        $null
    }
}

function Get-GhCliCompletionInvoker {
    $cachedInvoker = Get-Variable -Name GhCliCompletionInvoker -Scope Script -ErrorAction Ignore
    if ($null -ne $cachedInvoker) {
        return $cachedInvoker.Value
    }

    # A failed discovery is cached too, so a machine without gh pays for it once per session.
    if (Get-Variable -Name GhCliCompletionUnavailable -Scope Script -ErrorAction Ignore) {
        return $null
    }

    $completionScript = Get-GhCliGeneratedCompletionScript
    if ([string]::IsNullOrWhiteSpace($completionScript)) {
        $script:GhCliCompletionUnavailable = $true
        return $null
    }

    $completionScript = $completionScript -replace (
        "(?m)^\s*Register-ArgumentCompleter\s+-CommandName\s+'gh'\s+-ScriptBlock\s+\$\{__ghCompleterBlock\}\s*\r?$"
    ), ''

    # gh's block dereferences properties of an empty pipeline when there are no suggestions; run it
    # outside this script's strict mode so those accesses stay silent.
    $completionInvokerSource = @"
Set-StrictMode -Off
$completionScript

& `${__ghCompleterBlock} @args
"@

    try {
        $script:GhCliCompletionInvoker = [scriptblock]::Create($completionInvokerSource)
        return $script:GhCliCompletionInvoker
    } catch {
        Write-Verbose ("Failed to prepare gh completion: {0}" -f $_.Exception.Message)
        $script:GhCliCompletionUnavailable = $true
        $null
    }
}

function Get-GhCliConfigDirectory {
    $candidates = @()
    if ($env:GH_CONFIG_DIR) { $candidates += $env:GH_CONFIG_DIR }
    if ($env:APPDATA) { $candidates += (Join-Path -Path $env:APPDATA -ChildPath 'GitHub CLI') }
    if ($HOME) { $candidates += (Join-Path -Path $HOME -ChildPath '.config\gh') }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return $candidate
        }
    }

    $null
}

function Get-GhCliConfiguredAliasList {
    # The 'aliases:' block of config.yml, read locally instead of spawning 'gh alias list'.
    $configDirectory = Get-GhCliConfigDirectory
    if (-not $configDirectory) {
        return @()
    }

    $configFile = Join-Path -Path $configDirectory -ChildPath 'config.yml'
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        return @()
    }

    $names = New-Object System.Collections.Generic.List[string]
    $inAliases = $false
    foreach ($line in @(Get-Content -LiteralPath $configFile -ErrorAction Ignore)) {
        if ($line -match '^aliases:\s*$') {
            $inAliases = $true
            continue
        }

        if ($inAliases) {
            if ($line -match '^\s+(?<name>[A-Za-z0-9_-]+):') {
                [void]$names.Add($Matches['name'])
                continue
            }

            if ($line -match '^\S' -and $line -notmatch '^\s*#') {
                $inAliases = $false
            }
        }
    }

    @($names.ToArray())
}

function Get-GhCliConfiguredHostList {
    $hosts = New-Object System.Collections.Generic.List[string]
    [void]$hosts.Add('github.com')

    $configDirectory = Get-GhCliConfigDirectory
    if ($configDirectory) {
        $hostsFile = Join-Path -Path $configDirectory -ChildPath 'hosts.yml'
        foreach ($line in @(Get-Content -LiteralPath $hostsFile -ErrorAction Ignore)) {
            if ($line -match '^(?<host>[A-Za-z0-9.-]+):\s*$') {
                [void]$hosts.Add($Matches['host'])
            }
        }
    }

    @($hosts.ToArray() | Select-Object -Unique)
}

function Get-GhCliHelpTopicList {
    $cachedTopics = Get-Variable -Name GhCliHelpTopics -Scope Script -ErrorAction Ignore
    if ($null -ne $cachedTopics) {
        return $cachedTopics.Value
    }

    $topics = New-Object System.Collections.Generic.List[object]
    $ghCommandPath = Get-GhCliCommandPath
    if ($ghCommandPath) {
        $inTopics = $false
        foreach ($line in @($null | & $ghCommandPath --help 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })) {
            if ($line -match '^HELP TOPICS') {
                $inTopics = $true
                continue
            }

            if ($inTopics) {
                if ($line -match '^\s+(?<name>[a-z-]+):\s+(?<desc>\S.*)$') {
                    [void]$topics.Add([pscustomobject]@{ Name = $Matches['name']; Description = $Matches['desc'].Trim() })
                    continue
                }

                if ($line -match '^\S') {
                    break
                }
            }
        }
    }

    $script:GhCliHelpTopics = @($topics.ToArray())
    $script:GhCliHelpTopics
}

function Get-GhCliLocalBranchList {
    $gitCommand = Get-Command -Name 'git' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if (-not $gitCommand) {
        return @()
    }

    try {
        @($null | & $gitCommand.Source for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>$null | Where-Object { $_ -and $_ -notmatch '/HEAD$' })
    } catch {
        @()
    }
}

function Get-GhCliWorkflowFileList {
    $workflowDirectory = Join-Path -Path (Get-Location).Path -ChildPath '.github\workflows'
    @(Get-ChildItem -LiteralPath $workflowDirectory -File -ErrorAction Ignore | Where-Object { $_.Extension -in @('.yml', '.yaml') } | ForEach-Object { $_.Name })
}

function ConvertTo-GhCliValueResult {
    param(
        [string[]]$Values,
        [string]$CurrentWord,
        [string]$ToolTip,
        [string]$Placeholder
    )

    $typed = if ($null -eq $CurrentWord) { '' } else { $CurrentWord.Trim([char[]]@([char]34, [char]39)) }
    $results = @(
        foreach ($value in @($Values)) {
            if (-not [string]::IsNullOrWhiteSpace($value) -and $value.StartsWith($typed, [System.StringComparison]::OrdinalIgnoreCase)) {
                $completionText = if ($value -match '\s') { '"' + $value + '"' } else { $value }
                [System.Management.Automation.CompletionResult]::new($completionText, $value, 'ParameterValue', $ToolTip)
            }
        }
    )

    if ($results.Count -gt 0) {
        return $results
    }

    if ($Placeholder) {
        $completionText = if ($typed) { $typed } else { $Placeholder }
        return @([System.Management.Automation.CompletionResult]::new($completionText, $Placeholder, 'ParameterValue', $ToolTip))
    }

    @()
}

function Get-GhCliFallbackCompletion {
    # Value model for the slots gh's own completer leaves empty: closed enums from gh's help and
    # cheap local state (config aliases and hosts, git branches, workflow files).
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $priorTokens = @(
        foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
            if ($element.Extent.EndOffset -lt $CursorPosition) {
                $element.Extent.Text.Trim([char[]]@([char]34, [char]39))
            }
        }
    )

    $words = @($priorTokens | Where-Object { -not $_.StartsWith('-') })
    if ($words.Count -gt 0 -and $words[0] -eq 'co') {
        $words = @('pr', 'checkout') + @($words | Select-Object -Skip 1)
    }

    $commandPath = (@($words | Select-Object -First 2) -join ' ')
    $positionals = @($words | Select-Object -Skip 2)
    $previousToken = if ($priorTokens.Count -gt 0) { $priorTokens[-1] } else { '' }
    $currentWord = if ($null -eq $WordToComplete) { '' } else { $WordToComplete }

    if ($previousToken -eq '--hostname' -or $previousToken -eq '-h' -and $commandPath -like 'auth *') {
        return ConvertTo-GhCliValueResult -Values (Get-GhCliConfiguredHostList) -CurrentWord $currentWord -ToolTip 'GitHub host name.' -Placeholder '<hostname>'
    }

    if ($commandPath -like 'api*' -and $previousToken -in @('-X', '--method')) {
        return ConvertTo-GhCliValueResult -Values @('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD') -CurrentWord $currentWord -ToolTip 'HTTP method for the request (default GET).'
    }

    switch -Regex ($commandPath) {
        '^api(\s|$)' {
            if ($positionals.Count -eq 0 -and -not $previousToken.StartsWith('-')) {
                return ConvertTo-GhCliValueResult -Values @('user', 'graphql', 'repos/{owner}/{repo}', 'repos/{owner}/{repo}/issues', 'repos/{owner}/{repo}/pulls', 'orgs/{org}', 'search/repositories', 'rate_limit') -CurrentWord $currentWord -ToolTip 'REST endpoint path (or "graphql").' -Placeholder '<endpoint>'
            }
        }
        '^config (get|set)$' {
            $keys = @('git_protocol', 'editor', 'prompt', 'prefer_editor_prompt', 'pager', 'http_unix_socket', 'browser', 'color_labels', 'accessible_colors', 'accessible_prompter', 'spinner')
            if ($positionals.Count -eq 0) {
                return ConvertTo-GhCliValueResult -Values $keys -CurrentWord $currentWord -ToolTip 'gh configuration key.' -Placeholder '<key>'
            }

            if ($commandPath -eq 'config set' -and $positionals.Count -eq 1) {
                $values = switch ($positionals[0]) {
                    'git_protocol' { @('https', 'ssh') }
                    'prompt' { @('enabled', 'disabled') }
                    'prefer_editor_prompt' { @('enabled', 'disabled') }
                    'color_labels' { @('enabled', 'disabled') }
                    'accessible_colors' { @('enabled', 'disabled') }
                    'accessible_prompter' { @('enabled', 'disabled') }
                    'spinner' { @('enabled', 'disabled') }
                    default { @() }
                }
                return ConvertTo-GhCliValueResult -Values $values -CurrentWord $currentWord -ToolTip ('Value for ' + $positionals[0] + '.') -Placeholder '<value>'
            }
        }
        '^alias (delete|set)$' {
            if ($positionals.Count -eq 0) {
                return ConvertTo-GhCliValueResult -Values (Get-GhCliConfiguredAliasList) -CurrentWord $currentWord -ToolTip 'gh alias from config.yml.' -Placeholder '<alias>'
            }
        }
        '^workflow (run|view|enable|disable)$' {
            if ($positionals.Count -eq 0) {
                return ConvertTo-GhCliValueResult -Values (Get-GhCliWorkflowFileList) -CurrentWord $currentWord -ToolTip 'Workflow file under .github/workflows.' -Placeholder '<workflow>'
            }
        }
        '^pr checkout$' {
            if ($positionals.Count -eq 0) {
                return ConvertTo-GhCliValueResult -Values (Get-GhCliLocalBranchList) -CurrentWord $currentWord -ToolTip 'Local branch (or a PR number/URL).' -Placeholder '<number|url|branch>'
            }
        }
        '^(secret|variable) (set|delete|remove)$' {
            if ($positionals.Count -eq 0) {
                return ConvertTo-GhCliValueResult -Values @() -CurrentWord $currentWord -ToolTip 'Secret or variable name.' -Placeholder '<NAME>'
            }
        }
        '^help' {
            $topics = @(Get-GhCliHelpTopicList)
            $typed = $currentWord.Trim([char[]]@([char]34, [char]39))
            return @(
                foreach ($topic in $topics) {
                    if ($topic.Name.StartsWith($typed, [System.StringComparison]::OrdinalIgnoreCase)) {
                        [System.Management.Automation.CompletionResult]::new($topic.Name, $topic.Name, 'ParameterValue', $topic.Description)
                    }
                }
            )
        }
    }

    @()
}

function Invoke-GhCliCompletion {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $completionInvoker = Get-GhCliCompletionInvoker
    if ($null -eq $completionInvoker) {
        return
    }

    # gh's generated block lets the child process's 'Completion ended with directive' banner reach
    # stderr; redirecting the whole invocation keeps the console clean.
    $delegated = @()
    try {
        $delegated = @(& $completionInvoker $wordToComplete $commandAst $cursorPosition 2>$null)
    } catch {
        Write-Verbose ("gh completion block failed: {0}" -f $_.Exception.Message)
    }
    $realResults = @($delegated | Where-Object { $_ -is [System.Management.Automation.CompletionResult] })

    if ($realResults.Count -gt 0) {
        return $realResults
    }

    $fallback = @(Get-GhCliFallbackCompletion -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition)
    if ($fallback.Count -gt 0) {
        return $fallback
    }

    # Pass through gh's own "" sentinel (ShellCompDirectiveNoFileComp) or nothing (file completion allowed).
    $delegated
}

Register-ArgumentCompleter -Native -CommandName @('gh', 'gh.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-GhCliCompletion -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
