# psexec tab completion for PowerShell
# Static-first native completer for PsExec with safe remote placeholders and conservative command-tail handling.

Set-StrictMode -Version 2.0

function Initialize-PsExecCompletionCatalog {
    if (Get-Variable -Name PsExecCompletionCatalog -Scope Script -ErrorAction Ignore) { return }

    $script:PsExecCompletionCatalog = @{
        Switches = @(
            [pscustomobject]@{ Token = '-u'; Description = 'Optional user name for login to the remote computer.'; TakesValue = $true; ValueKind = 'User' }
            [pscustomobject]@{ Token = '-p'; Description = 'Optional password for the remote user name.'; TakesValue = $true; ValueKind = 'Password' }
            [pscustomobject]@{ Token = '-n'; Description = 'Timeout in seconds connecting to remote computers.'; TakesValue = $true; ValueKind = 'Timeout' }
            [pscustomobject]@{ Token = '-r'; Description = 'Name of the remote service to create or interact with.'; TakesValue = $true; ValueKind = 'ServiceName' }
            [pscustomobject]@{ Token = '-h'; Description = 'Run with the account''s elevated token when available.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-l'; Description = 'Run process as a limited user.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-s'; Description = 'Run the remote process in the System account.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-e'; Description = 'Do not load the specified account''s profile.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-x'; Description = 'Display UI on the Winlogon secure desktop (local only).' ; TakesValue = $false }
            [pscustomobject]@{ Token = '-i'; Description = 'Run the program interactively in the specified session. The session id is optional.'; TakesValue = $true; ValueKind = 'Session'; OptionalValue = $true }
            [pscustomobject]@{ Token = '-c'; Description = 'Copy the specified program to the remote system for execution.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-f'; Description = 'Copy the specified program even if it already exists remotely.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-v'; Description = 'Copy only if the local file is newer or a higher version.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-w'; Description = 'Set the remote working directory for the process.'; TakesValue = $true; ValueKind = 'RemoteDirectory' }
            [pscustomobject]@{ Token = '-d'; Description = 'Do not wait for process termination.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-g'; Description = 'Set the primary thread processor group.'; TakesValue = $true; ValueKind = 'ProcessorGroup' }
            [pscustomobject]@{ Token = '-a'; Description = 'Restrict the application to the specified CPUs.'; TakesValue = $true; ValueKind = 'Affinity' }
            [pscustomobject]@{ Token = '-arm'; Description = 'Indicate that the remote computer is ARM architecture.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-verbose'; Description = 'Enable verbose PsExec status output.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-accepteula'; Description = 'Suppress the Sysinternals license dialog.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.'; TakesValue = $false }
            [pscustomobject]@{ Token = '-low'; Description = 'Run the process at low priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-belownormal'; Description = 'Run the process below normal priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-abovenormal'; Description = 'Run the process above normal priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-high'; Description = 'Run the process at high priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-realtime'; Description = 'Run the process at realtime priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-background'; Description = 'Run the process at low I/O and memory priority.'; TakesValue = $false; Group = 'Priority' }
            [pscustomobject]@{ Token = '-?'; Description = 'Display PsExec help.'; TakesValue = $false; Terminal = $true }
            [pscustomobject]@{ Token = '/?'; Description = 'Display PsExec help.'; TakesValue = $false; Terminal = $true }
        )
        TimeoutHints = @('1', '2', '5', '10', '30', '60')
        SessionHints = @('0', '1', '2', '<session-id>')
        GroupHints   = @('0', '1', '<group-id>')
        # Help: 'Separate processors ... with commas where 1 is the lowest
        # numbered CPU. For example, to run the application on CPU 2 and CPU 4,
        # enter: "-a 2,4"'. CPU 0 does not exist in that numbering.
        AffinityHints = @(@(1..([Math]::Min([Environment]::ProcessorCount, 8)) | ForEach-Object { [string]$_ }) + @('2,4', '<cpu-list>'))
    }
}

function Expand-PsExecHint {
    param([string[]]$Hints, [string]$CurrentWord, [string]$SpanText, [string]$ToolTip)

    $typed = Remove-PsExecOuterQuotes -Value $CurrentWord
    $matched = @(
        foreach ($hint in $Hints) {
            if ([string]::IsNullOrWhiteSpace($typed) -or $hint.StartsWith($typed, [System.StringComparison]::OrdinalIgnoreCase)) {
                New-PsExecCompletionResult -CompletionText $hint -ResultType 'ParameterValue' -ToolTip $ToolTip
            }
        }
    )

    if ($matched.Count -gt 0) { return $matched }

    # Never clobber what the user already typed with an unrelated hint.
    @(New-PsExecCompletionResult -CompletionText $SpanText -ResultType 'ParameterValue' -ToolTip $ToolTip)
}

function Split-PsExecPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [pscustomobject]@{ Parent = '.'; Leaf = '' }
    }

    # Split-Path -Leaf resolves a '.' or '..' leaf to the folder's own name,
    # so those leaves are matched on the text instead.
    if ($Path -match '[\\/]+$|(^|[\\/])\.\.?$') {
        return [pscustomobject]@{ Parent = $Path; Leaf = '' }
    }

    $leaf = Split-Path -Path $Path -Leaf
    $parent = Split-Path -Path $Path -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) { $parent = '.' }

    [pscustomobject]@{ Parent = $parent; Leaf = $leaf }
}

function New-PsExecCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }

    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

# PowerShell treats U+2018-U+201B as single quotes and U+201C-U+201E as double
# quotes, exactly like ' and ", so every quote test below covers both.
function Get-PsExecTypedQuote {
    param([string]$Value)
    if ($Value -match '^([''"\u2018-\u201E])') { return $Matches[1] }
    ''
}

function Remove-PsExecOuterQuotes {
    param([string]$Value)
    $quote = Get-PsExecTypedQuote -Value $Value
    if (-not $quote) { return $Value -replace '`(.)', '$1' }
    # An unterminated quote is one token running to the cursor: read the string
    # up to its closing quote, when present, and undo that quote style's escapes
    # (a doubled quote stands for its second character).
    $inner = $Value.Substring(1)
    if ($quote -match "['\u2018-\u201B]") {
        return [regex]::Match($inner, "^(?:[^'\u2018-\u201B]|['\u2018-\u201B]{2})*").Value -replace "['\u2018-\u201B](['\u2018-\u201B])", '$1'
    }
    [regex]::Match($inner, '^(?:[^`"\u201C-\u201E]|`.|["\u201C-\u201E]{2})*').Value -replace '`(.)|["\u201C-\u201E](["\u201C-\u201E])', '$1$2'
}

function ConvertTo-PsExecQuotedValue {
    param([string]$Value, [string]$Quote = '')
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if (-not $Quote -and $Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') { return $Value }
    # Keep the quote the user typed (single by default). Inside single quotes
    # every single-quote character is doubled; inside double quotes ` " $ and
    # the typographic double quotes take a backtick.
    if (-not $Quote) { $Quote = "'" }
    if ($Quote -match "['\u2018-\u201B]") {
        return $Quote + ($Value -replace "(['\u2018-\u201B])", '$1$1') + $Quote
    }
    $Quote + ($Value -replace '([`$"\u201C-\u201E])', '`$1') + $Quote
}

function Get-PsExecArgumentState {
    param([System.Management.Automation.Language.CommandAst]$CommandAst, [int]$CursorPosition)

    # A bare '@' is an unrecognized token, so the parser splits '@.\hosts.txt'
    # into '@' and '.\hosts.txt'; glue it back onto the element it touches so
    # the word is the one psexec will see.
    $words = New-Object System.Collections.Generic.List[object]
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $previous = if ($words.Count -gt 0) { $words[$words.Count - 1] } else { $null }
        if ($previous -and $previous.Text -eq '@' -and -not $previous.At -and $previous.End -eq $element.Extent.StartOffset) {
            $previous.Text = '@' + $element.Extent.Text
            $previous.End = $element.Extent.EndOffset
            $previous.At = $true
            continue
        }
        [void]$words.Add([pscustomobject]@{ Start = $element.Extent.StartOffset; End = $element.Extent.EndOffset; Text = $element.Extent.Text; At = $false })
    }

    # The word under the cursor is read from the parser, never from
    # $wordToComplete (a registered completer receives it with '$name'
    # expanded): the element that contains the cursor, cut at the cursor. An
    # unterminated quote is one element. SpanText is the text PowerShell's
    # replacement span covers: the whole element, even when the cursor is
    # mid-word, so an echo of it changes nothing. For a glued '@' the span is
    # only the path after it (StrandedAt, results must keep that '@' valid), or
    # only the '@' itself when the cursor sits right after it (AtOnly).
    $currentWord = ''
    $spanText = ''
    $strandedAt = $false
    $atOnly = $false
    foreach ($word in $words) {
        if ($word.Start -lt $CursorPosition -and $word.End -ge $CursorPosition) {
            $currentWord = $word.Text.Substring(0, $CursorPosition - $word.Start)
            $spanText = $word.Text
            if ($word.At) {
                $atOnly = $CursorPosition -eq $word.Start + 1
                $strandedAt = -not $atOnly
                $spanText = if ($atOnly) { '@' } else { $word.Text.Substring(1) }
            }
            break
        }
    }

    # Only elements that end at or before the cursor have actually been typed
    # to the left of it; anything further right must not classify this slot.
    $tokens = @($words |
        Where-Object { $_.End -le $CursorPosition } |
        ForEach-Object { $_.Text })
    $tokensBeforeCurrent = @($tokens)
    if (-not [string]::IsNullOrEmpty($currentWord) -and $tokensBeforeCurrent.Count -gt 0 -and $tokensBeforeCurrent[-1] -eq $currentWord) {
        $tokensBeforeCurrent = @($tokensBeforeCurrent | Select-Object -First ($tokensBeforeCurrent.Count - 1))
    }

    [pscustomobject]@{
        CurrentWord         = $currentWord
        SpanText            = $spanText
        StrandedAt          = $strandedAt
        AtOnly              = $atOnly
        TokensBeforeCurrent = $tokensBeforeCurrent
    }
}

function Get-PsExecAtFileCompletions {
    param([string]$CurrentWord, [string]$SpanText, [bool]$StrandedAt = $false)

    $trimmed = Remove-PsExecOuterQuotes -Value $CurrentWord
    if (-not $trimmed.StartsWith('@')) { return @() }
    $pathPortion = $trimmed.Substring(1)
    $parts = Split-PsExecPath -Path $pathPortion
    $parent = $parts.Parent
    $leaf = $parts.Leaf
    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $items = @(Get-ChildItem -LiteralPath $parent -Filter $filter -ErrorAction Ignore)
    $quote = Get-PsExecTypedQuote -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($item in $items) {
        $completionPath = if ($pathPortion -and -not [System.IO.Path]::IsPathRooted($pathPortion) -and $parent -ne '.') {
            Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($parent -eq '.') {
            $item.Name
        } else {
            $item.FullName
        }

        if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionPath += [System.IO.Path]::DirectorySeparatorChar
        }

        # A stranded '@' stays in the line, and only '@(' keeps it valid: it
        # passes the quoted '@path' to psexec as one argument.
        $completionText = if ($StrandedAt) {
            '(' + (ConvertTo-PsExecQuotedValue -Value ('@' + $completionPath)) + ')'
        } else {
            ConvertTo-PsExecQuotedValue -Value ('@' + $completionPath) -Quote $quote
        }
        [void]$results.Add((New-PsExecCompletionResult -CompletionText $completionText -ListItemText ('@' + $item.Name) -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.'))
    }

    if ($results.Count -eq 0) {
        return @(
            New-PsExecCompletionResult -CompletionText $SpanText -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.'
        )
    }

    @($results.ToArray())
}

function Get-PsExecExecutableCompletions {
    param([string]$CurrentWord, [string]$SpanText)

    $trimmed = Remove-PsExecOuterQuotes -Value $CurrentWord
    $quote = Get-PsExecTypedQuote -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        foreach ($sample in @('cmd.exe', 'powershell.exe', 'pwsh.exe')) {
            [void]$results.Add((New-PsExecCompletionResult -CompletionText (ConvertTo-PsExecQuotedValue -Value $sample -Quote $quote) -ResultType 'ParameterValue' -ToolTip 'Local executable or script to copy and run with -c.'))
        }
    }

    if ($trimmed.StartsWith('\\')) {
        # A UNC copy source is never enumerated: resolving the share blocks the
        # completion thread on SMB name resolution for seconds when the host is
        # unknown, and leaves a Get-ChildItem record in $Error.
        [void]$results.Add((New-PsExecCompletionResult -CompletionText $SpanText -ResultType 'ParameterValue' -ToolTip 'Network path to copy with -c; UNC paths are not enumerated during completion.'))
        return @($results.ToArray())
    }

    if ($trimmed -match '[\\/]|^\.' -or $trimmed -match '^[A-Za-z]:') {
        $parts = Split-PsExecPath -Path $trimmed
        $parent = $parts.Parent
        $leaf = $parts.Leaf
        $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
        foreach ($item in @(Get-ChildItem -LiteralPath $parent -Filter $filter -ErrorAction Ignore)) {
            $completionPath = if ($trimmed -and -not [System.IO.Path]::IsPathRooted($trimmed) -and $parent -ne '.') {
                Join-Path -Path $parent -ChildPath $item.Name
            } elseif ($parent -eq '.') {
                $item.Name
            } else {
                $item.FullName
            }

            if ($item.PSIsContainer -and -not $completionPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
                $completionPath += [System.IO.Path]::DirectorySeparatorChar
            }

            [void]$results.Add((New-PsExecCompletionResult -CompletionText (ConvertTo-PsExecQuotedValue -Value $completionPath -Quote $quote) -ResultType $(if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }) -ToolTip $item.FullName))
        }
    } else {
        foreach ($command in @(Get-Command -Name "$trimmed*" -CommandType Application -ErrorAction SilentlyContinue | Sort-Object -Property Name -Unique | Select-Object -First 20)) {
            [void]$results.Add((New-PsExecCompletionResult -CompletionText (ConvertTo-PsExecQuotedValue -Value $command.Name -Quote $quote) -ResultType 'ParameterValue' -ToolTip ($command.Source ? $command.Source : $command.Name)))
        }
    }

    if ($results.Count -eq 0) {
        $completion = if ([string]::IsNullOrWhiteSpace($SpanText)) { '<local-command>' } else { $SpanText }
        return @(
            New-PsExecCompletionResult -CompletionText $completion -ResultType 'ParameterValue' -ToolTip 'Local executable or script to copy and run with -c.'
        )
    }

    $seen = @{}
    $unique = foreach ($item in $results) {
        if ($seen.ContainsKey($item.CompletionText)) { continue }
        $seen[$item.CompletionText] = $true
        $item
    }
    @($unique)
}

function Complete-PsExec {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'WordToComplete', Justification = 'The word is cut from the CommandAst element at the cursor; a registered completer receives WordToComplete with $name expanded.')]
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    Initialize-PsExecCompletionCatalog

    $state = Get-PsExecArgumentState -CommandAst $CommandAst -CursorPosition $CursorPosition
    # Tab between a bare '@' and the path after it replaces only the '@':
    # anything else would fuse with the typed path, so keep the line as it is.
    if ($state.AtOnly) {
        return @(New-PsExecCompletionResult -CompletionText '@' -ResultType 'ParameterValue' -ToolTip 'File containing remote computer names for @file syntax.')
    }
    $currentWord = $state.CurrentWord
    $spanText = $state.SpanText
    $tokensBeforeCurrent = @($state.TokensBeforeCurrent)
    $usedSwitches = @{}
    $valueContext = $null
    $remoteTarget = $null
    $commandToken = $null
    $commandTail = @()
    $copyMode = $false
    $prioritySelected = $false

    $switchLookup = @{}
    foreach ($spec in $script:PsExecCompletionCatalog.Switches) {
        $switchLookup[$spec.Token.ToLowerInvariant()] = $spec
    }

    for ($i = 0; $i -lt $tokensBeforeCurrent.Count; $i++) {
        $token = $tokensBeforeCurrent[$i]
        $key = $token.ToLowerInvariant()

        if ($switchLookup.ContainsKey($key)) {
            $usedSwitches[$key] = $true
            $spec = $switchLookup[$key]
            if ($spec.PSObject.Properties['Group'] -and $spec.Group -eq 'Priority') { $prioritySelected = $true }
            if ($key -eq '-c') { $copyMode = $true }
            if ($spec.TakesValue) {
                # '-i [session]' takes an OPTIONAL id, so only a number consumes
                # the next token; a switch, target or program stays what it is.
                $optional = [bool]($spec.PSObject.Properties['OptionalValue'] -and $spec.OptionalValue)
                if ($i -eq ($tokensBeforeCurrent.Count - 1)) {
                    if (-not $optional -or [string]::IsNullOrEmpty($currentWord) -or $currentWord -match '^\d+$') {
                        $valueContext = $spec.ValueKind
                        break
                    }
                    continue
                }

                if (-not $optional -or $tokensBeforeCurrent[$i + 1] -match '^\d+$') {
                    $i++
                }
            }
            continue
        }

        if (-not $remoteTarget -and ((Remove-PsExecOuterQuotes -Value $token).StartsWith('\\') -or (Remove-PsExecOuterQuotes -Value $token).StartsWith('@'))) {
            $remoteTarget = $token
            continue
        }

        if (-not $commandToken) {
            $commandToken = $token
            continue
        }

        $commandTail += $token
    }

    switch ($valueContext) {
        'User' {
            return @(Expand-PsExecHint -Hints @('<username>', '<domain\user>', "$env:USERDOMAIN\$env:USERNAME") -CurrentWord $currentWord -SpanText $spanText -ToolTip 'Remote user name, Domain\User syntax when network access is needed.')
        }
        'Password' {
            $value = if ([string]::IsNullOrWhiteSpace($spanText)) { '<password>' } else { $spanText }
            return @(New-PsExecCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'Remote password value.')
        }
        'Timeout' {
            return @(Expand-PsExecHint -Hints $script:PsExecCompletionCatalog.TimeoutHints -CurrentWord $currentWord -SpanText $spanText -ToolTip 'Remote connection timeout in seconds.')
        }
        'ServiceName' {
            return @(Expand-PsExecHint -Hints @('PSEXESVC', '<service-name>') -CurrentWord $currentWord -SpanText $spanText -ToolTip 'Remote service name for PsExec (PSEXESVC is the default).')
        }
        'Session' {
            return @(Expand-PsExecHint -Hints $script:PsExecCompletionCatalog.SessionHints -CurrentWord $currentWord -SpanText $spanText -ToolTip 'Interactive session number for -i.')
        }
        'RemoteDirectory' {
            $value = if ([string]::IsNullOrWhiteSpace($spanText)) { '<remote-directory>' } else { $spanText }
            return @(New-PsExecCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'Remote working directory path for -w.')
        }
        'ProcessorGroup' {
            return @(Expand-PsExecHint -Hints $script:PsExecCompletionCatalog.GroupHints -CurrentWord $currentWord -SpanText $spanText -ToolTip 'Processor group number for -g.')
        }
        'Affinity' {
            return @(Expand-PsExecHint -Hints $script:PsExecCompletionCatalog.AffinityHints -CurrentWord $currentWord -SpanText $spanText -ToolTip 'Comma-separated CPU list for -a, where 1 is the lowest numbered CPU.')
        }
    }

    if ((Remove-PsExecOuterQuotes -Value $currentWord).StartsWith('@')) {
        return Get-PsExecAtFileCompletions -CurrentWord $currentWord -SpanText $spanText -StrandedAt $state.StrandedAt
    }

    if ($copyMode -and -not $commandToken -and [string]::IsNullOrEmpty($currentWord)) {
        return Get-PsExecExecutableCompletions -CurrentWord $currentWord -SpanText $spanText
    }

    if ($commandToken) {
        if ($copyMode -and -not $commandTail) {
            return Get-PsExecExecutableCompletions -CurrentWord $currentWord -SpanText $spanText
        }

        $argumentValue = if ([string]::IsNullOrWhiteSpace($spanText)) { '<argument>' } else { $spanText }
        return @(New-PsExecCompletionResult -CompletionText $argumentValue -ResultType 'ParameterValue' -ToolTip 'Command tail is intentionally conservative and non-enumerating.')
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and
        -not $currentWord.StartsWith('-') -and
        -not $currentWord.StartsWith('/') -and
        -not $currentWord.StartsWith('\')) {
        # 'If you omit the computer name PsExec runs the application on the
        # local system', so the local-run command slot is a local program.
        if ($copyMode -or -not $remoteTarget) {
            return Get-PsExecExecutableCompletions -CurrentWord $currentWord -SpanText $spanText
        }

        return @(
            New-PsExecCompletionResult -CompletionText $spanText -ResultType 'ParameterValue' -ToolTip 'Remote command or command path.'
            New-PsExecCompletionResult -CompletionText '<command>' -ResultType 'ParameterValue' -ToolTip 'Remote command or command path.'
        )
    }

    $results = New-Object System.Collections.Generic.List[object]
    $typedTarget = Remove-PsExecOuterQuotes -Value $currentWord
    if (-not $remoteTarget) {
        foreach ($target in @('\\<computer>', "\\$env:COMPUTERNAME", '\\localhost', '\\*', '@file')) {
            if ([string]::IsNullOrWhiteSpace($currentWord) -or $target.StartsWith($typedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-PsExecCompletionResult -CompletionText $target -ResultType 'ParameterValue' -ToolTip 'PsExec remote target placeholder.'))
            }
        }
    }

    foreach ($spec in $script:PsExecCompletionCatalog.Switches) {
        $key = $spec.Token.ToLowerInvariant()
        $isTerminal = [bool]($spec.PSObject.Properties['Terminal'] -and $spec.Terminal)
        $isPriority = [bool]($spec.PSObject.Properties['Group'] -and $spec.Group -eq 'Priority')
        if ($isTerminal -and $tokensBeforeCurrent.Count -gt 0) { continue }
        if ($usedSwitches.ContainsKey($key)) { continue }
        if (($key -in @('-f', '-v')) -and -not $copyMode) { continue }
        if (($key -in @('-u', '-p')) -and -not $remoteTarget) { continue }
        if (($key -eq '-s' -and $usedSwitches.ContainsKey('-e')) -or ($key -eq '-e' -and $usedSwitches.ContainsKey('-s'))) { continue }
        if ($isPriority -and $prioritySelected) { continue }
        if (-not [string]::IsNullOrWhiteSpace($currentWord) -and -not $spec.Token.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        [void]$results.Add((New-PsExecCompletionResult -CompletionText $spec.Token -ResultType 'ParameterName' -ToolTip $spec.Description))
    }

    if ($copyMode -and -not $currentWord.StartsWith('-')) {
        [void]$results.AddRange(@(Get-PsExecExecutableCompletions -CurrentWord $currentWord -SpanText $spanText))
    }

    if ($results.Count -eq 0 -and ($typedTarget.StartsWith('\') -or $typedTarget.StartsWith('/'))) {
        # A partially typed UNC target or slash form that matches no placeholder:
        # echo it back rather than proposing a command in a slot that cannot
        # hold one.
        $echoToolTip = if ($typedTarget.StartsWith('\')) { 'Remote computer name.' } else { 'PsExec switch or command.' }
        [void]$results.Add((New-PsExecCompletionResult -CompletionText $spanText -ResultType 'ParameterValue' -ToolTip $echoToolTip))
    }

    @($results.ToArray())
}


Register-ArgumentCompleter -Native -CommandName @('psexec', 'psexec.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsExec -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
