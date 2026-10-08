# oh-my-posh tab completion for PowerShell
# Help-driven completer: commands, flags and positional values come from `oh-my-posh <command...> --help`, cached per command path.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name OhMyPoshCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:OhMyPoshCompletionCache = @{
        ExecutablePath   = $null
        ExecutableProbed = $false
        HelpByPath       = @{}
    }
}

function Get-OhMyPoshExecutable {
    if (-not $script:OhMyPoshCompletionCache.ExecutableProbed) {
        $script:OhMyPoshCompletionCache.ExecutableProbed = $true
        $command = Get-Command -Name 'oh-my-posh.exe', 'oh-my-posh' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
        if ($command) {
            $script:OhMyPoshCompletionCache.ExecutablePath = $command.Source
        }
    }

    $script:OhMyPoshCompletionCache.ExecutablePath
}

function Get-OhMyPoshFallbackHelp {
    param([string[]]$CommandPath)

    $help = @{ Commands = @(); Flags = @(); Positionals = @(); PositionalTips = @{} }
    if ($CommandPath.Count -eq 0) {
        foreach ($name in 'antigravity', 'auth', 'cache', 'claude', 'config', 'copilot', 'debug', 'disable', 'enable', 'font', 'get', 'help', 'init', 'notice', 'print', 'shell', 'stream', 'toggle', 'upgrade', 'version') {
            $help.Commands += @{ Text = $name; Tip = "oh-my-posh $name" }
        }
    } elseif (($CommandPath -join ' ') -eq 'init') {
        $help.Positionals = @('bash', 'zsh', 'fish', 'powershell', 'pwsh', 'cmd', 'nu', 'elvish', 'xonsh', 'yash')
    }

    $help.Flags = @(
        @{ Short = '-c'; Long = '--config'; Type = 'string'; Tip = 'config file path' }
        @{ Short = '-h'; Long = '--help'; Type = ''; Tip = 'help' }
        @{ Short = ''; Long = '--plain'; Type = ''; Tip = 'plain text output (no ANSI)' }
        @{ Short = '-s'; Long = '--shell'; Type = 'string'; Tip = 'shell' }
        @{ Short = ''; Long = '--trace'; Type = ''; Tip = 'enable tracing' }
    )

    $help
}

function Get-OhMyPoshHelp {
    param([string[]]$CommandPath)

    if ($null -eq $CommandPath) {
        $CommandPath = @()
    }

    $key = $CommandPath -join ' '
    if ($script:OhMyPoshCompletionCache.HelpByPath.ContainsKey($key)) {
        return $script:OhMyPoshCompletionCache.HelpByPath[$key]
    }

    $help = $null
    $executable = Get-OhMyPoshExecutable
    if ($executable) {
        try {
            $text = $null | & $executable @CommandPath --help 2>&1 | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String
        } catch {
            $text = ''
        }

        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $help = @{ Commands = @(); Flags = @(); Positionals = @(); PositionalTips = @{} }
            $section = ''
            $placeholder = $false
            $bullets = [ordered]@{}
            foreach ($line in ($text -split '\r?\n')) {
                if ($line -match '^- ([A-Za-z0-9_-]+): (.+)$') {
                    $bullets[$Matches[1]] = $Matches[2].Trim()
                    continue
                }

                if ($line -match '^(Usage|Available Commands|Flags|Global Flags):') {
                    $section = $Matches[1]
                    continue
                }

                if ($line -notmatch '^\s+\S') {
                    $section = ''
                    continue
                }

                switch ($section) {
                    'Usage' {
                        if ($line -match '\[([A-Za-z0-9_-]+(?:\|[A-Za-z0-9_-]+)+)\]') {
                            $help.Positionals = @($Matches[1] -split '\|')
                        } elseif ($line -match '\[(?!flags\]|command\])[A-Za-z0-9_-]+\]') {
                            $placeholder = $true
                        }
                    }
                    'Available Commands' {
                        if ($line -match '^\s+(\S+)\s+(.*)$') {
                            $help.Commands += @{ Text = $Matches[1]; Tip = $Matches[2].Trim() }
                        }
                    }
                    default {
                        if ($section -and $line -match '^\s+(?:(-[A-Za-z0-9]),\s+)?(--[A-Za-z0-9-]+)(?:\s+(string|strings|int|float|bool|duration))?\s+(.*)$') {
                            $help.Flags += @{ Short = [string]$Matches[1]; Long = $Matches[2]; Type = [string]$Matches[3]; Tip = $Matches[4].Trim() }
                        }
                    }
                }
            }

            # A single [placeholder] (auth [service]) documents its values as '- name: description' bullets.
            if ($placeholder -and $help.Positionals.Count -eq 0 -and $bullets.Count -gt 0) {
                $help.Positionals = @($bullets.Keys)
                $help.PositionalTips = @{} + $bullets
            }
        }
    }

    if ($null -eq $help) {
        $help = Get-OhMyPoshFallbackHelp -CommandPath $CommandPath
    }

    $script:OhMyPoshCompletionCache.HelpByPath[$key] = $help
    $help
}

function Get-OhMyPoshFlag {
    param(
        [hashtable]$Help,
        [string]$Token
    )

    foreach ($flag in $Help.Flags) {
        if ($flag.Long -eq $Token -or (-not [string]::IsNullOrEmpty($flag.Short) -and $flag.Short -eq $Token)) {
            return $flag
        }
    }

    $null
}

function ConvertFrom-OhMyPoshTypedWord {
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

function ConvertTo-OhMyPoshQuotedValue {
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
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-OhMyPoshCurrentWord {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # PowerShell hands a quoted word over re-quoted and drops the quote inside an attached
    # "--config='a", so the word is the whole element under the cursor as typed (the span PowerShell replaces).
    foreach ($element in ($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $extent.EndOffset) {
            return $extent.Text
        }
    }

    ''
}

function Get-OhMyPoshPathCompletions {
    param(
        [string]$TypedPrefix,
        [string]$Attached
    )

    # --config='a b.txt' parses as one constant argument, so an attached value is quoted after the '='.
    $Prefix = ConvertFrom-OhMyPoshTypedWord -Value $TypedPrefix
    $quoteChar = if ($TypedPrefix -match '^[''"\u2018-\u201E]') { $TypedPrefix.Substring(0, 1) } else { '' }

    $results = @()
    $themeRoot = $env:POSH_THEMES_PATH
    if ($themeRoot -and $Prefix -notmatch '[\\/]' -and (Test-Path -LiteralPath $themeRoot)) {
        foreach ($theme in (Get-ChildItem -LiteralPath $themeRoot -File -Filter '*.omp.*' -ErrorAction Ignore | Sort-Object -Property Name)) {
            if ($theme.Name.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $text = ConvertTo-OhMyPoshQuotedValue -Value $theme.FullName -QuoteChar $quoteChar
                $results += [System.Management.Automation.CompletionResult]::new($Attached + $text, $theme.Name, 'ProviderItem', $theme.FullName)
            }
        }
    }

    # The typed directory part is kept verbatim, so a typed .\ or ./ and its separator style survive.
    $directory = $Prefix.Substring(0, $Prefix.LastIndexOfAny([char[]]'\/') + 1)
    $leaf = $Prefix.Substring($directory.Length)
    $parent = if ($directory) { $directory } else { '.' }
    $separator = if ($directory.EndsWith('/')) { '/' } else { '\' }

    foreach ($item in (Get-ChildItem -LiteralPath $parent -ErrorAction Ignore | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name)) {
        $text = $directory + $item.Name
        # A whole word starting with a dash parses as a parameter, so it gets PowerShell's own .\ prefix.
        if (-not $directory -and -not $Attached -and $text -match '^[-\u2013-\u2015]') {
            $text = '.' + [System.IO.Path]::DirectorySeparatorChar + $text
        }
        if ($item.PSIsContainer) {
            $text += $separator
        }
        $quoted = ConvertTo-OhMyPoshQuotedValue -Value $text -QuoteChar $quoteChar
        $type = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ProviderItem' }
        $results += [System.Management.Automation.CompletionResult]::new($Attached + $quoted, $item.Name, $type, $item.FullName)
    }

    $results
}

function Complete-OhMyPosh {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if ($null -eq $wordToComplete) {
        $wordToComplete = ''
    }

    $tokens = @()
    foreach ($element in ($commandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.EndOffset -lt $cursorPosition) {
            $tokens += $element.Extent.Text
        }
    }

    $commandPath = @()
    $pendingFlag = $null
    $operandCount = 0
    $help = Get-OhMyPoshHelp -CommandPath @()
    foreach ($token in $tokens) {
        if ($null -ne $pendingFlag) {
            $pendingFlag = $null
            continue
        }

        if ($token.StartsWith('-')) {
            if ($token -match '=') {
                continue
            }
            $flag = Get-OhMyPoshFlag -Help $help -Token $token
            # An option this command does not list may take a value, so its slot stays a value slot.
            if (-not $flag) {
                $pendingFlag = @{ Long = $token; Short = ''; Type = 'unknown'; Tip = '' }
            } elseif (-not [string]::IsNullOrEmpty($flag.Type)) {
                $pendingFlag = $flag
            }
            continue
        }

        if ($operandCount -eq 0 -and @($help.Commands | Where-Object { $_.Text -eq $token }).Count -gt 0) {
            $commandPath += $token
            $help = Get-OhMyPoshHelp -CommandPath $commandPath
        } else {
            $operandCount++
        }
    }

    $currentWord = Get-OhMyPoshCurrentWord -CommandAst $commandAst -CursorPosition $cursorPosition
    $valueFlag = $null
    $valuePrefix = $currentWord
    $attached = ''
    if ($currentWord -match '^(?<flag>--?[A-Za-z0-9-]+)=(?<value>.*)$') {
        $valueFlag = Get-OhMyPoshFlag -Help $help -Token $Matches['flag']
        $valuePrefix = $Matches['value']
        $attached = $Matches['flag'] + '='
    } elseif ($null -ne $pendingFlag) {
        $valueFlag = $pendingFlag
    }

    if ($valueFlag) {
        if ($valueFlag.Type -eq 'unknown') {
            return @()
        }

        if ($valueFlag.Long -in '--config', '--data') {
            return @(Get-OhMyPoshPathCompletions -TypedPrefix $valuePrefix -Attached $attached)
        }

        $values = switch ($valueFlag.Long) {
            '--shell' { (Get-OhMyPoshHelp -CommandPath @('init')).Positionals }
            default { @() }
        }

        # A quoted attached value (--shell='p) is matched on its text and keeps the typed quote.
        $quoteChar = if ($valuePrefix -match '^[''"\u2018-\u201E]') { $valuePrefix.Substring(0, 1) } else { '' }
        $valueText = ConvertFrom-OhMyPoshTypedWord -Value $valuePrefix
        return @(
            foreach ($value in $values) {
                if ($value.StartsWith($valueText, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [System.Management.Automation.CompletionResult]::new($attached + (ConvertTo-OhMyPoshQuotedValue -Value $value -QuoteChar $quoteChar), $value, 'ParameterValue', $valueFlag.Tip)
                }
            }
        )
    }

    $results = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $add = {
        param($text, $type, $tip)
        if ($seen.Add($text)) {
            $results.Add([System.Management.Automation.CompletionResult]::new($text, $text, $type, $tip))
        }
    }

    if ($wordToComplete.StartsWith('-')) {
        foreach ($flag in $help.Flags) {
            # Long names match case-insensitively; short flags stay ordinal so a case-distinct pair never cross-matches.
            if ($flag.Long.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                & $add $flag.Long 'ParameterName' $flag.Tip
            }
            if (-not [string]::IsNullOrEmpty($flag.Short) -and $flag.Short.StartsWith($wordToComplete, [System.StringComparison]::Ordinal)) {
                & $add $flag.Short 'ParameterName' $flag.Tip
            }
        }
        return @($results.ToArray())
    }

    # Commands and the [a|b] / [service] operand take only the first operand slot.
    if ($operandCount -gt 0) {
        return @()
    }

    foreach ($command in $help.Commands) {
        if ($command.Text.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
            & $add $command.Text 'ParameterValue' $command.Tip
        }
    }

    foreach ($value in $help.Positionals) {
        if ($value.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
            $tip = if ($help.PositionalTips.ContainsKey($value)) { $help.PositionalTips[$value] } else { "oh-my-posh " + ($commandPath -join ' ') + " " + $value }
            & $add $value 'ParameterValue' $tip
        }
    }

    @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('oh-my-posh.exe', 'oh-my-posh') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-OhMyPosh -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
