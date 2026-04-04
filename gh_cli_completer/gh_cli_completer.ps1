<#
.SYNOPSIS
Registers GitHub CLI (`gh`) tab-completion through the installed `gh` executable.

.DESCRIPTION
This script registers importer-safe native completers for `gh` and `gh.exe`.
The generated completion script is resolved lazily at completion time, cached,
and then invoked through the installed GitHub CLI's own PowerShell completer.

Run once per session, or dot-source it from your PowerShell profile.
#>

Set-StrictMode -Version Latest

function Get-GhCliCommandPath {
    foreach ($commandName in @('gh', 'gh.exe')) {
        $ghCommand = Get-Command -Name $commandName -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -ne $ghCommand) {
            return $ghCommand.Source
        }
    }
}

function Get-GhCliGeneratedCompletionScript {
    $ghCommandPath = Get-GhCliCommandPath
    if ([string]::IsNullOrWhiteSpace($ghCommandPath)) {
        Write-Error "GitHub CLI (gh) was not found in PATH. Install gh and restart PowerShell."
        return
    }

    try {
        $completionScript = & $ghCommandPath completion -s powershell | Out-String

        if ([string]::IsNullOrWhiteSpace($completionScript)) {
            Write-Error "gh returned an empty completion script. Check your gh installation by running: gh --version"
            return
        }

        return $completionScript
    } catch {
        Write-Error ("Failed to load gh completion: {0}" -f $_.Exception.Message)
    }
}

function Get-GhCliCompletionInvoker {
    $cachedInvoker = Get-Variable -Name GhCliCompletionInvoker -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $cachedInvoker) {
        return $cachedInvoker.Value
    }

    $completionScript = Get-GhCliGeneratedCompletionScript
    if ([string]::IsNullOrWhiteSpace($completionScript)) {
        return
    }

    $completionScript = $completionScript -replace (
        "(?m)^\s*Register-ArgumentCompleter\s+-CommandName\s+'gh'\s+-ScriptBlock\s+\$\{__ghCompleterBlock\}\s*\r?$"
    ), ''

    $completionInvokerSource = @"
$completionScript

& `${__ghCompleterBlock} @args
"@

    try {
        $script:GhCliCompletionInvoker = [scriptblock]::Create($completionInvokerSource)
        return $script:GhCliCompletionInvoker
    } catch {
        Write-Error ("Failed to prepare gh completion: {0}" -f $_.Exception.Message)
    }
}

function Invoke-GhCliCompletion {
    [CmdletBinding()]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $completionInvoker = Get-GhCliCompletionInvoker
    if ($null -eq $completionInvoker) {
        return
    }

    & $completionInvoker $wordToComplete $commandAst $cursorPosition
}

Register-ArgumentCompleter -Native -CommandName @('gh', 'gh.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-GhCliCompletion -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
