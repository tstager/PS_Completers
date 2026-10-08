# jq tab completion for PowerShell
# Help-driven jq completer for jq.exe and jq.

Set-StrictMode -Version 2.0

function Get-JqCommandPath {
    foreach ($candidate in @('jq', 'jq.exe')) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction Ignore |
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

function ConvertFrom-JqTypedWord {
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

function ConvertTo-JqQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default). PowerShell reads ' and
    # U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes.
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $QuoteChar) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]' -and $Value -notmatch '^[-\u2013-\u2015]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-JqCommandTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    if ($null -eq $CommandAst) {
        return @()
    }

    # The element under the cursor is the word being completed, not a filled slot, so it is
    # left out ('jq ke' must not count 'ke' as the filter operand).
    return @(
        $CommandAst.CommandElements |
            Where-Object { $_.Extent.EndOffset -lt $CursorPosition } |
            ForEach-Object { $_.Extent.Text.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-JqCurrentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # The typed word as written: wordToComplete normalizes quotes to ASCII, closes them and
    # undoes their escapes. The whole word is read because PowerShell replaces the whole word,
    # even when the cursor is inside it. An unterminated quoted word is one element.
    foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text
        }
    }

    ''
}

function Get-JqPathCompletions {
    param(
        [string]$InputPath,
        [switch]$DirectoriesOnly
    )

    $cleanInput = ConvertFrom-JqTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # The directory part is kept exactly as typed (.\, ./, ..\ included) and the leaf filters.
    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    $directoryText = $cleanInput.Substring(0, $separatorIndex + 1)
    $leaf = $cleanInput.Substring($separatorIndex + 1)
    $parent = if ($directoryText) { $directoryText } else { '.' }

    if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') -and (-not $DirectoriesOnly -or $_.PSIsContainer) } | Sort-Object -Property Name

    foreach ($item in $items) {
        # A bare name starting with a dash would parse as a parameter, so it gets the
        # current-directory prefix, as PowerShell's own file completion does.
        $pathText = if (-not $directoryText -and $item.Name -match '^[-\u2013-\u2015]') {
            '.' + [System.IO.Path]::DirectorySeparatorChar + $item.Name
        } else {
            $directoryText + $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        $quotedPath = ConvertTo-JqQuotedValue -Value $pathText -QuoteChar $quoteChar
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
    $tokens = @(Get-JqCommandTokens -CommandAst $commandAst -CursorPosition $cursorPosition)
    $typedWord = Get-JqCurrentToken -CommandAst $commandAst -CursorPosition $cursorPosition

    # A slot is a placeholder, 'path', 'dir' (-L takes a module directory) or an array of the
    # literal values it accepts (--indent n, max 7).
    $arity = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $arity['--arg'] = @('<name>', '<value>')
    $arity['--argjson'] = @('<name>', '<json>')
    $arity['--rawfile'] = @('<name>', 'path')
    $arity['--slurpfile'] = @('<name>', 'path')
    $arity['-L'] = @('dir')
    $arity['--library-path'] = @('dir')
    $arity['--indent'] = @(, @('0', '1', '2', '3', '4', '5', '6', '7'))

    $pending = @()
    $operands = 0
    $fromFile = $false
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
            # -f/--from-file takes no value: it makes the first operand the program file, and
            # it also counts inside a short-flag bundle (-rf). '-Lf' is -L with the attached dir 'f'.
            if ($token -ceq '--from-file' -or ($token -cmatch '^-[A-Za-z]+$' -and -not $token.StartsWith('-L', [System.StringComparison]::Ordinal) -and $token.Contains('f'))) {
                $fromFile = $true
            }

            continue
        }

        $operands++
    }

    if ($pending.Count -gt 0) {
        $kind = $pending[0]
        if ($kind -is [array]) {
            return @(
                foreach ($value in $kind) {
                    if ($value.StartsWith($currentToken, [System.StringComparison]::Ordinal)) {
                        New-JqCompletionResult -CompletionText $value -ListItemText $value -ResultType 'ParameterValue' -ToolTip 'Spaces of indentation (max 7).'
                    }
                }
            )
        }

        if ($kind -eq 'path') {
            return Get-JqPathCompletions -InputPath $typedWord
        }

        if ($kind -eq 'dir') {
            return Get-JqPathCompletions -InputPath $typedWord -DirectoriesOnly
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

    if ($operands -eq 0 -and -not $fromFile) {
        $starters = @('.', '.[]', 'keys', 'keys_unsorted', 'length', 'type', 'to_entries', 'from_entries', 'with_entries(', 'map(', 'select(', 'add', 'sort_by(', 'group_by(', 'unique', 'has(', 'del(', 'paths', 'tostring', 'tonumber', 'split(', 'join(', 'test(')
        return @(
            foreach ($starter in $starters) {
                if ($starter.StartsWith($currentToken, [System.StringComparison]::Ordinal)) {
                    New-JqCompletionResult -CompletionText $starter -ListItemText $starter -ResultType 'ParameterValue' -ToolTip 'jq filter'
                }
            }
        )
    }

    Get-JqPathCompletions -InputPath $typedWord
}

Register-ArgumentCompleter -Native -CommandName 'jq', 'jq.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Jq -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
