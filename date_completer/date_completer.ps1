# date tab completion for PowerShell
# Static option completion for date.exe and date.

Set-StrictMode -Version 2.0

function Get-DateCompletionOptions {
    $cache = Get-Variable -Name 'DateCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-d', '--date', '-f', '--file', '-I', '--iso-8601', '-R', '--rfc-email', '--rfc-3339', '--debug', '-r', '--reference', '-s', '--set', '-u', '--universal', '--utc', '--resolution', '-h', '--help', '-V', '--version')
    $commandCandidates = @('date.exe', 'date')
    foreach ($candidate in $commandCandidates) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            continue
        }

        try {
            $helpOutput = $null | & $command.Source --help 2>&1 | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String
        } catch {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($helpOutput)) {
            continue
        }

        $options = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $descriptions = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
        foreach ($line in ([regex]::Split($helpOutput, '\r?\n'))) {
            # Only the option column at the head of a line holds real options.
            # date's help prints timezone offsets mid-line ('%:::z ... (e.g., -04,
            # +05:30)', 'Example: Mon, 14 Aug 2006 02:34:56 -0600'), which the
            # token regex alone would happily harvest as options.
            if ($line -notmatch '^\s*(?<run>-{1,2}[A-Za-z0-9][^\s,]*(?:,\s*-{1,2}[A-Za-z0-9][^\s,]*)*)') {
                continue
            }

            $optionRun = $Matches['run']
            foreach ($match in [regex]::Matches($optionRun, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|=|\[|$))')) {
                $rawOption = $match.Groups[1].Value
                $normalized = $rawOption.Trim()
                if ($normalized -match '^-\d') {
                    continue
                }

                if ($normalized -match '^-{1,2}[A-Za-z0-9][A-Za-z0-9-]*$') {
                    [void]$options.Add($normalized)
                    if (-not $descriptions.ContainsKey($normalized)) {
                        $description = ($line -replace '^\s*(?:-{1,2}[A-Za-z0-9][A-Za-z0-9-]*(?:[=\[<]\S*)?[,\s]+)+', '').Trim()
                        if ($description -and $description -ne $line.Trim()) {
                            $descriptions[$normalized] = $description
                        }
                    }
                }
            }
        }

        if ($options.Count -gt 0) {
            Set-Variable -Name 'DateCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'DateCompletionDescriptions' -Value $descriptions -Scope Script
            Set-Variable -Name 'DateCompletionHelpText' -Value $helpOutput -Scope Script
            return (Get-Variable -Name 'DateCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'DateCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'DateCompletionOptions' -Scope Script).Value
}


function New-DateCompletionResult {
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

function Remove-DateOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-DateQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        $escaped = $Value.Replace('`', '``').Replace('"', '`"')
        return '"' + $escaped + '"'
    }

    $Value
}

function Get-DateCurrentToken {
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

    # The closing quote is optional so an in-progress quoted path containing a
    # space stays one token instead of degrading to its last \S+ fragment.
    $parts = @([regex]::Matches($prefix, '"[^"]*"?|''[^'']*''?|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-DatePathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-DateOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    $forceJoin = $false
    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]+$') {
        $parent = $cleanInput
        $leaf = ''
    } elseif ($cleanInput -match '^\.{1,2}$') {
        # Split-Path -Leaf resolves '.' and '..' to a real directory name, which
        # would filter the listing by that name instead of listing the directory.
        $parent = $cleanInput
        $leaf = ''
        $forceJoin = $true
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
    $items = @($items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name)

    foreach ($item in $items) {
        $pathText = if (-not $forceJoin -and ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput))) {
            $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-DateQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-DateCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-DateCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-DateOptionValueTable {
    $cache = Get-Variable -Name 'DateOptionValueTable' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $dateValues = @(
        @{ Text = 'now'; Tip = 'Current time.' }
        @{ Text = 'today'; Tip = 'Start of today.' }
        @{ Text = 'yesterday'; Tip = 'Same time yesterday.' }
        @{ Text = 'tomorrow'; Tip = 'Same time tomorrow.' }
    )
    $isoValues = @(
        @{ Text = 'date'; Tip = 'Date only.' }
        @{ Text = 'hours'; Tip = 'Date and hours.' }
        @{ Text = 'minutes'; Tip = 'Date, hours and minutes.' }
        @{ Text = 'seconds'; Tip = 'Date and time to seconds.' }
        @{ Text = 'ns'; Tip = 'Date and time to nanoseconds.' }
    )
    $rfcValues = @(
        @{ Text = 'date'; Tip = 'Date only.' }
        @{ Text = 'seconds'; Tip = 'Date and time to seconds.' }
        @{ Text = 'ns'; Tip = 'Date and time to nanoseconds.' }
    )
    $setValues = @(
        @{ Text = '<string>'; Tip = 'Time to set.' }
    )

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    foreach ($name in @('-d', '--date')) { $table[$name] = $dateValues }
    foreach ($name in @('-f', '--file', '-r', '--reference')) { $table[$name] = 'path' }
    foreach ($name in @('-I', '--iso-8601')) { $table[$name] = $isoValues }
    $table['--rfc-3339'] = $rfcValues
    foreach ($name in @('-s', '--set')) { $table[$name] = $setValues }

    Set-Variable -Name 'DateOptionValueTable' -Value $table -Scope Script
    $table
}

function Get-DateOptionValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    # -I / --iso-8601 declare an OPTIONAL argument ('-I[FMT], --iso-8601[=FMT]').
    # GNU date only accepts such a value attached: 'date -I seconds' and
    # 'date --iso-8601 seconds' both fail with "invalid date 'seconds'", while
    # '-Iseconds' and '--iso-8601=seconds' work on both installed builds.
    $attachedOnly = @('-I', '--iso-8601')

    $option = $null
    $prefix = $CurrentWord
    $attached = ''
    if ($CurrentWord -match '^(?<option>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = $Matches['option']
        $prefix = $Matches['value']
        $attached = $option + '='
    } elseif ($CurrentWord -match '^(?<option>-I)(?<value>.*)$') {
        $option = $Matches['option']
        $prefix = $Matches['value']
        $attached = $option
    } elseif ($attachedOnly -contains $CurrentWord) {
        $option = $CurrentWord
        $prefix = ''
        $attached = $CurrentWord + '='
    } elseif (-not $CurrentWord.StartsWith('-')) {
        $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
        if ([string]::IsNullOrEmpty($CurrentWord)) {
            if ($elements.Count -gt 1) {
                $option = $elements[-1]
            }
        } elseif ($elements.Count -gt 2 -and $elements[-1] -eq $CurrentWord) {
            $option = $elements[-2]
        }

        if ($attachedOnly -contains $option) {
            return @()
        }
    }

    $table = Get-DateOptionValueTable
    if ([string]::IsNullOrEmpty($option) -or -not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-DatePathCompletions -InputPath $prefix) {
                New-DateCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType $result.ResultType -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-DateCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function ConvertFrom-DateFormatHelp {
    param([string]$HelpText)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $specifiers = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ([regex]::Split($HelpText, '\r?\n'))) {
        $specifier = $null
        $description = ''
        if ($line -match '^\s*\|\s*(?<spec>%\S+)\s*\|\s*(?<desc>[^|]*?)\s*\|') {
            # uutils prints the interpreted sequences as a markdown table.
            $specifier = $Matches['spec']
            $description = $Matches['desc']
        } elseif ($line -match '^\s+(?<spec>%\S+)\s{2,}(?<desc>\S.*?)\s*$') {
            # GNU prints '  %a   locale''s abbreviated weekday name (e.g., Sun)'.
            $specifier = $Matches['spec']
            $description = $Matches['desc']
        }

        if ($specifier -and $seen.Add($specifier)) {
            [void]$specifiers.Add(@{ Text = $specifier; Tip = $description })
        }
    }

    $specifiers.ToArray()
}

function Get-DateFormatSpecifierTable {
    $cache = Get-Variable -Name 'DateFormatSpecifiers' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    # Populating the option catalog also caches the raw help text this parses.
    [void](Get-DateCompletionOptions)
    $helpCache = Get-Variable -Name 'DateCompletionHelpText' -Scope Script -ErrorAction Ignore
    $specifiers = @()
    if ($null -ne $helpCache -and -not [string]::IsNullOrWhiteSpace($helpCache.Value)) {
        $specifiers = @(ConvertFrom-DateFormatHelp -HelpText $helpCache.Value)
    }

    if ($specifiers.Count -eq 0) {
        $specifiers = @(ConvertFrom-DateFormatHelp -HelpText @'
  %%    a literal %
  %a    locale's abbreviated weekday name
  %A    locale's full weekday name
  %b    locale's abbreviated month name
  %B    locale's full month name
  %c    locale's date and time
  %C    century; like %Y, except omit last two digits
  %d    day of month
  %D    date; same as %m/%d/%y
  %e    day of month, space padded; same as %_d
  %F    full date; same as %Y-%m-%d
  %g    last two digits of year of ISO week number (see %G)
  %G    year of ISO week number (see %V); normally useful only with %V
  %h    same as %b
  %H    hour (00..23)
  %I    hour (01..12)
  %j    day of year (001..366)
  %k    hour, space padded ( 0..23); same as %_H
  %l    hour, space padded ( 1..12); same as %_I
  %m    month (01..12)
  %M    minute (00..59)
  %n    a newline
  %N    nanoseconds (000000000..999999999)
  %p    locale's equivalent of either AM or PM; blank if not known
  %P    like %p, but lower case
  %q    quarter of year (1..4)
  %r    locale's 12-hour clock time
  %R    24-hour hour and minute; same as %H:%M
  %s    seconds since 1970-01-01 00:00:00 UTC
  %S    second (00..60)
  %t    a tab
  %T    time; same as %H:%M:%S
  %u    day of week (1..7); 1 is Monday
  %U    week number of year, with Sunday as first day of week (00..53)
  %V    ISO week number, with Monday as first day of week (01..53)
  %w    day of week (0..6); 0 is Sunday
  %W    week number of year, with Monday as first day of week (00..53)
  %x    locale's date representation
  %X    locale's time representation
  %y    last two digits of year (00..99)
  %Y    year
  %z    +hhmm numeric time zone
  %:z   +hh:mm numeric time zone
  %::z  +hh:mm:ss numeric time zone
  %:::z numeric time zone with : to necessary precision
  %Z    alphabetic time zone abbreviation
'@)
    }

    Set-Variable -Name 'DateFormatSpecifiers' -Value $specifiers -Scope Script
    $specifiers
}

function Expand-DateFormatToken {
    param([string]$CurrentWord)

    $specifiers = @(Get-DateFormatSpecifierTable)
    $index = $CurrentWord.LastIndexOf('%')
    $base = $CurrentWord
    $partial = '%'
    if ($index -ge 0) {
        $base = $CurrentWord.Substring(0, $index)
        $partial = $CurrentWord.Substring($index)
    }

    $matched = @(
        foreach ($entry in $specifiers) {
            if ($entry.Text.StartsWith($partial, [System.StringComparison]::Ordinal)) {
                New-DateCompletionResult -CompletionText ($base + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
    if ($matched.Count -gt 0) {
        return $matched
    }

    # The tail is already a complete specifier or literal text; append instead.
    @(
        foreach ($entry in $specifiers) {
            New-DateCompletionResult -CompletionText ($CurrentWord + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
        }
    )
}

function Get-DateOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'DateCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for date.'
}

function Complete-Date {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-DateCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $optionValues = @(Get-DateOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('+')) {
        return @(Expand-DateFormatToken -CurrentWord $currentWord)
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-DateCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-DateCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-DateOptionDescription -Option $option)
                }
            }
        )
    }

    Get-DatePathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'date', 'date.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Date -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
