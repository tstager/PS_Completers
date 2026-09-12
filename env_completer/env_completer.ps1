# env tab completion for PowerShell
# Static option completion for env.exe and env.

Set-StrictMode -Version 2.0

function Get-EnvCompletionOptions {
    $cache = Get-Variable -Name 'EnvCompletionOptions' -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-i', '--ignore-environment', '-C', '--chdir', '-0', '--null', '-f', '--file', '-s', '-u', '--unset', '-v', '--debug', '-S', '--split-string', '-a', '--argv0', '--ignore-signal', '--default-signal', '--block-signal', '--list-signal-handling', '-h', '--help', '-V', '--version')
    $commandCandidates = @('env.exe', 'env')
    foreach ($candidate in $commandCandidates) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            continue
        }

        try {
            $helpOutput = $null | & $command.Source --help 2>&1 | Out-String
        } catch {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($helpOutput)) {
            continue
        }

        $options = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
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
                }
            }
        }

        if ($options.Count -gt 0) {
            Set-Variable -Name 'EnvCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
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

function Remove-EnvOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-EnvQuotedValue {
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

function Get-EnvCurrentToken {
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

function Get-EnvPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-EnvOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]+$') {
        $parent = $cleanInput
        $leaf = ''
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
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = if ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $item.Name
        } elseif ([System.IO.Path]::IsPathRooted($cleanInput)) {
            Join-Path -Path $parent -ChildPath $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-EnvQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
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
            foreach ($result in Get-EnvPathCompletions -InputPath $prefix) {
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

function Complete-Env {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-EnvCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $optionValues = @(Get-EnvOptionValueCompletions -commandAst $commandAst -CurrentWord $currentWord)
    if ($optionValues.Count -gt 0) {
        return $optionValues
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-EnvCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-EnvCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'Option for env.'
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
