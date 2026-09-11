#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
.SYNOPSIS
Conformance gate for the completer scripts in this repository.

.DESCRIPTION
Runs Test-CompleterScript over every *_completer.ps1 script and fails on any
Error finding, then imports ps_completers.psd1 lazily and checks it lists
exactly the scripts in the repository. Nothing is executed; both checks are
static. Needs CompleterActions 2.0.0-preview1 or later. Run it in its own
profile-free process:

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
        Import-Module -Name CompleterActions -MinimumVersion 2.0.0 -ErrorAction Stop

        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:SetPath = Join-Path -Path $repoRoot -ChildPath 'ps_completers.psd1'
        $script:ScriptPaths = @(
            Get-ChildItem -Path $repoRoot -Directory -Filter '*_completer' |
                Get-ChildItem -Filter '*_completer.ps1' -File |
                ForEach-Object { $_.FullName } |
                Sort-Object
        )
    }

    AfterAll {
        Get-CompleterRegistration -ManagedOnly |
            Where-Object { $_.ScriptPath -and $_.ScriptPath -in $script:ScriptPaths } |
            Unregister-CompleterRegistration -Confirm:$false
    }

    It 'keeps every entry on the strict tier' {
        $set = Import-PowerShellDataFile -LiteralPath $script:SetPath

        @($set.Entries | Where-Object { $_.Trusted }) | Should -BeNullOrEmpty -Because 'every script passes the strict grammar, so no entry needs to be trusted'
    }

    It 'imports lazily and lists exactly the completer scripts in the repository' {
        $records = @(Import-CompleterSet -LiteralPath $script:SetPath -Force -Confirm:$false)

        @($records | Where-Object State -NE 'Pending') | Should -BeNullOrEmpty -Because 'a lazy import must not load any script'

        $listed = @($records.ScriptPath | Sort-Object -Unique)
        $listed | Should -Be $script:ScriptPaths -Because 'run tools/Export-CompleterSetFile.ps1 after adding, renaming, or removing a completer'
    }
}
