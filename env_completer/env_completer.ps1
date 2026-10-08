# env tab completion for PowerShell
# Static option completion for env.exe and env.

Set-StrictMode -Version 2.0

function Get-EnvCompletionOptions {
    $cache = Get-Variable -Name 'EnvCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-i', '--ignore-environment', '-C', '--chdir', '-0', '--null', '-f', '--file', '-s', '-u', '--unset', '-v', '--debug', '-S', '--split-string', '-a', '--argv0', '--ignore-signal', '--default-signal', '--block-signal', '--list-signal-handling', '-h', '--help', '-V', '--version')
    $commandCandidates = @('env.exe', 'env')
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
            foreach ($match in [regex]::Matches($line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|=|\[|\.\.\.|$))')) {
                $rawOption = $match.Groups[1].Value
                $normalized = $rawOption.Trim()
                if ($normalized.StartsWith('--')) {
                    $normalized = $normalized -replace '\[.*$', ''
                    $normalized = $normalized -replace '=.*$', ''
                }
                if ($normalized -match '^-{1,2}[A-Za-z0-9][A-Za-z0-9-]*$') {
                    [void]$options.Add($normalized)
                if (-not $descriptions.ContainsKey($normalized)) {
                    $description = ($line -replace '^\s*(?:-{1,2}[A-Za-z0-9][A-Za-z0-9-]*(?:[=\[]\S*)?(?:\.\.\.)?[,\s]+)+', '').Trim()
                    if ($description -and $description -ne $line.Trim()) {
                        $descriptions[$normalized] = $description
                    }
                }
                }
            }
        }

        if ($options.Count -gt 0) {
            Set-Variable -Name 'EnvCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'EnvCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'EnvCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'EnvCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'EnvCompletionOptions' -Scope Script).Value
}


function New-EnvCompletionResult {
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

function ConvertFrom-EnvTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    $tokens[0].Value
}

function Get-EnvPathCompletions {
    # Attached marks a value glued to its option (--chdir=VALUE): the word starts with the option.
    param(
        [string]$InputPath,
        [switch]$Attached
    )

    $cleanInput = ConvertFrom-EnvTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # The directory part is kept exactly as typed (.\, ./, ..\, C:\...); only the leaf is completed.
    $directory = $cleanInput.Substring(0, $cleanInput.LastIndexOfAny([char[]]'\/') + 1)
    if (-not $directory -and $cleanInput -match '^[A-Za-z]:') {
        $directory = $cleanInput.Substring(0, 2)
    }

    $parent = if ($directory) { $directory } else { '.' }
    $leaf = $cleanInput.Substring($directory.Length)

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = $directory + $item.Name

        # A whole word starting with a dash would parse as a parameter: prefix the current directory.
        if (-not $directory -and -not $Attached -and $item.Name -match '^[-\u2013-\u2015]') {
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-EnvOperandText -Value $pathText -Quote $quoteChar
        if ($item.PSIsContainer) {
            New-EnvCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-EnvCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-EnvOptionValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $option = $null
    $prefix = $CurrentWord
    $attached = ''
    if ($CurrentWord -match '^(?<option>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = $Matches['option']
        $prefix = $Matches['value']
        $attached = $option + '='
    } elseif (-not $CurrentWord.StartsWith('-')) {
        $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
        if ([string]::IsNullOrEmpty($CurrentWord)) {
            if ($elements.Count -gt 1) {
                $option = $elements[-1]
            }
        } elseif ($elements.Count -gt 2 -and $elements[-1] -eq $CurrentWord) {
            $option = $elements[-2]
        }
    }

    if ([string]::IsNullOrEmpty($option)) {
        return @()
    }

    $table = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $table['-u'] = { foreach ($item in (Get-ChildItem -Path Env: | Sort-Object -Property Name)) { @{ Text = $item.Name; Tip = 'Environment variable.' } } }
    $table['--unset'] = { foreach ($item in (Get-ChildItem -Path Env: | Sort-Object -Property Name)) { @{ Text = $item.Name; Tip = 'Environment variable.' } } }
    $table['-C'] = 'path'
    $table['--chdir'] = 'path'
    $table['-S'] = @(
        @{ Text = '<string>'; Tip = 'String to split into arguments.' }
    )
    $table['--split-string'] = @(
        @{ Text = '<string>'; Tip = 'String to split into arguments.' }
    )
    $table['--block-signal'] = @(
        @{ Text = 'HUP'; Tip = 'Signal HUP.' }
        @{ Text = 'INT'; Tip = 'Signal INT.' }
        @{ Text = 'QUIT'; Tip = 'Signal QUIT.' }
        @{ Text = 'KILL'; Tip = 'Signal KILL.' }
        @{ Text = 'TERM'; Tip = 'Signal TERM.' }
        @{ Text = 'USR1'; Tip = 'Signal USR1.' }
        @{ Text = 'USR2'; Tip = 'Signal USR2.' }
        @{ Text = 'PIPE'; Tip = 'Signal PIPE.' }
        @{ Text = 'ALRM'; Tip = 'Signal ALRM.' }
        @{ Text = 'CHLD'; Tip = 'Signal CHLD.' }
    )
    $table['--default-signal'] = @(
        @{ Text = 'HUP'; Tip = 'Signal HUP.' }
        @{ Text = 'INT'; Tip = 'Signal INT.' }
        @{ Text = 'QUIT'; Tip = 'Signal QUIT.' }
        @{ Text = 'KILL'; Tip = 'Signal KILL.' }
        @{ Text = 'TERM'; Tip = 'Signal TERM.' }
        @{ Text = 'USR1'; Tip = 'Signal USR1.' }
        @{ Text = 'USR2'; Tip = 'Signal USR2.' }
        @{ Text = 'PIPE'; Tip = 'Signal PIPE.' }
        @{ Text = 'ALRM'; Tip = 'Signal ALRM.' }
        @{ Text = 'CHLD'; Tip = 'Signal CHLD.' }
    )
    $table['--ignore-signal'] = @(
        @{ Text = 'HUP'; Tip = 'Signal HUP.' }
        @{ Text = 'INT'; Tip = 'Signal INT.' }
        @{ Text = 'QUIT'; Tip = 'Signal QUIT.' }
        @{ Text = 'KILL'; Tip = 'Signal KILL.' }
        @{ Text = 'TERM'; Tip = 'Signal TERM.' }
        @{ Text = 'USR1'; Tip = 'Signal USR1.' }
        @{ Text = 'USR2'; Tip = 'Signal USR2.' }
        @{ Text = 'PIPE'; Tip = 'Signal PIPE.' }
        @{ Text = 'ALRM'; Tip = 'Signal ALRM.' }
        @{ Text = 'CHLD'; Tip = 'Signal CHLD.' }
    )
    if (-not $table.ContainsKey($option)) {
        return @()
    }

    $spec = $table[$option]
    if ($spec -is [string] -and $spec -eq 'path') {
        return @(
            foreach ($result in Get-EnvPathCompletions -InputPath $prefix -Attached:([bool]$attached)) {
                New-EnvCompletionResult -CompletionText ($attached + $result.CompletionText) -ListItemText $result.ListItemText -ResultType 'ProviderItem' -ToolTip $result.ToolTip
            }
        )
    }

    $values = if ($spec -is [scriptblock]) { @(& $spec) } else { @($spec) }
    @(
        foreach ($entry in $values) {
            if ($entry.Text.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                New-EnvCompletionResult -CompletionText ($attached + $entry.Text) -ListItemText $entry.Text -ResultType 'ParameterValue' -ToolTip $entry.Tip
            }
        }
    )
}

function Get-EnvOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'EnvCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for env.'
}

function Get-EnvCommandLineState {
    # Walks the words before the cursor the way env's getopt does ('+' ordering):
    # options until the first non-option word or '--', then an optional bare '-',
    # then NAME=VALUE assignments, and the first word without '=' is COMMAND.
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $valueShorts = @('C', 'f', 'u', 'S', 'a')
    $valueLongs = @('--chdir', '--file', '--unset', '--split-string', '--argv0')
    $phase = 'Option'
    $pendingValue = $false
    $operandSeen = $false
    $word = ''
    foreach ($element in @($commandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.StartOffset -lt $cursorPosition -and $cursorPosition -le $element.Extent.EndOffset) {
            $word = $element.Extent.Text.Substring(0, $cursorPosition - $element.Extent.StartOffset)
            break
        }

        if ($element.Extent.EndOffset -ge $cursorPosition) {
            break
        }

        $text = if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $element.Value } else { $element.Extent.Text }
        if ($pendingValue) {
            $pendingValue = $false
            continue
        }

        if ($phase -ceq 'Option') {
            if ($text -ceq '--') {
                $phase = 'Operand'
            } elseif ($text.StartsWith('--')) {
                if (-not $text.Contains('=')) {
                    $matched = @(Get-EnvCompletionOptions | Where-Object { $_.StartsWith($text, [System.StringComparison]::Ordinal) })
                    $long = if ($matched -ccontains $text) { $text } elseif ($matched.Count -eq 1) { $matched[0] } else { '' }
                    $pendingValue = $valueLongs -ccontains $long
                }
            } elseif ($text.Length -gt 1 -and $text.StartsWith('-')) {
                for ($index = 1; $index -lt $text.Length; $index++) {
                    if ($valueShorts -ccontains [string]$text[$index]) {
                        $pendingValue = $index -eq $text.Length - 1
                        break
                    }
                }
            } else {
                $operandSeen = $true
                $phase = if ($text -ceq '-' -or $text.Contains('=')) { 'Operand' } else { 'Argument' }
            }

            continue
        }

        if ($phase -ceq 'Operand') {
            $operandSeen = $true
            if (-not $text.Contains('=')) {
                $phase = 'Argument'
            }
        }
    }

    $quote = if ($word -match '^[''"\u2018-\u201E]') { $word.Substring(0, 1) } else { '' }
    $value = ConvertFrom-EnvTypedWord -Value $word

    [pscustomobject]@{
        Phase = if ($pendingValue) { 'Value' } else { $phase }
        Word = $word
        Value = $value
        Quote = $quote
        AllowDash = -not $operandSeen
        HasOperand = $operandSeen
    }
}

function ConvertTo-EnvOperandText {
    # Bare when safe and no quote was typed, otherwise in the quote the user typed (single by
    # default). PowerShell reads ' and U+2018-U+201B as single quotes and " and U+201C-U+201E
    # as double quotes.
    param(
        [string]$Value,
        [string]$Quote
    )

    if (-not $Quote) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -match '^[''\u2018-\u201B]$') {
        return $Quote + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $Quote
    }

    $Quote + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $Quote
}

function Get-EnvPathCommandList {
    # Programs env can start (.exe/.com/.bat/.cmd) on PATH, first match in PATH order
    # winning, sorted by name. Cached per PATH value with a short TTL so new installs show up.
    $cache = Get-Variable -Name 'EnvPathCommandCache' -Scope Script -ErrorAction Ignore
    $key = [string]$env:PATH
    if ($null -ne $cache -and $cache.Value.Key -ceq $key -and $cache.Value.Expires -gt [System.Environment]::TickCount64) {
        return $cache.Value.Commands
    }

    $extensions = [System.Collections.Generic.HashSet[string]]::new([string[]]@('.exe', '.com', '.bat', '.cmd'), [System.StringComparer]::OrdinalIgnoreCase)
    $options = [System.IO.EnumerationOptions]::new()
    $options.AttributesToSkip = [System.IO.FileAttributes]::None
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $commands = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $key.Split(';')) {
        $directory = [System.Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"'))
        if ([string]::IsNullOrWhiteSpace($directory) -or -not [System.IO.Directory]::Exists($directory)) {
            continue
        }

        foreach ($file in [System.IO.Directory]::EnumerateFiles($directory, '*', $options)) {
            $name = [System.IO.Path]::GetFileName($file)
            if ($extensions.Contains([System.IO.Path]::GetExtension($name)) -and $seen.Add($name)) {
                $commands.Add([pscustomobject]@{ Name = $name; Source = $file; Text = (ConvertTo-EnvOperandText -Value $name -Quote '') })
            }
        }
    }

    $sorted = @($commands | Sort-Object -Property Name)
    Set-Variable -Name 'EnvPathCommandCache' -Value @{ Key = $key; Expires = [System.Environment]::TickCount64 + 60000; Commands = $sorted } -Scope Script
    $sorted
}

function Get-EnvOperandCompletionList {
    # The operand slot: the bare '-' (implies -i), NAME= assignments from the live
    # environment (names only) and programs on PATH, with path completion as the last tier.
    param($State)

    $value = $State.Value
    if ($value.Contains('=')) {
        return @()
    }

    if ($value -match '^(?:[\\/.~]|[A-Za-z]:)' -or $value -match '[\\/]') {
        return @(Get-EnvPathCompletions -InputPath $State.Word)
    }

    $results = [System.Collections.Generic.List[object]]::new()
    if ($State.AllowDash -and '-'.StartsWith($value, [System.StringComparison]::Ordinal)) {
        $results.Add((New-EnvCompletionResult -CompletionText (ConvertTo-EnvOperandText -Value '-' -Quote $State.Quote) -ListItemText '-' -ResultType 'ParameterValue' -ToolTip 'A mere - implies -i: start with an empty environment.'))
    }

    foreach ($item in (Get-ChildItem -Path Env: | Sort-Object -Property Name)) {
        if (-not [string]::IsNullOrEmpty($item.Name) -and -not $item.Name.Contains('=') -and $item.Name.StartsWith($value, [System.StringComparison]::OrdinalIgnoreCase)) {
            $assignment = $item.Name + '='
            $results.Add((New-EnvCompletionResult -CompletionText (ConvertTo-EnvOperandText -Value $assignment -Quote $State.Quote) -ListItemText $assignment -ResultType 'ParameterValue' -ToolTip ('Set environment variable ' + $item.Name + ' for COMMAND.')))
        }
    }

    if ($value.Length -gt 0 -or $State.HasOperand) {
        foreach ($command in Get-EnvPathCommandList) {
            if ($command.Name.StartsWith($value, [System.StringComparison]::OrdinalIgnoreCase)) {
                $text = if ($State.Quote) { ConvertTo-EnvOperandText -Value $command.Name -Quote $State.Quote } else { $command.Text }
                $results.Add([System.Management.Automation.CompletionResult]::new($text, $command.Name, 'Command', $command.Source))
            }
        }
    }

    if ($results.Count -eq 0 -and $value.Length -gt 0) {
        return @(Get-EnvPathCompletions -InputPath $State.Word)
    }

    $results.ToArray()
}

function Complete-Env {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; wordToComplete re-quotes a typed quote.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    # The word is cut from the element under the cursor: wordToComplete re-quotes a typed quote.
    $state = Get-EnvCommandLineState -commandAst $commandAst -cursorPosition $cursorPosition
    $currentWord = $state.Word
    if ($state.Phase -ceq 'Argument') {
        # Words after COMMAND belong to COMMAND, not to env.
        if ([string]::IsNullOrEmpty($currentWord) -or $currentWord.StartsWith('-')) {
            return @()
        }

        return @(Get-EnvPathCompletions -InputPath $currentWord)
    }

    if ($state.Phase -ceq 'Operand') {
        return @(Get-EnvOperandCompletionList -State $state)
    }

    $optionValues = @(Get-EnvOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ($state.Phase -ceq 'Option' -and -not $currentWord.StartsWith('-')) {
        return @(Get-EnvOperandCompletionList -State $state)
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            if ($state.Phase -ceq 'Option' -and $currentWord -ceq '-') {
                New-EnvCompletionResult -CompletionText '-' -ListItemText '-' -ResultType 'ParameterValue' -ToolTip 'A mere - implies -i: start with an empty environment.'
            }

            foreach ($option in Get-EnvCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-EnvCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-EnvOptionDescription -Option $option)
                }
            }
        )
    }

    Get-EnvPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'env', 'env.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Env -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
