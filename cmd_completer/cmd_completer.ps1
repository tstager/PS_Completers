Set-StrictMode -Version 2.0

if ($true) {
function New-CmdCompletionResult {
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

function Test-CmdStartsWith {
    param(
        [string]$Candidate,
        [string]$Prefix
    )

    [string]::IsNullOrEmpty($Prefix) -or $Candidate.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-CmdSwitchSpecs {
    @(
        [pscustomobject]@{ Token = '/A'; Description = 'Use ANSI output for internal command output redirected to a pipe or file.' }
        [pscustomobject]@{ Token = '/U'; Description = 'Use Unicode output for internal command output redirected to a pipe or file.' }
        [pscustomobject]@{ Token = '/Q'; Description = 'Turn echo off.' }
        [pscustomobject]@{ Token = '/D'; Description = 'Disable AutoRun command execution from the registry.' }
        [pscustomobject]@{ Token = '/S'; Description = 'Modify quote handling after /C or /K.' }
        [pscustomobject]@{ Token = '/C'; Description = 'Run the following command string, then terminate.' }
        [pscustomobject]@{ Token = '/K'; Description = 'Run the following command string and remain open.' }
        [pscustomobject]@{ Token = '/R'; Description = 'Compatibility alias for /C.' }
        [pscustomobject]@{ Token = '/X'; Description = 'Compatibility alias for /E:ON.' }
        [pscustomobject]@{ Token = '/Y'; Description = 'Compatibility alias for /E:OFF.' }
        [pscustomobject]@{ Token = '/E:ON'; Description = 'Enable command extensions.' }
        [pscustomobject]@{ Token = '/E:OFF'; Description = 'Disable command extensions.' }
        [pscustomobject]@{ Token = '/F:ON'; Description = 'Enable file and directory completion characters.' }
        [pscustomobject]@{ Token = '/F:OFF'; Description = 'Disable file and directory completion characters.' }
        [pscustomobject]@{ Token = '/V:ON'; Description = 'Enable delayed environment variable expansion.' }
        [pscustomobject]@{ Token = '/V:OFF'; Description = 'Disable delayed environment variable expansion.' }
        [pscustomobject]@{ Token = '/T:'; Description = 'Set initial foreground/background console colors.' }
        [pscustomobject]@{ Token = '/?'; Description = 'Display cmd.exe help.' }
    )
}

function Remove-CmdOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function Test-CmdPathLike {
    param([string]$Value)

    $clean = Remove-CmdOuterQuotes -Value $Value
    -not [string]::IsNullOrWhiteSpace($clean) -and $clean -match '^(?:\.{1,2}[\\/]|~[\\/]|[A-Za-z]:[\\/]|\\\\|[\\/])'
}

function Get-CmdPathCompletions {
    param(
        [string]$InputPath,
        [string]$Placeholder = '<path>'
    )

    $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
    foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($InputPath)) {
        $results.Add([System.Management.Automation.CompletionResult]::new(
            $item.CompletionText,
            $item.CompletionText,
            $item.ResultType,
            $item.ToolTip
        ))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Placeholder)) {
        $results.Add((New-CmdCompletionResult -CompletionText $Placeholder -ToolTip $Placeholder))
    }

    $results
}

function Get-CmdArgumentTokens {
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

function Get-CmdColorValues {
    @(
        '07', '0A', '0B', '0C', '0E', '0F',
        '70', '1F', '2F', '4F', '5F', 'F0'
    )
}

function Get-CmdInternalCommands {
    @(
        'ASSOC', 'BREAK', 'CALL', 'CD', 'CHDIR', 'CLS', 'COLOR', 'COPY', 'DATE',
        'DEL', 'DIR', 'ECHO', 'ENDLOCAL', 'ERASE', 'EXIT', 'FOR', 'FTYPE', 'GOTO',
        'IF', 'MD', 'MKDIR', 'MOVE', 'PATH', 'PAUSE', 'POPD', 'PROMPT', 'PUSHD',
        'RD', 'REM', 'REN', 'RENAME', 'RMDIR', 'SET', 'SETLOCAL', 'SHIFT',
        'START', 'TIME', 'TITLE', 'TYPE', 'VER', 'VERIFY', 'VOL'
    )
}

function Get-CmdCommandCompletions {
    param([string]$CurrentWord)

    foreach ($command in Get-CmdInternalCommands) {
        if (Test-CmdStartsWith -Candidate $command -Prefix $CurrentWord) {
            New-CmdCompletionResult -CompletionText $command -ToolTip 'cmd.exe internal command.'
        }
    }

    if (Test-CmdPathLike -Value $CurrentWord) {
        foreach ($item in Get-CmdPathCompletions -InputPath $CurrentWord -Placeholder '') {
            $item
        }
    }

    foreach ($command in @(Get-Command -Name "$CurrentWord*" -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Sort-Object -Property Name -Unique | Select-Object -First 30)) {
        New-CmdCompletionResult -CompletionText $command.Name -ToolTip $command.Source
    }

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        New-CmdCompletionResult -CompletionText '<command>' -ToolTip 'Command string passed to cmd.exe.'
    }
}

function Test-CmdCommandTailActive {
    param([string[]]$TokensBeforeCurrent)

    foreach ($token in $TokensBeforeCurrent) {
        if ($token.Equals('/C', [System.StringComparison]::OrdinalIgnoreCase) -or
            $token.Equals('/K', [System.StringComparison]::OrdinalIgnoreCase) -or
            $token.Equals('/R', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $false
}

function Get-CmdSwitchCompletions {
    param([string]$CurrentWord)

    if ($CurrentWord -match '^/(?<name>[EFV]):(?<value>.*)$') {
        $prefix = '/' + $Matches.name + ':'
        foreach ($value in @('ON', 'OFF')) {
            $completionText = "$prefix$value"
            if (Test-CmdStartsWith -Candidate $completionText -Prefix $CurrentWord) {
                New-CmdCompletionResult -CompletionText $completionText -ToolTip "$prefix$value" -ResultType 'ParameterName'
            }
        }

        return
    }

    if ($CurrentWord -match '^/T:(?<value>.*)$') {
        foreach ($value in Get-CmdColorValues) {
            $completionText = "/T:$value"
            if (Test-CmdStartsWith -Candidate $completionText -Prefix $CurrentWord) {
                New-CmdCompletionResult -CompletionText $completionText -ToolTip 'Initial foreground/background color pair.' -ResultType 'ParameterName'
            }
        }

        return
    }

    foreach ($spec in Get-CmdSwitchSpecs) {
        if (Test-CmdStartsWith -Candidate $spec.Token -Prefix $CurrentWord) {
            New-CmdCompletionResult -CompletionText $spec.Token -ToolTip $spec.Description -ResultType 'ParameterName'
        }
    }
}

function Complete-Cmd {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $currentWord = if ($null -eq $WordToComplete) { '' } else { $WordToComplete }
    $tokensBeforeCurrent = @(Get-CmdArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)

    if (Test-CmdCommandTailActive -TokensBeforeCurrent $tokensBeforeCurrent) {
        return @(Get-CmdCommandCompletions -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('/')) {
        return @(Get-CmdSwitchCompletions -CurrentWord $currentWord)
    }

    if (Test-CmdPathLike -Value $currentWord) {
        return @(Get-CmdPathCompletions -InputPath $currentWord -Placeholder '<command>')
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-CmdSwitchCompletions -CurrentWord $currentWord)
    }

    @(Get-CmdCommandCompletions -CurrentWord $currentWord)
}
}

Register-ArgumentCompleter -Native -CommandName @('cmd', 'cmd.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Cmd -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
