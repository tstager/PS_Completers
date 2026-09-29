#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
.SYNOPSIS
Conformance gate for the completer scripts in this repository.

.DESCRIPTION
Runs Test-CompleterScript over every *_completer.ps1 script and fails on any
Error finding, then runs Test-CompleterSet over ps_completers.psd1 and fails on
any drift between the set and the scripts on disk (missing or unlisted
scripts, stale hashes, target mismatches). Nothing is executed and nothing is
registered; both checks are static. Needs CompleterActions 2.1.0-preview1 or
later. Run it in its own profile-free process:

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
        Import-Module -Name CompleterActions -MinimumVersion 2.0.0 -ErrorAction Stop
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

Describe 'ps_completers.psd1 matches the repository' {
    BeforeAll {
        Import-Module -Name CompleterActions -MinimumVersion 2.1.0 -ErrorAction Stop

        $script:SetPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'ps_completers.psd1'
    }

    It 'keeps every entry on the strict tier' {
        $set = Import-PowerShellDataFile -LiteralPath $script:SetPath

        @($set.Entries | Where-Object { $_.Trusted }) | Should -BeNullOrEmpty -Because 'every script passes the strict grammar, so no entry needs to be trusted'
    }

    It 'has no drift' {
        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)

        $findings | Should -BeNullOrEmpty -Because (($findings | ForEach-Object { "$($_.Construct): $($_.Message) $($_.Hint)" }) -join '; ')
    }
}
