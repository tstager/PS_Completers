<#
.SYNOPSIS
Registers PowerShell tab completion for the local `pnpm` CLI.

.DESCRIPTION
Help-driven completer for pnpm 12, whose CLI is built on clap and prints a
long-form help page for every command and subcommand.

`pnpm --help` supplies the root command list (with aliases) and the universal
rc-options; `pnpm help <command> [<subcommand> ...]` supplies the same shape for
every deeper node. Each parsed page is cached in script scope for the session,
including the negative result, so a missing or failing pnpm costs one probe.

Option values are completed from the help page itself: clap's
`[possible values: ...]` lists and `Possible values:` blocks become enum
completions, `<DIR>` slots become directory completions, and everything else
becomes a `<PLACEHOLDER>` so the engine's filename fallback does not take over a
non-path slot. Both the separate (`--reporter silent`) and the attached
(`--reporter=silent`) forms are handled.

Three operand slots have live values: `run` script names and the dependency names
of `remove` / `why` / `update` / `unlink` come from the nearest package.json, and
config keys for `config get|set|delete` and `get` / `set` come from
`pnpm config list --json`.

This script registers completion for `pnpm`, `pnpm.cmd`, `pnpm.ps1`, and the
`pn` short alias, matching the names pnpm's own completion script registers.
#>

Set-StrictMode -Version Latest

if (-not (Get-Variable -Name PnpmCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:PnpmCompletionCache = @{
        ExecutableProbed = $false
        ExecutablePath   = $null
        Catalogs         = @{}
        Manifests        = @{}
        ConfigKeys       = @{}
    }
}

function Get-PnpmCompletionCache {
    $script:PnpmCompletionCache
}

function Get-PnpmExecutablePath {
    $cache = Get-PnpmCompletionCache
    if ($cache.ExecutableProbed) {
        return $cache.ExecutablePath
    }

    $cache.ExecutableProbed = $true
    $cache.ExecutablePath = $null

    foreach ($candidate in @(
            @{ Name = 'pnpm.cmd'; CommandType = 'Application' }
            @{ Name = 'pnpm'; CommandType = 'Application' }
            @{ Name = 'pnpm.ps1'; CommandType = 'ExternalScript' }
        )) {
        $command = @(Get-Command -Name $candidate.Name -CommandType $candidate.CommandType -ErrorAction Ignore) |
            Select-Object -First 1

        if ($null -eq $command) {
            continue
        }

        $cache.ExecutablePath = if ($command.Source) { $command.Source } else { $command.Path }
        break
    }

    $cache.ExecutablePath
}

function Get-PnpmHelpText {
    param([string[]]$CommandPath)

    $executablePath = Get-PnpmExecutablePath
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        return ''
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    [void]$arguments.Add('help')
    foreach ($segment in @($CommandPath)) {
        if (-not [string]::IsNullOrWhiteSpace($segment)) {
            [void]$arguments.Add($segment)
        }
    }

    try {
        $helpText = $null | & $executablePath @arguments 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String
    } catch {
        return ''
    }

    if ([string]::IsNullOrWhiteSpace($helpText)) {
        return ''
    }

    $helpText
}

function New-PnpmCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ListItemText,
        [System.Management.Automation.CompletionResultType]$ResultType,
        [string]$ToolTip
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

function Get-PnpmValueKind {
    param([string]$ValueName)

    if ([string]::IsNullOrWhiteSpace($ValueName)) {
        return 'None'
    }

    if ($ValueName -match '(?i)(^|_)dir$') {
        return 'Directory'
    }

    if ($ValueName -match '(?i)(^|_)(file|path)$') {
        return 'File'
    }

    'Text'
}

function ConvertFrom-PnpmHelpText {
    param([string]$HelpText)

    $commands = New-Object System.Collections.Generic.List[object]
    $options = New-Object System.Collections.Generic.List[object]
    $commandSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

    if ([string]::IsNullOrWhiteSpace($HelpText)) {
        return [pscustomobject]@{ Commands = @(); Options = @() }
    }

    $section = ''
    $current = $null
    $inPossibleValuesBlock = $false

    foreach ($line in [regex]::Split($HelpText, '\r?\n')) {
        if ($line -match '^(?<name>[A-Za-z][A-Za-z ]*):\s*$') {
            $section = $Matches.name
            $current = $null
            $inPossibleValuesBlock = $false
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $indent = $line.Length - $line.TrimStart(' ').Length
        $trimmed = $line.Trim()

        if ($section -eq 'Commands') {
            # Command rows are indented two spaces: "  add   Add a package [alias: a]".
            if ($indent -le 6 -and $line -match '^\s{2,}(?<name>[A-Za-z0-9][A-Za-z0-9_.-]*)(?:\s{2,}(?<description>\S.*))?$') {
                $name = $Matches.name
                $description = if ($Matches.ContainsKey('description')) { $Matches.description } else { '' }

                $aliases = New-Object System.Collections.Generic.List[string]
                if ($description -match '\[alias(?:es)?:\s*(?<list>[^\]]+)\]') {
                    foreach ($alias in ($Matches.list -split ',')) {
                        $aliasName = $alias.Trim()
                        if (-not [string]::IsNullOrWhiteSpace($aliasName)) {
                            [void]$aliases.Add($aliasName)
                        }
                    }
                }

                foreach ($spelling in @(@($name) + $aliases.ToArray())) {
                    if ($commandSeen.Add($spelling)) {
                        [void]$commands.Add([pscustomobject]@{
                                Name          = $spelling
                                CanonicalName = $name
                                Description   = $description
                            })
                    }
                }
            }

            continue
        }

        if ($section -ne 'Options') {
            continue
        }

        # Option definition rows are indented at most six spaces and start with a dash;
        # descriptions and clap metadata are indented ten or more.
        if ($indent -le 6 -and $trimmed.StartsWith('-')) {
            $spellings = @(
                [regex]::Matches($trimmed, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)') |
                    ForEach-Object { $_.Value }
            )

            if ($spellings.Count -eq 0) {
                $current = $null
                $inPossibleValuesBlock = $false
                continue
            }

            $valueName = ''
            if ($trimmed -match '<(?<value>[^>]+)>') {
                $valueName = $Matches.value
            }

            $current = [pscustomobject]@{
                Names        = [string[]]$spellings
                ValueName    = $valueName
                ValueKind    = (Get-PnpmValueKind -ValueName $valueName)
                AttachedOnly = ($trimmed -match '\[=<')
                ValueList    = (New-Object System.Collections.Generic.List[object])
                Description  = ''
            }

            [void]$options.Add($current)
            $inPossibleValuesBlock = $false
            continue
        }

        if ($null -eq $current) {
            continue
        }

        if ($inPossibleValuesBlock) {
            if ($trimmed -match '^-\s+(?<name>[^:\s]+):\s*(?<description>.*)$') {
                [void]$current.ValueList.Add([pscustomobject]@{ Name = $Matches.name; Description = $Matches.description.Trim() })
                continue
            }

            $inPossibleValuesBlock = $false
        }

        if ($trimmed -match '^Possible values:$') {
            $inPossibleValuesBlock = $true
            continue
        }

        if ($trimmed -match '^\[possible values:\s*(?<list>[^\]]+)\]$') {
            foreach ($value in ($Matches.list -split ',')) {
                $valueText = $value.Trim()
                if (-not [string]::IsNullOrWhiteSpace($valueText)) {
                    [void]$current.ValueList.Add([pscustomobject]@{ Name = $valueText; Description = '' })
                }
            }

            continue
        }

        if ($trimmed -match '^\[alias(?:es)?:\s*(?<list>[^\]]+)\]$') {
            $extra = New-Object System.Collections.Generic.List[string]
            $extra.AddRange([string[]]$current.Names)
            foreach ($alias in ($Matches.list -split ',')) {
                $aliasName = $alias.Trim()
                if ($aliasName -match '^--?[A-Za-z0-9]') {
                    [void]$extra.Add($aliasName)
                }
            }

            $current.Names = [string[]]$extra.ToArray()
            continue
        }

        if ($trimmed.StartsWith('[')) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($current.Description)) {
            $current.Description = $trimmed
        }
    }

    [pscustomobject]@{
        Commands = @($commands.ToArray())
        Options  = @($options.ToArray())
    }
}

function Get-PnpmCatalog {
    param([string[]]$CommandPath)

    $cache = Get-PnpmCompletionCache
    $segments = @(@($CommandPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $key = if ($segments.Count -gt 0) { $segments -join ' ' } else { '<root>' }

    if ($cache.Catalogs.ContainsKey($key)) {
        return $cache.Catalogs[$key]
    }

    $catalog = ConvertFrom-PnpmHelpText -HelpText (Get-PnpmHelpText -CommandPath $segments)
    $cache.Catalogs[$key] = $catalog
    $catalog
}

function Find-PnpmOption {
    param(
        [object]$Catalog,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    foreach ($option in @($Catalog.Options)) {
        foreach ($spelling in $option.Names) {
            if ([string]::Equals($spelling, $Name, [System.StringComparison]::Ordinal)) {
                return $option
            }
        }
    }

    $null
}

function Test-PnpmOptionTakesValue {
    param([object]$Option)

    $null -ne $Option -and -not [string]::IsNullOrWhiteSpace($Option.ValueName) -and -not $Option.AttachedOnly
}

function Get-PnpmArgumentToken {
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

        # Offsets from the AST and $cursorPosition are both absolute in the input
        # line. A token that ends at or after the cursor is the word being
        # completed, not a settled argument.
        if ($element.Extent.EndOffset -ge $CursorPosition) {
            continue
        }

        $text = $element.Extent.Text
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            [void]$tokens.Add($text.Trim())
        }
    }

    @($tokens.ToArray())
}

function Get-PnpmCurrentWord {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The word as typed, quotes included: $wordToComplete drops the quote inside an
    # attached --opt='value. The parser keeps an unterminated quoted word as one
    # element running to the cursor.
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
    }

    ''
}

function Resolve-PnpmCommandPath {
    param([string[]]$Tokens)

    $path = New-Object System.Collections.Generic.List[string]
    $catalog = Get-PnpmCatalog -CommandPath @()
    $skipNext = $false
    $operandCount = 0

    foreach ($token in @($Tokens)) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }

        if ($token.StartsWith('-')) {
            if ($token.Contains('=')) {
                continue
            }

            $option = Find-PnpmOption -Catalog $catalog -Name $token
            if (Test-PnpmOptionTakesValue -Option $option) {
                $skipNext = $true
            }

            continue
        }

        # Once the first operand is seen, every later word is an operand too.
        $match = $null
        if ($operandCount -eq 0) {
            foreach ($command in @($catalog.Commands)) {
                if ([string]::Equals($command.Name, $token, [System.StringComparison]::Ordinal)) {
                    $match = $command
                    break
                }
            }
        }

        if ($null -eq $match) {
            $operandCount++
            continue
        }

        [void]$path.Add($match.CanonicalName)
        $catalog = Get-PnpmCatalog -CommandPath @($path.ToArray())
    }

    [pscustomobject]@{
        Path         = @($path.ToArray())
        Catalog      = $catalog
        OperandCount = $operandCount
    }
}

function Get-PnpmWorkingDirectory {
    param([string[]]$Tokens)

    $location = Get-Location
    if ($location.Provider.Name -ne 'FileSystem') {
        return $null
    }

    # -C / --dir is accepted anywhere on the command line; the last one wins.
    $directory = ''
    $settled = @($Tokens)
    for ($index = 0; $index -lt $settled.Count; $index++) {
        $token = $settled[$index]
        if ($token -ceq '-C' -or $token -ceq '--dir') {
            if ($index + 1 -lt $settled.Count) {
                $index++
                $directory = $settled[$index]
            }
        } elseif ($token.StartsWith('--dir=', [System.StringComparison]::Ordinal)) {
            $directory = $token.Substring(6)
        }
    }

    $directory = ConvertFrom-PnpmTypedWord -Value $directory
    if ([string]::IsNullOrWhiteSpace($directory)) {
        return $location.ProviderPath
    }

    [System.IO.Path]::GetFullPath($directory, $location.ProviderPath)
}

function Get-PnpmManifestName {
    param(
        [string]$Directory,
        [ValidateSet('Scripts', 'Dependencies')]
        [string]$Kind
    )

    # The nearest package.json walking up from the working directory is the
    # project pnpm acts on. It is read passively and re-parsed only when its
    # timestamp changes.
    $manifestPath = $null
    $current = $Directory
    while (-not [string]::IsNullOrEmpty($current)) {
        $candidate = [System.IO.Path]::Combine($current, 'package.json')
        if ([System.IO.File]::Exists($candidate)) {
            $manifestPath = $candidate
            break
        }

        $current = [System.IO.Path]::GetDirectoryName($current)
    }

    if ($null -eq $manifestPath) {
        return @()
    }

    $cache = Get-PnpmCompletionCache
    $stamp = [System.IO.File]::GetLastWriteTimeUtc($manifestPath)
    $entry = $cache.Manifests[$manifestPath]
    if ($null -eq $entry -or $entry.Stamp -ne $stamp) {
        $scripts = New-Object System.Collections.Generic.List[object]
        $dependencies = New-Object System.Collections.Generic.List[object]
        $errorCountBefore = $Error.Count
        try {
            $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($manifest -is [System.Collections.IDictionary]) {
                if ($manifest['scripts'] -is [System.Collections.IDictionary]) {
                    foreach ($name in $manifest['scripts'].Keys) {
                        [void]$scripts.Add([pscustomobject]@{ Name = [string]$name; ToolTip = "${name}: $($manifest['scripts'][$name])" })
                    }
                }

                foreach ($group in @('dependencies', 'devDependencies', 'optionalDependencies')) {
                    if ($manifest[$group] -is [System.Collections.IDictionary]) {
                        foreach ($name in $manifest[$group].Keys) {
                            [void]$dependencies.Add([pscustomobject]@{ Name = [string]$name; ToolTip = "$group ${name}@$($manifest[$group][$name])" })
                        }
                    }
                }
            }
        } catch {
            Write-Debug "pnpm completer: cannot parse ${manifestPath}: $($_.Exception.Message)"
        } finally {
            # A package.json mid-edit is an expected miss, not a fault to leave in $Error.
            while ($Error.Count -gt $errorCountBefore) {
                $Error.RemoveAt(0)
            }
        }

        $entry = [pscustomobject]@{
            Stamp        = $stamp
            Scripts      = @($scripts.ToArray())
            Dependencies = @($dependencies.ToArray())
        }
        $cache.Manifests[$manifestPath] = $entry
    }

    @($entry.$Kind)
}

function Get-PnpmConfigKey {
    param([string]$Directory)

    $executablePath = Get-PnpmExecutablePath
    if ([string]::IsNullOrWhiteSpace($executablePath) -or -not [System.IO.Directory]::Exists($Directory)) {
        return @()
    }

    # The key set changes with the project's .npmrc / pnpm-workspace.yaml and with
    # `pnpm config set`, so it is cached per launcher and directory for 30 seconds.
    $cache = Get-PnpmCompletionCache
    $cacheKey = "$executablePath|$Directory"
    $entry = $cache.ConfigKeys[$cacheKey]
    if ($null -ne $entry -and ([datetime]::UtcNow - $entry.LoadedAt).TotalSeconds -lt 30) {
        return @($entry.Keys)
    }

    # `config list` is read-only and, unlike most commands, does not switch to the
    # project's pinned packageManager version, so it never reaches the network.
    # Stdin is closed, output is drained asynchronously and a hung child is killed.
    $output = ''
    $process = [System.Diagnostics.Process]::new()
    try {
        $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($executablePath)
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.WorkingDirectory = $Directory
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        foreach ($argument in @('config', 'list', '--json')) {
            [void]$process.StartInfo.ArgumentList.Add($argument)
        }

        [void]$process.Start()
        $process.StandardInput.Close()
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()

        if ($process.WaitForExit(5000)) {
            $output = $standardOutput.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', ''
            [void]$standardError.GetAwaiter().GetResult()
        } else {
            $process.Kill($true)
        }
    } catch {
        $output = ''
    } finally {
        $process.Dispose()
    }

    # Only key names are kept; values (auth tokens among them) are never emitted.
    $keys = New-Object System.Collections.Generic.List[object]
    if (-not [string]::IsNullOrWhiteSpace($output)) {
        $errorCountBefore = $Error.Count
        try {
            $config = $output | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($config -is [System.Collections.IDictionary]) {
                foreach ($name in $config.Keys) {
                    [void]$keys.Add([pscustomobject]@{ Name = [string]$name; ToolTip = "pnpm config key $name" })
                }
            }
        } catch {
            Write-Debug "pnpm completer: cannot parse 'pnpm config list --json': $($_.Exception.Message)"
        } finally {
            while ($Error.Count -gt $errorCountBefore) {
                $Error.RemoveAt(0)
            }
        }
    }

    $cache.ConfigKeys[$cacheKey] = [pscustomobject]@{
        LoadedAt = [datetime]::UtcNow
        Keys     = @($keys.ToArray())
    }
    @($keys.ToArray())
}

function ConvertFrom-PnpmTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    $tokens[0].Value
}

function Get-PnpmTypedQuote {
    param([string]$Value)

    if ($Value -match '^[''"\u2018-\u201E]') { $Value.Substring(0, 1) } else { '' }
}

function ConvertTo-PnpmQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default). PowerShell reads ' and
    # U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes.
    param(
        [string]$Value,
        [string]$Quote
    )

    if ([string]::IsNullOrEmpty($Quote)) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -match '^[''\u2018-\u201B]$') {
        return $Quote + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $Quote
    }

    $Quote + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $Quote
}

function Get-PnpmOperandCompletion {
    param(
        [object[]]$Candidates,
        [string]$WordToComplete
    )

    # An opening quote the user typed is kept on the inserted text.
    $quote = Get-PnpmTypedQuote -Value $WordToComplete
    $word = ConvertFrom-PnpmTypedWord -Value $WordToComplete

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($Candidates)) {
        if ($candidate.Name.StartsWith($word, [System.StringComparison]::OrdinalIgnoreCase)) {
            $completionText = ConvertTo-PnpmQuotedValue -Value $candidate.Name -Quote $quote
            [void]$results.Add((New-PnpmCompletionResult -CompletionText $completionText -ListItemText $candidate.Name -ResultType ParameterValue -ToolTip $candidate.ToolTip))
        }
    }

    @($results.ToArray())
}

function Get-PnpmPathCompletion {
    param(
        [string]$WordToComplete,
        [string]$Prefix,
        [switch]$Directory
    )

    $quote = Get-PnpmTypedQuote -Value $WordToComplete
    $container = [System.Management.Automation.CompletionResultType]::ProviderContainer

    # CompleteFilename quotes for PowerShell and wildcard-escapes for -Path parameters
    # (tick``x.txt). pnpm takes literal paths, so each result is unwrapped by the parser
    # and unescaped, then quoted once in the style the user typed.
    $items = foreach ($item in @([System.Management.Automation.CompletionCompleters]::CompleteFilename((ConvertFrom-PnpmTypedWord -Value $WordToComplete)))) {
        $path = $item.CompletionText
        if ($path -match '^[''"\u2018-\u201E]') {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($path, [ref]$null, [ref]$null)
            $constant = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
            if ($constant) {
                $path = $constant.Value
            }
        }

        $path = [System.Management.Automation.WildcardPattern]::Unescape($path)
        if ($item.ResultType -eq $container -and -not $path.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $path += [System.IO.Path]::DirectorySeparatorChar
        }

        [pscustomobject]@{ Path = $path; ListItemText = $item.ListItemText; ResultType = $item.ResultType; ToolTip = $item.ToolTip }
    }

    # A <DIR> slot offers directories. When none match, the files are offered as the
    # engine's own fallback would, but quoted for a literal path.
    if ($Directory) {
        $directories = @($items | Where-Object { $_.ResultType -eq $container })
        if ($directories.Count -gt 0) {
            $items = $directories
        }
    }

    foreach ($item in @($items)) {
        New-PnpmCompletionResult -CompletionText ($Prefix + (ConvertTo-PnpmQuotedValue -Value $item.Path -Quote $quote)) -ListItemText $item.ListItemText -ResultType $item.ResultType -ToolTip $item.ToolTip
    }
}

function Get-PnpmOptionValueCompletion {
    param(
        [object]$Option,
        [string]$WordToComplete,
        [string]$Prefix
    )

    $results = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Option) {
        return @()
    }

    # .ToArray() is deliberate: @() over a List[object] throws on PowerShell 7.6.
    $values = @($Option.ValueList.ToArray())
    if ($values.Count -gt 0) {
        $quote = Get-PnpmTypedQuote -Value $WordToComplete
        $typedValue = ConvertFrom-PnpmTypedWord -Value $WordToComplete
        foreach ($value in $values) {
            if ($value.Name.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                $toolTip = if ([string]::IsNullOrWhiteSpace($value.Description)) { "$($Option.Names[-1]) $($value.Name)" } else { $value.Description }
                [void]$results.Add((New-PnpmCompletionResult -CompletionText ($Prefix + (ConvertTo-PnpmQuotedValue -Value $value.Name -Quote $quote)) -ListItemText $value.Name -ResultType ParameterValue -ToolTip $toolTip))
            }
        }

        return @($results.ToArray())
    }

    if ($Option.ValueKind -eq 'Directory') {
        return @(Get-PnpmPathCompletion -WordToComplete $WordToComplete -Prefix $Prefix -Directory)
    }

    if ($Option.ValueKind -eq 'File') {
        return @(Get-PnpmPathCompletion -WordToComplete $WordToComplete -Prefix $Prefix)
    }

    if ([string]::IsNullOrEmpty($WordToComplete)) {
        $placeholder = "<$($Option.ValueName)>"
        [void]$results.Add((New-PnpmCompletionResult -CompletionText ($Prefix + $placeholder) -ListItemText $placeholder -ResultType ParameterValue -ToolTip $Option.Description))
    }

    @($results.ToArray())
}

function Get-PnpmOptionNameCompletion {
    param(
        [object]$Catalog,
        [string]$WordToComplete
    )

    $results = New-Object System.Collections.Generic.List[object]
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*'

    foreach ($option in @($Catalog.Options)) {
        foreach ($spelling in $option.Names) {
            if ($spelling -clike $pattern) {
                $toolTip = if ([string]::IsNullOrWhiteSpace($option.Description)) { $spelling } else { $option.Description }
                if (-not [string]::IsNullOrWhiteSpace($option.ValueName)) {
                    $toolTip = "$toolTip [<$($option.ValueName)>]"
                }

                [void]$results.Add((New-PnpmCompletionResult -CompletionText $spelling -ListItemText $spelling -ResultType ParameterName -ToolTip $toolTip))
            }
        }
    }

    @($results.ToArray())
}

function Get-PnpmCommandCompletion {
    param(
        [object]$Catalog,
        [string[]]$Path,
        [string]$WordToComplete
    )

    $results = New-Object System.Collections.Generic.List[object]
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*'
    $prefix = @(@('pnpm') + @($Path)) -join ' '

    foreach ($command in @($Catalog.Commands)) {
        if ($command.Name -like $pattern) {
            $toolTip = if ([string]::IsNullOrWhiteSpace($command.Description)) { "$prefix $($command.Name)" } else { $command.Description }
            [void]$results.Add((New-PnpmCompletionResult -CompletionText $command.Name -ListItemText $command.Name -ResultType ParameterValue -ToolTip $toolTip))
        }
    }

    @($results.ToArray())
}

function Invoke-PnpmCompletion {
    [CmdletBinding()]
    [OutputType([System.Object[]], [System.Array])]
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $word = Get-PnpmCurrentWord -CommandAst $CommandAst -CursorPosition $CursorPosition
    $tokens = @(Get-PnpmArgumentToken -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $resolved = Resolve-PnpmCommandPath -Tokens $tokens
    $catalog = $resolved.Catalog

    # Attached form: --reporter=sil
    if ($word -match '^(?<name>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = Find-PnpmOption -Catalog $catalog -Name $Matches.name
        if ($null -ne $option -and -not [string]::IsNullOrWhiteSpace($option.ValueName)) {
            return @(Get-PnpmOptionValueCompletion -Option $option -WordToComplete $Matches.value -Prefix "$($Matches.name)=")
        }

        return @()
    }

    if ($word.StartsWith('-')) {
        return @(Get-PnpmOptionNameCompletion -Catalog $catalog -WordToComplete $word)
    }

    # Separate form: the settled token before the cursor is a value-bearing option.
    $previous = if ($tokens.Count -gt 0) { $tokens[-1] } else { '' }
    if ($previous.StartsWith('-') -and -not $previous.Contains('=')) {
        $option = Find-PnpmOption -Catalog $catalog -Name $previous
        if (Test-PnpmOptionTakesValue -Option $option) {
            return @(Get-PnpmOptionValueCompletion -Option $option -WordToComplete $word -Prefix '')
        }
    }

    # Operands with a live value source: the script name for `run`, dependency
    # names for the commands that act on installed packages, and the config key.
    $operands = switch -CaseSensitive ($resolved.Path -join ' ') {
        'run' { if ($resolved.OperandCount -eq 0) { 'Scripts' } }
        { $_ -cin @('remove', 'why', 'update', 'unlink') } { 'Dependencies' }
        { $_ -cin @('get', 'set','config get', 'config set', 'config delete') } { if ($resolved.OperandCount -eq 0) { 'ConfigKeys' } }
    }

    if ($null -ne $operands) {
        $directory = Get-PnpmWorkingDirectory -Tokens $tokens
        if ($null -eq $directory) {
            return @()
        }

        $candidates = if ($operands -eq 'ConfigKeys') {
            Get-PnpmConfigKey -Directory $directory
        } else {
            Get-PnpmManifestName -Directory $directory -Kind $operands
        }

        return @(Get-PnpmOperandCompletion -Candidates @($candidates) -WordToComplete $word)
    }

    # A pnpm node either dispatches to subcommands or takes operands. When it takes
    # operands, return nothing so the engine's own path completion runs.
    @(Get-PnpmCommandCompletion -Catalog $catalog -Path $resolved.Path -WordToComplete $word)
}

Register-ArgumentCompleter -Native -CommandName @('pnpm', 'pnpm.cmd', 'pnpm.ps1', 'pn') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-PnpmCompletion -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
