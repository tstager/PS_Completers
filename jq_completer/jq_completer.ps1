# jq tab completion for PowerShell
# Help-driven jq completer for jq.exe and jq.

Set-StrictMode -Version 2.0

function Get-JqCommandPath {
    foreach ($candidate in @('jq', 'jq.exe')) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -ne $command) {
            return $command.Source
        }
    }
}

function Get-JqHelpOutput {
    $cache = Get-Variable -Name 'JqHelpOutput' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackHelp = @(
        'Usage: jq [options] <jq filter> [file...]',
        '       jq [options] --args <jq filter> [strings...]',
        '       jq [options] --jsonargs <jq filter> [JSON_TEXTS...]',
        'Command options:',
        '  -n, --null-input',
        '  -R, --raw-input',
        '  -s, --slurp',
        '  -c, --compact-output',
        '  -r, --raw-output',
        '      --raw-output0',
        '  -j, --join-output',
        '  -a, --ascii-output',
        '  -S, --sort-keys',
        '  -C, --color-output',
        '  -M, --monochrome-output',
        '      --tab',
        '      --indent n',
        '      --unbuffered',
        '      --stream',
        '      --stream-errors',
        '      --seq',
        '  -f, --from-file',
        '  -L, --library-path dir',
        '      --arg name value',
        '      --argjson name value',
        '      --slurpfile name file',
        '      --rawfile name file',
        '      --args',
        '      --jsonargs',
        '  -e, --exit-status',
        '  -b, --binary',
        '  -V, --version',
        '      --build-configuration',
        '  -h, --help',
        '  --'
    ) -join [Environment]::NewLine

    $commandPath = Get-JqCommandPath
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        Set-Variable -Name 'JqHelpOutput' -Value $fallbackHelp -Scope Script
        return (Get-Variable -Name 'JqHelpOutput' -Scope Script).Value
    }

    try {
        $helpOutput = $null | & $commandPath --help 2>&1 | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String
    } catch {
        $helpOutput = ''
    }

    if ([string]::IsNullOrWhiteSpace($helpOutput)) {
        $helpOutput = $fallbackHelp
    }

    Set-Variable -Name 'JqHelpOutput' -Value $helpOutput -Scope Script
    return (Get-Variable -Name 'JqHelpOutput' -Scope Script).Value
}

function Get-JqCompletionOptions {
    $cache = Get-Variable -Name 'JqCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $helpOutput = Get-JqHelpOutput
    $options = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($line in ([regex]::Split($helpOutput, '\r?\n'))) {
        foreach ($match in [regex]::Matches($line, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|$))')) {
            $normalized = $match.Groups[1].Value.Trim()
            if ($normalized.StartsWith('--')) {
                $normalized = $normalized -replace '\[.*$', ''
                $normalized = $normalized -replace '=.*$', ''
            }

            if ($normalized -match '^-{1,2}[A-Za-z0-9][A-Za-z0-9-]*$') {
                [void]$options.Add($normalized)
            }
        }
    }

    $completionOptions = @($options | Sort-Object)
    Set-Variable -Name 'JqCompletionOptions' -Value $completionOptions -Scope Script
    return (Get-Variable -Name 'JqCompletionOptions' -Scope Script).Value
}

function New-JqCompletionResult {
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

function Remove-JqOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-JqQuotedValue {
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

function Get-JqCommandTokens {
    param([System.Management.Automation.Language.CommandAst]$CommandAst)

    if ($null -eq $CommandAst) {
        return @()
    }

    return @($CommandAst.CommandElements | ForEach-Object { $_.Extent.Text.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-JqPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-JqOuterQuotes -Value $InputPath
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
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-JqQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        if ($item.PSIsContainer) {
            New-JqCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-JqCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Complete-Jq {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentToken = if ($null -eq $wordToComplete) { '' } else { $wordToComplete }
    $tokens = @(Get-JqCommandTokens -CommandAst $commandAst)

    $arity = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $arity['--arg'] = @('<name>', '<value>')
    $arity['--argjson'] = @('<name>', '<json>')
    $arity['--rawfile'] = @('<name>', 'path')
    $arity['--slurpfile'] = @('<name>', 'path')
    $arity['-f'] = @('path')
    $arity['--from-file'] = @('path')
    $arity['-L'] = @('path')
    $arity['--library-path'] = @('path')
    $arity['--indent'] = @('<n>')

    $pending = @()
    $operands = 0
    foreach ($token in ($tokens | Select-Object -Skip 1)) {
        if ($pending.Count -gt 0) {
            $pending = @($pending | Select-Object -Skip 1)
            continue
        }

        if ($arity.ContainsKey($token)) {
            $pending = @($arity[$token])
            continue
        }

        if ($token.StartsWith('-') -and $token.Length -gt 1) {
            continue
        }

        $operands++
    }

    if ($pending.Count -gt 0) {
        $kind = $pending[0]
        if ($kind -eq 'path') {
            return Get-JqPathCompletions -InputPath $currentToken
        }

        if ([string]::IsNullOrWhiteSpace($currentToken)) {
            return @(
                New-JqCompletionResult -CompletionText $kind -ListItemText $kind -ResultType 'ParameterValue' -ToolTip 'jq option argument'
            )
        }

        return @()
    }

    if ($currentToken.StartsWith('-')) {
        return @(
            foreach ($option in Get-JqCompletionOptions) {
                if ($option.StartsWith($currentToken, [System.StringComparison]::Ordinal)) {
                    New-JqCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'jq option'
                }
            }
        )
    }

    if ($operands -eq 0) {
        $starters = @('.', '.[]', 'keys', 'keys_unsorted', 'length', 'type', 'to_entries', 'from_entries', 'with_entries(', 'map(', 'select(', 'add', 'sort_by(', 'group_by(', 'unique', 'has(', 'del(', 'paths', 'tostring', 'tonumber', 'split(', 'join(', 'test(')
        return @(
            foreach ($starter in $starters) {
                if ($starter.StartsWith($currentToken, [System.StringComparison]::Ordinal)) {
                    New-JqCompletionResult -CompletionText $starter -ListItemText $starter -ResultType 'ParameterValue' -ToolTip 'jq filter'
                }
            }
        )
    }

    Get-JqPathCompletions -InputPath $currentToken
}

Register-ArgumentCompleter -Native -CommandName 'jq', 'jq.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Jq -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
