<#
.SYNOPSIS
Loads official PowerShell tab-completion for GitHub CLI (`gh`).

.DESCRIPTION
This script asks `gh` to emit its native PowerShell completer and
evaluates it in the current session.

Run once per session, or dot-source it from your PowerShell profile.
#>

Set-StrictMode -Version Latest

try {
    $ghCommand = Get-Command -Name gh -ErrorAction Stop
} catch {
    Write-Error "GitHub CLI (gh) was not found in PATH. Install gh and restart PowerShell."
    return
}

try {
    $completionScript = & $ghCommand.Source completion -s powershell | Out-String

    if ([string]::IsNullOrWhiteSpace($completionScript)) {
        Write-Error "gh returned an empty completion script. Check your gh installation by running: gh --version"
        return
    }

    Invoke-Expression $completionScript
    Write-Verbose "gh tab completion loaded." 
} catch {
    Write-Error ("Failed to load gh completion: {0}" -f $_.Exception.Message)
}