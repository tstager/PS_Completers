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
    $pathProbeComplete = Get-Variable -Name CodexCompletionExecutablePathProbed -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $pathProbeComplete -and $pathProbeComplete.Value) {
        $cachedPath = Get-Variable -Name CodexCompletionExecutablePath -Scope Script -ErrorAction SilentlyContinue
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
        $completionScript = & $codexExecutablePath completion powershell 2>$null | Out-String
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
    $cachedInvoker = Get-Variable -Name CodexCompletionInvoker -Scope Script -ErrorAction SilentlyContinue
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

function Invoke-CodexCompletion {
    [CmdletBinding()]
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

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
