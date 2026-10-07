# sha384sum tab completion for PowerShell
# Static option completion for sha384sum.exe and sha384sum.

Set-StrictMode -Version 2.0

function Get-Sha384sumCompletionOptions {
    $cache = Get-Variable -Name 'Sha384sumCompletionOptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value) {
        return $cache.Value
    }

    $fallbackOptions = @('-b', '--binary', '-c', '--check', '-w', '--warn', '--status', '--quiet', '--strict', '--ignore-missing', '--tag', '-t', '--text', '-z', '--zero', '-h', '--help', '-V', '--version')
    $commandCandidates = @('sha384sum.exe', 'sha384sum')
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
            Set-Variable -Name 'Sha384sumCompletionOptions' -Value (@($options | Sort-Object)) -Scope Script
            Set-Variable -Name 'Sha384sumCompletionDescriptions' -Value $descriptions -Scope Script
            return (Get-Variable -Name 'Sha384sumCompletionOptions' -Scope Script).Value
        }
    }

    Set-Variable -Name 'Sha384sumCompletionOptions' -Value $fallbackOptions -Scope Script
    return (Get-Variable -Name 'Sha384sumCompletionOptions' -Scope Script).Value
}

function New-Sha384sumCompletionResult {
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

function ConvertFrom-Sha384sumTypedWord {
    # Splits the word typed so far into its value and the opening quote the user
    # typed ('' when bare), undoing that quote style's escapes.
    param([string]$Text)

    $quote = ''
    if ($Text.StartsWith("'") -or $Text.StartsWith('"')) {
        $quote = $Text.Substring(0, 1)
        $Text = $Text.Substring(1)
        if ($Text.EndsWith($quote)) {
            $Text = $Text.Substring(0, $Text.Length - 1)
        }

        $Text = if ($quote -eq "'") { $Text.Replace("''", "'") } else { $Text -replace '`(.)', '$1' }
    }

    [pscustomobject]@{ Value = $Text; Quote = $quote }
}

function Test-Sha384sumArgumentNeedsQuote {
    # Whitespace and argument-mode metacharacters (including the typographic
    # quotes PowerShell treats as quotes) end or split a bare word; a leading
    # '@' or '#' would start a splat or a comment.
    param([string]$Value)

    $Value -match '[\s{}();,|&<>''"`$\u2018-\u201E]' -or $Value -match '^[@#]'
}

function ConvertTo-Sha384sumArgument {
    # Renders a value as one PowerShell argument: bare when safe and no quote was
    # typed, otherwise in the typed quote style (single by default).
    param(
        [string]$Value,
        [string]$Quote
    )

    if (-not $Quote) {
        if (-not (Test-Sha384sumArgumentNeedsQuote -Value $Value)) {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -eq "'") {
        return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
    }

    '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
}

function Get-Sha384sumCurrentWord {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$Fallback
    )

    # The parser keeps an unterminated quoted word as one element running past the cursor, so
    # the element under the cursor is the whole word even when it holds spaces.
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $element.Extent.EndOffset) {
            return $element.Extent.Text.Substring(0, $CursorPosition - $element.Extent.StartOffset)
        }
    }

    # Between words, where PowerShell's own word is empty too.
    $Fallback
}

function Get-Sha384sumPathCompletions {
    param([string]$InputPath)

    $typed = ConvertFrom-Sha384sumTypedWord -Text $InputPath
    $cleanInput = $typed.Value

    # Bare names are emitted only when the user typed no directory part. A lone '.', '~' or a
    # trailing '..' segment names a directory itself; any other trailing segment, '.' included,
    # is a name prefix, so '.\.' lists the dotfiles here. The text is split by hand because
    # Split-Path resolves '.' and '..' segments to real folder names.
    $bareNames = $false
    $separator = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
        $bareNames = $true
    } elseif ($cleanInput -match '(?:^|[\\/])\.\.$' -or $cleanInput -in @('.', '~')) {
        $parent = $cleanInput
        $leaf = ''
    } elseif ($separator -lt 0) {
        $parent = '.'
        $leaf = $cleanInput
        $bareNames = $true
    } else {
        $parent = $cleanInput.Substring(0, $separator + 1)
        $leaf = $cleanInput.Substring($separator + 1)
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        return @()
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name

    foreach ($item in $items) {
        $pathText = if ($bareNames) {
            $item.Name
        } else {
            Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $pathText += [System.IO.Path]::DirectorySeparatorChar
        }

        # PowerShell expands a leading '~' in a bare native argument but not inside quotes.
        $argumentText = $pathText
        if (($typed.Quote -or (Test-Sha384sumArgumentNeedsQuote -Value $pathText)) -and $pathText -match '^~[\\/]') {
            $argumentText = $HOME + $pathText.Substring(1)
        }

        $quotedPath = ConvertTo-Sha384sumArgument -Value $argumentText -Quote $typed.Quote
        if ($item.PSIsContainer) {
            New-Sha384sumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
        } else {
            New-Sha384sumCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderItem' -ToolTip $item.FullName
        }
    }
}

function Get-Sha384sumOptionDescription {
    param([string]$Option)

    $cache = Get-Variable -Name 'Sha384sumCompletionDescriptions' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.ContainsKey($Option)) {
        return $cache.Value[$Option]
    }

    'Option for sha384sum.'
}

function Complete-Sha384sum {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = Get-Sha384sumCurrentWord -CommandAst $commandAst -CursorPosition $cursorPosition -Fallback $wordToComplete

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-Sha384sumCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::Ordinal)) {
                    New-Sha384sumCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip (Get-Sha384sumOptionDescription -Option $option)
                }
            }
        )
    }

    Get-Sha384sumPathCompletions -InputPath $currentWord
}

Register-ArgumentCompleter -Native -CommandName 'sha384sum', 'sha384sum.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Sha384sum -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
