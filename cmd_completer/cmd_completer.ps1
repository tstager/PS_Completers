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

function Get-CmdColorTable {
    # The digit table printed by COLOR /?; /T:fg takes either one digit (foreground)
    # or two (background then foreground).
    [ordered]@{
        '0' = 'Black';  '1' = 'Blue';         '2' = 'Green';        '3' = 'Aqua'
        '4' = 'Red';    '5' = 'Purple';       '6' = 'Yellow';       '7' = 'White'
        '8' = 'Gray';   '9' = 'Light Blue';   'A' = 'Light Green';  'B' = 'Light Aqua'
        'C' = 'Light Red'; 'D' = 'Light Purple'; 'E' = 'Light Yellow'; 'F' = 'Bright White'
    }
}

function Get-CmdColorCompletion {
    param([string]$TypedValue)

    $names = Get-CmdColorTable
    if ([string]::IsNullOrEmpty($TypedValue)) {
        foreach ($digit in $names.Keys) {
            New-CmdCompletionResult -CompletionText ('/T:' + $digit) -ToolTip ('Foreground ' + $names[$digit] + ' (add a second digit for background/foreground).') -ResultType 'ParameterName'
        }

        return
    }

    $first = $TypedValue.Substring(0, 1).ToUpperInvariant()
    if (-not $names.Contains($first)) {
        return
    }

    if ($TypedValue.Length -eq 1) {
        New-CmdCompletionResult -CompletionText ('/T:' + $first) -ToolTip ('Foreground ' + $names[$first] + '.') -ResultType 'ParameterName'
    }

    $second = if ($TypedValue.Length -ge 2) { $TypedValue.Substring(1, 1).ToUpperInvariant() } else { '' }
    foreach ($digit in $names.Keys) {
        if ($second -and -not $digit.StartsWith($second)) {
            continue
        }

        New-CmdCompletionResult -CompletionText ('/T:' + $first + $digit) -ToolTip ($names[$digit] + ' on ' + $names[$first] + '.') -ResultType 'ParameterName'
    }
}

function Get-CmdInternalCommands {
    @(
        'ASSOC', 'BREAK', 'CALL', 'CD', 'CHCP', 'CHDIR', 'CLS', 'COLOR', 'COPY', 'DATE',
        'DEL', 'DIR', 'DPATH', 'ECHO', 'ENDLOCAL', 'ERASE', 'EXIT', 'FOR', 'FTYPE', 'GOTO',
        'IF', 'KEYS', 'MD', 'MKDIR', 'MKLINK', 'MOVE', 'PATH', 'PAUSE', 'POPD', 'PROMPT', 'PUSHD',
        'RD', 'REM', 'REN', 'RENAME', 'RMDIR', 'SET', 'SETLOCAL', 'SHIFT',
        'START', 'TIME', 'TITLE', 'TYPE', 'VER', 'VERIFY', 'VOL'
    )
}

function Get-CmdCommandCompletions {
    param([string]$CurrentWord)

    # A quoted tail word ('cmd /c "dir') is matched without its quotes and the
    # quote is reinstated on the completion so the command line stays balanced.
    $quotePrefix = if (-not [string]::IsNullOrEmpty($CurrentWord) -and $CurrentWord.StartsWith('"')) { '"' } else { '' }
    $cleanWord = Remove-CmdOuterQuotes -Value $CurrentWord

    foreach ($command in Get-CmdInternalCommands) {
        if (Test-CmdStartsWith -Candidate $command -Prefix $cleanWord) {
            New-CmdCompletionResult -CompletionText ($quotePrefix + $command + $quotePrefix) -ListItemText $command -ToolTip 'cmd.exe internal command.'
        }
    }

    if (Test-CmdPathLike -Value $CurrentWord) {
        foreach ($item in Get-CmdPathCompletions -InputPath $CurrentWord -Placeholder '') {
            $item
        }
    }

    foreach ($command in @(Get-Command -Name ([System.Management.Automation.WildcardPattern]::Escape($cleanWord) + '*') -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Sort-Object -Property Name -Unique | Select-Object -First 30)) {
        New-CmdCompletionResult -CompletionText ($quotePrefix + $command.Name + $quotePrefix) -ListItemText $command.Name -ToolTip $command.Source
    }

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        New-CmdCompletionResult -CompletionText '<command>' -ToolTip 'Command string passed to cmd.exe.'
    }
}

function Get-CmdCommandTailState {
    param([string[]]$TokensBeforeCurrent)

    # Everything after /C, /K or /R is the command string: its first word is the
    # command, the rest are that command's own arguments.
    $active = $false
    $tailWordCount = 0
    foreach ($token in $TokensBeforeCurrent) {
        if ($active) {
            $tailWordCount++
            continue
        }

        if ($token.Equals('/C', [System.StringComparison]::OrdinalIgnoreCase) -or
            $token.Equals('/K', [System.StringComparison]::OrdinalIgnoreCase) -or
            $token.Equals('/R', [System.StringComparison]::OrdinalIgnoreCase)) {
            $active = $true
        }
    }

    [pscustomobject]@{
        Active        = $active
        TailWordCount = $tailWordCount
    }
}

function Get-CmdCommandArgumentCompletion {
    param([string]$CurrentWord)

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        return @(New-CmdCompletionResult -CompletionText '<argument>' -ToolTip 'Argument for the command run by cmd.exe.')
    }

    if ($CurrentWord.StartsWith('/')) {
        # A slash here belongs to the inner command's switches, which this
        # completer does not model; keep the typed text rather than offering
        # filesystem roots for it.
        return @(New-CmdCompletionResult -CompletionText $CurrentWord -ListItemText '<switch>' -ToolTip 'Switch of the command run by cmd.exe; see that command''s /? help.')
    }

    if (Test-CmdPathLike -Value $CurrentWord) {
        return @(Get-CmdPathCompletions -InputPath $CurrentWord -Placeholder '')
    }

    @()
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

    if ($CurrentWord -match '^(?i)/T:(?<value>.*)$') {
        Get-CmdColorCompletion -TypedValue $Matches.value
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

    $tailState = Get-CmdCommandTailState -TokensBeforeCurrent $tokensBeforeCurrent
    if ($tailState.Active) {
        if ($tailState.TailWordCount -eq 0) {
            return @(Get-CmdCommandCompletions -CurrentWord $currentWord)
        }

        return @(Get-CmdCommandArgumentCompletion -CurrentWord $currentWord)
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
