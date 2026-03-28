Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name GroffCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:GroffCompletionCatalog = @{
        Initialized        = $false
        ExecutablePath     = $null
        HelpText           = $null
        HelpOptionTokens   = @()
        OptionDefinitions  = @()
        ShortOptionMap     = @{}
        LongOptionMap      = @{}
        OptionSuggestions  = @()
        LongSuggestions    = @()
        OutputDevices      = @()
        MacroPackages      = @()
        WarningCategories  = @(
            'all', 'w', 'char', 'number', 'break', 'delim', 'el', 'scale', 'range', 'syntax',
            'di', 'mac', 'reg', 'tab', 'right-brace', 'missing', 'input', 'escape', 'space',
            'font', 'ig', 'color', 'file'
        )
        EncodingHints      = @(
            'utf8', 'utf-8', 'latin1', 'latin2', 'latin5', 'latin9', 'koi8-r', 'cp1047', 'ascii'
        )
        PlaceholderHints   = @{
            '-d' = @('name=text', 'foo=bar', 's=string')
            '-f' = @('TR', 'HB', 'I')
            '-n' = @('1', '5', '10')
            '-o' = @('1', '1-3', '1,3-5,8-')
            '-r' = @('S=12', 'Pn=1', 'LL=72u')
            '-L' = @('<spooler-arg>')
            '-P' = @('<postprocessor-arg>')
        }
        AttachedPlaceholderHints = @{
            '-d' = @('name=text', 'foo=bar', 's=string')
            '-f' = @('TR', 'HB', 'I')
            '-n' = @('1', '5', '10')
            '-o' = @('1', '1-3', '1,3-5,8-')
            '-r' = @('S12', 'Pn1', 'LL72u')
            '-L' = @('<spooler-arg>')
            '-P' = @('<postprocessor-arg>')
        }
    }
}

function New-GroffCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ListItemText = $CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip = $CompletionText
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

function New-GroffStringSet {
    return ,([System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase))
}

function New-GroffStringObjectMap {
    return ,([System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal))
}

function Get-GroffUniqueStrings {
    param([string[]]$Items)

    $seen = New-GroffStringSet
    $results = New-Object System.Collections.Generic.List[string]

    foreach ($item in @($Items)) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        if ($seen.Add($item)) {
            [void]$results.Add($item)
        }
    }

    @($results.ToArray())
}

function Get-GroffCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback = ''
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') {
        return ''
    }

    $tokenStart = 0
    $inSingleQuote = $false
    $inDoubleQuote = $false

    for ($index = 0; $index -lt $prefix.Length; $index++) {
        $character = $prefix[$index]
        if (($character -eq '`') -and $inDoubleQuote -and (($index + 1) -lt $prefix.Length)) {
            $index++
            continue
        }

        if (($character -eq "'") -and -not $inDoubleQuote) {
            if ($inSingleQuote -and (($index + 1) -lt $prefix.Length) -and ($prefix[$index + 1] -eq "'")) {
                $index++
                continue
            }

            $inSingleQuote = -not $inSingleQuote
            continue
        }

        if (($character -eq '"') -and -not $inSingleQuote) {
            $inDoubleQuote = -not $inDoubleQuote
            continue
        }

        if ([char]::IsWhiteSpace($character) -and -not $inSingleQuote -and -not $inDoubleQuote) {
            $tokenStart = $index + 1
        }
    }

    if ($tokenStart -lt $prefix.Length) {
        return $prefix.Substring($tokenStart)
    }

    $Fallback
}

function Get-GroffQuoteCharacter {
    param([string]$InputText)

    if ([string]::IsNullOrEmpty($InputText)) {
        return $null
    }

    if ($InputText.StartsWith("'", [System.StringComparison]::Ordinal)) {
        return "'"
    }

    if ($InputText.StartsWith('"', [System.StringComparison]::Ordinal)) {
        return '"'
    }

    $null
}

function Remove-GroffOuterQuotes {
    param([string]$InputText)

    if ([string]::IsNullOrEmpty($InputText)) {
        return ''
    }

    $quoteCharacter = Get-GroffQuoteCharacter -InputText $InputText
    if ($null -eq $quoteCharacter) {
        return $InputText
    }

    $unquoted = $InputText.Substring(1)
    if ($unquoted.EndsWith($quoteCharacter, [System.StringComparison]::Ordinal)) {
        $unquoted = $unquoted.Substring(0, $unquoted.Length - 1)
    }

    if ($quoteCharacter -eq "'") {
        return $unquoted.Replace("''", "'")
    }

    $unquoted.Replace('`"', '"')
}

function ConvertTo-GroffQuotedValue {
    param(
        [string]$Value,
        [string]$QuoteCharacter
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    $effectiveQuote = $QuoteCharacter
    if ([string]::IsNullOrEmpty($effectiveQuote)) {
        $effectiveQuote = '"'
    }

    if (($effectiveQuote -eq "'") -and $Value.Contains("'")) {
        $effectiveQuote = '"'
    }

    if ($effectiveQuote -eq '"') {
        return '"' + $Value.Replace('`', '``').Replace('$', '`$').Replace('"', '`"') + '"'
    }

    "'" + $Value.Replace("'", "''") + "'"
}

function Get-GroffExecutablePath {
    if ($script:GroffCompletionCatalog.ExecutablePath) {
        return $script:GroffCompletionCatalog.ExecutablePath
    }

    foreach ($candidate in @('groff.exe', 'groff')) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if (-not $command) {
            continue
        }

        $script:GroffCompletionCatalog.ExecutablePath = if ($command.Path) {
            $command.Path
        } elseif ($command.Source) {
            $command.Source
        } else {
            $command.Name
        }

        if (-not [string]::IsNullOrWhiteSpace($script:GroffCompletionCatalog.ExecutablePath)) {
            return $script:GroffCompletionCatalog.ExecutablePath
        }
    }

    $null
}

function Ensure-GroffCommandAlias {
    $existingAlias = Get-Alias -Name groff -ErrorAction SilentlyContinue
    if ($existingAlias) {
        return
    }

    $groffExeCommand = Get-Command -Name groff.exe -ErrorAction SilentlyContinue
    if (-not $groffExeCommand) {
        return
    }

    $groffCommand = Get-Command -Name groff -ErrorAction SilentlyContinue
    if ($groffCommand -and
        ($groffCommand.CommandType -ne 'Application' -or $groffCommand.Name -ne 'groff.exe')) {
        return
    }

    Set-Alias -Name groff -Value groff.exe -Option AllScope -Scope Global
}

function Get-GroffHelpText {
    if ($null -ne $script:GroffCompletionCatalog.HelpText) {
        return $script:GroffCompletionCatalog.HelpText
    }

    $executablePath = Get-GroffExecutablePath
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        $script:GroffCompletionCatalog.HelpText = ''
        return $script:GroffCompletionCatalog.HelpText
    }

    try {
        $script:GroffCompletionCatalog.HelpText = ((& $executablePath --help 2>&1) -join [Environment]::NewLine)
    } catch {
        $script:GroffCompletionCatalog.HelpText = ''
    }

    $script:GroffCompletionCatalog.HelpText
}

function Get-GroffHelpOptionTokens {
    param([string]$HelpText)

    if ([string]::IsNullOrWhiteSpace($HelpText)) {
        return @()
    }

    $matches = [regex]::Matches(
        $HelpText,
        '(?<!\w)(--[a-z][a-z\-]*)(?:=[^\s,]+)?|(?<!\w)(-[A-Za-z])'
    )

    Get-GroffUniqueStrings -Items @(
        foreach ($match in $matches) {
            if ($match.Groups[1].Success) {
                $match.Groups[1].Value
                continue
            }

            if ($match.Groups[2].Success) {
                $match.Groups[2].Value
            }
        }
    )
}

function Get-GroffStaticOptionDefinitions {
    @(
        [pscustomobject]@{ Short = '-a'; Long = $null; Canonical = '-a'; Description = 'Produce an ASCII description of the output'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-b'; Long = $null; Canonical = '-b'; Description = 'Print backtraces with errors or warnings'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-c'; Long = $null; Canonical = '-c'; Description = 'Disable color output'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-C'; Long = $null; Canonical = '-C'; Description = 'Enable compatibility mode'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-d'; Long = $null; Canonical = '-d'; Description = 'Define a string'; ValueMode = 'Required'; ValueKind = 'DefineString'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-D'; Long = $null; Canonical = '-D'; Description = 'Use the default input encoding'; ValueMode = 'Required'; ValueKind = 'Encoding'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-e'; Long = $null; Canonical = '-e'; Description = 'Preprocess with eqn'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-E'; Long = $null; Canonical = '-E'; Description = 'Inhibit all errors'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-f'; Long = $null; Canonical = '-f'; Description = 'Use the default font family'; ValueMode = 'Required'; ValueKind = 'OpaqueValue'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-F'; Long = $null; Canonical = '-F'; Description = 'Search a directory for device directories'; ValueMode = 'Required'; ValueKind = 'DirectoryPath'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-g'; Long = $null; Canonical = '-g'; Description = 'Preprocess with grn'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-G'; Long = $null; Canonical = '-G'; Description = 'Preprocess with grap'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-h'; Long = '--help'; Canonical = '--help'; Description = 'Show help and exit'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $true }
        [pscustomobject]@{ Short = '-i'; Long = $null; Canonical = '-i'; Description = 'Read standard input after named input files'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-I'; Long = $null; Canonical = '-I'; Description = 'Search a directory for include files and grops'; ValueMode = 'Required'; ValueKind = 'DirectoryPath'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-j'; Long = $null; Canonical = '-j'; Description = 'Preprocess with chem'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-J'; Long = $null; Canonical = '-J'; Description = 'Preprocess with gideal when available'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-k'; Long = $null; Canonical = '-k'; Description = 'Preprocess with preconv'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-K'; Long = $null; Canonical = '-K'; Description = 'Use the input encoding'; ValueMode = 'Required'; ValueKind = 'Encoding'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-l'; Long = $null; Canonical = '-l'; Description = 'Spool the output'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-L'; Long = $null; Canonical = '-L'; Description = 'Pass an argument to the spooler'; ValueMode = 'Required'; ValueKind = 'OpaqueValue'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-m'; Long = $null; Canonical = '-m'; Description = 'Read a macro package'; ValueMode = 'Required'; ValueKind = 'MacroPackage'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-M'; Long = $null; Canonical = '-M'; Description = 'Search a directory for macro files'; ValueMode = 'Required'; ValueKind = 'DirectoryPath'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-n'; Long = $null; Canonical = '-n'; Description = 'Set the first page number'; ValueMode = 'Required'; ValueKind = 'OpaqueValue'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-N'; Long = $null; Canonical = '-N'; Description = 'Disallow newlines within eqn delimiters'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-o'; Long = $null; Canonical = '-o'; Description = 'Output only selected pages'; ValueMode = 'Required'; ValueKind = 'OpaqueValue'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-p'; Long = $null; Canonical = '-p'; Description = 'Preprocess with pic'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-P'; Long = $null; Canonical = '-P'; Description = 'Pass an argument to the postprocessor'; ValueMode = 'Required'; ValueKind = 'OpaqueValue'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-r'; Long = $null; Canonical = '-r'; Description = 'Define a number register'; ValueMode = 'Required'; ValueKind = 'DefineRegister'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-R'; Long = $null; Canonical = '-R'; Description = 'Preprocess with refer'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-s'; Long = $null; Canonical = '-s'; Description = 'Preprocess with soelim'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-S'; Long = $null; Canonical = '-S'; Description = 'Enable safer mode'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-t'; Long = $null; Canonical = '-t'; Description = 'Preprocess with tbl'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-T'; Long = $null; Canonical = '-T'; Description = 'Use an output device'; ValueMode = 'Required'; ValueKind = 'OutputDevice'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-U'; Long = $null; Canonical = '-U'; Description = 'Enable unsafe mode'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-v'; Long = '--version'; Canonical = '--version'; Description = 'Show version information and exit'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-V'; Long = $null; Canonical = '-V'; Description = 'Print commands instead of running them'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-w'; Long = $null; Canonical = '-w'; Description = 'Enable a warning category'; ValueMode = 'Required'; ValueKind = 'WarningCategory'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-W'; Long = $null; Canonical = '-W'; Description = 'Inhibit a warning category'; ValueMode = 'Required'; ValueKind = 'WarningCategory'; ShortAllowsSeparate = $true; ShortAllowsAttached = $true; Terminal = $false }
        [pscustomobject]@{ Short = '-X'; Long = $null; Canonical = '-X'; Description = 'Use the X11 previewer'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-z'; Long = $null; Canonical = '-z'; Description = 'Suppress formatted output'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
        [pscustomobject]@{ Short = '-Z'; Long = $null; Canonical = '-Z'; Description = 'Do not postprocess'; ValueMode = 'None'; ValueKind = 'None'; ShortAllowsSeparate = $false; ShortAllowsAttached = $false; Terminal = $false }
    )
}

function Get-GroffDiscoveryRoots {
    $commandPath = Get-GroffExecutablePath
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return @()
    }

    $commandDirectory = Split-Path -Path $commandPath -Parent
    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($relativePath in @(
            '..\share\groff',
            '..\..\share\groff',
            '..\tools\share\groff',
            '..\..\tools\share\groff',
            '..\lib\groff\tools\share\groff',
            '..\..\lib\groff\tools\share\groff'
        )) {
        try {
            $candidate = [System.IO.Path]::GetFullPath((Join-Path -Path $commandDirectory -ChildPath $relativePath))
            if (Test-Path -LiteralPath $candidate) {
                [void]$candidates.Add($candidate)
            }
        } catch {
        }
    }

    Get-GroffUniqueStrings -Items @($candidates.ToArray())
}

function Get-GroffOutputDevices {
    $devices = New-Object System.Collections.Generic.List[string]
    foreach ($root in @(Get-GroffDiscoveryRoots)) {
        $fontRoot = Join-Path -Path $root -ChildPath 'current\font'
        if (-not (Test-Path -LiteralPath $fontRoot)) {
            continue
        }

        foreach ($directory in @(Get-ChildItem -LiteralPath $fontRoot -Directory -Filter 'dev*' -ErrorAction SilentlyContinue)) {
            if ($directory.Name.Length -gt 3) {
                [void]$devices.Add($directory.Name.Substring(3))
            }
        }
    }

    foreach ($device in @('ascii', 'cp1047', 'dvi', 'html', 'latin1', 'lbp', 'lj4', 'pdf', 'ps', 'utf8', 'xhtml', 'X75', 'X75-12', 'X100', 'X100-12')) {
        [void]$devices.Add($device)
    }

    Get-GroffUniqueStrings -Items @($devices.ToArray()) | Sort-Object
}

function Get-GroffMacroPackages {
    $packages = New-Object System.Collections.Generic.List[string]
    foreach ($root in @(Get-GroffDiscoveryRoots)) {
        foreach ($childPath in @('current\tmac', 'site-tmac')) {
            $tmacRoot = Join-Path -Path $root -ChildPath $childPath
            if (-not (Test-Path -LiteralPath $tmacRoot)) {
                continue
            }

            foreach ($file in @(Get-ChildItem -LiteralPath $tmacRoot -File -ErrorAction SilentlyContinue)) {
                $name = $null
                if ($file.Name.StartsWith('tmac.', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $name = $file.Name.Substring(5)
                } elseif ($file.Name.EndsWith('.tmac', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                }

                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    [void]$packages.Add($name)
                }
            }
        }
    }

    foreach ($package in @('man', 'mandoc', 'mdoc', 'me', 'mm', 'mom', 'ms', 'www', 'andoc')) {
        [void]$packages.Add($package)
    }

    Get-GroffUniqueStrings -Items @($packages.ToArray()) | Sort-Object
}

function Initialize-GroffCompletionCatalog {
    if ($script:GroffCompletionCatalog.Initialized) {
        return
    }

    $helpText = Get-GroffHelpText
    $helpTokens = @(Get-GroffHelpOptionTokens -HelpText $helpText)
    $definitions = @(Get-GroffStaticOptionDefinitions)

    if ($helpTokens.Count -gt 0) {
        $script:GroffCompletionCatalog.HelpOptionTokens = @($helpTokens)
        $helpSet = New-GroffStringSet
        foreach ($token in $helpTokens) {
            [void]$helpSet.Add($token)
        }

        $definitions = @(
            foreach ($definition in $definitions) {
                if (($definition.Long -eq '--help') -or ($definition.Long -eq '--version')) {
                    $definition
                    continue
                }

                if ($helpSet.Contains($definition.Short)) {
                    $definition
                }
            }
        )
    }

    $script:GroffCompletionCatalog.OptionDefinitions = $definitions
    $script:GroffCompletionCatalog.ShortOptionMap = New-GroffStringObjectMap
    $script:GroffCompletionCatalog.LongOptionMap = New-GroffStringObjectMap
    $script:GroffCompletionCatalog.OptionSuggestions = @()
    $script:GroffCompletionCatalog.LongSuggestions = @()

    foreach ($definition in $definitions) {
        $script:GroffCompletionCatalog.ShortOptionMap[$definition.Short] = $definition
        $script:GroffCompletionCatalog.OptionSuggestions += [pscustomobject]@{
            Token       = $definition.Short
            Description = $definition.Description
        }

        if (-not [string]::IsNullOrWhiteSpace($definition.Long)) {
            $script:GroffCompletionCatalog.LongOptionMap[$definition.Long] = $definition
            $entry = [pscustomobject]@{
                Token       = $definition.Long
                Description = $definition.Description
            }

            $script:GroffCompletionCatalog.OptionSuggestions += $entry
            $script:GroffCompletionCatalog.LongSuggestions += $entry
        }
    }

    $script:GroffCompletionCatalog.OptionSuggestions += [pscustomobject]@{
        Token       = '--'
        Description = 'Stop option parsing and treat later arguments as input files'
    }

    $script:GroffCompletionCatalog.OutputDevices = @(Get-GroffOutputDevices)
    $script:GroffCompletionCatalog.MacroPackages = @(Get-GroffMacroPackages)
    $script:GroffCompletionCatalog.WarningCategories = @(Get-GroffUniqueStrings -Items $script:GroffCompletionCatalog.WarningCategories)
    $script:GroffCompletionCatalog.EncodingHints = @(Get-GroffUniqueStrings -Items $script:GroffCompletionCatalog.EncodingHints)
    $script:GroffCompletionCatalog.Initialized = $true
}

function New-GroffParseState {
    @{
        EndOfOptions          = $false
        PendingSeparateOption = $null
        HelpRequested         = $false
    }
}

function Parse-GroffShortToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token) -or ($Token -eq '-') -or -not $Token.StartsWith('-') -or $Token.StartsWith('--')) {
        return $null
    }

    for ($index = 1; $index -lt $Token.Length; $index++) {
        $optionToken = '-' + $Token[$index]
        $definition = $script:GroffCompletionCatalog.ShortOptionMap[$optionToken]
        if ($null -eq $definition) {
            break
        }

        if ($definition.ValueMode -ne 'None') {
            $attachedValue = ''
            if (($index + 1) -lt $Token.Length) {
                $attachedValue = $Token.Substring($index + 1)
            }

            return [pscustomobject]@{
                OptionToken      = $optionToken
                RequiresSeparate = [string]::IsNullOrEmpty($attachedValue)
                AttachedValue    = $attachedValue
                PrefixText       = $Token.Substring(0, $index + 1)
            }
        }
    }

    $null
}

function Update-GroffParseState {
    param(
        [hashtable]$State,
        [string[]]$Tokens
    )

    foreach ($token in @($Tokens)) {
        if ($State.PendingSeparateOption) {
            $State.PendingSeparateOption = $null
            continue
        }

        if ($State.EndOfOptions) {
            continue
        }

        if ($token -eq '--') {
            $State.EndOfOptions = $true
            continue
        }

        if ([string]::IsNullOrWhiteSpace($token) -or ($token -eq '-')) {
            continue
        }

        if ($token.StartsWith('--')) {
            if ($token -eq '--help') {
                $State.HelpRequested = $true
            }
            continue
        }

        if ($token -eq '-h') {
            $State.HelpRequested = $true
            continue
        }

        if ($token.StartsWith('-')) {
            $parsedToken = Parse-GroffShortToken -Token $token
            if ($parsedToken -and $parsedToken.RequiresSeparate) {
                $State.PendingSeparateOption = $parsedToken.OptionToken
            }
        }
    }
}

function Get-GroffPathCompletions {
    param(
        [string]$InputPath,
        [switch]$DirectoriesOnly
    )

    $quoteCharacter = Get-GroffQuoteCharacter -InputText $InputPath
    $cleanInput = Remove-GroffOuterQuotes -InputText $InputPath
    $pathSeparatorChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $inputEndsWithSeparator = $false
    if (-not [string]::IsNullOrEmpty($cleanInput)) {
        foreach ($separator in $pathSeparatorChars) {
            if ($cleanInput.EndsWith([string]$separator, [System.StringComparison]::Ordinal)) {
                $inputEndsWithSeparator = $true
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        return @()
    }

    if ($inputEndsWithSeparator) {
        $parentPath = $cleanInput
        $leaf = ''
    } else {
        $parentPath = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parentPath)) {
            $parentPath = '.'
        }
        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $items = @(Get-ChildItem -Path $parentPath -Filter $filter -ErrorAction SilentlyContinue)
    if ($DirectoriesOnly) {
        $items = @($items | Where-Object { $_.PSIsContainer })
    }

    $results = foreach ($item in $items) {
        $completionPath = if ([System.IO.Path]::IsPathRooted($cleanInput)) {
            Join-Path -Path $parentPath -ChildPath $item.Name
        } elseif ($parentPath -eq '.') {
            $item.Name
        } else {
            Join-Path -Path $parentPath -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionPath += [System.IO.Path]::DirectorySeparatorChar
        }

        if (($null -ne $quoteCharacter) -or ($completionPath -match '\s')) {
            $completionPath = ConvertTo-GroffQuotedValue -Value $completionPath -QuoteCharacter $quoteCharacter
        }

        $resultType = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }
        New-GroffCompletionResult -CompletionText $completionPath -ResultType $resultType -ToolTip $item.FullName
    }

    @($results)
}

function Get-GroffCatalogValueCompletions {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$TokenPrefix,
        [string]$ToolTipPrefix
    )

    $cleanValue = Remove-GroffOuterQuotes -InputText $CurrentValue
    $results = foreach ($value in @($Values)) {
        if (-not [string]::IsNullOrWhiteSpace($cleanValue) -and -not $value.StartsWith($cleanValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $completionText = if ([string]::IsNullOrWhiteSpace($TokenPrefix)) { $value } else { $TokenPrefix + $value }
        $toolTip = if ([string]::IsNullOrWhiteSpace($ToolTipPrefix)) { $value } else { $ToolTipPrefix + $value }
        New-GroffCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $toolTip
    }

    @($results)
}

function Get-GroffPlaceholderValueCompletions {
    param(
        [string]$OptionToken,
        [string]$CurrentValue,
        [string]$TokenPrefix
    )

    $hintSource = if ([string]::IsNullOrWhiteSpace($TokenPrefix)) {
        $script:GroffCompletionCatalog.PlaceholderHints
    } else {
        $script:GroffCompletionCatalog.AttachedPlaceholderHints
    }

    $hints = @($hintSource[$OptionToken])
    $cleanValue = Remove-GroffOuterQuotes -InputText $CurrentValue
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($hint in $hints) {
        if (-not [string]::IsNullOrWhiteSpace($cleanValue) -and -not $hint.StartsWith($cleanValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $completionText = if ([string]::IsNullOrWhiteSpace($TokenPrefix)) { $hint } else { $TokenPrefix + $hint }
        [void]$results.Add((New-GroffCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip ($OptionToken + ' value')))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($cleanValue)) {
        $completionText = if ([string]::IsNullOrWhiteSpace($TokenPrefix)) { $cleanValue } else { $TokenPrefix + $cleanValue }
        [void]$results.Add((New-GroffCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip ($OptionToken + ' value')))
    }

    @($results.ToArray())
}

function Get-GroffDirectoryValueCompletions {
    param(
        [string]$CurrentValue,
        [string]$TokenPrefix
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        $completionText = if ([string]::IsNullOrWhiteSpace($TokenPrefix)) { '<directory>' } else { $TokenPrefix + '<directory>' }
        return @(
            New-GroffCompletionResult -CompletionText $completionText -ListItemText '<directory>' -ResultType 'ParameterValue' -ToolTip 'Directory path.'
        )
    }

    if ([string]::IsNullOrWhiteSpace($TokenPrefix)) {
        return @(Get-GroffPathCompletions -InputPath $CurrentValue -DirectoriesOnly)
    }

    $results = foreach ($pathResult in @(Get-GroffPathCompletions -InputPath $CurrentValue -DirectoriesOnly)) {
        New-GroffCompletionResult -CompletionText ($TokenPrefix + $pathResult.CompletionText) -ResultType $pathResult.ResultType -ToolTip $pathResult.ToolTip
    }

    @($results)
}

function Get-GroffOperandCompletions {
    param([string]$CurrentValue)

    $results = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrEmpty($CurrentValue) -or '-'.StartsWith($CurrentValue, [System.StringComparison]::Ordinal)) {
        [void]$results.Add((New-GroffCompletionResult -CompletionText '-' -ResultType 'ParameterValue' -ToolTip 'Read from standard input'))
    }

    if (-not [string]::IsNullOrEmpty($CurrentValue) -and ($CurrentValue -ne '-')) {
        foreach ($result in @(Get-GroffPathCompletions -InputPath $CurrentValue)) {
            [void]$results.Add($result)
        }
    }

    @($results.ToArray())
}

function Get-GroffValueCompletions {
    param(
        [string]$OptionToken,
        [string]$CurrentValue,
        [string]$TokenPrefix = ''
    )

    $definition = $script:GroffCompletionCatalog.ShortOptionMap[$OptionToken]
    if ($null -eq $definition) {
        return @()
    }

    switch ($definition.ValueKind) {
        'OutputDevice' {
            return @(Get-GroffCatalogValueCompletions -Values $script:GroffCompletionCatalog.OutputDevices -CurrentValue $CurrentValue -TokenPrefix $TokenPrefix -ToolTipPrefix 'Output device ')
        }
        'MacroPackage' {
            return @(Get-GroffCatalogValueCompletions -Values $script:GroffCompletionCatalog.MacroPackages -CurrentValue $CurrentValue -TokenPrefix $TokenPrefix -ToolTipPrefix 'Macro package ')
        }
        'WarningCategory' {
            return @(Get-GroffCatalogValueCompletions -Values $script:GroffCompletionCatalog.WarningCategories -CurrentValue $CurrentValue -TokenPrefix $TokenPrefix -ToolTipPrefix 'Warning category ')
        }
        'Encoding' {
            return @(Get-GroffCatalogValueCompletions -Values $script:GroffCompletionCatalog.EncodingHints -CurrentValue $CurrentValue -TokenPrefix $TokenPrefix -ToolTipPrefix 'Encoding ')
        }
        'DirectoryPath' {
            return @(Get-GroffDirectoryValueCompletions -CurrentValue $CurrentValue -TokenPrefix $TokenPrefix)
        }
        'DefineString' { return @(Get-GroffPlaceholderValueCompletions -OptionToken $OptionToken -CurrentValue $CurrentValue -TokenPrefix $TokenPrefix) }
        'DefineRegister' { return @(Get-GroffPlaceholderValueCompletions -OptionToken $OptionToken -CurrentValue $CurrentValue -TokenPrefix $TokenPrefix) }
        'OpaqueValue' { return @(Get-GroffPlaceholderValueCompletions -OptionToken $OptionToken -CurrentValue $CurrentValue -TokenPrefix $TokenPrefix) }
        Default { return @() }
    }
}

function Get-GroffOptionCompletions {
    param([string]$CurrentToken)

    $suggestions = if ($CurrentToken.StartsWith('--', [System.StringComparison]::Ordinal)) {
        @($script:GroffCompletionCatalog.LongSuggestions)
    } else {
        @($script:GroffCompletionCatalog.OptionSuggestions)
    }

    $results = foreach ($suggestion in $suggestions) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentToken) -and -not $suggestion.Token.StartsWith($CurrentToken, [System.StringComparison]::Ordinal)) {
            continue
        }

        New-GroffCompletionResult -CompletionText $suggestion.Token -ResultType 'ParameterName' -ToolTip $suggestion.Description
    }

    @($results)
}

function Get-GroffTerminalCompletions {
    param([string]$CurrentWord)

    $completionText = if ([string]::IsNullOrEmpty($CurrentWord)) { ' ' } else { $CurrentWord }
    @(
        New-GroffCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip 'No further arguments are valid after help.'
    )
}

function Complete-Groff {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-GroffCompletionCatalog

    $allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokens = @($allTokens | Select-Object -Skip 1)
    $line = $commandAst.ToString()
    $currentWord = if ($null -eq $wordToComplete) {
        Get-GroffCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback ''
    } elseif ($wordToComplete.Length -eq 0) {
        ''
    } else {
        $wordToComplete
    }
    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)

    if ($hasTrailingSpace) {
        $tokensBeforeCurrent = @($tokens)
    } elseif ($tokens.Count -gt 1) {
        $tokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
    } else {
        $tokensBeforeCurrent = @()
    }

    $state = New-GroffParseState
    Update-GroffParseState -State $state -Tokens $tokensBeforeCurrent

    if ($state.HelpRequested) {
        return @(Get-GroffTerminalCompletions -CurrentWord $currentWord)
    }

    if ($state.PendingSeparateOption) {
        return @(Get-GroffValueCompletions -OptionToken $state.PendingSeparateOption -CurrentValue $currentWord)
    }

    if ($state.EndOfOptions) {
        return @(Get-GroffOperandCompletions -CurrentValue $currentWord)
    }

    if ($currentWord.StartsWith('--', [System.StringComparison]::Ordinal)) {
        if ($currentWord.Contains('=')) {
            return @()
        }

        return @(Get-GroffOptionCompletions -CurrentToken $currentWord)
    }

    if ($currentWord -eq '-') {
        return @(Get-GroffOptionCompletions -CurrentToken $currentWord)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-', [System.StringComparison]::Ordinal)) {
        $parsedCurrent = Parse-GroffShortToken -Token $currentWord
        if ($parsedCurrent) {
            return @(Get-GroffValueCompletions -OptionToken $parsedCurrent.OptionToken -CurrentValue $parsedCurrent.AttachedValue -TokenPrefix $parsedCurrent.PrefixText)
        }

        return @(Get-GroffOptionCompletions -CurrentToken $currentWord)
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        $results = New-Object System.Collections.Generic.List[object]
        foreach ($optionResult in @(Get-GroffOptionCompletions -CurrentToken $currentWord)) {
            [void]$results.Add($optionResult)
        }
        foreach ($operandResult in @(Get-GroffOperandCompletions -CurrentValue $currentWord)) {
            [void]$results.Add($operandResult)
        }
        return @($results.ToArray())
    }

    @(Get-GroffOperandCompletions -CurrentValue $currentWord)
}

foreach ($commandName in @('groff', 'groff.exe')) {
    Register-ArgumentCompleter -Native -CommandName $commandName -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        Complete-Groff -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
    }
}

Ensure-GroffCommandAlias
