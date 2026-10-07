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

function Get-OhMyPoshPathCompletions {
    param(
        [string]$Prefix,
        [string]$Attached
    )

    $results = @()
    $themeRoot = $env:POSH_THEMES_PATH
    if ($themeRoot -and $Prefix -notmatch '[\\/]' -and (Test-Path -LiteralPath $themeRoot)) {
        foreach ($theme in (Get-ChildItem -LiteralPath $themeRoot -File -Filter '*.omp.*' -ErrorAction SilentlyContinue | Sort-Object -Property Name)) {
            if ($theme.Name.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $text = if ($theme.FullName -match '\s') { '"' + $theme.FullName + '"' } else { $theme.FullName }
                $results += [System.Management.Automation.CompletionResult]::new($Attached + $text, $theme.Name, 'ProviderItem', $theme.FullName)
            }
        }
    }

    if ([string]::IsNullOrEmpty($Prefix) -or $Prefix -match '[\\/]$') {
        $parent = if ($Prefix) { $Prefix } else { '.' }
        $leaf = ''
    } else {
        $parent = Split-Path -Path $Prefix -Parent
        if ([string]::IsNullOrEmpty($parent)) {
            $parent = '.'
        }
        $leaf = Split-Path -Path $Prefix -Leaf
    }

    foreach ($item in (Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') } | Sort-Object -Property Name)) {
        $text = if ($parent -eq '.') { $item.Name } else { Join-Path -Path $parent -ChildPath $item.Name }
        if ($item.PSIsContainer) {
            $text += '\'
        }
        if ($text -match '\s') {
            $text = '"' + $text + '"'
        }
        $type = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ProviderItem' }
        $results += [System.Management.Automation.CompletionResult]::new($Attached + $text, $item.Name, $type, $item.FullName)
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

    $valueFlag = $null
    $valuePrefix = $wordToComplete
    $attached = ''
    if ($wordToComplete -match '^(?<flag>--?[A-Za-z0-9-]+)=(?<value>.*)$') {
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
            return @(Get-OhMyPoshPathCompletions -Prefix $valuePrefix -Attached $attached)
        }

        $values = switch ($valueFlag.Long) {
            '--shell' { (Get-OhMyPoshHelp -CommandPath @('init')).Positionals }
            default { @() }
        }

        return @(
            foreach ($value in $values) {
                if ($value.StartsWith($valuePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [System.Management.Automation.CompletionResult]::new($attached + $value, $value, 'ParameterValue', $valueFlag.Tip)
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
