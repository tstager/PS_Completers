Set-StrictMode -Version Latest

if (-not (Get-Variable -Name GawkCompletionCatalog -Scope Script -ErrorAction Ignore)) {
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
        LoadExtensionsKey       = $null
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
            @{ Text = 'FIELDWIDTHS='; Tooltip = 'Fixed-width field specification' }
            @{ Text = 'FPAT='; Tooltip = 'Regular expression describing field contents' }
            @{ Text = 'SUBSEP='; Tooltip = 'Subscript separator for multi-dimensional arrays' }
            @{ Text = 'LINT='; Tooltip = 'Lint mode: fatal, invalid, no-ext, or 1/0' }
            @{ Text = 'PREC='; Tooltip = 'Arbitrary-precision working precision in bits' }
            @{ Text = 'ROUNDMODE='; Tooltip = 'Arbitrary-precision rounding mode' }
            @{ Text = 'TEXTDOMAIN='; Tooltip = 'Text domain for gettext translations' }
            @{ Text = 'AWKPATH='; Tooltip = 'Search path for -f/-i source files' }
            @{ Text = 'AWKLIBPATH='; Tooltip = 'Search path for -l extension libraries' }
        )
        AssignmentValues        = @{
            'FS'         = 'FieldSeparators'
            'OFS'        = 'FieldSeparators'
            'RS'         = 'FieldSeparators'
            'ORS'        = 'FieldSeparators'
            'IGNORECASE' = @('0', '1')
            'BINMODE'    = @('0', '1', '2', '3', 'r', 'w', 'rw')
            'LINT'       = 'LintValues'
            'ROUNDMODE'  = @('N', 'U', 'D', 'Z', 'A')
            'AWKPATH'    = 'Path'
            'AWKLIBPATH' = 'Path'
        }
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
        $command = Get-Command -Name $candidate -ErrorAction Ignore
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
        (($null | & $executablePath --help 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' }) -join "`n")
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

function Resolve-GawkRealExecutablePath {
    param([string]$ExecutablePath)

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
        return $ExecutablePath
    }

    # A scoop shim is a launcher next to a '<name>.shim' file whose 'path = "..."'
    # line names the real binary; a symlink carries its target directly.
    $shimFile = [System.IO.Path]::ChangeExtension($ExecutablePath, '.shim')
    if (Test-Path -LiteralPath $shimFile -PathType Leaf) {
        foreach ($line in @(Get-Content -LiteralPath $shimFile -ErrorAction SilentlyContinue)) {
            if ($line -match '^\s*path\s*=\s*"?([^"]+)"?\s*$') {
                $target = $Matches[1].Trim()
                if (Test-Path -LiteralPath $target -PathType Leaf) {
                    return $target
                }
            }
        }
    }

    $item = Get-Item -LiteralPath $ExecutablePath -ErrorAction SilentlyContinue
    if ($item -and $item.PSObject.Properties['Target'] -and -not [string]::IsNullOrWhiteSpace($item.Target)) {
        $target = [string]@($item.Target)[0]
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            return $target
        }
    }

    $ExecutablePath
}

function Get-GawkLibrarySearchPath {
    param([string]$ExecutablePath)

    # gawk finds a bare --load name only on its effective AWKLIBPATH: the
    # environment variable when set, otherwise a compiled-in default that can
    # name the builder's machine (scoop's mingw build: d:/usr/lib/gawk/ext-4.1).
    $entries = New-Object System.Collections.Generic.List[string]
    $environmentValue = [Environment]::GetEnvironmentVariable('AWKLIBPATH')
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
        [void]$entries.Add($environmentValue)
    }

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $ExecutablePath
        [void]$startInfo.ArgumentList.Add('BEGIN { print ENVIRON["AWKLIBPATH"] }')
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $process.StandardInput.Close()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            [void]$process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) {
                try { $process.Kill($true) } catch { Write-Debug -Message $_.Exception.Message }
            }

            if ($outputTask.Wait(1000)) {
                $value = @(($outputTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', '') -split '\r?\n' | Select-Object -First 1)
                if ($value.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($value[0])) {
                    [void]$entries.Add($value[0].Trim())
                }
            }
        } finally {
            $process.Dispose()
        }
    } catch {
        Write-Debug -Message ('gawk AWKLIBPATH probe failed: {0}' -f $_.Exception.Message)
    }

    # Git for Windows' msys gawk prints POSIX paths (/usr/lib/gawk) rooted at
    # the directory that holds usr\bin\gawk.exe.
    $msysRoot = $null
    if ((Split-Path -Parent $ExecutablePath) -match '^(.+)[\\/]usr[\\/]bin$') {
        $msysRoot = $Matches[1]
    }

    $directories = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $entries) {
        # mingw builds separate entries with ';', msys builds with ':'; a ':'
        # right after a leading drive letter belongs to the path.
        foreach ($part in @($entry.Split(';') | ForEach-Object { $_ -split '(?<!^[A-Za-z]):' })) {
            if ([string]::IsNullOrWhiteSpace($part)) {
                continue
            }

            $candidate = $part.Trim()
            if ($candidate -match '^/(?!/)') {
                if (-not $msysRoot) {
                    continue
                }

                $candidate = $msysRoot + $candidate
            }

            $item = Get-Item -LiteralPath $candidate.Replace('/', '\') -Force -ErrorAction Ignore
            if ($item -and $item.PSIsContainer) {
                [void]$directories.Add($item.FullName.TrimEnd('\'))
            }
        }
    }

    @($directories.ToArray())
}

function Get-GawkDiscoveredLoadExtensions {
    param([string]$CommandName = 'gawk')

    $executablePath = Resolve-GawkRealExecutablePath -ExecutablePath (Get-GawkExecutablePath -CommandName $CommandName)
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        # Static fallback for when gawk is absent: the extensions gawk ships.
        return @(
            foreach ($name in @('filefuncs', 'fnmatch', 'fork', 'inplace', 'intdiv', 'ordchr', 'readdir', 'readfile', 'revoutput', 'revtwoway', 'rwarray', 'time')) {
                [pscustomobject]@{ Name = $name; Text = $name; ToolTip = 'Load the {0} extension' -f $name }
            }
        )
    }

    $searchDirectories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $candidateDirectories = New-Object System.Collections.Generic.List[string]
    foreach ($directory in @(Get-GawkLibrarySearchPath -ExecutablePath $executablePath)) {
        if ($searchDirectories.Add($directory)) {
            [void]$candidateDirectories.Add($directory)
        }
    }

    # gawk installs its extensions under <prefix>\lib\gawk (Git for Windows) or
    # <prefix>\lib\gawk\ext-<API> (scoop, MSYS2), where <prefix> is the parent of
    # the bin directory holding the real gawk.exe. The bin directory itself is
    # never scanned: it holds the msys/mingw runtime DLLs, not extensions.
    $exeDirectory = Split-Path -Parent $executablePath
    $prefixDirectory = Split-Path -Parent $exeDirectory
    $libRoots = @(
        (Join-Path -Path $exeDirectory -ChildPath 'lib\gawk')
        if (-not [string]::IsNullOrWhiteSpace($prefixDirectory)) { Join-Path -Path $prefixDirectory -ChildPath 'lib\gawk' }
    )
    foreach ($libRoot in $libRoots) {
        if (-not (Test-Path -LiteralPath $libRoot -PathType Container)) {
            continue
        }

        [void]$candidateDirectories.Add($libRoot.TrimEnd('\'))
        foreach ($apiDirectory in @(Get-ChildItem -LiteralPath $libRoot -Directory -Filter 'ext-*' -ErrorAction Ignore)) {
            [void]$candidateDirectories.Add($apiDirectory.FullName.TrimEnd('\'))
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $scannedDirectories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($directory in $candidateDirectories) {
        if (-not $scannedDirectories.Add($directory)) {
            continue
        }

        $onSearchPath = $searchDirectories.Contains($directory)
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -File -ErrorAction Ignore)) {
            if ($file.Extension -notin @('.dll', '.so', '.dylib', '.bundle')) {
                continue
            }

            $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            # Runtime libraries (libgmp-10, msys-2.0, cygwin1) sit beside real
            # extensions in some layouts and are never loadable with --load.
            if ($name -match '^(lib|msys|cyg)') {
                continue
            }

            $key = $name.ToLowerInvariant()
            if ($seen.ContainsKey($key)) {
                continue
            }

            $seen[$key] = $true
            if ($onSearchPath) {
                [void]$results.Add([pscustomobject]@{ Name = $name; Text = $name; ToolTip = ('Load the {0} extension from {1}' -f $name, $directory) })
            } else {
                # Off gawk's AWKLIBPATH a bare name fails ("cannot open shared
                # library"); the path without its suffix loads.
                [void]$results.Add([pscustomobject]@{
                        Name = $name
                        Text = Join-Path -Path $directory -ChildPath $name
                        ToolTip = ('Load the {0} extension by path; {1} is not on gawk''s AWKLIBPATH' -f $name, $directory)
                    })
            }
        }
    }

    @($results.ToArray() | Sort-Object -Property Name)
}

function Get-GawkLoadExtensionCatalog {
    # The answer depends on the resolved gawk and on $env:AWKLIBPATH.
    $cacheKey = [string](Get-GawkExecutablePath) + '|' + [Environment]::GetEnvironmentVariable('AWKLIBPATH')
    if ($script:GawkCompletionCatalog['LoadExtensionsKey'] -ne $cacheKey) {
        $script:GawkCompletionCatalog['LoadExtensions'] = @(Get-GawkDiscoveredLoadExtensions)
        $script:GawkCompletionCatalog['LoadExtensionsKey'] = $cacheKey
    }

    @($script:GawkCompletionCatalog['LoadExtensions'])
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

                # An unrecognised long option (typo, newer gawk) is still an
                # option, not the program text; leave the state untouched.
                continue
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
    $trimmedInput = ConvertFrom-GawkTypedWord -Text $text
    $quoteCharacter = if ($text -match '^[''"\u2018-\u201E]') { $text.Substring(0, 1) } else { '' }

    # $prefixText is the part of the typed word that precedes the leaf, kept
    # as typed so completions extend the user's own text ('.\', 'sub\',
    # '..\', 'C:\') instead of pasting absolute paths.
    if ([string]::IsNullOrWhiteSpace($trimmedInput)) {
        $parent = '.'
        $leaf = ''
        $prefixText = ''
    } elseif ($trimmedInput -match '[\\/]$') {
        $parent = $trimmedInput
        $leaf = ''
        $prefixText = $trimmedInput
    } else {
        $parent = Split-Path -Path $trimmedInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $trimmedInput -Leaf
        $prefixText = $trimmedInput.Substring(0, $trimmedInput.Length - $leaf.Length)
    }

    $filter = [System.Management.Automation.WildcardPattern]::Escape($leaf) + '*'
    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore | Where-Object { $_.Name -like $filter })
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
        $pathText = $prefixText + $item.Name

        # A whole-word name starting with a dash would parse as a parameter: lead with '.\'
        # as PowerShell's own file completion does.
        if (-not $AttachedPrefix -and -not $prefixText -and $item.Name -match '^[-\u2013-\u2015]') {
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $completionText = ConvertTo-GawkArgumentText -Text $pathText -QuoteCharacter $quoteCharacter

        $tooltip = if ($item.PSIsContainer) {
            'Directory: {0}' -f $item.FullName
        } else {
            $item.FullName
        }

        New-GawkCompletionResult -CompletionText ($AttachedPrefix + $completionText) -ListItemText ($AttachedPrefix + $pathText) -ResultType 'ParameterValue' -ToolTip $tooltip
    }
}

function Get-GawkAssignmentCompletions {
    param(
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    $word = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }
    $equalsIndex = $word.IndexOf('=')
    if ($equalsIndex -ge 0) {
        # 'NAME=' is complete; offer the values the catalog knows for that variable.
        $variableName = $word.Substring(0, $equalsIndex).Trim('"', "'").ToUpperInvariant()
        $valueText = $word.Substring($equalsIndex + 1)
        $valuePrefix = $AttachedPrefix + $word.Substring(0, $equalsIndex + 1)
        $catalogValues = $script:GawkCompletionCatalog.AssignmentValues
        if (-not $catalogValues.ContainsKey($variableName)) {
            return @()
        }

        $valueSource = $catalogValues[$variableName]
        if ($valueSource -is [string]) {
            if ($valueSource -eq 'Path') {
                return @(Get-GawkPathCompletions -InputText $valueText -AttachedPrefix $valuePrefix)
            }

            $valueSource = $script:GawkCompletionCatalog[$valueSource]
        }

        return @(Get-GawkSimpleValueCompletions -Values $valueSource -CurrentWord $valueText -AttachedPrefix $valuePrefix)
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

function ConvertFrom-GawkTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Text)

    if ($Text -notmatch '^[''"\u2018-\u201E]') {
        return $Text
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$parseErrors)
    $tokens[0].Value
}

function ConvertTo-GawkArgumentText {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default). PowerShell reads ' and
    # U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes.
    param(
        [string]$Text,
        [string]$QuoteCharacter = ''
    )

    if (-not $QuoteCharacter) {
        if ($Text -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Text
        }

        $QuoteCharacter = "'"
    }

    if ($QuoteCharacter -match '^[''\u2018-\u201B]$') {
        return $QuoteCharacter + ($Text -replace '([''\u2018-\u201B])', '$1$1') + $QuoteCharacter
    }

    $QuoteCharacter + ($Text -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteCharacter
}

function Get-GawkLoadExtensionCompletion {
    param(
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    $word = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }
    $quoteCharacter = if ($word -match '^[''"\u2018-\u201E]') { $word.Substring(0, 1) } else { '' }
    $word = ConvertFrom-GawkTypedWord -Text $word

    foreach ($extension in @(Get-GawkLoadExtensionCatalog)) {
        # A path-form value also matches on its extension name, so 'fil' finds '<dir>\filefuncs'.
        if (-not ($extension.Text.StartsWith($word, [System.StringComparison]::OrdinalIgnoreCase) -or
                $extension.Name.StartsWith($word, [System.StringComparison]::OrdinalIgnoreCase))) {
            continue
        }

        $valueText = $AttachedPrefix + $extension.Text
        New-GawkCompletionResult -CompletionText (ConvertTo-GawkArgumentText -Text $valueText -QuoteCharacter $quoteCharacter) -ListItemText $valueText -ResultType 'ParameterValue' -ToolTip $extension.ToolTip
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
            return @(Get-GawkLoadExtensionCompletion -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix)
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
    # Short options are case-distinct (-f/-F, -d/-D ...), so dedupe ordinally.
    $seen = [System.Collections.Generic.Dictionary[string, bool]]::new([System.StringComparer]::Ordinal)
    # A typed single-dash word must keep its case, or '-V' would also match '-v'.
    $comparison = if ($word.StartsWith('--')) {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }

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
            if ($candidate.Text.StartsWith($word, $comparison)) {
                $key = $candidate.Text
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

        if ($candidate.CompletionText.StartsWith($word, $comparison)) {
            $key = $candidate.CompletionText
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

    if ($State.AssignmentsAllowed -and (Test-GawkAssignmentToken -Token $CurrentWord)) {
        return @(Get-GawkAssignmentCompletions -CurrentWord $CurrentWord)
    }

    @(Get-GawkPathCompletions -InputText $CurrentWord)
}

function Complete-GawkNative {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # Tokenise the raw command text up to the cursor instead of using
    # CommandElements: the parser drops a bare comma ('-F,'), and text after
    # the cursor must not influence the parse state.
    $commandText = $CommandAst.Extent.Text
    $relativeCursor = [Math]::Max(0, [Math]::Min($CursorPosition - $CommandAst.Extent.StartOffset, $commandText.Length))
    $prefixText = $commandText.Substring(0, $relativeCursor)
    [object[]]$rawTokens = @([regex]::Matches($prefixText, '(?:["\u201C-\u201E][^"\u201C-\u201E]*["\u201C-\u201E]?|[''\u2018-\u201B][^''\u2018-\u201B]*[''\u2018-\u201B]?|[^\s"''\u2018-\u201E]+)+') | ForEach-Object { $_.Value })
    if ($rawTokens.Count -eq 0) {
        return
    }

    Initialize-GawkCompletionCatalog -CommandName $rawTokens[0]

    $cursorAfterWhitespace = ($CursorPosition -gt $CommandAst.Extent.EndOffset) -or ($prefixText -match '\s$')
    $currentWord = if ($cursorAfterWhitespace) { '' } else { [string]$rawTokens[-1] }
    if (-not $cursorAfterWhitespace -and $rawTokens.Count -eq 1) {
        $currentWord = Get-GawkCurrentWord -WordToComplete $WordToComplete
    }

    $completedCount = if ($cursorAfterWhitespace) { $rawTokens.Count - 1 } else { $rawTokens.Count - 2 }
    [object[]]$completedTokens = if ($completedCount -gt 0) {
        @($rawTokens | Select-Object -Skip 1 -First $completedCount)
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

Register-ArgumentCompleter -Native -CommandName @('gawk', 'gawk.exe', 'awk', 'awk.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-GawkNative -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
