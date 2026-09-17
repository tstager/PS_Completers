<#
.SYNOPSIS
Registers Docker Sandboxes (`sbx`) tab-completion through the installed `sbx` executable.

.DESCRIPTION
This script registers importer-safe native completers for `sbx` and `sbx.exe`.
The generated completion script (`sbx completion powershell`) is resolved lazily
at completion time, cached, and then invoked through the installed Docker
Sandboxes CLI's own PowerShell completer, so subcommands, flags and sandbox
names always match the installed `sbx` version.

Run once per session, or dot-source it from your PowerShell profile.
#>

Set-StrictMode -Version Latest

function Get-SbxCommandPath {
    $cachedPath = Get-Variable -Name SbxCommandPath -Scope Script -ErrorAction Ignore
    if ($null -ne $cachedPath) {
        return $cachedPath.Value
    }

    $sbxCommand = Get-Command -Name 'sbx', 'sbx.exe' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    $script:SbxCommandPath = if ($null -ne $sbxCommand) { $sbxCommand.Source } else { $null }
    $script:SbxCommandPath
}

function Get-SbxGeneratedCompletionScript {
    # A completion callback must stay silent: diagnostics go to the verbose stream only.
    $sbxCommandPath = Get-SbxCommandPath
    if ([string]::IsNullOrWhiteSpace($sbxCommandPath)) {
        Write-Verbose 'Docker Sandboxes CLI (sbx) was not found in PATH.'
        return $null
    }

    try {
        $completionScript = $null | & $sbxCommandPath completion powershell 2>$null | Out-String

        if ([string]::IsNullOrWhiteSpace($completionScript)) {
            Write-Verbose 'sbx returned an empty completion script.'
            return $null
        }

        return $completionScript
    } catch {
        Write-Verbose ("Failed to load sbx completion: {0}" -f $_.Exception.Message)
        $null
    }
}

function Get-SbxCompletionInvoker {
    $cachedInvoker = Get-Variable -Name SbxCompletionInvoker -Scope Script -ErrorAction Ignore
    if ($null -ne $cachedInvoker) {
        return $cachedInvoker.Value
    }

    # A failed discovery is cached too, so a machine without sbx pays for it once per session.
    if (Get-Variable -Name SbxCompletionUnavailable -Scope Script -ErrorAction Ignore) {
        return $null
    }

    $completionScript = Get-SbxGeneratedCompletionScript
    if ([string]::IsNullOrWhiteSpace($completionScript)) {
        $script:SbxCompletionUnavailable = $true
        return $null
    }

    # The upstream script registers only the bare 'sbx' name; registration is owned by this file.
    $completionScript = $completionScript -replace (
        "(?m)^\s*Register-ArgumentCompleter\s+-CommandName\s+'sbx'\s+-ScriptBlock\s+\$\{__sbxCompleterBlock\}\s*\r?$"
    ), ''

    # With no suggestions and the default directive (file completion allowed, e.g. 'sbx cp <path>')
    # $Values is $null, and '$null | ForEach-Object' still runs once, so the block would build a
    # CompletionResult from a null name and leave an exception in $Error on every such Tab.
    $completionScript = $completionScript -replace (
        '(?m)^(\s*)\$Values \| ForEach-Object \{\s*$'
    ), '$1$$Values | Where-Object { $$null -ne $$_ } | ForEach-Object {'

    # cobra's block dereferences properties of an empty pipeline when there are no suggestions; run it
    # outside this script's strict mode so those accesses stay silent.
    $completionInvokerSource = @"
Set-StrictMode -Off
$completionScript

& `${__sbxCompleterBlock} @args
"@

    try {
        $script:SbxCompletionInvoker = [scriptblock]::Create($completionInvokerSource)
        return $script:SbxCompletionInvoker
    } catch {
        Write-Verbose ("Failed to prepare sbx completion: {0}" -f $_.Exception.Message)
        $script:SbxCompletionUnavailable = $true
        $null
    }
}

function Invoke-SbxCompletion {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $completionInvoker = Get-SbxCompletionInvoker
    if ($null -eq $completionInvoker) {
        return
    }

    # cobra's block lets the child process's 'Completion ended with directive' banner reach stderr;
    # redirecting the whole invocation keeps the console clean. Its "" sentinel
    # (ShellCompDirectiveNoFileComp) and empty output are passed through unchanged.
    try {
        @(& $completionInvoker $wordToComplete $commandAst $cursorPosition 2>$null)
    } catch {
        Write-Verbose ("sbx completion block failed: {0}" -f $_.Exception.Message)
    }
}

Register-ArgumentCompleter -Native -CommandName @('sbx', 'sbx.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-SbxCompletion -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
