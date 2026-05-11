Set-StrictMode -Version 2.0

function New-PythonCompletionResult {
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

function Test-PythonStartsWith {
    param(
        [string]$Candidate,
        [string]$Prefix
    )

    [string]::IsNullOrEmpty($Prefix) -or $Candidate.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function New-PythonOptionSpec {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [string]$ValueKind = ''
    )

    [pscustomobject]@{
        Tokens      = @($Tokens)
        Description = $Description
        ValueKind   = $ValueKind
    }
}

function New-PythonXOptionSpec {
    param(
        [string]$Name,
        [string]$Description,
        [string[]]$ValueHints = @(),
        [bool]$AllowBare = $true
    )

    [pscustomobject]@{
        Name        = $Name
        Description = $Description
        ValueHints  = @($ValueHints)
        AllowBare   = $AllowBare
    }
}

function Get-PythonOptionSpecs {
    @(
        New-PythonOptionSpec @('-b') 'Issue warnings about str(bytes_instance), str(bytearray_instance), and bytes/int comparisons.'
        New-PythonOptionSpec @('-bb') 'Issue errors instead of warnings for bytes/str and bytes/int comparisons.'
        New-PythonOptionSpec @('-B') 'Do not write .pyc files on import.'
        New-PythonOptionSpec @('-c') 'Run the given command string.' 'CommandString'
        New-PythonOptionSpec @('-d') 'Turn on parser debugging output.'
        New-PythonOptionSpec @('-E') 'Ignore PYTHON* environment variables.'
        New-PythonOptionSpec @('-h', '-?', '--help') 'Show python command-line help.'
        New-PythonOptionSpec @('-i') 'Inspect interactively after running a script or command.'
        New-PythonOptionSpec @('-I') 'Isolated mode: imply -E and -s.'
        New-PythonOptionSpec @('-m') 'Run a library module as a script.' 'ModuleName'
        New-PythonOptionSpec @('-O') 'Remove assert statements and __debug__-dependent code.'
        New-PythonOptionSpec @('-OO') 'Also discard docstrings when optimizing.'
        New-PythonOptionSpec @('-P') 'Do not prepend a potentially unsafe path to sys.path.'
        New-PythonOptionSpec @('-q') 'Do not print the copyright and version messages on interactive startup.'
        New-PythonOptionSpec @('-s') 'Do not add the user site-packages directory to sys.path.'
        New-PythonOptionSpec @('-S') 'Do not imply import site on initialization.'
        New-PythonOptionSpec @('-u') 'Force stdout and stderr to be unbuffered.'
        New-PythonOptionSpec @('-v') 'Verbose import tracing.'
        New-PythonOptionSpec @('-V', '--version') 'Print the Python version number and exit.'
        New-PythonOptionSpec @('-W') 'Warning control.' 'WarningFilter'
        New-PythonOptionSpec @('-x') 'Skip the first line of the source.'
        New-PythonOptionSpec @('-X') 'Set an implementation-specific option.' 'XOption'
        New-PythonOptionSpec @('--check-hash-based-pycs') 'Control validation behavior for hash-based .pyc files.' 'HashPycsMode'
        New-PythonOptionSpec @('--help-env') 'Show help about Python environment variables.'
        New-PythonOptionSpec @('--help-xoptions') 'Show help about implementation-specific -X options.'
        New-PythonOptionSpec @('--help-all') 'Show complete help output.'
    )
}

function Get-PythonOptionMap {
    $map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($spec in Get-PythonOptionSpecs) {
        foreach ($token in $spec.Tokens) {
            $map[$token] = $spec
        }
    }

    $map
}

function Get-PythonXOptionSpecs {
    @(
        New-PythonXOptionSpec -Name 'context_aware_warnings' -Description 'Enable or disable context-aware warnings.' -ValueHints @('0', '1')
        New-PythonXOptionSpec -Name 'cpu_count' -Description 'Override os.cpu_count() and related APIs.' -ValueHints @('default', '<N>') -AllowBare $false
        New-PythonXOptionSpec -Name 'dev' -Description 'Enable Python development mode.'
        New-PythonXOptionSpec -Name 'disable-remote-debug' -Description 'Disable remote debugging support.'
        New-PythonXOptionSpec -Name 'faulthandler' -Description 'Enable faulthandler.'
        New-PythonXOptionSpec -Name 'frozen_modules' -Description 'Control frozen module usage.' -ValueHints @('on', 'off')
        New-PythonXOptionSpec -Name 'importtime' -Description 'Show import timing information.' -ValueHints @('2')
        New-PythonXOptionSpec -Name 'int_max_str_digits' -Description 'Limit int-to-string conversion digit count.' -ValueHints @('<N>') -AllowBare $false
        New-PythonXOptionSpec -Name 'no_debug_ranges' -Description 'Disable extra location tables for tracebacks.'
        New-PythonXOptionSpec -Name 'perf' -Description 'Enable Linux perf profiler support.'
        New-PythonXOptionSpec -Name 'perf_jit' -Description 'Enable Linux perf JIT support.'
        New-PythonXOptionSpec -Name 'pycache_prefix' -Description 'Write bytecode caches under the given prefix path.' -ValueHints @('<PATH>') -AllowBare $false
        New-PythonXOptionSpec -Name 'showrefcount' -Description 'Display total reference count and memory blocks at shutdown.'
        New-PythonXOptionSpec -Name 'thread_inherit_context' -Description 'Control thread context inheritance.' -ValueHints @('0', '1')
        New-PythonXOptionSpec -Name 'tracemalloc' -Description 'Start tracing memory allocations.' -ValueHints @('1', '<N>')
        New-PythonXOptionSpec -Name 'utf8' -Description 'Enable or disable UTF-8 mode.' -ValueHints @('0', '1')
        New-PythonXOptionSpec -Name 'warn_default_encoding' -Description 'Enable EncodingWarning for default encodings.'
    )
}

function Get-PythonCommandLineState {
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

function Get-PythonArgumentState {
    param([pscustomobject]$CommandLineState)

    $tokensBeforeCurrent = @($CommandLineState.TokensBeforeCurrent)
    $currentArgument = if ($null -eq $CommandLineState.CurrentToken) { '' } else { $CommandLineState.CurrentToken }
    $argumentsBeforeCurrent = if ($tokensBeforeCurrent.Count -gt 0) {
        @($tokensBeforeCurrent | Select-Object -Skip 1)
    } else {
        @()
    }

    if ($tokensBeforeCurrent.Count -eq 0 -and $currentArgument -match '^(?i:python(?:\.exe)?)$') {
        $currentArgument = ''
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = $argumentsBeforeCurrent
        CurrentArgument        = $currentArgument
    }
}

function Get-PythonCompletionContext {
    param([string[]]$ArgumentsBeforeCurrent)

    $optionMap = Get-PythonOptionMap
    $pendingValueKind = ''
    $terminalMode = ''

    foreach ($argument in @($ArgumentsBeforeCurrent)) {
        if (-not [string]::IsNullOrEmpty($terminalMode)) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($argument)) {
            continue
        }

        $consumedPendingValue = $false
        if (-not [string]::IsNullOrEmpty($pendingValueKind)) {
            switch ($pendingValueKind) {
                'CommandString' {
                    $pendingValueKind = ''
                    $terminalMode = 'CommandTail'
                    $consumedPendingValue = $true
                    break
                }
                'ModuleName' {
                    $pendingValueKind = ''
                    $terminalMode = 'ModuleTail'
                    $consumedPendingValue = $true
                    break
                }
                default {
                    $pendingValueKind = ''
                    $consumedPendingValue = $true
                    break
                }
            }

            if ($consumedPendingValue) {
                continue
            }
        }

        if ($optionMap.ContainsKey($argument)) {
            $valueKind = $optionMap[$argument].ValueKind
            if (-not [string]::IsNullOrWhiteSpace($valueKind)) {
                $pendingValueKind = $valueKind
            }

            continue
        }

        $terminalMode = 'ScriptTail'
    }

    [pscustomobject]@{
        PendingValueKind = $pendingValueKind
        TerminalMode     = $terminalMode
    }
}

function Get-PythonUniqueResults {
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

function Get-PythonOptionCompletions {
    param([string]$CurrentWord)

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($spec in Get-PythonOptionSpecs) {
        foreach ($token in $spec.Tokens) {
            if (Test-PythonStartsWith -Candidate $token -Prefix $CurrentWord) {
                [void]$results.Add((New-PythonCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $spec.Description))
            }
        }
    }

    @(Get-PythonUniqueResults -Results $results.ToArray())
}

function Get-PythonClosedValueCompletions {
    param(
        [string[]]$Values,
        [string]$CurrentWord,
        [string]$ToolTip
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($value in @($Values)) {
        if (Test-PythonStartsWith -Candidate $value -Prefix $CurrentWord) {
            [void]$results.Add((New-PythonCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip $ToolTip))
        }
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { '<value>' } else { $CurrentWord }
        [void]$results.Add((New-PythonCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    @($results.ToArray())
}

function Get-PythonPlaceholderCompletions {
    param(
        [string]$CurrentWord,
        [string]$Placeholder,
        [string]$ToolTip
    )

    $completionText = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { $Placeholder } else { $CurrentWord }
    @(
        New-PythonCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-PythonXOptionCompletions {
    param([string]$CurrentWord)

    $results = New-Object System.Collections.Generic.List[object]
    $xOptions = @(Get-PythonXOptionSpecs)

    if ($CurrentWord -match '^(?<name>[^=]+)=(?<value>.*)$') {
        $typedName = $Matches.name
        $typedValue = $Matches.value

        foreach ($spec in $xOptions) {
            if (-not $spec.Name.StartsWith($typedName, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            foreach ($valueHint in @($spec.ValueHints)) {
                if ([string]::IsNullOrWhiteSpace($valueHint)) {
                    continue
                }

                if (-not (Test-PythonStartsWith -Candidate $valueHint -Prefix $typedValue)) {
                    continue
                }

                [void]$results.Add((New-PythonCompletionResult -CompletionText "$($spec.Name)=$valueHint" -ResultType 'ParameterValue' -ToolTip $spec.Description))
            }
        }

        if ($results.Count -eq 0) {
            return @(Get-PythonPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '<xoption>' -ToolTip 'Python -X option.')
        }

        return @(Get-PythonUniqueResults -Results $results.ToArray())
    }

    foreach ($spec in $xOptions) {
        if ($spec.AllowBare -and (Test-PythonStartsWith -Candidate $spec.Name -Prefix $CurrentWord)) {
            [void]$results.Add((New-PythonCompletionResult -CompletionText $spec.Name -ResultType 'ParameterValue' -ToolTip $spec.Description))
        }

        foreach ($valueHint in @($spec.ValueHints)) {
            if ([string]::IsNullOrWhiteSpace($valueHint)) {
                continue
            }

            $candidate = "$($spec.Name)=$valueHint"
            if (Test-PythonStartsWith -Candidate $candidate -Prefix $CurrentWord) {
                [void]$results.Add((New-PythonCompletionResult -CompletionText $candidate -ResultType 'ParameterValue' -ToolTip $spec.Description))
            }
        }
    }

    if ($results.Count -eq 0) {
        return @(Get-PythonPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '<xoption>' -ToolTip 'Python -X option.')
    }

    @(Get-PythonUniqueResults -Results $results.ToArray())
}

function Get-PythonPathResults {
    param(
        [string]$CurrentWord,
        [string]$Placeholder = '<script-or-path>'
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
        return @(Get-PythonPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder $Placeholder -ToolTip 'Filesystem path.')
    }

    @($results.ToArray())
}

function Get-PythonFirstPositionalCompletions {
    param(
        [string]$CurrentWord,
        [bool]$IncludeRootOptions = $false
    )

    $results = New-Object System.Collections.Generic.List[object]

    if ('-'.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$results.Add((New-PythonCompletionResult -CompletionText '-' -ResultType 'ParameterValue' -ToolTip 'Read the Python program from standard input.'))
    }

    if ($IncludeRootOptions) {
        foreach ($item in @(Get-PythonOptionCompletions -CurrentWord $CurrentWord)) {
            [void]$results.Add($item)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $CurrentWord.StartsWith('-')) {
        foreach ($item in @(Get-PythonPathResults -CurrentWord $CurrentWord -Placeholder '<script-or-path>')) {
            [void]$results.Add($item)
        }
    }

    @(Get-PythonUniqueResults -Results $results.ToArray())
}

function Get-PythonTailCompletions {
    param(
        [string]$CurrentWord,
        [string]$TerminalMode
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and -not $CurrentWord.StartsWith('-')) {
        return @(Get-PythonPathResults -CurrentWord $CurrentWord -Placeholder '<arg-path>')
    }

    switch ($TerminalMode) {
        'CommandTail' { return @(Get-PythonPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '<command-arg>' -ToolTip 'Argument passed after python -c.') }
        'ModuleTail'  { return @(Get-PythonPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '<module-arg>' -ToolTip 'Argument passed after python -m.') }
        default       { return @(Get-PythonPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '<script-arg>' -ToolTip 'Argument passed to the Python program.') }
    }
}

function Complete-Python {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $commandLineState = Get-PythonCommandLineState -CommandAst $commandAst -CursorPosition $cursorPosition
    $argumentState = Get-PythonArgumentState -CommandLineState $commandLineState
    $currentWord = if ($null -eq $argumentState.CurrentArgument) { '' } else { $argumentState.CurrentArgument }
    $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent)
    $context = Get-PythonCompletionContext -ArgumentsBeforeCurrent $argumentsBeforeCurrent

    if (-not [string]::IsNullOrEmpty($context.PendingValueKind)) {
        switch ($context.PendingValueKind) {
            'HashPycsMode'  { return @(Get-PythonClosedValueCompletions -Values @('always', 'default', 'never') -CurrentWord $currentWord -ToolTip 'Value for --check-hash-based-pycs.') }
            'XOption'       { return @(Get-PythonXOptionCompletions -CurrentWord $currentWord) }
            'WarningFilter' { return @(Get-PythonPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<action:message:category:module:lineno>' -ToolTip 'Warning filter for -W.') }
            'ModuleName'    { return @(Get-PythonPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<module>' -ToolTip 'Module name for python -m.') }
            'CommandString' { return @(Get-PythonPlaceholderCompletions -CurrentWord $currentWord -Placeholder '<command-string>' -ToolTip 'Command string for python -c.') }
        }
    }

    if (-not [string]::IsNullOrEmpty($context.TerminalMode)) {
        return @(Get-PythonTailCompletions -CurrentWord $currentWord -TerminalMode $context.TerminalMode)
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-PythonFirstPositionalCompletions -CurrentWord $currentWord -IncludeRootOptions $true)
    }

    if ($currentWord -eq '-') {
        return @(Get-PythonFirstPositionalCompletions -CurrentWord $currentWord -IncludeRootOptions $true)
    }

    if ($currentWord.StartsWith('-')) {
        return @(Get-PythonOptionCompletions -CurrentWord $currentWord)
    }

    @(Get-PythonFirstPositionalCompletions -CurrentWord $currentWord)
}

Register-ArgumentCompleter -Native -CommandName @('python', 'python.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Python -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
