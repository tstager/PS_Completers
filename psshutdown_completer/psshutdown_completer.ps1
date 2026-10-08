# psshutdown tab completion for PowerShell
# Native completer for PsShutdown actions, switches, and value-aware placeholders.

Set-StrictMode -Version Latest

function New-PsShutdownCompletionResult {
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

function Remove-PsShutdownOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    $Value.TrimStart('"')
}

function Get-PsShutdownActionSpecs {
    @(
        [pscustomobject]@{ Token = '-s'; Description = 'Shutdown without poweroff.' }
        [pscustomobject]@{ Token = '-r'; Description = 'Reboot after shutdown.' }
        [pscustomobject]@{ Token = '-h'; Description = 'Hibernate the computer.' }
        [pscustomobject]@{ Token = '-d'; Description = 'Suspend the computer.' }
        [pscustomobject]@{ Token = '-k'; Description = 'Power off the computer.' }
        [pscustomobject]@{ Token = '-a'; Description = 'Abort a shutdown already in progress.' }
        [pscustomobject]@{ Token = '-l'; Description = 'Lock the computer.' }
        [pscustomobject]@{ Token = '-o'; Description = 'Log off the console user.' }
        [pscustomobject]@{ Token = '-x'; Description = 'Turn the monitor off.' }
    )
}

function Get-PsShutdownSwitchSpecs {
    @(
        [pscustomobject]@{ Token = '-f'; Description = 'Force running applications to close.'; TakesValue = $false }
        [pscustomobject]@{ Token = '-c'; Description = 'Allow the shutdown to be aborted by the interactive user.'; TakesValue = $false }
        [pscustomobject]@{ Token = '-t'; Description = 'Countdown seconds or shutdown time in h:m format.'; TakesValue = $true; ValueKind = 'Time' }
        [pscustomobject]@{ Token = '-v'; Description = 'Display the shutdown dialog for the specified number of seconds.'; TakesValue = $true; ValueKind = 'DisplaySeconds' }
        [pscustomobject]@{ Token = '-e'; Description = 'Shutdown reason code in [u|p]:xx:yy form.'; TakesValue = $true; ValueKind = 'ReasonCode' }
        [pscustomobject]@{ Token = '-m'; Description = 'Message shown to logged on users.'; TakesValue = $true; ValueKind = 'Message' }
        [pscustomobject]@{ Token = '-u'; Description = 'User name for the remote connection.'; TakesValue = $true; ValueKind = 'UserName' }
        [pscustomobject]@{ Token = '-p'; Description = 'Optional password for the remote connection user name.'; TakesValue = $true; ValueKind = 'Password' }
        [pscustomobject]@{ Token = '-n'; Description = 'Timeout in seconds for connecting to remote computers.'; TakesValue = $true; ValueKind = 'ConnectTimeout' }
        [pscustomobject]@{ Token = '-nobanner'; Description = 'Suppress the startup banner and copyright message.'; TakesValue = $false }
        [pscustomobject]@{ Token = '-accepteula'; Description = 'Accept the Sysinternals license agreement without the first-run dialog.'; TakesValue = $false }
    )
}

if (-not (Get-Variable -Name PsShutdownCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:PsShutdownCompletionCatalog = @{
        Initialized         = $false
        Actions             = @()
        ActionLookup        = @{}
        Switches            = @()
        SwitchLookup        = @{}
        ValueTakingSwitches = @{}
        ReasonCodes         = $null
    }
}

function Initialize-PsShutdownCompletionCatalog {
    if ($script:PsShutdownCompletionCatalog.Initialized) {
        return
    }

    $script:PsShutdownCompletionCatalog.Actions = @(Get-PsShutdownActionSpecs)
    $script:PsShutdownCompletionCatalog.ActionLookup = @{}
    $script:PsShutdownCompletionCatalog.Switches = @(Get-PsShutdownSwitchSpecs)
    $script:PsShutdownCompletionCatalog.SwitchLookup = @{}
    $script:PsShutdownCompletionCatalog.ValueTakingSwitches = @{}

    foreach ($action in $script:PsShutdownCompletionCatalog.Actions) {
        $script:PsShutdownCompletionCatalog.ActionLookup[$action.Token.ToLowerInvariant()] = $action
    }

    foreach ($switchSpec in $script:PsShutdownCompletionCatalog.Switches) {
        $lowerToken = $switchSpec.Token.ToLowerInvariant()
        $script:PsShutdownCompletionCatalog.SwitchLookup[$lowerToken] = $switchSpec
        if ($switchSpec.TakesValue) {
            $script:PsShutdownCompletionCatalog.ValueTakingSwitches[$lowerToken] = $switchSpec.ValueKind
        }
    }

    $script:PsShutdownCompletionCatalog.Initialized = $true
}

function Get-PsShutdownCommandState {
    param([string[]]$TokensBeforeCurrent)

    $usedTokens = @{}
    $selectedAction = $null
    $valueContext = $null
    $hasRemoteTarget = $false
    $remoteTargetToken = $null

    for ($i = 0; $i -lt $TokensBeforeCurrent.Count; $i++) {
        $token = $TokensBeforeCurrent[$i]
        $lookup = $token.ToLowerInvariant()

        if ($script:PsShutdownCompletionCatalog.ActionLookup.ContainsKey($lookup)) {
            $usedTokens[$lookup] = $true
            if (-not $selectedAction) {
                $selectedAction = $lookup
            }
            continue
        }

        if ($script:PsShutdownCompletionCatalog.SwitchLookup.ContainsKey($lookup)) {
            $usedTokens[$lookup] = $true
            if ($script:PsShutdownCompletionCatalog.ValueTakingSwitches.ContainsKey($lookup)) {
                if ($i -eq ($TokensBeforeCurrent.Count - 1)) {
                    $valueContext = $lookup
                    break
                }

                $i++
            }
            continue
        }

        if (-not $hasRemoteTarget) {
            $hasRemoteTarget = $true
            $remoteTargetToken = $token
        }
    }

    [pscustomobject]@{
        UsedTokens        = $usedTokens
        SelectedAction    = $selectedAction
        ValueContext      = $valueContext
        HasRemoteTarget   = $hasRemoteTarget
        RemoteTargetToken = $remoteTargetToken
    }
}

function New-PsShutdownLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-PsShutdownCompletionResult -CompletionText $Placeholder -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-PsShutdownCompletionResult -CompletionText $CurrentValue -ListItemText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-PsShutdownSampleValueResults {
    param(
        [string]$CurrentValue,
        [object[]]$Samples,
        [string]$Placeholder,
        [string]$PlaceholderToolTip
    )

    $typedValue = Remove-PsShutdownOuterQuotes -Value $CurrentValue
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($sample in $Samples) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $sample.CompletionText.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $sample.CompletionText `
                -ListItemText $sample.ListItemText `
                -ResultType 'ParameterValue' `
                -ToolTip $sample.ToolTip
        ))
    }

    if ([string]::IsNullOrWhiteSpace($typedValue) -or
        $Placeholder.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $Placeholder `
                -ListItemText $Placeholder `
                -ResultType 'ParameterValue' `
                -ToolTip $PlaceholderToolTip
        ))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $CurrentValue `
                -ListItemText $CurrentValue `
                -ResultType 'ParameterValue' `
                -ToolTip $PlaceholderToolTip
        ))
    }

    @($results.ToArray())
}

function ConvertFrom-PsShutdownTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    [string]$tokens[0].Value
}

function ConvertTo-PsShutdownQuotedValue {
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

function Get-PsShutdownAtFileCompletions {
    param(
        [string]$CurrentWord,
        [string]$SpanText,
        [bool]$StrandedAt = $false
    )

    $rawValue = if ([string]::IsNullOrEmpty($CurrentWord)) { '@' } else { $CurrentWord }
    $quoteChar = if ($rawValue -match '^[''"\u2018-\u201E]') { $rawValue.Substring(0, 1) } else { '' }
    $trimmedValue = ConvertFrom-PsShutdownTypedWord -Value $rawValue
    if (-not $trimmedValue.StartsWith('@')) {
        return @()
    }

    $inputPath = $trimmedValue.Substring(1)
    # The typed directory part ('.\', '../', 'docs\', 'C:') is kept exactly as typed, so a
    # candidate never deletes typed text; only the leaf after it is matched.
    $directoryPart = if ($inputPath -match '^.*[\\/]') { $Matches[0] } elseif ($inputPath -match '^[A-Za-z]:') { $Matches[0] } else { '' }
    $leaf = $inputPath.Substring($directoryPart.Length)
    $parent = if ($directoryPart) { $directoryPart } else { '.' }
    $separator = if ($directoryPart.EndsWith('/')) { '/' } else { [string][System.IO.Path]::DirectorySeparatorChar }

    $items = @()
    if (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Ignore) {
        $namePattern = [System.Management.Automation.WildcardPattern]::Escape($leaf) + '*'
        $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore | Where-Object { $_.Name -like $namePattern })
    }
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($item in $items) {
        $pathText = $directoryPart + $item.Name
        if ($item.PSIsContainer) {
            $pathText += $separator
        }

        # '@' is never safe bare (it opens a splat), so the value is always quoted. A stranded
        # bare '@' stays in the line, and only '@(' keeps it valid: it passes the quoted
        # '@path' to psshutdown as one argument.
        $completionText = if ($StrandedAt) {
            '(' + (ConvertTo-PsShutdownQuotedValue -Value ('@' + $pathText)) + ')'
        } else {
            ConvertTo-PsShutdownQuotedValue -Value ('@' + $pathText) -QuoteChar $quoteChar
        }
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $completionText `
                -ListItemText ('@' + $item.Name) `
                -ResultType 'ParameterValue' `
                -ToolTip 'Path to a file containing remote computer names.'
        ))
    }

    if (-not $StrandedAt -and ([string]::IsNullOrWhiteSpace($inputPath) -or
            '@file'.StartsWith($trimmedValue, [System.StringComparison]::OrdinalIgnoreCase))) {
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText '@file' `
                -ListItemText '@file' `
                -ResultType 'ParameterValue' `
                -ToolTip 'Path to a file containing remote computer names.'
        ))
    }

    # The echo is the text PowerShell's replacement span covers, so accepting it changes nothing.
    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($SpanText)) {
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $SpanText `
                -ListItemText $SpanText `
                -ResultType 'ParameterValue' `
                -ToolTip 'Remote target file in @file form.'
        ))
    }

    @($results.ToArray())
}

function Get-PsShutdownRemoteTargetCompletions {
    param(
        [string]$CurrentWord,
        [string]$SpanText,
        [bool]$StrandedAt = $false
    )

    if ((ConvertFrom-PsShutdownTypedWord -Value $CurrentWord).StartsWith('@')) {
        return @(Get-PsShutdownAtFileCompletions -CurrentWord $CurrentWord -SpanText $SpanText -StrandedAt $StrandedAt)
    }

    $typedValue = if ($null -eq $CurrentWord) { '' } else { Remove-PsShutdownOuterQuotes -Value $CurrentWord }

    $results = New-Object System.Collections.Generic.List[object]

    # PowerShell splits a native argument at ',' before the completer runs, so a
    # '\\a,b' list is never seen as one word; only the single-target forms are modelled.
    $candidates = @(
        [pscustomobject]@{ CompletionText = '\\computer'; ToolTip = 'Remote computer target in \\computer form.' }
        [pscustomobject]@{ CompletionText = '\\*'; ToolTip = 'Broadcast shutdown target placeholder.' }
        [pscustomobject]@{ CompletionText = '@file'; ToolTip = 'Path to a file containing remote computer names.' }
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($typedValue) -and
            -not $candidate.CompletionText.StartsWith($typedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $candidate.CompletionText `
                -ListItemText $candidate.CompletionText `
                -ResultType 'ParameterValue' `
                -ToolTip $candidate.ToolTip
        ))
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $CurrentWord `
                -ListItemText $CurrentWord `
                -ResultType 'ParameterValue' `
                -ToolTip 'Remote target in \\computer[,computer[,...]] or @file form.'
        ))
    }

    @($results.ToArray())
}

function Get-PsShutdownOptionCompletions {
    param(
        [string]$CurrentWord,
        [psobject]$State
    )

    $prefix = if ($null -eq $CurrentWord) { '' } else { $CurrentWord }
    $results = New-Object System.Collections.Generic.List[object]

    if (-not $State.SelectedAction) {
        foreach ($action in $script:PsShutdownCompletionCatalog.Actions) {
            if ($State.UsedTokens.ContainsKey($action.Token.ToLowerInvariant())) {
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($prefix) -and
                -not $action.Token.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            [void]$results.Add((
                New-PsShutdownCompletionResult `
                    -CompletionText $action.Token `
                    -ListItemText $action.Token `
                    -ResultType 'ParameterName' `
                    -ToolTip $action.Description
            ))
        }
    }

    foreach ($switchSpec in $script:PsShutdownCompletionCatalog.Switches) {
        $lowerToken = $switchSpec.Token.ToLowerInvariant()
        if ($State.UsedTokens.ContainsKey($lowerToken)) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($prefix) -and
            -not $switchSpec.Token.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [void]$results.Add((
            New-PsShutdownCompletionResult `
                -CompletionText $switchSpec.Token `
                -ListItemText $switchSpec.Token `
                -ResultType 'ParameterName' `
                -ToolTip $switchSpec.Description
        ))
    }

    @($results.ToArray())
}

function Get-PsShutdownReasonCodeList {
    $cached = $script:PsShutdownCompletionCatalog['ReasonCodes']
    if ($null -ne $cached) {
        return $cached
    }

    $fallback = @(
        [pscustomobject]@{ CompletionText = 'u:0:0'; ListItemText = 'u:0:0'; ToolTip = 'Other (Unplanned).' }
        [pscustomobject]@{ CompletionText = 'p:0:0'; ListItemText = 'p:0:0'; ToolTip = 'Other (Planned).' }
        [pscustomobject]@{ CompletionText = 'u:2:18'; ListItemText = 'u:2:18'; ToolTip = 'Operating System: Security fix (Unplanned).' }
        [pscustomobject]@{ CompletionText = 'p:2:17'; ListItemText = 'p:2:17'; ToolTip = 'Operating System: Hot fix (Planned).' }
        [pscustomobject]@{ CompletionText = 'p:4:2'; ListItemText = 'p:4:2'; ToolTip = 'Application: Installation (Planned).' }
    )

    # Without an accepted EULA the tool would raise its first-run dialog, so it is
    # never started; this is not cached, so accepting the EULA later takes effect.
    $eulaAccepted = [Microsoft.Win32.Registry]::GetValue('HKEY_CURRENT_USER\Software\Sysinternals\PsShutdown', 'EulaAccepted', $null)
    if ($eulaAccepted -ne 1) {
        return $fallback
    }

    $command = Get-Command -Name 'psshutdown' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    $text = ''
    if ($command) {
        # '-nobanner -?' only prints usage plus this computer's reason table; stdin is
        # closed and the call is bounded so a hang can never stall the completion thread.
        try {
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $command.Source
            $startInfo.ArgumentList.Add('-nobanner')
            $startInfo.ArgumentList.Add('-?')
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true

            $process = [System.Diagnostics.Process]::Start($startInfo)
            try {
                $process.StandardInput.Close()
                $outputTask = $process.StandardOutput.ReadToEndAsync()
                $errorTask = $process.StandardError.ReadToEndAsync()
                if ($process.WaitForExit(5000)) {
                    $text = ($outputTask.Result + "`n" + $errorTask.Result) -replace '\e\[[0-9;?]*[ -/]*[@-~]', ''
                } else {
                    $process.Kill()
                }
            } finally {
                $process.Dispose()
            }
        } catch {
            Write-Debug ('psshutdown completer: help capture failed: ' + $_.Exception.Message)
            $text = ''
        }
    }

    # Table rows under 'Reasons defined on this computer': '  U      2      17     Operating System: Hot fix (Unplanned)'.
    $codes = New-Object System.Collections.Generic.List[object]
    foreach ($match in [regex]::Matches($text, '(?m)^\s+([UP])\s+(\d+)\s+(\d+)\s+(\S.*?)\s*$')) {
        $kind = if ($match.Groups[1].Value -eq 'U') { 'Unplanned' } else { 'Planned' }
        $title = $match.Groups[4].Value
        if ($title -notmatch '\((Un)?planned\)$') {
            $title = "$title ($kind)"
        }

        $code = '{0}:{1}:{2}' -f $match.Groups[1].Value.ToLowerInvariant(), $match.Groups[2].Value, $match.Groups[3].Value
        [void]$codes.Add([pscustomobject]@{ CompletionText = $code; ListItemText = $code; ToolTip = "$title." })
    }

    $script:PsShutdownCompletionCatalog['ReasonCodes'] = if ($codes.Count -gt 0) { $codes.ToArray() } else { $fallback }
    $script:PsShutdownCompletionCatalog['ReasonCodes']
}

function Get-PsShutdownValueCompletions {
    param(
        [string]$OptionToken,
        [string]$CurrentWord
    )

    switch ($OptionToken.ToLowerInvariant()) {
        '-t' {
            return @(Get-PsShutdownSampleValueResults -CurrentValue $CurrentWord -Placeholder '<seconds-or-h:mm>' -PlaceholderToolTip 'Countdown seconds or shutdown time in h:m format.' -Samples @(
                    [pscustomobject]@{ CompletionText = '20'; ListItemText = '20'; ToolTip = 'Default countdown in seconds.' }
                    [pscustomobject]@{ CompletionText = '30'; ListItemText = '30'; ToolTip = 'Thirty-second countdown.' }
                    [pscustomobject]@{ CompletionText = '60'; ListItemText = '60'; ToolTip = 'One-minute countdown.' }
                    [pscustomobject]@{ CompletionText = '300'; ListItemText = '300'; ToolTip = 'Five-minute countdown.' }
                    [pscustomobject]@{ CompletionText = '1:00'; ListItemText = '1:00'; ToolTip = 'Shutdown time in 24-hour notation.' }
                    [pscustomobject]@{ CompletionText = '23:00'; ListItemText = '23:00'; ToolTip = 'Shutdown time in 24-hour notation.' }
                ))
        }
        '-v' {
            return @(Get-PsShutdownSampleValueResults -CurrentValue $CurrentWord -Placeholder '<seconds>' -PlaceholderToolTip 'Seconds to display the shutdown dialog.' -Samples @(
                    [pscustomobject]@{ CompletionText = '0'; ListItemText = '0'; ToolTip = 'Skip the shutdown notification dialog.' }
                    [pscustomobject]@{ CompletionText = '5'; ListItemText = '5'; ToolTip = 'Display the shutdown dialog for 5 seconds.' }
                    [pscustomobject]@{ CompletionText = '10'; ListItemText = '10'; ToolTip = 'Display the shutdown dialog for 10 seconds.' }
                    [pscustomobject]@{ CompletionText = '30'; ListItemText = '30'; ToolTip = 'Display the shutdown dialog for 30 seconds.' }
                ))
        }
        '-e' {
            return @(Get-PsShutdownSampleValueResults -CurrentValue $CurrentWord -Placeholder '[u|p]:xx:yy' -PlaceholderToolTip 'Shutdown reason code in planned/unplanned major:minor form.' -Samples @(Get-PsShutdownReasonCodeList))
        }
        '-m' {
            return @(New-PsShutdownLiteralValueResults -CurrentValue $CurrentWord -Placeholder '"<message>"' -ToolTip 'Message text shown to logged on users.')
        }
        '-u' {
            return @(Get-PsShutdownSampleValueResults -CurrentValue $CurrentWord -Placeholder '<username>' -PlaceholderToolTip 'Remote credentials user name.' -Samples @(
                    [pscustomobject]@{ CompletionText = '<domain\user>'; ListItemText = '<domain\user>'; ToolTip = 'Domain-qualified user name.' }
                    [pscustomobject]@{ CompletionText = '.\Administrator'; ListItemText = '.\Administrator'; ToolTip = 'Local Administrator account example.' }
                    [pscustomobject]@{ CompletionText = 'Administrator'; ListItemText = 'Administrator'; ToolTip = 'Simple user name example.' }
                ))
        }
        '-p' {
            return @(New-PsShutdownLiteralValueResults -CurrentValue $CurrentWord -Placeholder '<password>' -ToolTip 'Remote credentials password.')
        }
        '-n' {
            return @(Get-PsShutdownSampleValueResults -CurrentValue $CurrentWord -Placeholder '<seconds>' -PlaceholderToolTip 'Connection timeout in seconds for remote computers.' -Samples @(
                    [pscustomobject]@{ CompletionText = '5'; ListItemText = '5'; ToolTip = 'Five-second connection timeout.' }
                    [pscustomobject]@{ CompletionText = '10'; ListItemText = '10'; ToolTip = 'Ten-second connection timeout.' }
                    [pscustomobject]@{ CompletionText = '30'; ListItemText = '30'; ToolTip = 'Thirty-second connection timeout.' }
                    [pscustomobject]@{ CompletionText = '60'; ListItemText = '60'; ToolTip = 'One-minute connection timeout.' }
                ))
        }
    }

    @()
}

function Complete-PsShutdown {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-PsShutdownCompletionCatalog

    # The typed word is read from the parser, not from $wordToComplete (a registered
    # completer receives it with '$name' expanded): the element that contains the cursor,
    # cut at the cursor. An unterminated quote is one element. SpanText is the whole
    # element, which is what PowerShell's replacement span covers.
    $elements = @($commandAst.CommandElements | Select-Object -Skip 1)
    $typedWord = ''
    $spanText = ''
    $strandedAt = $false
    $currentStart = $cursorPosition
    for ($i = 0; $i -lt $elements.Count; $i++) {
        $extent = $elements[$i].Extent
        if ($extent.StartOffset -lt $cursorPosition -and $cursorPosition -le $extent.EndOffset) {
            $currentStart = $extent.StartOffset

            # In a comma list PowerShell completes only the item after the last comma: the
            # list item that holds the cursor, or a fresh empty word right after a comma.
            $wordExtent = $extent
            if ($elements[$i] -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                $wordExtent = @($elements[$i].Elements | Where-Object { $_.Extent.StartOffset -lt $cursorPosition -and $cursorPosition -le $_.Extent.EndOffset } | ForEach-Object { $_.Extent }) | Select-Object -First 1
            } elseif ($elements[$i] -is [System.Management.Automation.Language.ErrorExpressionAst] -and
                $extent.Text.Substring(0, $cursorPosition - $extent.StartOffset).EndsWith(',')) {
                $wordExtent = $null
            }

            if (-not $wordExtent) {
                break
            }

            $typedWord = $wordExtent.Text.Substring(0, $cursorPosition - $wordExtent.StartOffset)
            $spanText = $wordExtent.Text

            # A bare '@' is an unrecognized token, so the parser splits '@.\hosts.txt' into
            # '@' and '.\hosts.txt'. Tab right after such an '@' keeps the line as it is;
            # Tab in the path after it completes the glued word, and the span is the path.
            $next = if ($i + 1 -lt $elements.Count) { $elements[$i + 1].Extent } else { $null }
            if ($spanText -eq '@' -and $next -and $next.StartOffset -eq $extent.EndOffset) {
                return @(New-PsShutdownCompletionResult -CompletionText '@' -ResultType 'ParameterValue' -ToolTip 'Path to a file containing remote computer names.')
            }

            $previous = if ($i -gt 0) { $elements[$i - 1].Extent } else { $null }
            if ($previous -and $previous.Text -eq '@' -and $previous.EndOffset -eq $extent.StartOffset) {
                $typedWord = '@' + $typedWord
                $strandedAt = $true
                $currentStart = $previous.StartOffset
            }
            break
        }
    }

    $currentWord = if ([string]::IsNullOrWhiteSpace($wordToComplete)) { $typedWord } else { $wordToComplete }

    # Only elements that end before the current word are consumed, so completing inside
    # or at the end of an earlier token sees the same context as typing it fresh.
    $tokensBeforeCurrent = @(
        $elements |
            Where-Object { $_.Extent.EndOffset -le $currentStart } |
            ForEach-Object { $_.Extent.Text }
    )

    $state = Get-PsShutdownCommandState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.ValueContext) {
        return @(Get-PsShutdownValueCompletions -OptionToken $state.ValueContext -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord)) {
        # '@-d' is split into '@' and '-d' by the parser, but it is an @file word, not a switch.
        if ($currentWord.StartsWith('-') -and -not $strandedAt) {
            return @(Get-PsShutdownOptionCompletions -CurrentWord $currentWord -State $state)
        }

        if ($typedWord -match '^[''"\u2018-\u201E]?@') {
            return @(Get-PsShutdownRemoteTargetCompletions -CurrentWord $typedWord -SpanText $spanText -StrandedAt $strandedAt)
        }

        if ($currentWord.StartsWith('\')) {
            return @(Get-PsShutdownRemoteTargetCompletions -CurrentWord $currentWord)
        }

        if ($state.HasRemoteTarget) {
            return @()
        }

        return @(Get-PsShutdownRemoteTargetCompletions -CurrentWord $currentWord)
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($result in @(Get-PsShutdownOptionCompletions -CurrentWord $currentWord -State $state)) {
        [void]$results.Add($result)
    }

    # Switches stay valid after the target; only the target candidates must not repeat.
    if (-not $state.HasRemoteTarget) {
        foreach ($result in @(Get-PsShutdownRemoteTargetCompletions -CurrentWord $currentWord)) {
            [void]$results.Add($result)
        }
    }

    @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName 'psshutdown', 'psshutdown.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsShutdown -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
