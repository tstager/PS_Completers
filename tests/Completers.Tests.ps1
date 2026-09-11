#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
.SYNOPSIS
Conformance gate for the completer scripts in this repository.

.DESCRIPTION
Runs Test-CompleterScript from CompleterActions 1.4.0 or later over every
*_completer.ps1 script and fails on any Error finding. Nothing is executed;
the check is static. Run it in its own profile-free process:

    pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent

    $script:completerScripts = @(
        Get-ChildItem -Path $repoRoot -Directory -Filter '*_completer' |
            Get-ChildItem -Filter '*_completer.ps1' -File |
            Sort-Object -Property Name |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    )
}

Describe 'Completer scripts conform to the CompleterActions strict import grammar' {
    BeforeAll {
        Import-Module -Name CompleterActions -MinimumVersion 1.4.0 -ErrorAction Stop
    }

    It 'discovers the completer scripts' {
        $completerScripts.Count | Should -BeGreaterThan 0
    }

    It '<Name> has no Error findings' -ForEach $completerScripts {
        $findings = @(Test-CompleterScript -LiteralPath $Path | Where-Object -Property Severity -EQ -Value 'Error')

        $because = ($findings | ForEach-Object { "line $($_.Line), column $($_.Column) ($($_.Construct)): $($_.Message) $($_.Hint)" }) -join '; '
        $findings | Should -BeNullOrEmpty -Because $because
    }
}
