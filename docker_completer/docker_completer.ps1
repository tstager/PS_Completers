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

function Get-DockerHelpText {
    param([string[]]$Segments)

    $commandPath = Get-DockerExecutablePath
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return ''
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    foreach ($segment in @($Segments)) {
        if (-not [string]::IsNullOrWhiteSpace($segment)) {
            [void]$arguments.Add($segment)
        }
    }

    [void]$arguments.Add('--help')

    # A CLI plugin that hangs must not hang the prompt: standard input is closed
    # immediately and the child is killed if it outlives the budget.
    $helpText = ''
    $process = [System.Diagnostics.Process]::new()
    try {
        $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($commandPath)
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        foreach ($argument in $arguments) {
            [void]$process.StartInfo.ArgumentList.Add($argument)
        }

        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()

        if ($process.WaitForExit(4000)) {
            $helpText = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
        } else {
            $process.Kill($true)
        }
    } catch {
        $helpText = ''
    } finally {
        $process.Dispose()
    }

    return $helpText
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
            if ($indent -ge 2 -and $indent -le 6 -and $line -match '^\s{2,}(?<name>[A-Za-z0-9][A-Za-z0-9_-]*)\*?(?:\s{2,}(?<description>\S.*))?$') {
                $name = $Matches.name
                $description = if ($Matches.ContainsKey('description')) { $Matches.description } else { '' }
                if ($commandSeen.Add($name)) {
                    [void]$commands.Add([pscustomobject]@{ Name = $name; Description = $description })
                }
            }

            continue
        }

        if ($section -ne 'Options') {
            continue
        }

        # Option rows start at column 2 or 6. Wrapped description lines are indented
        # to the description column, so they can never be mistaken for definitions.
        if ($indent -le 6 -and $trimmed.StartsWith('-')) {
            $names = New-Object System.Collections.Generic.List[string]
            foreach ($match in [regex]::Matches($trimmed, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(?:\s|,|=|$))')) {
                $value = $match.Value
                if (-not $names.Contains($value)) {
                    [void]$names.Add($value)
                }
            }

            if ($names.Count -eq 0) {
                $current = $null
                continue
            }

            $lastName = $names[$names.Count - 1]
            $remainder = $trimmed.Substring($trimmed.IndexOf($lastName) + $lastName.Length)
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
        if ($option.Names -contains '--help' -or $option.Names -contains '-h') {
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

    return [pscustomobject]@{
        Commands = @($commands.ToArray())
        Options  = @($options.ToArray())
        Operands = @(Get-DockerUsageOperand -UsageLines @($usageLines.ToArray()))
    }
}

function Get-DockerUsageOperand {
    param([string[]]$UsageLines)

    $operands = New-Object System.Collections.Generic.List[object]

    foreach ($usage in @($UsageLines)) {
        if ($usage -notmatch '(?i)^\s*docker(?:\.exe)?\b(?<rest>.*)$') {
            continue
        }

        foreach ($token in ($Matches.rest -split '\s+')) {
            $name = $token.Trim().Trim('[', ']', '|').TrimEnd('.')
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            if ($name -cmatch '^[A-Z][A-Z0-9_]*$' -and $name -notin @('OPTIONS', 'COMMAND', 'ARG', 'SUBCOMMAND')) {
                [void]$operands.Add([pscustomobject]@{
                        Name   = $name
                        IsPath = ($name -match '(?i)(PATH|URL|FILE|DIR|DIRECTORY)$')
                    })
            }
        }

        break
    }

    return @($operands.ToArray())
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
        [string]$Prefix
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

    $prefix = if ($null -eq $wordToComplete) { '' } else { $wordToComplete }
    $results = New-Object System.Collections.Generic.List[object]
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($prefix) + '*'

    # Attached form: --log-level=de
    if ($prefix -match '^(?<name>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = Find-DockerOption -Catalog $context.Catalog -Name $Matches.name
        if ($null -ne $option -and $option.TakesValue) {
            return @(Get-DockerOptionValueCompletion -Option $option -WordToComplete $Matches.value -Prefix "$($Matches.name)=")
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
            return @(Get-DockerOptionValueCompletion -Option $option -WordToComplete $prefix -Prefix '')
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
    # a placeholder so the slot does not silently fill with unrelated file names.
    if ([string]::IsNullOrEmpty($prefix)) {
        $operands = @($context.Catalog.Operands)
        if ($context.OperandCount -lt $operands.Count) {
            $operand = $operands[$context.OperandCount]
            if (-not $operand.IsPath) {
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
