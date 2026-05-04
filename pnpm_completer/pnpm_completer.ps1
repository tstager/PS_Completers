<#
.SYNOPSIS
Registers PowerShell tab completion for the local `pnpm` CLI.

.DESCRIPTION
This completer is a thin, importer-safe wrapper around the PowerShell
completion script emitted by `pnpm completion pwsh`.

The generated completion script is loaded lazily on first completion request,
its built-in self-registration is rewritten into an invokable script block,
and that script block is cached for the rest of the session.

When the upstream completion engine does not return results, a small lazy
help-based fallback supplies root commands plus selected nested command and
option suggestions.

This script registers completion for `pnpm`, `pnpm.cmd`, and `pnpm.ps1`
because all three launcher names can be relevant on Windows.
#>

Set-StrictMode -Version Latest

function Get-PnpmCompletionExecutablePath {
    $pathProbeComplete = Get-Variable -Name PnpmCompletionExecutablePathProbed -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $pathProbeComplete -and $pathProbeComplete.Value) {
        $cachedPath = Get-Variable -Name PnpmCompletionExecutablePath -Scope Script -ErrorAction SilentlyContinue
        if ($null -ne $cachedPath) {
            return $cachedPath.Value
        }

        return $null
    }

    $script:PnpmCompletionExecutablePathProbed = $true
    $script:PnpmCompletionExecutablePath = $null

    foreach ($candidate in @(
            @{ Name = 'pnpm.cmd'; CommandType = 'Application' }
            @{ Name = 'pnpm'; CommandType = 'Application' }
            @{ Name = 'pnpm.ps1'; CommandType = 'ExternalScript' }
        )) {
        $command = Get-Command -Name $candidate.Name -CommandType $candidate.CommandType -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -eq $command) {
            continue
        }

        $script:PnpmCompletionExecutablePath = if ($command.Source) { $command.Source } else { $command.Path }
        break
    }

    $script:PnpmCompletionExecutablePath
}

function Get-PnpmGeneratedCompletionScript {
    $pnpmExecutablePath = Get-PnpmCompletionExecutablePath
    if ([string]::IsNullOrWhiteSpace($pnpmExecutablePath)) {
        return
    }

    try {
        $completionScript = & $pnpmExecutablePath completion pwsh 2>$null | Out-String
    } catch {
        return
    }

    if ([string]::IsNullOrWhiteSpace($completionScript)) {
        return
    }

    $completionScript
}

function ConvertTo-PnpmCompletionInvokerSource {
    param([string]$CompletionScript)

    if ([string]::IsNullOrWhiteSpace($CompletionScript)) {
        return
    }

    $registerPattern = '(?m)^\s*Register-ArgumentCompleter(?:\s+-Native)?\s+-CommandName\s+[''"]pnpm[''"]\s+-ScriptBlock\s+\{\s*$'
    $rewrittenScript = [regex]::Replace(
        $CompletionScript,
        $registerPattern,
        { param($match) '$__pnpmCompleterBlock = {' },
        1
    )

    if ($rewrittenScript -eq $CompletionScript) {
        return
    }

@"
$rewrittenScript

& `$__pnpmCompleterBlock @args
"@
}

function Get-PnpmCompletionInvoker {
    $cachedInvoker = Get-Variable -Name PnpmCompletionInvoker -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $cachedInvoker) {
        return $cachedInvoker.Value
    }

    $completionScript = Get-PnpmGeneratedCompletionScript
    if ([string]::IsNullOrWhiteSpace($completionScript)) {
        return
    }

    $completionInvokerSource = ConvertTo-PnpmCompletionInvokerSource -CompletionScript $completionScript
    if ([string]::IsNullOrWhiteSpace($completionInvokerSource)) {
        return
    }

    try {
        $loadCount = Get-Variable -Name PnpmCompletionInvokerLoadCount -Scope Script -ErrorAction SilentlyContinue
        if ($null -eq $loadCount) {
            $script:PnpmCompletionInvokerLoadCount = 0
        }

        $script:PnpmCompletionInvoker = [scriptblock]::Create($completionInvokerSource)
        $script:PnpmCompletionInvokerLoadCount = [int]$script:PnpmCompletionInvokerLoadCount + 1
        return $script:PnpmCompletionInvoker
    } catch {
        return
    }
}

function New-PnpmCompletionResult {
    param(
        [Parameter(Mandatory)]
        [string]$CompletionText,

        [Parameter(Mandatory)]
        [System.Management.Automation.CompletionResultType]$ResultType,

        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new($CompletionText, $CompletionText, $ResultType, $ToolTip)
}

function Expand-PnpmOptionToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return @()
    }

    if ($Token -match '\[no-\]') {
        $positive = $Token -replace '\[no-\]', ''
        $negative = $Token -replace '\[no-\]', 'no-'
        return @($positive, $negative)
    }

    @($Token)
}

function Get-PnpmHelpText {
    param([string[]]$Arguments)

    $pnpmExecutablePath = Get-PnpmCompletionExecutablePath
    if ([string]::IsNullOrWhiteSpace($pnpmExecutablePath)) {
        return
    }

    try {
        $helpText = & $pnpmExecutablePath @Arguments 2>$null | Out-String
    } catch {
        return
    }

    if ([string]::IsNullOrWhiteSpace($helpText)) {
        return
    }

    $helpText
}

function Get-PnpmRootCommandEntries {
    $cachedEntries = Get-Variable -Name PnpmRootCommandEntries -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $cachedEntries) {
        return $cachedEntries.Value
    }

    $helpText = Get-PnpmHelpText -Arguments @('help', '-a')
    if ([string]::IsNullOrWhiteSpace($helpText)) {
        return @()
    }

    $entries = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($line in ($helpText -split '\r?\n')) {
        if ($line -notmatch '^\s{2,}(?<field>[A-Za-z0-9][A-Za-z0-9,\- ]*[A-Za-z0-9])\s{2,}(?<description>\S.*)$') {
            continue
        }

        $names = @(
            $Matches.field.Split(',') |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )

        if ($names.Count -eq 0) {
            continue
        }

        $canonicalName = $names[-1]

        foreach ($name in $names) {
            if (-not $seen.Add($name)) {
                continue
            }

            $entries.Add([pscustomobject]@{
                    Name         = $name
                    CanonicalName = $canonicalName
                    Description  = $Matches.description
                })
        }
    }

    $script:PnpmRootCommandEntries = $entries.ToArray()
    $script:PnpmRootCommandEntries
}

function Resolve-PnpmCommandName {
    param([string]$CommandName)

    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        return $null
    }

    foreach ($entry in (Get-PnpmRootCommandEntries)) {
        if ($entry.Name -ieq $CommandName) {
            return $entry.CanonicalName
        }
    }

    $CommandName
}

function Get-PnpmCommandHelpEntry {
    param([string]$CommandName)

    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        return $null
    }

    $resolvedCommandName = Resolve-PnpmCommandName -CommandName $CommandName
    if ([string]::IsNullOrWhiteSpace($resolvedCommandName)) {
        return $null
    }

    $cacheVariable = Get-Variable -Name PnpmCommandHelpCache -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $cacheVariable) {
        $script:PnpmCommandHelpCache = @{}
    }

    if ($script:PnpmCommandHelpCache.ContainsKey($resolvedCommandName)) {
        return $script:PnpmCommandHelpCache[$resolvedCommandName]
    }

    $helpText = Get-PnpmHelpText -Arguments @('help', $resolvedCommandName)
    if ([string]::IsNullOrWhiteSpace($helpText)) {
        $script:PnpmCommandHelpCache[$resolvedCommandName] = $null
        return $null
    }

    $commandEntries = New-Object System.Collections.Generic.List[object]
    $optionEntries = New-Object System.Collections.Generic.List[object]
    $commandSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $optionSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $section = ''

    foreach ($line in ($helpText -split '\r?\n')) {
        switch -Regex ($line) {
            '^\s*Commands:\s*$' {
                $section = 'Commands'
                continue
            }
            '^\s*Options:\s*$' {
                $section = 'Options'
                continue
            }
            '^\s*$' {
                continue
            }
        }

        if ($section -eq 'Commands' -and $line -match '^\s{2,}(?<field>\S(?:.*\S)?)\s{2,}(?<description>\S.*)$') {
            $commandToken = ($Matches.field -split '\s+')[0]
            if (-not [string]::IsNullOrWhiteSpace($commandToken) -and $commandSeen.Add($commandToken)) {
                $commandEntries.Add([pscustomobject]@{
                        Name        = $commandToken
                        Description = $Matches.description
                    })
            }

            continue
        }

        if ($section -eq 'Options' -and $line -match '^\s{2,}(?<field>(?:-[^,\s]+,\s*)?(?:--?[^\s]+(?:\s+<[^>]+>)?|\S+))\s{2,}(?<description>\S.*)$') {
            $switchTokens = @(
                [regex]::Matches($Matches.field, '(?<!\S)-{1,2}[^\s,]+') |
                    ForEach-Object { $_.Value }
            )

            foreach ($switchToken in $switchTokens) {
                foreach ($expandedToken in (Expand-PnpmOptionToken -Token $switchToken)) {
                    if (-not [string]::IsNullOrWhiteSpace($expandedToken) -and $optionSeen.Add($expandedToken)) {
                        $optionEntries.Add([pscustomobject]@{
                                Name        = $expandedToken
                                Description = $Matches.description
                            })
                    }
                }
            }
        }
    }

    $entry = [pscustomobject]@{
        Commands = $commandEntries.ToArray()
        Options  = $optionEntries.ToArray()
    }

    $script:PnpmCommandHelpCache[$resolvedCommandName] = $entry
    $entry
}

function Get-PnpmFallbackContext {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $commandText = $CommandAst.Extent.Text
    $commandTextLength = $commandText.Length
    if ($commandTextLength -gt $CursorPosition) {
        $commandText = $commandText.Substring(0, $CursorPosition)
    }

    $hasTrailingSpace = ($WordToComplete -eq '') -and ($CursorPosition -gt $commandTextLength -or $commandText -match '\s$')
    [string[]]$tokens = @(
        $commandText -split '\s+' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    [string[]]$arguments = if ($tokens.Count -gt 1) {
        @($tokens[1..($tokens.Count - 1)])
    } else {
        @()
    }

    [pscustomobject]@{
        HasTrailingSpace = $hasTrailingSpace
        Tokens           = $tokens
        Arguments        = $arguments
        CurrentWord      = $WordToComplete
        PreviousArgument = if ($arguments.Count -gt 0) { $arguments[-1] } else { $null }
        FirstArgument    = if ($arguments.Count -gt 0) { $arguments[0] } else { $null }
    }
}

function Get-PnpmFallbackCompletion {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $context = Get-PnpmFallbackContext -WordToComplete $WordToComplete -CommandAst $CommandAst -CursorPosition $CursorPosition
    if ($context.Tokens.Count -eq 0) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    $isRootPosition = $context.Arguments.Count -eq 0 -or (
        $context.Arguments.Count -eq 1 -and
        -not $context.HasTrailingSpace -and
        $context.FirstArgument.StartsWith($WordToComplete, [System.StringComparison]::OrdinalIgnoreCase)
    )

    if ($isRootPosition) {
        foreach ($rootOption in @(
                @{ Name = '-h'; Description = 'Output usage information' }
                @{ Name = '--help'; Description = 'Output usage information' }
                @{ Name = '-v'; Description = 'Show version number' }
                @{ Name = '--version'; Description = 'Show version number' }
            )) {
            if ($rootOption.Name.StartsWith($WordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                $results.Add((New-PnpmCompletionResult -CompletionText $rootOption.Name -ResultType ParameterName -ToolTip $rootOption.Description))
            }
        }

        foreach ($entry in (Get-PnpmRootCommandEntries)) {
            if ($entry.Name.StartsWith($WordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                $results.Add((New-PnpmCompletionResult -CompletionText $entry.Name -ResultType ParameterValue -ToolTip $entry.Description))
            }
        }

        return @($results)
    }

    $commandEntry = Get-PnpmCommandHelpEntry -CommandName $context.FirstArgument
    if ($null -eq $commandEntry) {
        return @()
    }

    $isNestedSubcommandPosition = (
        $context.Arguments.Count -eq 1 -and $context.HasTrailingSpace
    ) -or (
        $context.Arguments.Count -eq 2 -and -not $WordToComplete.StartsWith('-')
    )

    if ($isNestedSubcommandPosition) {
        foreach ($entry in $commandEntry.Commands) {
            if ($entry.Name.StartsWith($WordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                $results.Add((New-PnpmCompletionResult -CompletionText $entry.Name -ResultType ParameterValue -ToolTip $entry.Description))
            }
        }
    }

    if (
        $WordToComplete.StartsWith('-') -or
        ($context.Arguments.Count -eq 1 -and $context.HasTrailingSpace) -or
        $context.Arguments.Count -eq 2
    ) {
        foreach ($entry in $commandEntry.Options) {
            if ($entry.Name.StartsWith($WordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                $results.Add((New-PnpmCompletionResult -CompletionText $entry.Name -ResultType ParameterName -ToolTip $entry.Description))
            }
        }
    }

    @($results)
}

function Invoke-PnpmCompletion {
    [CmdletBinding()]
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $completionInvoker = Get-PnpmCompletionInvoker
    if ($null -ne $completionInvoker) {
        $upstreamResults = @(
            & $completionInvoker $WordToComplete $CommandAst $CursorPosition |
                Where-Object { $null -ne $_ }
        )

        if ($upstreamResults.Count -gt 0) {
            return $upstreamResults
        }
    }

    Get-PnpmFallbackCompletion -WordToComplete $WordToComplete -CommandAst $CommandAst -CursorPosition $CursorPosition
}

Register-ArgumentCompleter -Native -CommandName @('pnpm', 'pnpm.cmd', 'pnpm.ps1') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-PnpmCompletion -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
