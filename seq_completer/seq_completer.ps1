# seq tab completion for PowerShell
# Static option completion for seq.exe and seq.

Set-StrictMode -Version 2.0

function Get-SeqCompletionOptions {
    $cache = Get-Variable -Name 'SeqCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-s', '--separator', '-t', '--terminator', '-w', '--equal-width', '-f', '--format', '-p', '-h', '--help', '-V', '--version')
    $commandCandidates = @('seq.exe', 'seq')
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
            Set-Variable -Name 'SeqCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'SeqCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'SeqCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'SeqCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'SeqCompletionOptions' -Scope Script).Value
}


function New-SeqCompletionResult {
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

function Get-SeqLineTokens {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    # Tokens are taken from the raw command text rather than CommandElements because the
    # PowerShell parser swallows a bare ',' ('seq -s ,') and drops it from the AST.
    if ([string]::IsNullOrWhiteSpace($Line)) {
        return @()
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    @([regex]::Matches($prefix, '"[^"]*"?|''[^'']*''?|\S+') | ForEach-Object { $_.Value })
}

function Get-SeqCurrentToken {
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

    $parts = @(Get-SeqLineTokens -Line $Line -CursorPosition $CursorPosition)
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-SeqValueOptionList {
    @('-s', '--separator', '-t', '--terminator', '-f', '--format')
}

function Get-SeqOperandCount {
    param([string[]]$TokensBeforeCurrent)

    # Operands are the numbers (including negative ones such as '-5') that are neither options
    # nor the separate-form value of -s/-t/-f.
    $count = 0
    $skipNext = $false
    foreach ($token in @($TokensBeforeCurrent)) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }

        if ($token -ceq '--') {
            continue
        }

        if ($token -match '^-[A-Za-z]|^--') {
            if ($token -cin (Get-SeqValueOptionList)) {
                $skipNext = $true
            }

            continue
        }

        $count++
    }

    $count
}

function Complete-SeqOperand {
    param([int]$OperandCount)

    # 'seq [OPTION]... LAST | FIRST LAST | FIRST INCREMENT LAST': the operands are floating-point
    # numbers, so the empty slot is described by placeholders rather than filesystem paths.
    switch ($OperandCount) {
        0 { $slots = @(@{ Text = '<LAST>'; Tip = 'Count from 1 to LAST.' }, @{ Text = '<FIRST>'; Tip = 'First number, followed by LAST (or INCREMENT LAST).' }) }
        1 { $slots = @(@{ Text = '<LAST>'; Tip = 'Last number of the sequence.' }, @{ Text = '<INCREMENT>'; Tip = 'Step between numbers, followed by LAST.' }) }
        2 { $slots = @(@{ Text = '<LAST>'; Tip = 'Last number of the sequence.' }) }
        default { return @() }
    }

    @(
        foreach ($slot in $slots) {
            New-SeqCompletionResult -CompletionText $slot.Text -ListItemText $slot.Text -ResultType 'ParameterValue' -ToolTip $slot.Tip
        }
    )
}

function Get-SeqOptionValueCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $option = $null
    $prefix = $CurrentWord
    $attached = ''
    if ($CurrentWord -match '^(?<option>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = $Matches['option']
        $prefix = $Matches['value']
        $attached = $option + '='
    } elseif (-not ($CurrentWord -match '^-[A-Za-z]|^--') -and $null -ne $TokensBeforeCurrent -and $TokensBeforeCurrent.Count -gt 0) {
        $option = $TokensBeforeCurrent[-1]
    }

    if ([string]::IsNullOrEmpty($option) -or $option -cnotin (Get-SeqValueOptionList)) {
        return @()
    }

    # A quoted or half-quoted value ('";"', "' ") is matched on its bare text and re-quoted the
    # same way; entries that need PowerShell escapes carry their own quoted spelling.
    $quote = ''
    if ($prefix.Length -gt 0 -and ($prefix[0] -eq '"' -or $prefix[0] -eq "'")) {
        $quote = [string]$prefix[0]
        $prefix = $prefix.Substring(1)
        if ($prefix.EndsWith($quote)) {
            $prefix = $prefix.Substring(0, $prefix.Length - 1)
        }
    }

    $separators = @(
        @{ Text = ','; Tip = 'Comma separator.' }
        @{ Text = ';'; Tip = 'Semicolon separator.' }
        @{ Text = ':'; Tip = 'Colon separator.' }
        @{ Text = ' '; Display = '<space>'; Quoted = "' '"; Tip = 'Single space separator.' }
        @{ Text = "`t"; Display = '<tab>'; Quoted = '"`t"'; Tip = 'Tab separator (PowerShell "`t" escape).' }
        @{ Text = "`n"; Display = '<newline>'; Quoted = '"`n"'; Tip = 'Newline separator, the default.' }
        @{ Text = '<string>'; Tip = 'Custom separator string.' }
    )
    $formats = @(
        @{ Text = '%g'; Tip = 'General floating-point format, the default for non-fixed-point input.' }
        @{ Text = '%f'; Tip = 'Fixed-point format.' }
        @{ Text = '%e'; Tip = 'Scientific format.' }
        @{ Text = '%.1f'; Tip = 'One decimal place.' }
        @{ Text = '%.2f'; Tip = 'Two decimal places.' }
        @{ Text = '%03g'; Tip = 'Zero-padded to width 3.' }
        @{ Text = '%05g'; Tip = 'Zero-padded to width 5.' }
        @{ Text = '%05.2f'; Tip = 'Zero-padded to width 5 with two decimal places.' }
    )
    $values = if ($option -cin @('-f', '--format')) { $formats } else { $separators }

    @(
        foreach ($entry in $values) {
            if (-not $entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
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

            New-SeqCompletionResult -CompletionText ($attached + $completion) -ListItemText $display -ResultType 'ParameterValue' -ToolTip $entry.Tip
        }
    )
}

function Get-SeqOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'SeqCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for seq.'
}

function Complete-Seq {
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
        Get-SeqCurrentToken -Line $commandText -CursorPosition $relativeCursor -Fallback $wordToComplete
    }

    $lineTokens = @(Get-SeqLineTokens -Line $commandText -CursorPosition $relativeCursor | Select-Object -Skip 1)
    $tokensBeforeCurrent = @(if ([string]::IsNullOrEmpty($currentWord)) {
        $lineTokens
    } else {
        $lineTokens | Select-Object -First ([Math]::Max(0, $lineTokens.Count - 1))
    })

    $optionValues = @(Get-SeqOptionValueCompletions -TokensBeforeCurrent $tokensBeforeCurrent -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return Complete-SeqOperand -OperandCount (Get-SeqOperandCount -TokensBeforeCurrent $tokensBeforeCurrent)
    }

    if ($currentWord -match '^-[A-Za-z]|^--|^-$') {
        return @(
            foreach ($option in Get-SeqCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-SeqCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-SeqOptionDescription -Option $option)
                }
            }
        )
    }

    # A partially typed operand is a number; there is nothing to complete and no path slot.
    @()
}

Register-ArgumentCompleter -Native -CommandName 'seq', 'seq.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Seq -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
