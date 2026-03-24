Set-StrictMode -Version Latest

if (-not (Get-Variable -Name GawkCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:GawkCompletionCatalog = @{
        Initialized             = $false
        ProbedExecutable        = $false
        ExecutablePath          = $null
        OptionDefinitions       = @()
        CanonicalOptionMap      = @{}
        ShortOptionMap          = $null
        LongOptionMap           = @{}
        UniqueLongPrefixMap     = @{}
        MinimalLongAbbreviations = @{}
        LongSuggestions         = @()
        LoadExtensions          = @()
        LintValues              = @('fatal', 'invalid', 'no-ext')
        FieldSeparators         = @(
            @{ Text = ','; Tooltip = 'Comma-separated fields' }
            @{ Text = ':'; Tooltip = 'Colon-separated fields' }
            @{ Text = ';'; Tooltip = 'Semicolon-separated fields' }
            @{ Text = '|'; Tooltip = 'Pipe-separated fields' }
            @{ Text = '\t'; Tooltip = 'Tab character' }
            @{ Text = '[[:space:]]+'; Tooltip = 'Runs of whitespace' }
        )
        AssignmentSuggestions   = @(
            @{ Text = 'name='; Tooltip = 'Set an awk variable assignment' }
            @{ Text = 'FS='; Tooltip = 'Field separator' }
            @{ Text = 'OFS='; Tooltip = 'Output field separator' }
            @{ Text = 'RS='; Tooltip = 'Record separator' }
            @{ Text = 'ORS='; Tooltip = 'Output record separator' }
            @{ Text = 'IGNORECASE='; Tooltip = 'Case-insensitive matching' }
            @{ Text = 'BINMODE='; Tooltip = 'Binary/text file mode selection' }
            @{ Text = 'CONVFMT='; Tooltip = 'Numeric-to-string conversion format' }
            @{ Text = 'OFMT='; Tooltip = 'Default numeric output format' }
        )
    }
}

function New-GawkCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ListItemText = $CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip = $CompletionText
    )

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Get-GawkExecutablePath {
    param([string]$CommandName = 'gawk')

    if ($script:GawkCompletionCatalog.ProbedExecutable) {
        return $script:GawkCompletionCatalog.ExecutablePath
    }

    $script:GawkCompletionCatalog.ProbedExecutable = $true

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($CommandName)) {
        $leafName = Split-Path -Leaf $CommandName
        if (-not [string]::IsNullOrWhiteSpace($leafName)) {
            $candidates += $leafName
        }
    }
    $candidates += @('gawk.exe', 'gawk', 'awk.exe', 'awk')

    foreach ($candidate in $candidates | Select-Object -Unique) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($command) {
            $script:GawkCompletionCatalog.ExecutablePath = $command.Source
            break
        }
    }

    $script:GawkCompletionCatalog.ExecutablePath
}

function Get-GawkHelpText {
    param([string]$CommandName = 'gawk')

    $executablePath = Get-GawkExecutablePath -CommandName $CommandName
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        return ''
    }

    try {
        ((& $executablePath --help 2>$null) -join "`n")
    } catch {
        ''
    }
}

function Get-GawkHelpOptionTokens {
    param([string]$HelpText)

    if ([string]::IsNullOrWhiteSpace($HelpText)) {
        return @()
    }

    $tokenMatches = [regex]::Matches(
        $HelpText,
        '(?<!\w)(--[a-z][a-z\-]*)(?:\[[^\]]+\])?(?:=[^\s]+)?|(?<!\w)(-[A-Za-z])(?:\[[^\]]+\])?'
    )

    $seen = @{}
    $results = New-Object System.Collections.Generic.List[string]
    foreach ($match in $tokenMatches) {
        $token = if ($match.Groups[1].Success) {
            $match.Groups[1].Value
        } else {
            $match.Groups[2].Value
        }

        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        $key = $token.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        [void]$results.Add($token)
    }

    @($results.ToArray())
}

function Get-GawkStaticOptionDefinitions {
    @(
        @{
            Short = '-f'; Long = '--file'; Canonical = '--file'
            Description = 'Read awk program source from file'
            ValueMode = 'Required'; ValueKind = 'SourceFile'
            ShortAllowsSeparate = $true; ShortAllowsAttached = $true
            LongAllowsSeparate = $true; LongAllowsEquals = $true
            ProvidesProgramSource = $true
        }
        @{
            Short = '-F'; Long = '--field-separator'; Canonical = '--field-separator'
            Description = 'Set FS to the given field separator'
            ValueMode = 'Required'; ValueKind = 'FieldSeparator'
            ShortAllowsSeparate = $true; ShortAllowsAttached = $true
            LongAllowsSeparate = $true; LongAllowsEquals = $true
        }
        @{
            Short = '-v'; Long = '--assign'; Canonical = '--assign'
            Description = 'Assign an awk variable before execution starts'
            ValueMode = 'Required'; ValueKind = 'Assignment'
            ShortAllowsSeparate = $true; ShortAllowsAttached = $true
            LongAllowsSeparate = $true; LongAllowsEquals = $true
        }
        @{
            Short = '-b'; Long = '--characters-as-bytes'; Canonical = '--characters-as-bytes'
            Description = 'Treat input and output data as single-byte characters'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-c'; Long = '--traditional'; Canonical = '--traditional'
            Description = 'Disable GNU awk language extensions'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-C'; Long = '--copyright'; Canonical = '--copyright'
            Description = 'Print copyright and license summary'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-d'; Long = '--dump-variables'; Canonical = '--dump-variables'
            Description = 'Dump global variables to awkvars.out or the attached file path'
            ValueMode = 'Optional'; ValueKind = 'OutputFile'
            ShortAllowsSeparate = $false; ShortAllowsAttached = $true
            LongAllowsSeparate = $false; LongAllowsEquals = $true
        }
        @{
            Short = '-D'; Long = '--debug'; Canonical = '--debug'
            Description = 'Enable the debugger; optional attached file supplies debugger commands'
            ValueMode = 'Optional'; ValueKind = 'OutputFile'
            ShortAllowsSeparate = $false; ShortAllowsAttached = $true
            LongAllowsSeparate = $false; LongAllowsEquals = $true
        }
        @{
            Short = '-e'; Long = '--source'; Canonical = '--source'
            Description = 'Provide awk program source on the command line'
            ValueMode = 'Required'; ValueKind = 'ProgramText'
            ShortAllowsSeparate = $true; ShortAllowsAttached = $true
            LongAllowsSeparate = $true; LongAllowsEquals = $true
            ProvidesProgramSource = $true
        }
        @{
            Short = '-E'; Long = '--exec'; Canonical = '--exec'
            Description = 'Read awk program source from file and stop option parsing'
            ValueMode = 'Required'; ValueKind = 'SourceFile'
            ShortAllowsSeparate = $true; ShortAllowsAttached = $true
            LongAllowsSeparate = $true; LongAllowsEquals = $true
            ProvidesProgramSource = $true; TerminatesOptionParsing = $true; DisallowsAssignments = $true
        }
        @{
            Short = '-g'; Long = '--gen-pot'; Canonical = '--gen-pot'
            Description = 'Generate a gettext POT template from marked strings'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-h'; Long = '--help'; Canonical = '--help'
            Description = 'Show help and exit'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-i'; Long = '--include'; Canonical = '--include'
            Description = 'Read an awk source library file once'
            ValueMode = 'Required'; ValueKind = 'SourceFile'
            ShortAllowsSeparate = $true; ShortAllowsAttached = $true
            LongAllowsSeparate = $true; LongAllowsEquals = $true
        }
        @{
            Short = '-I'; Long = '--trace'; Canonical = '--trace'
            Description = 'Trace internal bytecode execution'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-k'; Long = '--csv'; Canonical = '--csv'
            Description = 'Enable CSV processing mode'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-l'; Long = '--load'; Canonical = '--load'
            Description = 'Load a dynamic extension by library name'
            ValueMode = 'Required'; ValueKind = 'LoadExtension'
            ShortAllowsSeparate = $true; ShortAllowsAttached = $true
            LongAllowsSeparate = $true; LongAllowsEquals = $true
        }
        @{
            Short = '-L'; Long = '--lint'; Canonical = '--lint'
            Description = 'Enable lint warnings, optionally with fatal, invalid, or no-ext'
            ValueMode = 'Optional'; ValueKind = 'Lint'
            ShortAllowsSeparate = $false; ShortAllowsAttached = $true
            LongAllowsSeparate = $false; LongAllowsEquals = $true
        }
        @{
            Short = '-M'; Long = '--bignum'; Canonical = '--bignum'
            Description = 'Enable arbitrary-precision arithmetic when available'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-N'; Long = '--use-lc-numeric'; Canonical = '--use-lc-numeric'
            Description = 'Use the locale decimal point when parsing numeric input'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-n'; Long = '--non-decimal-data'; Canonical = '--non-decimal-data'
            Description = 'Interpret octal and hexadecimal values in input data'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-o'; Long = '--pretty-print'; Canonical = '--pretty-print'
            Description = 'Pretty-print the program to awkprof.out or the attached file path'
            ValueMode = 'Optional'; ValueKind = 'OutputFile'
            ShortAllowsSeparate = $false; ShortAllowsAttached = $true
            LongAllowsSeparate = $false; LongAllowsEquals = $true
        }
        @{
            Short = '-O'; Long = '--optimize'; Canonical = '--optimize'
            Description = 'Enable optimizer behavior'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-p'; Long = '--profile'; Canonical = '--profile'
            Description = 'Write execution profile to awkprof.out or the attached file path'
            ValueMode = 'Optional'; ValueKind = 'OutputFile'
            ShortAllowsSeparate = $false; ShortAllowsAttached = $true
            LongAllowsSeparate = $false; LongAllowsEquals = $true
        }
        @{
            Short = '-P'; Long = '--posix'; Canonical = '--posix'
            Description = 'Operate in strict POSIX mode'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-r'; Long = '--re-interval'; Canonical = '--re-interval'
            Description = 'Allow interval expressions in regular expressions'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-s'; Long = '--no-optimize'; Canonical = '--no-optimize'
            Description = 'Disable optimizer behavior'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-S'; Long = '--sandbox'; Canonical = '--sandbox'
            Description = 'Disable system access, redirections, and dynamic extensions'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-t'; Long = '--lint-old'; Canonical = '--lint-old'
            Description = 'Warn about constructs missing from original Version 7 awk'
            ValueMode = 'None'; ValueKind = 'None'
        }
        @{
            Short = '-V'; Long = '--version'; Canonical = '--version'
            Description = 'Show version information and exit'
            ValueMode = 'None'; ValueKind = 'None'
        }
    )
}

function Get-GawkUniqueLongPrefixMaps {
    param([string[]]$LongOptions)

    $rawPrefixMap = @{}
    foreach ($longOption in @($LongOptions)) {
        if ([string]::IsNullOrWhiteSpace($longOption) -or -not $longOption.StartsWith('--')) {
            continue
        }

        $name = $longOption.Substring(2)
        for ($index = 1; $index -lt $name.Length; $index++) {
            $prefix = '--' + $name.Substring(0, $index)
            if (-not $rawPrefixMap.ContainsKey($prefix)) {
                $rawPrefixMap[$prefix] = New-Object System.Collections.Generic.List[string]
            }

            [void]$rawPrefixMap[$prefix].Add($longOption)
        }
    }

    $uniquePrefixes = @{}
    $minimalPrefixes = @{}
    foreach ($entry in $rawPrefixMap.GetEnumerator()) {
        $targets = @($entry.Value | Select-Object -Unique)
        if ($targets.Count -eq 1) {
            $uniquePrefixes[$entry.Key] = $targets[0]
        }
    }

    foreach ($longOption in @($LongOptions)) {
        $candidates = @(
            $uniquePrefixes.Keys |
                Where-Object { $uniquePrefixes[$_] -eq $longOption } |
                Sort-Object { $_.Length }
        )

        if ($candidates.Count -gt 0) {
            $minimalPrefixes[$longOption] = $candidates[0]
        }
    }

    @{
        UniquePrefixes = $uniquePrefixes
        MinimalPrefixes = $minimalPrefixes
    }
}

function Get-GawkDiscoveredLoadExtensions {
    param([string]$CommandName = 'gawk')

    $seededExtensions = @(
        'filefuncs',
        'fnmatch',
        'fork',
        'inplace',
        'intdiv',
        'ordchr',
        'readdir',
        'readfile',
        'revoutput',
        'revtwoway',
        'rwarray',
        'time'
    )

    $results = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    foreach ($name in $seededExtensions) {
        $key = $name.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$results.Add($name)
        }
    }

    $candidateDirectories = New-Object System.Collections.Generic.List[string]
    $libPath = [Environment]::GetEnvironmentVariable('AWKLIBPATH')
    if (-not [string]::IsNullOrWhiteSpace($libPath)) {
        foreach ($part in $libPath.Split([System.IO.Path]::PathSeparator)) {
            if (-not [string]::IsNullOrWhiteSpace($part) -and (Test-Path -LiteralPath $part)) {
                [void]$candidateDirectories.Add($part)
            }
        }
    }

    $executablePath = Get-GawkExecutablePath -CommandName $CommandName
    if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
        $exeDirectory = Split-Path -Parent $executablePath
        foreach ($candidate in @(
            $exeDirectory,
            (Join-Path -Path $exeDirectory -ChildPath 'lib'),
            (Join-Path -Path $exeDirectory -ChildPath 'gawk'),
            (Join-Path -Path $exeDirectory -ChildPath 'extensions')
        )) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
                [void]$candidateDirectories.Add($candidate)
            }
        }
    }

    foreach ($directory in @($candidateDirectories | Select-Object -Unique)) {
        Get-ChildItem -LiteralPath $directory -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.dll', '.so', '.dylib', '.bundle') } |
            ForEach-Object {
                $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                if ([string]::IsNullOrWhiteSpace($name)) {
                    return
                }

                $key = $name.ToLowerInvariant()
                if ($seen.ContainsKey($key)) {
                    return
                }

                $seen[$key] = $true
                [void]$results.Add($name)
            }
    }

    @($results.ToArray() | Sort-Object)
}

function Initialize-GawkCompletionCatalog {
    param([string]$CommandName = 'gawk')

    if ($script:GawkCompletionCatalog.Initialized) {
        return
    }

    $definitions = @(Get-GawkStaticOptionDefinitions)
    $helpText = Get-GawkHelpText -CommandName $CommandName
    $helpTokens = @(Get-GawkHelpOptionTokens -HelpText $helpText)
    $helpTokenSet = @{}
    foreach ($token in $helpTokens) {
        $helpTokenSet[$token.ToLowerInvariant()] = $true
    }

    $availableDefinitions = @()
    foreach ($definition in $definitions) {
        $shortKey = $definition.Short.ToLowerInvariant()
        $longKey = $definition.Long.ToLowerInvariant()
        $isAvailable = if ($helpTokenSet.Count -eq 0) {
            $true
        } elseif ($helpTokenSet.ContainsKey($shortKey) -or $helpTokenSet.ContainsKey($longKey)) {
            $true
        } else {
            $false
        }

        if ($isAvailable) {
            $availableDefinitions += $definition
        }
    }

    if ($availableDefinitions.Count -eq 0) {
        $availableDefinitions = $definitions
    }

    $canonicalMap = @{}
    $shortMap = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $longMap = @{}
    foreach ($definition in $availableDefinitions) {
        $canonicalMap[$definition.Canonical] = $definition
        $shortMap[$definition.Short] = $definition.Canonical
        $longMap[$definition.Long.ToLowerInvariant()] = $definition.Canonical
    }

    $prefixData = Get-GawkUniqueLongPrefixMaps -LongOptions ($availableDefinitions | ForEach-Object { $_.Long })

    $script:GawkCompletionCatalog.OptionDefinitions = $availableDefinitions
    $script:GawkCompletionCatalog.CanonicalOptionMap = $canonicalMap
    $script:GawkCompletionCatalog.ShortOptionMap = $shortMap
    $script:GawkCompletionCatalog.LongOptionMap = $longMap
    $script:GawkCompletionCatalog.UniqueLongPrefixMap = $prefixData.UniquePrefixes
    $script:GawkCompletionCatalog.MinimalLongAbbreviations = $prefixData.MinimalPrefixes
    $script:GawkCompletionCatalog.LongSuggestions = @(
        foreach ($definition in $availableDefinitions) {
            [pscustomobject]@{
                CompletionText = $definition.Long
                Canonical = $definition.Canonical
                ToolTip = $definition.Description
                IsAbbreviation = $false
            }

            if ($prefixData.MinimalPrefixes.ContainsKey($definition.Long)) {
                $abbreviation = $prefixData.MinimalPrefixes[$definition.Long]
                if (-not [string]::IsNullOrWhiteSpace($abbreviation) -and ($abbreviation -ne $definition.Long)) {
                    [pscustomobject]@{
                        CompletionText = $abbreviation
                        Canonical = $definition.Canonical
                        ToolTip = 'Unique abbreviation for {0}' -f $definition.Long
                        IsAbbreviation = $true
                    }
                }
            }
        }
    )
    $script:GawkCompletionCatalog.LoadExtensions = Get-GawkDiscoveredLoadExtensions -CommandName $CommandName
    $script:GawkCompletionCatalog.Initialized = $true
}

function Resolve-GawkLongOption {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $normalized = $Token.ToLowerInvariant()
    if ($script:GawkCompletionCatalog.LongOptionMap.ContainsKey($normalized)) {
        return $script:GawkCompletionCatalog.LongOptionMap[$normalized]
    }

    if ($script:GawkCompletionCatalog.UniqueLongPrefixMap.ContainsKey($normalized)) {
        $targetLong = $script:GawkCompletionCatalog.UniqueLongPrefixMap[$normalized]
        return $script:GawkCompletionCatalog.LongOptionMap[$targetLong.ToLowerInvariant()]
    }

    $null
}

function Get-GawkOptionDefinition {
    param([string]$CanonicalOption)

    if ([string]::IsNullOrWhiteSpace($CanonicalOption)) {
        return $null
    }

    if ($script:GawkCompletionCatalog.CanonicalOptionMap.ContainsKey($CanonicalOption)) {
        return $script:GawkCompletionCatalog.CanonicalOptionMap[$CanonicalOption]
    }

    $null
}

function New-GawkParseState {
    @{
        EndOfOptions = $false
        ProgramSourceProvided = $false
        PendingSeparateOption = $null
        AssignmentsAllowed = $true
    }
}

function Test-GawkAssignmentToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    $trimmed = $Token.Trim('"', "'")
    $trimmed -match '^[A-Za-z_][A-Za-z0-9_]*='
}

function Update-GawkStateFromValue {
    param(
        [hashtable]$State,
        [hashtable]$Definition,
        [string]$Value
    )

    if ($null -eq $Definition) {
        return
    }

    if ($Definition.ContainsKey('ProvidesProgramSource') -and $Definition.ProvidesProgramSource) {
        $State.ProgramSourceProvided = $true
    }

    if ($Definition.ContainsKey('TerminatesOptionParsing') -and $Definition.TerminatesOptionParsing) {
        $State.EndOfOptions = $true
    }

    if ($Definition.ContainsKey('DisallowsAssignments') -and $Definition.DisallowsAssignments) {
        $State.AssignmentsAllowed = $false
    }
}

function Update-GawkStateFromOption {
    param(
        [hashtable]$State,
        [hashtable]$Definition
    )

    if ($null -eq $Definition) {
        return
    }

    if ($Definition.ValueMode -eq 'None') {
        if ($Definition.ContainsKey('TerminatesOptionParsing') -and $Definition.TerminatesOptionParsing) {
            $State.EndOfOptions = $true
        }
        if ($Definition.ContainsKey('DisallowsAssignments') -and $Definition.DisallowsAssignments) {
            $State.AssignmentsAllowed = $false
        }
    }
}

function Parse-GawkShortToken {
    param(
        [string]$Token,
        [hashtable]$State
    )

    if ([string]::IsNullOrWhiteSpace($Token) -or ($Token.Length -lt 2)) {
        return
    }

    $offset = 1
    while ($offset -lt $Token.Length) {
        $shortToken = '-' + $Token[$offset]
        if (-not $script:GawkCompletionCatalog.ShortOptionMap.ContainsKey($shortToken)) {
            break
        }

        $canonical = $script:GawkCompletionCatalog.ShortOptionMap[$shortToken]
        $definition = Get-GawkOptionDefinition -CanonicalOption $canonical
        if ($null -eq $definition) {
            break
        }

        $remaining = if ($offset + 1 -lt $Token.Length) {
            $Token.Substring($offset + 1)
        } else {
            ''
        }

        switch ($definition.ValueMode) {
            'None' {
                Update-GawkStateFromOption -State $State -Definition $definition
                $offset += 1
                continue
            }
            'Required' {
                if (-not [string]::IsNullOrEmpty($remaining)) {
                    Update-GawkStateFromValue -State $State -Definition $definition -Value $remaining
                } elseif ($definition.ShortAllowsSeparate) {
                    $State.PendingSeparateOption = $canonical
                }
                return
            }
            'Optional' {
                if (-not [string]::IsNullOrEmpty($remaining)) {
                    Update-GawkStateFromValue -State $State -Definition $definition -Value $remaining
                } else {
                    Update-GawkStateFromOption -State $State -Definition $definition
                }
                return
            }
            default {
                return
            }
        }
    }
}

function Update-GawkParseState {
    param(
        [string[]]$CompletedTokens
    )

    $state = New-GawkParseState

    foreach ($token in @($CompletedTokens)) {
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        if ($state.PendingSeparateOption) {
            $definition = Get-GawkOptionDefinition -CanonicalOption $state.PendingSeparateOption
            Update-GawkStateFromValue -State $state -Definition $definition -Value $token
            $state.PendingSeparateOption = $null
            continue
        }

        if (-not $state.EndOfOptions -and $token -eq '--') {
            $state.EndOfOptions = $true
            continue
        }

        if (-not $state.EndOfOptions) {
            if ($token.StartsWith('--')) {
                $equalsIndex = $token.IndexOf('=')
                $optionToken = if ($equalsIndex -ge 0) { $token.Substring(0, $equalsIndex) } else { $token }
                $canonical = Resolve-GawkLongOption -Token $optionToken
                if ($canonical) {
                    $definition = Get-GawkOptionDefinition -CanonicalOption $canonical
                    if ($definition.ValueMode -eq 'Required') {
                        if ($equalsIndex -ge 0) {
                            $valueText = $token.Substring($equalsIndex + 1)
                            Update-GawkStateFromValue -State $state -Definition $definition -Value $valueText
                        } elseif ($definition.LongAllowsSeparate) {
                            $state.PendingSeparateOption = $canonical
                        }
                    } elseif ($definition.ValueMode -eq 'Optional') {
                        if ($equalsIndex -ge 0) {
                            $valueText = $token.Substring($equalsIndex + 1)
                            Update-GawkStateFromValue -State $state -Definition $definition -Value $valueText
                        } else {
                            Update-GawkStateFromOption -State $state -Definition $definition
                        }
                    } else {
                        Update-GawkStateFromOption -State $state -Definition $definition
                    }

                    continue
                }
            } elseif ($token.StartsWith('-') -and ($token -ne '-')) {
                Parse-GawkShortToken -Token $token -State $state
                continue
            }
        }

        if (-not $state.ProgramSourceProvided) {
            $state.ProgramSourceProvided = $true
            $state.EndOfOptions = $true
            continue
        }

        if ($state.AssignmentsAllowed -and (Test-GawkAssignmentToken -Token $token)) {
            $state.EndOfOptions = $true
            continue
        }

        $state.EndOfOptions = $true
    }

    $state
}

function Get-GawkCurrentWord {
    param(
        [string]$WordToComplete
    )

    if ($null -eq $WordToComplete) {
        return ''
    }

    $WordToComplete
}

function Get-GawkPathCompletions {
    param(
        [string]$InputText,
        [string]$AttachedPrefix = '',
        [string[]]$PreferredExtensions = @()
    )

    $text = if ($null -eq $InputText) { '' } else { $InputText }
    $trimmedInput = $text.Trim('"')

    if ([string]::IsNullOrWhiteSpace($trimmedInput)) {
        $parent = '.'
        $leaf = ''
    } else {
        $parent = Split-Path -Path $trimmedInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $trimmedInput -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $quoteResult = $text.StartsWith('"')

    $items = @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)
    $preferredMap = @{}
    foreach ($extension in @($PreferredExtensions)) {
        if ([string]::IsNullOrWhiteSpace($extension)) {
            continue
        }

        $preferredMap[$extension.ToLowerInvariant()] = $true
    }

    $sortedItems = @(
        $items | Sort-Object `
            @{ Expression = { -not $_.PSIsContainer } }, `
            @{ Expression = {
                    if ($_.PSIsContainer) {
                        0
                    } elseif ($preferredMap.ContainsKey($_.Extension.ToLowerInvariant())) {
                        0
                    } else {
                        1
                    }
                }
            }, `
            @{ Expression = { $_.Name } }
    )

    foreach ($item in $sortedItems) {
        $completionText = if ($trimmedInput -and -not [System.IO.Path]::IsPathRooted($trimmedInput)) {
            if ($parent -eq '.') {
                $item.Name
            } else {
                Join-Path -Path $parent -ChildPath $item.Name
            }
        } else {
            $item.FullName
        }

        if ($item.PSIsContainer -and -not $completionText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionText += [System.IO.Path]::DirectorySeparatorChar
        }

        if (($quoteResult -or $completionText -match '\s') -and -not ($completionText.StartsWith('"') -and $completionText.EndsWith('"'))) {
            $completionText = '"' + $completionText + '"'
        }

        $tooltip = if ($item.PSIsContainer) {
            'Directory: {0}' -f $item.FullName
        } else {
            $item.FullName
        }

        New-GawkCompletionResult -CompletionText ($AttachedPrefix + $completionText) -ResultType 'ParameterValue' -ToolTip $tooltip
    }
}

function Get-GawkAssignmentCompletions {
    param(
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    $word = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }
    if ($word -match '=') {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    if ($word -match '^[A-Za-z_][A-Za-z0-9_]*$') {
        $toolTip = 'Assign awk variable {0}' -f $word
        [void]$results.Add(
            (New-GawkCompletionResult -CompletionText ($AttachedPrefix + $word + '=') -ResultType 'ParameterValue' -ToolTip $toolTip)
        )
    }

    foreach ($suggestion in $script:GawkCompletionCatalog.AssignmentSuggestions) {
        $completionText = $AttachedPrefix + $suggestion.Text
        if ([string]::IsNullOrWhiteSpace($word) -or $completionText.StartsWith($AttachedPrefix + $word, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add(
                (New-GawkCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $suggestion.Tooltip)
            )
        }
    }

    @($results.ToArray() | Sort-Object CompletionText -Unique)
}

function Get-GawkSimpleValueCompletions {
    param(
        [object[]]$Values,
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    $word = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }

    foreach ($value in @($Values)) {
        $text = if ($value -is [string]) { $value } else { $value.Text }
        $toolTip = if ($value -is [string]) { $value } else { $value.Tooltip }

        if (($AttachedPrefix + $text).StartsWith($AttachedPrefix + $word, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-GawkCompletionResult -CompletionText ($AttachedPrefix + $text) -ResultType 'ParameterValue' -ToolTip $toolTip
        }
    }
}

function Get-GawkValueCompletions {
    param(
        [hashtable]$Definition,
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    if ($null -eq $Definition) {
        return @()
    }

    switch ($Definition.ValueKind) {
        'SourceFile' {
            return @(Get-GawkPathCompletions -InputText $CurrentWord -AttachedPrefix $AttachedPrefix -PreferredExtensions @('.awk', '.gawk', '.inc'))
        }
        'OutputFile' {
            return @(Get-GawkPathCompletions -InputText $CurrentWord -AttachedPrefix $AttachedPrefix)
        }
        'LoadExtension' {
            return @(Get-GawkSimpleValueCompletions -Values $script:GawkCompletionCatalog.LoadExtensions -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix)
        }
        'Lint' {
            return @(Get-GawkSimpleValueCompletions -Values $script:GawkCompletionCatalog.LintValues -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix)
        }
        'FieldSeparator' {
            return @(Get-GawkSimpleValueCompletions -Values $script:GawkCompletionCatalog.FieldSeparators -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix)
        }
        'Assignment' {
            return @(Get-GawkAssignmentCompletions -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix)
        }
        default {
            return @()
        }
    }
}

function Get-GawkOptionCompletions {
    param([string]$CurrentWord)

    $word = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    $seen = @{}

    if ([string]::IsNullOrWhiteSpace($word) -or '--'.StartsWith($word, [System.StringComparison]::OrdinalIgnoreCase)) {
        $key = '--'
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$results.Add(
                (New-GawkCompletionResult -CompletionText '--' -ResultType 'ParameterName' -ToolTip 'End option parsing')
            )
        }
    }

    foreach ($definition in $script:GawkCompletionCatalog.OptionDefinitions) {
        foreach ($candidate in @(
            [pscustomobject]@{ Text = $definition.Short; ToolTip = $definition.Description },
            [pscustomobject]@{ Text = $definition.Long; ToolTip = $definition.Description }
        )) {
            if ($candidate.Text.StartsWith($word, [System.StringComparison]::OrdinalIgnoreCase)) {
                $key = $candidate.Text.ToLowerInvariant()
                if ($seen.ContainsKey($key)) {
                    continue
                }

                $seen[$key] = $true
                [void]$results.Add(
                    (New-GawkCompletionResult -CompletionText $candidate.Text -ResultType 'ParameterName' -ToolTip $candidate.ToolTip)
                )
            }
        }
    }

    foreach ($candidate in $script:GawkCompletionCatalog.LongSuggestions) {
        if (-not $candidate.IsAbbreviation) {
            continue
        }

        if ($candidate.CompletionText.StartsWith($word, [System.StringComparison]::OrdinalIgnoreCase)) {
            $key = $candidate.CompletionText.ToLowerInvariant()
            if ($seen.ContainsKey($key)) {
                continue
            }

            $seen[$key] = $true
            [void]$results.Add(
                (New-GawkCompletionResult -CompletionText $candidate.CompletionText -ResultType 'ParameterName' -ToolTip $candidate.ToolTip)
            )
        }
    }

    @($results.ToArray())
}

function Get-GawkPositionalCompletions {
    param(
        [hashtable]$State,
        [string]$CurrentWord
    )

    if (-not $State.ProgramSourceProvided) {
        return @()
    }

    if ($State.AssignmentsAllowed -and -not [string]::IsNullOrWhiteSpace($CurrentWord) -and ($CurrentWord -match '^[A-Za-z_][A-Za-z0-9_]*$')) {
        return @(Get-GawkAssignmentCompletions -CurrentWord $CurrentWord)
    }

    if ($State.AssignmentsAllowed -and [string]::IsNullOrWhiteSpace($CurrentWord)) {
        return @(
            (Get-GawkAssignmentCompletions -CurrentWord $CurrentWord) +
            (Get-GawkPathCompletions -InputText $CurrentWord)
        )
    }

    if ($State.AssignmentsAllowed -and ($CurrentWord -match '=')) {
        return @()
    }

    @(Get-GawkPathCompletions -InputText $CurrentWord)
}

function Complete-GawkNative {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    [object[]]$commandElements = @($CommandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    if ($commandElements.Count -eq 0) {
        return
    }

    Initialize-GawkCompletionCatalog -CommandName $commandElements[0]

    $currentWord = Get-GawkCurrentWord -WordToComplete $WordToComplete
    [object[]]$argumentTokens = if ($commandElements.Count -gt 1) {
        @($commandElements[1..($commandElements.Count - 1)])
    } else {
        @()
    }

    [object[]]$completedTokens = if ([string]::IsNullOrEmpty($currentWord)) {
        @($argumentTokens)
    } elseif ($argumentTokens.Count -gt 1) {
        @($argumentTokens[0..($argumentTokens.Count - 2)])
    } else {
        @()
    }

    $state = Update-GawkParseState -CompletedTokens $completedTokens

    if ($state.PendingSeparateOption) {
        $definition = Get-GawkOptionDefinition -CanonicalOption $state.PendingSeparateOption
        return @(Get-GawkValueCompletions -Definition $definition -CurrentWord $currentWord)
    }

    if (-not $state.EndOfOptions -and $currentWord.StartsWith('--')) {
        $equalsIndex = $currentWord.IndexOf('=')
        if ($equalsIndex -ge 0) {
            $left = $currentWord.Substring(0, $equalsIndex)
            $right = $currentWord.Substring($equalsIndex + 1)
            $canonical = Resolve-GawkLongOption -Token $left
            if ($canonical) {
                $definition = Get-GawkOptionDefinition -CanonicalOption $canonical
                if (($definition.ValueMode -eq 'Required' -and $definition.LongAllowsEquals) -or
                    ($definition.ValueMode -eq 'Optional' -and $definition.LongAllowsEquals)) {
                    return @(Get-GawkValueCompletions -Definition $definition -CurrentWord $right -AttachedPrefix ($left + '='))
                }
            }
        }

        return @(Get-GawkOptionCompletions -CurrentWord $currentWord)
    }

    if (-not $state.EndOfOptions -and $currentWord.StartsWith('-') -and ($currentWord -ne '-')) {
        if ($currentWord.Length -ge 2) {
            $shortToken = $currentWord.Substring(0, 2)
            if ($script:GawkCompletionCatalog.ShortOptionMap.ContainsKey($shortToken)) {
                $canonical = $script:GawkCompletionCatalog.ShortOptionMap[$shortToken]
                $definition = Get-GawkOptionDefinition -CanonicalOption $canonical
                if ($definition.ValueMode -eq 'Required' -or $definition.ValueMode -eq 'Optional') {
                    $attachedValue = if ($currentWord.Length -gt 2) { $currentWord.Substring(2) } else { '' }
                    return @(Get-GawkValueCompletions -Definition $definition -CurrentWord $attachedValue -AttachedPrefix $currentWord.Substring(0, 2))
                }
            }
        }

        return @(Get-GawkOptionCompletions -CurrentWord $currentWord)
    }

    if (-not $state.EndOfOptions -and ($currentWord -eq '-')) {
        return @(Get-GawkOptionCompletions -CurrentWord $currentWord)
    }

    @(Get-GawkPositionalCompletions -State $state -CurrentWord $currentWord)
}

foreach ($commandName in @('gawk', 'gawk.exe', 'awk', 'awk.exe')) {
    Register-ArgumentCompleter -Native -CommandName $commandName -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)

        Complete-GawkNative -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
    }
}
