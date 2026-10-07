<#
.SYNOPSIS
Registers GitHub CLI (`gh`) tab-completion through the installed `gh` executable.

.DESCRIPTION
This script registers importer-safe native completers for `gh` and `gh.exe`.
Every Tab speaks cobra's completion protocol to the installed GitHub CLI
directly: the typed words are projected from the command AST without being
evaluated and passed to `gh __complete` as a process argument list.

Run once per session, or dot-source it from your PowerShell profile.
#>

Set-StrictMode -Version Latest

function Get-GhCliCommandPath {
    # A missing gh is cached too, so a machine without it pays for the lookup once per session.
    $cachedPath = Get-Variable -Name GhCliCommandPath -Scope Script -ErrorAction Ignore
    if ($null -ne $cachedPath) {
        return $cachedPath.Value
    }

    $ghCommand = Get-Command -Name 'gh', 'gh.exe' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    $script:GhCliCommandPath = if ($null -ne $ghCommand) { $ghCommand.Source } else { $null }
    $script:GhCliCommandPath
}

function Get-GhCliCompletionRequest {
    # Projects the typed command line to the argument list cobra expects, without evaluating anything:
    # string constants by value, every other prior element by its literal text, the word under the cursor
    # cut at the cursor, and an empty final argument when the cursor follows whitespace. Returns $null
    # when the word under the cursor is not literal text (a variable, subexpression, splat, ...).
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    $word = $null
    $quote = ''

    foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $start = $element.Extent.StartOffset
        if ($start -ge $CursorPosition) {
            break
        }

        if ($element.Extent.EndOffset -lt $CursorPosition) {
            if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $arguments.Add($element.Value)
            } else {
                $arguments.Add($element.Extent.Text)
            }
            continue
        }

        $typed = $element.Extent.Text.Substring(0, $CursorPosition - $start)
        $isWhole = $typed.Length -eq $element.Extent.Text.Length
        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            switch ($element.StringConstantType) {
                'BareWord' {
                    $word = if ($isWhole) { $element.Value } else { $typed -replace '`(.)', '$1' }
                }
                'SingleQuoted' {
                    $quote = "'"
                    $word = if ($isWhole) { $element.Value } else { $typed.Substring(1) -replace "''", "'" }
                }
                'DoubleQuoted' {
                    $quote = '"'
                    $word = if ($isWhole) { $element.Value } else { $typed.Substring(1) -replace '`(.)', '$1' }
                }
                default { return $null }
            }
        } elseif ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $null -eq $element.Argument) {
            $word = $typed
        } elseif ($element -is [System.Management.Automation.Language.ArrayLiteralAst] -and
            @($element.Elements | Where-Object { $_ -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or $_.StringConstantType -ne 'BareWord' }).Count -eq 0) {
            # A bare comma list such as '--json number,ti' reaches gh as one argument, exactly as typed.
            $word = $typed
        } else {
            return $null
        }

        break
    }

    if ($null -eq $word) {
        $word = ''
    }
    $arguments.Add($word)

    [pscustomobject]@{
        Arguments = $arguments.ToArray()
        Word      = $word
        Quote     = $quote
    }
}

function Invoke-GhCliCompleteRequest {
    # Runs 'gh __complete <arguments>' directly (no shell, no command-line string) and returns its
    # ANSI-stripped stdout lines. The session's location is handed over because gh resolves the
    # repository from its working directory.
    param([string[]]$Arguments)

    $ghCommandPath = Get-GhCliCommandPath
    if (-not $ghCommandPath) {
        return @()
    }

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($ghCommandPath)
        [void]$startInfo.ArgumentList.Add('__complete')
        foreach ($argument in $Arguments) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        # ActiveHelp lines have no PowerShell rendering; set on the child only.
        $startInfo.Environment['GH_ACTIVE_HELP'] = '0'

        $location = Get-Location -PSProvider FileSystem -ErrorAction Ignore
        if ($location) {
            $startInfo.WorkingDirectory = $location.ProviderPath
        }

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $process.StandardInput.Close()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            [void]$process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) {
                try { $process.Kill($true) } catch { Write-Verbose $_.Exception.Message }
                return @()
            }

            @(($outputTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', '') -split '\r?\n' | Where-Object { $_ -ne '' })
        } finally {
            $process.Dispose()
        }
    } catch {
        Write-Verbose ("gh __complete failed: {0}" -f $_.Exception.Message)
        @()
    }
}

function ConvertTo-GhCliArgument {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed, otherwise in
    # the typed quote style (single by default). A bare comma list stays bare: PowerShell passes it to a
    # native command as one argument.
    param(
        [string]$Value,
        [string]$Quote
    )

    if (-not $Quote) {
        if ($Value -notmatch '[\s{}();|&<>''"`$\u2018-\u201E]' -and $Value -notmatch '^[@#]') {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -eq "'") {
        return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
    }

    '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
}

function Get-GhCliLiveCompletion {
    # Cobra's protocol: 'value<TAB>description' lines, then ':<directive>' with the bit flags
    # 1 Error, 2 NoSpace, 4 NoFileComp, 8 FilterFileExt, 16 FilterDirs, 32 KeepOrder, 64 ActiveHelp.
    # An empty answer leaves the slot to the fallback and then to PowerShell's own path completion.
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $request = Get-GhCliCompletionRequest -CommandAst $CommandAst -CursorPosition $CursorPosition
    if ($null -eq $request) {
        return @()
    }

    $lines = @(Invoke-GhCliCompleteRequest -Arguments $request.Arguments)
    if ($lines.Count -eq 0 -or $lines[-1] -notmatch '^:(?<directive>\d+)$') {
        return @()
    }

    $directive = [int]$Matches['directive']
    if ($directive -band (1 + 8 + 16)) {
        return @()
    }

    # For '--flag=value' cobra answers with bare values; the flag spelling goes back in front.
    $prefix = ''
    $filter = $request.Word
    if ($filter -match '^(?<flag>--[^=]+=)(?<value>.*)$') {
        $prefix = $Matches['flag']
        $filter = $Matches['value']
    }

    $candidates = @(
        foreach ($line in ($lines | Select-Object -SkipLast 1)) {
            $name, $description = $line.Split("`t", 2)
            if ($name -and $name.StartsWith($filter, [System.StringComparison]::OrdinalIgnoreCase)) {
                [pscustomobject]@{ Name = $prefix + $name; Description = $description }
            }
        }
    )

    if (-not ($directive -band 32)) {
        $candidates = @($candidates | Sort-Object -Property Name)
    }

    foreach ($candidate in $candidates) {
        $resultType = if (-not $prefix -and $candidate.Name.StartsWith('-')) { 'ParameterName' } else { 'ParameterValue' }
        $toolTip = if ([string]::IsNullOrWhiteSpace($candidate.Description)) { $candidate.Name } else { $candidate.Description }
        [System.Management.Automation.CompletionResult]::new(
            (ConvertTo-GhCliArgument -Value $candidate.Name -Quote $request.Quote), $candidate.Name, $resultType, $toolTip)
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

function Get-GhCliExtensionList {
    # Installed extensions are the gh-* entries of gh's data directory, read locally instead of
    # spawning 'gh extension list'.
    $dataDirectory = if ($env:XDG_DATA_HOME) {
        Join-Path -Path $env:XDG_DATA_HOME -ChildPath 'gh'
    } elseif ($env:LOCALAPPDATA) {
        Join-Path -Path $env:LOCALAPPDATA -ChildPath 'GitHub CLI'
    } elseif ($HOME) {
        Join-Path -Path $HOME -ChildPath '.local\share\gh'
    }

    if (-not $dataDirectory) {
        return @()
    }

    $extensionDirectory = Join-Path -Path $dataDirectory -ChildPath 'extensions'
    @(Get-ChildItem -LiteralPath $extensionDirectory -Filter 'gh-*' -ErrorAction Ignore | ForEach-Object { $_.Name.Substring(3) })
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
        [string]$Placeholder,
        # Attached option spelling (--method=, -X) kept in front of every completion text.
        [string]$Prefix
    )

    $typed = if ($null -eq $CurrentWord) { '' } else { $CurrentWord.Trim([char[]]@([char]34, [char]39)) }
    $results = @(
        foreach ($value in @($Values)) {
            if (-not [string]::IsNullOrWhiteSpace($value) -and $value.StartsWith($typed, [System.StringComparison]::OrdinalIgnoreCase)) {
                $completionText = if ($value -match '\s') { '"' + $value + '"' } else { $Prefix + $value }
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

    if ($commandPath -like 'api*') {
        $methods = @('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD')
        $methodToolTip = 'HTTP method for the request (default GET).'
        if ($previousToken -in @('-X', '--method')) {
            return ConvertTo-GhCliValueResult -Values $methods -CurrentWord $currentWord -ToolTip $methodToolTip
        }

        # Attached spellings, both accepted by gh: --method=POST and -XPOST.
        if ($currentWord -cmatch '^(?<flag>--method=|-X)(?<value>.+)?$' -and ($Matches['flag'] -eq '--method=' -or $Matches['value'])) {
            return ConvertTo-GhCliValueResult -Values $methods -CurrentWord ([string]$Matches['value']) -ToolTip $methodToolTip -Prefix $Matches['flag']
        }
    }

    switch -Regex ($commandPath) {
        '^api(\s|$)' {
            if ($positionals.Count -eq 0 -and -not $previousToken.StartsWith('-')) {
                return ConvertTo-GhCliValueResult -Values @('user', 'graphql', 'repos/{owner}/{repo}', 'repos/{owner}/{repo}/issues', 'repos/{owner}/{repo}/pulls', 'orgs/{org}', 'search/repositories', 'rate_limit') -CurrentWord $currentWord -ToolTip 'REST endpoint path (or "graphql").' -Placeholder '<endpoint>'
            }
        }
        '^config (get|set)$' {
            $keys = @('api_host', 'git_protocol', 'editor', 'prompt', 'prefer_editor_prompt', 'pager', 'http_unix_socket', 'browser', 'clipboard', 'color_labels', 'accessible_colors', 'accessible_prompter', 'spinner', 'telemetry')
            if ($positionals.Count -eq 0) {
                return ConvertTo-GhCliValueResult -Values $keys -CurrentWord $currentWord -ToolTip 'gh configuration key.' -Placeholder '<key>'
            }

            if ($commandPath -eq 'config set' -and $positionals.Count -eq 1) {
                $values = switch ($positionals[0]) {
                    'git_protocol' { @('https', 'ssh') }
                    'prompt' { @('enabled', 'disabled') }
                    'prefer_editor_prompt' { @('enabled', 'disabled') }
                    'clipboard' { @('enabled', 'disabled') }
                    'color_labels' { @('enabled', 'disabled') }
                    'accessible_colors' { @('enabled', 'disabled') }
                    'accessible_prompter' { @('enabled', 'disabled') }
                    'spinner' { @('enabled', 'disabled') }
                    'telemetry' { @('enabled', 'disabled', 'log') }
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
        '^(extension|extensions|ext) (remove|uninstall|upgrade)$' {
            if ($positionals.Count -eq 0) {
                $extensions = @(Get-GhCliExtensionList)
                if ($commandPath -like '* upgrade') {
                    $extensions += '--all'
                }
                return ConvertTo-GhCliValueResult -Values $extensions -CurrentWord $currentWord -ToolTip 'Installed gh extension.' -Placeholder '<extension>'
            }
        }
        '^(secret|variable) (set|delete|remove)$' {
            if ($positionals.Count -eq 0) {
                return ConvertTo-GhCliValueResult -Values @() -CurrentWord $currentWord -ToolTip 'Secret or variable name.' -Placeholder '<NAME>'
            }
        }
        '^help' {
            # 'gh help <topic>' takes one operand; later words belong to a command path.
            if ($words.Count -gt 1) {
                return @()
            }

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
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $liveResults = @(Get-GhCliLiveCompletion -CommandAst $CommandAst -CursorPosition $CursorPosition)

    # gh's completion offers commands but not the HELP TOPICS for 'gh help <topic>', so that slot
    # also consults the (cheap, cached) fallback and appends the topics.
    $elements = $CommandAst.CommandElements
    $isHelp = $elements.Count -gt 1 -and $elements[1].Extent.Text -eq 'help'
    if ($liveResults.Count -gt 0 -and -not $isHelp) {
        return $liveResults
    }

    @($liveResults) + @(Get-GhCliFallbackCompletion -WordToComplete $WordToComplete -CommandAst $CommandAst -CursorPosition $CursorPosition)
}

Register-ArgumentCompleter -Native -CommandName @('gh', 'gh.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-GhCliCompletion -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
