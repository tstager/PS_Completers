# expr tab completion for PowerShell
# Static option completion for expr.exe and expr.

Set-StrictMode -Version 2.0

function Get-ExprCompletionOptions {
    $cache = Get-Variable -Name 'ExprCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('--help', '--version')
    $commandCandidates = @('expr.exe', 'expr')
    foreach ($candidate in $commandCandidates) {
        $command = Get-Command -Name $candidate -ErrorAction Ignore
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
            Set-Variable -Name 'ExprCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'ExprCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'ExprCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'ExprCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'ExprCompletionOptions' -Scope Script).Value
}

function New-ExprCompletionResult {
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

function Get-ExprCurrentToken {
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function ConvertTo-ExprArgument {
    param(
        [string]$Text,
        [string]$Quote
    )

    if ([string]::IsNullOrEmpty($Quote)) {
        if ($Text -notmatch '[\s{}();,|&<>''"`$]|^[@#]') {
            return $Text
        }
        $Quote = "'"
    }

    if ($Quote -eq '"') {
        return '"' + ($Text -replace '([`"$])', '`$1') + '"'
    }

    "'" + $Text.Replace("'", "''") + "'"
}

function Get-ExprValueCompletions {
    param(
        [string]$Prefix,
        [switch]$Operator,
        [switch]$CloseParen
    )

    $quote = ''
    if ($Prefix.Length -gt 0 -and ($Prefix[0] -eq "'" -or $Prefix[0] -eq '"')) {
        $quote = [string]$Prefix[0]
        $Prefix = $Prefix.Substring(1)
        if ($Prefix.EndsWith($quote, [System.StringComparison]::Ordinal)) {
            $Prefix = $Prefix.Substring(0, $Prefix.Length - 1)
        }
    }

    $entries = if ($Operator) {
        @(
            @{ Text = '|'; Tip = 'ARG1 | ARG2: ARG1 if it is neither null nor 0, otherwise ARG2.' }
            @{ Text = '&'; Tip = 'ARG1 & ARG2: ARG1 if neither argument is null or 0, otherwise 0.' }
            @{ Text = '<'; Tip = 'ARG1 < ARG2: ARG1 is less than ARG2.' }
            @{ Text = '<='; Tip = 'ARG1 <= ARG2: ARG1 is less than or equal to ARG2.' }
            @{ Text = '='; Tip = 'ARG1 = ARG2: ARG1 is equal to ARG2.' }
            @{ Text = '!='; Tip = 'ARG1 != ARG2: ARG1 is unequal to ARG2.' }
            @{ Text = '>='; Tip = 'ARG1 >= ARG2: ARG1 is greater than or equal to ARG2.' }
            @{ Text = '>'; Tip = 'ARG1 > ARG2: ARG1 is greater than ARG2.' }
            @{ Text = '+'; Tip = 'ARG1 + ARG2: arithmetic sum of ARG1 and ARG2.' }
            @{ Text = '-'; Tip = 'ARG1 - ARG2: arithmetic difference of ARG1 and ARG2.' }
            @{ Text = '*'; Tip = 'ARG1 * ARG2: arithmetic product of ARG1 and ARG2. The Windows expr builds expand a bare * as a file wildcard, so it only works where * matches no file.' }
            @{ Text = '/'; Tip = 'ARG1 / ARG2: arithmetic quotient of ARG1 divided by ARG2.' }
            @{ Text = '%'; Tip = 'ARG1 % ARG2: arithmetic remainder of ARG1 divided by ARG2.' }
            @{ Text = ':'; Tip = 'STRING : REGEXP: anchored pattern match of REGEXP in STRING.' }
            if ($CloseParen) {
                @{ Text = ')'; Tip = '( EXPRESSION ): close the parenthesized expression.' }
            }
        )
    } else {
        @(
            @{ Text = 'match'; Tip = 'match STRING REGEX: anchored pattern match.' }
            @{ Text = 'substr'; Tip = 'substr STRING POS LENGTH: substring of STRING.' }
            @{ Text = 'index'; Tip = 'index STRING CHARS: index in STRING of any CHARS.' }
            @{ Text = 'length'; Tip = 'length STRING: length of STRING.' }
            @{ Text = '('; Tip = '( EXPRESSION ): value of EXPRESSION.' }
            @{ Text = '+'; Tip = '+ TOKEN: interpret TOKEN as a string, even if it is a keyword like match or an operator like /.' }
        )
    }

    @(
        foreach ($entry in $entries) {
            if ($entry.Text.StartsWith($Prefix, [System.StringComparison]::Ordinal)) {
                New-ExprCompletionResult -CompletionText (ConvertTo-ExprArgument -Text $entry.Text -Quote $quote) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-ExprGrammarState {
    param([string[]]$Words)

    $arity = @{
        'match'  = @('<string>', '<regexp>')
        'substr' = @('<string>', '<pos>', '<length>')
        'index'  = @('<string>', '<chars>')
        'length' = @('<string>')
    }
    $state = @{ Mode = 'Operand'; Slot = ''; SlotTip = ''; ParenOpen = $false; First = $true; Terminal = $false }
    $frames = [System.Collections.Generic.List[object]]::new()

    $start = 0
    if ($Words.Count -gt 0) {
        if ($Words[0] -ceq '--help' -or $Words[0] -ceq '--version') {
            $state.Terminal = $true
            return $state
        }
        if ($Words[0] -ceq '--') {
            $start = 1
        }
    }
    if ($Words.Count -gt 0) {
        $state.First = $false
    }

    for ($i = $start; $i -lt $Words.Count; $i++) {
        $word = $Words[$i]
        $primaryDone = $false
        switch ($state.Mode) {
            'Operand' {
                if ($arity.Keys -ccontains $word) {
                    $frames.Add(@{ Keyword = $word; Index = 0 })
                } elseif ($word -ceq '(') {
                    $frames.Add(@{ Keyword = '('; Index = 0 })
                } elseif ($word -ceq '+') {
                    $state.Mode = 'Token'
                } else {
                    $primaryDone = $true
                }
            }
            'Token' {
                $primaryDone = $true
            }
            'Operator' {
                if (@('|', '&', '<', '<=', '=', '!=', '>=', '>', '+', '-', '*', '/', '%', ':') -ccontains $word) {
                    $state.Mode = 'Operand'
                } elseif ($word -ceq ')' -and $frames.Count -gt 0 -and $frames[$frames.Count - 1].Keyword -ceq '(') {
                    $frames.RemoveAt($frames.Count - 1)
                    $primaryDone = $true
                } else {
                    $state.Terminal = $true
                    return $state
                }
            }
        }

        if ($primaryDone) {
            $state.Mode = 'Operator'
            while ($frames.Count -gt 0 -and $frames[$frames.Count - 1].Keyword -cne '(') {
                $frame = $frames[$frames.Count - 1]
                $frame.Index++
                if ($frame.Index -lt $arity[$frame.Keyword].Count) {
                    $state.Mode = 'Operand'
                    break
                }
                $frames.RemoveAt($frames.Count - 1)
            }
        }
    }

    if ($frames.Count -gt 0) {
        $top = $frames[$frames.Count - 1]
        if ($top.Keyword -ceq '(') {
            $state.ParenOpen = $true
        } elseif ($state.Mode -eq 'Operand') {
            $state.Slot = $arity[$top.Keyword][$top.Index]
            $state.SlotTip = "$($state.Slot) argument of $($top.Keyword) $(($arity[$top.Keyword] -join ' ').ToUpperInvariant() -replace '[<>]', '')."
        }
    }
    if ($state.Mode -eq 'Token') {
        $state.Slot = '<token>'
        $state.SlotTip = '+ TOKEN: TOKEN is taken as a string, even if it is a keyword or an operator.'
    }

    $state
}

function Get-ExprOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'ExprCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for expr.'
}

function Complete-Expr {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-ExprCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $priorWords = @(
        foreach ($element in @($commandAst.CommandElements | Select-Object -Skip 1)) {
            if ($element.Extent.EndOffset -ge $cursorPosition) {
                break
            }
            if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $element.Value
            } else {
                $element.Extent.Text
            }
        }
    )
    $state = Get-ExprGrammarState -Words $priorWords

    if ($state.Terminal) {
        return
    }

    if ($state.Mode -eq 'Operator') {
        return Get-ExprValueCompletions -Prefix $currentWord -Operator -CloseParen:$state.ParenOpen
    }

    if ($state.Slot) {
        if ([string]::IsNullOrEmpty($currentWord)) {
            return New-ExprCompletionResult -CompletionText $state.Slot -ListItemText $state.Slot -ResultType 'ParameterValue' -ToolTip $state.SlotTip
        }
        if ($state.Slot -ceq '<token>') {
            return
        }
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return Get-ExprValueCompletions -Prefix ''
    }

    if ($currentWord.StartsWith('-') -and $state.First) {
        return @(
            foreach ($option in Get-ExprCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-ExprCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-ExprOptionDescription -Option $option)
                }
            }
        )
    }

    Get-ExprValueCompletions -Prefix $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'expr', 'expr.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Expr -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
