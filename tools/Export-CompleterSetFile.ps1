#Requires -Modules @{ ModuleName = 'CompleterActions'; ModuleVersion = '2.0.0' }

<#
.SYNOPSIS
Regenerates ps_completers.psd1 from every completer script in this repository.

.DESCRIPTION
Registers each *_completer.ps1 lazily, which derives its targets from the
parsed script without executing it, then exports the resulting registrations
as a completer set at the repository root. Run it in a profile-free process
after adding or changing a completer:

    pwsh -NoProfile -File ./tools/Export-CompleterSetFile.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$setPath = Join-Path -Path $repoRoot -ChildPath 'ps_completers.psd1'

$scripts = Get-ChildItem -Path $repoRoot -Directory -Filter '*_completer' |
    Get-ChildItem -Filter '*_completer.ps1' -File |
    Sort-Object -Property FullName

$registrations = foreach ($script in $scripts)
{
    Register-CompleterRegistration -LiteralPath $script.FullName -Lazy -Force -PassThru -Confirm:$false
}

$registrations | Export-CompleterSet -Path $setPath -Confirm:$false

$entryCount = @((Import-PowerShellDataFile -LiteralPath $setPath).Entries).Count
"Wrote $entryCount entries for $($scripts.Count) scripts to $setPath"
