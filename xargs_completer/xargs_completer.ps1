# xargs tab completion for PowerShell
# Registers a native PowerShell argument completer for xargs.exe using the option surface
# of the xargs that resolves on PATH (its --help, cached) and lightweight value-aware completion.

Set-StrictMode -Version 2.0

function New-XargsCompletionResult {
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

function Get-XargsStaticOptionTable {
    # GNU findutils surface; also the value-kind source for options the live help lists.
    @(
        [pscustomobject]@{ Token = '-0'; LongToken = '--null'; Description = 'Items are separated by a null, not whitespace'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = '-a'; LongToken = '--arg-file'; Description = 'Read arguments from FILE, not standard input'; ValueKind = 'FilePath' },
        [pscustomobject]@{ Token = '-d'; LongToken = '--delimiter'; Description = 'Items in input stream are separated by CHARACTER'; ValueKind = 'Delimiter' },
        [pscustomobject]@{ Token = '-E'; LongToken = ''; Description = 'Set logical EOF string'; ValueKind = 'EofString' },
        [pscustomobject]@{ Token = '-e'; LongToken = '--eof'; Description = 'Equivalent to -E END if END is specified'; ValueKind = 'EofString' },
        [pscustomobject]@{ Token = '-I'; LongToken = ''; Description = 'Same as --replace=R'; ValueKind = 'ReplaceText' },
        [pscustomobject]@{ Token = '-i'; LongToken = '--replace'; Description = 'Replace R in INITIAL-ARGS with names read from standard input (R only in the attached form -iR / --replace=R; otherwise {})'; ValueKind = 'ReplaceTextAttached' },
        [pscustomobject]@{ Token = '-L'; LongToken = '--max-lines'; Description = 'Use at most MAX-LINES non-blank input lines per command line'; ValueKind = 'Integer' },
        [pscustomobject]@{ Token = '-l'; LongToken = ''; Description = 'Similar to -L but defaults to at most one non-blank input line'; ValueKind = 'OptionalInteger' },
        [pscustomobject]@{ Token = '-n'; LongToken = '--max-args'; Description = 'Use at most MAX-ARGS arguments per command line'; ValueKind = 'Integer' },
        [pscustomobject]@{ Token = '-o'; LongToken = '--open-tty'; Description = 'Reopen stdin as /dev/tty in the child process'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = '-P'; LongToken = '--max-procs'; Description = 'Run at most MAX-PROCS processes at a time'; ValueKind = 'Integer' },
        [pscustomobject]@{ Token = '-p'; LongToken = '--interactive'; Description = 'Prompt before running commands'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = ''; LongToken = '--process-slot-var'; Description = 'Set environment variable VAR in child processes'; ValueKind = 'VarName' },
        [pscustomobject]@{ Token = '-r'; LongToken = '--no-run-if-empty'; Description = 'If there are no arguments, then do not run COMMAND'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = '-s'; LongToken = '--max-chars'; Description = 'Limit length of command line to MAX-CHARS'; ValueKind = 'Integer' },
        [pscustomobject]@{ Token = ''; LongToken = '--show-limits'; Description = 'Show limits on command-line length'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = '-t'; LongToken = '--verbose'; Description = 'Print commands before executing them'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = '-x'; LongToken = '--exit'; Description = 'Exit if the size (see -s) is exceeded'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = ''; LongToken = '--help'; Description = 'Display help and exit'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = ''; LongToken = '--version'; Description = 'Output version information and exit'; ValueKind = 'NoValue' }
    )
}

function Get-XargsHelpText {
    param([string]$CommandPath)

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $CommandPath
        [void]$startInfo.ArgumentList.Add('--help')
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $process.StandardInput.Close()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            [void]$process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) {
                try { $process.Kill($true) } catch { Write-Debug -Message $_.Exception.Message }
                return ''
            }

            if ($outputTask.Wait(1000)) {
                return ($outputTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
            }
        } finally {
            $process.Dispose()
        }
    } catch {
        Write-Debug -Message "xargs --help probe failed: $($_.Exception.Message)"
    }

    ''
}

function ConvertFrom-XargsHelpText {
    param([string]$HelpText)

    $staticTable = @(Get-XargsStaticOptionTable)
    $specs = New-Object System.Collections.Generic.List[object]
    foreach ($line in $HelpText -split '\r?\n') {
        # Option rows start within a few columns; wrapped description lines are indented much deeper.
        if ($line -notmatch '^ {1,8}(?<spec>-\S.*?)(?: {2,}(?<desc>\S.*))?$') {
            continue
        }

        $description = $matches['desc']
        if ($matches['spec'] -notmatch '^(?:(?<short>-[A-Za-z0-9])(?=[,\s\[]|$))?,?\s*(?<long>--[A-Za-z0-9][A-Za-z0-9-]*)?(?<arg>.*)$') {
            continue
        }

        $short = $matches['short']
        $long = $matches['long']
        $argument = $matches['arg'].Trim()
        if (-not $short -and -not $long) {
            continue
        }

        $known = $null
        foreach ($option in $staticTable) {
            if (($long -and [string]::Equals($option.LongToken, $long, [System.StringComparison]::Ordinal)) -or ($short -and [string]::Equals($option.Token, $short, [System.StringComparison]::Ordinal))) {
                $known = $option
                break
            }
        }

        if ($known) {
            $valueKind = $known.ValueKind
            $description = $known.Description
        } elseif ($argument -and -not $argument.StartsWith('[')) {
            $valueKind = 'Value'
        } else {
            $valueKind = 'NoValue'
        }

        [void]$specs.Add([pscustomobject]@{
                Token       = if ($short) { $short } else { '' }
                LongToken   = if ($long) { $long } else { '' }
                Description = $description
                ValueKind   = $valueKind
                Placeholder = if ($argument) { '<' + ($argument -replace '[\[\]<>=]', '').ToLowerInvariant() + '>' } else { '' }
            })
    }

    @($specs.ToArray())
}

function Get-XargsOptionSpecs {
    # The option table follows the xargs that resolves on PATH (uutils and GNU findutils differ).
    $cache = Get-Variable -Name 'XargsOptionSpecCache' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.Path -eq $env:PATH) {
        if (-not $cache.Value.Source -or [System.IO.File]::GetLastWriteTimeUtc($cache.Value.Source) -eq $cache.Value.WriteTime) {
            return $cache.Value.Specs
        }
    }

    # A PATH scan in PATHEXT order; Get-Command spends seconds searching modules when xargs is absent.
    $source = $null
    $extensions = @($env:PATHEXT -split ';' | Where-Object { $_ })
    foreach ($directory in @($env:PATH -split ';' | Where-Object { $_ })) {
        if (-not [System.IO.Directory]::Exists($directory)) {
            continue
        }

        $candidates = [System.IO.Directory]::GetFiles($directory, 'xargs.*', [System.IO.EnumerationOptions]::new())
        if ($candidates.Count -eq 0) {
            continue
        }

        foreach ($extension in $extensions) {
            $source = $candidates | Where-Object { [System.IO.Path]::GetExtension($_) -eq $extension } | Select-Object -First 1
            if ($source) {
                break
            }
        }

        if ($source) {
            break
        }
    }

    $writeTime = [datetime]::MinValue
    $specs = @()
    if ($source) {
        $writeTime = [System.IO.File]::GetLastWriteTimeUtc($source)
        $specs = @(ConvertFrom-XargsHelpText -HelpText (Get-XargsHelpText -CommandPath $source))
    }

    if ($specs.Count -eq 0) {
        $specs = @(Get-XargsStaticOptionTable)
    }

    Set-Variable -Name 'XargsOptionSpecCache' -Value @{ Path = $env:PATH; Source = $source; WriteTime = $writeTime; Specs = $specs } -Scope Script
    $specs
}

function Get-XargsOptionSpecByToken {
    param([string]$Token)

    $cleanToken = if ([string]::IsNullOrWhiteSpace($Token)) { '' } else { $Token.Trim() }
    if ([string]::IsNullOrWhiteSpace($cleanToken)) {
        return $null
    }

    # Ordinal: -P/-p, -L/-l, -I/-i and -E/-e are distinct options.
    foreach ($option in Get-XargsOptionSpecs) {
        if ([string]::Equals($option.Token, $cleanToken, [System.StringComparison]::Ordinal) -or [string]::Equals($option.LongToken, $cleanToken, [System.StringComparison]::Ordinal)) {
            return $option
        }
    }

    $null
}

function Get-XargsOptionSuggestions {
    param(
        [string]$CurrentToken,
        [string]$Prefix = ''
    )

    $results = New-Object System.Collections.Generic.List[object]
    $typed = if ($null -eq $CurrentToken) { '' } else { $CurrentToken }
    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        $Prefix = ''
    }

    foreach ($option in Get-XargsOptionSpecs) {
        $matchingText = if ($typed.StartsWith('--')) { $option.LongToken } else { $option.Token }
        if ([string]::IsNullOrWhiteSpace($matchingText)) {
            continue
        }

        if ($matchingText -clike ([System.Management.Automation.WildcardPattern]::Escape($typed) + '*')) {
            $completionText = if ($Prefix) { $Prefix + $matchingText } else { $matchingText }
            [void]$results.Add((New-XargsCompletionResult -CompletionText $completionText -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $matchingText))
        }
    }

    @($results.ToArray())
}

function Get-XargsPathCompletions {
    param(
        [string]$CurrentValue,
        [string]$Prefix = ''
    )

    $results = New-Object System.Collections.Generic.List[object]
    $cleanValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue.Trim([char[]]@([char]34, [char]39)) }
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentValue) -and $CurrentValue.StartsWith('"')

    if ([string]::IsNullOrWhiteSpace($cleanValue)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanValue.EndsWith('\') -or $cleanValue.EndsWith('/')) {
        $parent = $cleanValue
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanValue -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }
        $leaf = Split-Path -Path $cleanValue -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    foreach ($item in @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)) {
        $completionText = if ($cleanValue -and -not [System.IO.Path]::IsPathRooted($cleanValue)) {
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

        if ($alwaysQuote -and -not $completionText.StartsWith('"')) {
            $completionText = '"' + $completionText + '"'
        }

        $completionText = $Prefix + $completionText
        [void]$results.Add((New-XargsCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $item.FullName -ListItemText $item.Name))
    }

    @($results.ToArray())
}

function Get-XargsValueSuggestions {
    param(
        [pscustomobject]$OptionSpec,
        [string]$CurrentValue,
        [string]$Prefix = ''
    )

    if ($null -eq $OptionSpec) {
        return @()
    }

    $typed = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $toolTip = if ([string]::IsNullOrWhiteSpace($OptionSpec.Description)) { $OptionSpec.Token } else { $OptionSpec.Description }

    if ($OptionSpec.ValueKind -eq 'FilePath') {
        $results = @(Get-XargsPathCompletions -CurrentValue $typed -Prefix $Prefix)
        if ($results.Count -gt 0) {
            return $results
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($typed)) {
        return @()
    }

    $placeholder = switch ($OptionSpec.ValueKind) {
        'FilePath' { '<arg-file>' }
        'Delimiter' { '<delimiter>' }
        'Integer' { '<max>' }
        'OptionalInteger' { '<max-lines>' }
        'ReplaceText' { '<R>' }
        'ReplaceTextAttached' { '<R>' }
        'EofString' { '<eof-string>' }
        'VarName' { '<var>' }
        'Value' { $OptionSpec.Placeholder }
        default { $null }
    }

    if ($null -eq $placeholder) {
        return @()
    }

    @(New-XargsCompletionResult -CompletionText ($Prefix + $placeholder) -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $placeholder)
}

function Get-XargsCommandNames {
    $cache = Get-Variable -Name 'XargsCommandCache' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.Path -eq $env:PATH) {
        return $cache.Value.Names
    }

    $names = @(
        Get-Command -CommandType Application -ErrorAction SilentlyContinue |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
            Where-Object { $_ -and $_ -ne 'xargs' } |
            Sort-Object -Unique
    )
    Set-Variable -Name 'XargsCommandCache' -Value @{ Path = $env:PATH; Names = $names } -Scope Script
    $names
}

function Get-XargsCommandSuggestions {
    param([string]$CurrentValue)

    $typed = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }

    @(
        foreach ($name in Get-XargsCommandNames) {
            if ($name.StartsWith($typed, [System.StringComparison]::OrdinalIgnoreCase)) {
                New-XargsCompletionResult -CompletionText $name -ResultType 'Command' -ToolTip 'Command to execute' -ListItemText $name
            }
        }
    )
}

function Test-XargsCommandOperandSeen {
    param([string[]]$TokensBeforeCurrent)

    $skipNext = $false
    foreach ($token in @($TokensBeforeCurrent)) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }

        if ($token -match '^--[A-Za-z0-9-]+=') {
            continue
        }

        # -i/--replace only take R attached, so the token after them is the COMMAND.
        if ($token -match '^--[A-Za-z0-9-]+$') {
            $spec = Get-XargsOptionSpecByToken -Token $token
            if ($spec -and $spec.ValueKind -notin @('NoValue', 'OptionalInteger', 'ReplaceTextAttached')) {
                $skipNext = $true
            }
            continue
        }

        if ($token -match '^-[A-Za-z0-9]') {
            $spec = Get-XargsOptionSpecByToken -Token $token.Substring(0, 2)
            if ($spec -and $token.Length -eq 2 -and $spec.ValueKind -notin @('NoValue', 'OptionalInteger', 'ReplaceTextAttached')) {
                $skipNext = $true
            }
            continue
        }

        return $true
    }

    $false
}

function Get-XargsCompletionContext {
    param(
        [string]$CurrentToken,
        [string[]]$TokensBeforeCurrent
    )

    $currentValue = $CurrentToken
    if ($currentValue -match '^(?<option>--[A-Za-z0-9][A-Za-z0-9\-]*)=(?<value>.*)$') {
        $optionSpec = Get-XargsOptionSpecByToken -Token $matches['option']
        if ($optionSpec -and $optionSpec.ValueKind -ne 'NoValue') {
            return [pscustomobject]@{
                OptionSpec = $optionSpec
                ValueText  = $matches['value']
                Prefix     = $matches['option'] + '='
            }
        }
    }

    if ($TokensBeforeCurrent.Count -gt 0) {
        $lastToken = $TokensBeforeCurrent[-1]
        $optionSpec = Get-XargsOptionSpecByToken -Token $lastToken
        if ($optionSpec -and $optionSpec.ValueKind -notin @('NoValue', 'ReplaceTextAttached')) {
            return [pscustomobject]@{
                OptionSpec = $optionSpec
                ValueText  = $currentValue
                Prefix     = ''
            }
        }
    }

    $null
}

Register-ArgumentCompleter -Native -CommandName 'xargs', 'xargs.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $tokensBeforeCurrent = @()
    foreach ($element in $commandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $cursorPosition) {
            $tokensBeforeCurrent += $element.Extent.Text
        }
    }

    $context = Get-XargsCompletionContext -CurrentToken $wordToComplete -TokensBeforeCurrent $tokensBeforeCurrent
    if ($context) {
        return Get-XargsValueSuggestions -OptionSpec $context.OptionSpec -CurrentValue $context.ValueText -Prefix $context.Prefix
    }

    if (-not [string]::IsNullOrWhiteSpace($wordToComplete) -and $wordToComplete.StartsWith('-')) {
        return Get-XargsOptionSuggestions -CurrentToken $wordToComplete
    }

    if (-not (Test-XargsCommandOperandSeen -TokensBeforeCurrent $tokensBeforeCurrent)) {
        return Get-XargsCommandSuggestions -CurrentValue $wordToComplete
    }

    @()
}
