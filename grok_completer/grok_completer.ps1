# grok tab completion for PowerShell
# Help-driven native completer for grok and grok.exe.

Set-StrictMode -Version 2.0

function New-GrokCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Get-GrokCommandPath {
    foreach ($candidate in @('grok', 'grok.exe')) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -ne $command) {
            return $command.Source
        }
    }
}

function Invoke-GrokHelpCapture {
    param(
        [string]$CommandPath,
        [string[]]$Arguments
    )

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $CommandPath
        foreach ($argument in $Arguments) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $process.StandardInput.Close()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) {
                try { $process.Kill($true) } catch { Write-Debug -Message $_.Exception.Message }
                return ''
            }

            return $outputTask.Result + $errorTask.Result
        } finally {
            $process.Dispose()
        }
    } catch {
        return ''
    }
}

function Get-GrokRootHelpOutput {
    $commandPath = Get-GrokCommandPath
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return ''
    }

    return Invoke-GrokHelpCapture -CommandPath $commandPath -Arguments @('--help')
}

function Get-GrokSubcommandHelpOutput {
    param([string[]]$SubcommandPath)

    $commandPath = Get-GrokCommandPath
    if ([string]::IsNullOrWhiteSpace($commandPath) -or @($SubcommandPath).Count -eq 0) {
        return ''
    }

    return Invoke-GrokHelpCapture -CommandPath $commandPath -Arguments (@('help') + @($SubcommandPath))
}

function Get-GrokValueKind {
    param(
        [string]$Metavar,
        [string]$Description,
        [string[]]$Values
    )

    if (@($Values).Count -gt 0) {
        return 'Enum'
    }

    if ([string]::IsNullOrWhiteSpace($Metavar)) {
        return 'None'
    }

    if ($Metavar -match '^(CWD|DIR|DIRECTORY|FOLDER)$' -or $Metavar -match '_DIR$' -or $Description -match '\bdirectory\b') {
        return 'Directory'
    }

    if ($Metavar -match '^(FILE|PATH|FILES|PATHS)$' -or $Metavar -match '_(FILE|PATH)$' -or $Description -match '\bfile\b') {
        return 'Path'
    }

    return 'Text'
}

function ConvertFrom-GrokHelp {
    param([string]$HelpText)

    $lines = @([regex]::Split($HelpText, '\r?\n'))
    $options = New-Object System.Collections.Generic.List[object]
    $subcommands = New-Object System.Collections.Generic.List[string]
    $arguments = New-Object System.Collections.Generic.List[object]
    $optionByName = @{}
    $subcommandAliases = @{}

    # Group the help into entries: each entry is a head line plus every
    # following line that belongs to it (clap prints both the one-line and
    # the long, blank-line separated layouts, sometimes mixed in one page).
    $entries = New-Object System.Collections.Generic.List[object]
    $section = ''
    $current = $null

    foreach ($rawLine in $lines) {
        $line = $rawLine.TrimEnd()

        if ($line -match '^(Commands|Options|Arguments|Usage):\s*(.*)$') {
            if ($null -ne $current) { [void]$entries.Add($current); $current = $null }
            $section = $Matches[1]
            continue
        }

        if ($section -eq '' -or $section -eq 'Usage') {
            continue
        }

        if ($line -match '^\S') {
            if ($null -ne $current) { [void]$entries.Add($current); $current = $null }
            $section = ''
            continue
        }

        $startsEntry = switch ($section) {
            'Options' { $line -match '^\s{2,7}-\S' }
            'Arguments' { $line -match '^\s{2}[<\[]' }
            default { $line -match '^\s{2}\S' -and $line -notmatch '^\s{3}' }
        }

        if ($startsEntry) {
            if ($null -ne $current) { [void]$entries.Add($current) }
            $current = [pscustomobject]@{ Section = $section; Head = $line; Body = New-Object System.Collections.Generic.List[string] }
            continue
        }

        if ($null -ne $current) {
            [void]$current.Body.Add($line)
        }
    }

    if ($null -ne $current) { [void]$entries.Add($current) }

    foreach ($entry in $entries) {
        $head = $entry.Head
        $bodyText = ''
        $bulletValues = New-Object System.Collections.Generic.List[string]
        $inPossibleValues = $false

        foreach ($bodyLine in $entry.Body) {
            $trimmed = $bodyLine.Trim()
            if ($trimmed -match '^Possible values:') {
                $inPossibleValues = $true
                continue
            }

            if ($inPossibleValues) {
                if ($trimmed -match '^-\s+([^:\s]+)') {
                    [void]$bulletValues.Add($Matches[1])
                    continue
                }

                if ($trimmed -eq '') {
                    continue
                }

                if ($trimmed -notmatch '^\[') {
                    $inPossibleValues = $false
                }
            }

            if ($trimmed -ne '') {
                $bodyText = if ($bodyText) { "$bodyText $trimmed" } else { $trimmed }
            }
        }

        $fullText = ($head.Trim() + ' ' + $bodyText).Trim()

        $values = @()
        if ($bulletValues.Count -gt 0) {
            $values = @($bulletValues.ToArray())
        } elseif ($fullText -match '\[possible values:\s*([^\]]+)\]') {
            $values = @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        $aliases = @()
        if ($fullText -match '\[aliases:\s*([^\]]+)\]') {
            $aliases = @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        switch ($entry.Section) {
            'Commands' {
                if ($head -match '^\s{2}([A-Za-z0-9][A-Za-z0-9-]*)\s*(.*)$') {
                    $subName = $Matches[1]
                    if ($subName -ne 'help') {
                        [void]$subcommands.Add($subName)
                        foreach ($alias in $aliases) {
                            $subcommandAliases[$alias] = $subName
                        }
                    }
                }
            }
            'Arguments' {
                if ($head -match '^\s{2}(<[^>]+>|\[[^\]]+\])(\.\.\.)?(?:\s{2,}(.*))?$') {
                    $argName = $Matches[1]
                    $description = if ($Matches[3]) { $Matches[3].Trim() } else { '' }
                    if ($bodyText) {
                        $description = if ($description) { "$description $bodyText" } else { $bodyText }
                    }

                    [void]$arguments.Add([pscustomobject]@{
                        Name = $argName
                        Values = @($values)
                        Description = ($description -replace '\s*\[possible values:[^\]]*\]', '')
                    })
                }
            }
            'Options' {
                if ($head -match '^\s{2,7}(-[^\s<\[,]+(?:,\s+-[^\s<\[,]+)*)(?:\s+(?:<([^>]+)>|\[<([^>]+)>\]))?(?:\s{2,}(\S.*))?$') {
                    $optionNames = @($Matches[1] -split ',\s*' | ForEach-Object { $_.Trim().TrimEnd('.') } | Where-Object { $_ })
                    $metavar = if ($Matches[2]) { $Matches[2] } elseif ($Matches[3]) { $Matches[3] } else { '' }
                    $optionalValue = [bool]$Matches[3]
                    $description = if ($Matches[4]) { $Matches[4].Trim() } else { '' }
                    if ($bodyText) {
                        $description = if ($description) { "$description $bodyText" } else { $bodyText }
                    }

                    $description = $description -replace '\s*\[(possible values|aliases|default|env):[^\]]*\]', ''

                    $compatAliases = @([regex]::Matches($description, 'compat alias:\s*(--?[A-Za-z0-9][A-Za-z0-9-]*)') | ForEach-Object { $_.Groups[1].Value })
                    $allAliases = @($aliases + $compatAliases | Where-Object { $_ -match '^--?[A-Za-z0-9]' })

                    $valueKind = Get-GrokValueKind -Metavar $metavar -Description $description -Values $values
                    $hasValue = -not [string]::IsNullOrWhiteSpace($metavar)

                    foreach ($optionName in $optionNames) {
                        $spec = [pscustomobject]@{
                            Name = $optionName
                            TakesValue = $hasValue
                            OptionalValue = $optionalValue
                            ValueKind = $valueKind
                            Values = @($values)
                            Aliases = @($allAliases)
                            Description = $description
                        }

                        [void]$options.Add($spec)
                        $optionByName[$optionName] = $spec
                    }

                    foreach ($alias in $allAliases) {
                        if (-not $optionByName.ContainsKey($alias)) {
                            $optionByName[$alias] = $optionByName[$optionNames[-1]]
                        }
                    }
                }
            }
        }
    }

    [pscustomobject]@{
        Options = (ConvertTo-GrokArray -Value $options)
        Subcommands = (ConvertTo-GrokArray -Value ($subcommands.ToArray() | Sort-Object -Unique))
        SubcommandAliases = $subcommandAliases
        Arguments = (ConvertTo-GrokArray -Value $arguments)
        OptionByName = $optionByName
    }
}

function Get-GrokCompletionCatalog {
    $catalog = Get-Variable -Name 'GrokCompletionCatalog' -Scope Script -ErrorAction Ignore
    if ($null -ne $catalog -and $null -ne $catalog.Value) {
        return $catalog.Value
    }

    $newCatalog = [ordered]@{
        Initialized = $false
        CommandPath = $null
        RootHelpText = ''
        RootSubcommands = @()
        RootSubcommandAliases = @{}
        RootOptions = @()
        RootArguments = @()
        RootOptionByName = @{}
        SubcommandCatalogs = @{}
    }

    Set-Variable -Name 'GrokCompletionCatalog' -Value $newCatalog -Scope Script
    return (Get-Variable -Name 'GrokCompletionCatalog' -Scope Script).Value
}

function Initialize-GrokCompletionCatalog {
    $catalog = Get-GrokCompletionCatalog
    if ($catalog.Initialized) {
        return $catalog
    }

    $catalog.CommandPath = Get-GrokCommandPath
    $catalog.RootHelpText = Get-GrokRootHelpOutput

    $rootHelp = ConvertFrom-GrokHelp -HelpText $catalog.RootHelpText
    $catalog.RootSubcommands = (ConvertTo-GrokArray -Value $rootHelp.Subcommands)
    $catalog.RootSubcommandAliases = $rootHelp.SubcommandAliases
    $catalog.RootOptions = (ConvertTo-GrokArray -Value $rootHelp.Options)
    $catalog.RootArguments = (ConvertTo-GrokArray -Value $rootHelp.Arguments)
    $catalog.RootOptionByName = $rootHelp.OptionByName

    $catalog.Initialized = $true
    Set-Variable -Name 'GrokCompletionCatalog' -Value $catalog -Scope Script
    return (Get-Variable -Name 'GrokCompletionCatalog' -Scope Script).Value
}

function Get-GrokSubcommandCatalog {
    param([string[]]$SubcommandPath)

    $catalog = Initialize-GrokCompletionCatalog
    $path = @($SubcommandPath)

    if ($path.Count -eq 0) {
        return [pscustomobject]@{
            Options = (ConvertTo-GrokArray -Value $catalog.RootOptions)
            Subcommands = (ConvertTo-GrokArray -Value $catalog.RootSubcommands)
            SubcommandAliases = $catalog.RootSubcommandAliases
            Arguments = (ConvertTo-GrokArray -Value $catalog.RootArguments)
            OptionByName = $catalog.RootOptionByName
        }
    }

    $key = $path -join ' '
    if ($catalog.SubcommandCatalogs.ContainsKey($key)) {
        return $catalog.SubcommandCatalogs[$key]
    }

    $helpOutput = Get-GrokSubcommandHelpOutput -SubcommandPath $path
    $parsed = ConvertFrom-GrokHelp -HelpText $helpOutput
    $parsedObject = [pscustomobject]@{
        Options = (ConvertTo-GrokArray -Value $parsed.Options)
        Subcommands = (ConvertTo-GrokArray -Value $parsed.Subcommands)
        SubcommandAliases = $parsed.SubcommandAliases
        Arguments = (ConvertTo-GrokArray -Value $parsed.Arguments)
        OptionByName = $parsed.OptionByName
    }

    $catalog.SubcommandCatalogs[$key] = $parsedObject
    Set-Variable -Name 'GrokCompletionCatalog' -Value $catalog -Scope Script
    return $catalog.SubcommandCatalogs[$key]
}

function ConvertTo-GrokArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $typeName = $Value.GetType().FullName
        if ($typeName -like 'System.Collections.Generic.List*' -or $typeName -like 'System.Collections.Generic.IReadOnlyList*') {
            return @($Value.ToArray())
        }
    }

    return @($Value)
}

function Get-GrokCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') {
        return ''
    }

    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    return $Fallback
}

function Get-GrokCommandTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    if ($null -eq $CommandAst) {
        return @()
    }

    # Only elements that end strictly before the cursor precede the current
    # word; the element the cursor touches is the word being completed.
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            [void]$tokens.Add($element.Extent.Text.Trim())
        }
    }

    return (ConvertTo-GrokArray -Value $tokens)
}

function Get-GrokPathCompletions {
    param(
        [string]$InputPath,
        [switch]$DirectoryOnly
    )

    $cleanInput = $InputPath
    if ($null -eq $cleanInput) {
        $cleanInput = ''
    }

    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]+$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        if ($DirectoryOnly -and -not $item.PSIsContainer) {
            continue
        }

        $pathText = if ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = $pathText
        if (($alwaysQuote -or $pathText -match '\s') -and -not ($pathText.StartsWith('"') -and $pathText.EndsWith('"'))) {
            $escaped = $pathText.Replace('`', '``').Replace('"', '`"')
            $quotedPath = '"' + $escaped + '"'
        }

        if ($item.PSIsContainer) {
            New-GrokCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-GrokCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-GrokOptionSpec {
    param(
        [psobject]$Catalog,
        [string]$OptionName
    )

    if ($null -eq $Catalog -or [string]::IsNullOrWhiteSpace($OptionName)) {
        return $null
    }

    $optionByName = $Catalog.OptionByName
    if ($null -eq $optionByName) {
        return $null
    }

    if ($optionByName.ContainsKey($OptionName)) {
        return $optionByName[$OptionName]
    }

    if ($optionByName.ContainsKey($OptionName.ToLowerInvariant())) {
        return $optionByName[$OptionName.ToLowerInvariant()]
    }

    return $null
}

function Resolve-GrokSubcommandName {
    param(
        [psobject]$Catalog,
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($Token) -or $Token.StartsWith('-')) {
        return $null
    }

    if (@($Catalog.Subcommands) -contains $Token) {
        return $Token
    }

    $aliases = $Catalog.SubcommandAliases
    if ($null -ne $aliases -and $aliases.ContainsKey($Token)) {
        return $aliases[$Token]
    }

    return $null
}

function Complete-GrokOptionValue {
    param(
        [psobject]$OptionSpec,
        [string]$ValueText,
        [string]$Prefix = ''
    )

    $results = New-Object System.Collections.Generic.List[object]

    switch ($OptionSpec.ValueKind) {
        'Enum' {
            foreach ($value in $OptionSpec.Values) {
                if ($value -like ([System.Management.Automation.WildcardPattern]::Escape($ValueText) + '*')) {
                    [void]$results.Add((New-GrokCompletionResult -CompletionText ($Prefix + $value) -ListItemText $value -ResultType 'ParameterValue' -ToolTip $OptionSpec.Description))
                }
            }
        }
        'Directory' {
            foreach ($result in @(Get-GrokPathCompletions -InputPath $ValueText -DirectoryOnly)) {
                [void]$results.Add((New-GrokCompletionResult -CompletionText ($Prefix + $result.CompletionText) -ListItemText $result.ListItemText -ResultType $result.ResultType -ToolTip $result.ToolTip))
            }
        }
        'Path' {
            foreach ($result in @(Get-GrokPathCompletions -InputPath $ValueText)) {
                [void]$results.Add((New-GrokCompletionResult -CompletionText ($Prefix + $result.CompletionText) -ListItemText $result.ListItemText -ResultType $result.ResultType -ToolTip $result.ToolTip))
            }
        }
        default {
            [void]$results.Add((New-GrokCompletionResult -CompletionText ($Prefix + '<value>') -ListItemText '<value>' -ResultType 'ParameterValue' -ToolTip $OptionSpec.Description))
        }
    }

    return (ConvertTo-GrokArray -Value $results)
}

function Complete-Grok {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $null = Initialize-GrokCompletionCatalog
    $currentWord = if ($null -eq $wordToComplete) { '' } else { $wordToComplete }
    $tokensBeforeCurrent = @(Get-GrokCommandTokens -CommandAst $commandAst -CursorPosition $cursorPosition)

    # The engine hands over the whole token when the cursor sits inside it;
    # re-derive the word from the command-relative text before the cursor.
    $currentToken = $currentWord
    if ($null -ne $commandAst) {
        if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
            $currentToken = ''
        } else {
            $currentToken = Get-GrokCurrentToken -Line $commandAst.Extent.Text -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $currentWord
        }
    }
    $currentToken = $currentToken.Trim([char[]]@([char]34, [char]39))

    # Walk the command path greedily: every leading non-option token that
    # names a subcommand (or alias) of the current node descends one level.
    $commandPath = @()
    $activeCatalog = Get-GrokSubcommandCatalog -SubcommandPath @()
    $positionalCount = 0
    $descending = $true
    $pendingOption = $null

    foreach ($token in $tokensBeforeCurrent) {
        if ($null -ne $pendingOption) {
            $pendingOption = $null
            continue
        }

        if ($token.StartsWith('-') -and $token.Length -gt 1) {
            if ($token.Contains('=')) {
                continue
            }

            $spec = Get-GrokOptionSpec -Catalog $activeCatalog -OptionName $token
            if ($null -ne $spec -and $spec.TakesValue -and -not $spec.OptionalValue) {
                $pendingOption = $spec
            }

            continue
        }

        $resolved = if ($descending) { Resolve-GrokSubcommandName -Catalog $activeCatalog -Token $token } else { $null }
        if ($null -ne $resolved) {
            $commandPath += $resolved
            $activeCatalog = Get-GrokSubcommandCatalog -SubcommandPath $commandPath
            continue
        }

        $descending = $false
        $positionalCount++
    }

    if ($null -ne $pendingOption) {
        return Complete-GrokOptionValue -OptionSpec $pendingOption -ValueText $currentToken
    }

    if ($currentToken -match '^(--?[A-Za-z0-9][A-Za-z0-9-]*)=(.*)$') {
        $spec = Get-GrokOptionSpec -Catalog $activeCatalog -OptionName $Matches[1]
        if ($null -ne $spec -and $spec.TakesValue) {
            return Complete-GrokOptionValue -OptionSpec $spec -ValueText $Matches[2] -Prefix ($Matches[1] + '=')
        }

        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ($positionalCount -eq 0 -and -not $currentToken.StartsWith('-')) {
        $argumentSpec = $null
        foreach ($argument in @($activeCatalog.Arguments)) {
            if ($argument.Name -match '^<' -and @($argument.Values).Count -gt 0) {
                $argumentSpec = $argument
                break
            }
        }

        if ($null -ne $argumentSpec) {
            foreach ($value in $argumentSpec.Values) {
                if ($value -like ([System.Management.Automation.WildcardPattern]::Escape($currentToken) + '*')) {
                    [void]$results.Add((New-GrokCompletionResult -CompletionText $value -ListItemText $value -ResultType 'ParameterValue' -ToolTip $argumentSpec.Description))
                }
            }

            return (ConvertTo-GrokArray -Value $results)
        }
    }

    if ($currentToken.StartsWith('-')) {
        foreach ($option in @($activeCatalog.Options)) {
            if ($option.Name -like ([System.Management.Automation.WildcardPattern]::Escape($currentToken) + '*')) {
                [void]$results.Add((New-GrokCompletionResult -CompletionText $option.Name -ListItemText $option.Name -ResultType 'ParameterName' -ToolTip $option.Description))
            }
        }
    } else {
        # When not starting with '-', offer both subcommands and options at the command level
        if ($descending) {
            foreach ($subcommand in @($activeCatalog.Subcommands)) {
                if ($subcommand -like ([System.Management.Automation.WildcardPattern]::Escape($currentToken) + '*')) {
                    [void]$results.Add((New-GrokCompletionResult -CompletionText $subcommand -ListItemText $subcommand -ResultType 'ParameterValue' -ToolTip 'grok subcommand'))
                }
            }
        }

        # Also offer options at the command level (with '-' prefix)
        foreach ($option in @($activeCatalog.Options)) {
            if ($option.Name -like ('-' + [System.Management.Automation.WildcardPattern]::Escape($currentToken) + '*')) {
                [void]$results.Add((New-GrokCompletionResult -CompletionText $option.Name -ListItemText $option.Name -ResultType 'ParameterName' -ToolTip $option.Description))
            }
        }
    }

    return (ConvertTo-GrokArray -Value $results)
}

Register-ArgumentCompleter -Native -CommandName @('grok', 'grok.exe', 'agent') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Grok -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
