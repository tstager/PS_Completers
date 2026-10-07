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
        $completionScript = $null | & $sbxCommandPath completion powershell 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String

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

function Get-SbxFlagValueSlot {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # Closed value sets that 'sbx <command> --help' documents but cobra does not register.
    # --skills and --pull exist only for local sandboxes, so they are dropped under --cloud.
    $valueSets = @{
        'run --on-timeout'    = 'stop', 'restart', 'delete'
        'run --platform'      = 'linux/amd64', 'linux/arm64'
        'run --skills'        = 'off', 'readonly', 'readwrite'
        'run --pull'          = 'always', 'missing', 'never'
        'create --on-timeout' = 'stop', 'restart', 'delete'
        'create --platform'   = 'linux/amd64', 'linux/arm64'
        'create --skills'     = 'off', 'readonly', 'readwrite'
        'create --pull'       = 'always', 'missing', 'never'
        'move --to'           = 'local', 'cloud'
        'move --on-timeout'   = 'stop', 'delete'
    }
    $localOnlyFlags = '--skills', '--pull'

    $elements = @($CommandAst.CommandElements | Select-Object -Skip 1)
    $preceding = @($elements | Where-Object { $_.Extent.EndOffset -lt $CursorPosition } | ForEach-Object { $_.Extent.Text })
    $current = $elements | Where-Object { $_.Extent.StartOffset -lt $CursorPosition -and $_.Extent.EndOffset -ge $CursorPosition } | Select-Object -First 1
    $typed = if ($null -ne $current) { $current.Extent.Text.Substring(0, $CursorPosition - $current.Extent.StartOffset) } else { '' }

    # Everything after a bare '--' belongs to the agent; root flags take no value, so the first bare word is the command.
    if ($preceding -ccontains '--') {
        return $null
    }
    $command = $preceding | Where-Object { -not $_.StartsWith('-') } | Select-Object -First 1
    if ($null -eq $command) {
        return $null
    }

    $attached = $typed -cmatch '^(--[a-z-]+=)(.*)$'
    if ($attached) {
        $flag = $Matches[1].TrimEnd('=')
        $prefix = $Matches[1]
        $valueText = $Matches[2]
    } elseif ($preceding.Count -gt 0 -and -not $typed.StartsWith('-')) {
        $flag = $preceding[-1]
        $prefix = ''
        $valueText = $typed
    } else {
        return $null
    }

    $values = $valueSets["$command $flag"]
    if ($null -eq $values -or (($preceding -ccontains '--cloud') -and $localOnlyFlags -ccontains $flag)) {
        return $null
    }

    $quote = if ($valueText.Length -gt 0 -and $valueText[0] -in "'", '"') { [string]$valueText[0] } else { '' }
    [pscustomobject]@{
        Attached = $attached
        Prefix   = $prefix
        Quote    = $quote
        Value    = $valueText.Substring($quote.Length)
        Values   = $values
    }
}

function Get-SbxFlagValueCompletion {
    param([psobject]$Slot)

    foreach ($value in $Slot.Values) {
        if ($value.StartsWith($Slot.Value, [System.StringComparison]::OrdinalIgnoreCase)) {
            $completionText = '{0}{1}{2}{1}' -f $Slot.Prefix, $Slot.Quote, $value
            [System.Management.Automation.CompletionResult]::new($completionText, $value, 'ParameterValue', $value)
        }
    }
}

function Invoke-SbxCompletion {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $flagValueSlot = Get-SbxFlagValueSlot -CommandAst $commandAst -CursorPosition $cursorPosition

    # cobra has no values for an attached '--flag=' here, and its block faults on that empty answer.
    if ($null -ne $flagValueSlot -and $flagValueSlot.Attached) {
        return Get-SbxFlagValueCompletion -Slot $flagValueSlot
    }

    $results = @()
    $completionInvoker = Get-SbxCompletionInvoker
    if ($null -ne $completionInvoker) {
        # cobra's block lets the child process's 'Completion ended with directive' banner reach stderr;
        # redirecting the whole invocation keeps the console clean. Its "" sentinel
        # (ShellCompDirectiveNoFileComp) is dropped: PowerShell rejects an empty completion text.
        try {
            $results = @(& $completionInvoker $wordToComplete $commandAst $cursorPosition 2>$null |
                    Where-Object { -not ($_ -is [string] -and $_.Length -eq 0) })
        } catch {
            Write-Verbose ("sbx completion block failed: {0}" -f $_.Exception.Message)
        }
    }

    if ($results.Count -eq 0 -and $null -ne $flagValueSlot) {
        return Get-SbxFlagValueCompletion -Slot $flagValueSlot
    }

    $results
}

Register-ArgumentCompleter -Native -CommandName @('sbx', 'sbx.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-SbxCompletion -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
