<#
.SYNOPSIS
Registers PowerShell tab completion for the local `codex` CLI.

.DESCRIPTION
This completer is a thin, importer-safe wrapper around the PowerShell
completion script emitted by `codex completion powershell`.

The generated completion script is loaded lazily on first completion request,
its built-in self-registration is rewritten into an invokable script block,
and that script block is cached for the rest of the session.

This script registers completion for `codex`, `codex.cmd`, and `codex.ps1`
because all three launcher names can be relevant on Windows.
#>

Set-StrictMode -Version Latest

function Get-CodexCompletionExecutablePath {
    $pathProbeComplete = Get-Variable -Name CodexCompletionExecutablePathProbed -Scope Script -ErrorAction Ignore
    if ($null -ne $pathProbeComplete -and $pathProbeComplete.Value) {
        $cachedPath = Get-Variable -Name CodexCompletionExecutablePath -Scope Script -ErrorAction Ignore
        if ($null -ne $cachedPath) {
            return $cachedPath.Value
        }

        return $null
    }

    $script:CodexCompletionExecutablePathProbed = $true
    $script:CodexCompletionExecutablePath = $null

    foreach ($candidate in @(
            @{ Name = 'codex.cmd'; CommandType = 'Application' }
            @{ Name = 'codex'; CommandType = 'Application' }
            @{ Name = 'codex.ps1'; CommandType = 'ExternalScript' }
        )) {
        # A launcher name that is not installed is an expected miss; SilentlyContinue would still record it in $Error.
        $command = Get-Command -Name $candidate.Name -CommandType $candidate.CommandType -ErrorAction Ignore |
            Select-Object -First 1

        if ($null -eq $command) {
            continue
        }

        $script:CodexCompletionExecutablePath = if ($command.Source) { $command.Source } else { $command.Path }
        break
    }

    $script:CodexCompletionExecutablePath
}

function Get-CodexGeneratedCompletionScript {
    $codexExecutablePath = Get-CodexCompletionExecutablePath
    if ([string]::IsNullOrWhiteSpace($codexExecutablePath)) {
        return
    }

    try {
        $completionScript = & $codexExecutablePath completion powershell 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String
    } catch {
        return
    }

    if ([string]::IsNullOrWhiteSpace($completionScript)) {
        return
    }

    $completionScript
}

function ConvertTo-CodexCompletionInvokerSource {
    param([string]$CompletionScript)

    if ([string]::IsNullOrWhiteSpace($CompletionScript)) {
        return
    }

    $registerPattern = '(?m)^\s*Register-ArgumentCompleter\s+-Native\s+-CommandName\s+[''"]codex[''"]\s+-ScriptBlock\s+\{\s*$'
    $rewrittenScript = [regex]::Replace(
        $CompletionScript,
        $registerPattern,
        { param($match) '$__codexCompleterBlock = {' },
        1
    )

    if ($rewrittenScript -eq $CompletionScript) {
        return
    }

@"
$rewrittenScript

& `$__codexCompleterBlock @args
"@
}

function Get-CodexCompletionInvoker {
    $cachedInvoker = Get-Variable -Name CodexCompletionInvoker -Scope Script -ErrorAction Ignore
    if ($null -ne $cachedInvoker) {
        return $cachedInvoker.Value
    }

    $completionScript = Get-CodexGeneratedCompletionScript
    if ([string]::IsNullOrWhiteSpace($completionScript)) {
        return
    }

    $completionInvokerSource = ConvertTo-CodexCompletionInvokerSource -CompletionScript $completionScript
    if ([string]::IsNullOrWhiteSpace($completionInvokerSource)) {
        return
    }

    try {
        $script:CodexCompletionInvoker = [scriptblock]::Create($completionInvokerSource)
        return $script:CodexCompletionInvoker
    } catch {
        return
    }
}

function Get-CodexHomePath {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return $env:CODEX_HOME
    }

    Join-Path -Path $HOME -ChildPath '.codex'
}

function Get-CodexStateFileValue {
    <#
    .SYNOPSIS
    Parses a file under $CODEX_HOME once and reuses the result until the
    file's size or write time changes.
    #>
    param(
        [string]$Kind,
        [string]$Path,
        [scriptblock]$Parser
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Ignore
    if ($null -eq $item -or $item.PSIsContainer) {
        return
    }

    if ($null -eq (Get-Variable -Name CodexStateFileCache -Scope Script -ErrorAction Ignore)) {
        $script:CodexStateFileCache = @{}
    }

    $cacheKey = $Kind + '|' + $item.FullName
    $stamp = '{0}|{1}' -f $item.LastWriteTimeUtc.Ticks, $item.Length
    $entry = $script:CodexStateFileCache[$cacheKey]
    if ($null -ne $entry -and $entry.Stamp -eq $stamp) {
        return $entry.Values
    }

    $values = @(& $Parser $item.FullName)
    $script:CodexStateFileCache[$cacheKey] = @{ Stamp = $stamp; Values = $values }
    $values
}

function ConvertFrom-CodexJson {
    param([string]$Json)

    # A malformed or half-written state file is an expected miss while completing.
    # Reject it up front: a caught parse exception is still recorded in $Error, and
    # under the managed import that is not the $Error this function could clean up.
    if ([string]::IsNullOrWhiteSpace($Json) -or -not (Test-Json -Json $Json -ErrorAction Ignore)) {
        return
    }

    $Json | ConvertFrom-Json -AsHashtable
}

function Get-CodexSessionValue {
    $indexPath = Join-Path -Path (Get-CodexHomePath) -ChildPath 'session_index.jsonl'
    Get-CodexStateFileValue -Kind 'session' -Path $indexPath -Parser {
        param($Path)

        $lines = @(Get-Content -LiteralPath $Path -Tail 500 -ErrorAction Ignore | Where-Object { $_.Trim() })
        if ($lines.Count -eq 0) {
            return
        }

        # Parse the tail as one array; a line codex is still appending breaks that, so
        # fall back to parsing line by line and dropping the bad ones.
        $records = @(ConvertFrom-CodexJson -Json ('[' + ($lines -join ',') + ']'))
        if ($records.Count -eq 0) {
            $records = @(foreach ($line in $lines) { ConvertFrom-CodexJson -Json $line })
        }

        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        # The index is append-only: walk it newest first so a renamed thread keeps its latest name.
        for ($index = $records.Count - 1; $index -ge 0; $index--) {
            $record = $records[$index]
            if ($record -isnot [System.Collections.IDictionary]) {
                continue
            }

            $id = [string]$record['id']
            if ([string]::IsNullOrWhiteSpace($id) -or -not $seen.Add($id)) {
                continue
            }

            $threadName = ([string]$record['thread_name'] -replace '\s+', ' ').Trim()
            $label = if ($threadName) { "$threadName ($id)" } else { $id }
            [pscustomobject]@{
                Value    = $id
                Alias    = $threadName
                ListItem = $label
                ToolTip  = ('{0} updated {1}' -f $label, [string]$record['updated_at'])
            }
        }
    }
}

function Get-CodexModelValue {
    $cachePath = Join-Path -Path (Get-CodexHomePath) -ChildPath 'models_cache.json'
    Get-CodexStateFileValue -Kind 'model' -Path $cachePath -Parser {
        param($Path)

        $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Ignore
        if (-not $json) {
            return
        }

        $document = ConvertFrom-CodexJson -Json $json
        if ($document -isnot [System.Collections.IDictionary] -or $null -eq $document['models']) {
            return
        }

        foreach ($model in @($document['models'])) {
            if ($model -isnot [System.Collections.IDictionary] -or [string]::IsNullOrWhiteSpace([string]$model['slug'])) {
                continue
            }

            $slug = [string]$model['slug']
            $tip = @([string]$model['display_name'], [string]$model['description']) | Where-Object { $_ }
            [pscustomobject]@{
                Value    = $slug
                Alias    = ''
                ListItem = $slug
                ToolTip  = if ($tip) { ($tip -join ' - ') } else { $slug }
            }
        }
    }
}

function Get-CodexConfigTableName {
    <#
    .SYNOPSIS
    Names of the direct child tables of [plugins] or [mcp_servers] in
    $CODEX_HOME/config.toml. Reads table headers only, never their values.
    #>
    param([ValidateSet('plugins', 'mcp_servers')][string]$Table)

    $configPath = Join-Path -Path (Get-CodexHomePath) -ChildPath 'config.toml'
    Get-CodexStateFileValue -Kind $Table -Path $configPath -Parser {
        param($Path)

        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Ignore
        if (-not $text) {
            return
        }

        $pattern = '(?m)^[ \t]*\[[ \t]*' + $Table + '[ \t]*\.[ \t]*(?:"(?<name>[^"\r\n]+)"|''(?<name>[^''\r\n]+)''|(?<name>[A-Za-z0-9_-]+))[ \t]*\][ \t]*(?:#[^\r\n]*)?\r?$'
        $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($match in [regex]::Matches($text, $pattern)) {
            $name = $match.Groups['name'].Value
            if ($names.Add($name)) {
                [pscustomobject]@{ Value = $name; Alias = ''; ListItem = $name; ToolTip = $name }
            }
        }
    }
}

function Get-CodexProfileValue {
    # -p/--profile layers $CODEX_HOME/<name>.config.toml on top of config.toml.
    foreach ($file in @(Get-ChildItem -LiteralPath (Get-CodexHomePath) -Filter '*.config.toml' -File -Force -ErrorAction Ignore)) {
        if ($file.Name.Length -le '.config.toml'.Length -or -not $file.Name.EndsWith('.config.toml', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $name = $file.Name.Substring(0, $file.Name.Length - '.config.toml'.Length)
        [pscustomobject]@{ Value = $name; Alias = ''; ListItem = $name; ToolTip = $file.FullName }
    }
}

function Get-CodexFeatureValue {
    <#
    .SYNOPSIS
    Feature keys from the read-only 'codex features list', run once per
    session per launcher (bounded, stdin closed) and negatively cached.
    #>
    $codexExecutablePath = Get-CodexCompletionExecutablePath
    if ([string]::IsNullOrWhiteSpace($codexExecutablePath)) {
        return
    }

    $cached = Get-Variable -Name CodexFeatureCache -Scope Script -ErrorAction Ignore
    if ($null -ne $cached -and $cached.Value.Path -eq $codexExecutablePath) {
        return $cached.Value.Values
    }

    $output = ''
    if (-not $codexExecutablePath.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
        $errorCountBefore = $Error.Count
        $process = [System.Diagnostics.Process]::new()
        try {
            $info = [System.Diagnostics.ProcessStartInfo]::new($codexExecutablePath)
            $info.UseShellExecute = $false
            $info.CreateNoWindow = $true
            $info.RedirectStandardInput = $true
            $info.RedirectStandardOutput = $true
            $info.RedirectStandardError = $true
            $info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $info.Environment['NO_COLOR'] = '1'
            [void]$info.ArgumentList.Add('features')
            [void]$info.ArgumentList.Add('list')
            $process.StartInfo = $info
            [void]$process.Start()
            $process.StandardInput.Close()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            [void]$process.StandardError.ReadToEndAsync()
            if ($process.WaitForExit(5000)) {
                $output = $stdout.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', ''
            } else {
                $process.Kill($true)
            }
        } catch {
            $output = ''
        } finally {
            $process.Dispose()
            # A launcher that fails to start is a negative-cache miss, not a fault to leave in $Error.
            while ($Error.Count -gt $errorCountBefore) {
                $Error.RemoveAt(0)
            }
        }
    }

    $values = @(foreach ($line in ($output -split '\r?\n')) {
        # '<key>  <stage>  <true|false>'; removed keys are accepted but do nothing, so skip them.
        if ($line -notmatch '^(?<name>[A-Za-z0-9_.-]+)\s+(?<stage>\S.*?)\s+(?<state>true|false)\s*$' -or $Matches.stage -eq 'removed') {
            continue
        }

        $state = if ($Matches.state -eq 'true') { 'enabled' } else { 'disabled' }
        [pscustomobject]@{ Value = $Matches.name; Alias = ''; ListItem = $Matches.name; ToolTip = "$($Matches.stage), currently $state" }
    })

    $script:CodexFeatureCache = @{ Path = $codexExecutablePath; Values = $values }
    $values
}

function ConvertTo-CodexQuotedValue {
    param(
        [string]$Value,
        [string]$QuoteCharacter
    )

    if ($QuoteCharacter -eq '"') {
        return '"' + ($Value -replace '([`"$])', '`$1') + '"'
    }

    if ($QuoteCharacter -eq "'" -or $Value -match '[\s{}();,|&<>''"`$]|^[@#]') {
        return "'" + $Value.Replace("'", "''") + "'"
    }

    $Value
}

function Get-CodexStateCandidate {
    param([ValidateSet('session', 'model', 'profile', 'feature', 'plugin', 'mcp')][string]$Slot)

    switch ($Slot) {
        'session' { Get-CodexSessionValue }
        'model' { Get-CodexModelValue }
        'profile' { Get-CodexProfileValue }
        'feature' { Get-CodexFeatureValue }
        'plugin' { Get-CodexConfigTableName -Table 'plugins' }
        'mcp' { Get-CodexConfigTableName -Table 'mcp_servers' }
    }
}

function ConvertTo-CodexStateCompletion {
    param(
        [object[]]$Candidate,
        [string]$ValueWord,
        [string]$ValuePrefix
    )

    $quoteCharacter = ''
    if ($ValueWord.Length -gt 0 -and ($ValueWord[0] -eq "'" -or $ValueWord[0] -eq '"')) {
        $quoteCharacter = [string]$ValueWord[0]
        # PowerShell hands an unterminated quoted word over with its closing quote added.
        $ValueWord = $ValueWord.Substring(1)
        if ($ValueWord.EndsWith($quoteCharacter)) {
            $ValueWord = $ValueWord.Substring(0, $ValueWord.Length - 1)
        }
    }

    foreach ($item in $Candidate) {
        if ($null -eq $item) {
            continue
        }

        if (-not $item.Value.StartsWith($ValueWord, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not ($item.Alias -and $item.Alias.StartsWith($ValueWord, [System.StringComparison]::OrdinalIgnoreCase))) {
            continue
        }

        $completionText = $ValuePrefix + (ConvertTo-CodexQuotedValue -Value $item.Value -QuoteCharacter $quoteCharacter)
        [System.Management.Automation.CompletionResult]::new($completionText, $item.ListItem, 'ParameterValue', $item.ToolTip)
    }
}

function Get-CodexValueCompletion {
    <#
    .SYNOPSIS
    Value overlay for slots the clap-generated script leaves empty: closed
    enum options, directory options, the 'completion <SHELL>' positional, and
    values read from local codex state (sessions, models, profiles, plugins,
    MCP servers, features). $Handled is set when a state-backed slot owns the
    word, so the caller does not fall back to the generated option list.
    #>
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [ref]$Handled
    )

    $enumValues = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::Ordinal)
    $enumValues['-s'] = @('read-only', 'workspace-write', 'danger-full-access')
    $enumValues['--sandbox'] = $enumValues['-s']
    $enumValues['-a'] = @('on-request', 'never')
    $enumValues['--ask-for-approval'] = $enumValues['-a']
    $enumValues['--local-provider'] = @('lmstudio', 'ollama')
    $enumValues['--color'] = @('always', 'never', 'auto')

    $directoryOptions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($name in @('-C', '--cd', '--add-dir')) { [void]$directoryOptions.Add($name) }

    $stateOptions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $stateOptions['-m'] = 'model'
    $stateOptions['--model'] = 'model'
    $stateOptions['-p'] = 'profile'
    $stateOptions['--profile'] = 'profile'
    $stateOptions['--enable'] = 'feature'
    $stateOptions['--disable'] = 'feature'

    $statePositionals = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($sessionNode in @('resume', 'fork', 'archive', 'delete', 'unarchive', 'exec;resume', 'exec;fork', 'e;resume', 'e;fork')) {
        $statePositionals['codex;' + $sessionNode] = 'session'
    }
    $statePositionals['codex;plugin;remove'] = 'plugin'
    foreach ($mcpNode in @('get', 'remove', 'login', 'logout')) {
        $statePositionals['codex;mcp;' + $mcpNode] = 'mcp'
    }
    $statePositionals['codex;features;enable'] = 'feature'
    $statePositionals['codex;features;disable'] = 'feature'

    $committed = @(
        $CommandAst.CommandElements |
            Select-Object -Skip 1 |
            Where-Object { $_.Extent.EndOffset -lt $CursorPosition } |
            ForEach-Object { $_.Extent.Text }
    )
    $previousToken = if ($committed.Count -gt 0) { $committed[-1] } else { '' }
    $node = 'codex'
    foreach ($token in $committed) {
        if ($token.StartsWith('-')) {
            break
        }

        $node += ';' + $token
    }

    $optionName = $null
    $valuePrefix = ''
    $valueWord = $WordToComplete
    if ($WordToComplete -match '^(?<option>--?[A-Za-z][A-Za-z0-9-]*)=(?<value>.*)$') {
        $optionName = $Matches.option
        $valuePrefix = $optionName + '='
        $valueWord = $Matches.value
    } elseif ($previousToken.StartsWith('-')) {
        $optionName = $previousToken
    }

    if ($optionName) {
        if ($enumValues.ContainsKey($optionName)) {
            return @(foreach ($value in $enumValues[$optionName]) {
                if ($value.StartsWith($valueWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [System.Management.Automation.CompletionResult]::new($valuePrefix + $value, $value, 'ParameterValue', $value)
                }
            })
        }

        if ($directoryOptions.Contains($optionName)) {
            return @(foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($valueWord)) {
                if ($item.ResultType -ne [System.Management.Automation.CompletionResultType]::ProviderContainer) {
                    continue
                }

                if ($valuePrefix) {
                    [System.Management.Automation.CompletionResult]::new($valuePrefix + $item.CompletionText, $item.ListItemText, $item.ResultType, $item.ToolTip)
                } else {
                    $item
                }
            })
        }

        $stateSlot = $null
        if ($stateOptions.ContainsKey($optionName)) {
            $stateSlot = $stateOptions[$optionName]
        } elseif ($optionName -ceq '--thread' -and $node -eq 'codex;queue') {
            $stateSlot = 'session'
        }

        if ($stateSlot -and -not $valueWord.StartsWith('-')) {
            $Handled.Value = $true
            return @(ConvertTo-CodexStateCompletion -Candidate @(Get-CodexStateCandidate -Slot $stateSlot) -ValueWord $valueWord -ValuePrefix $valuePrefix)
        }

        return @()
    }

    if ($statePositionals.ContainsKey($node) -and -not $WordToComplete.StartsWith('-')) {
        $Handled.Value = $true
        return @(ConvertTo-CodexStateCompletion -Candidate @(Get-CodexStateCandidate -Slot $statePositionals[$node]) -ValueWord $WordToComplete -ValuePrefix '')
    }

    if ($node -eq 'codex;completion' -and -not $WordToComplete.StartsWith('-')) {
        return @(foreach ($shell in @('bash', 'elvish', 'fish', 'powershell', 'zsh')) {
            if ($shell.StartsWith($WordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                [System.Management.Automation.CompletionResult]::new($shell, $shell, 'ParameterValue', "Generate $shell completions")
            }
        })
    }

    @()
}

function Invoke-CodexCompletion {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $handled = $false
    $valueResults = @(Get-CodexValueCompletion -WordToComplete $WordToComplete -CommandAst $CommandAst -CursorPosition $CursorPosition -Handled ([ref]$handled))
    if ($handled -or $valueResults.Count -gt 0) {
        $valueResults
        return
    }

    $completionInvoker = Get-CodexCompletionInvoker
    if ($null -eq $completionInvoker) {
        return
    }

    & $completionInvoker $WordToComplete $CommandAst $CursorPosition
}

Register-ArgumentCompleter -Native -CommandName @('codex', 'codex.cmd', 'codex.ps1') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-CodexCompletion -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
