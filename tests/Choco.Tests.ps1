#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

Describe 'Chocolatey native argument completion' {
    BeforeAll {
        # Keep the native registration and its help cache out of Pester's runspace.
        $shell = [powershell]::Create()
        $path = Join-Path $PSScriptRoot '../choco_completer/choco_completer.ps1'
        foreach ($name in 'README.md', '--password=README.md') {
            $null = New-Item (Join-Path $TestDrive $name) -ItemType File
        }
        $null = $shell.AddScript({
            param($Path, $Directory)
            . $Path
            Set-Location -LiteralPath $Directory
            $script:OfflineHelp = $false
            $script:CacheHelpRequests = [System.Collections.Generic.List[string]]::new()

            # The 2.5 cache and template child help repeat the parent's page.
            function Invoke-ChocoCapture {
                param([string[]]$Arguments, [int]$TimeoutMilliseconds)
                if ($Arguments[-1] -ne '--help' -or $script:OfflineHelp) { return }
                switch ($Arguments[0]) {
                    'install' {
                        'Examples'
                        '    choco install git -y --params="''/GitAndUnixToolsOnPath /NoAutoCrlf''" --install-arguments="''/DIR=C:\git''"'
                        'Options and Switches'
                        ' -p, --password=VALUE'
                        ' --params=VALUE'
                        ' --log-file=VALUE'
                    }
                    'apikey' {
                        'Options and Switches'
                        ' -k, --key, --apikey, --api-key=VALUE'
                    }
                    'cache' {
                        $script:CacheHelpRequests.Add(($Arguments -join ' '))
                        'Usage'
                        '    choco cache [list]|remove [options/switches]'
                        'Examples'
                        '    choco cache list'
                        '    choco cache remove --expired'
                        'Options and Switches'
                        ' -v, --verbose'
                        ' --expired'
                        '     Expired - Remove cached items that have expired.'
                    }
                    'search' {
                        'Options and Switches'
                        ' -?, --help, -h'
                        ' --page-size=VALUE'
                    }
                    'template' {
                        'Usage'
                        '    choco template [list]|info [<options/switches>]'
                        'Examples'
                        '    choco template list --reduce-output'
                        'Options and Switches'
                        ' -v, --verbose'
                    }
                    'source' {
                        'Usage'
                        '    choco source [list]|add|remove|disable|enable [<options/switches>]'
                        # Not in the static fallback: prove alternatives come from usage.
                        '    choco source [list]|audit [<options/switches>]'
                    }
                }
            }
        }).AddArgument($path).AddArgument($TestDrive).Invoke()
        $shell.HadErrors | Should -BeFalse
        $shell.Commands.Clear()

        function Get-ChocoMatches([string]$Line, [switch]$Offline, [int]$Cursor = $Line.Length) {
            $shell.Commands.Clear()
            $result = $shell.AddScript({
                param($Line, $Offline, $Cursor)
                if ($script:OfflineHelp -ne $Offline) {
                    $script:OfflineHelp = $Offline
                    $script:ChocoCompletionCache.HelpDataByPath.Clear()
                    $script:ChocoCompletionCache.HelpLinesByCommand.Clear()
                }
                (TabExpansion2 $Line $Cursor).CompletionMatches
            }).AddArgument($Line).AddArgument($Offline.IsPresent).AddArgument($Cursor).Invoke()
            $shell.HadErrors | Should -BeFalse
            $result | ForEach-Object CompletionText
        }
    }

    AfterAll { $shell.Dispose() }

    It 'recognizes an option after a quoted value without harvesting switches inside it' {
        @(Get-ChocoMatches 'choco install /NoAuto') | Should -Not -Contain '/NoAutoCrlf'
        @(Get-ChocoMatches 'choco install --install-arg') | Should -Contain '--install-arguments'
    }

    It 'scopes --expired to cache remove (offline=<Offline>)' -ForEach @(
        @{ Offline = $false }
        @{ Offline = $true }
    ) {
        @(Get-ChocoMatches 'choco cache list --exp' -Offline:$Offline) | Should -Not -Contain '--expired'
        @(Get-ChocoMatches 'choco cache remove --exp' -Offline:$Offline) | Should -Contain '--expired'
        @(Get-ChocoMatches 'choco cache list --verb' -Offline:$Offline) | Should -Contain '--verbose'
        if (-not $Offline) {
            $shell.Commands.Clear()
            $requests = @($shell.AddScript({ $script:CacheHelpRequests.ToArray() }).Invoke())
            $requests | Should -HaveCount 1
            $requests[0] | Should -Be 'cache --help'
        }
    }

    It 'scopes an example-only template switch to its documented subcommand' {
        @(Get-ChocoMatches 'choco template list --reduce') | Should -Contain '--reduce-output'
        @(Get-ChocoMatches 'choco template info --reduce') | Should -Not -Contain '--reduce-output'
    }

    It 'does not fall back to matching files after a partial secret (<Line>)' -ForEach @(
        @{ Line = 'choco install --password RE' }
        @{ Line = 'choco install -p RE' }
        @{ Line = 'choco install --password=RE' }
        @{ Line = 'choco apikey add -k RE' }
        @{ Line = 'choco install --password --log-file=RE' }
    ) {
        @(Get-ChocoMatches 'choco install --log-file RE') | Should -Contain 'README.md'
        @(Get-ChocoMatches $Line).Count | Should -Be 0
    }

    It 'does not replace an attached password when the cursor is just before its first character' {
        $prefix = 'choco install --password='
        @(Get-ChocoMatches ($prefix + 'RE') -Cursor $prefix.Length).Count | Should -Be 0
    }

    It 'still hints an empty password slot' {
        @(Get-ChocoMatches 'choco install --password ') | Should -Contain '<secret>'
        @(Get-ChocoMatches 'choco install --password=') | Should -Contain '--password=<secret>'
    }

    It 'does not invent attached values for <Option>' -ForEach @(
        @{ Option = '--help' }
        @{ Option = '--zzzz' }
    ) {
        @(Get-ChocoMatches "choco find $Option=").Count | Should -Be 0
        @(Get-ChocoMatches 'choco find --page-size=3') | Should -Contain '--page-size=30'
    }

    It 'recognizes usage alternatives without examples or an option table' {
        $verbs = @(Get-ChocoMatches 'choco source ')
        foreach ($verb in 'list', 'add', 'remove', 'disable', 'enable', 'audit') {
            $verbs | Should -Contain $verb
        }
    }
}
