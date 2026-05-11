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

function New-PyLauncherOptionSpec {
    param(
        [string]$Token,
        [string]$Description,
        [bool]$IsTerminal = $false
    )

    [pscustomobject]@{
        Token       = $Token
        Description = $Description
        IsTerminal  = $IsTerminal
    }
}

function Get-PyLauncherOptionSpecs {
    @(
        New-PyLauncherOptionSpec -Token '-2' -Description 'Launch the latest Python 2.x runtime.'
        New-PyLauncherOptionSpec -Token '-3' -Description 'Launch the latest Python 3.x runtime.'
        New-PyLauncherOptionSpec -Token '-32' -Description 'Restrict launcher selection to 32-bit runtimes.'
        New-PyLauncherOptionSpec -Token '-64' -Description 'Omit 32-bit runtimes when selecting a runtime.'
        New-PyLauncherOptionSpec -Token '-0' -Description 'List the available Python runtimes.' -IsTerminal $true
        New-PyLauncherOptionSpec -Token '--list' -Description 'List the available Python runtimes.' -IsTerminal $true
        New-PyLauncherOptionSpec -Token '-0p' -Description 'List the available Python runtimes with paths.' -IsTerminal $true
        New-PyLauncherOptionSpec -Token '--list-paths' -Description 'List the available Python runtimes with paths.' -IsTerminal $true
        New-PyLauncherOptionSpec -Token '-h' -Description 'Show Python Launcher for Windows help.' -IsTerminal $true
        New-PyLauncherOptionSpec -Token '-?' -Description 'Show Python Launcher for Windows help.' -IsTerminal $true
        New-PyLauncherOptionSpec -Token '--help' -Description 'Show Python Launcher for Windows help.' -IsTerminal $true
        New-PyLauncherOptionSpec -Token '-V:' -Description 'Select a runtime by tag or by COMPANY/TAG.'
    )
}

function Get-PyLauncherOptionMap {
    $map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($spec in Get-PyLauncherOptionSpecs) {
        $map[$spec.Token] = $spec
    }

    $map
}

function Resolve-PyCommandName {
    $cache = Get-Variable -Name PyCompletionResolvedCommand -Scope Script -ErrorAction SilentlyContinue
    if ($cache) {
        return $cache.Value
    }

    $resolved = $null
    $command = Get-Command -Name py.exe, py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $resolved = if ([string]::IsNullOrWhiteSpace($command.Source)) { $command.Name } else { $command.Source }
    }

    Set-Variable -Name PyCompletionResolvedCommand -Scope Script -Value $resolved
    $resolved
}

function Get-PyRuntimeTagCatalog {
    $cache = Get-Variable -Name PyCompletionRuntimeTagCatalog -Scope Script -ErrorAction SilentlyContinue
    if ($cache) {
        $age = (Get-Date) - $cache.Value.UpdatedAt
        if ($age.TotalSeconds -lt 300) {
            return $cache.Value
        }
    }

    $commandName = Resolve-PyCommandName
    $tagSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $qualifiedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $numericSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if (-not [string]::IsNullOrWhiteSpace($commandName)) {
        try {
            $lines = @(& $commandName -0p 2>$null)
            foreach ($line in $lines) {
                $match = [regex]::Match($line, '(?i)-V:(?<selector>\S+)')
                if (-not $match.Success) {
                    continue
                }

                $selector = $match.Groups['selector'].Value.Trim()
                if ([string]::IsNullOrWhiteSpace($selector)) {
                    continue
                }

                [void]$qualifiedSet.Add($selector)

                $tag = $selector
                if ($selector.Contains('/')) {
                    $tag = ($selector -split '/', 2)[1]
                }

                if (-not [string]::IsNullOrWhiteSpace($tag)) {
                    [void]$tagSet.Add($tag)
                    if ($tag -match '^\d+(?:\.\d+)*$') {
                        [void]$numericSet.Add($tag)
                    }
                }
            }
        } catch {
        }
    }

    $catalog = [pscustomobject]@{
        UpdatedAt          = Get-Date
        Tags               = @($tagSet | Sort-Object)
        QualifiedSelectors = @($qualifiedSet | Sort-Object)
        NumericTags        = @($numericSet | Sort-Object)
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

    $Token -match '^-\d+(?:\.\d+)*(?:-(?:32|64))?$'
}

function Test-PyVersionSelectorPrefix {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    $Token -match '^-\d+(?:\.\d*)?(?:-(?:32|64)?)?$'
}

function Test-PyPathLikeToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    $trimmed = $Token.TrimStart([char]34, [char]39)
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $false
    }

    if ($trimmed -match '^(?:\.{1,2}[\\/]|[\\/]|~[\\/]|[A-Za-z]:[\\/])') {
        return $true
    }

    $trimmed.Contains('\') -or $trimmed.Contains('/')
}

function Get-PyCompletionContext {
    param([string[]]$ArgumentsBeforeCurrent)

    $optionMap = Get-PyLauncherOptionMap
    $terminalMode = ''

    foreach ($argument in @($ArgumentsBeforeCurrent)) {
        if (-not [string]::IsNullOrEmpty($terminalMode)) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($argument)) {
            continue
        }

        if ($optionMap.ContainsKey($argument)) {
            if ($optionMap[$argument].IsTerminal) {
                $terminalMode = 'LauncherTerminal'
            }

            continue
        }

        if ($argument.StartsWith('-V:', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if (Test-PyVersionSelectorToken -Token $argument) {
            continue
        }

        if ($argument.StartsWith('-', [System.StringComparison]::Ordinal)) {
            continue
        }

        $terminalMode = 'ScriptTail'
    }

    [pscustomobject]@{
        TerminalMode = $terminalMode
    }
}

function Get-PyUniqueResults {
    param([object[]]$Results)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
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
        [string]$Placeholder
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($CurrentWord)) {
        [void]$results.Add([System.Management.Automation.CompletionResult]::new(
                $item.CompletionText,
                $item.ListItemText,
                $item.ResultType,
                $item.ToolTip
            ))
    }

    if ($results.Count -eq 0) {
        return @(Get-PyPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder $Placeholder -ToolTip 'Filesystem path.')
    }

    @($results.ToArray())
}

function Get-PyLauncherOptionCompletions {
    param([string]$CurrentWord)

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($spec in Get-PyLauncherOptionSpecs) {
        if (Test-PyStartsWith -Candidate $spec.Token -Prefix $CurrentWord) {
            [void]$results.Add((New-PyCompletionResult -CompletionText $spec.Token -ResultType 'ParameterName' -ToolTip $spec.Description))
        }
    }

    @(Get-PyUniqueResults -Results $results.ToArray())
}

function Get-PyVCompletions {
    param([string]$CurrentWord)

    $results = New-Object System.Collections.Generic.List[object]
    $catalog = Get-PyRuntimeTagCatalog
    $suffix = if ($CurrentWord.Length -ge 3) { $CurrentWord.Substring(3) } else { '' }

    if ($suffix.Contains('/')) {
        $separatorIndex = $suffix.IndexOf('/')
        $companyPrefix = $suffix.Substring(0, $separatorIndex + 1)
        $tagPrefix = $suffix.Substring($separatorIndex + 1)

        foreach ($tag in @($catalog.Tags)) {
            if (Test-PyStartsWith -Candidate $tag -Prefix $tagPrefix) {
                [void]$results.Add((New-PyCompletionResult -CompletionText "-V:$companyPrefix$tag" -ResultType 'ParameterValue' -ToolTip 'Launcher runtime selector by COMPANY/TAG.'))
            }
        }

        foreach ($selector in @($catalog.QualifiedSelectors)) {
            if (Test-PyStartsWith -Candidate $selector -Prefix $suffix) {
                [void]$results.Add((New-PyCompletionResult -CompletionText "-V:$selector" -ResultType 'ParameterValue' -ToolTip 'Installed launcher runtime selector.'))
            }
        }

        if ($results.Count -eq 0) {
            return @(Get-PyPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder "-V:$companyPrefix<TAG>" -ToolTip 'Launcher runtime selector by COMPANY/TAG.')
        }

        return @(Get-PyUniqueResults -Results $results.ToArray())
    }

    foreach ($tag in @($catalog.Tags)) {
        if (Test-PyStartsWith -Candidate $tag -Prefix $suffix) {
            [void]$results.Add((New-PyCompletionResult -CompletionText "-V:$tag" -ResultType 'ParameterValue' -ToolTip 'Installed launcher runtime selector by tag.'))
        }
    }

    foreach ($selector in @($catalog.QualifiedSelectors)) {
        if (Test-PyStartsWith -Candidate $selector -Prefix $suffix) {
            [void]$results.Add((New-PyCompletionResult -CompletionText "-V:$selector" -ResultType 'ParameterValue' -ToolTip 'Installed launcher runtime selector.'))
        }
    }

    if ([string]::IsNullOrWhiteSpace($suffix)) {
        [void]$results.Add((New-PyCompletionResult -CompletionText '-V:<TAG>' -ResultType 'ParameterValue' -ToolTip 'Launcher runtime selector by tag.' -ListItemText '-V:<TAG>'))
        [void]$results.Add((New-PyCompletionResult -CompletionText '-V:<COMPANY/TAG>' -ResultType 'ParameterValue' -ToolTip 'Launcher runtime selector by COMPANY/TAG.' -ListItemText '-V:<COMPANY/TAG>'))
    } elseif ($results.Count -eq 0) {
        $placeholder = if ($suffix.Contains('/')) { '-V:<COMPANY/TAG>' } else { '-V:<TAG>' }
        return @(Get-PyPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder $placeholder -ToolTip 'Launcher runtime selector.')
    }

    @(Get-PyUniqueResults -Results $results.ToArray())
}

function Get-PyVersionSelectorCompletions {
    param([string]$CurrentWord)

    $results = New-Object System.Collections.Generic.List[object]
    $catalog = Get-PyRuntimeTagCatalog
    $numericTags = New-Object System.Collections.Generic.List[string]

    foreach ($tag in @($catalog.NumericTags)) {
        [void]$numericTags.Add($tag)
    }

    foreach ($fallback in @('2', '3')) {
        if (-not $numericTags.Contains($fallback)) {
            [void]$numericTags.Add($fallback)
        }
    }

    foreach ($tag in @($numericTags.ToArray() | Sort-Object -Unique)) {
        foreach ($candidate in @("-$tag", "-$tag-32", "-$tag-64")) {
            if (Test-PyStartsWith -Candidate $candidate -Prefix $CurrentWord) {
                [void]$results.Add((New-PyCompletionResult -CompletionText $candidate -ResultType 'ParameterValue' -ToolTip 'Launcher version-selector form.'))
            }
        }
    }

    if ($results.Count -eq 0) {
        return @(Get-PyPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '-X.Y' -ToolTip 'Launcher version-selector form.')
    }

    @(Get-PyUniqueResults -Results $results.ToArray())
}

function Get-PyFirstPositionalCompletions {
    param(
        [string]$CurrentWord,
        [bool]$IncludeLauncherOptions
    )

    $results = New-Object System.Collections.Generic.List[object]

    if ($IncludeLauncherOptions) {
        foreach ($item in @(Get-PyLauncherOptionCompletions -CurrentWord $CurrentWord)) {
            [void]$results.Add($item)
        }
    }

    foreach ($item in @(Get-PyPathCompletions -CurrentWord $CurrentWord -Placeholder '<script-path>')) {
        [void]$results.Add($item)
    }

    @(Get-PyUniqueResults -Results $results.ToArray())
}

function Get-PyTailCompletions {
    param([string]$CurrentWord)

    if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $CurrentWord.StartsWith('-')) {
        return @(Get-PyPathCompletions -CurrentWord $CurrentWord -Placeholder '<script-arg-path>')
    }

    @(Get-PyTerminalCompletions -CurrentWord $CurrentWord -Placeholder '<script-arg>' -ToolTip 'Launcher option completion stops after the script operand.')
}

function Complete-Py {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $commandLineState = Get-PyCommandLineState -CommandAst $commandAst -CursorPosition $cursorPosition
    $argumentState = Get-PyArgumentState -CommandLineState $commandLineState
    $context = Get-PyCompletionContext -ArgumentsBeforeCurrent $argumentState.ArgumentsBeforeCurrent
    $currentWord = if ($null -eq $argumentState.CurrentArgument) { '' } else { $argumentState.CurrentArgument }

    if ($context.TerminalMode -eq 'LauncherTerminal') {
        return @(Get-PyTerminalCompletions -CurrentWord $currentWord -Placeholder '<complete>' -ToolTip 'No further launcher arguments are valid after this terminal launcher option.')
    }

    if ($context.TerminalMode -eq 'ScriptTail') {
        return @(Get-PyTailCompletions -CurrentWord $currentWord)
    }

    if ($currentWord.StartsWith('-V:', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @(Get-PyVCompletions -CurrentWord $currentWord)
    }

    if ($currentWord -eq '-V') {
        return @(
            New-PyCompletionResult -CompletionText '-V:' -ResultType 'ParameterName' -ToolTip 'Select a runtime by tag or by COMPANY/TAG.'
        )
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-PyFirstPositionalCompletions -CurrentWord $currentWord -IncludeLauncherOptions $true)
    }

    if ($currentWord.StartsWith('-', [System.StringComparison]::Ordinal)) {
        $results = New-Object System.Collections.Generic.List[object]

        foreach ($item in @(Get-PyLauncherOptionCompletions -CurrentWord $currentWord)) {
            [void]$results.Add($item)
        }

        if ((Test-PyVersionSelectorPrefix -Token $currentWord) -or ($currentWord -eq '-')) {
            foreach ($item in @(Get-PyVersionSelectorCompletions -CurrentWord $currentWord)) {
                [void]$results.Add($item)
            }
        }

        if ($currentWord.StartsWith('-V', [System.StringComparison]::OrdinalIgnoreCase)) {
            foreach ($item in @(Get-PyVCompletions -CurrentWord '-V:')) {
                if (Test-PyStartsWith -Candidate $item.CompletionText -Prefix $currentWord) {
                    [void]$results.Add($item)
                }
            }
        }

        if ($results.Count -eq 0) {
            return @(Get-PyTerminalCompletions -CurrentWord $currentWord -Placeholder '<launcher-arg>' -ToolTip 'Launcher-specific argument slot.')
        }

        return @(Get-PyUniqueResults -Results $results.ToArray())
    }

    if (Test-PyPathLikeToken -Token $currentWord) {
        return @(Get-PyPathCompletions -CurrentWord $currentWord -Placeholder '<script-path>')
    }

    @(Get-PyPathCompletions -CurrentWord $currentWord -Placeholder '<script-path>')
}

Register-ArgumentCompleter -Native -CommandName @('py', 'py.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Py -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
