# docker tab completion for PowerShell
# Help-driven completer for the Docker CLI, including nested subcommands and CLI plugins.

Set-StrictMode -Version 2.0

function New-DockerCompletionResult {
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

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Get-DockerExecutablePath {
    foreach ($candidate in @('docker', 'docker.exe')) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -ne $command) {
            return $command.Source
        }
    }

    return ''
}

function Get-DockerCatalogCache {
    $cache = Get-Variable -Name 'DockerCatalogCache' -Scope Script -ErrorAction Ignore
    if ($null -eq $cache -or $null -eq $cache.Value) {
        Set-Variable -Name 'DockerCatalogCache' -Value @{} -Scope Script
    }

    return (Get-Variable -Name 'DockerCatalogCache' -Scope Script).Value
}

function Invoke-DockerProcess {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory = ''
    )

    $commandPath = Get-DockerExecutablePath
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return $null
    }

    # A CLI plugin that hangs must not hang the prompt: standard input is closed
    # immediately and the child is killed if it outlives the budget.
    $output = $null
    $process = [System.Diagnostics.Process]::new()
    try {
        $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($commandPath)
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        if (-not [string]::IsNullOrEmpty($WorkingDirectory)) {
            $process.StartInfo.WorkingDirectory = $WorkingDirectory
        }

        foreach ($argument in @($Arguments)) {
            [void]$process.StartInfo.ArgumentList.Add($argument)
        }

        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()

        if ($process.WaitForExit(4000)) {
            $output = [pscustomobject]@{
                StdOut = ($stdout.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
                StdErr = ($stderr.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
            }
        } else {
            $process.Kill($true)
        }
    } catch {
        $output = $null
    } finally {
        $process.Dispose()
    }

    return $output
}

function Get-DockerHelpText {
    param([string[]]$Segments)

    $arguments = New-Object System.Collections.Generic.List[string]
    foreach ($segment in @($Segments)) {
        if (-not [string]::IsNullOrWhiteSpace($segment)) {
            [void]$arguments.Add($segment)
        }
    }

    [void]$arguments.Add('--help')

    $output = Invoke-DockerProcess -Arguments $arguments.ToArray()
    if ($null -eq $output) {
        return ''
    }

    return $output.StdOut + "`n" + $output.StdErr
}

function ConvertFrom-DockerQuotedToken {
    param([string]$Token)

    if ($Token.Length -ge 2 -and $Token[0] -eq "'" -and $Token[$Token.Length - 1] -eq "'") {
        return $Token.Substring(1, $Token.Length - 2).Replace("''", "'")
    }

    if ($Token.Length -ge 2 -and $Token[0] -eq '"' -and $Token[$Token.Length - 1] -eq '"') {
        return $Token.Substring(1, $Token.Length - 2)
    }

    return $Token
}

function Get-DockerRootSetting {
    param([string[]]$Tokens)

    # Global options sit before the first command word: -H/--host, -c/--context
    # and --config decide which daemon and which context store a query would use.
    $setting = @{ Host = ''; Context = ''; Config = '' }
    $rootCatalog = Get-DockerCommandCatalog -Segments @()
    $tokenList = @($Tokens)

    for ($index = 0; $index -lt $tokenList.Count; $index++) {
        $token = $tokenList[$index]
        if (-not $token.StartsWith('-')) {
            break
        }

        $name = $token
        $value = $null
        if ($token -match '^(?<name>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
            $name = $Matches.name
            $value = $Matches.value
        } else {
            $option = Find-DockerOption -Catalog $rootCatalog -Name $token
            if ($null -ne $option -and $option.TakesValue -and $index + 1 -lt $tokenList.Count) {
                $index++
                $value = $tokenList[$index]
            }
        }

        if ($null -eq $value) {
            continue
        }

        $value = ConvertFrom-DockerQuotedToken -Token $value
        if ($name -ceq '-H' -or $name -ceq '--host') {
            $setting.Host = $value
        } elseif ($name -ceq '-c' -or $name -ceq '--context') {
            $setting.Context = $value
        } elseif ($name -ceq '--config') {
            $setting.Config = $value
        }
    }

    return $setting
}

function Get-DockerDefaultHost {
    if (-not [string]::IsNullOrWhiteSpace($env:DOCKER_HOST)) {
        return $env:DOCKER_HOST
    }

    if ($IsWindows) {
        return 'npipe:////./pipe/docker_engine'
    }

    return 'unix:///var/run/docker.sock'
}

function Get-DockerContextEntry {
    param([hashtable]$Setting)

    # Contexts live in <config>/contexts/meta/<digest>/meta.json. Reading them is a
    # passive file read; only the name and the docker endpoint are taken, never
    # TLS material or anything else the store holds.
    $configDirectory = $Setting.Config
    if ([string]::IsNullOrWhiteSpace($configDirectory)) {
        $configDirectory = if ([string]::IsNullOrWhiteSpace($env:DOCKER_CONFIG)) { [System.IO.Path]::Combine($HOME, '.docker') } else { $env:DOCKER_CONFIG }
    }

    $entries = New-Object System.Collections.Generic.List[object]
    $metaRoot = [System.IO.Path]::Combine($configDirectory, 'contexts', 'meta')
    if ([System.IO.Directory]::Exists($metaRoot)) {
        foreach ($directory in [System.IO.Directory]::GetDirectories($metaRoot)) {
            $metaFile = [System.IO.Path]::Combine($directory, 'meta.json')
            if (-not [System.IO.File]::Exists($metaFile)) {
                continue
            }

            $text = [System.IO.File]::ReadAllText($metaFile)
            if ($text -notmatch '"Name"\s*:\s*"(?<name>[^"\\]+)"') {
                continue
            }

            $name = $Matches.name
            $endpoint = if ($text -match '"docker"\s*:\s*\{[^{}]*?"Host"\s*:\s*"(?<host>[^"]*)"') { $Matches.host } else { '' }
            [void]$entries.Add([pscustomobject]@{ Name = $name; Description = $endpoint })
        }
    }

    [void]$entries.Add([pscustomobject]@{ Name = 'default'; Description = (Get-DockerDefaultHost) })

    $current = ''
    $configFile = [System.IO.Path]::Combine($configDirectory, 'config.json')
    if ([System.IO.File]::Exists($configFile) -and [System.IO.File]::ReadAllText($configFile) -match '"currentContext"\s*:\s*"(?<name>[^"]*)"') {
        $current = $Matches.name
    }

    return [pscustomobject]@{
        Entries = @($entries.ToArray())
        Current = $current
    }
}

function Test-DockerLocalDaemon {
    param([string[]]$Tokens)

    # Same precedence as the CLI: --context, then --host, then DOCKER_HOST, then
    # DOCKER_CONTEXT, then the store's current context.
    $setting = Get-DockerRootSetting -Tokens $Tokens
    $endpoint = ''
    $contextName = ''

    if (-not [string]::IsNullOrWhiteSpace($setting.Context)) {
        $contextName = $setting.Context
    } elseif (-not [string]::IsNullOrWhiteSpace($setting.Host)) {
        $endpoint = $setting.Host
    } elseif (-not [string]::IsNullOrWhiteSpace($env:DOCKER_HOST)) {
        $endpoint = $env:DOCKER_HOST
    } elseif (-not [string]::IsNullOrWhiteSpace($env:DOCKER_CONTEXT)) {
        $contextName = $env:DOCKER_CONTEXT
    } else {
        $contextName = (Get-DockerContextEntry -Setting $setting).Current
    }

    if ([string]::IsNullOrEmpty($endpoint)) {
        if ([string]::IsNullOrEmpty($contextName) -or $contextName -ceq 'default') {
            $endpoint = Get-DockerDefaultHost
        } else {
            foreach ($entry in @((Get-DockerContextEntry -Setting $setting).Entries)) {
                if ($entry.Name -ceq $contextName) {
                    $endpoint = $entry.Description
                    break
                }
            }
        }
    }

    # Only a daemon on this machine that is already listening may be asked: a
    # remote endpoint is a network call, and a missing pipe means the engine is
    # not running, which completion must never try to change.
    if ($endpoint -match '^npipe:/{2,4}\./pipe/(?<pipe>[^/\\]+)$') {
        $pipePath = '\\.\pipe\' + $Matches.pipe
        foreach ($existing in [System.IO.Directory]::GetFiles('\\.\pipe\')) {
            if ([string]::Equals($existing, $pipePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        return $false
    }

    if ($endpoint -match '^unix://(?<path>/.+)$') {
        return [System.IO.File]::Exists($Matches.path)
    }

    return $false
}

function Get-DockerLiveCache {
    $cache = Get-Variable -Name 'DockerLiveCache' -Scope Script -ErrorAction Ignore
    if ($null -eq $cache -or $null -eq $cache.Value) {
        Set-Variable -Name 'DockerLiveCache' -Value ([System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)) -Scope Script
    }

    return (Get-Variable -Name 'DockerLiveCache' -Scope Script).Value
}

function Get-DockerLiveCandidate {
    param(
        [object]$Context,
        [string[]]$Arguments,
        [switch]$Operand
    )

    $path = @($Context.Path)
    $argumentList = @($Arguments)

    # Context names come straight from the context store, without a process:
    # the root -c/--context value, and the CONTEXT operand of every
    # 'docker context' verb that takes an existing context.
    $contextOption = (-not $Operand -and $path.Count -eq 0 -and $argumentList.Count -gt 0 -and $argumentList[$argumentList.Count - 1] -cin @('-c', '--context'))
    $contextOperand = ($Operand -and $path.Count -eq 2 -and $path[0] -ceq 'context' -and $path[1] -cnotin @('create', 'import'))
    if ($contextOption -or $contextOperand) {
        return @((Get-DockerContextEntry -Setting (Get-DockerRootSetting -Tokens $Context.Tokens)).Entries)
    }

    $workingDirectory = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
    $processArguments = New-Object System.Collections.Generic.List[string]
    [void]$processArguments.Add('__complete')
    foreach ($argument in $argumentList) {
        [void]$processArguments.Add((ConvertFrom-DockerQuotedToken -Token $argument))
    }

    # The partial word is filtered here, so one query serves every keystroke.
    [void]$processArguments.Add('')

    $key = @(
        $workingDirectory, $env:DOCKER_HOST, $env:DOCKER_CONTEXT, $env:DOCKER_CONFIG,
        $env:COMPOSE_FILE, $env:COMPOSE_PROFILES, ($processArguments.ToArray() -join "`0")
    ) -join "`n"

    $cache = Get-DockerLiveCache
    if ($cache.ContainsKey($key) -and $cache[$key].Stopwatch.Elapsed.TotalSeconds -lt 15) {
        return $cache[$key].Candidates
    }

    $candidates = New-Object System.Collections.Generic.List[object]

    # Compose reads its project files and needs no daemon. Core commands ask the
    # local daemon; other CLI plugins are skipped because their completion may
    # reach the network.
    $allowed = $true
    if ($path.Count -gt 0 -and $path[0] -cne 'compose') {
        foreach ($command in @((Get-DockerCommandCatalog -Segments @()).Commands)) {
            if ($command.Name -ceq $path[0] -and $command.IsPlugin) {
                $allowed = $false
                break
            }
        }
    }

    if ($allowed -and ($path.Count -eq 0 -or $path[0] -cne 'compose')) {
        $allowed = Test-DockerLocalDaemon -Tokens $Context.Tokens
    }

    $output = if ($allowed) { Invoke-DockerProcess -Arguments $processArguments.ToArray() -WorkingDirectory $workingDirectory } else { $null }
    if ($null -ne $output) {
        # cobra prints one candidate per line ("name<TAB>description") and ends
        # with ":<directive>"; directive bit 1 means the completion failed.
        $lines = @([regex]::Split($output.StdOut.TrimEnd(), '\r?\n'))
        $last = $lines[$lines.Count - 1]
        if ($last -match '^:(?<directive>\d+)$' -and ([int]$Matches.directive -band 1) -eq 0) {
            $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            foreach ($line in @($lines | Select-Object -First ($lines.Count - 1))) {
                if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('_activeHelp_')) {
                    continue
                }

                $parts = $line.Split("`t", 2)
                $name = $parts[0].Trim()
                if ($name.Length -gt 0 -and $seen.Add($name)) {
                    $description = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
                    [void]$candidates.Add([pscustomobject]@{ Name = $name; Description = $description })
                }
            }
        }
    }

    $cache[$key] = [pscustomobject]@{
        Candidates = @($candidates.ToArray())
        Stopwatch  = [System.Diagnostics.Stopwatch]::StartNew()
    }

    return @($candidates.ToArray())
}

function Add-DockerLiveResult {
    param(
        [System.Collections.Generic.List[object]]$Results,
        [object[]]$Candidates,
        [string]$WordToComplete,
        [string]$Prefix,
        [string]$ToolTip
    )

    # An opening quote the user typed is kept; the parser hands it over closed.
    $quote = ''
    $word = $WordToComplete
    if ($word.Length -gt 0 -and ($word[0] -eq "'" -or $word[0] -eq '"')) {
        $quote = [string]$word[0]
        $word = $word.Substring(1)
        if ($word.EndsWith($quote)) {
            $word = $word.Substring(0, $word.Length - 1)
        }
    }

    $pattern = [System.Management.Automation.WildcardPattern]::Escape($word) + '*'
    foreach ($candidate in @($Candidates)) {
        if ($candidate.Name -notlike $pattern) {
            continue
        }

        $text = $candidate.Name
        if ($quote -eq '"') {
            $text = '"' + ($text -replace '([`"$])', '`$1') + '"'
        } elseif ($quote -eq "'" -or $text -match '[\s{}();,|&<>''"`$]|^[@#]') {
            $text = "'" + $text.Replace("'", "''") + "'"
        }

        $candidateTip = if ([string]::IsNullOrWhiteSpace($candidate.Description)) { $ToolTip } else { $candidate.Description }
        [void]$Results.Add((New-DockerCompletionResult -CompletionText ($Prefix + $text) -ResultType 'ParameterValue' -ToolTip $candidateTip -ListItemText $candidate.Name))
    }
}

function Get-DockerOptionValueType {
    param([string]$Remainder)

    # "  -f, --filter filter   Filter output" - a single space, the type word, then
    # the aligned description column. A flag with no value has many spaces instead.
    if ($Remainder -match '^ (?<type>[a-z][A-Za-z0-9]*)(?:\s{2,}|$)') {
        return $Matches.type
    }

    return ''
}

function Get-DockerDescriptionEnumValue {
    param([string]$Description)

    $values = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Description)) {
        return @()
    }

    # ("never"|"always"|"auto"), ("debug", "info", "warn"), (auto, tty, plain)
    foreach ($group in [regex]::Matches($Description, '\((?<alts>(?:"[^"]+"|[a-z][a-z0-9_.-]*)(?:\s*[|,]\s*(?:"[^"]+"|[a-z][a-z0-9_.-]*))+)\)')) {
        $alternatives = @($group.Groups['alts'].Value -split '\s*[|,]\s*')
        if ($alternatives.Count -lt 2) {
            continue
        }

        foreach ($alternative in $alternatives) {
            $value = $alternative.Trim().Trim('"')
            if ($value -match '^[A-Za-z][A-Za-z0-9_.-]*$' -and -not $values.Contains($value)) {
                [void]$values.Add($value)
            }
        }
    }

    # docker's --format documents its modes as "'table':" / "'json':".
    foreach ($group in [regex]::Matches($Description, "'(?<value>[a-z][a-z0-9_.-]*)':")) {
        $value = $group.Groups['value'].Value
        if (-not $values.Contains($value)) {
            [void]$values.Add($value)
        }
    }

    return @($values.ToArray())
}

function Test-DockerPathOptionName {
    param([string]$Name)

    $bare = $Name -replace '^-+', ''
    return ($bare -match '(?i)(file|dir|directory|path|cert|cacert|key|config|output)$')
}

function ConvertFrom-DockerHelp {
    param([string]$HelpText)

    $lines = @([regex]::Split($HelpText, '\r?\n'))
    $options = New-Object System.Collections.Generic.List[object]
    $commands = New-Object System.Collections.Generic.List[object]
    $commandSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $usageLines = New-Object System.Collections.Generic.List[string]

    $section = ''
    $current = $null

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            $current = $null
            continue
        }

        # Section headers sit at column 0 or 1. Docker CLI plugins print them both
        # with and without the trailing colon, so the colon is optional here.
        if ($line -match '^\s{0,1}(?<name>[A-Za-z][A-Za-z ]*?)\s*:?\s*$' -and $trimmed -notmatch '^-') {
            $name = $Matches.name.Trim()
            $current = $null

            switch -Regex ($name) {
                '^(?:Options|Flags|Global Options|Global Flags|Advanced options)$' { $section = 'Options'; break }
                '^(?:\S+ )?Commands$' { $section = 'Commands'; break }
                '^Usage$' { $section = 'Usage'; break }
                default { $section = '' }
            }

            continue
        }

        if ($line -match '^Usage:?\s*(?<usage>\S.*)$') {
            [void]$usageLines.Add($Matches.usage)
            $section = ''
            $current = $null
            continue
        }

        $indent = $line.Length - $line.TrimStart(' ').Length

        if ($section -eq 'Usage') {
            [void]$usageLines.Add($trimmed)
            continue
        }

        if ($section -eq 'Commands') {
            if ($indent -ge 2 -and $indent -le 6 -and $line -match '^\s{2,}(?<name>[A-Za-z0-9][A-Za-z0-9_-]*)(?<plugin>\*)?(?:\s{2,}(?<description>\S.*))?$') {
                $name = $Matches.name
                $isPlugin = $Matches.ContainsKey('plugin')
                $description = if ($Matches.ContainsKey('description')) { $Matches.description } else { '' }
                if ($commandSeen.Add($name)) {
                    [void]$commands.Add([pscustomobject]@{ Name = $name; Description = $description; IsPlugin = $isPlugin })
                }
            }

            continue
        }

        if ($section -ne 'Options') {
            continue
        }

        # Option rows start at column 2 or 6. Wrapped description lines are indented
        # to the description column, so they can never be mistaken for definitions.
        # Only the leading "-s, --long" cluster names the option; dashed words in
        # the description ("-1 for unlimited", "implied by --tlsverify") do not.
        if ($indent -le 6 -and $trimmed.StartsWith('-')) {
            $definition = [regex]::Match($trimmed, '^(?:(?<short>-[A-Za-z0-9]),\s+)?(?<long>--[A-Za-z0-9][A-Za-z0-9-]*)(?=\s|=|$)|^(?<short>-[A-Za-z0-9])(?=\s|=|$)')
            if (-not $definition.Success) {
                $current = $null
                continue
            }

            $names = New-Object System.Collections.Generic.List[string]
            foreach ($group in @('short', 'long')) {
                if ($definition.Groups[$group].Success) {
                    [void]$names.Add($definition.Groups[$group].Value)
                }
            }

            $lastName = $names[$names.Count - 1]
            $remainder = $trimmed.Substring($definition.Length)
            $valueType = Get-DockerOptionValueType -Remainder $remainder
            $description = if ([string]::IsNullOrWhiteSpace($valueType)) { $remainder.Trim() } else { $remainder.Trim().Substring($valueType.Length).Trim() }

            $current = [pscustomobject]@{
                Name        = $lastName
                Names       = @($names.ToArray())
                TakesValue  = (-not [string]::IsNullOrWhiteSpace($valueType))
                ValueType   = $valueType
                IsPathValue = (Test-DockerPathOptionName -Name $lastName)
                Description = $description
            }

            [void]$options.Add($current)
            continue
        }

        if ($null -ne $current) {
            $current.Description = ($current.Description + ' ' + $trimmed).Trim()
        }
    }

    $hasHelp = $false
    foreach ($option in $options) {
        # Case-sensitive: the root's -H (--host) is not -h.
        if ($option.Names -ccontains '--help' -or $option.Names -ccontains '-h') {
            $hasHelp = $true
            break
        }
    }

    if (-not $hasHelp) {
        [void]$options.Add([pscustomobject]@{
                Name        = '--help'
                Names       = @('-h', '--help')
                TakesValue  = $false
                ValueType   = ''
                IsPathValue = $false
                Description = 'Show help'
            })
    }

    $usage = Get-DockerUsageOperand -UsageLines @($usageLines.ToArray())
    return [pscustomobject]@{
        Commands           = @($commands.ToArray())
        Options            = @($options.ToArray())
        Operands           = $usage.Operands
        HasTrailingCommand = $usage.HasTrailingCommand
    }
}

function Get-DockerUsageOperand {
    param([string[]]$UsageLines)

    $operands = New-Object System.Collections.Generic.List[object]
    $hasTrailingCommand = $false

    foreach ($usage in @($UsageLines)) {
        if ($usage -notmatch '(?i)^\s*docker(?:\.exe)?\b(?<rest>.*)$') {
            continue
        }

        foreach ($token in ($Matches.rest -split '\s+')) {
            $name = $token.Trim().Trim('[', ']', '|').TrimEnd('.')
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            # "IMAGE [COMMAND] [ARG...]": a COMMAND/ARG tail after an operand is the
            # container's own command line, not more docker arguments.
            if ($name -cin @('COMMAND', 'ARG', 'ARGS')) {
                if ($operands.Count -gt 0) {
                    $hasTrailingCommand = $true
                }

                continue
            }

            if ($name -cmatch '^[A-Z][A-Z0-9_]*$' -and $name -notin @('OPTIONS', 'SUBCOMMAND')) {
                [void]$operands.Add([pscustomobject]@{
                        Name   = $name
                        IsPath = ($name -match '(?i)(PATH|URL|FILE|DIR|DIRECTORY)$')
                    })
            }
        }

        break
    }

    return [pscustomobject]@{
        Operands           = @($operands.ToArray())
        HasTrailingCommand = $hasTrailingCommand
    }
}

function Get-DockerCommandCatalog {
    param([string[]]$Segments)

    $cache = Get-DockerCatalogCache
    $cacheKey = if (@($Segments).Count -gt 0) { @($Segments) -join ' ' } else { '<root>' }

    if ($cache.ContainsKey($cacheKey)) {
        $entry = $cache[$cacheKey]
        # A catalog that came back empty was most likely a transient failure (the
        # daemon or a plugin was not ready); retry it instead of poisoning the
        # whole session, but not on every keystroke.
        if ($entry.Complete -or $entry.Stopwatch.Elapsed.TotalSeconds -lt 30) {
            return $entry.Catalog
        }
    }

    $catalog = ConvertFrom-DockerHelp -HelpText (Get-DockerHelpText -Segments $Segments)
    $cache[$cacheKey] = [pscustomobject]@{
        Catalog   = $catalog
        Complete  = (@($catalog.Commands).Count -gt 0 -or @($catalog.Options).Count -gt 1)
        Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    }

    return $catalog
}

function Get-DockerCommandTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = New-Object System.Collections.Generic.List[string]

    if ($null -eq $CommandAst) {
        return @()
    }

    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($null -eq $element -or $null -eq $element.Extent) {
            continue
        }

        # Extent offsets and $cursorPosition are both absolute in the input line.
        # A token that ends at or after the cursor is the word being completed,
        # so it must not be consumed as a settled argument.
        if ($element.Extent.EndOffset -ge $CursorPosition) {
            continue
        }

        $text = $element.Extent.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            [void]$tokens.Add($text)
        }
    }

    return $tokens.ToArray()
}

function Find-DockerOption {
    param(
        [object]$Catalog,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    foreach ($option in @($Catalog.Options)) {
        foreach ($spelling in @($option.Names)) {
            if ([string]::Equals($spelling, $Name, [System.StringComparison]::Ordinal)) {
                return $option
            }
        }
    }

    return $null
}

function Get-DockerCompletionContext {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    if ($null -eq $CommandAst) {
        return $null
    }

    $elements = @($CommandAst.CommandElements)
    if ($elements.Count -lt 1) {
        return $null
    }

    $commandName = $elements[0].Extent.Text.Trim()
    if ($commandName -notin @('docker', 'docker.exe')) {
        return $null
    }

    $catalog = Get-DockerCommandCatalog -Segments @()
    $path = New-Object System.Collections.Generic.List[string]
    $tokens = @(Get-DockerCommandTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $operandCount = 0
    $skipNext = $false

    foreach ($token in $tokens) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }

        if ($token.StartsWith('-')) {
            if (-not $token.Contains('=')) {
                $option = Find-DockerOption -Catalog $catalog -Name $token
                if ($null -ne $option -and $option.TakesValue) {
                    $skipNext = $true
                }
            }

            continue
        }

        $match = $null
        foreach ($command in @($catalog.Commands)) {
            if ([string]::Equals($command.Name, $token, [System.StringComparison]::Ordinal)) {
                $match = $command
                break
            }
        }

        if ($null -eq $match) {
            $operandCount++
            continue
        }

        [void]$path.Add($token)
        $catalog = Get-DockerCommandCatalog -Segments @($path.ToArray())
    }

    $previous = ''
    if ($tokens.Count -gt 0) {
        $previous = $tokens[$tokens.Count - 1]
    }

    return [pscustomobject]@{
        CommandName  = $commandName
        Tokens       = $tokens
        Path         = $path.ToArray()
        Catalog      = $catalog
        Previous     = $previous
        OperandCount = $operandCount
    }
}

function Test-DockerPathLikeWord {
    param([string]$Word)

    if ([string]::IsNullOrEmpty($Word)) {
        return $false
    }

    return ($Word -match '^[.~]|[\\/]|^[A-Za-z]:')
}

function Get-DockerOptionValueCompletion {
    param(
        [object]$Option,
        [string]$WordToComplete,
        [string]$Prefix,
        [object]$Context,
        [string[]]$Arguments
    )

    $results = New-Object System.Collections.Generic.List[object]
    $values = @(Get-DockerDescriptionEnumValue -Description $Option.Description)
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*'

    if ($values.Count -gt 0) {
        foreach ($value in $values) {
            if ($value -like $pattern) {
                [void]$results.Add((New-DockerCompletionResult -CompletionText ($Prefix + $value) -ResultType 'ParameterValue' -ToolTip $Option.Description -ListItemText $value))
            }
        }

        return [object[]]$results
    }

    if ($Option.IsPathValue -or (Test-DockerPathLikeWord -Word $WordToComplete)) {
        if ([string]::IsNullOrEmpty($Prefix)) {
            return @([System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete))
        }

        return @()
    }

    # Live values (contexts, networks, ...) replace the placeholder when the
    # CLI's own completion has any; otherwise the placeholder stays.
    $candidates = @(Get-DockerLiveCandidate -Context $Context -Arguments $Arguments)
    if ($candidates.Count -gt 0) {
        Add-DockerLiveResult -Results $results -Candidates $candidates -WordToComplete $WordToComplete -Prefix $Prefix -ToolTip $Option.Description
        return [object[]]$results
    }

    if ([string]::IsNullOrEmpty($WordToComplete)) {
        $placeholder = "<$($Option.ValueType)>"
        [void]$results.Add((New-DockerCompletionResult -CompletionText ($Prefix + $placeholder) -ResultType 'ParameterValue' -ToolTip $Option.Description -ListItemText $placeholder))
    }

    return [object[]]$results
}

function Complete-DockerCommand {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $context = Get-DockerCompletionContext -CommandAst $commandAst -CursorPosition $cursorPosition
    if ($null -eq $context) {
        return @()
    }

    # Past the operands of run/create/exec every word belongs to the container's
    # command, which docker's own completion leaves alone too.
    if ($context.Catalog.HasTrailingCommand -and $context.OperandCount -ge @($context.Catalog.Operands).Count) {
        return @()
    }

    $prefix = if ($null -eq $wordToComplete) { '' } else { $wordToComplete }
    $results = New-Object System.Collections.Generic.List[object]
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($prefix) + '*'

    # Attached form: --log-level=de
    if ($prefix -match '^(?<name>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = Find-DockerOption -Catalog $context.Catalog -Name $Matches.name
        if ($null -ne $option -and $option.TakesValue) {
            return @(Get-DockerOptionValueCompletion -Option $option -WordToComplete $Matches.value -Prefix "$($Matches.name)=" -Context $context -Arguments @(@($context.Tokens) + @($Matches.name)))
        }

        return @()
    }

    if ($prefix -match '^-') {
        foreach ($option in @($context.Catalog.Options)) {
            foreach ($optionName in @($option.Names)) {
                if ($optionName -clike $pattern) {
                    [void]$results.Add((New-DockerCompletionResult -CompletionText $optionName -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $optionName))
                }
            }
        }

        return [object[]]$results
    }

    # Separate form: the settled token before the cursor is a value-bearing option.
    if ($context.Previous.StartsWith('-') -and -not $context.Previous.Contains('=')) {
        $option = Find-DockerOption -Catalog $context.Catalog -Name $context.Previous
        if ($null -ne $option -and $option.TakesValue) {
            return @(Get-DockerOptionValueCompletion -Option $option -WordToComplete $prefix -Prefix '' -Context $context -Arguments @($context.Tokens))
        }
    }

    # A path-shaped word belongs to the engine's own filename completion.
    if (Test-DockerPathLikeWord -Word $prefix) {
        return @()
    }

    foreach ($command in @($context.Catalog.Commands)) {
        if ($command.Name -like $pattern) {
            $toolTip = if ([string]::IsNullOrWhiteSpace($command.Description)) { (@(@('docker') + @($context.Path) + @($command.Name)) -join ' ') } else { $command.Description }
            [void]$results.Add((New-DockerCompletionResult -CompletionText $command.Name -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $command.Name))
        }
    }

    # Operand slot. A path-shaped operand is left to the engine; anything else gets
    # the CLI's own live names (containers, images, services, contexts, ...), or a
    # placeholder when there are none, so the slot does not silently fill with
    # unrelated file names.
    $operands = @($context.Catalog.Operands)
    if ($context.OperandCount -lt $operands.Count) {
        $operand = $operands[$context.OperandCount]
        if (-not $operand.IsPath) {
            $candidates = @(Get-DockerLiveCandidate -Context $context -Arguments @($context.Tokens) -Operand)
            if ($candidates.Count -gt 0) {
                Add-DockerLiveResult -Results $results -Candidates $candidates -WordToComplete $prefix -Prefix '' -ToolTip "$($operand.Name) operand"
            } elseif ([string]::IsNullOrEmpty($prefix)) {
                [void]$results.Add((New-DockerCompletionResult -CompletionText "<$($operand.Name)>" -ResultType 'ParameterValue' -ToolTip "$($operand.Name) operand" -ListItemText "<$($operand.Name)>"))
            }
        }
    }

    foreach ($option in @($context.Catalog.Options)) {
        foreach ($optionName in @($option.Names)) {
            if ($optionName -clike $pattern) {
                [void]$results.Add((New-DockerCompletionResult -CompletionText $optionName -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $optionName))
            }
        }
    }

    return [object[]]$results
}

Register-ArgumentCompleter -Native -CommandName @('docker', 'docker.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-DockerCommand -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
