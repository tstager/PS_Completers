# numfmt tab completion for PowerShell
# Static option completion for numfmt.exe and numfmt.

Set-StrictMode -Version 2.0

function Get-NumfmtCompletionOptions {
    $cache = Get-Variable -Name 'NumfmtCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('--debug', '--field', '--format', '--from', '--to', '--invalid', '--suffix', '--round', '--padding', '--grouping', '--header', '--zero-terminated', '--help', '--version', '-d', '-f', '-i', '-o', '-p', '-s', '-z')
    $commandCandidates = @('numfmt.exe', 'numfmt')
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
            foreach ($match in [regex]::Matches($line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|=|\[|$))')) {
                $rawOption = $match.Groups[1].Value
                $normalized = $rawOption.Trim()
                if ($normalized.StartsWith('--')) {
                    $normalized = $normalized -replace '\[.*$', ''
                    $normalized = $normalized -replace '=.*$', ''
                }
                if ($normalized -match '^-{1,2}[A-Za-z0-9][A-Za-z0-9-]*$') {
                    [void]$options.Add($normalized)
                if (-not $descriptions.ContainsKey($normalized)) {
                    $description = ($line -replace '^\s*(?:-{1,2}[A-Za-z0-9][A-Za-z0-9-]*(?:[=\[]\S*)?[,\s]+)+', '').Trim()
                    if ($description -and $description -ne $line.Trim()) {
                        $descriptions[$normalized] = $description
                    }
                }
                }
            }
        }

        if ($options.Count -gt 0) {
            Set-Variable -Name 'NumfmtCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'NumfmtCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'NumfmtCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'NumfmtCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'NumfmtCompletionOptions' -Scope Script).Value
}

function New-NumfmtCompletionResult {
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

function Get-NumfmtLineTokens {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    # Tokens come from the raw command text because the PowerShell parser drops a bare ','
    # ('numfmt -d , ') from CommandElements.
    if ([string]::IsNullOrWhiteSpace($Line)) {
        return @()
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    @([regex]::Matches($prefix, '"[^"]*"?|''[^'']*''?|\S+') | ForEach-Object { $_.Value })
}

function Get-NumfmtCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    if ($Line.Substring(0, $safeCursor) -match '\s$') {
        return ''
    }

    $parts = @(Get-NumfmtLineTokens -Line $Line -CursorPosition $CursorPosition)
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Resolve-NumfmtValueOption {
    param([string]$Token)

    # Map a short spelling or an '--opt=value' head to the long option that owns the value table.
    if ([string]::IsNullOrEmpty($Token)) {
        return $null
    }

    $name = $Token -replace '=.*$', ''
    if ($name -ceq '-d') {
        return '--delimiter'
    }

    $name
}

function Get-NumfmtValueTable {
    # Values verified against GNU coreutils 8.32 and uutils 0.11.0 --help. '--header[=N]' only
    # takes its value attached, so it is served for '--header=' and never for the next token.
    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['--field'] = @(
        @{ Text = '1'; Tip = 'Field 1 (N: the N-th field, counted from 1).' }
        @{ Text = '1,2'; Tip = 'Fields 1 and 2; ranges may be separated with commas.' }
        @{ Text = '2-'; Tip = 'N-: from the N-th field to the end of the line.' }
        @{ Text = '2-4'; Tip = 'N-M: from the N-th to the M-th field, inclusive.' }
        @{ Text = '-3'; Tip = '-M: from the first to the M-th field, inclusive.' }
        @{ Text = '-'; Tip = 'All fields.' }
    )
    $table['--format'] = @(
        @{ Text = '%f'; Tip = 'Floating-point format; FORMAT must print one %f argument.' }
        @{ Text = "%'f"; Quoted = '"%''f"'; Tip = 'Quote flag enables --grouping (locale permitting).' }
        @{ Text = '%10f'; Tip = 'Width value pads the output.' }
        @{ Text = '%010f'; Tip = 'Zero width zero-pads the number.' }
        @{ Text = '%-10f'; Tip = 'Negative width left-aligns.' }
        @{ Text = '%.1f'; Tip = 'Precision overrides the input-determined precision.' }
        @{ Text = '<format>'; Tip = 'printf-style floating-point format.' }
    )
    $table['--from'] = @(
        @{ Text = 'none'; Tip = 'No auto-scaling; suffixes trigger an error (default).' }
        @{ Text = 'auto'; Tip = 'Accept an optional one- or two-letter suffix: 1K = 1000, 1Ki = 1024.' }
        @{ Text = 'si'; Tip = 'Accept an optional single-letter suffix: 1K = 1000, 1M = 1000000.' }
        @{ Text = 'iec'; Tip = 'Accept an optional single-letter suffix: 1K = 1024, 1M = 1048576.' }
        @{ Text = 'iec-i'; Tip = 'Accept an optional two-letter suffix: 1Ki = 1024, 1Mi = 1048576.' }
    )
    $table['--to'] = @(
        @{ Text = 'none'; Tip = 'No auto-scaling (default).' }
        @{ Text = 'si'; Tip = 'Single-letter suffix: 1K = 1000, 1M = 1000000.' }
        @{ Text = 'iec'; Tip = 'Single-letter suffix: 1K = 1024, 1M = 1048576.' }
        @{ Text = 'iec-i'; Tip = 'Two-letter suffix: 1Ki = 1024, 1Mi = 1048576.' }
    )
    $table['--invalid'] = @(
        @{ Text = 'abort'; Tip = 'Stop at the first invalid number with exit status 2 (default).' }
        @{ Text = 'fail'; Tip = 'Warn for each invalid number; exit status 2.' }
        @{ Text = 'warn'; Tip = 'Warn for each invalid number; exit status 0.' }
        @{ Text = 'ignore'; Tip = 'Do not diagnose invalid numbers; exit status 0.' }
    )
    $table['--round'] = @(
        @{ Text = 'up'; Tip = 'Round up when scaling.' }
        @{ Text = 'down'; Tip = 'Round down when scaling.' }
        @{ Text = 'from-zero'; Tip = 'Round away from zero (default).' }
        @{ Text = 'towards-zero'; Tip = 'Round towards zero.' }
        @{ Text = 'nearest'; Tip = 'Round to the nearest value.' }
    )
    $table['--padding'] = @(
        @{ Text = '10'; Tip = 'Right-align in 10 characters.' }
        @{ Text = '-10'; Tip = 'Left-align in 10 characters (negative N).' }
        @{ Text = '<N>'; Tip = 'Pad the output to N characters.' }
    )
    $table['--suffix'] = @(
        @{ Text = 'B'; Tip = 'Print B after each number and accept it on input.' }
        @{ Text = '<suffix>'; Tip = 'Suffix printed after each number and accepted on input.' }
    )
    $table['--delimiter'] = @(
        @{ Text = ','; Tip = 'Comma field delimiter.' }
        @{ Text = ';'; Tip = 'Semicolon field delimiter.' }
        @{ Text = '|'; Tip = 'Pipe field delimiter.' }
        @{ Text = "`t"; Display = '<tab>'; Quoted = '"`t"'; Tip = 'Tab field delimiter (PowerShell "`t" escape).' }
        @{ Text = '<char>'; Tip = 'Single character to use instead of whitespace.' }
    )
    $table['--header'] = @(
        @{ Text = '1'; Tip = 'Print the first line without converting it.' }
        @{ Text = '<N>'; Tip = 'Number of header lines to print unconverted.' }
    )
    $table['--from-unit'] = @(
        @{ Text = '1'; Tip = 'Input unit size 1 (default).' }
        @{ Text = '1024'; Tip = 'Input unit size 1024.' }
        @{ Text = '<N>'; Tip = 'Input unit size.' }
    )
    $table['--to-unit'] = @(
        @{ Text = '1'; Tip = 'Output unit size 1 (default).' }
        @{ Text = '1024'; Tip = 'Output unit size 1024.' }
        @{ Text = '<N>'; Tip = 'Output unit size.' }
    )
    $table['--unit-separator'] = @(
        @{ Text = ' '; Display = '<space>'; Quoted = "' '"; Tip = 'Single space between the number and its unit.' }
        @{ Text = '<string>'; Tip = 'String printed between the number and its unit (uutils build).' }
    )
    $table
}

function Get-NumfmtValueCompletions {
    param(
        [string]$Option,
        [string]$Prefix,
        [string]$Attached = ''
    )

    $table = Get-NumfmtValueTable
    if ([string]::IsNullOrEmpty($Option) -or -not $table.ContainsKey($Option)) {
        return @()
    }

    # A quoted or half-quoted value is matched on its bare text and re-quoted the same way.
    $quote = ''
    if ($Prefix.Length -gt 0 -and ($Prefix[0] -eq '"' -or $Prefix[0] -eq "'")) {
        $quote = [string]$Prefix[0]
        $Prefix = $Prefix.Substring(1)
        if ($Prefix.EndsWith($quote)) {
            $Prefix = $Prefix.Substring(0, $Prefix.Length - 1)
        }
    }

    @(
        foreach ($entry in $table[$Option]) {
            if (-not $entry.Text.StartsWith($Prefix, [System.StringComparison]::Ordinal)) {
                continue
            }

            $display = if ($entry.ContainsKey('Display')) { $entry.Display } else { $entry.Text }
            $completion = if ($entry.ContainsKey('Quoted')) {
                $entry.Quoted
            } elseif ($quote) {
                $quote + $entry.Text + $quote
            } else {
                $entry.Text
            }

            New-NumfmtCompletionResult -CompletionText ($Attached + $completion) -ListItemText $display -ResultType 'ParameterValue' -ToolTip $entry.Tip
        }
    )
}

function Complete-NumfmtOperand {
    param([string]$Prefix)

    # 'numfmt [OPTION]... [NUMBER]...' reads numbers, never files; describe the slot with
    # number-shaped placeholders instead of filesystem paths.
    $numbers = @(
        @{ Text = '1000'; Tip = 'Plain number.' }
        @{ Text = '1K'; Tip = 'Number with a single-letter suffix (needs --from=si, iec or auto).' }
        @{ Text = '1Ki'; Tip = 'Number with a two-letter suffix (needs --from=iec-i or auto).' }
        @{ Text = '1M'; Tip = 'Number with a single-letter suffix (needs --from=si, iec or auto).' }
        @{ Text = '<number>'; Tip = 'Number to reformat; standard input is read when none is given.' }
    )

    @(
        foreach ($entry in $numbers) {
            if ($entry.Text.StartsWith($Prefix, [System.StringComparison]::Ordinal)) {
                New-NumfmtCompletionResult -CompletionText $entry.Text -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-NumfmtOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'NumfmtCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for numfmt.'
}

function Complete-Numfmt {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $commandText = $commandAst.ToString()
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-NumfmtCurrentToken -Line $commandText -CursorPosition $relativeCursor -Fallback $wordToComplete
    }

    $lineTokens = @(Get-NumfmtLineTokens -Line $commandText -CursorPosition $relativeCursor | Select-Object -Skip 1)
    $tokensBeforeCurrent = @(if ([string]::IsNullOrEmpty($currentWord)) {
        $lineTokens
    } else {
        $lineTokens | Select-Object -First ([Math]::Max(0, $lineTokens.Count - 1))
    })

    # Attached form: '--to=s', '--header=' (the only spelling --header takes a value in).
    if ($currentWord -match '^(?<option>--[A-Za-z][A-Za-z0-9-]*|-d)=(?<value>.*)$') {
        $option = Resolve-NumfmtValueOption -Token $Matches['option']
        return Get-NumfmtValueCompletions -Option $option -Prefix $Matches['value'] -Attached ($Matches['option'] + '=')
    }

    # Separate form: the previous token is a value-taking option ('--from a' -> auto).
    if ($tokensBeforeCurrent.Count -gt 0 -and -not ($currentWord -match '^-[A-Za-z]|^--')) {
        $previous = $tokensBeforeCurrent[-1]
        $option = Resolve-NumfmtValueOption -Token $previous
        if ($option -cne '--header' -and ($previous -ceq $option -or $previous -ceq '-d') -and (Get-NumfmtValueTable).ContainsKey($option)) {
            return Get-NumfmtValueCompletions -Option $option -Prefix $currentWord
        }
    }

    if ($currentWord -match '^-[A-Za-z]|^--|^-$') {
        return @(
            foreach ($option in Get-NumfmtCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-NumfmtCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-NumfmtOptionDescription -Option $option)
                }
            }
        )
    }

    Complete-NumfmtOperand -Prefix $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'numfmt', 'numfmt.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Numfmt -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
