# Module manifest for the PS_Completers package on the PowerShell Gallery.
# The package is a CompleterActions completer set: PrivateData.CompleterSet names
# the set file, and Import-CompleterSet -Name PS_Completers imports it. Nothing in
# the package runs on import, so there is no RootModule and nothing is exported.
# tools/Build-Package.ps1 stages this file at the package root; the repository's
# ps_completers.psd1 is staged as completers/completers.psd1.
@{
    ModuleVersion     = '1.1.1'
    GUID              = '6b0d8c7e-3a41-4f6a-9d2e-5c1a7f0e9b34'
    Author            = 'Trent Stager'
    Description       = 'Argument completers for native commands, as a CompleterActions completer set.'
    PowerShellVersion = '7.0'
    RequiredModules   = @(@{ ModuleName = 'CompleterActions'; ModuleVersion = '2.2.0' })
    FunctionsToExport = @()
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        CompleterSet = 'completers/completers.psd1'
        PSData       = @{
            Tags       = @('completer', 'argument-completer', 'CompleterActions')
            LicenseUri = 'https://github.com/tstager/PS_Completers/blob/master/LICENSE'
        }
    }
}
