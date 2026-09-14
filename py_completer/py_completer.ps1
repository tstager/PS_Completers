Set-StrictMode -Version 2.0

function New-PyCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip,
        [string]$ListItemText
    )

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

function Test-PyStartsWith {
    param(
        [string]$Candidate,
        [string]$Prefix
    )

    [string]::IsNullOrEmpty($Prefix) -or $Candidate.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function New-PyOptionSpec {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [string]$ValueKind = '',
        [bool]$IsTerminal = $false
    )

    [pscustomobject]@{
        Tokens      = @($Tokens)
        Description = $Description
        ValueKind   = $ValueKind
        IsTerminal  = $IsTerminal
    }
}

function Get-PyLegacyOptionTable {
    # Python Launcher for Windows (PEP 397). -32/-64 exist only as suffixes on a version selector.
    @(
        New-PyOptionSpec -Tokens @('-2') -Description 'Launch the latest Python 2.x runtime.'
        New-PyOptionSpec -Tokens @('-3') -Description 'Launch the latest Python 3.x runtime.'
        New-PyOptionSpec -Tokens @('-0', '--list') -Description 'List the available Python runtimes.' -IsTerminal $true
        New-PyOptionSpec -Tokens @('-0p', '--list-paths') -Description 'List the available Python runtimes with paths.' -IsTerminal $true
        New-PyOptionSpec -Tokens @('-h', '-?', '--help') -Description 'Show Python Launcher for Windows help.' -IsTerminal $true
        New-PyOptionSpec -Tokens @('-V:') -Description 'Select a runtime by tag or by COMPANY\TAG.'
    )
}

function Get-PyManagerRootOptionTable {
    # Python install manager: launch forms accepted before any command.
    @(
        New-PyOptionSpec -Tokens @('-3') -Description 'Launch a PythonCore 3.x runtime (-3<VERSION>, platform suffix allowed).'
        New-PyOptionSpec -Tokens @('-V:') -Description 'Launch the runtime identified by <TAG> (include the company unless PythonCore).'
    )
}

function Get-PyGlobalOptionTable {
    # Python install manager global options; they must follow the command.
    @(
        New-PyOptionSpec -Tokens @('-v', '--verbose') -Description 'Increased output (log_level=20).'
        New-PyOptionSpec -Tokens @('-vv') -Description 'Further increased output (log_level=10).'
        New-PyOptionSpec -Tokens @('-q', '--quiet') -Description 'Less output (log_level=30).'
        New-PyOptionSpec -Tokens @('-qq') -Description 'Even less output (log_level=40).'
        New-PyOptionSpec -Tokens @('-y', '--yes') -Description 'Always accept confirmation prompts (confirm=false).'
        New-PyOptionSpec -Tokens @('-h', '-?', '--help') -Description 'Show help for a specific command.' -IsTerminal $true
        New-PyOptionSpec -Tokens @('--config') -Description 'Override configuration with a JSON file (--config=<PATH>).' -ValueKind 'ConfigPath'
    )
}

function Get-PyCommandTable {
    @(
        [pscustomobject]@{ Name = 'exec';      Description = 'Launch a runtime (-V:<TAG> or -3<VERSION>), installing it if needed.' }
        [pscustomobject]@{ Name = 'help';      Description = 'Show help for Python installation manager commands.' }
        [pscustomobject]@{ Name = 'install';   Description = 'Download new Python runtimes, or pass --update to update existing installs.' }
        [pscustomobject]@{ Name = 'list';      Description = 'Show installed Python runtimes, optionally filtered.' }
        [pscustomobject]@{ Name = 'uninstall'; Description = 'Remove one or more runtimes from your machine.' }
    )
}

function Get-PyCommandOptionTable {
    param([string]$Command)

    $specs = switch ($Command) {
        'install' {
            @(
                New-PyOptionSpec -Tokens @('-s', '--source') -Description 'Specify index.json to use (install.source=...).' -ValueKind 'Uri'
                New-PyOptionSpec -Tokens @('-t', '--target') -Description 'Extract runtime to location instead of installing.' -ValueKind 'DirectoryPath'
                New-PyOptionSpec -Tokens @('-d', '--download') -Description 'Prepare an offline index with one or more runtimes.' -ValueKind 'DirectoryPath'
                New-PyOptionSpec -Tokens @('-f', '--force') -Description 'Re-download and overwrite existing install.'
                New-PyOptionSpec -Tokens @('-u', '--update') -Description 'Overwrite existing install if a newer version is available.'
                New-PyOptionSpec -Tokens @('--dry-run') -Description 'Choose runtime but do not install.'
                New-PyOptionSpec -Tokens @('--refresh') -Description 'Update shortcuts and aliases for all installed versions.'
                New-PyOptionSpec -Tokens @('--configure') -Description 'Re-run the system configuration helper.'
                New-PyOptionSpec -Tokens @('--by-id') -Description 'Require TAG to exactly match the install ID.'
            )
        }
        'list' {
            @(
                New-PyOptionSpec -Tokens @('-f', '--format') -Description 'Specify list format, defaults to table.' -ValueKind 'ListFormat'
                New-PyOptionSpec -Tokens @('-1', '--one') -Description 'Only display first result that matches the filter.'
                New-PyOptionSpec -Tokens @('--online') -Description 'List runtimes available to install from the default index.'
                New-PyOptionSpec -Tokens @('-s', '--source') -Description 'List runtimes from a particular index.' -ValueKind 'Uri'
                New-PyOptionSpec -Tokens @('--only-managed') -Description 'Only list Python installs managed by the tool.'
            )
        }
        'uninstall' {
            @(
                New-PyOptionSpec -Tokens @('--purge') -Description 'Remove all runtimes, shortcuts, and cached files. Ignores tags.'
                New-PyOptionSpec -Tokens @('--by-id') -Description 'Require TAG to exactly match the install ID.'
            )
        }
        default { @() }
    }

    @($specs) + @(Get-PyGlobalOptionTable)
}

function Get-PyOptionMap {
    param([object[]]$Specs)

    # Ordinal: -v (verbose) and -V: (selector) are different tokens.
    $map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($spec in @($Specs)) {
        foreach ($token in $spec.Tokens) {
            $map[$token] = $spec
        }
    }

    $map
}

function Resolve-PyCommandName {
    $cache = Get-Variable -Name PyCompletionResolvedCommand -Scope Script -ErrorAction Ignore
    if ($cache) {
        return $cache.Value
    }

    $resolved = $null
    $command = Get-Command -Name py.exe, py -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if ($command) {
        $resolved = if ([string]::IsNullOrWhiteSpace($command.Source)) { $command.Name } else { $command.Source }
    }

    Set-Variable -Name PyCompletionResolvedCommand -Scope Script -Value $resolved
    $resolved
}

function Invoke-PyProcessOutput {
    param([string[]]$Arguments)

    $commandName = Resolve-PyCommandName
    if ([string]::IsNullOrWhiteSpace($commandName)) {
        return $null
    }

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $commandName
        foreach ($argument in $Arguments) {
            $startInfo.ArgumentList.Add($argument)
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
                $process.Kill()
                return $null
            }

            $text = $outputTask.Result
            if ([string]::IsNullOrWhiteSpace($text)) {
                $text = $errorTask.Result
            }

            return $text
        } finally {
            $process.Dispose()
        }
    } catch {
        Write-Debug "py completer: '$commandName $($Arguments -join ' ')' failed: $($_.Exception.Message)"
        return $null
    }
}

function Get-PyLauncherFlavor {
    # 'manager' for the Python install manager (py exec|help|install|list|uninstall),
    # 'legacy' for the Python Launcher for Windows (-0, -0p, -2 ...).
    $cache = Get-Variable -Name PyCompletionFlavor -Scope Script -ErrorAction Ignore
    if ($cache) {
        return $cache.Value
    }

    $flavor = 'legacy'
    $commandName = Resolve-PyCommandName
    if (-not [string]::IsNullOrWhiteSpace($commandName)) {
        $siblingManager = $null
        try {
            $siblingManager = Join-Path -Path (Split-Path -Path $commandName -Parent) -ChildPath 'pymanager.exe'
        } catch {
            $siblingManager = $null
        }

        if (($siblingManager -and (Test-Path -LiteralPath $siblingManager)) -or $commandName -match 'PythonManager') {
            $flavor = 'manager'
        } else {
            $help = Invoke-PyProcessOutput -Arguments @('-h')
            if (-not [string]::IsNullOrWhiteSpace($help) -and $help -notmatch 'Python Launcher for Windows') {
                $flavor = 'manager'
            }
        }
    }

    Set-Variable -Name PyCompletionFlavor -Scope Script -Value $flavor
    $flavor
}

function Add-PyRuntimeTag {
    param(
        [System.Collections.Generic.HashSet[string]]$TagSet,
        [System.Collections.Generic.HashSet[string]]$QualifiedSet,
        [string]$Company,
        [string]$Tag
    )

    if ([string]::IsNullOrWhiteSpace($Tag) -or $Tag.Contains('[') -or $Tag.Contains(']')) {
        return
    }

    [void]$TagSet.Add($Tag)
    if (-not [string]::IsNullOrWhiteSpace($Company)) {
        [void]$QualifiedSet.Add("$Company\$Tag")
    }
}

function Get-PyRuntimeTagCatalog {
    $cache = Get-Variable -Name PyCompletionRuntimeTagCatalog -Scope Script -ErrorAction Ignore
    if ($cache) {
        $age = (Get-Date) - $cache.Value.UpdatedAt
        if ($age.TotalSeconds -lt 300) {
            return $cache.Value
        }
    }

    $tagSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $qualifiedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $companySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $loaded = $false

    if ((Get-PyLauncherFlavor) -eq 'manager') {
        # Structured source: company and tag fields need no display-syntax parsing.
        $json = Invoke-PyProcessOutput -Arguments @('list', '-f=json')
        if (-not [string]::IsNullOrWhiteSpace($json)) {
            try {
                $document = $json | ConvertFrom-Json -ErrorAction Stop
                foreach ($version in @($document.versions)) {
                    $company = if ($version.PSObject.Properties['company']) { [string]$version.company } else { '' }
                    if (-not [string]::IsNullOrWhiteSpace($company)) {
                        [void]$companySet.Add($company)
                    }

                    if ($version.PSObject.Properties['tag']) {
                        Add-PyRuntimeTag -TagSet $tagSet -QualifiedSet $qualifiedSet -Company $company -Tag ([string]$version.tag)
                    }

                    if ($version.PSObject.Properties['install-for']) {
                        foreach ($alias in @($version.'install-for')) {
                            Add-PyRuntimeTag -TagSet $tagSet -QualifiedSet $qualifiedSet -Company $company -Tag ([string]$alias)
                        }
                    }

                    if ($version.PSObject.Properties['run-for']) {
                        foreach ($entry in @($version.'run-for')) {
                            if ($entry.PSObject.Properties['tag']) {
                                Add-PyRuntimeTag -TagSet $tagSet -QualifiedSet $qualifiedSet -Company $company -Tag ([string]$entry.tag)
                            }
                        }
                    }

                    $loaded = $true
                }
            } catch {
                Write-Debug "py completer: could not parse 'py list -f=json': $($_.Exception.Message)"
            }
        }
    }

    if (-not $loaded) {
        # Legacy launcher (or JSON unavailable): scrape 'py -0p'. The display notation '3.14[-64]'
        # means an optional platform suffix, so it expands to '3.14' and '3.14-64'.
        $text = Invoke-PyProcessOutput -Arguments @('-0p')
        foreach ($line in @(($text -split '\r?\n'))) {
            $match = [regex]::Match($line, '(?i)-V:(?<selector>\S+)')
            if (-not $match.Success) {
                continue
            }

            $selector = $match.Groups['selector'].Value.Trim()
            $company = ''
            $tag = $selector
            $separator = $selector.IndexOfAny([char[]]@('/', '\'))
            if ($separator -ge 0) {
                $company = $selector.Substring(0, $separator)
                $tag = $selector.Substring($separator + 1)
                if (-not [string]::IsNullOrWhiteSpace($company)) {
                    [void]$companySet.Add($company)
                }
            }

            $bracket = [regex]::Match($tag, '^(?<base>[^\[]+)\[(?<optional>[^\]]+)\]$')
            if ($bracket.Success) {
                Add-PyRuntimeTag -TagSet $tagSet -QualifiedSet $qualifiedSet -Company $company -Tag $bracket.Groups['base'].Value
                Add-PyRuntimeTag -TagSet $tagSet -QualifiedSet $qualifiedSet -Company $company -Tag ($bracket.Groups['base'].Value + $bracket.Groups['optional'].Value)
            } else {
                Add-PyRuntimeTag -TagSet $tagSet -QualifiedSet $qualifiedSet -Company $company -Tag $tag
            }
        }
    }

    $catalog = [pscustomobject]@{
        UpdatedAt          = Get-Date
        Tags               = @($tagSet | Sort-Object)
        QualifiedSelectors = @($qualifiedSet | Sort-Object)
        Companies          = @($companySet | Sort-Object)
    }

    Set-Variable -Name PyCompletionRuntimeTagCatalog -Scope Script -Value $catalog
    $catalog
}

function Get-PyCommandLineState {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $line = if ($null -eq $CommandAst) { '' } else { $CommandAst.Extent.Text }
    if ($null -eq $line) {
        $line = ''
    }

    if ($null -ne $CommandAst -and $CursorPosition -gt $CommandAst.Extent.EndOffset) {
        $line += [string]::new([char]32, ($CursorPosition - $CommandAst.Extent.EndOffset))
    }

    $relativeCursor = if ($null -eq $CommandAst) {
        $CursorPosition
    } else {
        $CursorPosition - $CommandAst.Extent.StartOffset
    }

    $safeCursor = [Math]::Min([Math]::Max($relativeCursor, 0), $line.Length)
    $prefix = $line.Substring(0, $safeCursor)
    $tokens = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    $quoteChar = [char]0

    foreach ($character in $prefix.ToCharArray()) {
        if (($character -eq [char]34) -or ($character -eq [char]39)) {
            if ($quoteChar -eq [char]0) {
                $quoteChar = $character
            } elseif ($quoteChar -eq $character) {
                $quoteChar = [char]0
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and $quoteChar -eq [char]0) {
            if ($builder.Length -gt 0) {
                $tokens.Add($builder.ToString())
                [void]$builder.Clear()
            }

            continue
        }

        [void]$builder.Append($character)
    }

    $hasTrailingSpace = $prefix -match '\s$'
    if ($builder.Length -gt 0) {
        $tokens.Add($builder.ToString())
    }

    if ($hasTrailingSpace) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens)
            CurrentToken        = ''
        }
    }

    if ($tokens.Count -gt 0) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
            CurrentToken        = $tokens[$tokens.Count - 1]
        }
    }

    [pscustomobject]@{
        TokensBeforeCurrent = @()
        CurrentToken        = ''
    }
}

function Get-PyArgumentState {
    param([pscustomobject]$CommandLineState)

    $tokensBeforeCurrent = @($CommandLineState.TokensBeforeCurrent)
    $currentArgument = if ($null -eq $CommandLineState.CurrentToken) { '' } else { $CommandLineState.CurrentToken }
    $argumentsBeforeCurrent = if ($tokensBeforeCurrent.Count -gt 0) {
        @($tokensBeforeCurrent | Select-Object -Skip 1)
    } else {
        @()
    }

    if ($tokensBeforeCurrent.Count -eq 0 -and $currentArgument -match '^(?i:py(?:\.exe)?)$') {
        $currentArgument = ''
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = $argumentsBeforeCurrent
        CurrentArgument        = $currentArgument
    }
}

function Test-PyVersionSelectorToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    # -3, -3.14, -3.14-64, -3.14.6-64, -3-arm64 (and -2... on the legacy launcher)
    $Token -cmatch '^-[23](?:$|[.\-][\w.\-]*$)' -or $Token.StartsWith('-V:', [System.StringComparison]::Ordinal)
}

function Test-PyVersionSelectorPrefix {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    $Token -cmatch '^-[23](?:$|[.\-][\w.\-]*$)'
}

function Get-PyContextOptionTable {
    param(
        [string]$Flavor,
        [string]$Command
    )

    if ($Flavor -ne 'manager') {
        return @(Get-PyLegacyOptionTable)
    }

    if ([string]::IsNullOrEmpty($Command)) {
        return @(Get-PyManagerRootOptionTable)
    }

    if ($Command -eq 'exec') {
        return @(Get-PyManagerRootOptionTable) + @(Get-PyGlobalOptionTable)
    }

    @(Get-PyCommandOptionTable -Command $Command)
}

function Get-PyCompletionContext {
    param(
        [string[]]$ArgumentsBeforeCurrent,
        [string]$Flavor
    )

    $command = ''
    $runtimeSelected = $false
    $terminalMode = ''
    $pendingValueKind = ''
    $positionals = New-Object System.Collections.Generic.List[string]
    $commandNames = @((Get-PyCommandTable) | ForEach-Object { $_.Name })

    foreach ($argument in @($ArgumentsBeforeCurrent)) {
        if (-not [string]::IsNullOrEmpty($terminalMode)) {
            break
        }

        if ([string]::IsNullOrWhiteSpace($argument)) {
            continue
        }

        if (-not [string]::IsNullOrEmpty($pendingValueKind)) {
            $pendingValueKind = ''
            continue
        }

        $isDash = $argument.StartsWith('-', [System.StringComparison]::Ordinal)
        if ($Flavor -eq 'manager' -and [string]::IsNullOrEmpty($command) -and -not $runtimeSelected -and -not $isDash -and $positionals.Count -eq 0 -and ($commandNames -contains $argument)) {
            $command = $argument.ToLowerInvariant()
            continue
        }

        if ($isDash -and (Test-PyVersionSelectorToken -Token $argument) -and ($Flavor -ne 'manager' -or [string]::IsNullOrEmpty($command) -or $command -eq 'exec')) {
            $runtimeSelected = $true
            continue
        }

        if ($isDash) {
            $optionMap = Get-PyOptionMap -Specs (Get-PyContextOptionTable -Flavor $Flavor -Command $command)
            $name = $argument
            $hasAttachedValue = $false
            $equals = $argument.IndexOf('=')
            if ($equals -gt 0) {
                $name = $argument.Substring(0, $equals)
                $hasAttachedValue = $true
            }

            if ($optionMap.ContainsKey($name)) {
                $spec = $optionMap[$name]
                if ($spec.IsTerminal) {
                    $terminalMode = 'LauncherTerminal'
                } elseif (-not $hasAttachedValue -and -not [string]::IsNullOrWhiteSpace($spec.ValueKind)) {
                    $pendingValueKind = $spec.ValueKind
                }
            }

            continue
        }

        if ($Flavor -eq 'manager' -and $command -in @('install', 'uninstall', 'list', 'help')) {
            $positionals.Add($argument)
            continue
        }

        $terminalMode = 'ScriptTail'
    }

    [pscustomobject]@{
        Command          = $command
        RuntimeSelected  = $runtimeSelected
        TerminalMode     = $terminalMode
        PendingValueKind = $pendingValueKind
        Positionals      = @($positionals)
    }
}

function Get-PyUniqueResults {
    param([object[]]$Results)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $unique = New-Object System.Collections.Generic.List[object]

    foreach ($result in @($Results)) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.Add($result.CompletionText)) {
            [void]$unique.Add($result)
        }
    }

    @($unique.ToArray())
}

function Get-PyPlaceholderCompletions {
    param(
        [string]$CurrentWord,
        [string]$Placeholder,
        [string]$ToolTip
    )

    $completionText = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { $Placeholder } else { $CurrentWord }
    @(
        New-PyCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText $Placeholder
    )
}

function Get-PyTerminalCompletions {
    param(
        [string]$CurrentWord,
        [string]$ToolTip,
        [string]$Placeholder
    )

    $completionText = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { ' ' } else { $CurrentWord }
    @(
        New-PyCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $ToolTip -ListItemText $Placeholder
    )
}

function Get-PyPathCompletions {
    param(
        [string]$CurrentWord,
        [string]$Placeholder,
        [string]$AttachedPrefix = '',
        [switch]$ContainersOnly
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($CurrentWord)) {
        if ($ContainersOnly -and $item.ResultType -ne [System.Management.Automation.CompletionResultType]::ProviderContainer) {
            continue
        }

        [void]$results.Add([System.Management.Automation.CompletionResult]::new(
                ($AttachedPrefix + $item.CompletionText),
                $item.ListItemText,
                $item.ResultType,
                $item.ToolTip
            ))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { $AttachedPrefix + $Placeholder } else { $AttachedPrefix + $CurrentWord }
        return @(New-PyCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip 'Filesystem path.' -ListItemText $Placeholder)
    }

    @($results.ToArray())
}

function Get-PyOptionCompletionList {
    param(
        [object[]]$Specs,
        [string]$CurrentWord
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($spec in @($Specs)) {
        foreach ($token in $spec.Tokens) {
            # Ordinal: py's options are case-sensitive (-v is --verbose, -V: is the runtime selector).
            if ([string]::IsNullOrEmpty($CurrentWord) -or $token.StartsWith($CurrentWord, [System.StringComparison]::Ordinal)) {
                $completionText = if (-not [string]::IsNullOrWhiteSpace($spec.ValueKind) -and $token.StartsWith('--')) { $token + '=' } else { $token }
                [void]$results.Add((New-PyCompletionResult -CompletionText $completionText -ResultType 'ParameterName' -ToolTip $spec.Description -ListItemText $token))
            }
        }
    }

    @(Get-PyUniqueResults -Results $results.ToArray())
}

function Get-PyVCompletions {
    param([string]$CurrentWord)

    $results = New-Object System.Collections.Generic.List[object]
    $catalog = Get-PyRuntimeTagCatalog
    $suffix = if ($CurrentWord.Length -ge 3) { $CurrentWord.Substring(3) } else { '' }
    $separatorIndex = $suffix.IndexOfAny([char[]]@('/', '\'))

    if ($separatorIndex -ge 0) {
        # COMPANY\TAG (the documented form) or COMPANY/TAG; keep whichever separator was typed.
        $companyPrefix = $suffix.Substring(0, $separatorIndex + 1)
        $tagPrefix = $suffix.Substring($separatorIndex + 1)

        foreach ($tag in @($catalog.Tags)) {
            if (Test-PyStartsWith -Candidate $tag -Prefix $tagPrefix) {
                [void]$results.Add((New-PyCompletionResult -CompletionText "-V:$companyPrefix$tag" -ResultType 'ParameterName' -ToolTip 'Runtime selector by COMPANY\TAG.'))
            }
        }

        if ($results.Count -eq 0) {
            return @(Get-PyPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder "-V:$companyPrefix<TAG>" -ToolTip 'Runtime selector by COMPANY\TAG.')
        }

        return @(Get-PyUniqueResults -Results $results.ToArray())
    }

    foreach ($tag in @($catalog.Tags)) {
        if (Test-PyStartsWith -Candidate $tag -Prefix $suffix) {
            [void]$results.Add((New-PyCompletionResult -CompletionText "-V:$tag" -ResultType 'ParameterName' -ToolTip 'Installed runtime selector by tag.'))
        }
    }

    foreach ($selector in @($catalog.QualifiedSelectors)) {
        if (Test-PyStartsWith -Candidate $selector -Prefix $suffix) {
            [void]$results.Add((New-PyCompletionResult -CompletionText "-V:$selector" -ResultType 'ParameterName' -ToolTip 'Installed runtime selector by COMPANY\TAG.'))
        }
    }

    if ([string]::IsNullOrWhiteSpace($suffix)) {
        [void]$results.Add((New-PyCompletionResult -CompletionText '-V:<TAG>' -ResultType 'ParameterName' -ToolTip 'Runtime selector by tag.'))
        [void]$results.Add((New-PyCompletionResult -CompletionText '-V:<COMPANY\TAG>' -ResultType 'ParameterName' -ToolTip 'Runtime selector by COMPANY\TAG.'))
    } elseif ($results.Count -eq 0) {
        return @(Get-PyPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '-V:<TAG>' -ToolTip 'Runtime selector.')
    }

    @(Get-PyUniqueResults -Results $results.ToArray())
}

function Get-PyVersionSelectorCompletions {
    param(
        [string]$CurrentWord,
        [string]$Flavor
    )

    $results = New-Object System.Collections.Generic.List[object]
    $catalog = Get-PyRuntimeTagCatalog
    $majors = if ($Flavor -eq 'manager') { @('3') } else { @('2', '3') }

    foreach ($major in $majors) {
        if (Test-PyStartsWith -Candidate "-$major" -Prefix $CurrentWord) {
            [void]$results.Add((New-PyCompletionResult -CompletionText "-$major" -ResultType 'ParameterName' -ToolTip "Launch the latest Python $major.x runtime."))
        }
    }

    foreach ($tag in @($catalog.Tags)) {
        if ($tag -notmatch '^\d') {
            continue
        }

        if ($Flavor -eq 'manager' -and -not $tag.StartsWith('3')) {
            continue
        }

        $candidate = "-$tag"
        if (Test-PyStartsWith -Candidate $candidate -Prefix $CurrentWord) {
            [void]$results.Add((New-PyCompletionResult -CompletionText $candidate -ResultType 'ParameterName' -ToolTip 'Installed runtime version selector.'))
        }
    }

    if ($results.Count -eq 0) {
        return @(Get-PyPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '-3.X' -ToolTip 'Version selector form (-3<VERSION>).')
    }

    @(Get-PyUniqueResults -Results $results.ToArray())
}

function Get-PyTagCompletionList {
    param(
        [string]$CurrentWord,
        [string]$Command
    )

    $results = New-Object System.Collections.Generic.List[object]
    $catalog = Get-PyRuntimeTagCatalog

    if ($Command -eq 'help') {
        foreach ($commandSpec in @(Get-PyCommandTable)) {
            if (Test-PyStartsWith -Candidate $commandSpec.Name -Prefix $CurrentWord) {
                [void]$results.Add((New-PyCompletionResult -CompletionText $commandSpec.Name -ResultType 'ParameterValue' -ToolTip $commandSpec.Description))
            }
        }

        if ($results.Count -eq 0) {
            return @(Get-PyPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '<CMD>' -ToolTip 'Command to show help for.')
        }

        return @(Get-PyUniqueResults -Results $results.ToArray())
    }

    $toolTip = switch ($Command) {
        'install'   { 'Runtime tag to install (Company\Tag format).' }
        'uninstall' { 'Installed runtime to remove (Company\Tag format).' }
        default     { 'Filter (Company\Tag with optional <, <=, >, >= prefix).' }
    }

    $comparisonPrefix = ''
    $tagWord = $CurrentWord
    if ($Command -eq 'list' -and $CurrentWord -match '^(?<op><=|>=|<|>)(?<rest>.*)$') {
        $comparisonPrefix = $Matches.op
        $tagWord = $Matches.rest
    }

    foreach ($tag in @($catalog.Tags)) {
        if (Test-PyStartsWith -Candidate $tag -Prefix $tagWord) {
            [void]$results.Add((New-PyCompletionResult -CompletionText ($comparisonPrefix + $tag) -ResultType 'ParameterValue' -ToolTip $toolTip))
        }
    }

    foreach ($selector in @($catalog.QualifiedSelectors)) {
        if (Test-PyStartsWith -Candidate $selector -Prefix $tagWord) {
            [void]$results.Add((New-PyCompletionResult -CompletionText ($comparisonPrefix + $selector) -ResultType 'ParameterValue' -ToolTip $toolTip))
        }
    }

    if ($Command -eq 'install') {
        foreach ($hint in @('3', '3.14', '3.13', '3.12')) {
            if (Test-PyStartsWith -Candidate $hint -Prefix $tagWord) {
                [void]$results.Add((New-PyCompletionResult -CompletionText $hint -ResultType 'ParameterValue' -ToolTip 'PythonCore version to install (latest matching release).'))
            }
        }
    }

    if ($results.Count -eq 0) {
        $placeholder = if ($Command -eq 'list') { '<FILTER>' } else { '<TAG>' }
        return @(Get-PyPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder $placeholder -ToolTip $toolTip)
    }

    @(Get-PyUniqueResults -Results $results.ToArray())
}

function Get-PyValueCompletionList {
    param(
        [string]$ValueKind,
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    switch ($ValueKind) {
        'ListFormat' {
            $formats = @(
                @{ Name = 'table';        Description = 'Lists as a user-friendly table.' }
                @{ Name = 'csv';          Description = 'List as a comma-separated value table.' }
                @{ Name = 'json';         Description = 'Lists as a single JSON object.' }
                @{ Name = 'jsonl';        Description = 'Lists as JSON on each line.' }
                @{ Name = 'id';           Description = 'Lists the runtime ID.' }
                @{ Name = 'exe';          Description = 'Lists the main executable path.' }
                @{ Name = 'prefix';       Description = 'Lists the prefix directory.' }
                @{ Name = 'url';          Description = 'Lists the original source URL.' }
                @{ Name = 'legacy';       Description = 'List runtimes using the old format.' }
                @{ Name = 'legacy-paths'; Description = 'List runtime paths using the old format.' }
                @{ Name = 'formats';      Description = 'List the available list formats.' }
                @{ Name = 'config';       Description = 'List the current config.' }
            )

            $results = New-Object System.Collections.Generic.List[object]
            foreach ($format in $formats) {
                if (Test-PyStartsWith -Candidate $format.Name -Prefix $CurrentWord) {
                    [void]$results.Add((New-PyCompletionResult -CompletionText ($AttachedPrefix + $format.Name) -ResultType 'ParameterValue' -ToolTip $format.Description -ListItemText $format.Name))
                }
            }

            if ($results.Count -eq 0) {
                return @(Get-PyPlaceholderCompletions -CurrentWord ($AttachedPrefix + $CurrentWord) -Placeholder ($AttachedPrefix + '<format>') -ToolTip 'List format.')
            }

            return @($results.ToArray())
        }
        'ConfigPath' {
            return @(Get-PyPathCompletions -CurrentWord $CurrentWord -Placeholder '<config.json>' -AttachedPrefix $AttachedPrefix)
        }
        'DirectoryPath' {
            return @(Get-PyPathCompletions -CurrentWord $CurrentWord -Placeholder '<directory>' -AttachedPrefix $AttachedPrefix -ContainersOnly)
        }
        'Uri' {
            return @(Get-PyPlaceholderCompletions -CurrentWord ($AttachedPrefix + $CurrentWord) -Placeholder ($AttachedPrefix + '<URI>') -ToolTip 'Index URL or index.json path.')
        }
    }

    @()
}

function Get-PyTailCompletions {
    param([string]$CurrentWord)

    if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $CurrentWord.StartsWith('-')) {
        return @(Get-PyPathCompletions -CurrentWord $CurrentWord -Placeholder '<script-arg-path>')
    }

    @(Get-PyTerminalCompletions -CurrentWord $CurrentWord -Placeholder '<script-arg>' -ToolTip 'Launcher option completion stops after the script operand.')
}

function Get-PyLaunchSlotCompletionList {
    param(
        [string]$CurrentWord,
        [string]$Flavor,
        [bool]$RuntimeSelected,
        [object[]]$OptionSpecs,
        [bool]$IncludeCommands
    )

    $results = New-Object System.Collections.Generic.List[object]

    if ($CurrentWord.StartsWith('-V:', [System.StringComparison]::Ordinal)) {
        return @(Get-PyVCompletions -CurrentWord $CurrentWord)
    }

    if ([string]::Equals($CurrentWord, '-V', [System.StringComparison]::Ordinal)) {
        return @(New-PyCompletionResult -CompletionText '-V:' -ResultType 'ParameterName' -ToolTip 'Select a runtime by tag or by COMPANY\TAG.')
    }

    if ($RuntimeSelected) {
        # Only one selector is accepted; what follows are regular Python options or the script.
        if ($CurrentWord.StartsWith('-', [System.StringComparison]::Ordinal)) {
            return @(Get-PyTerminalCompletions -CurrentWord $CurrentWord -Placeholder '<python-option>' -ToolTip 'Regular Python interpreter option (see python -h).')
        }

        return @(Get-PyPathCompletions -CurrentWord $CurrentWord -Placeholder '<script-path>')
    }

    if ($CurrentWord.StartsWith('-', [System.StringComparison]::Ordinal)) {
        foreach ($item in @(Get-PyOptionCompletionList -Specs $OptionSpecs -CurrentWord $CurrentWord)) {
            [void]$results.Add($item)
        }

        if ((Test-PyVersionSelectorPrefix -Token $CurrentWord) -or $CurrentWord -eq '-') {
            foreach ($item in @(Get-PyVersionSelectorCompletions -CurrentWord $CurrentWord -Flavor $Flavor)) {
                [void]$results.Add($item)
            }
        }

        if ($results.Count -eq 0) {
            if ($Flavor -eq 'manager') {
                # Global options must follow a command; anything else here is passed to python.
                return @(Get-PyTerminalCompletions -CurrentWord $CurrentWord -Placeholder '<python-option>' -ToolTip 'Regular Python interpreter option (see python -h).')
            }

            return @(Get-PyTerminalCompletions -CurrentWord $CurrentWord -Placeholder '<launcher-arg>' -ToolTip 'Launcher-specific argument slot.')
        }

        return @(Get-PyUniqueResults -Results $results.ToArray())
    }

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        foreach ($item in @(Get-PyOptionCompletionList -Specs $OptionSpecs -CurrentWord $CurrentWord)) {
            [void]$results.Add($item)
        }
    }

    if ($IncludeCommands) {
        foreach ($commandSpec in @(Get-PyCommandTable)) {
            if (Test-PyStartsWith -Candidate $commandSpec.Name -Prefix $CurrentWord) {
                [void]$results.Add((New-PyCompletionResult -CompletionText $commandSpec.Name -ResultType 'ParameterValue' -ToolTip $commandSpec.Description))
            }
        }
    }

    foreach ($item in @(Get-PyPathCompletions -CurrentWord $CurrentWord -Placeholder '<script-path>')) {
        if ($results.Count -gt 0 -and [string]::Equals($item.CompletionText, $CurrentWord, [System.StringComparison]::Ordinal)) {
            # Skip the echo placeholder when a command name already matched.
            continue
        }

        [void]$results.Add($item)
    }

    @(Get-PyUniqueResults -Results $results.ToArray())
}

function Complete-Py {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $flavor = Get-PyLauncherFlavor
    $commandLineState = Get-PyCommandLineState -CommandAst $commandAst -CursorPosition $cursorPosition
    $argumentState = Get-PyArgumentState -CommandLineState $commandLineState
    $context = Get-PyCompletionContext -ArgumentsBeforeCurrent $argumentState.ArgumentsBeforeCurrent -Flavor $flavor
    $currentWord = if ($null -eq $argumentState.CurrentArgument) { '' } else { $argumentState.CurrentArgument }
    $optionSpecs = @(Get-PyContextOptionTable -Flavor $flavor -Command $context.Command)

    if ($context.TerminalMode -eq 'LauncherTerminal') {
        return @(Get-PyTerminalCompletions -CurrentWord $currentWord -Placeholder '<complete>' -ToolTip 'No further launcher arguments are valid after this terminal launcher option.')
    }

    if ($context.TerminalMode -eq 'ScriptTail') {
        return @(Get-PyTailCompletions -CurrentWord $currentWord)
    }

    # Attached --option=value form (the idiom the tool's own help uses: -f=exe, --target=.\runtime).
    if ($currentWord -match '^(?<option>--?[^=:]+)=(?<value>.*)$') {
        $optionMap = Get-PyOptionMap -Specs $optionSpecs
        $optionName = $Matches.option
        if ($optionMap.ContainsKey($optionName) -and -not [string]::IsNullOrWhiteSpace($optionMap[$optionName].ValueKind)) {
            return @(Get-PyValueCompletionList -ValueKind $optionMap[$optionName].ValueKind -CurrentWord $Matches.value -AttachedPrefix ($optionName + '='))
        }
    }

    if (-not [string]::IsNullOrEmpty($context.PendingValueKind)) {
        return @(Get-PyValueCompletionList -ValueKind $context.PendingValueKind -CurrentWord $currentWord)
    }

    if ($flavor -ne 'manager' -or [string]::IsNullOrEmpty($context.Command) -or $context.Command -eq 'exec') {
        return @(Get-PyLaunchSlotCompletionList -CurrentWord $currentWord -Flavor $flavor -RuntimeSelected $context.RuntimeSelected -OptionSpecs $optionSpecs -IncludeCommands ($flavor -eq 'manager' -and [string]::IsNullOrEmpty($context.Command)))
    }

    # install | list | uninstall | help
    if ($currentWord.StartsWith('-', [System.StringComparison]::Ordinal)) {
        $results = @(Get-PyOptionCompletionList -Specs $optionSpecs -CurrentWord $currentWord)
        if ($results.Count -eq 0) {
            return @(Get-PyTerminalCompletions -CurrentWord $currentWord -Placeholder '<option>' -ToolTip "Option for 'py $($context.Command)'.")
        }

        return $results
    }

    $results = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        foreach ($item in @(Get-PyOptionCompletionList -Specs $optionSpecs -CurrentWord $currentWord)) {
            [void]$results.Add($item)
        }
    }

    foreach ($item in @(Get-PyTagCompletionList -CurrentWord $currentWord -Command $context.Command)) {
        [void]$results.Add($item)
    }

    @(Get-PyUniqueResults -Results $results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('py', 'py.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Py -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
