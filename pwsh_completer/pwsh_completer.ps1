Set-StrictMode -Version 2.0

if ($true) {
function New-PwshCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ToolTip,
        [string]$ResultType = 'ParameterValue',
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Test-PwshStartsWith {
    param(
        [string]$Candidate,
        [string]$Prefix
    )

    [string]::IsNullOrEmpty($Prefix) -or $Candidate.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function New-PwshOptionSpec {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [string]$ValueKind = ''
    )

    [pscustomobject]@{
        Tokens      = @($Tokens)
        Description = $Description
        ValueKind   = $ValueKind
    }
}

function Get-PwshOptionSpecs {
    @(
        New-PwshOptionSpec @('-Login', '-l') 'Start PowerShell as a login shell on Unix-like platforms.'
        New-PwshOptionSpec @('-File', '-f') 'Run a script file. This parameter consumes remaining arguments.' 'ScriptPath'
        New-PwshOptionSpec @('-Command', '-c') 'Execute a PowerShell command string, script block, or stdin command text.' 'CommandText'
        New-PwshOptionSpec @('-CommandWithArgs', '-cwa') 'Execute a PowerShell command and populate $args from remaining values.' 'CommandText'
        New-PwshOptionSpec @('-ConfigurationName', '-config') 'Run in a named PowerShell session configuration.' 'ConfigurationName'
        New-PwshOptionSpec @('-ConfigurationFile') 'Use a PowerShell session configuration file.' 'ConfigPath'
        New-PwshOptionSpec @('-CustomPipeName') 'Use a named pipe for debugging and cross-process communication.' 'PipeName'
        New-PwshOptionSpec @('-EncodedCommand', '-e', '-ec') 'Run a UTF-16LE Base64-encoded command string.' 'EncodedCommand'
        New-PwshOptionSpec @('-ExecutionPolicy', '-ex', '-ep') 'Set the process execution policy preference.' 'ExecutionPolicy'
        New-PwshOptionSpec @('-InputFormat', '-inp', '-if') 'Set input data format.' 'Format'
        New-PwshOptionSpec @('-Interactive', '-i') 'Start an interactive session.'
        New-PwshOptionSpec @('-MTA') 'Start PowerShell using a multi-threaded apartment on Windows.'
        New-PwshOptionSpec @('-NoExit', '-noe') 'Do not exit after running startup commands.'
        New-PwshOptionSpec @('-NoLogo', '-nol') 'Hide the startup banner.'
        New-PwshOptionSpec @('-NonInteractive', '-noni') 'Disable interactive prompts.'
        New-PwshOptionSpec @('-NoProfile', '-nop') 'Do not load PowerShell profiles.'
        New-PwshOptionSpec @('-NoProfileLoadTime') 'Hide profile load time output.'
        New-PwshOptionSpec @('-OutputFormat', '-o', '-of') 'Set output data format.' 'Format'
        New-PwshOptionSpec @('-SettingsFile', '-settings') 'Use a PowerShell settings JSON file.' 'SettingsPath'
        New-PwshOptionSpec @('-SSHServerMode', '-sshs') 'Run as an SSH subsystem process.'
        New-PwshOptionSpec @('-STA') 'Start PowerShell using a single-threaded apartment on Windows.'
        New-PwshOptionSpec @('-Version', '-v') 'Display the PowerShell version.'
        New-PwshOptionSpec @('-WindowStyle', '-w') 'Set the process window style.' 'WindowStyle'
        New-PwshOptionSpec @('-WorkingDirectory', '-wd') 'Set the initial working directory.' 'DirectoryPath'
        New-PwshOptionSpec @('-Help', '-h', '-?', '/?') 'Display pwsh command-line help.'
    )
}

function Get-PwshOptionMap {
    $map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($spec in Get-PwshOptionSpecs) {
        foreach ($token in $spec.Tokens) {
            $map[$token] = $spec
        }
    }

    $map
}

function Resolve-PwshOptionSpec {
    param([string]$Token)

    if ([string]::IsNullOrEmpty($Token)) {
        return $null
    }

    # pwsh accepts every parameter with a double dash as well (pwsh --noprofile --version).
    $lookup = if ($Token.StartsWith('--')) { $Token.Substring(1) } else { $Token }
    $optionMap = Get-PwshOptionMap
    if ($optionMap.ContainsKey($lookup)) {
        return $optionMap[$lookup]
    }

    $null
}

function Test-PwshOptionToken {
    param(
        [string]$Token,
        [string[]]$Tokens
    )

    if ([string]::IsNullOrEmpty($Token)) {
        return $false
    }

    $lookup = if ($Token.StartsWith('--')) { $Token.Substring(1) } else { $Token }
    foreach ($candidate in $Tokens) {
        if ([string]::Equals($lookup, $candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $false
}

function Remove-PwshOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function Test-PwshPathLike {
    param([string]$Value)

    $clean = Remove-PwshOuterQuotes -Value $Value
    -not [string]::IsNullOrWhiteSpace($clean) -and $clean -match '^(?:\.{1,2}[\\/]|~[\\/]|[A-Za-z]:[\\/]|\\\\|[\\/])'
}

function Get-PwshPathCompletions {
    param(
        [string]$InputPath,
        [string]$AttachedPrefix = '',
        [string]$Placeholder = '<path>',
        [string[]]$Extension = @(),
        [switch]$ContainersOnly
    )

    $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
    foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($InputPath)) {
        $isContainer = $item.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer
        if (-not $isContainer) {
            if ($ContainersOnly) {
                continue
            }

            if ($Extension.Count -gt 0) {
                $leaf = Remove-PwshOuterQuotes -Value $item.ListItemText
                $itemExtension = [System.IO.Path]::GetExtension($leaf)
                if (-not ($Extension -contains $itemExtension)) {
                    continue
                }
            }
        }

        if ([string]::IsNullOrEmpty($AttachedPrefix)) {
            $results.Add($item)
            continue
        }

        $completionText = "$AttachedPrefix$($item.CompletionText)"
        $results.Add([System.Management.Automation.CompletionResult]::new(
            $completionText,
            $item.ListItemText,
            $item.ResultType,
            $item.ToolTip
        ))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Placeholder)) {
        $completionText = if ([string]::IsNullOrEmpty($AttachedPrefix)) { $Placeholder } else { "$AttachedPrefix$Placeholder" }
        $results.Add((New-PwshCompletionResult -CompletionText $completionText -ToolTip $completionText))
    }

    $results
}

function Get-PwshArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $element.Value
            } else {
                $element.Extent.Text
            }
        }
    }
}

function Get-PwshPendingOption {
    param([string[]]$TokensBeforeCurrent)

    if (-not $TokensBeforeCurrent -or $TokensBeforeCurrent.Count -eq 0) {
        return $null
    }

    $spec = Resolve-PwshOptionSpec -Token $TokensBeforeCurrent[-1]
    if ($spec -and -not [string]::IsNullOrWhiteSpace($spec.ValueKind)) {
        return $spec
    }

    $null
}

function Get-PwshClosedValueCompletions {
    param(
        [string[]]$Values,
        [string]$CurrentWord,
        [string]$AttachedPrefix = '',
        [string]$ToolTip = ''
    )

    foreach ($value in $Values) {
        if (Test-PwshStartsWith -Candidate $value -Prefix $CurrentWord) {
            $completionText = if ([string]::IsNullOrEmpty($AttachedPrefix)) { $value } else { "$AttachedPrefix$value" }
            New-PwshCompletionResult -CompletionText $completionText -ToolTip $(if ($ToolTip) { $ToolTip } else { $value }) -ListItemText $value
        }
    }
}

function Get-PwshCommandTextCompletions {
    param(
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
    $extras = @(
        @{ Text = '-';              ToolTip = 'Read the command text from standard input.' }
        @{ Text = '& { <script> }'; ToolTip = 'Run an inline script block.' }
    )

    foreach ($extra in $extras) {
        if (Test-PwshStartsWith -Candidate $extra.Text -Prefix $CurrentWord) {
            $completionText = if ([string]::IsNullOrEmpty($AttachedPrefix)) { $extra.Text } else { "$AttachedPrefix$($extra.Text)" }
            $results.Add((New-PwshCompletionResult -CompletionText $completionText -ToolTip $extra.ToolTip -ListItemText $extra.Text))
        }
    }

    if ([string]::IsNullOrEmpty($CurrentWord)) {
        $completionText = if ([string]::IsNullOrEmpty($AttachedPrefix)) { '<command>' } else { "$AttachedPrefix<command>" }
        $results.Add((New-PwshCompletionResult -CompletionText $completionText -ToolTip 'PowerShell command text.' -ListItemText '<command>'))
        return $results
    }

    # Real command names from the session the completer runs in (in-process, no child process).
    try {
        foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteCommand($CurrentWord)) {
            if ([string]::IsNullOrEmpty($AttachedPrefix)) {
                $results.Add($item)
            } else {
                $results.Add([System.Management.Automation.CompletionResult]::new(
                    "$AttachedPrefix$($item.CompletionText)",
                    $item.ListItemText,
                    $item.ResultType,
                    $item.ToolTip
                ))
            }
        }
    } catch {
        Write-Debug "pwsh completer: CompleteCommand failed: $($_.Exception.Message)"
    }

    $results
}

function Get-PwshValueCompletions {
    param(
        [object]$Spec,
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    switch ($Spec.ValueKind) {
        'ScriptPath'      { return @(Get-PwshPathCompletions -InputPath $CurrentWord -AttachedPrefix $AttachedPrefix -Placeholder '<script.ps1>' -Extension @('.ps1')) }
        'ConfigPath'      { return @(Get-PwshPathCompletions -InputPath $CurrentWord -AttachedPrefix $AttachedPrefix -Placeholder '<configuration.pssc>' -Extension @('.pssc')) }
        'SettingsPath'    { return @(Get-PwshPathCompletions -InputPath $CurrentWord -AttachedPrefix $AttachedPrefix -Placeholder '<settings.json>' -Extension @('.json')) }
        'DirectoryPath'   { return @(Get-PwshPathCompletions -InputPath $CurrentWord -AttachedPrefix $AttachedPrefix -Placeholder '<directory>' -ContainersOnly) }
        'CommandText'     { return @(Get-PwshCommandTextCompletions -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix) }
        'ConfigurationName' { return @(Get-PwshClosedValueCompletions -Values @('PowerShell.7', 'Microsoft.PowerShell', '<configuration-name>') -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix -ToolTip 'PowerShell session configuration name.') }
        'PipeName'        { return @(Get-PwshClosedValueCompletions -Values @('pwsh-debug', 'mydebugpipe', '<pipe-name>') -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix -ToolTip 'Custom named pipe.') }
        'EncodedCommand'  { return @(Get-PwshClosedValueCompletions -Values @('<base64-encoded-command>') -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix -ToolTip 'UTF-16LE Base64-encoded command.') }
        'ExecutionPolicy' { return @(Get-PwshClosedValueCompletions -Values @('Restricted', 'AllSigned', 'RemoteSigned', 'Unrestricted', 'Bypass', 'Undefined', 'Default') -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix -ToolTip 'Execution policy value.') }
        'Format'          { return @(Get-PwshClosedValueCompletions -Values @('Text', 'XML') -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix -ToolTip 'Serialization format.') }
        'WindowStyle'     { return @(Get-PwshClosedValueCompletions -Values @('Normal', 'Minimized', 'Maximized', 'Hidden') -CurrentWord $CurrentWord -AttachedPrefix $AttachedPrefix -ToolTip 'Window style.') }
    }

    @()
}

function Get-PwshOptionCompletions {
    param([string]$CurrentWord)

    $doubleDash = -not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('--')
    foreach ($spec in Get-PwshOptionSpecs) {
        foreach ($token in $spec.Tokens) {
            $candidate = $token
            if ($doubleDash) {
                if (-not $token.StartsWith('-')) {
                    continue
                }

                $candidate = '-' + $token
            }

            if (Test-PwshStartsWith -Candidate $candidate -Prefix $CurrentWord) {
                New-PwshCompletionResult -CompletionText $candidate -ToolTip $spec.Description -ResultType 'ParameterName'
            }
        }
    }
}

function Test-PwshHasTerminalOption {
    param(
        [string[]]$TokensBeforeCurrent,
        [string[]]$TerminalOptions
    )

    $skipNext = $false
    foreach ($token in $TokensBeforeCurrent) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }

        if (Test-PwshOptionToken -Token $token -Tokens $TerminalOptions) {
            return $true
        }

        $spec = Resolve-PwshOptionSpec -Token $token
        if ($spec -and -not [string]::IsNullOrWhiteSpace($spec.ValueKind)) {
            $skipNext = $true
        }
    }

    $false
}

function Get-PwshParameterValueContext {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # 'pwsh -ExecutionPolicy:By' parses into a CommandParameterAst; the engine then hands the
    # completer only the value ('By'), so the option name must be recovered from the AST.
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
            continue
        }

        if ($null -eq $element.Argument) {
            continue
        }

        if ($element.Extent.StartOffset -le $CursorPosition -and $CursorPosition -le $element.Extent.EndOffset) {
            $spec = Resolve-PwshOptionSpec -Token ('-' + $element.ParameterName)
            if ($spec -and -not [string]::IsNullOrWhiteSpace($spec.ValueKind)) {
                return $spec
            }
        }
    }

    $null
}

function Complete-Pwsh {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $currentWord = if ($null -eq $WordToComplete) { '' } else { $WordToComplete }
    $tokensBeforeCurrent = @(Get-PwshArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)

    if ($currentWord -match '^(?<option>-[^:=]+|/[^:=]+)(?<separator>[:=])(?<value>.*)$') {
        $optionName = $Matches.option
        $attachedSpec = Resolve-PwshOptionSpec -Token $optionName
        if ($attachedSpec -and -not [string]::IsNullOrWhiteSpace($attachedSpec.ValueKind)) {
            return @(Get-PwshValueCompletions -Spec $attachedSpec -CurrentWord $Matches.value -AttachedPrefix "$optionName$($Matches.separator)")
        }
    }

    $parameterValueSpec = Get-PwshParameterValueContext -CommandAst $CommandAst -CursorPosition $CursorPosition
    if ($parameterValueSpec) {
        return @(Get-PwshValueCompletions -Spec $parameterValueSpec -CurrentWord $currentWord)
    }

    $pendingOption = Get-PwshPendingOption -TokensBeforeCurrent $tokensBeforeCurrent
    if ($pendingOption) {
        return @(Get-PwshValueCompletions -Spec $pendingOption -CurrentWord $currentWord)
    }

    if (Test-PwshHasTerminalOption -TokensBeforeCurrent $tokensBeforeCurrent -TerminalOptions @('-File', '-f')) {
        if (Test-PwshPathLike -Value $currentWord) {
            return @(Get-PwshPathCompletions -InputPath $currentWord -Placeholder '<script-argument>')
        }

        return @(New-PwshCompletionResult -CompletionText '<script-argument>' -ToolTip 'Argument passed to the script file.')
    }

    if (Test-PwshHasTerminalOption -TokensBeforeCurrent $tokensBeforeCurrent -TerminalOptions @('-Command', '-c', '-CommandWithArgs', '-cwa')) {
        return @(Get-PwshCommandTextCompletions -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and ($currentWord.StartsWith('-') -or $currentWord.StartsWith('/'))) {
        return @(Get-PwshOptionCompletions -CurrentWord $currentWord)
    }

    if (Test-PwshPathLike -Value $currentWord) {
        return @(Get-PwshPathCompletions -InputPath $currentWord -Placeholder '<script.ps1>')
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        # -File is the default parameter, so the bare operand slot offers scripts alongside the options.
        return @(
            Get-PwshOptionCompletions -CurrentWord $currentWord
            Get-PwshPathCompletions -InputPath $currentWord -Placeholder '' -Extension @('.ps1')
        )
    }

    @(Get-PwshPathCompletions -InputPath $currentWord -Placeholder '<script.ps1>')
}
}

Register-ArgumentCompleter -Native -CommandName @('pwsh', 'pwsh.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pwsh -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
