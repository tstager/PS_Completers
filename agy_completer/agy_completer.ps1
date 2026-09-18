# Installed-help-driven completion for the Antigravity CLI.
Set-StrictMode -Version 2.0

function Get-AgyCompletionCatalog {
    param([string]$Context = '')
    if (-not (Get-Variable -Name AgyCompletionCatalogs -Scope Script -ErrorAction Ignore)) {
        $script:AgyCompletionCatalogs = @{}
    }
    if ($script:AgyCompletionCatalogs.ContainsKey($Context)) { return $script:AgyCompletionCatalogs[$Context] }
    $options = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $commands = [ordered]@{}
    $helpText = ''
    $exe = Get-Command agy.exe -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if ($null -ne $exe) {
        # Only known help entry points are executable: plugin verbs treat --help as data.
        $arguments = @('--help')
        if ($Context -match '^mcp (add|remove|list|enable|disable)$') { $arguments = @('mcp', $Matches[1], '--help') }
        elseif ($Context) { $arguments = @('help', ($Context -split ' ')[0]) }
        $process = [System.Diagnostics.Process]::new()
        try {
            $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($exe.Source)
            $process.StartInfo.UseShellExecute = $false
            $process.StartInfo.CreateNoWindow = $true
            $process.StartInfo.RedirectStandardInput = $true
            $process.StartInfo.RedirectStandardOutput = $true
            $process.StartInfo.RedirectStandardError = $true
            foreach ($argument in $arguments) { [void]$process.StartInfo.ArgumentList.Add($argument) }
            [void]$process.Start()
            $process.StandardInput.Close()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if ($process.WaitForExit(2000)) { $helpText = ($stdout.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '') + "`n" + ($stderr.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '') }
            else { $process.Kill($true) }
        } catch { $helpText = '' } finally { $process.Dispose() }
    }
    $section = ''
    foreach ($line in ($helpText -split '\r?\n')) {
        if ($line -match '^(Available subcommands|Commands):') { $section = 'commands'; continue }
        if ($line -match '^\S') { $section = '' }
        if ($line -match '^\s+(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|=|\[|$))(?:[^\s]*)(?:\s+\S+)?\s{2,}(.+)$') { $options[$Matches[1]] = $Matches[3].Trim(); continue }
        if ($section -eq 'commands' -and $line -match '^\s+([a-z][a-z0-9-]*)(?: [^\r\n]*?)?\s{2,}(.+)$') { $commands[$Matches[1]] = $Matches[2].Trim() }
    }
    if (-not $helpText.Trim()) {
        $options['--help'] = 'Show help'
        if (-not $Context) { foreach ($name in @('agent','agents','changelog','help','install','mcp','mic-serve','models','plugin','plugins','update')) { $commands[$name] = "Show help for $name" } }
    }
    $catalog = @{ Options = $options; Commands = $commands }
    $script:AgyCompletionCatalogs[$Context] = $catalog
    return $catalog
}

function Get-AgyValueKind {
    param([string]$Context, [string]$Option)
    $catalog = Get-AgyCompletionCatalog $Context
    if ($catalog.Options.ContainsKey($Option)) {
        $description = $catalog.Options[$Option]
        if ($description -match '\(([a-z][a-z0-9-]*(?:\s*[,|]\s*[a-z][a-z0-9-]*)+)\)') {
            return (($Matches[1] -split '\s*[,|]\s*') -join '|')
        }
        if ($description -match "Server type: '([^']+)' or '([^']+)'") { return $Matches[1] + '|' + $Matches[2] }
    }
    if (-not $Context) {
        switch -CaseSensitive ($Option) {
            '--add-dir' { return 'directory' }
            '--log-file' { return 'file' }
            '--json-schema' { return 'schema' }
            '--effort' { return 'low|medium|high' }
            '--input-format' { return 'text|stream-json' }
            '--output-format' { return 'text|json|stream-json' }
            '--mode' { return 'accept-edits|plan' }
            '--print-timeout' { return '<duration>' }
            '--agent' { return '<agent>' }
            '--model' { return '<model>' }
            '--conversation' { return '<conversation-id>' }
            '--project' { return '<project-id-or-name>' }
            { $_ -cin @('-p','--print','--prompt','-i','--prompt-interactive') } { return '<prompt>' }
        }
    }
    if ($Context -eq 'install' -and $Option -ceq '--dir') { return 'directory' }
    if ($Context -eq 'mic-serve' -and $Option -ceq '--addr') { return '<host:port>' }
    if ($Context -eq 'mcp add') {
        switch -CaseSensitive ($Option) {
            { $_ -cin @('-t','--type') } { return 'stdio|http' }
            { $_ -cin @('-e','--env') } { return '<KEY=value>' }
            { $_ -cin @('-H','--header') } { return '<Key: Value>' }
        }
    }
    return ''
}

function New-AgyCompletion {
    param([string]$Text, [string]$Description, [string]$Type = 'ParameterValue')
    $quoted = $Text
    if ($Text -match '[\s''"`$;|&(){}<>#@]') { $quoted = "'" + $Text.Replace("'", "''") + "'" }
    [System.Management.Automation.CompletionResult]::new($quoted, $Text, $Type, $Description)
}

function Get-AgyValueCompletion {
    param([string]$Kind, [string]$Word, [string]$Prefix = '')
    $Word = $Word.Trim("'", '"')
    if ($Kind -eq 'schema') {
        if (-not $Word -or $Word.StartsWith('{')) { New-AgyCompletion ($Prefix + $(if ($Word) { $Word } else { '<json-schema>' })) 'Enter a JSON schema string or local schema file' }
        if ($Word.StartsWith('{')) { return }
        $Kind = 'file'
    }
    if ($Kind -in @('file','directory')) {
        if ($Word -match '^(?:\\\\|//)' -or $Word -match '^[^:]+::') {
            New-AgyCompletion ($Prefix + $Word) 'Enter a path; remote paths are not enumerated'
            return
        }
        $parent = '.'; $leaf = $Word
        if ($Word -match '[/\\]$') { $parent = $Word; $leaf = '' }
        elseif ($Word -match '[/\\]') { $parent = Split-Path -Path $Word -Parent; $leaf = Split-Path -Path $Word -Leaf }
        $found = $false
        if (Test-Path -LiteralPath $parent -PathType Container) {
            foreach ($entry in (Get-ChildItem -LiteralPath $parent -Force -ErrorAction Ignore)) {
                if ($Kind -eq 'directory' -and -not $entry.PSIsContainer) { continue }
                if (-not $entry.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $path = if ($parent -eq '.') { $entry.Name } else { Join-Path $parent $entry.Name }
                if ($entry.PSIsContainer) { $path += [System.IO.Path]::DirectorySeparatorChar }
                New-AgyCompletion ($Prefix + $path) $entry.FullName
                $found = $true
            }
        }
        if (-not $found) { New-AgyCompletion ($Prefix + $(if ($Word) { $Word } else { '<path>' })) 'Enter a local path' }
        return
    }
    if ($Kind.StartsWith('<')) { New-AgyCompletion ($Prefix + $(if ($Word) { $Word } else { $Kind })) "Enter $Kind"; return }
    $found = $false
    foreach ($value in ($Kind -split '\|')) {
        if ($value.StartsWith($Word, [System.StringComparison]::Ordinal)) { New-AgyCompletion ($Prefix + $value) $value; $found = $true }
    }
    if (-not $found) { New-AgyCompletion ($Prefix + $Word) "Expected: $Kind" }
}

function Get-AgyCompletion {
    param([string]$Word, [System.Management.Automation.Language.CommandAst]$Ast, [int]$Cursor)
    $tokens = @()
    foreach ($element in ($Ast.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.StartOffset -ge $Cursor) { break }
        if ($element.Extent.EndOffset -ge $Cursor -and $Word) { break }
        $text = $element.Extent.Text
        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $text = $element.Value }
        $tokens += $text
    }
    $context = ''; $pending = ''; $operands = @(); $helpMode = $false; $endOptions = $false
    $catalog = Get-AgyCompletionCatalog
    foreach ($token in $tokens) {
        if ($pending) { $pending = ''; continue }
        if ($token -ceq '--') { $endOptions = $true; continue }
        if (-not $endOptions -and $token.StartsWith('-') -and -not ($context -eq 'mcp add' -and $operands.Count)) {
            $split = $token.IndexOf('=')
            if ($split -lt 0) { $pending = Get-AgyValueKind $context $token }
            continue
        }
        if (-not $context -and -not $operands.Count -and -not $endOptions -and $catalog.Commands.Contains($token)) {
            if ($token -eq 'help') { $helpMode = $true; continue }
            $context = if ($token -eq 'plugins') { 'plugin' } else { $token }
            $catalog = Get-AgyCompletionCatalog $context
            continue
        }
        if ($context -in @('plugin','mcp') -and -not $operands.Count -and $catalog.Commands.Contains($token)) {
            $context += ' ' + $token
            if ($context.StartsWith('mcp ')) { $catalog = Get-AgyCompletionCatalog $context }
            else { $catalog = @{ Options = @{}; Commands = @{} } }
            continue
        }
        $operands += $token
    }
    if ($pending) { Get-AgyValueCompletion $pending $Word; return }
    $allowOptions = -not $endOptions -and -not ($context -eq 'mcp add' -and $operands.Count) -and -not $helpMode
    if ($allowOptions -and $Word -match '^(--?[A-Za-z0-9][A-Za-z0-9-]*=)(.*)$') {
        $prefix = $Matches[1]; $value = $Matches[2]
        $kind = Get-AgyValueKind $context $prefix.TrimEnd('=')
        if ($kind) { Get-AgyValueCompletion $kind $value $prefix; return }
    }
    $found = $false
    if ($allowOptions -and ($Word.StartsWith('-') -or -not $Word)) {
        foreach ($option in ($catalog.Options.Keys | Sort-Object -CaseSensitive)) {
            if ($option.StartsWith($Word, [System.StringComparison]::Ordinal)) { New-AgyCompletion $option $catalog.Options[$option] 'ParameterName'; $found = $true }
        }
    }
    if (-not $endOptions -and -not $operands.Count) {
        foreach ($name in $catalog.Commands.Keys) {
            if ($name.StartsWith($Word, [System.StringComparison]::Ordinal)) { New-AgyCompletion $name $catalog.Commands[$name]; $found = $true }
        }
    }
    if ($found) { return }
    $kind = '<argument>'
    switch -Regex ($context) {
        '^$' { $kind = if ($helpMode) { '<command>' } else { '<prompt>' } }
        '^mcp add$' { $kind = if ($operands.Count -eq 0) { '<server-name>' } elseif ($operands.Count -eq 1) { '<command-or-url>' } else { '<command-argument>' } }
        '^mcp (remove|enable|disable)$' { $kind = '<server-name>' }
        '^plugin import$' { $kind = 'gemini|claude' }
        '^plugin validate$' { $kind = 'directory' }
        '^plugin install$' { $kind = 'directory' }
        '^plugin (uninstall|enable|disable)$' { $kind = '<plugin-name>' }
        '^plugin link$' { $kind = if ($operands.Count -eq 0) { '<marketplace>' } else { '<target>' } }
    }
    if ($context -eq 'plugin import' -and ($Word -match '[/\\.:]' -or -not $Word)) {
        Get-AgyValueCompletion 'directory' $Word
        if ($Word) { return }
    }
    if ($context -eq 'plugin install' -and (-not $Word -or $Word.Contains('@'))) {
        New-AgyCompletion $(if ($Word) { $Word } else { '<plugin@marketplace>' }) 'Enter a plugin@marketplace target or local directory'
        if ($Word) { return }
    }
    Get-AgyValueCompletion $kind $Word
}

Register-ArgumentCompleter -Native -CommandName @('agy', 'agy.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Get-AgyCompletion -Word $wordToComplete -Ast $commandAst -Cursor $cursorPosition
}
