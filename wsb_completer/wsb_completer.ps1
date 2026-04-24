<#
.SYNOPSIS
    Registers a native PowerShell argument completer for wsb.

.DESCRIPTION
    Provides a static-first native completer for `wsb` and `wsb.exe`.

    The completer covers:
    - top-level commands and aliases
    - command-specific options
    - inline `--option=value` completion for selected option kinds
    - safe local discovery of running sandbox IDs via `wsb list --raw`
    - local directory completion for `--host-path`
    - placeholder-driven completion for free-form config, command, and sandbox-path slots

    The script keeps its top level compatible with `Import-CompleterScript`.
#>

Set-StrictMode -Version Latest

function New-WsbCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $ListItemText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function New-WsbOptionSpec {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [string]$ValueKind,
        [string]$CompletionText
    )

    foreach ($token in @($Tokens)) {
        [pscustomobject]@{
            Token          = $token
            Description    = $Description
            ValueKind      = $ValueKind
            CompletionText = if ([string]::IsNullOrWhiteSpace($CompletionText)) { $token } else { $CompletionText }
        }
    }
}

function New-WsbCommandSpec {
    param(
        [string[]]$Names,
        [string]$Description,
        [object[]]$Options
    )

    [pscustomobject]@{
        Names       = @($Names)
        Canonical   = $Names[0]
        Description = $Description
        Options     = @($Options)
    }
}

function Get-WsbMetadata {
    if (Get-Variable -Name WsbMetadata -Scope Script -ErrorAction SilentlyContinue) {
        return $script:WsbMetadata
    }

    $globalOptions = @(
        New-WsbOptionSpec -Tokens @('--raw') -Description 'Format output as JSON.'
        New-WsbOptionSpec -Tokens @('-?', '-h', '--help') -Description 'Show help.'
        New-WsbOptionSpec -Tokens @('--version') -Description 'Show version information.'
    )

    $commands = @(
        New-WsbCommandSpec -Names @('StartSandbox', 'start') -Description 'Start an instance of Windows Sandbox.' -Options @(
            New-WsbOptionSpec -Tokens @('--id') -Description 'ID of the Windows Sandbox environment.' -ValueKind 'SandboxId'
            New-WsbOptionSpec -Tokens @('-c', '--config') -Description 'Formatted config string used to create the Windows Sandbox environment.' -ValueKind 'ConfigString'
            $globalOptions
        )
        New-WsbCommandSpec -Names @('ListRunningSandboxes', 'list') -Description 'List the IDs of all running Windows Sandbox environments.' -Options @(
            $globalOptions
        )
        New-WsbCommandSpec -Names @('Execute', 'exec') -Description 'Execute a command in the running Windows Sandbox environment.' -Options @(
            New-WsbOptionSpec -Tokens @('--id') -Description 'ID of the Windows Sandbox environment.' -ValueKind 'SandboxId'
            New-WsbOptionSpec -Tokens @('-c', '--command') -Description 'The command to execute within Windows Sandbox.' -ValueKind 'CommandString'
            New-WsbOptionSpec -Tokens @('-d', '--working-directory') -Description 'Directory inside Windows Sandbox to execute the command in.' -ValueKind 'SandboxPath'
            New-WsbOptionSpec -Tokens @('-r', '--run-as') -Description 'User context to run the command as.' -ValueKind 'RunAs'
            $globalOptions
        )
        New-WsbCommandSpec -Names @('ShareFolder', 'share') -Description 'Share a host folder into the Windows Sandbox session.' -Options @(
            New-WsbOptionSpec -Tokens @('--id') -Description 'ID of the Windows Sandbox environment.' -ValueKind 'SandboxId'
            New-WsbOptionSpec -Tokens @('-f', '--host-path') -Description 'Host folder path to share.' -ValueKind 'HostDirectoryPath'
            New-WsbOptionSpec -Tokens @('-s', '--sandbox-path') -Description 'Destination path inside Windows Sandbox.' -ValueKind 'SandboxPath'
            New-WsbOptionSpec -Tokens @('-w', '--allow-write') -Description 'Allow writes from the sandbox to the shared host folder.'
            $globalOptions
        )
        New-WsbCommandSpec -Names @('StopSandbox', 'stop') -Description 'Terminate a running Windows Sandbox.' -Options @(
            New-WsbOptionSpec -Tokens @('--id') -Description 'ID of the Windows Sandbox environment.' -ValueKind 'SandboxId'
            $globalOptions
        )
        New-WsbCommandSpec -Names @('ConnectToSandbox', 'connect') -Description 'Start a remote session for a Windows Sandbox environment.' -Options @(
            New-WsbOptionSpec -Tokens @('--id') -Description 'ID of the Windows Sandbox environment.' -ValueKind 'SandboxId'
            $globalOptions
        )
        New-WsbCommandSpec -Names @('GetIpAddress', 'ip') -Description 'Get the IP address of the Windows Sandbox environment.' -Options @(
            New-WsbOptionSpec -Tokens @('--id') -Description 'ID of the Windows Sandbox environment.' -ValueKind 'SandboxId'
            $globalOptions
        )
    )

    $commandLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $commandSuggestions = New-Object System.Collections.Generic.List[object]
    foreach ($command in $commands) {
        foreach ($name in $command.Names) {
            $commandLookup[$name] = $command
            [void]$commandSuggestions.Add([pscustomobject]@{ CompletionText = $name; ToolTip = $command.Description })
        }
    }

    $script:WsbMetadata = [pscustomobject]@{
        GlobalOptions       = @($globalOptions)
        Commands            = @($commands)
        CommandLookup       = $commandLookup
        CommandSuggestions  = @($commandSuggestions.ToArray())
        RunAsValues         = @('ExistingLogin', 'System')
    }

    $script:WsbMetadata
}

function Get-WsbTokenState {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    if ($null -eq $Line) {
        $Line = ''
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    $tokens = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    $quoteChar = [char]0

    foreach ($character in $prefix.ToCharArray()) {
        if (($character -eq [char]34) -or ($character -eq [char]39)) {
            if ($quoteChar -eq [char]0) {
                $quoteChar = $character
            } elseif ($quoteChar -eq $character) {
                $quoteChar = [char]0
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and $quoteChar -eq [char]0) {
            if ($builder.Length -gt 0) {
                $tokens.Add($builder.ToString())
                [void]$builder.Clear()
            }

            continue
        }

        [void]$builder.Append($character)
    }

    $hasTrailingSpace = $prefix -match '\s$'
    if ($builder.Length -gt 0) {
        $tokens.Add($builder.ToString())
    }

    if ($hasTrailingSpace) {
        return [pscustomobject]@{ TokensBeforeCurrent = @($tokens); CurrentToken = '' }
    }

    if ($tokens.Count -gt 0) {
        return [pscustomobject]@{ TokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1)); CurrentToken = $tokens[$tokens.Count - 1] }
    }

    [pscustomobject]@{ TokensBeforeCurrent = @(); CurrentToken = '' }
}

function Get-WsbArgumentsFromTokenState {
    param([pscustomobject]$TokenState)

    $tokensBeforeCurrent = @($TokenState.TokensBeforeCurrent)
    $currentArgument = if ($null -eq $TokenState.CurrentToken) { '' } else { $TokenState.CurrentToken }

    if ($tokensBeforeCurrent.Count -gt 0) {
        $argumentsBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip 1)
    } else {
        $argumentsBeforeCurrent = @()
    }

    if ($tokensBeforeCurrent.Count -eq 0 -and $currentArgument -match '^(?i)wsb(?:\.exe)?$') {
        $currentArgument = ''
    }

    [pscustomobject]@{
        ArgumentsBeforeCurrent = $argumentsBeforeCurrent
        CurrentArgument        = $currentArgument
    }
}

function Get-WsbRunningSandboxIds {
    if (Get-Variable -Name WsbSandboxIdCache -Scope Script -ErrorAction SilentlyContinue) {
        $cache = $script:WsbSandboxIdCache
        if (((Get-Date) - $cache.UpdatedAt).TotalSeconds -lt 10) {
            return $cache.Values
        }
    }

    $values = @()
    if (Get-Command -Name wsb.exe -ErrorAction SilentlyContinue) {
        try {
            $jsonText = (& wsb.exe list --raw 2>$null | Out-String)
            if (-not [string]::IsNullOrWhiteSpace($jsonText)) {
                $parsed = $jsonText | ConvertFrom-Json -ErrorAction Stop
                if ($parsed.WindowsSandboxEnvironments) {
                    foreach ($entry in @($parsed.WindowsSandboxEnvironments)) {
                        if ($entry.Id) {
                            $values += [string]$entry.Id
                        }
                    }
                }
            }
        } catch {
            $values = @()
        }
    }

    $values = @($values | Sort-Object -Unique)
    $script:WsbSandboxIdCache = [pscustomobject]@{ UpdatedAt = Get-Date; Values = $values }
    @($values)
}

function Remove-WsbOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and (($Value.StartsWith('"') -and $Value.EndsWith('"')) -or ($Value.StartsWith("'") -and $Value.EndsWith("'")))) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"', "'")
}

function ConvertTo-WsbQuotedValue {
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

function Get-WsbOptionLookup {
    param([object[]]$Options)

    $lookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($option in @($Options)) {
        $lookup[$option.Token] = $option
    }

    $lookup
}

function Get-WsbActiveCommand {
    param([string[]]$ArgumentsBeforeCurrent)

    $metadata = Get-WsbMetadata
    foreach ($token in @($ArgumentsBeforeCurrent)) {
        if ($token.StartsWith('-')) {
            continue
        }

        if ($metadata.CommandLookup.ContainsKey($token)) {
            return $metadata.CommandLookup[$token]
        }
    }

    $null
}

function Get-WsbInlineOptionInfo {
    param(
        [string]$Token,
        [object[]]$Options
    )

    if ([string]::IsNullOrWhiteSpace($Token) -or -not $Token.StartsWith('--')) {
        return $null
    }

    $match = [regex]::Match($Token, '^(?<name>--[^=]+)=(?<value>.*)$')
    if (-not $match.Success) {
        return $null
    }

    $optionLookup = Get-WsbOptionLookup -Options $Options
    $name = $match.Groups['name'].Value
    if (-not $optionLookup.ContainsKey($name)) {
        return $null
    }

    [pscustomobject]@{
        Prefix = $name + '='
        Value  = $match.Groups['value'].Value
        Option = $optionLookup[$name]
    }
}

function Get-WsbOptionCompletions {
    param(
        [string]$CurrentWord,
        [object[]]$Options
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($option in @($Options)) {
        if (-not $seen.Add($option.Token)) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            -not $option.Token.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        New-WsbCompletionResult -CompletionText $option.CompletionText -ResultType 'ParameterName' -ToolTip $option.Description
    }
}

function Get-WsbCommandCompletions {
    param([string]$CurrentWord)

    foreach ($suggestion in (Get-WsbMetadata).CommandSuggestions) {
        if (-not [string]::IsNullOrWhiteSpace($CurrentWord) -and
            -not $suggestion.CompletionText.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        New-WsbCompletionResult -CompletionText $suggestion.CompletionText -ResultType 'ParameterValue' -ToolTip $suggestion.ToolTip
    }
}

function Get-WsbPlaceholderCompletions {
    param(
        [string]$CurrentWord,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        return @(
            New-WsbCompletionResult -CompletionText ($Prefix + $Placeholder) -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-WsbCompletionResult -CompletionText ($Prefix + $CurrentWord) -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-WsbEnumCompletions {
    param(
        [string]$CurrentWord,
        [string[]]$Values,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $typedValue = Remove-WsbOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($value in @($Values)) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $value.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-WsbCompletionResult -CompletionText ($Prefix + $value) -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { $Prefix + '<value>' } else { $Prefix + $CurrentWord }
        [void]$results.Add((New-WsbCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    @($results.ToArray())
}

function Get-WsbSandboxIdCompletions {
    param(
        [string]$CurrentWord,
        [string]$Prefix = ''
    )

    $typedValue = Remove-WsbOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($id in @(Get-WsbRunningSandboxIds)) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $id.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((New-WsbCompletionResult -CompletionText ($Prefix + $id) -ResultType 'ParameterValue' -ToolTip 'Running Windows Sandbox ID.'))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { $Prefix + '<sandbox-id>' } else { $Prefix + $CurrentWord }
        [void]$results.Add((New-WsbCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip 'Running Windows Sandbox ID.'))
    }

    @($results.ToArray())
}

function Get-WsbDirectoryPathCompletions {
    param(
        [string]$CurrentWord,
        [string]$Prefix = ''
    )

    $typedValue = Remove-WsbOuterQuotes -Value $CurrentWord
    $alwaysQuote = $CurrentWord.StartsWith('"')
    $results = New-Object System.Collections.Generic.List[object]

    $parentPath = '.'
    $leaf = ''
    if (-not [string]::IsNullOrWhiteSpace($typedValue)) {
        if ($typedValue.EndsWith('\') -or $typedValue.EndsWith('/')) {
            $parentPath = $typedValue
        } else {
            try {
                $candidateParent = Split-Path -Path $typedValue -Parent
            } catch {
                $candidateParent = ''
            }

            if ([string]::IsNullOrWhiteSpace($candidateParent)) {
                $leaf = $typedValue
            } else {
                $parentPath = $candidateParent
                try {
                    $leaf = Split-Path -Path $typedValue -Leaf
                } catch {
                    $leaf = $typedValue
                }
            }
        }
    }

    try {
        $items = @(Get-ChildItem -LiteralPath $parentPath -Directory -ErrorAction Stop)
    } catch {
        $items = @()
    }

    foreach ($item in $items) {
        if (-not [string]::IsNullOrWhiteSpace($leaf) -and
            -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidate = if ($parentPath -eq '.') { $item.Name } else { Join-Path -Path $parentPath -ChildPath $item.Name }
        if (-not ($candidate.EndsWith('\') -or $candidate.EndsWith('/'))) {
            $candidate += '\'
        }

        $completionText = ConvertTo-WsbQuotedValue -Value $candidate -AlwaysQuote $alwaysQuote
        [void]$results.Add((New-WsbCompletionResult -CompletionText ($Prefix + $completionText) -ResultType 'ParameterValue' -ToolTip $item.FullName))
    }

    if ($results.Count -eq 0) {
        $fallback = if ([string]::IsNullOrWhiteSpace($CurrentWord)) { $Prefix + '<host-path>' } else { $Prefix + $CurrentWord }
        [void]$results.Add((New-WsbCompletionResult -CompletionText $fallback -ResultType 'ParameterValue' -ToolTip 'Host directory path.'))
    }

    @($results.ToArray())
}

function Get-WsbValueCompletions {
    param(
        [string]$ValueKind,
        [string]$CurrentWord,
        [string]$Prefix = ''
    )

    switch ($ValueKind) {
        'SandboxId' {
            return @(Get-WsbSandboxIdCompletions -CurrentWord $CurrentWord -Prefix $Prefix)
        }
        'RunAs' {
            return @(Get-WsbEnumCompletions -CurrentWord $CurrentWord -Values (Get-WsbMetadata).RunAsValues -ToolTip 'User context for command execution.' -Prefix $Prefix)
        }
        'HostDirectoryPath' {
            return @(Get-WsbDirectoryPathCompletions -CurrentWord $CurrentWord -Prefix $Prefix)
        }
        'ConfigString' {
            return @(Get-WsbPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '<config>' -ToolTip 'Formatted Windows Sandbox config string.' -Prefix $Prefix)
        }
        'CommandString' {
            return @(Get-WsbPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '<command>' -ToolTip 'Command to execute inside Windows Sandbox.' -Prefix $Prefix)
        }
        'SandboxPath' {
            return @(Get-WsbPlaceholderCompletions -CurrentWord $CurrentWord -Placeholder '<sandbox-path>' -ToolTip 'Path inside Windows Sandbox.' -Prefix $Prefix)
        }
    }

    @()
}

function Get-WsbTerminalCompletions {
    param([string]$CurrentWord)

    $completionText = if ([string]::IsNullOrEmpty($CurrentWord)) { ' ' } else { $CurrentWord }
    @(
        New-WsbCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip 'No further arguments are valid after help.'
    )
}

function Complete-Wsb {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $metadata = Get-WsbMetadata
    $tokenState = Get-WsbTokenState -Line $commandAst.ToString() -CursorPosition $cursorPosition
    $argumentState = Get-WsbArgumentsFromTokenState -TokenState $tokenState
    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)

    if ($hasTrailingSpace -and -not [string]::IsNullOrEmpty($argumentState.CurrentArgument)) {
        $currentWord = ''
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent + $argumentState.CurrentArgument)
    } else {
        $currentWord = if ($null -eq $argumentState.CurrentArgument) { '' } else { $argumentState.CurrentArgument }
        $argumentsBeforeCurrent = @($argumentState.ArgumentsBeforeCurrent)
    }

    $activeCommand = Get-WsbActiveCommand -ArgumentsBeforeCurrent $argumentsBeforeCurrent
    $commandIndex = -1
    if ($null -ne $activeCommand) {
        for ($i = 0; $i -lt $argumentsBeforeCurrent.Count; $i++) {
            if ($activeCommand.Names -contains $argumentsBeforeCurrent[$i]) {
                $commandIndex = $i
                break
            }
        }
    }

    $argumentsAfterCommand = @(
        if ($commandIndex -ge 0 -and $commandIndex -lt ($argumentsBeforeCurrent.Count - 1)) {
            $argumentsBeforeCurrent[($commandIndex + 1)..($argumentsBeforeCurrent.Count - 1)]
        }
    )

    $availableOptions = if ($null -ne $activeCommand) { $activeCommand.Options } else { $metadata.GlobalOptions }
    $helpRequested = ($argumentsBeforeCurrent + $currentWord) | Where-Object { $_ -in @('-?', '-h', '--help') }
    if ($helpRequested) {
        return @(Get-WsbTerminalCompletions -CurrentWord $currentWord)
    }

    $optionLookup = Get-WsbOptionLookup -Options $availableOptions

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('--')) {
        $inline = Get-WsbInlineOptionInfo -Token $currentWord -Options $availableOptions
        if ($null -ne $inline -and -not [string]::IsNullOrWhiteSpace($inline.Option.ValueKind)) {
            return @(Get-WsbValueCompletions -ValueKind $inline.Option.ValueKind -CurrentWord $inline.Value -Prefix $inline.Prefix)
        }
    }

    if ($argumentsAfterCommand.Count -gt 0) {
        $previousToken = $argumentsAfterCommand[-1]
        if ($optionLookup.ContainsKey($previousToken) -and -not [string]::IsNullOrWhiteSpace($optionLookup[$previousToken].ValueKind)) {
            return @(Get-WsbValueCompletions -ValueKind $optionLookup[$previousToken].ValueKind -CurrentWord $currentWord)
        }
    } elseif ($commandIndex -lt 0 -and $argumentsBeforeCurrent.Count -gt 0) {
        $previousToken = $argumentsBeforeCurrent[-1]
        if ($optionLookup.ContainsKey($previousToken) -and -not [string]::IsNullOrWhiteSpace($optionLookup[$previousToken].ValueKind)) {
            return @(Get-WsbValueCompletions -ValueKind $optionLookup[$previousToken].ValueKind -CurrentWord $currentWord)
        }
    }

    if ($null -eq $activeCommand) {
        $results = New-Object System.Collections.Generic.List[object]
        if ([string]::IsNullOrWhiteSpace($currentWord) -or -not $currentWord.StartsWith('-')) {
            foreach ($commandCompletion in @(Get-WsbCommandCompletions -CurrentWord $currentWord)) {
                [void]$results.Add($commandCompletion)
            }
        }

        foreach ($optionCompletion in @(Get-WsbOptionCompletions -CurrentWord $currentWord -Options $metadata.GlobalOptions)) {
            [void]$results.Add($optionCompletion)
        }

        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($result in @($results.ToArray())) {
            if ($seen.Add($result.CompletionText)) {
                $result
            }
        }

        return
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-WsbOptionCompletions -CurrentWord $currentWord -Options $availableOptions)
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-WsbOptionCompletions -CurrentWord $currentWord -Options $availableOptions)
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName @('wsb', 'wsb.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Wsb -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
