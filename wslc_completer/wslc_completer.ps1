# Help-driven completer for wslc.exe, the WSL container CLI.
# Command and option lists come from live --help. Object names come from read-only JSON lists.

Set-StrictMode -Version 2.0

function New-WslcCompletionResult {
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

function Get-WslcExecutablePath {
    foreach ($candidate in @('wslc', 'wslc.exe')) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction Ignore |
            Select-Object -First 1
        if ($null -ne $command) {
            return $command.Source
        }
    }

    $defaultPath = 'C:\Program Files\WSL\wslc.exe'
    if (Test-Path -LiteralPath $defaultPath) {
        return $defaultPath
    }

    return ''
}

function Get-WslcHelpCache {
    $cache = Get-Variable -Name 'WslcHelpCache' -Scope Script -ErrorAction Ignore
    if ($null -eq $cache -or $null -eq $cache.Value) {
        Set-Variable -Name 'WslcHelpCache' -Scope Script -Value ([System.Collections.Hashtable]::new([System.StringComparer]::Ordinal))
    }

    return (Get-Variable -Name 'WslcHelpCache' -Scope Script).Value
}

function Get-WslcListCache {
    $cache = Get-Variable -Name 'WslcListCache' -Scope Script -ErrorAction Ignore
    if ($null -eq $cache -or $null -eq $cache.Value) {
        Set-Variable -Name 'WslcListCache' -Scope Script -Value ([System.Collections.Hashtable]::new([System.StringComparer]::Ordinal))
    }

    return (Get-Variable -Name 'WslcListCache' -Scope Script).Value
}

function Get-WslcStripAnsi {
    param([string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    return ($Text -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
}

function Invoke-WslcCapture {
    param(
        [string[]]$Arguments,
        [int]$TimeoutMs = 4000
    )

    $path = Get-WslcExecutablePath
    if ([string]::IsNullOrWhiteSpace($path)) {
        return ''
    }

    $process = [System.Diagnostics.Process]::new()
    try {
        $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($path)
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        foreach ($argument in @($Arguments)) {
            if (-not [string]::IsNullOrWhiteSpace($argument)) {
                [void]$process.StartInfo.ArgumentList.Add($argument)
            }
        }

        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()

        if ($process.WaitForExit($TimeoutMs)) {
            return (Get-WslcStripAnsi -Text $stdout.GetAwaiter().GetResult()) + "`n" + (Get-WslcStripAnsi -Text $stderr.GetAwaiter().GetResult())
        }

        try {
            $process.Kill($true)
        }
        catch {
            try { $process.Kill() } catch { }
        }
    }
    catch {
        return ''
    }
    finally {
        $process.Dispose()
    }

    return ''
}

function Get-WslcEnumValues {
    param(
        [string]$Description,
        [string]$OptionName
    )

    $values = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Description)) {
        return @()
    }

    foreach ($match in [regex]::Matches($Description, '\((?<enum>[A-Za-z0-9]+(?:\|[A-Za-z0-9]+)+)\)')) {
        foreach ($part in @($match.Groups['enum'].Value -split '\|')) {
            if (-not $values.Contains($part)) {
                [void]$values.Add($part)
            }
        }
    }

    foreach ($match in [regex]::Matches($Description, '\((?<enum>[A-Za-z0-9]+(?:\s*,\s*[A-Za-z0-9]+)+)\)')) {
        foreach ($part in @($match.Groups['enum'].Value -split '\s*,\s*')) {
            if (-not $values.Contains($part)) {
                [void]$values.Add($part)
            }
        }
    }

    if ($Description -match '(?i)\bjson\b(?:\s+or\s+|\s*/\s*)\btable\b') {
        foreach ($part in @('json', 'table')) {
            if (-not $values.Contains($part)) {
                [void]$values.Add($part)
            }
        }
    }

    if ($OptionName -eq '--gpus' -and $Description -match "'all'") {
        if (-not $values.Contains('all')) {
            [void]$values.Add('all')
        }
    }

    return @($values)
}

function Test-WslcOptionTakesValue {
    param(
        [string]$Name,
        [string]$Description
    )

    if ($Name -in @('-?', '--help', '--password-stdin', '--version')) {
        return $false
    }

    # Descriptions for these read like flags ("Show all events created since the timestamp", "Username").
    if ($Name -in @('--since', '--until', '--password', '--username', '--type', '--gateway', '--label')) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($Description)) {
        return $false
    }

    if ($Description -match '\([A-Za-z0-9]+(?:\|[A-Za-z0-9]+)+\)' -or $Description -match '\([A-Za-z0-9]+(?:\s*,\s*[A-Za-z0-9]+)+\)' -or $Description -match '(?i)\bjson\b(?:\s+or\s+|\s*/\s*)\btable\b' -or $Description -match '(?i)\(e\.g\.') {
        return $true
    }

    if ($Description -match '(?i)^always attempt') {
        return $false
    }

    if ($Description -match '(?i)^(show n |write |number |ip address|set |key=|file |add |command to|time between|name of|name for|connect a|publish a |image pull|size of|signal to|timeout |mount |user |bind |working |specif|path to|tag |filter |assign |consecutive |start period|maximum |ulimit |output formatting|expose |seconds )') {
        return $true
    }

    if ($Description -match '(?i)^(run container|remove the|remove container|disable |show all|show the latest|display |do not |open a |outputs the|publish all|output verbose)') {
        return $false
    }

    if ($Description -match '(?i)\b(path|file|name|policy|format|seconds|address|directory|limit|destination|secret|label|alias|port|hostname|domain|mount)\b') {
        return $true
    }

    return $false
}

function Test-WslcPathOption {
    param(
        [string]$Name,
        [string]$Description
    )

    $leaf = $Name -replace '^-+', ''
    if ($leaf -in @('file', 'cidfile', 'iidfile', 'env-file')) {
        return $true
    }

    # export/save write a file; build --output takes a buildx spec.
    if ($Name -eq '--output') {
        return ($Description -notmatch '(?i)\bspec\b')
    }

    if ($Name -in @('--publish', '--mount', '--tmpfs', '--volume', '--secret')) {
        return $false
    }

    return ($Description -match '(?i)\bpath\b' -and $Description -notmatch '(?i)publish')
}

function Get-WslcValueKind {
    param(
        [string]$Name,
        [string]$Description,
        [bool]$IsPath
    )

    $leaf = $Name -replace '^-+', ''
    if ($Name -in @('--password')) {
        return 'secret'
    }

    if ($Name -eq '--session') {
        return 'session'
    }

    if ($Name -eq '--network') {
        return 'network'
    }

    if ($Name -in @('-v', '--volume')) {
        return 'volume'
    }

    if ($Name -in @('-p', '--publish')) {
        return 'publish'
    }

    if ($Name -in @('-e', '--env', '--build-arg', '-l', '--label')) {
        return 'keyvalue'
    }

    if ($Name -eq '--name') {
        return 'newname'
    }

    if ($IsPath) {
        return 'path'
    }

    if ($leaf -eq 'filter') {
        return 'filter'
    }

    return 'placeholder'
}

function Get-WslcOperandKind {
    param([string]$Name)

    $leaf = $Name.ToLowerInvariant()
    switch -Regex ($leaf) {
        'container' { return 'container' }
        'image|source|target' { return 'image' }
        'network' { return 'network' }
        'volume' { return 'volume' }
        'session' { return 'session' }
        'path|file|tarball|context' { return 'path' }
        'server' { return 'server' }
        'command' { return 'command' }
        'argument' { return 'argument' }
        default { return 'placeholder' }
    }
}

function ConvertFrom-WslcHelp {
    param([string]$HelpText)

    $commands = New-Object System.Collections.Generic.List[object]
    $options = New-Object System.Collections.Generic.List[object]
    $operands = New-Object System.Collections.Generic.List[object]
    $seenCommands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $seenOptions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $argumentDescriptions = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $section = ''

    foreach ($line in @([regex]::Split([string]$HelpText, '\r?\n'))) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($trimmed -match '^Commands?:\s*$') {
            $section = 'Commands'
            continue
        }

        if ($trimmed -match '^Options?:\s*$' -or $trimmed -match '^Global Options for .*:$') {
            $section = 'Options'
            continue
        }

        if ($trimmed -match '^Arguments?:\s*$') {
            $section = 'Arguments'
            continue
        }

        if ($trimmed -match '^Aliases?:\s*$' -or $trimmed -match '^Usage:' -or $trimmed -match '^For more details') {
            $section = ''
            if ($trimmed -match '^Usage:\s+(?<rest>.+)$') {
                $rest = $Matches.rest
                $skipCommandOperand = $rest -match '\[<command>\]' -and $rest -notmatch '<image>'
                if ($rest -match '\[options\]\s*(?<tail>.*)$') {
                    $rest = $Matches.tail
                }

                foreach ($match in [regex]::Matches($rest, '<(?<name>[A-Za-z0-9_-]+)>(?<repeat>\.\.\.)?')) {
                    $operandName = $match.Groups['name'].Value
                    if ($operandName -in @('options', 'global-options')) {
                        continue
                    }

                    if ($skipCommandOperand -and $operandName -eq 'command') {
                        continue
                    }

                    [void]$operands.Add([pscustomobject]@{
                            Name      = $operandName
                            Kind      = (Get-WslcOperandKind -Name $operandName)
                            IsPath    = ((Get-WslcOperandKind -Name $operandName) -eq 'path')
                            Repeating = [bool]$match.Groups['repeat'].Success
                        })
                }
            }

            continue
        }

        if ($section -eq 'Commands' -and $trimmed -match '^(?<name>[a-z][a-z0-9-]*)\s{2,}(?<desc>.+)$') {
            $name = $Matches.name
            if ($seenCommands.Add($name)) {
                [void]$commands.Add([pscustomobject]@{
                        Name        = $name
                        Description = $Matches.desc.Trim()
                    })
            }

            continue
        }

        if ($section -eq 'Arguments' -and $trimmed -match '^(?<name>[A-Za-z0-9_-]+)\s{2,}(?<desc>.+)$') {
            $argumentDescriptions[$Matches.name] = $Matches.desc.Trim()
            continue
        }

        if ($section -eq 'Options' -and $trimmed -match '^(?:(?<short>-[A-Za-z0-9?])\s+)?(?<long>--[A-Za-z0-9][A-Za-z0-9-]*)(?:\s+(?<desc>.*))?$') {
            $names = New-Object System.Collections.Generic.List[string]
            if ($Matches.ContainsKey('short') -and -not [string]::IsNullOrWhiteSpace($Matches.short)) {
                [void]$names.Add($Matches.short)
            }

            [void]$names.Add($Matches.long)
            $description = ''
            if ($Matches.ContainsKey('desc')) {
                $description = [string]$Matches.desc
            }

            $description = $description.Trim()
            $key = $names -join '|'
            if ($seenOptions.Add($key)) {
                $isPath = Test-WslcPathOption -Name $Matches.long -Description $description
                [void]$options.Add([pscustomobject]@{
                        Names       = @($names)
                        Description = $description
                        TakesValue  = (Test-WslcOptionTakesValue -Name $Matches.long -Description $description)
                        Enums       = @(Get-WslcEnumValues -Description $description -OptionName $Matches.long)
                        IsPath      = $isPath
                        ValueKind   = (Get-WslcValueKind -Name $Matches.long -Description $description -IsPath $isPath)
                    })
            }
        }
    }

    # Usage names alone are ambiguous: tag <source> is an image, container cp <source> is a path.
    foreach ($operand in $operands) {
        $description = [string]$argumentDescriptions[$operand.Name]
        if ($description -match '(?i)\bpath\b') {
            $operand.Kind = 'path'
            $operand.IsPath = $true
        }
    }

    $commandArray = @($commands.ToArray())
    $optionArray = @($options.ToArray())
    $operandArray = @($operands.ToArray())
    return [pscustomobject]@{
        Commands = $commandArray
        Options  = $optionArray
        Operands = $operandArray
    }
}

function Get-WslcStaticRootCatalog {
    $commands = @(
        'container', 'image', 'network', 'registry', 'settings', 'system', 'volume',
        'attach', 'build', 'create', 'exec', 'events', 'export', 'images', 'import', 'info',
        'inspect', 'kill', 'list', 'load', 'login', 'logout', 'logs', 'pull', 'push', 'remove',
        'restart', 'rmi', 'run', 'save', 'start', 'stats', 'stop', 'tag', 'version', 'ls', 'ps'
    ) | ForEach-Object {
        [pscustomobject]@{ Name = $_; Description = $_ }
    }

    $options = @(
        [pscustomobject]@{ Names = @('-v', '--version'); Description = 'Show version information for this tool'; TakesValue = $false; Enums = @(); IsPath = $false; ValueKind = 'placeholder' }
        [pscustomobject]@{ Names = @('-?', '--help'); Description = 'Shows help about the selected command'; TakesValue = $false; Enums = @(); IsPath = $false; ValueKind = 'placeholder' }
        [pscustomobject]@{ Names = @('--session'); Description = 'Specify the session to use'; TakesValue = $true; Enums = @(); IsPath = $false; ValueKind = 'session' }
    )

    return [pscustomobject]@{
        Commands = @($commands)
        Options  = @($options)
        Operands = @()
    }
}

function Add-WslcCommandAliases {
    param(
        [object]$Catalog,
        [string[]]$Segments
    )

    # Parent help lists canonical names only; each alias appears on its target's own page.
    # Probe the usual spellings and keep one only when that page lists it under Aliases.
    $commands = New-Object System.Collections.Generic.List[object]
    foreach ($command in @($Catalog.Commands)) {
        [void]$commands.Add($command)
    }

    if ($commands.Count -eq 0) {
        return $Catalog
    }

    foreach ($alias in @('ls', 'ps', 'rm', 'delete')) {
        if ($null -ne (Find-WslcCommand -Catalog $Catalog -Name $alias)) {
            continue
        }

        $helpText = Invoke-WslcCapture -Arguments @($Segments + $alias + '--help') -TimeoutMs 4000
        $lines = @([regex]::Split([string]$helpText, '\r?\n') | ForEach-Object { $_.Trim() })
        $index = [array]::IndexOf($lines, 'Aliases:')
        if ($index -lt 0 -or $index + 1 -ge $lines.Count) {
            continue
        }

        $spelling = (@('wslc') + $Segments + $alias) -join ' '
        if (@($lines[$index + 1] -split '\s*,\s*') -cnotcontains $spelling) {
            continue
        }

        $target = $alias
        if ($helpText -match '(?m)^Usage:\s+wslc\s+(?<path>[a-z][a-z0-9 -]*?)\s+\[') {
            $target = @($Matches.path -split '\s+')[-1]
        }

        [void]$commands.Add([pscustomobject]@{ Name = $alias; Description = "Alias of $target" })
    }

    $Catalog.Commands = @($commands.ToArray())
    return $Catalog
}

function Get-WslcCommandCatalog {
    param([string[]]$Segments)

    $segmentList = @($Segments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $key = $segmentList -join ' '
    $cache = Get-WslcHelpCache
    if ($cache.ContainsKey($key)) {
        $entry = $cache[$key]
        $fresh = $entry.Complete -or ($entry.Fetched -gt [datetime]::UtcNow.AddSeconds(-30))
        if ($fresh) {
            return $entry.Catalog
        }
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    foreach ($segment in $segmentList) {
        [void]$arguments.Add($segment)
    }

    [void]$arguments.Add('--help')
    $helpText = Invoke-WslcCapture -Arguments @($arguments) -TimeoutMs 4000
    $catalog = $null
    $complete = $false
    if (-not [string]::IsNullOrWhiteSpace($helpText) -and $helpText -match '(?m)^Commands?:|^Options?:|^Usage:') {
        $catalog = Add-WslcCommandAliases -Catalog (ConvertFrom-WslcHelp -HelpText $helpText) -Segments $segmentList
        $complete = (@($catalog.Commands).Count -gt 0 -or @($catalog.Options).Count -gt 0)
    }

    if ($null -eq $catalog) {
        if ($segmentList.Count -eq 0) {
            $catalog = Get-WslcStaticRootCatalog
        }
        else {
            $catalog = [pscustomobject]@{ Commands = @(); Options = @(); Operands = @() }
        }
    }

    $cache[$key] = [pscustomobject]@{
        Catalog  = $catalog
        Complete = $complete
        Fetched  = [datetime]::UtcNow
    }

    return $catalog
}

function Find-WslcOption {
    param(
        [object]$Catalog,
        [string]$Name
    )

    foreach ($option in @($Catalog.Options)) {
        foreach ($spelling in @($option.Names)) {
            if ([string]::Equals($spelling, $Name, [System.StringComparison]::Ordinal)) {
                return $option
            }
        }
    }

    return $null
}

function Resolve-WslcOption {
    param(
        [object]$Catalog,
        [string]$Name
    )

    $option = Find-WslcOption -Catalog $Catalog -Name $Name
    if ($null -ne $option -or $Name -cnotmatch '^-[A-Za-z0-9?]{2,}$') {
        return $option
    }

    # Alias chain (-dp): every letter is a flag and only the last one may take a value.
    $last = $null
    for ($i = 1; $i -lt $Name.Length; $i++) {
        $last = Find-WslcOption -Catalog $Catalog -Name ('-' + $Name[$i])
        if ($null -eq $last -or ($last.TakesValue -and $i -lt $Name.Length - 1)) {
            return $null
        }
    }

    return $last
}

function Find-WslcCommand {
    param(
        [object]$Catalog,
        [string]$Name
    )

    foreach ($command in @($Catalog.Commands)) {
        if ([string]::Equals($command.Name, $Name, [System.StringComparison]::Ordinal)) {
            return $command
        }
    }

    return $null
}

function Get-WslcCommandTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($null -eq $element -or $null -eq $element.Extent) {
            continue
        }

        # EndOffset and $cursorPosition are both absolute. The token under the cursor is not settled.
        if ($element.Extent.EndOffset -ge $CursorPosition) {
            continue
        }

        $text = $element.Extent.Text.Trim().Trim('"').Trim("'")
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            [void]$tokens.Add($text)
        }
    }

    return @($tokens)
}

function Get-WslcCompletionContext {
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

    $commandName = $elements[0].Extent.Text.Trim().Trim('"').Trim("'")
    if ($commandName -notin @('wslc', 'wslc.exe')) {
        return $null
    }

    $catalog = Get-WslcCommandCatalog -Segments @()
    $path = New-Object System.Collections.Generic.List[string]
    $tokens = @(Get-WslcCommandTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $operandCount = 0
    $pendingOption = ''
    $session = ''

    foreach ($token in $tokens) {
        if (-not [string]::IsNullOrEmpty($pendingOption)) {
            if ($pendingOption -eq '--session') {
                $session = $token
            }

            $pendingOption = ''
            continue
        }

        if ($token.StartsWith('-')) {
            if ($token.StartsWith('--session=')) {
                $session = $token.Substring('--session='.Length)
            }
            elseif (-not $token.Contains('=')) {
                $option = Resolve-WslcOption -Catalog $catalog -Name $token
                if ($null -ne $option -and $option.TakesValue) {
                    $pendingOption = @($option.Names)[-1]
                }
            }

            continue
        }

        $match = Find-WslcCommand -Catalog $catalog -Name $token
        if ($null -ne $match) {
            [void]$path.Add($token)
            $catalog = Get-WslcCommandCatalog -Segments @($path)
            continue
        }

        $operandCount++
    }

    $previous = ''
    if ($tokens.Count -gt 0) {
        $previous = [string]$tokens[$tokens.Count - 1]
    }

    # run/create/exec and session run stop parsing options at the first operand; the rest belongs to <command>.
    $passthrough = $operandCount -gt 0 -and @($catalog.Operands | Where-Object { $_.Name -eq 'command' }).Count -gt 0

    return [pscustomobject]@{
        Tokens       = $tokens
        Path         = @($path)
        Catalog      = $catalog
        Previous     = $previous
        OperandCount = $operandCount
        Session      = $session
        Passthrough  = $passthrough
    }
}

function Get-WslcPropertyText {
    param(
        [object]$Item,
        [string]$Name
    )

    if ($null -eq $Item) {
        return ''
    }

    $property = $Item.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return ''
    }

    $value = $property.Value
    if ($value -is [string]) {
        return $value.Trim()
    }

    if ($value -is [System.Collections.IEnumerable]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($part in @($value)) {
            $text = [string]$part
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                [void]$parts.Add($text.Trim())
            }
        }

        return ($parts -join ',')
    }

    return ([string]$value).Trim()
}

function Get-WslcSessionNames {
    $cache = Get-WslcListCache
    $now = [datetime]::UtcNow
    if ($cache.ContainsKey('list:session')) {
        $entry = $cache['list:session']
        if ($entry.Expires -gt $now) {
            return @($entry.Values)
        }
    }

    # 'system session list' has no --format; parse the Display Name column of its table.
    # It only reads state, unlike the object lists, which start the default session.
    $values = New-Object System.Collections.Generic.List[string]
    $text = Invoke-WslcCapture -Arguments @('system', 'session', 'list') -TimeoutMs 3000
    $column = -1
    foreach ($line in @([regex]::Split([string]$text, '\r?\n'))) {
        if ($column -lt 0) {
            $column = $line.IndexOf('Display Name', [System.StringComparison]::Ordinal)
            continue
        }

        if ($line.Length -gt $column) {
            $name = $line.Substring($column).Trim()
            if (-not [string]::IsNullOrWhiteSpace($name) -and -not $values.Contains($name)) {
                [void]$values.Add($name)
            }
        }
    }

    $cache['list:session'] = [pscustomobject]@{
        Expires = $now.AddSeconds(8)
        Values  = @($values)
    }

    return @($values)
}

function Get-WslcDynamicNames {
    param(
        [string]$Kind,
        [string]$Session
    )

    if ($Kind -eq 'session') {
        return @(Get-WslcSessionNames)
    }

    # Listing objects boots the session when none is running (about 2 s). Completion must not do that.
    $sessions = @(Get-WslcSessionNames)
    if ($sessions.Count -eq 0 -or (-not [string]::IsNullOrEmpty($Session) -and $sessions -cnotcontains $Session)) {
        return @()
    }

    $cache = Get-WslcListCache
    $key = 'list:' + $Kind + ':' + $Session
    $now = [datetime]::UtcNow
    if ($cache.ContainsKey($key)) {
        $entry = $cache[$key]
        if ($entry.Expires -gt $now) {
            return @($entry.Values)
        }
    }

    $arguments = switch ($Kind) {
        'container' { @('list', '--all', '--format', 'json') }
        'image' { @('images', '--format', 'json') }
        'network' { @('network', 'list', '--format', 'json') }
        'volume' { @('volume', 'list', '--format', 'json') }
        default { @() }
    }

    if (-not [string]::IsNullOrEmpty($Session)) {
        $arguments = @('--session', $Session) + $arguments
    }

    $values = New-Object System.Collections.Generic.List[string]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if (@($arguments).Count -gt 0) {
        $text = Invoke-WslcCapture -Arguments $arguments -TimeoutMs 3000
        foreach ($line in @([regex]::Split([string]$text, '\r?\n'))) {
            $trimmed = $line.Trim()
            if (-not $trimmed.StartsWith('{')) {
                continue
            }

            $item = $null
            try {
                $item = $trimmed | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                continue
            }

            $picked = New-Object System.Collections.Generic.List[string]
            switch ($Kind) {
                'image' {
                    $repo = Get-WslcPropertyText -Item $item -Name 'Repository'
                    $tag = Get-WslcPropertyText -Item $item -Name 'Tag'
                    if (-not [string]::IsNullOrWhiteSpace($repo) -and -not [string]::IsNullOrWhiteSpace($tag) -and $tag -ne '<none>') {
                        [void]$picked.Add($repo + ':' + $tag)
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($repo)) {
                        [void]$picked.Add($repo)
                    }

                    foreach ($field in @('ID', 'Id')) {
                        $id = Get-WslcPropertyText -Item $item -Name $field
                        if (-not [string]::IsNullOrWhiteSpace($id)) {
                            [void]$picked.Add($id)
                        }
                    }
                }
                default {
                    foreach ($field in @('Names', 'Name', 'ID', 'Id')) {
                        $textValue = Get-WslcPropertyText -Item $item -Name $field
                        if (-not [string]::IsNullOrWhiteSpace($textValue)) {
                            [void]$picked.Add($textValue.TrimStart('/'))
                            if ($Kind -in @('network', 'volume')) {
                                break
                            }
                        }
                    }
                }
            }

            foreach ($name in @($picked)) {
                if (-not [string]::IsNullOrWhiteSpace($name) -and $seen.Add($name)) {
                    [void]$values.Add($name)
                }
            }
        }
    }

    $cache[$key] = [pscustomobject]@{
        Expires = $now.AddSeconds(8)
        Values  = @($values)
    }

    return @($values)
}

function Test-WslcPathLikeWord {
    param([string]$Word)

    if ([string]::IsNullOrEmpty($Word)) {
        return $false
    }

    return ($Word -match '^[.~]|[\\/]|^[A-Za-z]:')
}

function Get-WslcPlaceholder {
    param([string]$Name)

    $leaf = ($Name -replace '^-+', '').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        return '<value>'
    }

    return '<' + $leaf + '>'
}

function Add-WslcFilteredResults {
    param(
        [System.Collections.Generic.List[object]]$Results,
        [System.Collections.Generic.HashSet[string]]$Seen,
        [string[]]$Candidates,
        [string]$Word,
        [string]$Prefix,
        [string]$ResultType,
        [string]$ToolTip
    )

    foreach ($candidate in @($Candidates)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $completion = $Prefix + $candidate
        $typed = $Prefix + $Word
        if (-not $completion.StartsWith($typed, [System.StringComparison]::Ordinal)) {
            continue
        }

        if (-not $Seen.Add($completion)) {
            continue
        }

        $item = New-WslcCompletionResult -CompletionText $completion -ResultType $ResultType -ToolTip $ToolTip -ListItemText $candidate
        if ($null -ne $item) {
            [void]$Results.Add($item)
        }
    }
}

function Get-WslcKindValues {
    param(
        [string]$Kind,
        [string]$Word,
        [string]$Session
    )

    $values = New-Object System.Collections.Generic.List[string]
    $kinds = switch ($Kind) {
        'inspect' { @('container', 'image') }
        { $_ -in @('container', 'image', 'network', 'volume', 'session') } { $Kind }
    }

    # A $null $kinds (no listable kind) iterates zero times.
    foreach ($listKind in $kinds) {
        foreach ($name in @(Get-WslcDynamicNames -Kind $listKind -Session $Session)) {
            [void]$values.Add($name)
        }
    }

    if ($values.Count -eq 0 -and [string]::IsNullOrEmpty($Word)) {
        $placeholder = switch ($Kind) {
            'container' { '<container>' }
            'image' { '<image>' }
            'network' { '<network>' }
            'volume' { '<volume>' }
            'session' { '<session>' }
            'inspect' { '<container-or-image>' }
            'secret' { '<password>' }
            'server' { '<server>' }
            'publish' { '<host:container>' }
            'keyvalue' { '<key=value>' }
            'newname' { '<name>' }
            'filter' { '<filter>' }
            'command' { '<command>' }
            'argument' { '<argument>' }
            'placeholder' { '<value>' }
            default { '' }
        }
        if (-not [string]::IsNullOrWhiteSpace($placeholder)) {
            [void]$values.Add($placeholder)
        }
    }

    return @($values)
}

function Get-WslcOptionValueCompletions {
    param(
        [object]$Option,
        [string]$Word,
        [string]$Prefix,
        [string]$Session
    )

    if ($null -eq $Option) {
        return @()
    }

    if ($Option.IsPath -or ($Option.ValueKind -eq 'path')) {
        return @([System.Management.Automation.CompletionCompleters]::CompleteFilename($Word))
    }

    if ($Option.ValueKind -eq 'volume' -and (Test-WslcPathLikeWord -Word $Word)) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $enums = @($Option.Enums)
    if ($enums.Count -gt 0) {
        Add-WslcFilteredResults -Results $results -Seen $seen -Candidates $enums -Word $Word -Prefix $Prefix -ResultType 'ParameterValue' -ToolTip $Option.Description
        return @($results.ToArray())
    }

    $kind = [string]$Option.ValueKind
    if ($kind -eq 'placeholder') {
        $candidates = @((Get-WslcPlaceholder -Name @($Option.Names)[-1]))
    }
    else {
        $candidates = @(Get-WslcKindValues -Kind $kind -Word $Word -Session $Session)
        if ($candidates.Count -eq 0 -and [string]::IsNullOrEmpty($Word)) {
            $candidates = @((Get-WslcPlaceholder -Name @($Option.Names)[-1]))
        }
    }

    Add-WslcFilteredResults -Results $results -Seen $seen -Candidates $candidates -Word $Word -Prefix $Prefix -ResultType 'ParameterValue' -ToolTip $Option.Description
    return @($results.ToArray())
}

function Get-WslcOperandCompletions {
    param(
        [object]$Catalog,
        [int]$OperandCount,
        [string]$Word,
        [string[]]$Path,
        [string]$Session
    )

    $operands = @($Catalog.Operands)
    $operand = $null
    if ($OperandCount -lt $operands.Count) {
        $operand = $operands[$OperandCount]
    }
    elseif ($operands.Count -gt 0 -and $operands[$operands.Count - 1].Repeating) {
        $operand = $operands[$operands.Count - 1]
    }

    if ($null -eq $operand) {
        $leaf = ''
        $pathList = @($Path)
        if ($pathList.Count -gt 0) {
            $leaf = [string]$pathList[$pathList.Count - 1]
        }

        if ($leaf -in @('inspect', 'logs', 'start', 'stop', 'kill', 'remove', 'restart', 'attach', 'exec', 'export', 'stats')) {
            $operand = [pscustomobject]@{ Name = 'container-id'; Kind = 'container'; IsPath = $false; Repeating = $true }
        }
        elseif ($leaf -in @('rmi', 'push', 'pull', 'tag', 'save')) {
            $operand = [pscustomobject]@{ Name = 'image'; Kind = 'image'; IsPath = $false; Repeating = $true }
        }
    }

    if ($null -eq $operand) {
        return @()
    }

    if ($operand.IsPath -or $operand.Kind -eq 'path') {
        return @([System.Management.Automation.CompletionCompleters]::CompleteFilename($Word))
    }

    $kind = [string]$operand.Kind
    $pathText = (@($Path) -join ' ')
    if ($kind -eq 'placeholder' -and $pathText -match '(^| )inspect$' -and $operand.Name -match 'object|id|name') {
        $kind = 'inspect'
    }

    $results = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $candidates = @(Get-WslcKindValues -Kind $kind -Word $Word -Session $Session)
    if ($candidates.Count -eq 0 -and [string]::IsNullOrEmpty($Word)) {
        $candidates = @((Get-WslcPlaceholder -Name $operand.Name))
    }

    Add-WslcFilteredResults -Results $results -Seen $seen -Candidates $candidates -Word $Word -Prefix '' -ResultType 'ParameterValue' -ToolTip $operand.Name
    return @($results.ToArray())
}

function Complete-Wslc {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $context = Get-WslcCompletionContext -CommandAst $commandAst -CursorPosition $cursorPosition
    if ($null -eq $context) {
        return @()
    }

    $word = if ($null -eq $wordToComplete) { '' } else { [string]$wordToComplete }
    $results = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    if ($context.Passthrough) {
        if ($word.StartsWith('-') -or (Test-WslcPathLikeWord -Word $word)) {
            return @()
        }

        return @(Get-WslcOperandCompletions -Catalog $context.Catalog -OperandCount $context.OperandCount -Word $word -Path $context.Path -Session $context.Session)
    }

    if ($word -match '^(?<name>--?[A-Za-z0-9?][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = Resolve-WslcOption -Catalog $context.Catalog -Name $Matches.name
        if ($null -ne $option -and $option.TakesValue) {
            return @(Get-WslcOptionValueCompletions -Option $option -Word $Matches.value -Prefix ($Matches.name + '=') -Session $context.Session)
        }

        return @()
    }

    if ($word.StartsWith('-')) {
        $pattern = [System.Management.Automation.WildcardPattern]::Escape($word) + '*'
        $shortWord = $word -match '^-[A-Za-z0-9?]$'
        foreach ($option in @($context.Catalog.Options)) {
            $matched = $false
            foreach ($name in @($option.Names)) {
                if ($name -clike $pattern) {
                    $matched = $true
                    break
                }
            }

            if (-not $matched) {
                continue
            }

            foreach ($name in @($option.Names)) {
                $include = $name -clike $pattern
                if (-not $include -and $shortWord -and $name.StartsWith('--')) {
                    $include = $true
                }

                if ($include -and $seen.Add($name)) {
                    $item = New-WslcCompletionResult -CompletionText $name -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $name
                    if ($null -ne $item) {
                        [void]$results.Add($item)
                    }
                }
            }
        }

        return @($results.ToArray())
    }

    if ($context.Previous.StartsWith('-') -and -not $context.Previous.Contains('=')) {
        $option = Resolve-WslcOption -Catalog $context.Catalog -Name $context.Previous
        if ($null -ne $option -and $option.TakesValue) {
            return @(Get-WslcOptionValueCompletions -Option $option -Word $word -Prefix '' -Session $context.Session)
        }
    }

    if (Test-WslcPathLikeWord -Word $word) {
        return @()
    }

    if ($context.OperandCount -eq 0) {
        foreach ($command in @($context.Catalog.Commands)) {
            if ($command.Name.StartsWith($word, [System.StringComparison]::Ordinal) -and $seen.Add($command.Name)) {
                $item = New-WslcCompletionResult -CompletionText $command.Name -ResultType 'ParameterValue' -ToolTip $command.Description -ListItemText $command.Name
                if ($null -ne $item) {
                    [void]$results.Add($item)
                }
            }
        }
    }

    foreach ($item in @(Get-WslcOperandCompletions -Catalog $context.Catalog -OperandCount $context.OperandCount -Word $word -Path $context.Path -Session $context.Session)) {
        if ($null -ne $item -and $seen.Add($item.CompletionText)) {
            [void]$results.Add($item)
        }
    }

    if ($context.OperandCount -eq 0) {
        $pattern = [System.Management.Automation.WildcardPattern]::Escape($word) + '*'
        foreach ($option in @($context.Catalog.Options)) {
            foreach ($name in @($option.Names)) {
                if ($name -clike $pattern -and $seen.Add($name)) {
                    $item = New-WslcCompletionResult -CompletionText $name -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $name
                    if ($null -ne $item) {
                        [void]$results.Add($item)
                    }
                }
            }
        }
    }

    return @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('wslc', 'wslc.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Wslc -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
