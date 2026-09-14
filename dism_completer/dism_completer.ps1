# DISM tab completion for PowerShell
# Static catalog of the documented DISM surface, enriched from DISM's own help when the shell is elevated
# (DISM refuses to print help otherwise).
# Usage: . .\dism_completer.ps1

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name DismCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:DismCompletionCatalog = @{
        Initialized       = $false
        Commands          = @()
        GlobalSwitches    = @()
        OptionSpecs       = $null
        LiveCommandKeys   = @{}
        ExtraSwitchesByKey = @{}
    }
}

function New-DismSwitchSpec {
    param(
        [string]$Token,
        [string]$Description,
        [string]$Kind = 'Flag',
        [string[]]$Values = @(),
        [string[]]$Extensions = @(),
        [string]$Placeholder = '<value>'
    )

    [pscustomobject]@{
        Token       = $Token
        Description = $Description
        Kind        = $Kind
        Values      = @($Values)
        Extensions  = @($Extensions)
        Placeholder = $Placeholder
    }
}

function New-DismCommandSpec {
    param(
        [string]$Token,
        [string]$Description,
        [object[]]$Switches = @(),
        [string]$Kind = 'Flag',
        [string[]]$Values = @(),
        [string]$Placeholder = '<value>'
    )

    [pscustomobject]@{
        Token       = $Token
        Description = $Description
        Kind        = $Kind
        Values      = @($Values)
        Extensions  = @()
        Placeholder = $Placeholder
        Switches    = @($Switches)
    }
}

function Get-DismStaticCatalog {
    $imageExtensions = @('.wim', '.esd', '.swm', '.ffu', '.vhd', '.vhdx')
    $s = @{
        ImageFile            = New-DismSwitchSpec -Token '/ImageFile:' -Description 'Path to the image file (.wim, .esd, .ffu, .vhd, .vhdx).' -Kind 'File' -Extensions $imageExtensions
        SourceImageFile      = New-DismSwitchSpec -Token '/SourceImageFile:' -Description 'Path to the source image file.' -Kind 'File' -Extensions $imageExtensions
        DestinationImageFile = New-DismSwitchSpec -Token '/DestinationImageFile:' -Description 'Path to the destination image file.' -Kind 'File' -Extensions $imageExtensions
        SWMFile              = New-DismSwitchSpec -Token '/SWMFile:' -Description 'Naming pattern and location of split .swm files.' -Kind 'File' -Extensions @('.swm')
        SFUFile              = New-DismSwitchSpec -Token '/SFUFile:' -Description 'Naming pattern and location of split .sfu files.' -Kind 'File' -Extensions @('.sfu')
        Index                = New-DismSwitchSpec -Token '/Index:' -Description 'Index number of the image inside the file (use 1 for FFU and VHD).' -Kind 'Value' -Placeholder '<index>'
        SourceIndex          = New-DismSwitchSpec -Token '/SourceIndex:' -Description 'Index number of the source image.' -Kind 'Value' -Placeholder '<index>'
        Name                 = New-DismSwitchSpec -Token '/Name:' -Description 'Name of the image.' -Kind 'Value' -Placeholder '<image-name>'
        SourceName           = New-DismSwitchSpec -Token '/SourceName:' -Description 'Name of the source image.' -Kind 'Value' -Placeholder '<image-name>'
        DestinationName      = New-DismSwitchSpec -Token '/DestinationName:' -Description 'Name of the destination image.' -Kind 'Value' -Placeholder '<image-name>'
        Description          = New-DismSwitchSpec -Token '/Description:' -Description 'Description of the image.' -Kind 'Value' -Placeholder '<description>'
        MountDir             = New-DismSwitchSpec -Token '/MountDir:' -Description 'Directory the image is (or will be) mounted to.' -Kind 'Directory'
        ApplyDir             = New-DismSwitchSpec -Token '/ApplyDir:' -Description 'Target directory the image is applied to.' -Kind 'Directory'
        CaptureDir           = New-DismSwitchSpec -Token '/CaptureDir:' -Description 'Source directory to capture.' -Kind 'Directory'
        ConfigFile           = New-DismSwitchSpec -Token '/ConfigFile:' -Description 'Configuration file listing capture and compress exclusions.' -Kind 'File' -Extensions @('.ini')
        CheckIntegrity       = New-DismSwitchSpec -Token '/CheckIntegrity' -Description 'Detects and tracks .wim file corruption.'
        Verify               = New-DismSwitchSpec -Token '/Verify' -Description 'Checks for errors and file duplication.'
        NoRpFix              = New-DismSwitchSpec -Token '/NoRpFix' -Description 'Disables the reparse point tag fix.'
        Bootable             = New-DismSwitchSpec -Token '/Bootable' -Description 'Marks a volume image as bootable (WinPE images only).'
        WIMBoot              = New-DismSwitchSpec -Token '/WIMBoot' -Description 'WIMBoot configuration (Windows 8.1 images only).'
        EA                   = New-DismSwitchSpec -Token '/EA' -Description 'Captures or applies extended attributes.'
        Compress             = New-DismSwitchSpec -Token '/Compress:' -Description 'Compression type for the capture or export.' -Kind 'Enum' -Values @('max', 'fast', 'none', 'recovery')
        FileSize             = New-DismSwitchSpec -Token '/FileSize:' -Description 'Maximum size in MB of each split file.' -Kind 'Value' -Placeholder '<MB-size>'
        PackagePath          = New-DismSwitchSpec -Token '/PackagePath:' -Description 'Path to a .cab/.msu package or a folder of packages.' -Kind 'File' -Extensions @('.cab', '.msu', '.appx', '.appxbundle', '.msix', '.msixbundle', '.spp')
        PackageName          = New-DismSwitchSpec -Token '/PackageName:' -Description 'Name of the package as listed in the image.' -Kind 'Value' -Placeholder '<package-name>'
        FeatureName          = New-DismSwitchSpec -Token '/FeatureName:' -Description 'Name of the feature as listed by /Get-Features.' -Kind 'Value' -Placeholder '<feature-name>'
        CapabilityName       = New-DismSwitchSpec -Token '/CapabilityName:' -Description 'Name of the capability as listed by /Get-Capabilities.' -Kind 'Value' -Placeholder '<capability-name>'
        Source               = New-DismSwitchSpec -Token '/Source:' -Description 'Location of the files required to restore or repair (for example a mounted Windows folder).' -Kind 'Directory'
        LimitAccess          = New-DismSwitchSpec -Token '/LimitAccess' -Description 'Prevents DISM from contacting Windows Update.'
        Format               = New-DismSwitchSpec -Token '/Format:' -Description 'Report output format.' -Kind 'Enum' -Values @('Table', 'List')
        Driver               = New-DismSwitchSpec -Token '/Driver:' -Description 'Path to a driver .inf file or a folder of drivers.' -Kind 'File' -Extensions @('.inf')
        Distribution         = New-DismSwitchSpec -Token '/Distribution:' -Description 'Path to the distribution share.' -Kind 'Directory'
        CustomDataPath       = New-DismSwitchSpec -Token '/CustomDataPath:' -Description 'Custom data file added to the app package as Custom.dat.' -Kind 'File'
    }

    $globals = @(
        New-DismSwitchSpec -Token '/?' -Description 'Displays information about available DISM command-line options and arguments.'
        New-DismSwitchSpec -Token '/Get-Help' -Description 'Displays information about available DISM command-line options and arguments (same as /?).'
        New-DismSwitchSpec -Token '/Online' -Description 'Targets the running operating system.'
        New-DismSwitchSpec -Token '/Image:' -Description 'Full path to the root directory of the offline Windows image to service.' -Kind 'Directory'
        New-DismSwitchSpec -Token '/WinDir:' -Description 'Path to the Windows directory relative to the image path (used with /Image).' -Kind 'Directory'
        New-DismSwitchSpec -Token '/SysDriveDir:' -Description 'Path to the location of the BootMgr files (Windows PE servicing).' -Kind 'Directory'
        New-DismSwitchSpec -Token '/LogPath:' -Description 'Full path and file name to log to (default %WINDIR%\Logs\Dism\dism.log).' -Kind 'File' -Extensions @('.log')
        New-DismSwitchSpec -Token '/LogLevel:' -Description 'Maximum output level shown in the logs: 1 errors, 2 warnings, 3 informational, 4 debug.' -Kind 'Enum' -Values @('1', '2', '3', '4')
        New-DismSwitchSpec -Token '/ScratchDir:' -Description 'Local temporary directory used when extracting files during servicing.' -Kind 'Directory'
        New-DismSwitchSpec -Token '/Quiet' -Description 'Turns off information and progress output to the console.'
        New-DismSwitchSpec -Token '/NoRestart' -Description 'Suppresses reboot and the restart prompt.'
        New-DismSwitchSpec -Token '/English' -Description 'Displays command-line output in English.'
        $s.Format
    )

    $commands = @(
        # Image management
        New-DismCommandSpec -Token '/Get-ImageInfo' -Description 'Displays information about the images in a .wim, .ffu, .vhd or .vhdx file.' -Switches @($s.ImageFile, $s.Index, $s.Name)
        New-DismCommandSpec -Token '/Get-MountedImageInfo' -Description 'Lists the images that are currently mounted.'
        New-DismCommandSpec -Token '/Mount-Image' -Description 'Mounts an image to a directory so it is available for servicing.' -Switches @($s.ImageFile, $s.Index, $s.Name, $s.MountDir,
            (New-DismSwitchSpec -Token '/ReadOnly' -Description 'Mounts the image with read-only permissions.'),
            (New-DismSwitchSpec -Token '/Optimize' -Description 'Reduces initial mount time.'),
            $s.CheckIntegrity)
        New-DismCommandSpec -Token '/Unmount-Image' -Description 'Unmounts an image and commits or discards the changes.' -Switches @($s.MountDir,
            (New-DismSwitchSpec -Token '/Commit' -Description 'Saves the changes made to the mounted image.'),
            (New-DismSwitchSpec -Token '/Discard' -Description 'Discards the changes made to the mounted image.'),
            $s.CheckIntegrity,
            (New-DismSwitchSpec -Token '/Append' -Description 'Adds the modified image to the .wim file instead of overwriting the original image.'))
        New-DismCommandSpec -Token '/Remount-Image' -Description 'Remounts a mounted image that has become inaccessible.' -Switches @($s.MountDir)
        New-DismCommandSpec -Token '/Commit-Image' -Description 'Applies the changes made to the mounted image without unmounting it.' -Switches @($s.MountDir, $s.CheckIntegrity,
            (New-DismSwitchSpec -Token '/Append' -Description 'Adds the modified image to the .wim file instead of overwriting the original image.'))
        New-DismCommandSpec -Token '/Cleanup-Mountpoints' -Description 'Deletes the resources associated with corrupted mounted images.'
        New-DismCommandSpec -Token '/Apply-Image' -Description 'Applies a .wim or split .swm image to a specified directory.' -Switches @($s.ImageFile, $s.SWMFile, $s.ApplyDir, $s.Index, $s.Name, $s.CheckIntegrity, $s.Verify, $s.NoRpFix,
            (New-DismSwitchSpec -Token '/ConfirmTrustedFile' -Description 'Validates the image for Trusted Desktop (WinPE 4.0 or later).'),
            $s.WIMBoot,
            (New-DismSwitchSpec -Token '/Compact' -Description 'Applies the image in compact mode, saving drive space.'),
            $s.EA)
        New-DismCommandSpec -Token '/Capture-Image' -Description 'Captures an image of a drive to a new .wim file.' -Switches @($s.ImageFile, $s.CaptureDir, $s.Name, $s.Description, $s.ConfigFile, $s.Compress, $s.Bootable, $s.WIMBoot, $s.CheckIntegrity, $s.Verify, $s.NoRpFix, $s.EA)
        New-DismCommandSpec -Token '/Capture-CustomImage' -Description 'Captures incremental file changes to a custom.wim for a WIMBoot image.' -Switches @($s.CaptureDir, $s.ConfigFile, $s.CheckIntegrity, $s.Verify,
            (New-DismSwitchSpec -Token '/ConfirmTrustedFile' -Description 'Validates the image for Trusted Desktop (WinPE 4.0 or later).'))
        New-DismCommandSpec -Token '/Append-Image' -Description 'Adds an additional image to a .wim file.' -Switches @($s.ImageFile, $s.CaptureDir, $s.Name, $s.Description, $s.ConfigFile, $s.Bootable, $s.WIMBoot, $s.CheckIntegrity, $s.Verify, $s.NoRpFix)
        New-DismCommandSpec -Token '/Export-Image' -Description 'Exports a copy of the specified image to another file.' -Switches @($s.SourceImageFile, $s.SourceIndex, $s.SourceName, $s.DestinationImageFile, $s.DestinationName, $s.SWMFile, $s.Compress, $s.Bootable, $s.WIMBoot, $s.CheckIntegrity)
        New-DismCommandSpec -Token '/Delete-Image' -Description 'Deletes a volume image from a .wim file with multiple images.' -Switches @($s.ImageFile, $s.Index, $s.Name, $s.CheckIntegrity)
        New-DismCommandSpec -Token '/Split-Image' -Description 'Splits an existing .wim file into multiple read-only .swm files.' -Switches @($s.ImageFile, $s.SWMFile, $s.FileSize, $s.CheckIntegrity)
        New-DismCommandSpec -Token '/List-Image' -Description 'Lists the files and folders in a specified image.' -Switches @($s.ImageFile, $s.Index, $s.Name)
        New-DismCommandSpec -Token '/Optimize-Image' -Description 'Optimizes an offline image (last command before applying it to a device).' -Switches @(
            (New-DismSwitchSpec -Token '/Boot' -Description 'Reduces the online configuration time the OS spends during boot.'),
            $s.WIMBoot)
        New-DismCommandSpec -Token '/Apply-FFU' -Description 'Applies a full flash update (.ffu) or split FFU image to a physical drive.' -Switches @($s.ImageFile,
            (New-DismSwitchSpec -Token '/ApplyDrive:' -Description 'Physical drive to image (for example \\.\PhysicalDrive0).' -Kind 'Value' -Placeholder '\\.\PhysicalDrive<n>'),
            $s.SFUFile)
        New-DismCommandSpec -Token '/Capture-FFU' -Description 'Captures an image of a physical drive to a new .ffu file.' -Switches @($s.ImageFile,
            (New-DismSwitchSpec -Token '/CaptureDrive:' -Description 'Physical drive to capture (for example \\.\PhysicalDrive0).' -Kind 'Value' -Placeholder '\\.\PhysicalDrive<n>'),
            $s.Name, $s.Description,
            (New-DismSwitchSpec -Token '/PlatformIds:' -Description 'Semicolon-separated platform ids to add to the image.' -Kind 'Value' -Placeholder '<platform-ids>'),
            (New-DismSwitchSpec -Token '/Compress:' -Description 'Compression used when capturing (use none when the FFU will be split).' -Kind 'Enum' -Values @('default', 'none')))
        New-DismCommandSpec -Token '/Split-FFU' -Description 'Splits an existing .ffu file into multiple read-only .sfu files.' -Switches @($s.ImageFile, $s.SFUFile, $s.FileSize, $s.CheckIntegrity)
        New-DismCommandSpec -Token '/Optimize-FFU' -Description 'Optimizes an FFU image so it deploys faster and to differently-sized disks.' -Switches @($s.ImageFile,
            (New-DismSwitchSpec -Token '/PartitionNumber:' -Description 'Partition to optimize (defaults to the OS partition).' -Kind 'Value' -Placeholder '<partition-number>'))
        New-DismCommandSpec -Token '/Apply-CustomDataImage' -Description 'Dehydrates files contained in a custom data image.' -Switches @(
            (New-DismSwitchSpec -Token '/CustomDataImage:' -Description 'Path to the custom data image (.wim).' -Kind 'File' -Extensions @('.wim')),
            (New-DismSwitchSpec -Token '/ImagePath:' -Description 'Path to the root of the applied Windows image.' -Kind 'Directory'),
            (New-DismSwitchSpec -Token '/SingleInstance' -Description 'Single-instances the files in the custom data image.'))
        New-DismCommandSpec -Token '/Apply-SiloedPackage' -Description 'Applies one or more siloed provisioning packages (.spp) to an applied image.' -Switches @(
            (New-DismSwitchSpec -Token '/PackagePath:' -Description 'Path of a siloed provisioning package file.' -Kind 'File' -Extensions @('.spp')),
            (New-DismSwitchSpec -Token '/ImagePath:' -Description 'Path of the Windows image where the SPP is applied.' -Kind 'Directory'))
        New-DismCommandSpec -Token '/Get-WIMBootEntry' -Description 'Displays WIMBoot configuration entries for the specified volume.' -Switches @(
            (New-DismSwitchSpec -Token '/Path:' -Description 'Disk volume of the WIMBoot configuration.' -Kind 'Directory'))
        New-DismCommandSpec -Token '/Update-WIMBootEntry' -Description 'Updates a WIMBoot configuration entry with a renamed or moved image file.' -Switches @(
            (New-DismSwitchSpec -Token '/Path:' -Description 'Disk volume of the WIMBoot configuration.' -Kind 'Directory'),
            (New-DismSwitchSpec -Token '/DataSourceID:' -Description 'Data source id as displayed by /Get-WIMBootEntry.' -Kind 'Value' -Placeholder '<data-source-id>'),
            $s.ImageFile)
        # OS package servicing
        New-DismCommandSpec -Token '/Get-Packages' -Description 'Displays basic information about all packages in the image.' -Switches @($s.Format)
        New-DismCommandSpec -Token '/Get-PackageInfo' -Description 'Displays detailed information about a package (.cab).' -Switches @($s.PackageName, $s.PackagePath)
        New-DismCommandSpec -Token '/Add-Package' -Description 'Installs a .cab or .msu package in the image.' -Switches @($s.PackagePath,
            (New-DismSwitchSpec -Token '/IgnoreCheck' -Description 'Skips the applicability check of each package.'),
            (New-DismSwitchSpec -Token '/PreventPending' -Description 'Skips the installation when the image has pending online actions.'))
        New-DismCommandSpec -Token '/Remove-Package' -Description 'Removes a .cab package from the image.' -Switches @($s.PackageName, $s.PackagePath)
        New-DismCommandSpec -Token '/Get-Features' -Description 'Displays basic information about all features in a package or the image.' -Switches @($s.PackageName, $s.PackagePath, $s.Format)
        New-DismCommandSpec -Token '/Get-FeatureInfo' -Description 'Displays detailed information about a feature.' -Switches @($s.FeatureName, $s.PackageName, $s.PackagePath)
        New-DismCommandSpec -Token '/Enable-Feature' -Description 'Enables or updates the specified feature in the image.' -Switches @($s.FeatureName, $s.PackageName, $s.PackagePath, $s.Source, $s.LimitAccess,
            (New-DismSwitchSpec -Token '/All' -Description 'Enables all parent features of the specified feature.'))
        New-DismCommandSpec -Token '/Disable-Feature' -Description 'Disables the specified feature in the image.' -Switches @($s.FeatureName, $s.PackageName, $s.PackagePath,
            (New-DismSwitchSpec -Token '/Remove' -Description 'Removes the feature payload without removing its manifest.'))
        New-DismCommandSpec -Token '/Cleanup-Image' -Description 'Performs cleanup or recovery operations on the image.' -Switches @(
            (New-DismSwitchSpec -Token '/CheckHealth' -Description 'Checks whether the image has been flagged as corrupted and whether it can be repaired.'),
            (New-DismSwitchSpec -Token '/ScanHealth' -Description 'Scans the image for component store corruption.'),
            (New-DismSwitchSpec -Token '/RestoreHealth' -Description 'Scans the image for corruption and performs repair operations automatically.'),
            $s.Source, $s.LimitAccess,
            (New-DismSwitchSpec -Token '/StartComponentCleanup' -Description 'Cleans up superseded components and reduces the size of the component store.'),
            (New-DismSwitchSpec -Token '/ResetBase' -Description 'Resets the base of superseded components (with /StartComponentCleanup).'),
            (New-DismSwitchSpec -Token '/Defer' -Description 'Defers long-running cleanup to the next automatic maintenance (with /ResetBase).'),
            (New-DismSwitchSpec -Token '/SPSuperseded' -Description 'Removes backup files created during a service pack installation.'),
            (New-DismSwitchSpec -Token '/HideSP' -Description 'Prevents the service pack from being listed in Installed Updates (with /SPSuperseded).'),
            (New-DismSwitchSpec -Token '/AnalyzeComponentStore' -Description 'Creates a report of the component store.'),
            (New-DismSwitchSpec -Token '/RevertPendingActions' -Description 'Reverts all pending actions from previous servicing operations (offline recovery only).'))
        # Capabilities
        New-DismCommandSpec -Token '/Get-Capabilities' -Description 'Displays the capabilities in the image.' -Switches @($s.Format, $s.Source, $s.LimitAccess)
        New-DismCommandSpec -Token '/Get-CapabilityInfo' -Description 'Displays detailed information about a capability.' -Switches @($s.CapabilityName, $s.Source, $s.LimitAccess)
        New-DismCommandSpec -Token '/Add-Capability' -Description 'Adds a capability to the image.' -Switches @($s.CapabilityName, $s.Source, $s.LimitAccess)
        New-DismCommandSpec -Token '/Remove-Capability' -Description 'Removes a capability from the image.' -Switches @($s.CapabilityName)
        New-DismCommandSpec -Token '/Export-Source' -Description 'Exports the source files of the capabilities in the image.' -Switches @($s.Source,
            (New-DismSwitchSpec -Token '/Target:' -Description 'Destination folder for the exported source.' -Kind 'Directory'),
            $s.CapabilityName)
        # Drivers
        New-DismCommandSpec -Token '/Get-Drivers' -Description 'Displays basic information about driver packages in the image.' -Switches @(
            (New-DismSwitchSpec -Token '/All' -Description 'Includes the default (inbox) drivers.'),
            $s.Format)
        New-DismCommandSpec -Token '/Get-DriverInfo' -Description 'Displays detailed information about a driver .inf file.' -Switches @($s.Driver)
        New-DismCommandSpec -Token '/Add-Driver' -Description 'Adds third-party driver packages to an offline image.' -Switches @($s.Driver,
            (New-DismSwitchSpec -Token '/Recurse' -Description 'Installs all drivers found in the folder and its subfolders.'),
            (New-DismSwitchSpec -Token '/ForceUnsigned' -Description 'Adds unsigned drivers to x64-based images.'))
        New-DismCommandSpec -Token '/Remove-Driver' -Description 'Removes third-party drivers from an offline image.' -Switches @($s.Driver)
        New-DismCommandSpec -Token '/Export-Driver' -Description 'Exports all third-party driver packages to a destination path.' -Switches @(
            (New-DismSwitchSpec -Token '/Destination:' -Description 'Folder the driver packages are exported to.' -Kind 'Directory'))
        # Editions
        New-DismCommandSpec -Token '/Get-CurrentEdition' -Description 'Displays the edition of the image.'
        New-DismCommandSpec -Token '/Get-TargetEditions' -Description 'Displays the editions the image can be upgraded to.'
        New-DismCommandSpec -Token '/Set-Edition:' -Description 'Changes the image to a higher edition (/Set-Edition:<target edition>).' -Kind 'Value' -Placeholder '<target-edition>' -Switches @(
            (New-DismSwitchSpec -Token '/ProductKey:' -Description 'Product key for the target edition.' -Kind 'Value' -Placeholder '<product-key>'),
            (New-DismSwitchSpec -Token '/AcceptEula' -Description 'Accepts the licence terms for the target edition.'),
            (New-DismSwitchSpec -Token '/Channel:' -Description 'Path to the licensing channel (.xrm-ms) file.' -Kind 'File' -Extensions @('.xrm-ms')))
        New-DismCommandSpec -Token '/Set-ProductKey:' -Description 'Enters the product key for the current edition (/Set-ProductKey:<key>).' -Kind 'Value' -Placeholder '<product-key>'
        # Unattend and app packages
        New-DismCommandSpec -Token '/Apply-Unattend:' -Description 'Applies an unattend.xml answer file to the image (/Apply-Unattend:<path>).' -Kind 'File' -Placeholder '<unattend.xml>'
        New-DismCommandSpec -Token '/Get-ProvisionedAppxPackages' -Description 'Displays the app packages (.appx/.appxbundle) provisioned in the image.'
        New-DismCommandSpec -Token '/Add-ProvisionedAppxPackage' -Description 'Adds one or more app packages to the image.' -Switches @(
            (New-DismSwitchSpec -Token '/FolderPath:' -Description 'Folder of unpacked app files (main package, dependencies, licence).' -Kind 'Directory'),
            (New-DismSwitchSpec -Token '/PackagePath:' -Description 'App package (.appx, .appxbundle, .msix, .msixbundle).' -Kind 'File' -Extensions @('.appx', '.appxbundle', '.msix', '.msixbundle')),
            (New-DismSwitchSpec -Token '/DependencyPackagePath:' -Description 'Dependency package needed by the app (repeatable).' -Kind 'File' -Extensions @('.appx', '.appxbundle', '.msix', '.msixbundle')),
            (New-DismSwitchSpec -Token '/LicensePath:' -Description 'Location of the .xml file containing the application licence.' -Kind 'File' -Extensions @('.xml')),
            (New-DismSwitchSpec -Token '/SkipLicense' -Description 'Skips the licence for apps that do not require one (sideloading-enabled computers).'),
            $s.CustomDataPath,
            (New-DismSwitchSpec -Token '/Region:' -Description 'Regions the package is provisioned for: all, or a semicolon-separated list of ISO 3166-1 codes.' -Kind 'Enum' -Values @('all')),
            (New-DismSwitchSpec -Token '/StubPackageOption:' -Description 'Stub preference of the package.' -Kind 'Enum' -Values @('installstub', 'installfull')))
        New-DismCommandSpec -Token '/Remove-ProvisionedAppxPackage' -Description 'Removes provisioning for an app package from the image.' -Switches @($s.PackageName)
        New-DismCommandSpec -Token '/Optimize-ProvisionedAppxPackages' -Description 'Optimizes the total file size of provisioned packages using hardlinks (offline only).'
        New-DismCommandSpec -Token '/Set-ProvisionedAppxDataFile' -Description 'Adds a custom data file into a provisioned app package.' -Switches @($s.CustomDataPath, $s.PackageName)
        New-DismCommandSpec -Token '/Get-DefaultAppAssociations' -Description 'Displays the default application associations in the image.'
        New-DismCommandSpec -Token '/Export-DefaultAppAssociations:' -Description 'Exports the default application associations to an XML file.' -Kind 'File' -Placeholder '<path.xml>'
        New-DismCommandSpec -Token '/Import-DefaultAppAssociations:' -Description 'Imports default application associations from an XML file.' -Kind 'File' -Placeholder '<path.xml>'
        New-DismCommandSpec -Token '/Remove-DefaultAppAssociations' -Description 'Removes the default application associations from the image.'
        # International servicing
        New-DismCommandSpec -Token '/Get-Intl' -Description 'Displays information about the international settings and languages.' -Switches @($s.Distribution)
        New-DismCommandSpec -Token '/Set-UILang:' -Description 'Sets the default system UI language (/Set-UILang:<language>).' -Kind 'Value' -Placeholder '<language>'
        New-DismCommandSpec -Token '/Set-UILangFallback:' -Description 'Sets the fallback system UI language (/Set-UILangFallback:<language>).' -Kind 'Value' -Placeholder '<language>'
        New-DismCommandSpec -Token '/Set-SysLocale:' -Description 'Sets the language for non-Unicode programs (/Set-SysLocale:<locale>).' -Kind 'Value' -Placeholder '<locale>'
        New-DismCommandSpec -Token '/Set-UserLocale:' -Description 'Sets the per-user format settings (/Set-UserLocale:<locale>).' -Kind 'Value' -Placeholder '<locale>'
        New-DismCommandSpec -Token '/Set-InputLocale:' -Description 'Sets the input locale and keyboard layout (/Set-InputLocale:<locale>).' -Kind 'Value' -Placeholder '<locale>'
        New-DismCommandSpec -Token '/Set-AllIntl:' -Description 'Sets all international settings to one language (/Set-AllIntl:<language>).' -Kind 'Value' -Placeholder '<language>'
        New-DismCommandSpec -Token '/Set-TimeZone:' -Description 'Sets the default time zone (/Set-TimeZone:<time zone>).' -Kind 'Value' -Placeholder '<time-zone>'
        New-DismCommandSpec -Token '/Set-SKUIntlDefaults:' -Description 'Sets the SKU international defaults for a language (/Set-SKUIntlDefaults:<language>).' -Kind 'Value' -Placeholder '<language>'
        New-DismCommandSpec -Token '/Set-LayeredDriver:' -Description 'Sets the keyboard layered driver (/Set-LayeredDriver:{1..6}).' -Kind 'Enum' -Values @('1', '2', '3', '4', '5', '6')
        New-DismCommandSpec -Token '/Gen-LangIni' -Description 'Generates a new Lang.ini file for Windows Setup.' -Switches @($s.Distribution)
        New-DismCommandSpec -Token '/Set-SetupUILang:' -Description 'Sets the default language used by Windows Setup (/Set-SetupUILang:<language>).' -Kind 'Value' -Placeholder '<language>' -Switches @($s.Distribution)
        # Windows PE servicing
        New-DismCommandSpec -Token '/Get-PESettings' -Description 'Displays the Windows PE settings in the image.'
        New-DismCommandSpec -Token '/Get-ScratchSpace' -Description 'Displays the configured Windows PE scratch space.'
        New-DismCommandSpec -Token '/Get-TargetPath' -Description 'Displays the target path of the Windows PE image.'
        New-DismCommandSpec -Token '/Set-ScratchSpace:' -Description 'Sets the Windows PE scratch space in MB (/Set-ScratchSpace:<size>).' -Kind 'Enum' -Values @('32', '64', '128', '256', '512')
        New-DismCommandSpec -Token '/Set-TargetPath:' -Description 'Sets the location of the Windows PE image on the disk (/Set-TargetPath:<path>).' -Kind 'Value' -Placeholder '<target-path>'
        New-DismCommandSpec -Token '/Enable-Profiling' -Description 'Enables Windows PE file logging (profiling).'
        New-DismCommandSpec -Token '/Disable-Profiling' -Description 'Disables Windows PE file logging (profiling).'
        New-DismCommandSpec -Token '/Get-Profiling' -Description 'Displays whether Windows PE profiling is enabled.'
        # Reserved storage
        New-DismCommandSpec -Token '/Get-ReservedStorageState' -Description 'Displays whether reserved storage is enabled.'
        New-DismCommandSpec -Token '/Set-ReservedStorageState' -Description 'Enables or disables reserved storage.' -Switches @(
            (New-DismSwitchSpec -Token '/State:' -Description 'Reserved storage state.' -Kind 'Enum' -Values @('Enabled', 'Disabled')))
    )

    [pscustomobject]@{
        GlobalSwitches = @($globals)
        Commands       = @($commands)
    }
}

function Get-DismOptionKey {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $clean = $Token.Trim('"')
    if ($clean -match '^(/[A-Za-z?][A-Za-z0-9\-]*:?)') {
        return $matches[1].ToLowerInvariant()
    }

    $null
}

function Test-DismElevated {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        ([System.Security.Principal.WindowsPrincipal]$identity).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        $false
    }
}

function Invoke-DismHelpText {
    param([string[]]$Arguments, [int]$TimeoutMilliseconds = 2000)

    $command = Get-Command -Name 'dism.exe', 'dism' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if (-not $command) {
        return @()
    }

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $command.Source
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        foreach ($argument in @($Arguments)) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
        [void]$startInfo.ArgumentList.Add('/?')

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $process.StandardInput.Close()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            try { $process.Kill($true) } catch { Write-Debug -Message $_.Exception.Message }
            return @()
        }

        [void]$errorTask.Result
        $text = $outputTask.Result
        if ([string]::IsNullOrWhiteSpace($text) -or $text -match 'Error:\s*740' -or $text -match 'Elevated permissions are required') {
            return @()
        }

        @($text -split '\r?\n')
    } catch {
        @()
    }
}

function Get-DismSwitchTokensFromLines {
    param([string[]]$Lines)

    $tokens = foreach ($line in @($Lines)) {
        foreach ($match in [regex]::Matches($line, '(?<!\w)(/[A-Za-z][A-Za-z0-9\-]*:?)(?=[\s\]\}\|,]|$|<)')) {
            $match.Groups[1].Value
        }
    }

    @($tokens | Sort-Object -Unique)
}

function Add-DismLiveSwitchSet {
    param([string]$Key, [string[]]$HelpLines)

    # Enrichment only: tokens the static catalog does not know are added as plain flags under the given key.
    $known = $script:DismCompletionCatalog.OptionSpecs
    $extras = New-Object System.Collections.Generic.List[object]
    foreach ($token in Get-DismSwitchTokensFromLines -Lines $HelpLines) {
        $tokenKey = Get-DismOptionKey -Token $token
        if ($null -eq $tokenKey -or $known.ContainsKey($tokenKey) -or $known.ContainsKey($tokenKey + ':')) {
            continue
        }

        [void]$extras.Add((New-DismSwitchSpec -Token $token -Description "DISM option $token (from live help)."))
    }

    $script:DismCompletionCatalog.ExtraSwitchesByKey[$Key] = @($extras.ToArray())
}

function Initialize-DismCompletionCatalog {
    if ($script:DismCompletionCatalog.Initialized) {
        return
    }

    $static = Get-DismStaticCatalog
    $script:DismCompletionCatalog.Commands = @($static.Commands)
    $script:DismCompletionCatalog.GlobalSwitches = @($static.GlobalSwitches)

    $specs = @{}
    foreach ($switch in @($static.GlobalSwitches)) {
        $specs[(Get-DismOptionKey -Token $switch.Token)] = $switch
    }
    foreach ($command in @($static.Commands)) {
        $specs[(Get-DismOptionKey -Token $command.Token)] = $command
        foreach ($switch in @($command.Switches)) {
            $key = Get-DismOptionKey -Token $switch.Token
            if (-not $specs.ContainsKey($key)) {
                $specs[$key] = $switch
            }
        }
    }
    $script:DismCompletionCatalog.OptionSpecs = $specs
    $script:DismCompletionCatalog.Initialized = $true

    # DISM only prints help from an elevated shell; on any other shell the static catalog is the whole surface.
    if (Test-DismElevated) {
        $topHelp = Invoke-DismHelpText
        if ($topHelp.Count -gt 0) {
            $section = ''
            $liveCommands = New-Object System.Collections.Generic.List[object]
            foreach ($line in $topHelp) {
                if ($line -match '^\s*([A-Z][A-Z\s]+):\s*$') {
                    $section = $matches[1].Trim()
                    continue
                }

                if ($section -like '*COMMANDS*' -and $line -match '^\s*(/[A-Za-z][A-Za-z0-9\-]*:?)\s*(?:-|<|\{)') {
                    $token = $matches[1]
                    $key = Get-DismOptionKey -Token $token
                    if (-not $specs.ContainsKey($key) -and -not $specs.ContainsKey($key + ':')) {
                        $spec = New-DismCommandSpec -Token $token -Description "DISM command $token (from live help)."
                        [void]$liveCommands.Add($spec)
                        $specs[$key] = $spec
                    }
                }
            }

            if ($liveCommands.Count -gt 0) {
                $script:DismCompletionCatalog.Commands = @($static.Commands) + @($liveCommands.ToArray())
            }

            Add-DismLiveSwitchSet -Key '__top__' -HelpLines $topHelp
        }
    }
}

function Update-DismCommandCatalog {
    param([object]$Command, [bool]$Online)

    $key = Get-DismOptionKey -Token $Command.Token
    if ($script:DismCompletionCatalog.LiveCommandKeys.ContainsKey($key)) {
        return
    }
    $script:DismCompletionCatalog.LiveCommandKeys[$key] = $true

    if (-not (Test-DismElevated)) {
        return
    }

    $arguments = @()
    if ($Online) { $arguments += '/Online' }
    $arguments += $Command.Token.TrimEnd(':')
    $help = Invoke-DismHelpText -Arguments $arguments
    if ($help.Count -gt 0) {
        Add-DismLiveSwitchSet -Key $key -HelpLines $help
    }
}

function Get-DismActiveCommand {
    param([string[]]$Tokens)

    foreach ($token in @($Tokens)) {
        $key = Get-DismOptionKey -Token $token
        if ($null -eq $key) {
            continue
        }

        foreach ($command in @($script:DismCompletionCatalog.Commands)) {
            $commandKey = Get-DismOptionKey -Token $command.Token
            if ($commandKey -eq $key -or ($command.Token.EndsWith(':') -and $key -eq $commandKey.TrimEnd(':'))) {
                return $command
            }
        }
    }

    $null
}

function Get-DismOptionSpec {
    param([string]$Key, [object]$ActiveCommand)

    if ($ActiveCommand) {
        foreach ($switch in @($ActiveCommand.Switches)) {
            if ((Get-DismOptionKey -Token $switch.Token) -eq $Key) {
                return $switch
            }
        }
    }

    if ($script:DismCompletionCatalog.OptionSpecs.ContainsKey($Key)) {
        return $script:DismCompletionCatalog.OptionSpecs[$Key]
    }

    $null
}

function New-DismCompletionResult {
    param([string]$CompletionText, [string]$ListItemText, [string]$ResultType, [string]$ToolTip)

    if ([string]::IsNullOrWhiteSpace($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrWhiteSpace($ToolTip)) { $ToolTip = $CompletionText }
    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

function Get-DismPathCompletions {
    param(
        [string]$InputPath,
        [string]$Kind,
        [string[]]$AllowedExtensions
    )

    # Split on the last separator instead of Split-Path: '', 'C:\' and '.\' must list that directory's children
    # and the typed prefix must be preserved verbatim.
    $cleanInput = if ($null -eq $InputPath) { '' } else { $InputPath }
    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    if ($separatorIndex -ge 0) {
        $parentText = $cleanInput.Substring(0, $separatorIndex + 1)
        $leaf = $cleanInput.Substring($separatorIndex + 1)
    } else {
        $parentText = ''
        $leaf = $cleanInput
    }

    $parent = if ([string]::IsNullOrEmpty($parentText)) { '.' } else { $parentText }
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($leaf) + '*'
    $extensions = @($AllowedExtensions | ForEach-Object { $_.ToLowerInvariant() })

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern } | Sort-Object -Property Name)
    foreach ($item in $items) {
        if (-not $item.PSIsContainer) {
            if ($Kind -eq 'Directory') { continue }
            if ($extensions.Count -gt 0 -and ($extensions -notcontains $item.Extension.ToLowerInvariant())) { continue }
        }

        $text = $parentText + $item.Name
        if ($item.PSIsContainer) { $text += [System.IO.Path]::DirectorySeparatorChar }
        [pscustomobject]@{
            Text        = $text
            IsContainer = $item.PSIsContainer
            FullName    = $item.FullName
        }
    }
}

function Get-DismOptionValueCompletion {
    param(
        [string]$OptionPrefix,
        [string]$TypedValue,
        [object]$Spec,
        [string]$QuoteStyle
    )

    $valueQuoted = $TypedValue.StartsWith('"')
    $cleanValue = $TypedValue.Trim('"')
    if ($valueQuoted -and $QuoteStyle -eq 'None') { $QuoteStyle = 'Value' }

    switch ($Spec.Kind) {
        'Enum' {
            foreach ($value in @($Spec.Values)) {
                if ($value.StartsWith($cleanValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-DismCompletionResult -CompletionText ($OptionPrefix + $value) -ResultType 'ParameterValue' -ToolTip $Spec.Description
                }
            }
            return
        }
        { $_ -in @('Directory', 'File') } {
            $paths = @(Get-DismPathCompletions -InputPath $cleanValue -Kind $Spec.Kind -AllowedExtensions $Spec.Extensions)
            if ($paths.Count -eq 0) {
                if ([string]::IsNullOrEmpty($cleanValue)) {
                    $hint = if ($Spec.Kind -eq 'Directory') { '<directory>' } else { '<path>' }
                    New-DismCompletionResult -CompletionText ($OptionPrefix + $hint) -ResultType 'ParameterValue' -ToolTip $Spec.Description
                }
                return
            }

            foreach ($path in $paths) {
                $style = $QuoteStyle
                if ($style -eq 'None' -and $path.Text -match '\s') { $style = 'Token' }
                $text = switch ($style) {
                    'Token' { '"' + $OptionPrefix + $path.Text + '"' }
                    'Value' { $OptionPrefix + '"' + $path.Text + '"' }
                    default { $OptionPrefix + $path.Text }
                }
                $resultType = if ($path.IsContainer) { 'ProviderContainer' } else { 'ProviderItem' }
                New-DismCompletionResult -CompletionText $text -ListItemText ($OptionPrefix + $path.Text) -ResultType $resultType -ToolTip $path.FullName
            }
            return
        }
        default {
            if ([string]::IsNullOrEmpty($cleanValue)) {
                New-DismCompletionResult -CompletionText ($OptionPrefix + $Spec.Placeholder) -ResultType 'ParameterValue' -ToolTip $Spec.Description
            }
        }
    }
}

function Get-DismSwitchSuggestion {
    param([object]$ActiveCommand, [string]$CurrentWord)

    $suggestions = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $candidates = New-Object System.Collections.Generic.List[object]

    if ($ActiveCommand) {
        foreach ($switch in @($ActiveCommand.Switches)) { [void]$candidates.Add($switch) }
        $commandKey = Get-DismOptionKey -Token $ActiveCommand.Token
        if ($script:DismCompletionCatalog.ExtraSwitchesByKey.ContainsKey($commandKey)) {
            foreach ($switch in @($script:DismCompletionCatalog.ExtraSwitchesByKey[$commandKey])) { [void]$candidates.Add($switch) }
        }
        foreach ($switch in @($script:DismCompletionCatalog.GlobalSwitches)) { [void]$candidates.Add($switch) }
    } else {
        foreach ($command in @($script:DismCompletionCatalog.Commands)) { [void]$candidates.Add($command) }
        foreach ($switch in @($script:DismCompletionCatalog.GlobalSwitches)) { [void]$candidates.Add($switch) }
        if ($script:DismCompletionCatalog.ExtraSwitchesByKey.ContainsKey('__top__')) {
            foreach ($switch in @($script:DismCompletionCatalog.ExtraSwitchesByKey['__top__'])) { [void]$candidates.Add($switch) }
        }
    }

    foreach ($candidate in $candidates) {
        $key = $candidate.Token.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        if (-not [string]::IsNullOrEmpty($CurrentWord) -and -not $candidate.Token.StartsWith($CurrentWord, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $seen[$key] = $true
        [void]$suggestions.Add((New-DismCompletionResult -CompletionText $candidate.Token -ResultType 'ParameterName' -ToolTip $candidate.Description))
    }

    @($suggestions.ToArray())
}

function Complete-Dism {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    Initialize-DismCompletionCatalog

    # Tokens that end before the cursor form the context; the element under the cursor is the current word, cut at
    # the cursor; anything to the right is ignored.
    $tokensBefore = New-Object System.Collections.Generic.List[string]
    $currentWord = ''
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        $extent = $element.Extent
        if ($extent.EndOffset -lt $CursorPosition) {
            [void]$tokensBefore.Add($extent.Text)
            continue
        }
        if ($extent.StartOffset -le $CursorPosition) {
            $currentWord = $extent.Text.Substring(0, $CursorPosition - $extent.StartOffset)
        }
        break
    }
    if ([string]::IsNullOrEmpty($currentWord) -and -not [string]::IsNullOrEmpty($WordToComplete)) { $currentWord = $WordToComplete }

    $quoteStyle = 'None'
    $cleanWord = $currentWord
    if ($cleanWord.StartsWith('"')) {
        $quoteStyle = 'Token'
        $cleanWord = $cleanWord.Trim('"')
    }

    $activeCommand = Get-DismActiveCommand -Tokens @($tokensBefore.ToArray())
    $online = [bool](@($tokensBefore.ToArray()) | Where-Object { (Get-DismOptionKey -Token $_) -eq '/online' })
    if ($activeCommand) {
        Update-DismCommandCatalog -Command $activeCommand -Online $online
    }

    if ($cleanWord -match '^(/[A-Za-z][A-Za-z0-9\-]*:)(.*)$') {
        $optionPrefix = $matches[1]
        $typedValue = $matches[2]
        $spec = Get-DismOptionSpec -Key $optionPrefix.ToLowerInvariant() -ActiveCommand $activeCommand
        if ($spec) {
            return @(Get-DismOptionValueCompletion -OptionPrefix $optionPrefix -TypedValue $typedValue -Spec $spec -QuoteStyle $quoteStyle)
        }

        return @()
    }

    if ($cleanWord.StartsWith('/') -or [string]::IsNullOrWhiteSpace($cleanWord)) {
        return @(Get-DismSwitchSuggestion -ActiveCommand $activeCommand -CurrentWord $cleanWord)
    }

    if ($cleanWord -like '*\*' -or $cleanWord -like '[A-Za-z]:*') {
        return @(Get-DismPathCompletions -InputPath $cleanWord -Kind 'File' -AllowedExtensions @() | ForEach-Object {
            New-DismCompletionResult -CompletionText $_.Text -ResultType $(if ($_.IsContainer) { 'ProviderContainer' } else { 'ProviderItem' }) -ToolTip $_.FullName
        })
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'dism' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Dism -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
