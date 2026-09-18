<#
.SYNOPSIS
Registers PowerShell tab completion for the local `codex` CLI.

.DESCRIPTION
This completer is a thin, importer-safe wrapper around the PowerShell
completion script emitted by `codex completion powershell`.

The generated completion script is loaded lazily on first completion request,
its built-in self-registration is rewritten into an invokable script block,
and that script block is cached for the rest of the session.

This script registers completion for `codex`, `codex.cmd`, and `codex.ps1`
because all three launcher names can be relevant on Windows.
#>

Set-StrictMode -Version Latest

function Get-CodexCompletionExecutablePath {
    $pathProbeComplete = Get-Variable -Name CodexCompletionExecutablePathProbed -Scope Script -ErrorAction Ignore
    if ($null -ne $pathProbeComplete -and $pathProbeComplete.Value) {
        $cachedPath = Get-Variable -Name CodexCompletionExecutablePath -Scope Script -ErrorAction Ignore
        if ($null -ne $cachedPath) {
            return $cachedPath.Value
        }

        return $null
    }

    $script:CodexCompletionExecutablePathProbed = $true
    $script:CodexCompletionExecutablePath = $null

    foreach ($candidate in @(
            @{ Name = 'codex.cmd'; CommandType = 'Application' }
            @{ Name = 'codex'; CommandType = 'Application' }
            @{ Name = 'codex.ps1'; CommandType = 'ExternalScript' }
        )) {
        $command = Get-Command -Name $candidate.Name -CommandType $candidate.CommandType -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -eq $command) {
            continue
        }

        $script:CodexCompletionExecutablePath = if ($command.Source) { $command.Source } else { $command.Path }
        break
    }

    $script:CodexCompletionExecutablePath
}

function Get-CodexGeneratedCompletionScript {
    $codexExecutablePath = Get-CodexCompletionExecutablePath
    if ([string]::IsNullOrWhiteSpace($codexExecutablePath)) {
        return
    }

    try {
        $completionScript = & $codexExecutablePath completion powershell 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String
    } catch {
        return
    }

    if ([string]::IsNullOrWhiteSpace($completionScript)) {
        return
    }

    $completionScript
}

function ConvertTo-CodexCompletionInvokerSource {
    param([string]$CompletionScript)

    if ([string]::IsNullOrWhiteSpace($CompletionScript)) {
        return
    }

    $registerPattern = '(?m)^\s*Register-ArgumentCompleter\s+-Native\s+-CommandName\s+[''"]codex[''"]\s+-ScriptBlock\s+\{\s*$'
    $rewrittenScript = [regex]::Replace(
        $CompletionScript,
        $registerPattern,
        { param($match) '$__codexCompleterBlock = {' },
        1
    )

    if ($rewrittenScript -eq $CompletionScript) {
        return
    }

@"
$rewrittenScript

& `$__codexCompleterBlock @args
"@
}

function Get-CodexCompletionInvoker {
    $cachedInvoker = Get-Variable -Name CodexCompletionInvoker -Scope Script -ErrorAction Ignore
    if ($null -ne $cachedInvoker) {
        return $cachedInvoker.Value
    }

    $completionScript = Get-CodexGeneratedCompletionScript
    if ([string]::IsNullOrWhiteSpace($completionScript)) {
        return
    }

    $completionInvokerSource = ConvertTo-CodexCompletionInvokerSource -CompletionScript $completionScript
    if ([string]::IsNullOrWhiteSpace($completionInvokerSource)) {
        return
    }

    try {
        $script:CodexCompletionInvoker = [scriptblock]::Create($completionInvokerSource)
        return $script:CodexCompletionInvoker
    } catch {
        return
    }
}

function Get-CodexValueCompletion {
    <#
    .SYNOPSIS
    Value overlay for slots the clap-generated script leaves empty: closed
    enum options, directory options, and the 'completion <SHELL>' positional.
    #>
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $enumValues = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::Ordinal)
    $enumValues['-s'] = @('read-only', 'workspace-write', 'danger-full-access')
    $enumValues['--sandbox'] = $enumValues['-s']
    $enumValues['-a'] = @('on-request', 'never')
    $enumValues['--ask-for-approval'] = $enumValues['-a']
    $enumValues['--local-provider'] = @('lmstudio', 'ollama')
    $enumValues['--color'] = @('always', 'never', 'auto')

    $directoryOptions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($name in @('-C', '--cd', '--add-dir')) { [void]$directoryOptions.Add($name) }

    $committed = @(
        $CommandAst.CommandElements |
            Select-Object -Skip 1 |
            Where-Object { $_.Extent.EndOffset -lt $CursorPosition } |
            ForEach-Object { $_.Extent.Text }
    )
    $previousToken = if ($committed.Count -gt 0) { $committed[-1] } else { '' }
    $node = 'codex'
    foreach ($token in $committed) {
        if ($token.StartsWith('-')) {
            break
        }

        $node += ';' + $token
    }

    $optionName = $null
    $valuePrefix = ''
    $valueWord = $WordToComplete
    if ($WordToComplete -match '^(?<option>--?[A-Za-z][A-Za-z0-9-]*)=(?<value>.*)$') {
        $optionName = $Matches.option
        $valuePrefix = $optionName + '='
        $valueWord = $Matches.value
    } elseif ($previousToken.StartsWith('-')) {
        $optionName = $previousToken
    }

    if ($optionName) {
        if ($enumValues.ContainsKey($optionName)) {
            return @(foreach ($value in $enumValues[$optionName]) {
                if ($value.StartsWith($valueWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [System.Management.Automation.CompletionResult]::new($valuePrefix + $value, $value, 'ParameterValue', $value)
                }
            })
        }

        if ($directoryOptions.Contains($optionName)) {
            return @(foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($valueWord)) {
                if ($item.ResultType -ne [System.Management.Automation.CompletionResultType]::ProviderContainer) {
                    continue
                }

                if ($valuePrefix) {
                    [System.Management.Automation.CompletionResult]::new($valuePrefix + $item.CompletionText, $item.ListItemText, $item.ResultType, $item.ToolTip)
                } else {
                    $item
                }
            })
        }

        return @()
    }

    if ($node -eq 'codex;completion' -and -not $WordToComplete.StartsWith('-')) {
        return @(foreach ($shell in @('bash', 'elvish', 'fish', 'powershell', 'zsh')) {
            if ($shell.StartsWith($WordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                [System.Management.Automation.CompletionResult]::new($shell, $shell, 'ParameterValue', "Generate $shell completions")
            }
        })
    }

    @()
}

function Invoke-CodexCompletion {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $valueResults = @(Get-CodexValueCompletion -WordToComplete $WordToComplete -CommandAst $CommandAst -CursorPosition $CursorPosition)
    if ($valueResults.Count -gt 0) {
        $valueResults
        return
    }

    $completionInvoker = Get-CodexCompletionInvoker
    if ($null -eq $completionInvoker) {
        return
    }

    & $completionInvoker $WordToComplete $CommandAst $CursorPosition
}

Register-ArgumentCompleter -Native -CommandName @('codex', 'codex.cmd', 'codex.ps1') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-CodexCompletion -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
