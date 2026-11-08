# Help-driven completer for wtcli.exe, the Intelligent Terminal CLI (microsoft/intelligent-terminal).
# Commands, aliases, options, value types and enums come from live --help. Window, tab, pane and
# profile values come from read-only `wtcli --json list-*` queries, and only inside an Intelligent
# Terminal pane, because those queries use COM activation and would otherwise start Terminal.

Set-StrictMode -Version 2.0

function New-WtcliCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip = '',
        [string]$ListItemText = ''
    )

    if ([string]::IsNullOrWhiteSpace($CompletionText)) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $ListItemText
    }

    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

function Get-WtcliCache {
    param([string]$Name)

    $cache = Get-Variable -Name $Name -Scope Script -ErrorAction Ignore
    if ($null -eq $cache -or $null -eq $cache.Value) {
        Set-Variable -Name $Name -Scope Script -Value ([System.Collections.Hashtable]::new([System.StringComparer]::Ordinal))
    }

    return (Get-Variable -Name $Name -Scope Script).Value
}

function Get-WtcliExecutablePath {
    foreach ($candidate in @('wtcli.exe', 'wtcli')) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction Ignore | Select-Object -First 1
        if ($null -ne $command) {
            return $command.Source
        }
    }

    return ''
}

function Invoke-WtcliCapture {
    # Runs wtcli with stdin closed and a hard timeout. Returns $null when it cannot run or times out.
    param(
        [string[]]$Arguments,
        [int]$TimeoutMs = 3000
    )

    $path = Get-WtcliExecutablePath
    if ([string]::IsNullOrWhiteSpace($path)) {
        return $null
    }

    $process = [System.Diagnostics.Process]::new()
    try {
        $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($path)
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        foreach ($argument in @($Arguments)) {
            [void]$process.StartInfo.ArgumentList.Add($argument)
        }

        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()

        if ($process.WaitForExit($TimeoutMs)) {
            return [pscustomobject]@{
                ExitCode = $process.ExitCode
                Output   = ($stdout.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
                Error    = ($stderr.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
            }
        }

        try { $process.Kill($true) } catch { Write-Debug "wtcli kill failed: $_" }
    }
    catch {
        Write-Debug "wtcli capture failed: $_"
    }
    finally {
        $process.Dispose()
    }

    return $null
}

function Get-WtcliRootFallbackHelp {
    # Root help of Intelligent Terminal 0.3.3083.0, used only when wtcli cannot be run.
    @'
OPTIONS:
  -h,     --help              Print this help message and exit
          --json              Output raw JSON
          --skip-authenticate Skip the compatibility handshake (testing only)

SUBCOMMANDS:
  list-windows, lsw           List all windows
  list-tabs, lst              List tabs in a window
  list-panes, lsp             List panes in a tab
  list-profiles               List effective terminal profiles, including dynamically generated
                              agent profiles
  get-settings                Read the current Terminal settings
  active-pane                 Show the currently active pane
  capture-pane, capturep      Capture pane output
  get-pane-context            Resolve a pane and capture bounded context (requires the
                              authentication handshake)
  pane-status                 Show pane process status
  new-tab, neww               Create a new tab
  split-pane, splitw          Split a pane
  kill-pane, killp            Close a pane
  send-keys, send             Send keys to a pane
  focus-pane, focusp          Switch focus to a pane
  test-pipe                   Test connection to Windows Terminal
  info                        Show connection info
  wait-for                    Wait for a pane to exit
  set-env, setenv             Print env setup commands
  publish                     Forward raw JSON to SendEvent
  send-event, se              Publish an event to all listeners
  agent-hook                  Forward an agent lifecycle hook from stdin
  listen                      Stream real-time events from Windows Terminal
'@
}

function ConvertFrom-WtcliHelp {
    # Parses CLI11 help: OPTIONS, SUBCOMMANDS and POSITIONALS sections, with wrapped descriptions.
    param([string]$Text)

    $options = New-Object System.Collections.Generic.List[object]
    $commands = New-Object System.Collections.Generic.List[object]
    $positionals = New-Object System.Collections.Generic.List[object]
    $section = ''
    $last = $null

    foreach ($line in @($Text -split "\r?\n")) {
        if ($line -match '^(?<name>OPTIONS|SUBCOMMANDS|POSITIONALS):\s*$') {
            $section = $Matches.name
            $last = $null
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line) -or $line -notmatch '^\s') {
            $last = $null
            continue
        }

        if ($null -ne $last -and $line -match '^\s{20,}(?<text>\S.*?)\s*$') {
            $last.Description = ($last.Description + ' ' + $Matches.text).Trim()
            continue
        }

        switch ($section) {
            'OPTIONS' {
                if ($line -match '^\s{2}(?:(?<short>-[A-Za-z0-9]),)?\s+(?<long>--[A-Za-z0-9][A-Za-z0-9-]*)(?<spec>(?: \S+)*)\s*(?<desc>.*?)\s*$' -or
                    $line -match '^\s{2}(?<short>-[A-Za-z0-9])(?<spec>(?: \S+)*)\s*(?<desc>.*?)\s*$') {
                    # Every -match below replaces $Matches, so the line's groups are kept in $m.
                    $m = $Matches.Clone()
                    $names = @(@($m['short'], $m['long']) | Where-Object { -not [string]::IsNullOrEmpty($_) })
                    $specTokens = @($m['spec'].Trim() -split ' ' | Where-Object { $_ })
                    $type = ''
                    if ($specTokens.Count -gt 0 -and $specTokens[0] -cmatch '^[A-Z]+$' -and $specTokens[0] -cne 'REQUIRED') {
                        $type = $specTokens[0]
                    }

                    $last = [pscustomobject]@{
                        Names       = $names
                        Long        = [string]$names[-1]
                        Type        = $type
                        TakesValue  = -not [string]::IsNullOrEmpty($type)
                        Description = [string]$m['desc']
                    }
                    [void]$options.Add($last)
                }
            }
            'SUBCOMMANDS' {
                if ($line -match '^\s{2}(?<names>[a-z][a-z0-9-]*(?:, [a-z][a-z0-9-]*)*)(?:\s{2,}(?<desc>.*?))?\s*$') {
                    $names = @($Matches.names -split ', ')
                    $last = [pscustomobject]@{
                        Name        = $names[0]
                        Aliases     = @($names | Select-Object -Skip 1)
                        Description = [string]$Matches['desc']
                    }
                    [void]$commands.Add($last)
                }
            }
            'POSITIONALS' {
                if ($line -match '^\s{2}(?<name>[a-z][a-z0-9_-]*) (?<type>[A-Z]+)(?<spec>.*)$') {
                    $name = $Matches['name']
                    $spec = $Matches['spec']
                    $description = if ($spec -match '\s{2,}(?<desc>\S.*?)\s*$') { $Matches['desc'] } else { $spec.Trim() }
                    $last = [pscustomobject]@{
                        Name        = $name
                        Repeating   = $spec.StartsWith(' ...')
                        Description = $description
                    }
                    [void]$positionals.Add($last)
                }
            }
        }
    }

    foreach ($option in $options) {
        $enums = @()
        if ($option.Description -match '(?<list>[a-z]+(?:\|[a-z]+)+)') {
            $enums = @($Matches.list -split '\|')
        }
        elseif ($option.Description -match ':\s*(?<list>[a-z]+(?:, [a-z]+)+)\s*$') {
            $enums = @($Matches.list -split ', ')
        }

        $option | Add-Member -NotePropertyName Enums -NotePropertyValue $enums
    }

    # @($list) inside a [pscustomobject] literal throws "Argument types do not match"; ToArray() does not.
    return [pscustomobject]@{
        Options     = $options.ToArray()
        Commands    = $commands.ToArray()
        Positionals = $positionals.ToArray()
    }
}

function Get-WtcliCatalog {
    # Catalog for the root ('') or one canonical subcommand, parsed from live help and cached.
    # A failed help call is retried after 30 seconds rather than on every keystroke.
    param([string]$Command = '')

    $cache = Get-WtcliCache -Name 'WtcliHelpCache'
    $entry = $cache[$Command]
    if ($null -ne $entry -and ($entry.Ok -or ([DateTime]::UtcNow - $entry.Time).TotalSeconds -lt 30)) {
        return $entry.Catalog
    }

    $arguments = if ($Command) { @($Command, '--help') } else { @('--help') }
    $result = Invoke-WtcliCapture -Arguments $arguments
    $ok = $null -ne $result -and $result.Output -match '(?m)^OPTIONS:'
    if ($ok) {
        $catalog = ConvertFrom-WtcliHelp -Text $result.Output
    }
    elseif ($Command) {
        $catalog = ConvertFrom-WtcliHelp -Text "OPTIONS:`n  -h,     --help              Print this help message and exit"
    }
    else {
        $catalog = ConvertFrom-WtcliHelp -Text (Get-WtcliRootFallbackHelp)
    }

    $cache[$Command] = @{ Ok = $ok; Time = [DateTime]::UtcNow; Catalog = $catalog }
    return $catalog
}

function Find-WtcliCommand {
    param(
        [object]$RootCatalog,
        [string]$Name
    )

    foreach ($command in @($RootCatalog.Commands)) {
        if ($command.Name -ceq $Name -or @($command.Aliases) -ccontains $Name) {
            return $command
        }
    }

    return $null
}

function Find-WtcliOption {
    param(
        [object]$Catalog,
        [string]$Name
    )

    foreach ($option in @($Catalog.Options)) {
        if (@($option.Names) -ccontains $Name) {
            return $option
        }
    }

    return $null
}

function Get-WtcliCompletionContext {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $root = Get-WtcliCatalog
    $context = [pscustomobject]@{
        Root          = $root
        Catalog       = $root
        Command       = ''
        Pending       = $null
        OperandCount  = 0
        EndOfOptions  = $false
        Used          = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        WindowId      = ''
    }

    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        # EndOffset and the cursor are both absolute; the word under the cursor is not settled yet.
        if ($null -eq $element.Extent -or $element.Extent.EndOffset -ge $CursorPosition) {
            continue
        }

        $token = $element.Extent.Text.Trim().Trim('"').Trim("'")
        if ([string]::IsNullOrEmpty($token)) {
            continue
        }

        if ($null -ne $context.Pending) {
            if ($context.Pending.Long -eq '--window-id') {
                $context.WindowId = $token
            }

            $context.Pending = $null
            continue
        }

        if (-not $context.EndOfOptions -and $token -eq '--') {
            $context.EndOfOptions = $true
            continue
        }

        if (-not $context.EndOfOptions -and $token.Length -gt 1 -and $token.StartsWith('-')) {
            if ($token -match '^(?<name>--[^=]+)=(?<value>.*)$') {
                $option = Find-WtcliOption -Catalog $context.Catalog -Name $Matches.name
                if ($null -ne $option) {
                    [void]$context.Used.Add($option.Long)
                    if ($option.Long -eq '--window-id') {
                        $context.WindowId = $Matches.value
                    }
                }
            }
            elseif ($token.StartsWith('--') -or $token.Length -eq 2) {
                $option = Find-WtcliOption -Catalog $context.Catalog -Name $token
                if ($null -ne $option) {
                    [void]$context.Used.Add($option.Long)
                    if ($option.TakesValue) {
                        $context.Pending = $option
                    }
                }
            }
            else {
                # A short cluster: flags (-Hv) or a short option with its value attached (-w5).
                for ($i = 1; $i -lt $token.Length; $i++) {
                    $option = Find-WtcliOption -Catalog $context.Catalog -Name ('-' + $token[$i])
                    if ($null -eq $option) {
                        break
                    }

                    [void]$context.Used.Add($option.Long)
                    if ($option.TakesValue) {
                        if ($i -eq $token.Length - 1) {
                            $context.Pending = $option
                        }
                        elseif ($option.Long -eq '--window-id') {
                            $context.WindowId = $token.Substring($i + 1).TrimStart('=')
                        }

                        break
                    }
                }
            }

            continue
        }

        if (-not $context.Command) {
            $command = Find-WtcliCommand -RootCatalog $root -Name $token
            if ($null -ne $command) {
                $context.Command = $command.Name
                $context.Catalog = Get-WtcliCatalog -Command $command.Name
                continue
            }
        }

        $context.OperandCount++
    }

    return $context
}

function Get-WtcliCurrentWord {
    # PowerShell hands a quoted word over re-quoted and drops the quote inside an attached
    # --opt='va, so the word is read from the element under the cursor instead.
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$WordToComplete
    )

    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            if ($element -is [System.Management.Automation.Language.ArrayLiteralAst] -or $element -is [System.Management.Automation.Language.ErrorExpressionAst]) {
                return $WordToComplete
            }

            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    return ''
}

function ConvertFrom-WtcliTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by the
    # PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    return [string]$tokens[0].Value
}

function ConvertTo-WtcliQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed, otherwise
    # in the quote the user typed (single by default). PowerShell reads ' and U+2018-U+201B as
    # single quotes and " and U+201C-U+201E as double quotes.
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $QuoteChar) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2013-\u2015\u2018-\u201E]' -and $Value -notmatch '^-') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    return $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-WtcliDirectoryCompletions {
    # CompleteFilename returns each path quoted and wildcard-escaped for PowerShell, so each
    # result is unwrapped by the tokenizer and unescaped, then quoted once in the typed style.
    param(
        [string]$RawWord,
        [string]$Prefix = ''
    )

    $quoteChar = if ($RawWord -match '^[''"\u2018-\u201E]') { $RawWord.Substring(0, 1) } else { '' }
    $value = ConvertFrom-WtcliTypedWord -Value $RawWord
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($item in @([System.Management.Automation.CompletionCompleters]::CompleteFilename($value))) {
        if ([string]$item.ResultType -ne 'ProviderContainer') {
            continue
        }

        $path = [System.Management.Automation.WildcardPattern]::Unescape((ConvertFrom-WtcliTypedWord -Value $item.CompletionText))
        if ($path -notmatch '[\\/]$') {
            $path += [System.IO.Path]::DirectorySeparatorChar
        }

        $listItemText = [System.Management.Automation.WildcardPattern]::Unescape($item.ListItemText)
        $completion = New-WtcliCompletionResult -CompletionText ($Prefix + (ConvertTo-WtcliQuotedValue -Value $path -QuoteChar $quoteChar)) -ResultType 'ProviderContainer' -ToolTip $item.ToolTip -ListItemText $listItemText
        if ($null -ne $completion) {
            [void]$results.Add($completion)
        }
    }

    if ($results.Count -eq 0 -and [string]::IsNullOrEmpty($value)) {
        [void]$results.Add((New-WtcliCompletionResult -CompletionText ($Prefix + '<directory>') -ToolTip 'Starting directory'))
    }

    return @($results.ToArray())
}

function Test-WtcliLiveTerminal {
    # wtcli finds Terminal through WT_COM_CLSID, and every pane has WT_SESSION. List commands use
    # COM activation, so outside a pane a query could start Terminal; the official hook bundles
    # gate on the same two variables.
    return (-not [string]::IsNullOrWhiteSpace($env:WT_COM_CLSID)) -and (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION))
}

function Invoke-WtcliJsonQuery {
    # Runs one read-only `wtcli --json <args>` query with a short timeout. Successful results are
    # cached for $TtlSeconds and failures for 10 seconds, so a dead server costs one Tab, not every Tab.
    param(
        [string[]]$Arguments,
        [string]$Property,
        [int]$TtlSeconds = 5
    )

    if (-not (Test-WtcliLiveTerminal)) {
        return @()
    }

    $cache = Get-WtcliCache -Name 'WtcliQueryCache'
    $key = ($Arguments -join ' ')
    $entry = $cache[$key]
    if ($null -ne $entry) {
        $limit = if ($entry.Ok) { $TtlSeconds } else { 10 }
        if (([DateTime]::UtcNow - $entry.Time).TotalSeconds -lt $limit) {
            return @($entry.Items)
        }
    }

    $items = @()
    $ok = $false
    $result = Invoke-WtcliCapture -Arguments (@('--json') + $Arguments) -TimeoutMs 1500
    if ($null -ne $result -and $result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($result.Output) -and
        (Test-Json -Json $result.Output -ErrorAction Ignore)) {
        $data = ConvertFrom-Json -InputObject $result.Output -AsHashtable -ErrorAction Ignore
        if ($data -is [System.Collections.IDictionary] -and $data.Contains($Property)) {
            $items = @($data[$Property] | Where-Object { $_ -is [System.Collections.IDictionary] })
            $ok = $true
        }
    }

    $cache[$key] = @{ Ok = $ok; Time = [DateTime]::UtcNow; Items = $items }
    return $items
}

function Get-WtcliWindows {
    return @(Invoke-WtcliJsonQuery -Arguments @('list-windows') -Property 'windows')
}

function Get-WtcliTabs {
    param([string]$WindowId)

    $windowIds = if ($WindowId -match '^\d+$') { @($WindowId) } else { @(Get-WtcliWindows | ForEach-Object { [string]$_['window_id'] }) }
    $tabs = New-Object System.Collections.Generic.List[object]
    foreach ($id in $windowIds) {
        foreach ($tab in @(Invoke-WtcliJsonQuery -Arguments @('list-tabs', '-w', $id) -Property 'tabs')) {
            [void]$tabs.Add(@{ Window = $id; Tab = [string]$tab['tab_id']; Title = [string]$tab['title']; Active = [bool]$tab['is_active'] })
        }
    }

    return @($tabs.ToArray())
}

function Get-WtcliPanes {
    # list-panes covers one tab, so every pane takes one query per tab. The walk stops after
    # 2.5 seconds and the whole result is cached for 5 seconds.
    $cache = Get-WtcliCache -Name 'WtcliQueryCache'
    $entry = $cache['#panes']
    if ($null -ne $entry -and ([DateTime]::UtcNow - $entry.Time).TotalSeconds -lt 5) {
        return @($entry.Items)
    }

    $panes = New-Object System.Collections.Generic.List[object]
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($tab in @(Get-WtcliTabs)) {
        if ($timer.ElapsedMilliseconds -gt 2500) {
            break
        }

        foreach ($pane in @(Invoke-WtcliJsonQuery -Arguments @('list-panes', '-w', $tab.Window, '-t', $tab.Tab) -Property 'panes')) {
            $id = [string]$pane['session_id']
            if ($id) {
                [void]$panes.Add(@{ Id = $id; Pid = [string]$pane['pid']; Active = [bool]$pane['is_active']; Window = $tab.Window; Tab = $tab.Tab; Title = $tab.Title })
            }
        }
    }

    $items = @($panes.ToArray())
    $cache['#panes'] = @{ Ok = $true; Time = [DateTime]::UtcNow; Items = $items }
    return $items
}

function Get-WtcliProfiles {
    return @(Invoke-WtcliJsonQuery -Arguments @('list-profiles') -Property 'profiles' -TtlSeconds 30)
}

function Get-WtcliEventTopics {
    param([string]$Kind)

    # agent-hook topics come from the official wt-agent-hooks bundles; the send-event topics from
    # doc/specs/llm-agent-event-integration.md. Terminal passes any topic through.
    $hookTopics = @(
        'agent.session.start', 'agent.session.end', 'agent.session.unbind', 'agent.session.renamed',
        'agent.prompt.submit', 'agent.tool.starting', 'agent.tool.finished', 'agent.tool.failed',
        'agent.stop', 'agent.subagent.stop', 'agent.notification', 'agent.error'
    )
    $specTopics = @(
        'agent.started', 'agent.task.started', 'agent.tool.invoked', 'agent.tool.completed',
        'agent.task.completed', 'agent.idle', 'agent.error'
    )

    switch ($Kind) {
        'hookevent' { return $hookTopics }
        'event' { return @($specTopics + $hookTopics | Select-Object -Unique) }
        default { return @(@('agent.*', 'agent.session.*', 'agent.tool.*', 'agent.task.*') + $specTopics + $hookTopics | Select-Object -Unique) }
    }
}

function Get-WtcliValueKind {
    param(
        [string]$Command,
        [object]$Option
    )

    if (@($Option.Enums).Count -gt 0) {
        return 'enum'
    }

    switch ($Option.Long) {
        '--target' { return 'session' }
        '--pane' { return 'session' }
        '--window-id' { return 'window' }
        '--tab-id' { return 'tab' }
        '--profile' { return 'profile' }
        '--agent-provider' { return 'provider' }
        '--cli-source' { return 'clisource' }
        '--cwd' { return 'directory' }
        '--parent-pid' { return 'pid' }
        '--event' {
            if ($Command -eq 'agent-hook') { return 'hookevent' }
            if ($Command -eq 'listen') { return 'eventfilter' }
            return 'event'
        }
    }

    return 'placeholder'
}

function Get-WtcliPlaceholder {
    param([object]$Option)

    switch ($Option.Long) {
        '--max-lines' { return '<lines>' }
        '--max-chars' { return '<chars>' }
        '--interval' { return '<ms>' }
        '--timeout' { return '<seconds>' }
        '--size' { return '<fraction>' }
        '--command' { return '<command>' }
        '--title' { return '<title>' }
        '--ready-token' { return '<token>' }
    }

    return '<' + $Option.Long.TrimStart('-') + '>'
}

function Get-WtcliValueCandidates {
    # Returns @{ Value; ToolTip; ListItemText } entries for one value slot.
    param(
        [string]$Kind,
        [string]$Command,
        [object]$Option,
        [string]$WindowId
    )

    $items = New-Object System.Collections.Generic.List[object]
    # Live slots fall back to their placeholder only when nothing live was found.
    $placeholder = $null
    switch ($Kind) {
        'enum' {
            foreach ($value in @($Option.Enums)) {
                [void]$items.Add(@{ Value = $value; ToolTip = $Option.Description })
            }
        }
        'session' {
            if (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION)) {
                [void]$items.Add(@{ Value = $env:WT_SESSION; ToolTip = 'This pane ($env:WT_SESSION)' })
            }

            foreach ($pane in @(Get-WtcliPanes)) {
                $state = if ($pane.Active) { ', active' } else { '' }
                [void]$items.Add(@{ Value = $pane.Id; ToolTip = "Window $($pane.Window), tab $($pane.Tab) '$($pane.Title)', pid $($pane.Pid)$state" })
            }

            $placeholder = '<session-guid>'
        }
        'window' {
            foreach ($window in @(Get-WtcliWindows)) {
                $focus = if ($window['is_focused']) { ' (focused)' } else { '' }
                [void]$items.Add(@{ Value = [string]$window['window_id']; ToolTip = "$($window['title'])$focus" })
            }

            $placeholder = '<window-id>'
        }
        'tab' {
            foreach ($tab in @(Get-WtcliTabs -WindowId $WindowId)) {
                $state = if ($tab.Active) { ', active' } else { '' }
                [void]$items.Add(@{ Value = $tab.Tab; ToolTip = "Window $($tab.Window): '$($tab.Title)'$state" })
            }

            $placeholder = '<tab-id>'
        }
        'profile' {
            foreach ($entry in @(Get-WtcliProfiles)) {
                $tip = [string]$entry['id']
                if ($entry['is_default']) { $tip += ', default' }
                if ($entry.Contains('agent_id')) { $tip += ", agent $($entry['agent_id'])" }
                [void]$items.Add(@{ Value = [string]$entry['name']; ToolTip = $tip })
                [void]$items.Add(@{ Value = [string]$entry['id']; ToolTip = [string]$entry['name']; ListItemText = "$($entry['id']) ($($entry['name']))" })
            }

            $placeholder = '<profile>'
        }
        'provider' {
            # BuiltinNativeProfileAgents in src/cascadia/inc/AgentRegistry.h, plus live agent profiles.
            $providers = @('copilot', 'claude', 'codex', 'gemini', 'opencode', 'antigravity') +
                @(Get-WtcliProfiles | Where-Object { $_.Contains('agent_id') } | ForEach-Object { [string]$_['agent_id'] })
            foreach ($value in @($providers | Select-Object -Unique)) {
                [void]$items.Add(@{ Value = $value; ToolTip = $Option.Description })
            }

            [void]$items.Add(@{ Value = 'custom:<name>'; ToolTip = 'A custom agent provider' })
        }
        'clisource' {
            foreach ($value in @('copilot', 'claude', 'codex', 'gemini', 'opencode', 'antigravity')) {
                [void]$items.Add(@{ Value = $value; ToolTip = $Option.Description })
            }
        }
        { $_ -in @('hookevent', 'event', 'eventfilter') } {
            foreach ($value in @(Get-WtcliEventTopics -Kind $Kind)) {
                [void]$items.Add(@{ Value = $value; ToolTip = $Option.Description })
            }

            if ($Kind -ne 'hookevent') {
                [void]$items.Add(@{ Value = '<event-type>'; ToolTip = 'Any event type; Terminal passes unknown types through' })
            }
        }
        'pid' {
            [void]$items.Add(@{ Value = [string]$PID; ToolTip = 'This PowerShell process' })
            [void]$items.Add(@{ Value = '<pid>'; ToolTip = $Option.Description })
        }
        default {
            [void]$items.Add(@{ Value = (Get-WtcliPlaceholder -Option $Option); ToolTip = $Option.Description })
        }
    }

    if ($null -ne $placeholder -and $items.Count -eq 0) {
        [void]$items.Add(@{ Value = $placeholder; ToolTip = $Option.Description })
    }

    # new-tab -w 0 targets the most recent window whether or not live ids are known.
    if ($Kind -eq 'window' -and $Command -eq 'new-tab') {
        $items.Insert(0, @{ Value = '0'; ToolTip = 'The most recent window' })
    }

    return @($items.ToArray())
}

function Add-WtcliValueResults {
    param(
        [System.Collections.Generic.List[object]]$Results,
        [object[]]$Candidates,
        [string]$RawWord,
        [string]$Prefix,
        [bool]$IgnoreCase
    )

    $quoteChar = if ($RawWord -match '^[''"\u2018-\u201E]') { $RawWord.Substring(0, 1) } else { '' }
    $typed = ConvertFrom-WtcliTypedWord -Value $RawWord
    $comparison = if ($IgnoreCase) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($candidate in @($Candidates)) {
        $value = [string]$candidate.Value
        if ([string]::IsNullOrEmpty($value) -or -not $value.StartsWith($typed, $comparison) -or -not $seen.Add($value)) {
            continue
        }

        # Placeholders are typed over, never accepted as values; they are not quoted.
        $text = if ($value -match '<[^<>\s]+>') { $value } else { ConvertTo-WtcliQuotedValue -Value $value -QuoteChar $quoteChar }
        $listItemText = if ($candidate.Contains('ListItemText')) { [string]$candidate.ListItemText } else { $value }
        $item = New-WtcliCompletionResult -CompletionText ($Prefix + $text) -ToolTip ([string]$candidate.ToolTip) -ListItemText $listItemText
        if ($null -ne $item) {
            [void]$Results.Add($item)
        }
    }
}

function Get-WtcliOptionValueCompletions {
    param(
        [object]$Context,
        [object]$Option,
        [string]$RawWord,
        [string]$Prefix = ''
    )

    $kind = Get-WtcliValueKind -Command $Context.Command -Option $Option
    if ($kind -eq 'directory') {
        return @(Get-WtcliDirectoryCompletions -RawWord $RawWord -Prefix $Prefix)
    }

    $results = New-Object System.Collections.Generic.List[object]
    $candidates = @(Get-WtcliValueCandidates -Kind $kind -Command $Context.Command -Option $Option -WindowId $Context.WindowId)
    Add-WtcliValueResults -Results $results -Candidates $candidates -RawWord $RawWord -Prefix $Prefix -IgnoreCase ($kind -in @('session', 'profile'))
    return @($results.ToArray())
}

function Get-WtcliOptionCompletions {
    param(
        [object]$Context,
        [string]$Word
    )

    $results = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $shortWord = $Word -cmatch '^-[A-Za-z0-9]$'
    foreach ($option in @($Context.Catalog.Options)) {
        $matched = @($option.Names | Where-Object { $_.StartsWith($Word, [System.StringComparison]::Ordinal) }).Count -gt 0
        if (-not $matched) {
            continue
        }

        foreach ($name in @($option.Names)) {
            # A typed short option also offers its long spelling: -t lists -t and --target.
            if (($name.StartsWith($Word, [System.StringComparison]::Ordinal) -or ($shortWord -and $name.StartsWith('--'))) -and $seen.Add($name)) {
                $item = New-WtcliCompletionResult -CompletionText $name -ResultType 'ParameterName' -ToolTip $option.Description
                if ($null -ne $item) {
                    [void]$results.Add($item)
                }
            }
        }
    }

    return @($results.ToArray())
}

function Get-WtcliPositionalCompletions {
    param(
        [object]$Context,
        [string]$RawWord
    )

    $positionals = @($Context.Catalog.Positionals)
    $positional = $null
    if ($Context.OperandCount -lt $positionals.Count) {
        $positional = $positionals[$Context.OperandCount]
    }
    elseif ($positionals.Count -gt 0 -and $positionals[-1].Repeating) {
        $positional = $positionals[-1]
    }

    if ($null -eq $positional -or ($positional.Name -eq 'json' -and $Context.Used.Contains('--stdin'))) {
        return @()
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    if ($positional.Name -eq 'keys' -and -not $Context.Used.Contains('--raw')) {
        # TranslateKeys in src/tools/wtcli/wtcli_functions.h; anything else is sent as text.
        $keys = [ordered]@{
            'Enter' = 'Carriage return'; 'Space' = 'Space'; 'Tab' = 'Tab'; 'Escape' = 'Escape (also Esc)'
            'BSpace' = 'Backspace'; 'C-c' = 'Ctrl+C'; 'C-d' = 'Ctrl+D'; 'C-z' = 'Ctrl+Z'; 'C-l' = 'Ctrl+L'
        }
        foreach ($key in $keys.Keys) {
            [void]$candidates.Add(@{ Value = $key; ToolTip = $keys[$key] })
        }

        if ($RawWord.StartsWith('C-', [System.StringComparison]::Ordinal)) {
            foreach ($letter in [char[]]'abcdefghijklmnopqrstuvwxyz') {
                [void]$candidates.Add(@{ Value = "C-$letter"; ToolTip = "Ctrl+$([char]::ToUpperInvariant($letter))" })
            }
        }
    }

    $placeholder = switch ($positional.Name) { 'keys' { '<text>' } 'json' { '<json>' } default { "<$($positional.Name)>" } }
    [void]$candidates.Add(@{ Value = $placeholder; ToolTip = $positional.Description })

    $results = New-Object System.Collections.Generic.List[object]
    Add-WtcliValueResults -Results $results -Candidates @($candidates.ToArray()) -RawWord $RawWord -Prefix '' -IgnoreCase $false
    return @($results.ToArray())
}

function Complete-Wtcli {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $context = Get-WtcliCompletionContext -CommandAst $commandAst -CursorPosition $cursorPosition
    $word = if ($null -eq $wordToComplete) { '' } else { [string]$wordToComplete }
    $rawWord = Get-WtcliCurrentWord -CommandAst $commandAst -CursorPosition $cursorPosition -WordToComplete $word
    $optionWord = -not $context.EndOfOptions -and $word.StartsWith('-')

    if (-not $context.EndOfOptions -and $word -match '^(?<name>--[A-Za-z0-9][A-Za-z0-9-]*)=') {
        $option = Find-WtcliOption -Catalog $context.Catalog -Name $Matches.name
        if ($null -eq $option -or -not $option.TakesValue) {
            return @()
        }

        $prefix = $Matches.name + '='
        $rawValue = if ($rawWord.StartsWith($prefix, [System.StringComparison]::Ordinal)) { $rawWord.Substring($prefix.Length) } else { $word.Substring($prefix.Length) }
        return @(Get-WtcliOptionValueCompletions -Context $context -Option $option -RawWord $rawValue -Prefix $prefix)
    }

    if ($null -ne $context.Pending -and -not $optionWord) {
        return @(Get-WtcliOptionValueCompletions -Context $context -Option $context.Pending -RawWord $rawWord)
    }

    if ($optionWord) {
        return @(Get-WtcliOptionCompletions -Context $context -Word $word)
    }

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $context.Command) {
        foreach ($command in @($context.Root.Commands)) {
            foreach ($name in @(@($command.Name) + @($command.Aliases))) {
                if ($name.StartsWith($word, [System.StringComparison]::Ordinal)) {
                    $tip = if ($name -ceq $command.Name) { $command.Description } else { "Alias for $($command.Name): $($command.Description)" }
                    [void]$results.Add((New-WtcliCompletionResult -CompletionText $name -ToolTip $tip))
                }
            }
        }
    }
    else {
        foreach ($item in @(Get-WtcliPositionalCompletions -Context $context -RawWord $rawWord)) {
            [void]$results.Add($item)
        }
    }

    # An empty word also lists the options, so a slot without values never falls back to file names.
    if ([string]::IsNullOrEmpty($word) -and -not $context.EndOfOptions -and ($context.OperandCount -eq 0 -or $results.Count -eq 0)) {
        foreach ($item in @(Get-WtcliOptionCompletions -Context $context -Word '-')) {
            [void]$results.Add($item)
        }
    }

    return @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('wtcli', 'wtcli.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Wtcli -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
