#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
.SYNOPSIS
Conformance gate for the completer scripts in this repository.

.DESCRIPTION
Runs Test-CompleterScript over every *_completer.ps1 script and fails on any
Error finding, then runs Test-CompleterSet over ps_completers.psd1 and fails on
any drift between the set and the scripts on disk (missing or unlisted
scripts, stale hashes, target mismatches). Nothing is executed and nothing is
registered; both checks are static.

The package gate stages the PSGallery package with tools/Build-Package.ps1
into the test drive, runs Test-CompleterSet over the staged set (including
its package layout checks), and imports the staged package by name from a
test-drive module root to check it registers the same lazy records as the
repository's set. Those records are unregistered again; no script is loaded.

Needs CompleterActions 2.2.0 or later (2.2.0-preview1 satisfies it). Run it
in its own profile-free process:

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

Describe 'The staged PS_Completers package is a conforming completer-set package' {
    BeforeAll {
        Import-Module -Name CompleterActions -MinimumVersion 2.2.0 -ErrorAction Stop

        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:RepoSetPath = Join-Path -Path $repoRoot -ChildPath 'ps_completers.psd1'
        $script:Package = & (Join-Path -Path $repoRoot -ChildPath 'tools/Build-Package.ps1') -DestinationPath (Join-Path -Path $TestDrive -ChildPath 'staging')
    }

    It 'has no findings from Test-CompleterSet on the staged set' {
        $findings = @(Test-CompleterSet -LiteralPath (Join-Path -Path $script:Package.FullName -ChildPath 'completers/completers.psd1'))

        $findings | Should -BeNullOrEmpty -Because (($findings | ForEach-Object { "$($_.Construct): $($_.Message) $($_.Hint)" }) -join '; ')
    }

    It 'imports by name with the same Pending records as the repository set' {
        $version = (Import-PowerShellDataFile -LiteralPath (Join-Path -Path $script:Package.FullName -ChildPath 'PS_Completers.psd1')).ModuleVersion
        $moduleRoot = Join-Path -Path $TestDrive -ChildPath 'modules'
        $moduleFolder = New-Item -Path (Join-Path -Path $moduleRoot -ChildPath 'PS_Completers') -ItemType Directory
        Copy-Item -LiteralPath $script:Package.FullName -Destination (Join-Path -Path $moduleFolder.FullName -ChildPath $version) -Recurse

        $savedModulePath = $env:PSModulePath
        $byName = @()
        $byPath = @()
        try {
            $env:PSModulePath = $moduleRoot
            $byName = @(Import-CompleterSet -Name PS_Completers)
        }
        finally {
            $env:PSModulePath = $savedModulePath
            if ($byName) { $byName | Unregister-Completer -Confirm:$false }
        }
        try {
            $byPath = @(Import-CompleterSet -LiteralPath $script:RepoSetPath)
        }
        finally {
            if ($byPath) { $byPath | Unregister-Completer -Confirm:$false }
        }

        $byPath.Count | Should -BeGreaterThan 0
        $byName.Count | Should -Be $byPath.Count
        @($byName | Where-Object -Property State -NE -Value 'Pending') | Should -BeNullOrEmpty -Because 'importing a set registers lazy records and loads no script'
        @($byName.Key | Sort-Object) | Should -Be @($byPath.Key | Sort-Object)
    }
}
