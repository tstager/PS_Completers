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
        [string]$Placeholder = '<path>'
    )

    $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
    foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($InputPath)) {
        $completionText = if ([string]::IsNullOrEmpty($AttachedPrefix)) {
            $item.CompletionText
        } else {
            "$AttachedPrefix$($item.CompletionText)"
        }

        $results.Add([System.Management.Automation.CompletionResult]::new(
            $completionText,
            $completionText,
            $item.ResultType,
            $completionText
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

    $optionMap = Get-PwshOptionMap
    $lastToken = $TokensBeforeCurrent[-1]
    if ($optionMap.ContainsKey($lastToken) -and -not [string]::IsNullOrWhiteSpace($optionMap[$lastToken].ValueKind)) {
        return $optionMap[$lastToken]
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
        $completionText = if ([string]::IsNullOrEmpty($AttachedPrefix)) { $value } else { "$AttachedPrefix$value" }
        if (Test-PwshStartsWith -Candidate $completionText -Prefix $CurrentWord) {
            New-PwshCompletionResult -CompletionText $completionText -ToolTip $(if ($ToolTip) { $ToolTip } else { $value })
        }
    }
}

function Get-PwshCommandTextCompletions {
    param([string]$CurrentWord)

    $suggestions = @('-', 'Get-Command', 'Get-Help', 'Get-Location', 'Get-Process', 'Get-Date', '& { <script> }', '<command>')
    foreach ($value in $suggestions) {
        if (Test-PwshStartsWith -Candidate $value -Prefix $CurrentWord) {
            New-PwshCompletionResult -CompletionText $value -ToolTip 'PowerShell command text.'
        }
    }
}

function Get-PwshValueCompletions {
    param(
        [object]$Spec,
        [string]$CurrentWord,
        [string]$AttachedPrefix = ''
    )

    switch ($Spec.ValueKind) {
        'ScriptPath'      { return @(Get-PwshPathCompletions -InputPath $CurrentWord -AttachedPrefix $AttachedPrefix -Placeholder '<script.ps1>') }
        'ConfigPath'      { return @(Get-PwshPathCompletions -InputPath $CurrentWord -AttachedPrefix $AttachedPrefix -Placeholder '<configuration.pssc>') }
        'SettingsPath'    { return @(Get-PwshPathCompletions -InputPath $CurrentWord -AttachedPrefix $AttachedPrefix -Placeholder '<settings.json>') }
        'DirectoryPath'   { return @(Get-PwshPathCompletions -InputPath $CurrentWord -AttachedPrefix $AttachedPrefix -Placeholder '<directory>') }
        'CommandText'     { return @(Get-PwshCommandTextCompletions -CurrentWord $CurrentWord) }
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

    foreach ($spec in Get-PwshOptionSpecs) {
        foreach ($token in $spec.Tokens) {
            if (Test-PwshStartsWith -Candidate $token -Prefix $CurrentWord) {
                New-PwshCompletionResult -CompletionText $token -ToolTip $spec.Description -ResultType 'ParameterName'
            }
        }
    }
}

function Test-PwshHasTerminalOption {
    param(
        [string[]]$TokensBeforeCurrent,
        [string[]]$TerminalOptions
    )

    $optionMap = Get-PwshOptionMap
    $skipNext = $false
    foreach ($token in $TokensBeforeCurrent) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }

        if ($TerminalOptions -contains $token) {
            return $true
        }

        if ($optionMap.ContainsKey($token) -and -not [string]::IsNullOrWhiteSpace($optionMap[$token].ValueKind)) {
            $skipNext = $true
        }
    }

    $false
}

function Complete-Pwsh {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $currentWord = if ($null -eq $WordToComplete) { '' } else { $WordToComplete }
    $tokensBeforeCurrent = @(Get-PwshArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $optionMap = Get-PwshOptionMap

    if ($currentWord -match '^(?<option>-[^:=]+|/[^:=]+)(?<separator>[:=])(?<value>.*)$') {
        $optionName = $Matches.option
        if ($optionMap.ContainsKey($optionName) -and -not [string]::IsNullOrWhiteSpace($optionMap[$optionName].ValueKind)) {
            return @(Get-PwshValueCompletions -Spec $optionMap[$optionName] -CurrentWord $Matches.value -AttachedPrefix "$optionName$($Matches.separator)")
        }
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
        return @(Get-PwshOptionCompletions -CurrentWord $currentWord)
    }

    @(Get-PwshPathCompletions -InputPath $currentWord -Placeholder '<script.ps1>')
}
}

Register-ArgumentCompleter -Native -CommandName @('pwsh', 'pwsh.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pwsh -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
