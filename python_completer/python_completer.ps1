Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name PythonModuleCache -Scope Script -ErrorAction Ignore)) {
    $script:PythonModuleCache = @{
        RootsKey         = $null
        Roots            = @()
        NamesByDirectory = @{}
    }
}

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
        [string]$Prefix,
        [switch]$CaseSensitive
    )

    if ([string]::IsNullOrEmpty($Prefix)) {
        return $true
    }

    $comparison = if ($CaseSensitive) { [System.StringComparison]::Ordinal } else { [System.StringComparison]::OrdinalIgnoreCase }
    $Candidate.StartsWith($Prefix, $comparison)
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
        New-PythonOptionSpec -Tokens @('-W') -Description 'Warning control (action:message:category:module:lineno).' -ValueKind 'WarningFilter'
        New-PythonOptionSpec @('-x') 'Skip the first line of the source.'
        New-PythonOptionSpec @('-X') 'Set an implementation-specific option.' 'XOption'
        New-PythonOptionSpec @('--check-hash-based-pycs') 'Control validation behavior for hash-based .pyc files.' 'HashPycsMode'
        New-PythonOptionSpec @('--help-env') 'Show help about Python environment variables.'
        New-PythonOptionSpec @('--help-xoptions') 'Show help about implementation-specific -X options.'
        New-PythonOptionSpec @('--help-all') 'Show complete help output.'
    )
}

function Get-PythonOptionMap {
    # python's option parser is case-sensitive (-x and -X, -b and -B are different options).
    $map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)

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
    $quoteKind = ''

    foreach ($character in $prefix.ToCharArray()) {
        # PowerShell reads ' and U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes.
        $characterKind = if ($character -match '[''\u2018-\u201B]') { 'Single' } elseif ($character -match '["\u201C-\u201E]') { 'Double' } else { '' }
        if ($characterKind) {
            if (-not $quoteKind) {
                $quoteKind = $characterKind
            } elseif ($quoteKind -eq $characterKind) {
                $quoteKind = ''
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and -not $quoteKind) {
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

        if ($argument.StartsWith('-', [System.StringComparison]::Ordinal) -and $argument.Length -gt 1) {
            # Unknown or clustered switch: it is not the program operand.
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
    param(
        [object[]]$Results,
        [switch]$CaseSensitive
    )

    $comparer = if ($CaseSensitive) { [System.StringComparer]::Ordinal } else { [System.StringComparer]::OrdinalIgnoreCase }
    $seen = [System.Collections.Generic.HashSet[string]]::new($comparer)
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
            if (Test-PythonStartsWith -Candidate $token -Prefix $CurrentWord -CaseSensitive) {
                [void]$results.Add((New-PythonCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $spec.Description))
            }
        }
    }

    @(Get-PythonUniqueResults -Results $results.ToArray() -CaseSensitive)
}

function Get-PythonWarningFilterCompletions {
    param([string]$CurrentWord)

    $actions = @(
        @{ Name = 'default'; Description = 'Print the first occurrence of matching warnings for each location.' }
        @{ Name = 'error';   Description = 'Turn matching warnings into exceptions.' }
        @{ Name = 'always';  Description = 'Always print matching warnings.' }
        @{ Name = 'all';     Description = 'Alias for always.' }
        @{ Name = 'module';  Description = 'Print the first occurrence of matching warnings for each module.' }
        @{ Name = 'once';    Description = 'Print only the first occurrence of matching warnings.' }
        @{ Name = 'ignore';  Description = 'Never print matching warnings.' }
    )
    $categories = @(
        'Warning', 'DeprecationWarning', 'PendingDeprecationWarning', 'UserWarning', 'SyntaxWarning',
        'RuntimeWarning', 'FutureWarning', 'ImportWarning', 'UnicodeWarning', 'BytesWarning',
        'ResourceWarning', 'EncodingWarning'
    )

    $results = New-Object System.Collections.Generic.List[object]
    $fields = @($CurrentWord.Split([char]':'))

    if ($fields.Count -eq 1) {
        foreach ($action in $actions) {
            if (Test-PythonStartsWith -Candidate $action.Name -Prefix $CurrentWord) {
                [void]$results.Add((New-PythonCompletionResult -CompletionText $action.Name -ResultType 'ParameterValue' -ToolTip $action.Description))
            }
        }
    } elseif ($fields.Count -eq 3) {
        $prefix = ($fields[0], $fields[1]) -join ':'
        foreach ($category in $categories) {
            if (Test-PythonStartsWith -Candidate $category -Prefix $fields[2]) {
                [void]$results.Add((New-PythonCompletionResult -CompletionText "${prefix}:$category" -ResultType 'ParameterValue' -ToolTip "Warning category $category" -ListItemText $category))
            }
        }
    }

    if ($results.Count -eq 0) {
        return @(Get-PythonPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '<action:message:category:module:lineno>' -ToolTip 'Warning filter for -W.')
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

function ConvertFrom-PythonTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    # A quote closed mid-word ('my dir'\s) is more than one token and yields $null.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    if ($tokens[0].Extent.EndOffset -lt $Value.Length) {
        return $null
    }

    $tokens[0].Value
}

function ConvertTo-PythonQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default). PowerShell reads ' and
    # U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes.
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $QuoteChar) {
        # A bare word starting with a dash would be read as a parameter name.
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]|^[-\u2013-\u2015]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-PythonPathResults {
    param(
        [string]$CurrentWord,
        [string]$Placeholder = '<script-or-path>'
    )

    $results = New-Object System.Collections.Generic.List[object]
    $quoteChar = if ($CurrentWord -match '^[''"\u2018-\u201E]') { $CurrentWord.Substring(0, 1) } else { '' }
    $typedValue = ConvertFrom-PythonTypedWord -Value $CurrentWord
    $items = if ($null -eq $typedValue) { @() } else { [System.Management.Automation.CompletionCompleters]::CompleteFilename($typedValue) }

    # CompleteFilename rewrites a typed .\ ./ ..\ ../ directory relative to the current location
    # (./s becomes .\spam.py); the typed directory is kept verbatim instead.
    $typedDirectory = ''
    if ($typedValue -match '^\.{1,2}[\\/]') {
        $typedDirectory = $typedValue.Substring(0, $typedValue.LastIndexOfAny([char[]]@('\', '/')) + 1)
        if ($typedDirectory -match '[*?\[]') {
            $typedDirectory = ''
        }
    }

    # CompleteFilename returns PowerShell-quoted, wildcard-escaped text (tick``x.txt inside
    # single quotes), so each result is unwrapped by the parser and unescaped, then quoted once.
    foreach ($item in $items) {
        $path = $item.CompletionText
        if ($path -match '^[''"\u2018-\u201E]') {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($path, [ref]$null, [ref]$null)
            $constant = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
            if ($constant) {
                $path = $constant.Value
            }
        }

        $path = [System.Management.Automation.WildcardPattern]::Unescape($path)
        if ($typedDirectory) {
            $path = $typedDirectory + [System.IO.Path]::GetFileName($path.TrimEnd([char[]]@('\', '/')))
        }

        [void]$results.Add([System.Management.Automation.CompletionResult]::new(
                (ConvertTo-PythonQuotedValue -Value $path -QuoteChar $quoteChar),
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

function Get-PythonModuleRoot {
    # The import roots behind 'python -m', read from the interpreter's layout on disk; no process is started.
    $cache = $script:PythonModuleCache
    $key = "$env:PATH|$env:PYTHONNOUSERSITE"
    if ($cache.RootsKey -ceq $key) {
        return @($cache.Roots)
    }

    $roots = New-Object System.Collections.Generic.List[object]
    $command = Get-Command -Name python -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    $executable = if ($null -eq $command) { '' } else { $command.Source }
    if ($executable) {
        $targetFile = "$executable.__target__"
        if ([System.IO.File]::Exists($targetFile)) {
            # Python install manager shims record the real interpreter beside themselves.
            $executable = [System.IO.File]::ReadAllText($targetFile).Trim()
        }
    }

    $binDirectory = if ($executable) { [System.IO.Path]::GetDirectoryName($executable) } else { '' }
    if ($binDirectory) {
        $venvDirectory = [System.IO.Path]::GetDirectoryName($binDirectory)
        $venvConfig = if ([string]::IsNullOrEmpty($venvDirectory)) { '' } else { [System.IO.Path]::Combine($venvDirectory, 'pyvenv.cfg') }
        $baseDirectory = $binDirectory
        $siteDirectories = New-Object System.Collections.Generic.List[object]

        if ($venvConfig -and [System.IO.File]::Exists($venvConfig)) {
            $settings = @{}
            foreach ($configLine in [System.IO.File]::ReadAllLines($venvConfig)) {
                if ($configLine -match '^\s*([^=]+?)\s*=\s*(.*?)\s*$') {
                    $settings[$Matches[1]] = $Matches[2]
                }
            }

            $baseDirectory = if ($settings.ContainsKey('home')) { $settings['home'] } else { '' }
            [void]$siteDirectories.Add(@([System.IO.Path]::Combine($venvDirectory, 'Lib', 'site-packages'), 'venv site-packages'))
            if ($settings.ContainsKey('include-system-site-packages') -and $settings['include-system-site-packages'] -eq 'true' -and $baseDirectory) {
                [void]$siteDirectories.Add(@([System.IO.Path]::Combine($baseDirectory, 'Lib', 'site-packages'), 'site-packages'))
            }
        } else {
            $versionDll = if ([System.IO.Directory]::Exists($baseDirectory)) {
                [System.IO.Directory]::GetFiles($baseDirectory, 'python3*.dll') |
                    ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) } |
                    Where-Object { $_ -match '^python3\d+t?$' } |
                    Select-Object -First 1
            }
            if ($versionDll -and $env:APPDATA -and -not $env:PYTHONNOUSERSITE) {
                [void]$siteDirectories.Add(@([System.IO.Path]::Combine($env:APPDATA, 'Python', ('P' + $versionDll.Substring(1)), 'site-packages'), 'user site-packages'))
            }
            [void]$siteDirectories.Add(@([System.IO.Path]::Combine($baseDirectory, 'Lib', 'site-packages'), 'site-packages'))
        }

        $candidates = @()
        if ($baseDirectory) {
            $candidates += , @([System.IO.Path]::Combine($baseDirectory, 'DLLs'), 'stdlib extension')
            $candidates += , @([System.IO.Path]::Combine($baseDirectory, 'Lib'), 'stdlib')
        }
        $candidates += $siteDirectories.ToArray()

        foreach ($candidate in $candidates) {
            if ([System.IO.Directory]::Exists($candidate[0])) {
                [void]$roots.Add([pscustomobject]@{ Path = $candidate[0]; Kind = $candidate[1]; RequirePackageMarker = $false; IsSite = $candidate[1].EndsWith('site-packages') })
            }
        }
    }

    $cache.Roots = @($roots.ToArray())
    $cache.RootsKey = $key
    @($cache.Roots)
}

function Get-PythonPthDirectory {
    param([string]$SiteDirectory)

    # Each .pth line in a site directory appends that path to sys.path; 'import' lines run code and are skipped.
    $cache = $script:PythonModuleCache.NamesByDirectory
    $cacheKey = "$SiteDirectory|pth"
    $stamp = [System.IO.Directory]::GetLastWriteTimeUtc($SiteDirectory)
    if ($cache.ContainsKey($cacheKey) -and $cache[$cacheKey].Stamp -eq $stamp) {
        return @($cache[$cacheKey].Entries)
    }

    $directories = New-Object System.Collections.Generic.List[string]
    foreach ($pthFile in [System.IO.Directory]::GetFiles($SiteDirectory, '*.pth')) {
        foreach ($pthLine in [System.IO.File]::ReadAllLines($pthFile)) {
            $entry = $pthLine.Trim()
            if (-not $entry -or $entry.StartsWith('#') -or $entry -match '^import[ \t]') {
                continue
            }

            $directory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($SiteDirectory, $entry))
            if ([System.IO.Directory]::Exists($directory) -and -not $directories.Contains($directory)) {
                [void]$directories.Add($directory)
            }
        }
    }

    $cache[$cacheKey] = [pscustomobject]@{ Stamp = $stamp; Entries = @($directories.ToArray()) }
    @($directories.ToArray())
}

function Get-PythonDirectoryModule {
    param(
        [string]$Directory,
        [bool]$RequirePackageMarker
    )

    # A directory's entry list only changes when its own LastWriteTime does, so that stamp keys the cache.
    $cache = $script:PythonModuleCache.NamesByDirectory
    $cacheKey = "$Directory|$RequirePackageMarker"
    $stamp = [System.IO.Directory]::GetLastWriteTimeUtc($Directory)
    if ($cache.ContainsKey($cacheKey) -and $cache[$cacheKey].Stamp -eq $stamp) {
        return @($cache[$cacheKey].Entries)
    }

    $modules = New-Object System.Collections.Generic.List[object]
    foreach ($entry in [System.IO.DirectoryInfo]::new($Directory).EnumerateFileSystemInfos()) {
        $isPackage = $entry -is [System.IO.DirectoryInfo]
        if ($isPackage) {
            if ($RequirePackageMarker -and -not [System.IO.File]::Exists([System.IO.Path]::Combine($entry.FullName, '__init__.py'))) {
                continue
            }

            $moduleName = $entry.Name
        } elseif ($entry.Extension -eq '.py' -or $entry.Extension -eq '.pyw') {
            $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($entry.Name)
        } elseif ($entry.Extension -eq '.pyd') {
            $moduleName = $entry.Name.Substring(0, $entry.Name.IndexOf('.'))
        } else {
            continue
        }

        if ($moduleName -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $moduleName -ceq '__pycache__' -or $moduleName -ceq '__init__' -or $moduleName -ceq '__main__') {
            continue
        }

        [void]$modules.Add([pscustomobject]@{ Name = $moduleName; IsPackage = $isPackage })
    }

    $cache[$cacheKey] = [pscustomobject]@{ Stamp = $stamp; Entries = @($modules.ToArray()) }
    @($modules.ToArray())
}

function Get-PythonModuleCompletions {
    param([string]$CurrentWord)

    $quote = ''
    $word = $CurrentWord
    if ($word.Length -gt 0 -and ($word[0] -eq [char]39 -or $word[0] -eq [char]34)) {
        $quote = [string]$word[0]
        $word = $word.Substring(1)
    }

    $lastDot = $word.LastIndexOf('.')
    $parentName = if ($lastDot -ge 0) { $word.Substring(0, $lastDot) } else { '' }
    $leaf = $word.Substring($lastDot + 1)
    $parentValid = [string]::IsNullOrEmpty($parentName) -or $parentName -cmatch '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$'
    $results = New-Object System.Collections.Generic.List[object]

    if ($parentValid) {
        # 'python -m' puts the current directory first on sys.path; there only real packages count.
        $searchRoots = New-Object System.Collections.Generic.List[object]
        [void]$searchRoots.Add([pscustomobject]@{ Path = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath; Kind = 'current directory'; RequirePackageMarker = $true })
        foreach ($root in @(Get-PythonModuleRoot)) {
            [void]$searchRoots.Add($root)
            if ($root.IsSite) {
                foreach ($pthDirectory in @(Get-PythonPthDirectory -SiteDirectory $root.Path)) {
                    [void]$searchRoots.Add([pscustomobject]@{ Path = $pthDirectory; Kind = "$($root.Kind) .pth"; RequirePackageMarker = $false })
                }
            }
        }

        $relativePath = $parentName.Replace('.', [System.IO.Path]::DirectorySeparatorChar)
        $toolTips = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
        $names = New-Object System.Collections.Generic.List[string]
        $includePrivate = $leaf.StartsWith('_', [System.StringComparison]::Ordinal)
        $namePrefix = if ($parentName) { "$parentName." } else { '' }

        foreach ($root in $searchRoots) {
            $directory = if ($relativePath) { [System.IO.Path]::Combine($root.Path, $relativePath) } else { $root.Path }
            if (-not [System.IO.Directory]::Exists($directory)) {
                continue
            }

            foreach ($module in @(Get-PythonDirectoryModule -Directory $directory -RequirePackageMarker $root.RequirePackageMarker)) {
                if (-not $module.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase) -or (-not $includePrivate -and $module.Name.StartsWith('_', [System.StringComparison]::Ordinal))) {
                    continue
                }

                $fullName = $namePrefix + $module.Name
                if (-not $toolTips.ContainsKey($fullName)) {
                    $kind = if ($module.IsPackage) { 'package' } else { 'module' }
                    $toolTips[$fullName] = "$($root.Kind) $kind ($directory)"
                    [void]$names.Add($fullName)
                }
            }
        }

        $names.Sort([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in $names) {
            [void]$results.Add([System.Management.Automation.CompletionResult]::new("$quote$name$quote", $name, 'ParameterValue', $toolTips[$name]))
        }
    }

    if ($results.Count -eq 0) {
        return @(Get-PythonPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '<module>' -ToolTip 'Module name for python -m.')
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

    if (-not $CurrentWord.StartsWith('-')) {
        # The script operand is python's dominant invocation, so list files from an empty word too.
        foreach ($item in @(Get-PythonPathResults -CurrentWord $CurrentWord -Placeholder '<script-or-path>')) {
            [void]$results.Add($item)
        }
    }

    @(Get-PythonUniqueResults -Results $results.ToArray() -CaseSensitive)
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
            'WarningFilter' { return @(Get-PythonWarningFilterCompletions -CurrentWord $currentWord) }
            'ModuleName'    { return @(Get-PythonModuleCompletions -CurrentWord $currentWord) }
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
