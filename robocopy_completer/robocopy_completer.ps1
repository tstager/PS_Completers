# robocopy tab completion for PowerShell
# Builds completion data from robocopy built-in help.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name RobocopyCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:RobocopyCompletionCatalog = @{
        Initialized     = $false
        Options         = @()
        OptionInfoByKey = @{}
    }
}

function Invoke-RobocopyHelpText {
    if (-not (Get-Command -Name robocopy.exe -ErrorAction SilentlyContinue)) {
        return @()
    }

    try {
        @(& robocopy.exe '/?' 2>$null)
    } catch {
        @()
    }
}

function Get-RobocopyStaticOptionMetadata {
    @{
        '/copy' = @{
            Key                 = '/copy'
            Display             = '/COPY:copyflag[s]'
            CompletionText      = '/COPY:'
            Description         = 'Specify which file properties to copy.'
            InlineValueKind     = 'Flags'
            AllowedCharacters   = 'DATSOUX'
            Suggestions         = @('DAT', 'DATS', 'DATSOU', 'DATSOUX')
        }
        '/dcopy' = @{
            Key                 = '/dcopy'
            Display             = '/DCOPY:copyflag[s]'
            CompletionText      = '/DCOPY:'
            Description         = 'Specify which directory properties to copy.'
            InlineValueKind     = 'Flags'
            AllowedCharacters   = 'DATEX'
            Suggestions         = @('DA', 'DAT', 'DATEX')
        }
        '/a+' = @{
            Key                 = '/a+'
            Display             = '/A+:[RASHCNET]'
            CompletionText      = '/A+:'
            Description         = 'Add file attributes to copied files.'
            InlineValueKind     = 'Flags'
            AllowedCharacters   = 'RASHCNET'
            Suggestions         = @('R', 'A', 'H', 'S', 'C', 'N', 'E', 'T')
        }
        '/a-' = @{
            Key                 = '/a-'
            Display             = '/A-:[RASHCNETO]'
            CompletionText      = '/A-:'
            Description         = 'Remove file attributes from copied files.'
            InlineValueKind     = 'Flags'
            AllowedCharacters   = 'RASHCNETO'
            Suggestions         = @('R', 'A', 'H', 'S', 'C', 'N', 'E', 'T', 'O')
        }
        '/xa' = @{
            Key                 = '/xa'
            Display             = '/XA:[RASHCNETO]'
            CompletionText      = '/XA:'
            Description         = 'Exclude files with the specified attributes.'
            InlineValueKind     = 'Flags'
            AllowedCharacters   = 'RASHCNETO'
            Suggestions         = @('R', 'A', 'H', 'S', 'C', 'N', 'E', 'T', 'O')
        }
        '/ia' = @{
            Key                 = '/ia'
            Display             = '/IA:[RASHCNETO]'
            CompletionText      = '/IA:'
            Description         = 'Include only files with the specified attributes.'
            InlineValueKind     = 'Flags'
            AllowedCharacters   = 'RASHCNETO'
            Suggestions         = @('R', 'A', 'H', 'S', 'C', 'N', 'E', 'T', 'O')
        }
        '/lev' = @{
            Key                 = '/lev'
            Display             = '/LEV:n'
            CompletionText      = '/LEV:'
            Description         = 'Copy only the top n levels of the source tree.'
            InlineValueKind     = 'List'
            Suggestions         = @('1', '2', '3', '5', '10')
        }
        '/mon' = @{
            Key                 = '/mon'
            Display             = '/MON:n'
            CompletionText      = '/MON:'
            Description         = 'Monitor and rerun when more than n changes are seen.'
            InlineValueKind     = 'List'
            Suggestions         = @('1', '5', '10', '50', '100')
        }
        '/mot' = @{
            Key                 = '/mot'
            Display             = '/MOT:m'
            CompletionText      = '/MOT:'
            Description         = 'Monitor and rerun in m minutes when changes are detected.'
            InlineValueKind     = 'List'
            Suggestions         = @('1', '5', '10', '15', '30', '60')
        }
        '/rh' = @{
            Key                 = '/rh'
            Display             = '/RH:hhmm-hhmm'
            CompletionText      = '/RH:'
            Description         = 'Restrict new copies to the specified run hours.'
            InlineValueKind     = 'List'
            Suggestions         = @('0000-2359', '0800-1700', '0900-1800')
        }
        '/ipg' = @{
            Key                 = '/ipg'
            Display             = '/IPG:n'
            CompletionText      = '/IPG:'
            Description         = 'Set the inter-packet gap in milliseconds.'
            InlineValueKind     = 'List'
            Suggestions         = @('0', '1', '10', '50', '100')
        }
        '/mt' = @{
            Key                 = '/mt'
            Display             = '/MT[:n]'
            CompletionText      = '/MT'
            Description         = 'Enable multithreaded copies with an optional thread count.'
            InlineValueKind     = 'List'
            OptionalInlineValue = $true
            Suggestions         = @('4', '8', '16', '32', '64', '128')
        }
        '/sparse' = @{
            Key                 = '/sparse'
            Display             = '/SPARSE[:Y/N]'
            CompletionText      = '/SPARSE'
            Description         = 'Control whether sparse file state is retained during copy.'
            InlineValueKind     = 'List'
            OptionalInlineValue = $true
            Suggestions         = @('Y', 'N')
        }
        '/lfsm' = @{
            Key                 = '/lfsm'
            Display             = '/LFSM[:n[kmg]]'
            CompletionText      = '/LFSM'
            Description         = 'Enable low free space mode with an optional free-space floor.'
            InlineValueKind     = 'List'
            OptionalInlineValue = $true
            Suggestions         = @('100M', '500M', '1G', '5G')
        }
        '/iomaxsize' = @{
            Key                 = '/iomaxsize'
            Display             = '/IOMAXSIZE:n[kmg]'
            CompletionText      = '/IOMAXSIZE:'
            Description         = 'Set the maximum I/O size per read or write.'
            InlineValueKind     = 'List'
            Suggestions         = @('1M', '4M', '8M', '16M')
        }
        '/iorate' = @{
            Key                 = '/iorate'
            Display             = '/IORATE:n[kmg]'
            CompletionText      = '/IORATE:'
            Description         = 'Set the maximum I/O bandwidth to use.'
            InlineValueKind     = 'List'
            Suggestions         = @('1M', '10M', '100M', '1G')
        }
        '/threshold' = @{
            Key                 = '/threshold'
            Display             = '/THRESHOLD:n[kmg]'
            CompletionText      = '/THRESHOLD:'
            Description         = 'Throttle only files larger than the specified threshold.'
            InlineValueKind     = 'List'
            Suggestions         = @('1M', '10M', '100M', '1G')
        }
        '/max' = @{
            Key                 = '/max'
            Display             = '/MAX:n'
            CompletionText      = '/MAX:'
            Description         = 'Specify the maximum file size to copy.'
            InlineValueKind     = 'List'
            Suggestions         = @('1024', '1048576', '1073741824')
        }
        '/min' = @{
            Key                 = '/min'
            Display             = '/MIN:n'
            CompletionText      = '/MIN:'
            Description         = 'Specify the minimum file size to copy.'
            InlineValueKind     = 'List'
            Suggestions         = @('1', '1024', '1048576')
        }
        '/maxage' = @{
            Key                 = '/maxage'
            Display             = '/MAXAGE:n'
            CompletionText      = '/MAXAGE:'
            Description         = 'Specify the maximum file age to copy.'
            InlineValueKind     = 'List'
            Suggestions         = @('1', '7', '30', '365')
        }
        '/minage' = @{
            Key                 = '/minage'
            Display             = '/MINAGE:n'
            CompletionText      = '/MINAGE:'
            Description         = 'Specify the minimum file age to copy.'
            InlineValueKind     = 'List'
            Suggestions         = @('1', '7', '30', '365')
        }
        '/maxlad' = @{
            Key                 = '/maxlad'
            Display             = '/MAXLAD:n'
            CompletionText      = '/MAXLAD:'
            Description         = 'Specify the maximum last-access date to copy.'
            InlineValueKind     = 'List'
            Suggestions         = @('1', '7', '30', '365')
        }
        '/minlad' = @{
            Key                 = '/minlad'
            Display             = '/MINLAD:n'
            CompletionText      = '/MINLAD:'
            Description         = 'Specify the minimum last-access date to copy.'
            InlineValueKind     = 'List'
            Suggestions         = @('1', '7', '30', '365')
        }
        '/r' = @{
            Key                 = '/r'
            Display             = '/R:n'
            CompletionText      = '/R:'
            Description         = 'Specify the number of retries on failed copies.'
            InlineValueKind     = 'List'
            Suggestions         = @('0', '1', '3', '5', '10')
        }
        '/w' = @{
            Key                 = '/w'
            Display             = '/W:n'
            CompletionText      = '/W:'
            Description         = 'Specify the wait time between retries in seconds.'
            InlineValueKind     = 'List'
            Suggestions         = @('0', '1', '5', '10', '30')
        }
        '/log' = @{
            Key                 = '/log'
            Display             = '/LOG:file'
            CompletionText      = '/LOG:'
            Description         = 'Write status output to the specified log file.'
            InlineValueKind     = 'Path'
        }
        '/log+' = @{
            Key                 = '/log+'
            Display             = '/LOG+:file'
            CompletionText      = '/LOG+:'
            Description         = 'Append status output to the specified log file.'
            InlineValueKind     = 'Path'
        }
        '/unilog' = @{
            Key                 = '/unilog'
            Display             = '/UNILOG:file'
            CompletionText      = '/UNILOG:'
            Description         = 'Write Unicode status output to the specified log file.'
            InlineValueKind     = 'Path'
        }
        '/unilog+' = @{
            Key                 = '/unilog+'
            Display             = '/UNILOG+:file'
            CompletionText      = '/UNILOG+:'
            Description         = 'Append Unicode status output to the specified log file.'
            InlineValueKind     = 'Path'
        }
        '/job' = @{
            Key                 = '/job'
            Display             = '/JOB:jobname'
            CompletionText      = '/JOB:'
            Description         = 'Load parameters from the specified job file.'
            InlineValueKind     = 'Job'
        }
        '/save' = @{
            Key                 = '/save'
            Display             = '/SAVE:jobname'
            CompletionText      = '/SAVE:'
            Description         = 'Save parameters to the specified job file.'
            InlineValueKind     = 'Job'
        }
        '/xf' = @{
            Key                 = '/xf'
            Display             = '/XF file [file]...'
            CompletionText      = '/XF'
            Description         = 'Exclude files matching the given names or paths.'
            SeparateValueKind   = 'FileSpecMulti'
        }
        '/xd' = @{
            Key                 = '/xd'
            Display             = '/XD dirs [dirs]...'
            CompletionText      = '/XD'
            Description         = 'Exclude directories matching the given names or paths.'
            SeparateValueKind   = 'DirectorySpecMulti'
        }
    }
}

function New-RobocopyCompletionResult {
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

function Remove-RobocopyOuterQuotes {
    param([string]$Text)

    if ($null -eq $Text) {
        return $Text
    }

    $Text.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-RobocopyQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        return '"' + $Value + '"'
    }

    $Value
}

function ConvertFrom-RobocopyHelpToken {
    param([string]$Token)

    $cleanToken = $Token.Trim().TrimEnd('.', ',', ';', ')')
    if ([string]::IsNullOrWhiteSpace($cleanToken) -or -not $cleanToken.StartsWith('/')) {
        return $null
    }

    $match = [regex]::Match($cleanToken, '^(?<root>/[A-Za-z0-9?]+(?:[+-])?)(?<suffix>.*)$')
    if (-not $match.Success) {
        return $null
    }

    $root = $match.Groups['root'].Value
    $suffix = $match.Groups['suffix'].Value
    $completionText = if ($suffix -match '^\[:') {
        $root
    } elseif ($suffix.StartsWith(':')) {
        "${root}:"
    } else {
        $root
    }

    @{
        Key            = $root.ToLowerInvariant()
        Display        = $cleanToken
        CompletionText = $completionText
        Description    = $cleanToken
    }
}

function Initialize-RobocopyCompletion {
    if ($script:RobocopyCompletionCatalog.Initialized) {
        return
    }

    $catalog = @{}
    $staticMetadata = Get-RobocopyStaticOptionMetadata

    foreach ($key in $staticMetadata.Keys) {
        $catalog[$key] = @{} + $staticMetadata[$key]
    }

    $helpLines = Invoke-RobocopyHelpText
    foreach ($line in $helpLines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $description = ''
        if ($line -match '::\s*(.+)$') {
            $description = $matches[1].Trim()
        } else {
            $description = ([regex]::Replace($line, '(?<!\S)/[A-Za-z0-9?][^\s]*', '') -replace '\s{2,}', ' ').Trim(' ', ':')
        }

        foreach ($match in [regex]::Matches($line, '(?<!\S)/[A-Za-z0-9?][^\s]*')) {
            $parsed = ConvertFrom-RobocopyHelpToken -Token $match.Value
            if ($null -eq $parsed) {
                continue
            }

            $key = $parsed.Key
            if ($catalog.ContainsKey($key)) {
                if (-not [string]::IsNullOrWhiteSpace($description)) {
                    $catalog[$key]['Description'] = $description
                }

                if (-not $catalog[$key].ContainsKey('Display')) {
                    $catalog[$key]['Display'] = $parsed.Display
                }

                if (-not $catalog[$key].ContainsKey('CompletionText')) {
                    $catalog[$key]['CompletionText'] = $parsed.CompletionText
                }

                continue
            }

            $catalog[$key] = @{} + $parsed
            if (-not [string]::IsNullOrWhiteSpace($description)) {
                $catalog[$key]['Description'] = $description
            }
        }
    }

    $script:RobocopyCompletionCatalog.Options = @(
        foreach ($entry in $catalog.Values) {
            [pscustomobject]$entry
        }
    ) | Sort-Object -Property CompletionText, Display -Unique

    $script:RobocopyCompletionCatalog.OptionInfoByKey = @{}
    foreach ($option in $script:RobocopyCompletionCatalog.Options) {
        $script:RobocopyCompletionCatalog.OptionInfoByKey[$option.Key] = $option
    }

    $script:RobocopyCompletionCatalog.Initialized = $true
}

function Get-RobocopyOptionKey {
    param([string]$Token)

    $cleanToken = Remove-RobocopyOuterQuotes $Token
    if ([string]::IsNullOrWhiteSpace($cleanToken) -or -not $cleanToken.StartsWith('/')) {
        return $null
    }

    $match = [regex]::Match($cleanToken, '^(?<root>/[A-Za-z0-9?]+(?:[+-])?)')
    if ($match.Success) {
        return $match.Groups['root'].Value.ToLowerInvariant()
    }

    $null
}

function Resolve-RobocopySourcePath {
    param([string]$PathText)

    $cleanPath = Remove-RobocopyOuterQuotes $PathText
    if ([string]::IsNullOrWhiteSpace($cleanPath)) {
        return $null
    }

    try {
        (Resolve-Path -LiteralPath $cleanPath -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Path)
    } catch {
        $null
    }
}

function Get-RobocopyArgumentList {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $arguments = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $arguments += $element.Extent.Text
        }
    }

    $arguments
}

function Get-RobocopyCompletionContext {
    param([string[]]$Arguments)

    Initialize-RobocopyCompletion

    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingMode = $null
    $sawOption = $false

    foreach ($argument in $Arguments) {
        if ([string]::IsNullOrWhiteSpace($argument)) {
            continue
        }

        $optionKey = Get-RobocopyOptionKey -Token $argument

        if ($pendingMode) {
            if ($null -eq $optionKey) {
                continue
            }

            $pendingMode = $null
        }

        if ($null -ne $optionKey) {
            $sawOption = $true
            if ($script:RobocopyCompletionCatalog.OptionInfoByKey.ContainsKey($optionKey)) {
                $optionInfo = $script:RobocopyCompletionCatalog.OptionInfoByKey[$optionKey]
                if ($optionInfo.PSObject.Properties.Name -contains 'SeparateValueKind') {
                    $pendingMode = $optionInfo.SeparateValueKind
                }
            }

            continue
        }

        $positionals.Add($argument)
    }

    [pscustomobject]@{
        PendingMode = $pendingMode
        SawOption   = $sawOption
        Positionals = @($positionals)
        SourcePath  = if ($positionals.Count -gt 0) {
            Resolve-RobocopySourcePath -PathText $positionals[0]
        } else {
            $null
        }
    }
}

function Get-RobocopyUniqueCompletions {
    param([System.Management.Automation.CompletionResult[]]$Results)

    $seen = @{}
    $unique = @()

    foreach ($result in $Results) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.ContainsKey($result.CompletionText)) {
            continue
        }

        $seen[$result.CompletionText] = $true
        $unique += $result
    }

    $unique
}

function Get-RobocopyPathCompletions {
    param(
        [string]$InputPath,
        [string]$Kind,
        [string]$CompletionPrefix = ''
    )

    $cleanInput = Remove-RobocopyOuterQuotes $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and $InputPath.StartsWith('"')

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $inputIsRooted = -not [string]::IsNullOrWhiteSpace($cleanInput) -and [System.IO.Path]::IsPathRooted($cleanInput)
    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like "$leaf*" }

    if ($Kind -eq 'Directory') {
        $items = $items | Where-Object { $_.PSIsContainer }
    } elseif ($Kind -eq 'File') {
        $items = $items | Where-Object { -not $_.PSIsContainer }
    }

    foreach ($item in $items | Sort-Object -Property Name) {
        if ($inputIsRooted) {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $pathText = $item.Name
        } else {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $tokenText = if ([string]::IsNullOrEmpty($CompletionPrefix)) {
            $pathText
        } else {
            $CompletionPrefix + $pathText
        }

        New-RobocopyCompletionResult `
            -CompletionText (ConvertTo-RobocopyQuotedValue -Value $tokenText -AlwaysQuote $alwaysQuote) `
            -ListItemText $tokenText `
            -ResultType 'ParameterValue' `
            -ToolTip $item.FullName
    }
}

function Get-RobocopySourceRelativeCompletions {
    param(
        [string]$InputPath,
        [string]$SourcePath,
        [string]$Kind
    )

    $cleanInput = Remove-RobocopyOuterQuotes $InputPath
    if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        return @()
    }

    if (-not [string]::IsNullOrWhiteSpace($cleanInput) -and [System.IO.Path]::IsPathRooted($cleanInput)) {
        return @(Get-RobocopyPathCompletions -InputPath $InputPath -Kind $Kind)
    }

    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and $InputPath.StartsWith('"')

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $relativeParent = ''
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]$') {
        $relativeParent = $cleanInput.TrimEnd([char[]]@([char]92, [char]47))
        $leaf = ''
    } else {
        $relativeParent = Split-Path -Path $cleanInput -Parent
        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $basePath = if ([string]::IsNullOrWhiteSpace($relativeParent)) {
        $SourcePath
    } else {
        Join-Path -Path $SourcePath -ChildPath $relativeParent
    }

    $items = @(Get-ChildItem -LiteralPath $basePath -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like "$leaf*" }

    if ($Kind -eq 'Directory') {
        $items = $items | Where-Object { $_.PSIsContainer }
    } elseif ($Kind -eq 'File') {
        $items = $items | Where-Object { -not $_.PSIsContainer }
    }

    foreach ($item in $items | Sort-Object -Property Name) {
        $pathText = if ([string]::IsNullOrWhiteSpace($relativeParent)) {
            $item.Name
        } else {
            Join-Path -Path $relativeParent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        New-RobocopyCompletionResult `
            -CompletionText (ConvertTo-RobocopyQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote) `
            -ListItemText $pathText `
            -ResultType 'ParameterValue' `
            -ToolTip $item.FullName
    }
}

function Get-RobocopyWildcardSuggestions {
    param(
        [string]$WordToComplete,
        [string[]]$Candidates
    )

    $cleanWord = Remove-RobocopyOuterQuotes $WordToComplete
    foreach ($candidate in ($Candidates | Sort-Object -Unique)) {
        if ($candidate -like "$cleanWord*") {
            New-RobocopyCompletionResult -CompletionText $candidate -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip 'Wildcard selection pattern.'
        }
    }
}

function Get-RobocopyFileSpecCompletions {
    param(
        [string]$WordToComplete,
        [string]$SourcePath
    )

    $results = @()
    $results += @(Get-RobocopyWildcardSuggestions -WordToComplete $WordToComplete -Candidates @('*', '*.*'))
    $results += @(Get-RobocopySourceRelativeCompletions -InputPath $WordToComplete -SourcePath $SourcePath -Kind 'Any')
    Get-RobocopyUniqueCompletions -Results $results
}

function Get-RobocopyDirectorySpecCompletions {
    param(
        [string]$WordToComplete,
        [string]$SourcePath
    )

    $results = @()
    $results += @(Get-RobocopyWildcardSuggestions -WordToComplete $WordToComplete -Candidates @('*'))
    $results += @(Get-RobocopySourceRelativeCompletions -InputPath $WordToComplete -SourcePath $SourcePath -Kind 'Directory')
    Get-RobocopyUniqueCompletions -Results $results
}

function Get-RobocopyPrefixedSuggestions {
    param(
        [string]$Prefix,
        [string]$CurrentValue,
        [string[]]$Suggestions,
        [string]$ToolTip
    )

    $cleanCurrentValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue.ToUpperInvariant() }
    foreach ($suggestion in ($Suggestions | Sort-Object -Unique)) {
        if ($suggestion.ToUpperInvariant().StartsWith($cleanCurrentValue)) {
            $tokenText = $Prefix + $suggestion
            New-RobocopyCompletionResult -CompletionText (ConvertTo-RobocopyQuotedValue -Value $tokenText) -ListItemText $tokenText -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }
}

function Get-RobocopyFlagValueCompletions {
    param(
        [string]$Prefix,
        [string]$CurrentValue,
        [string]$AllowedCharacters,
        [string[]]$Suggestions,
        [string]$ToolTip
    )

    $results = @()
    $currentUpper = if ($null -eq $CurrentValue) { '' } else { $CurrentValue.ToUpperInvariant() }

    $results += @(Get-RobocopyPrefixedSuggestions -Prefix $Prefix -CurrentValue $CurrentValue -Suggestions $Suggestions -ToolTip $ToolTip)

    foreach ($character in $AllowedCharacters.ToCharArray()) {
        if ($currentUpper.IndexOf([string]$character) -ge 0) {
            continue
        }

        $candidate = $currentUpper + [string]$character
        $tokenText = $Prefix + $candidate
        $results += New-RobocopyCompletionResult -CompletionText $tokenText -ListItemText $tokenText -ResultType 'ParameterValue' -ToolTip $ToolTip
    }

    Get-RobocopyUniqueCompletions -Results $results
}

function Get-RobocopyJobCompletions {
    param(
        [string]$Prefix,
        [string]$CurrentValue,
        [string]$ToolTip
    )

    $cleanCurrentValue = Remove-RobocopyOuterQuotes $CurrentValue
    $jobFiles = @(Get-ChildItem -LiteralPath . -Filter '*.rcj' -File -ErrorAction SilentlyContinue)

    foreach ($jobFile in $jobFiles | Sort-Object -Property Name) {
        $jobName = [System.IO.Path]::GetFileNameWithoutExtension($jobFile.Name)
        if ($jobName -like "$cleanCurrentValue*") {
            $tokenText = $Prefix + $jobName
            New-RobocopyCompletionResult -CompletionText (ConvertTo-RobocopyQuotedValue -Value $tokenText) -ListItemText $tokenText -ResultType 'ParameterValue' -ToolTip $jobFile.FullName
        }
    }
}

function Get-RobocopyInlineValueCompletions {
    param([string]$WordToComplete)

    Initialize-RobocopyCompletion

    $cleanWord = Remove-RobocopyOuterQuotes $WordToComplete
    $match = [regex]::Match($cleanWord, '^(?<root>/[A-Za-z0-9?]+(?:[+-])?)(?<separator>:)(?<value>.*)$')
    if (-not $match.Success) {
        return @()
    }

    $key = $match.Groups['root'].Value.ToLowerInvariant()
    if (-not $script:RobocopyCompletionCatalog.OptionInfoByKey.ContainsKey($key)) {
        return @()
    }

    $optionInfo = $script:RobocopyCompletionCatalog.OptionInfoByKey[$key]
    if (-not ($optionInfo.PSObject.Properties.Name -contains 'InlineValueKind')) {
        return @()
    }

    $prefix = $match.Groups['root'].Value + ':'
    $currentValue = $match.Groups['value'].Value

    switch ($optionInfo.InlineValueKind) {
        'Path' {
            return @(Get-RobocopyPathCompletions -InputPath $currentValue -Kind 'Any' -CompletionPrefix $prefix)
        }
        'Job' {
            return @(Get-RobocopyJobCompletions -Prefix $prefix -CurrentValue $currentValue -ToolTip $optionInfo.Description)
        }
        'List' {
            return @(Get-RobocopyPrefixedSuggestions -Prefix $prefix -CurrentValue $currentValue -Suggestions $optionInfo.Suggestions -ToolTip $optionInfo.Description)
        }
        'Flags' {
            return @(Get-RobocopyFlagValueCompletions -Prefix $prefix -CurrentValue $currentValue -AllowedCharacters $optionInfo.AllowedCharacters -Suggestions $optionInfo.Suggestions -ToolTip $optionInfo.Description)
        }
    }

    @()
}

function Get-RobocopyOptionCompletions {
    param([string]$WordToComplete)

    Initialize-RobocopyCompletion

    $prefix = if ([string]::IsNullOrWhiteSpace($WordToComplete)) {
        ''
    } else {
        (Remove-RobocopyOuterQuotes $WordToComplete).ToUpperInvariant()
    }

    foreach ($option in $script:RobocopyCompletionCatalog.Options) {
        if ($option.CompletionText.ToUpperInvariant().StartsWith($prefix) -or $option.Display.ToUpperInvariant().StartsWith($prefix)) {
            New-RobocopyCompletionResult `
                -CompletionText $option.CompletionText `
                -ListItemText $option.Display `
                -ResultType 'ParameterName' `
                -ToolTip $option.Description
        }
    }
}

function Complete-Robocopy {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if (-not (Get-Command -Name robocopy.exe -ErrorAction SilentlyContinue)) {
        return @()
    }

    Initialize-RobocopyCompletion

    $currentWord = if ($null -eq $wordToComplete) { '' } else { $wordToComplete }

    if (-not [string]::IsNullOrEmpty($currentWord) -and (Remove-RobocopyOuterQuotes $currentWord).StartsWith('/')) {
        $inlineValueCompletions = @(Get-RobocopyInlineValueCompletions -WordToComplete $currentWord)
        if ($inlineValueCompletions.Count -gt 0) {
            return $inlineValueCompletions
        }

        return @(Get-RobocopyOptionCompletions -WordToComplete $currentWord)
    }

    $arguments = @(Get-RobocopyArgumentList -CommandAst $commandAst -CursorPosition $cursorPosition)
    $context = Get-RobocopyCompletionContext -Arguments $arguments

    switch ($context.PendingMode) {
        'FileSpecMulti' {
            return @(Get-RobocopyFileSpecCompletions -WordToComplete $currentWord -SourcePath $context.SourcePath)
        }
        'DirectorySpecMulti' {
            return @(Get-RobocopyDirectorySpecCompletions -WordToComplete $currentWord -SourcePath $context.SourcePath)
        }
    }

    if ($context.Positionals.Count -lt 2) {
        return @(Get-RobocopyPathCompletions -InputPath $currentWord -Kind 'Directory')
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        $results = @()
        $results += @(Get-RobocopyFileSpecCompletions -WordToComplete $currentWord -SourcePath $context.SourcePath)
        $results += @(Get-RobocopyOptionCompletions -WordToComplete $currentWord)
        return @(Get-RobocopyUniqueCompletions -Results $results)
    }

    @(Get-RobocopyFileSpecCompletions -WordToComplete $currentWord -SourcePath $context.SourcePath)
}

Register-ArgumentCompleter -Native -CommandName 'robocopy', 'robocopy.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Robocopy -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
