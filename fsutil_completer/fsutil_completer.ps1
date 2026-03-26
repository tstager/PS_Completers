# fsutil native tab completion for PowerShell
# Parses fsutil help into a cached command tree and layers static value-aware hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name FsutilCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:FsutilCompletionCatalog = @{
        Initialized              = $false
        CommandName              = $null
        NodesByKey               = @{}
        LoadedKeys               = @{}
        LeafHelpByKey            = @{}
        BehaviorQueryOptions     = @()
        BehaviorSetValueMaps     = @{}
        SpecsByKey               = @{}
    }
}

function New-FsutilCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $ListItemText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Remove-FsutilOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return $Value
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-FsutilQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        $escaped = $Value.Replace('`', '``').Replace('"', '`"')
        return '"' + $escaped + '"'
    }

    $Value
}

function Resolve-FsutilCommandName {
    if ($script:FsutilCompletionCatalog.CommandName) {
        return $script:FsutilCompletionCatalog.CommandName
    }

    $command = Get-Command -Name fsutil.exe, fsutil -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $script:FsutilCompletionCatalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $script:FsutilCompletionCatalog.CommandName
}

function Test-FsutilCommandAvailable {
    [bool](Resolve-FsutilCommandName)
}

function Get-FsutilPathKey {
    param([string[]]$PathTokens)

    $PathTokens = @($PathTokens)
    if (-not $PathTokens -or $PathTokens.Count -eq 0) {
        return '__ROOT__'
    }

    (($PathTokens | ForEach-Object { $_.ToLowerInvariant() }) -join [string][char]31)
}

function Get-FsutilNode {
    param(
        [string[]]$PathTokens,
        [switch]$Create
    )

    $key = Get-FsutilPathKey -PathTokens $PathTokens
    if (-not $script:FsutilCompletionCatalog.NodesByKey.ContainsKey($key)) {
        if (-not $Create) {
            return $null
        }

        $script:FsutilCompletionCatalog.NodesByKey[$key] = @{
            PathTokens = @($PathTokens)
            Children   = [ordered]@{}
        }
    }

    $script:FsutilCompletionCatalog.NodesByKey[$key]
}

function Add-FsutilChildNode {
    param(
        [string[]]$PathTokens,
        [string]$Name,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return
    }

    $node = Get-FsutilNode -PathTokens $PathTokens -Create
    $key = $Name.ToLowerInvariant()
    if (-not $node.Children.Contains($key)) {
        $node.Children[$key] = [pscustomobject]@{
            CompletionText = $Name
            Description    = $Description
        }
    }
}

function Get-FsutilStaticRootEntries {
    @(
        @{ Name = '8dot3name';      Description = '8dot3name management' }
        @{ Name = 'behavior';       Description = 'Control file system behavior' }
        @{ Name = 'bypassIo';       Description = 'BypassIo management' }
        @{ Name = 'clfs';           Description = 'CLFS logfile management' }
        @{ Name = 'dax';            Description = 'Dax volume management' }
        @{ Name = 'devdrv';         Description = 'Developer volume management' }
        @{ Name = 'dirty';          Description = 'Manage volume dirty bit' }
        @{ Name = 'file';           Description = 'File specific commands' }
        @{ Name = 'fsInfo';         Description = 'File system information' }
        @{ Name = 'hardlink';       Description = 'Hard link management' }
        @{ Name = 'objectID';       Description = 'Object ID management' }
        @{ Name = 'quota';          Description = 'Quota management' }
        @{ Name = 'repair';         Description = 'Self healing management' }
        @{ Name = 'reparsePoint';   Description = 'Reparse point management' }
        @{ Name = 'storageReserve'; Description = 'Storage Reserve management' }
        @{ Name = 'resource';       Description = 'Transactional Resource Manager management' }
        @{ Name = 'sparse';         Description = 'Sparse file control' }
        @{ Name = 'tiering';        Description = 'Storage tiering property management' }
        @{ Name = 'trace';          Description = 'File system trace management' }
        @{ Name = 'transaction';    Description = 'Transaction management' }
        @{ Name = 'usn';            Description = 'USN management' }
        @{ Name = 'volume';         Description = 'Volume management' }
        @{ Name = 'wim';            Description = 'Transparent wim hosting management' }
    )
}

function Get-FsutilStaticFamilyFallbacks {
    @{
        '8dot3name' = @(
            @{ Name = 'query'; Description = 'Query the current setting for the shortname behavior on the system' }
            @{ Name = 'scan';  Description = 'Scan for impacted registry entries' }
            @{ Name = 'set';   Description = 'Change the setting that controls the shortname behavior on the system' }
            @{ Name = 'strip'; Description = 'Remove the shortnames for all files within a directory' }
        )
        'behavior' = @(
            @{ Name = 'query'; Description = 'Query the file system behavior parameters' }
            @{ Name = 'set';   Description = 'Change the file system behavior parameters' }
        )
        'file' = @(
            @{ Name = 'createNew';                Description = 'Creates a new file of a specified size' }
            @{ Name = 'findBySID';                Description = 'Find a file by security identifier' }
            @{ Name = 'layout';                   Description = 'Query all the information available about the file' }
            @{ Name = 'optimizeMetadata';         Description = 'Optimize metadata for a file' }
            @{ Name = 'queryAllocRanges';         Description = 'Query the allocated ranges for a file' }
            @{ Name = 'queryCaseSensitiveInfo';   Description = 'Query the case sensitive information for a directory' }
            @{ Name = 'queryEA';                  Description = 'Query the extended attributes (EA) information for a file' }
            @{ Name = 'queryExtents';             Description = 'Query the extents for a file' }
            @{ Name = 'queryExtentsAndRefCounts'; Description = 'Query the extents and their corresponding refcounts for a file' }
            @{ Name = 'queryFileID';              Description = 'Queries the file ID of the specified file' }
            @{ Name = 'queryFileNameById';        Description = 'Displays a random link name for the file ID' }
            @{ Name = 'queryProcessesUsing';      Description = 'Query the set of processes which have a file opened' }
            @{ Name = 'queryOptimizeMetadata';    Description = 'Query the optimize metadata state for a file' }
            @{ Name = 'queryValidData';           Description = 'Queries the valid data length for the file' }
            @{ Name = 'setCaseSensitiveInfo';     Description = 'Set the case sensitive information for a directory' }
            @{ Name = 'setShortName';             Description = 'Set the short name for a file' }
            @{ Name = 'setValidData';             Description = 'Set the valid data length for a file' }
            @{ Name = 'setZeroData';              Description = 'Set the zero data for a file' }
            @{ Name = 'setEOF';                   Description = 'Sets the end of file for an existing file' }
            @{ Name = 'setStrictlySequential';    Description = 'Sets ReFS SMR file as strictly sequential' }
        )
        'fsinfo' = @(
            @{ Name = 'drives';     Description = 'List all drives' }
            @{ Name = 'driveType';  Description = 'Query drive type for a drive' }
            @{ Name = 'ntfsInfo';   Description = 'Query NTFS specific volume information' }
            @{ Name = 'refsInfo';   Description = 'Query REFS specific volume information' }
            @{ Name = 'sectorInfo'; Description = 'Query sector information' }
            @{ Name = 'statistics'; Description = 'Query file system statistics' }
            @{ Name = 'volumeInfo'; Description = 'Query volume information' }
        )
        'hardlink' = @(
            @{ Name = 'create'; Description = 'Create a hard link' }
            @{ Name = 'list';   Description = 'Enumerate hard links on a file' }
        )
        'objectid' = @(
            @{ Name = 'create'; Description = 'Create the object identifier' }
            @{ Name = 'delete'; Description = 'Delete the object identifier' }
            @{ Name = 'query';  Description = 'Query the object identifier' }
            @{ Name = 'set';    Description = 'Change the object identifier' }
        )
        'quota' = @(
            @{ Name = 'disable';    Description = 'Disable quota tracking and enforcement' }
            @{ Name = 'enforce';    Description = 'Enable quota enforcement' }
            @{ Name = 'modify';     Description = 'Set disk quota for a user' }
            @{ Name = 'query';      Description = 'Query disk quotas' }
            @{ Name = 'track';      Description = 'Enable quota tracking' }
            @{ Name = 'violations'; Description = 'Display quota violations' }
        )
        'repair' = @(
            @{ Name = 'enumerate'; Description = 'Enumerate the entries of a volume''s corruption log' }
            @{ Name = 'initiate';  Description = 'Initiate the repair of a file' }
            @{ Name = 'query';     Description = 'Query the self healing state of the volume' }
            @{ Name = 'set';       Description = 'Set the self healing state of the volume' }
            @{ Name = 'state';     Description = 'Query the corruption state of the volume(s)' }
            @{ Name = 'wait';      Description = 'Wait for repair(s) to complete' }
        )
        'reparsepoint' = @(
            @{ Name = 'delete'; Description = 'Delete a reparse point' }
            @{ Name = 'query';  Description = 'Query a reparse point' }
        )
        'sparse' = @(
            @{ Name = 'queryFlag';  Description = 'Query sparse' }
            @{ Name = 'queryRange'; Description = 'Query range' }
            @{ Name = 'setFlag';    Description = 'Set sparse' }
            @{ Name = 'setRange';   Description = 'Set sparse range' }
        )
        'usn' = @(
            @{ Name = 'createJournal';       Description = 'Create a USN journal' }
            @{ Name = 'deleteJournal';       Description = 'Delete a USN journal' }
            @{ Name = 'enableRangeTracking'; Description = 'Enable write range tracking for a volume' }
            @{ Name = 'enumData';            Description = 'Enumerate USN data' }
            @{ Name = 'queryJournal';        Description = 'Query the USN data for a volume' }
            @{ Name = 'readJournal';         Description = 'Reads the USN records in the USN journal' }
            @{ Name = 'readData';            Description = 'Read the USN data for a file' }
        )
        'volume' = @(
            @{ Name = 'allocationReport';  Description = 'Allocated clusters report' }
            @{ Name = 'diskFree';          Description = 'Query the free space of a volume' }
            @{ Name = 'dismount';          Description = 'Dismount a volume' }
            @{ Name = 'findShrinkBlocker'; Description = 'Find files that are blocking volume shrink' }
            @{ Name = 'fileLayout';        Description = 'Query all the information available about the file(s)' }
            @{ Name = 'flush';             Description = 'Flush a volume' }
            @{ Name = 'list';              Description = 'List volumes' }
            @{ Name = 'queryCluster';      Description = 'Query which file is using a particular cluster' }
            @{ Name = 'queryLabel';        Description = 'Query the label for a volume' }
            @{ Name = 'queryNumaInfo';     Description = 'Queries the NUMA node for the given volume' }
            @{ Name = 'setLabel';          Description = 'Set the label for a volume' }
            @{ Name = 'smrGC';             Description = 'Control SMR Garbage Collection' }
            @{ Name = 'smrInfo';           Description = 'Query SMR information' }
            @{ Name = 'tpInfo';            Description = 'Query thin provisioning info for the given volume' }
            @{ Name = 'upgrade';           Description = 'Trigger an upgrade of the specified volume' }
        )
        'wim' = @(
            @{ Name = 'enumFiles'; Description = 'Enumerate WIM backed files' }
            @{ Name = 'enumWims';  Description = 'Enumerate backing WIM files' }
            @{ Name = 'removeWim'; Description = 'Remove a WIM from backing files' }
            @{ Name = 'queryFile'; Description = 'Query the origin of a specific file' }
        )
    }
}

function Get-FsutilStaticSpecs {
    @{
        (Get-FsutilPathKey @('8dot3name', 'query')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('8dot3name', 'scan')) = @{
            Positionals = @('DirectoryPath')
            Options     = @(
                @{ Token = '/s'; Description = 'Scan subdirectories.' }
                @{ Token = '/l'; Description = 'Write a log file.'; ValueKind = 'LogFilePath' }
                @{ Token = '/v'; Description = 'Verbose output.' }
            )
        }
        (Get-FsutilPathKey @('8dot3name', 'set')) = @{
            Handler = '8dot3nameSet'
        }
        (Get-FsutilPathKey @('8dot3name', 'strip')) = @{
            Positionals = @('DirectoryPath')
            Options     = @(
                @{ Token = '/t'; Description = 'Test mode.' }
                @{ Token = '/s'; Description = 'Process subdirectories.' }
                @{ Token = '/f'; Description = 'Force removal.' }
                @{ Token = '/l'; Description = 'Write a log file.'; ValueKind = 'LogFilePath' }
                @{ Token = '/v'; Description = 'Verbose output.' }
            )
        }
        (Get-FsutilPathKey @('behavior', 'query')) = @{
            Handler = 'BehaviorQuery'
        }
        (Get-FsutilPathKey @('behavior', 'set')) = @{
            Handler = 'BehaviorSet'
        }
        (Get-FsutilPathKey @('file', 'createNew')) = @{
            Positionals = @('FilePath', 'Length')
        }
        (Get-FsutilPathKey @('file', 'queryAllocRanges')) = @{
            Handler = 'FileQueryAllocRanges'
        }
        (Get-FsutilPathKey @('file', 'queryCaseSensitiveInfo')) = @{
            Positionals = @('DirectoryPath')
        }
        (Get-FsutilPathKey @('file', 'queryFileID')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('file', 'queryFileNameById')) = @{
            Handler = 'FileQueryFileNameById'
        }
        (Get-FsutilPathKey @('file', 'queryProcessesUsing')) = @{
            Positionals = @('Path')
            Options     = @(
                @{ Token = '/C'; Description = 'Search child items recursively.' }
            )
        }
        (Get-FsutilPathKey @('file', 'queryValidData')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('fsInfo', 'driveType')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('fsInfo', 'ntfsInfo')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('fsInfo', 'refsInfo')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('fsInfo', 'sectorInfo')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('fsInfo', 'statistics')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('fsInfo', 'volumeInfo')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('hardlink', 'create')) = @{
            Positionals = @('FilePath', 'FilePath')
        }
        (Get-FsutilPathKey @('hardlink', 'list')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('objectID', 'create')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('objectID', 'delete')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('objectID', 'query')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('objectID', 'set')) = @{
            Handler = 'ObjectIdSet'
        }
        (Get-FsutilPathKey @('quota', 'disable')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('quota', 'enforce')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('quota', 'modify')) = @{
            Positionals = @('VolumePath', 'Threshold', 'Limit', 'UserOrSid')
        }
        (Get-FsutilPathKey @('quota', 'query')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('quota', 'track')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('quota', 'violations')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('repair', 'enumerate')) = @{
            Handler = 'RepairEnumerate'
        }
        (Get-FsutilPathKey @('repair', 'query')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('repair', 'set')) = @{
            Handler = 'RepairSet'
        }
        (Get-FsutilPathKey @('repair', 'wait')) = @{
            Handler = 'RepairWait'
        }
        (Get-FsutilPathKey @('reparsePoint', 'delete')) = @{
            Positionals = @('Path')
        }
        (Get-FsutilPathKey @('reparsePoint', 'query')) = @{
            Positionals = @('Path')
        }
        (Get-FsutilPathKey @('sparse', 'queryFlag')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('sparse', 'queryRange')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('sparse', 'setFlag')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('sparse', 'setRange')) = @{
            Positionals = @('FilePath', 'Offset', 'Length')
        }
        (Get-FsutilPathKey @('storageReserve', 'findByID')) = @{
            Handler = 'StorageReserveFindById'
        }
        (Get-FsutilPathKey @('storageReserve', 'query')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('storageReserve', 'repair')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('transaction', 'query')) = @{
            Handler = 'TransactionQuery'
        }
        (Get-FsutilPathKey @('usn', 'createJournal')) = @{
            Handler = 'UsnCreateJournal'
        }
        (Get-FsutilPathKey @('usn', 'deleteJournal')) = @{
            Handler = 'UsnDeleteJournal'
        }
        (Get-FsutilPathKey @('usn', 'enableRangeTracking')) = @{
            Handler = 'UsnEnableRangeTracking'
        }
        (Get-FsutilPathKey @('usn', 'enumData')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('usn', 'queryJournal')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('usn', 'readJournal')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('usn', 'readData')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('volume', 'allocationReport')) = @{
            Handler = 'VolumeAllocationReport'
        }
        (Get-FsutilPathKey @('volume', 'diskFree')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('volume', 'dismount')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('volume', 'flush')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('volume', 'queryCluster')) = @{
            Handler = 'VolumeQueryCluster'
        }
        (Get-FsutilPathKey @('volume', 'queryLabel')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('volume', 'queryNumaInfo')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('volume', 'setLabel')) = @{
            Positionals = @('VolumePath', 'Label')
        }
        (Get-FsutilPathKey @('volume', 'findShrinkBlocker')) = @{
            Handler = 'VolumeFindShrinkBlocker'
        }
        (Get-FsutilPathKey @('volume', 'smrInfo')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('volume', 'tpInfo')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('volume', 'upgrade')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('wim', 'enumFiles')) = @{
            Handler = 'WimEnumFiles'
        }
        (Get-FsutilPathKey @('wim', 'queryFile')) = @{
            Positionals = @('FilePath')
        }
    }
}

function Invoke-FsutilHelpText {
    param(
        [string[]]$Arguments,
        [switch]$Bare
    )

    $commandName = Resolve-FsutilCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        if ($Bare) {
            return @(& $commandName @Arguments 2>$null)
        }

        return @(& $commandName @Arguments '/?' 2>$null)
    } catch {
        @()
    }
}

function Get-FsutilHelpEntries {
    param([string[]]$Lines)

    $entries = New-Object System.Collections.Generic.List[object]
    $inCommandList = $false

    foreach ($line in @($Lines)) {
        if ($line -match '^\s*---- .*Commands Supported ----\s*$') {
            $inCommandList = $true
            continue
        }

        if (-not $inCommandList) {
            continue
        }

        if ($line -match '^\s*Please use ') {
            break
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match '^\s*(?<name>[A-Za-z0-9]+)\s{2,}(?<description>.+?)\s*$') {
            $entries.Add([pscustomobject]@{
                    Name        = $matches.name
                    Description = $matches.description.Trim()
                })
        }
    }

    @($entries.ToArray())
}

function Ensure-FsutilPathLoaded {
    param([string[]]$PathTokens)

    $key = Get-FsutilPathKey -PathTokens $PathTokens
    if ($script:FsutilCompletionCatalog.LoadedKeys.ContainsKey($key)) {
        return
    }

    $entries = @()
    if (-not $PathTokens -or $PathTokens.Count -eq 0) {
        $entries = Get-FsutilHelpEntries -Lines (Invoke-FsutilHelpText -Arguments @() -Bare)
        if (-not $entries -or $entries.Count -eq 0) {
            $entries = foreach ($entry in (Get-FsutilStaticRootEntries)) {
                [pscustomobject]@{
                    Name        = $entry.Name
                    Description = $entry.Description
                }
            }
        }
    } elseif ($PathTokens.Count -eq 1) {
        $entries = Get-FsutilHelpEntries -Lines (Invoke-FsutilHelpText -Arguments $PathTokens -Bare)
        if ((-not $entries -or $entries.Count -eq 0)) {
            $fallbacks = Get-FsutilStaticFamilyFallbacks
            $familyKey = $PathTokens[0].ToLowerInvariant()
            if ($fallbacks.ContainsKey($familyKey)) {
                $entries = foreach ($entry in $fallbacks[$familyKey]) {
                    [pscustomobject]@{
                        Name        = $entry.Name
                        Description = $entry.Description
                    }
                }
            }
        }
    } else {
        $entries = Get-FsutilHelpEntries -Lines (Invoke-FsutilHelpText -Arguments $PathTokens)
    }

    foreach ($entry in @($entries)) {
        Add-FsutilChildNode -PathTokens $PathTokens -Name $entry.Name -Description $entry.Description
    }

    $script:FsutilCompletionCatalog.LoadedKeys[$key] = $true
}

function Get-FsutilLeafHelpLines {
    param([string[]]$PathTokens)

    $key = Get-FsutilPathKey -PathTokens $PathTokens
    if (-not $script:FsutilCompletionCatalog.LeafHelpByKey.ContainsKey($key)) {
        $script:FsutilCompletionCatalog.LeafHelpByKey[$key] = @(Invoke-FsutilHelpText -Arguments $PathTokens)
    }

    @($script:FsutilCompletionCatalog.LeafHelpByKey[$key])
}

function Resolve-FsutilCommandPath {
    param([string[]]$Tokens)

    $Tokens = @($Tokens)
    $path = @()
    $consumedCount = 0

    while ($consumedCount -lt $Tokens.Count) {
        Ensure-FsutilPathLoaded -PathTokens $path
        $node = Get-FsutilNode -PathTokens $path
        if (-not $node -or $node.Children.Count -eq 0) {
            break
        }

        $lookup = (Remove-FsutilOuterQuotes -Value $Tokens[$consumedCount]).ToLowerInvariant()
        if (-not $node.Children.Contains($lookup)) {
            break
        }

        $path += $node.Children[$lookup].CompletionText
        $consumedCount++
    }

    $remaining = @()
    if ($consumedCount -lt $Tokens.Count) {
        $remaining = @($Tokens[$consumedCount..($Tokens.Count - 1)])
    }

    [pscustomobject]@{
        PathTokens    = [string[]]@($path)
        ConsumedCount = $consumedCount
        Remaining     = [string[]]@($remaining)
    }
}

function Get-FsutilCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') {
        return ''
    }

    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-FsutilTokensBeforeCurrent {
    param(
        [string[]]$Tokens,
        [string]$CurrentWord,
        [bool]$HasTrailingSpace
    )

    if ($HasTrailingSpace) {
        return @($Tokens)
    }

    if (-not $Tokens -or $Tokens.Count -eq 0) {
        return @()
    }

    if (-not [string]::IsNullOrEmpty($CurrentWord)) {
        for ($suffixLength = 1; $suffixLength -le $Tokens.Count; $suffixLength++) {
            $suffix = (@($Tokens | Select-Object -Last $suffixLength) -join '')
            if ($suffix -eq $CurrentWord) {
                $prefixLength = $Tokens.Count - $suffixLength
                if ($prefixLength -le 0) {
                    return @()
                }

                return @($Tokens | Select-Object -First $prefixLength)
            }
        }
    }

    if ($Tokens.Count -gt 1) {
        return @($Tokens | Select-Object -First ($Tokens.Count - 1))
    }

    @()
}

function Get-FsutilChildSuggestions {
    param(
        [System.Collections.IDictionary]$Children,
        [string]$WordToComplete
    )

    if (-not $Children) {
        return @()
    }

    $cleanCurrent = Remove-FsutilOuterQuotes -Value $WordToComplete
    foreach ($entry in $Children.Values) {
        if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or $entry.CompletionText.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-FsutilCompletionResult -CompletionText $entry.CompletionText -ResultType 'ParameterValue' -ToolTip $entry.Description
        }
    }
}

function Get-FsutilLiteralCompletions {
    param(
        [string]$CurrentValue,
        [object[]]$Items,
        [string]$DefaultToolTip = 'fsutil value'
    )

    $cleanCurrent = Remove-FsutilOuterQuotes -Value $CurrentValue
    foreach ($item in @($Items)) {
        $completionText = $null
        $listItemText = $null
        $toolTip = $DefaultToolTip
        $resultType = 'ParameterValue'

        if ($item -is [hashtable] -or $item -is [pscustomobject]) {
            $completionText = [string]$item.CompletionText
            $listItemText = if ($item.PSObject.Properties.Name -contains 'ListItemText') { [string]$item.ListItemText } else { $completionText }
            if ($item.PSObject.Properties.Name -contains 'ToolTip') {
                $toolTip = [string]$item.ToolTip
            }
            if ($item.PSObject.Properties.Name -contains 'ResultType') {
                $resultType = [string]$item.ResultType
            }
        } else {
            $completionText = [string]$item
            $listItemText = $completionText
        }

        if ([string]::IsNullOrWhiteSpace($completionText)) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or $completionText.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-FsutilCompletionResult -CompletionText $completionText -ListItemText $listItemText -ResultType $resultType -ToolTip $toolTip
        }
    }
}

function Get-FsutilPlaceholderCompletions {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip
    )

    $cleanCurrent = Remove-FsutilOuterQuotes -Value $CurrentValue
    if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or
        $Placeholder.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
        return @(
            New-FsutilCompletionResult -CompletionText $Placeholder -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-FsutilCompletionResult -CompletionText $CurrentValue -ListItemText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-FsutilPathCompletions {
    param(
        [string]$InputPath,
        [ValidateSet('Any', 'File', 'Directory')]
        [string]$ItemMode = 'Any'
    )

    $cleanInput = Remove-FsutilOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput -match '^[A-Za-z]:$') {
        $parent = $cleanInput + '\'
        $leaf = ''
    } elseif ($cleanInput -match '[\\/]$') {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $inputIsRooted = -not [string]::IsNullOrWhiteSpace($cleanInput) -and [System.IO.Path]::IsPathRooted($cleanInput)
    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = @($items | Where-Object { $_.Name -like "$leaf*" })

    if ($ItemMode -eq 'File') {
        $items = @($items | Where-Object { -not $_.PSIsContainer })
    } elseif ($ItemMode -eq 'Directory') {
        $items = @($items | Where-Object { $_.PSIsContainer })
    }

    foreach ($item in ($items | Sort-Object -Property @{ Expression = 'PSIsContainer'; Descending = $true }, Name)) {
        if ($inputIsRooted) {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $pathText = $item.Name
        } else {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $quoted = ConvertTo-FsutilQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        $resultType = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ProviderItem' }
        New-FsutilCompletionResult -CompletionText $quoted -ListItemText $pathText -ResultType $resultType -ToolTip $item.FullName
    }
}

function Get-FsutilVolumePathCompletions {
    param(
        [string]$CurrentValue,
        [switch]$DriveNameOnly
    )

    $cleanCurrent = Remove-FsutilOuterQuotes -Value $CurrentValue
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^[A-Za-z]$' } |
            Sort-Object -Property Name)) {
        $driveName = $drive.Name + ':'
        if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or
            $driveName.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            $items.Add([pscustomobject]@{
                    CompletionText = $driveName
                    ToolTip        = 'Volume path'
                })
        }

        if (-not $DriveNameOnly) {
            $driveRoot = $drive.Name + ':\'
            if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or
                $driveRoot.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
                $items.Add([pscustomobject]@{
                        CompletionText = $driveRoot
                        ToolTip        = 'Drive root path'
                    })
            }
        }
    }

    $guidPlaceholder = '\\?\Volume{GUID}\'
    if (-not $DriveNameOnly -and (
            [string]::IsNullOrWhiteSpace($cleanCurrent) -or
            $guidPlaceholder.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase))) {
        $items.Add([pscustomobject]@{
                CompletionText = $guidPlaceholder
                ToolTip        = 'Volume GUID path placeholder'
            })
    }

    Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @($items.ToArray()) -DefaultToolTip 'Volume path'
}

function Get-FsutilOptionInfo {
    param(
        [hashtable]$Spec,
        [string]$Token
    )

    if (-not $Spec -or -not ($Spec.ContainsKey('Options'))) {
        return $null
    }

    $lookup = (Remove-FsutilOuterQuotes -Value $Token).ToLowerInvariant()
    foreach ($option in @($Spec.Options)) {
        if ([string]$option.Token -ieq $lookup) {
            return $option
        }
    }

    $null
}

function Get-FsutilArgumentState {
    param(
        [hashtable]$Spec,
        [string[]]$Tokens
    )

    $state = @{
        Positionals      = @()
        PendingValueKind = $null
        SeenOptions      = @()
    }

    foreach ($token in @($Tokens)) {
        $cleanToken = Remove-FsutilOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($state.PendingValueKind) {
            $state.Positionals += [pscustomobject]@{
                Kind  = $state.PendingValueKind
                Value = $cleanToken
            }
            $state.PendingValueKind = $null
            continue
        }

        $optionInfo = Get-FsutilOptionInfo -Spec $Spec -Token $cleanToken
        if ($optionInfo) {
            $state.SeenOptions += ([string]$optionInfo.Token).ToLowerInvariant()
            if ($optionInfo.ContainsKey('ValueKind')) {
                $state.PendingValueKind = [string]$optionInfo.ValueKind
            }
            continue
        }

        $state.Positionals += [pscustomobject]@{
            Kind  = $null
            Value = $cleanToken
        }
    }

    $state
}

function Get-FsutilOptionCompletions {
    param(
        [hashtable]$Spec,
        [string]$CurrentValue,
        [hashtable]$State
    )

    if (-not $Spec -or -not ($Spec.ContainsKey('Options'))) {
        return @()
    }

    $cleanCurrent = Remove-FsutilOuterQuotes -Value $CurrentValue
    foreach ($option in @($Spec.Options)) {
        $token = [string]$option.Token
        if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or $token.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-FsutilCompletionResult -CompletionText $token -ListItemText $token -ResultType 'ParameterName' -ToolTip $option.Description
        }
    }
}

function Ensure-FsutilBehaviorMetadata {
    if ($script:FsutilCompletionCatalog.BehaviorQueryOptions.Count -gt 0 -and
        $script:FsutilCompletionCatalog.BehaviorSetValueMaps.Count -gt 0) {
        return
    }

    $queryOptions = New-Object System.Collections.Generic.List[string]
    $queryLines = Get-FsutilLeafHelpLines -PathTokens @('behavior', 'query')
    $inOptionsBlock = $false
    foreach ($line in @($queryLines)) {
        if ($line -match '^\s*<options>\s*$') {
            $inOptionsBlock = $true
            continue
        }

        if (-not $inOptionsBlock) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match '^\s*(Sample commands|Example)') {
            break
        }

        if ($line -match '^\s*(?<name>[A-Za-z0-9]+)') {
            $name = [string]$matches['name']
            if ($name -cmatch '^[a-z][A-Za-z0-9]+$') {
                $queryOptions.Add($name)
            }
        }
    }

    $setMaps = @{}
    $setLines = Get-FsutilLeafHelpLines -PathTokens @('behavior', 'set')
    foreach ($line in @($setLines)) {
        if ($line -match '^\s*(?<name>[A-Za-z0-9]+)\s{2,}(?<values>.+?)\s*$') {
            $name = [string]$matches['name']
            $values = [string]$matches['values']
            if ($name -ine '<option>') {
                $setMaps[$name.ToLowerInvariant()] = [pscustomobject]@{
                    Name       = $name
                    ValueShape = $values.Trim()
                }
            }
        }
    }

    $script:FsutilCompletionCatalog.BehaviorQueryOptions = @($queryOptions | Sort-Object -Unique)
    $script:FsutilCompletionCatalog.BehaviorSetValueMaps = $setMaps
}

function Get-FsutilValueKindCompletions {
    param(
        [string]$ValueKind,
        [string]$CurrentValue,
        [hashtable]$Context
    )

    switch ($ValueKind) {
        'VolumePath' {
            $results = @(Get-FsutilVolumePathCompletions -CurrentValue $CurrentValue)
            if ($results.Count -eq 0) {
                return @(
                    New-FsutilCompletionResult -CompletionText '<volume>' -ListItemText '<volume>' -ResultType 'ParameterValue' -ToolTip 'Volume path'
                )
            }
            return $results
        }
        'DriveName' {
            $results = @(Get-FsutilVolumePathCompletions -CurrentValue $CurrentValue -DriveNameOnly)
            if ($results.Count -eq 0) {
                return @(
                    New-FsutilCompletionResult -CompletionText '<drive>' -ListItemText '<drive>' -ResultType 'ParameterValue' -ToolTip 'Drive name'
                )
            }
            return $results
        }
        'FilePath' {
            $results = @(Get-FsutilPathCompletions -InputPath $CurrentValue -ItemMode Any)
            if ($results.Count -eq 0) {
                return @(Get-FsutilPlaceholderCompletions -CurrentValue $CurrentValue -Placeholder '<filename>' -ToolTip 'File path')
            }
            return $results
        }
        'DirectoryPath' {
            $results = @(Get-FsutilPathCompletions -InputPath $CurrentValue -ItemMode Directory)
            if ($results.Count -eq 0) {
                return @(Get-FsutilPlaceholderCompletions -CurrentValue $CurrentValue -Placeholder '<DirectoryPath>' -ToolTip 'Directory path')
            }
            return $results
        }
        'LogFilePath' {
            $results = @(Get-FsutilPathCompletions -InputPath $CurrentValue -ItemMode Any)
            if ($results.Count -eq 0) {
                return @(Get-FsutilPlaceholderCompletions -CurrentValue $CurrentValue -Placeholder '<log-file>' -ToolTip 'Log file path')
            }
            return $results
        }
        'Path' {
            $results = @(Get-FsutilPathCompletions -InputPath $CurrentValue -ItemMode Any)
            if ($results.Count -eq 0) {
                return @(Get-FsutilPlaceholderCompletions -CurrentValue $CurrentValue -Placeholder '<path>' -ToolTip 'Path')
            }
            return $results
        }
        'Length' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '0';    ToolTip = 'Zero length' }
                    @{ CompletionText = '1024'; ToolTip = 'Example byte length' }
                    @{ CompletionText = '4096'; ToolTip = 'Example byte length' }
                ) -DefaultToolTip 'Length')
        }
        'Offset' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '0';     ToolTip = 'Offset 0' }
                    @{ CompletionText = '4096';  ToolTip = 'Example byte offset' }
                    @{ CompletionText = '65536'; ToolTip = 'Example byte offset' }
                ) -DefaultToolTip 'Offset')
        }
        'Boolean01' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '0'; ToolTip = 'Disabled / false' }
                    @{ CompletionText = '1'; ToolTip = 'Enabled / true' }
                ) -DefaultToolTip '0 or 1')
        }
        'Range03' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '0'; ToolTip = 'Value 0' }
                    @{ CompletionText = '1'; ToolTip = 'Value 1' }
                    @{ CompletionText = '2'; ToolTip = 'Value 2' }
                    @{ CompletionText = '3'; ToolTip = 'Value 3' }
                ) -DefaultToolTip '0 through 3')
        }
        'Threshold' {
            return @(Get-FsutilPlaceholderCompletions -CurrentValue $CurrentValue -Placeholder '<threshold>' -ToolTip 'Quota threshold')
        }
        'Limit' {
            return @(Get-FsutilPlaceholderCompletions -CurrentValue $CurrentValue -Placeholder '<limit>' -ToolTip 'Quota limit')
        }
        'UserOrSid' {
            return @(Get-FsutilPlaceholderCompletions -CurrentValue $CurrentValue -Placeholder '<user>' -ToolTip 'User or SID')
        }
        'Label' {
            return @(Get-FsutilPlaceholderCompletions -CurrentValue $CurrentValue -Placeholder '<label>' -ToolTip 'Volume label')
        }
        'Hex32' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '40dff02fc9b4d4118f120090273fa9fc'; ToolTip = '32-digit hexadecimal value' }
                    @{ CompletionText = '00000000000000000000000000000000'; ToolTip = '32-digit hexadecimal value' }
                ) -DefaultToolTip '32-digit hexadecimal value')
        }
        'FileId' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '0x0000000000000000'; ToolTip = 'Example 64-bit file ID' }
                    @{ CompletionText = '<fileid>'; ToolTip = 'File ID' }
                ) -DefaultToolTip 'File ID')
        }
        'Guid' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '{00000000-0000-0000-0000-000000000000}'; ToolTip = 'Transaction GUID placeholder' }
                ) -DefaultToolTip 'GUID')
        }
        'RepairFlags' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '0';    ToolTip = 'Disable general repair' }
                    @{ CompletionText = '1';    ToolTip = 'Enable general repair' }
                    @{ CompletionText = '9';    ToolTip = 'Enable repair and warn about potential data loss' }
                    @{ CompletionText = '0x10'; ToolTip = 'Disable repair and bugcheck on first corruption' }
                ) -DefaultToolTip 'Repair flags')
        }
        'RepairLogName' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '$corrupt'; ToolTip = 'Corruption log' }
                    @{ CompletionText = '$verify';  ToolTip = 'Verify log' }
                ) -DefaultToolTip 'Repair log name')
        }
        'WaitType' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '0'; ToolTip = 'Wait type 0' }
                    @{ CompletionText = '1'; ToolTip = 'Wait type 1' }
                ) -DefaultToolTip 'Wait type')
        }
        'Cluster' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '50';     ToolTip = 'Example cluster number' }
                    @{ CompletionText = '0x2000'; ToolTip = 'Example hexadecimal cluster number' }
                    @{ CompletionText = '<cluster>'; ToolTip = 'Cluster number' }
                ) -DefaultToolTip 'Cluster number')
        }
        'DataSource' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '0'; ToolTip = 'Example WIM data source / index' }
                    @{ CompletionText = '1'; ToolTip = 'Example WIM data source / index' }
                    @{ CompletionText = '<data-source>'; ToolTip = 'Data source' }
                ) -DefaultToolTip 'Data source')
        }
    }

    @()
}

function Get-FsutilGenericArgumentCompletions {
    param(
        [hashtable]$Spec,
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $state = Get-FsutilArgumentState -Spec $Spec -Tokens $TokensBeforeCurrent
    if ($state.PendingValueKind) {
        return @(Get-FsutilValueKindCompletions -ValueKind $state.PendingValueKind -CurrentValue $CurrentWord -Context $state)
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrEmpty($CurrentWord) -or $CurrentWord.StartsWith('/')) {
        foreach ($item in @(Get-FsutilOptionCompletions -Spec $Spec -CurrentValue $CurrentWord -State $state)) {
            $results.Add($item)
        }
    }

    $positionals = if ($Spec.ContainsKey('Positionals')) { @($Spec.Positionals) } else { @() }
    $nextKind = $null
    $declaredPositionalCount = @($positionals).Count
    $positionalCount = @($state.Positionals).Count
    if ($declaredPositionalCount -gt 0 -and $positionalCount -lt $declaredPositionalCount) {
        $nextKind = [string](@($positionals)[$positionalCount])
    }

    if ($nextKind) {
        foreach ($item in @(Get-FsutilValueKindCompletions -ValueKind $nextKind -CurrentValue $CurrentWord -Context $state)) {
            $results.Add($item)
        }
    }

    @($results.ToArray() | Sort-Object -Property CompletionText -Unique)
}

function Get-Fsutil8Dot3nameSetCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $positionals = @($TokensBeforeCurrent | ForEach-Object { Remove-FsutilOuterQuotes -Value $_ } | Where-Object { $_ })
    switch ($positionals.Count) {
        0 {
            $results = @(
                Get-FsutilValueKindCompletions -ValueKind 'Range03' -CurrentValue $CurrentWord -Context @{}
                Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{}
            )
            return @($results | Sort-Object -Property CompletionText -Unique)
        }
        1 {
            if ($positionals[0] -match '^[0-3]$') {
                return @()
            }

            return @(Get-FsutilValueKindCompletions -ValueKind 'Boolean01' -CurrentValue $CurrentWord -Context @{})
        }
    }

    @()
}

function Get-FsutilBehaviorQueryCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    Ensure-FsutilBehaviorMetadata
    if ($TokensBeforeCurrent.Count -gt 0) {
        return @()
    }

    $items = foreach ($option in @($script:FsutilCompletionCatalog.BehaviorQueryOptions)) {
        [pscustomobject]@{
            CompletionText = $option
            ToolTip        = 'fsutil behavior query option'
        }
    }

    Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items $items -DefaultToolTip 'behavior query option'
}

function Get-FsutilBehaviorSetValueShapeCompletions {
    param(
        [string]$OptionName,
        [string[]]$TypedValues,
        [string]$CurrentWord
    )

    Ensure-FsutilBehaviorMetadata
    $lookup = $OptionName.ToLowerInvariant()
    if (-not $script:FsutilCompletionCatalog.BehaviorSetValueMaps.ContainsKey($lookup)) {
        return @()
    }

    switch ($lookup) {
        'disable8dot3' {
            if ($TypedValues.Count -eq 0) {
                return @(
                    Get-FsutilValueKindCompletions -ValueKind 'Range03' -CurrentValue $CurrentWord -Context @{}
                    Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{}
                )
            }

            if ($TypedValues.Count -eq 1 -and -not ($TypedValues[0] -match '^[0-3]$')) {
                return @(Get-FsutilValueKindCompletions -ValueKind 'Boolean01' -CurrentValue $CurrentWord -Context @{})
            }

            return @()
        }
        'disabledeletenotify' {
            if ($TypedValues.Count -eq 0) {
                return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @(
                        @{ CompletionText = 'NTFS'; ToolTip = 'NTFS file system' }
                        @{ CompletionText = 'ReFS'; ToolTip = 'ReFS file system' }
                        @{ CompletionText = '0'; ToolTip = 'Disable / false' }
                        @{ CompletionText = '1'; ToolTip = 'Enable / true' }
                    ) -DefaultToolTip 'behavior set value')
            }

            if ($TypedValues.Count -eq 1 -and ($TypedValues[0] -in @('NTFS', 'ReFS'))) {
                return @(Get-FsutilValueKindCompletions -ValueKind 'Boolean01' -CurrentValue $CurrentWord -Context @{})
            }

            return @()
        }
        'disabletxf' {
            if ($TypedValues.Count -eq 0) {
                return @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})
            }

            if ($TypedValues.Count -eq 1) {
                return @(Get-FsutilValueKindCompletions -ValueKind 'Boolean01' -CurrentValue $CurrentWord -Context @{})
            }

            return @()
        }
    }

    $valueShape = [string]$script:FsutilCompletionCatalog.BehaviorSetValueMaps[$lookup].ValueShape
    if ($valueShape -match '<0\|1>') {
        return @(Get-FsutilValueKindCompletions -ValueKind 'Boolean01' -CurrentValue $CurrentWord -Context @{})
    }

    if ($valueShape -match '<0-3>') {
        return @(Get-FsutilValueKindCompletions -ValueKind 'Range03' -CurrentValue $CurrentWord -Context @{})
    }

    if ($valueShape -match '<1-2>') {
        return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @(
                @{ CompletionText = '1'; ToolTip = 'Value 1' }
                @{ CompletionText = '2'; ToolTip = 'Value 2' }
            ) -DefaultToolTip '1 or 2')
    }

    if ($valueShape -match '<0-15>') {
        return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @(
                @{ CompletionText = '0'; ToolTip = 'Value 0' }
                @{ CompletionText = '1'; ToolTip = 'Value 1' }
                @{ CompletionText = '15'; ToolTip = 'Value 15' }
            ) -DefaultToolTip '0 through 15')
    }

    if ($valueShape -match '<Volume Path>') {
        return @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})
    }

    @()
}

function Get-FsutilBehaviorSetCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    Ensure-FsutilBehaviorMetadata
    $positionals = @($TokensBeforeCurrent | ForEach-Object { Remove-FsutilOuterQuotes -Value $_ } | Where-Object { $_ })
    if ($positionals.Count -eq 0) {
        $items = foreach ($option in @($script:FsutilCompletionCatalog.BehaviorSetValueMaps.Values | Sort-Object -Property Name)) {
            [pscustomobject]@{
                CompletionText = $option.Name
                ToolTip        = $option.ValueShape
            }
        }

        return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items $items -DefaultToolTip 'behavior set option')
    }

    $optionName = $positionals[0]
    $typedValues = @()
    if ($positionals.Count -gt 1) {
        $typedValues = @($positionals | Select-Object -Skip 1)
    }

    Get-FsutilBehaviorSetValueShapeCompletions -OptionName $optionName -TypedValues $typedValues -CurrentWord $CurrentWord
}

function Get-FsutilFileQueryAllocRangesCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $tagValues = @{}
    $positionals = New-Object System.Collections.Generic.List[string]
    foreach ($token in @($TokensBeforeCurrent)) {
        $cleanToken = Remove-FsutilOuterQuotes -Value $token
        if ($cleanToken -match '^(?<tag>offset|length)=(?<value>.*)$') {
            $tagValues[$matches.tag.ToLowerInvariant()] = $matches.value
        } elseif (-not [string]::IsNullOrWhiteSpace($cleanToken)) {
            $positionals.Add($cleanToken)
        }
    }

    if ($CurrentWord -match '^(?<tag>offset|length)=(?<value>.*)$') {
        $tag = $matches.tag.ToLowerInvariant()
        $valuePrefix = $matches.value
        $kind = if ($tag -eq 'offset') { 'Offset' } else { 'Length' }
        $results = foreach ($item in @(Get-FsutilValueKindCompletions -ValueKind $kind -CurrentValue $valuePrefix -Context @{})) {
            [pscustomobject]@{
                CompletionText = "$tag=$($item.CompletionText)"
                ToolTip        = "$tag parameter"
            }
        }

        return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items $results -DefaultToolTip 'queryAllocRanges value')
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($tag in @('offset', 'length')) {
        if (-not $tagValues.ContainsKey($tag)) {
            $results.Add((New-FsutilCompletionResult -CompletionText ($tag + '=') -ListItemText ($tag + '=') -ResultType 'ParameterValue' -ToolTip ('Provide ' + $tag + ' value')))
        }
    }

    if ($tagValues.ContainsKey('offset') -and $tagValues.ContainsKey('length')) {
        foreach ($item in @(Get-FsutilValueKindCompletions -ValueKind 'FilePath' -CurrentValue $CurrentWord -Context @{})) {
            $results.Add($item)
        }
    }

    @($results.ToArray() | Sort-Object -Property CompletionText -Unique)
}

function Get-FsutilFileQueryFileNameByIdCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $positionals = @($TokensBeforeCurrent | ForEach-Object { Remove-FsutilOuterQuotes -Value $_ } | Where-Object { $_ })
    switch ($positionals.Count) {
        0 { return @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{}) }
        1 { return @(Get-FsutilValueKindCompletions -ValueKind 'FileId' -CurrentValue $CurrentWord -Context @{}) }
        2 { return @(Get-FsutilValueKindCompletions -ValueKind 'FileId' -CurrentValue $CurrentWord -Context @{}) }
    }

    @()
}

function Get-FsutilObjectIdSetCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $positionals = @($TokensBeforeCurrent | ForEach-Object { Remove-FsutilOuterQuotes -Value $_ } | Where-Object { $_ })
    if ($positionals.Count -lt 4) {
        return @(Get-FsutilValueKindCompletions -ValueKind 'Hex32' -CurrentValue $CurrentWord -Context @{})
    }

    if ($positionals.Count -eq 4) {
        return @(Get-FsutilValueKindCompletions -ValueKind 'FilePath' -CurrentValue $CurrentWord -Context @{})
    }

    @()
}

function Get-FsutilRepairEnumerateCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $positionals = @($TokensBeforeCurrent | ForEach-Object { Remove-FsutilOuterQuotes -Value $_ } | Where-Object { $_ })
    switch ($positionals.Count) {
        0 { return @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{}) }
        1 { return @(Get-FsutilValueKindCompletions -ValueKind 'RepairLogName' -CurrentValue $CurrentWord -Context @{}) }
    }

    @()
}

function Get-FsutilRepairSetCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $positionals = @($TokensBeforeCurrent | ForEach-Object { Remove-FsutilOuterQuotes -Value $_ } | Where-Object { $_ })
    switch ($positionals.Count) {
        0 { return @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{}) }
        1 { return @(Get-FsutilValueKindCompletions -ValueKind 'RepairFlags' -CurrentValue $CurrentWord -Context @{}) }
    }

    @()
}

function Get-FsutilRepairWaitCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $positionals = @($TokensBeforeCurrent | ForEach-Object { Remove-FsutilOuterQuotes -Value $_ } | Where-Object { $_ })
    switch ($positionals.Count) {
        0 {
            return @(
                Get-FsutilValueKindCompletions -ValueKind 'WaitType' -CurrentValue $CurrentWord -Context @{}
                Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{}
            )
        }
        1 {
            if ($positionals[0] -match '^[01]$') {
                return @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})
            }
        }
    }

    @()
}

function Get-FsutilStorageReserveFindByIdCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $optionSeen = $false
    $positionals = New-Object System.Collections.Generic.List[string]
    foreach ($token in @($TokensBeforeCurrent)) {
        $clean = Remove-FsutilOuterQuotes -Value $token
        if ($clean -ieq '/v') {
            $optionSeen = $true
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($clean)) {
            $positionals.Add($clean)
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $optionSeen -and ([string]::IsNullOrEmpty($CurrentWord) -or $CurrentWord.StartsWith('/'))) {
        $results.Add((New-FsutilCompletionResult -CompletionText '/v' -ListItemText '/v' -ResultType 'ParameterName' -ToolTip 'Verbose mode'))
    }

    switch ($positionals.Count) {
        0 {
            foreach ($item in @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})) {
                $results.Add($item)
            }
        }
        1 {
            foreach ($item in @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @(
                        @{ CompletionText = '*'; ToolTip = 'All storage reserve IDs' }
                        @{ CompletionText = '2'; ToolTip = 'Example storage reserve ID' }
                        @{ CompletionText = '<id>'; ToolTip = 'Storage reserve ID' }
                    ) -DefaultToolTip 'Storage reserve ID')) {
                $results.Add($item)
            }
        }
    }

    @($results.ToArray() | Sort-Object -Property CompletionText -Unique)
}

function Get-FsutilTransactionQueryCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $positionals = @($TokensBeforeCurrent | ForEach-Object { Remove-FsutilOuterQuotes -Value $_ } | Where-Object { $_ })
    switch ($positionals.Count) {
        0 {
            return @(
                Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @(
                    @{ CompletionText = 'files'; ToolTip = 'Query file transactions' }
                    @{ CompletionText = 'all'; ToolTip = 'Query all transactions' }
                ) -DefaultToolTip 'transaction query scope'
                Get-FsutilValueKindCompletions -ValueKind 'Guid' -CurrentValue $CurrentWord -Context @{}
            )
        }
        1 {
            if ($positionals[0] -in @('files', 'all')) {
                return @(Get-FsutilValueKindCompletions -ValueKind 'Guid' -CurrentValue $CurrentWord -Context @{})
            }
        }
    }

    @()
}

function Get-FsutilUsnCreateJournalCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $hasM = $false
    $hasA = $false
    $positionals = New-Object System.Collections.Generic.List[string]
    foreach ($token in @($TokensBeforeCurrent)) {
        $clean = Remove-FsutilOuterQuotes -Value $token
        if ($clean -match '^m=') {
            $hasM = $true
            continue
        }

        if ($clean -match '^a=') {
            $hasA = $true
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($clean)) {
            $positionals.Add($clean)
        }
    }

    if ($CurrentWord -match '^m=(?<value>.*)$') {
        return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @(
                @{ CompletionText = 'm=1048576'; ToolTip = 'Example max size' }
                @{ CompletionText = 'm=<maxsize>'; ToolTip = 'Maximum journal size' }
            ) -DefaultToolTip 'm= value')
    }

    if ($CurrentWord -match '^a=(?<value>.*)$') {
        return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @(
                @{ CompletionText = 'a=65536'; ToolTip = 'Example allocation delta' }
                @{ CompletionText = 'a=<allocationdelta>'; ToolTip = 'Allocation delta' }
            ) -DefaultToolTip 'a= value')
    }

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $hasM) {
        $results.Add((New-FsutilCompletionResult -CompletionText 'm=' -ListItemText 'm=' -ResultType 'ParameterValue' -ToolTip 'Maximum journal size'))
    }

    if (-not $hasA) {
        $results.Add((New-FsutilCompletionResult -CompletionText 'a=' -ListItemText 'a=' -ResultType 'ParameterValue' -ToolTip 'Allocation delta'))
    }

    if ($positionals.Count -eq 0) {
        foreach ($item in @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})) {
            $results.Add($item)
        }
    }

    @($results.ToArray() | Sort-Object -Property CompletionText -Unique)
}

function Get-FsutilUsnDeleteJournalCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $seenFlags = @()
    $positionals = New-Object System.Collections.Generic.List[string]
    foreach ($token in @($TokensBeforeCurrent)) {
        $clean = Remove-FsutilOuterQuotes -Value $token
        if ($clean -in @('/D', '/N', '/d', '/n')) {
            $seenFlags += $clean.ToUpperInvariant()
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($clean)) {
            $positionals.Add($clean)
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrEmpty($CurrentWord) -or $CurrentWord.StartsWith('/')) {
        foreach ($flag in @('/D', '/N')) {
            if ($seenFlags -notcontains $flag) {
                $results.Add((New-FsutilCompletionResult -CompletionText $flag -ListItemText $flag -ResultType 'ParameterName' -ToolTip 'USN deleteJournal flag'))
            }
        }
    }

    if ($positionals.Count -eq 0) {
        foreach ($item in @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})) {
            $results.Add($item)
        }
    }

    @($results.ToArray() | Sort-Object -Property CompletionText -Unique)
}

function Get-FsutilUsnEnableRangeTrackingCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $positionals = New-Object System.Collections.Generic.List[string]
    $hasChunk = $false
    $hasThreshold = $false
    foreach ($token in @($TokensBeforeCurrent)) {
        $clean = Remove-FsutilOuterQuotes -Value $token
        if ($clean -match '^c=') {
            $hasChunk = $true
            continue
        }

        if ($clean -match '^s=') {
            $hasThreshold = $true
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($clean)) {
            $positionals.Add($clean)
        }
    }

    if ($CurrentWord -match '^c=') {
        return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @(
                @{ CompletionText = 'c=4096'; ToolTip = 'Example chunk size' }
                @{ CompletionText = 'c=<chunk-size>'; ToolTip = 'Chunk size' }
            ) -DefaultToolTip 'c= value')
    }

    if ($CurrentWord -match '^s=') {
        return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @(
                @{ CompletionText = 's=1048576'; ToolTip = 'Example file-size threshold' }
                @{ CompletionText = 's=<file-size-threshold>'; ToolTip = 'File size threshold' }
            ) -DefaultToolTip 's= value')
    }

    $results = New-Object System.Collections.Generic.List[object]
    if ($positionals.Count -eq 0) {
        foreach ($item in @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})) {
            $results.Add($item)
        }
    } else {
        if (-not $hasChunk) {
            $results.Add((New-FsutilCompletionResult -CompletionText 'c=' -ListItemText 'c=' -ResultType 'ParameterValue' -ToolTip 'Chunk size'))
        }

        if (-not $hasThreshold) {
            $results.Add((New-FsutilCompletionResult -CompletionText 's=' -ListItemText 's=' -ResultType 'ParameterValue' -ToolTip 'File size threshold'))
        }
    }

    @($results.ToArray() | Sort-Object -Property CompletionText -Unique)
}

function Get-FsutilVolumeQueryClusterCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $positionals = @($TokensBeforeCurrent | ForEach-Object { Remove-FsutilOuterQuotes -Value $_ } | Where-Object { $_ })
    if ($positionals.Count -eq 0) {
        return @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})
    }

    return @(Get-FsutilValueKindCompletions -ValueKind 'Cluster' -CurrentValue $CurrentWord -Context @{})
}

function Get-FsutilVolumeAllocationReportCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $hasVerbose = $false
    $hasTier = $false
    $pendingTierValue = $false
    $positionals = New-Object System.Collections.Generic.List[string]

    foreach ($token in @($TokensBeforeCurrent)) {
        $clean = Remove-FsutilOuterQuotes -Value $token
        if ($pendingTierValue) {
            if (-not [string]::IsNullOrWhiteSpace($clean)) {
                $positionals.Add($clean)
            }
            $pendingTierValue = $false
            continue
        }

        switch -Regex ($clean) {
            '^/v$' {
                $hasVerbose = $true
                continue
            }
            '^/tier$' {
                $hasTier = $true
                $pendingTierValue = $true
                continue
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($clean)) {
            $positionals.Add($clean)
        }
    }

    if ($pendingTierValue) {
        return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @(
                @{ CompletionText = 'capacity'; ToolTip = 'Capacity tier' }
                @{ CompletionText = 'performance'; ToolTip = 'Performance tier' }
            ) -DefaultToolTip 'Tier type')
    }

    $results = New-Object System.Collections.Generic.List[object]

    if (($positionals.Count -eq 0) -or -not [string]::IsNullOrEmpty($CurrentWord)) {
        foreach ($item in @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})) {
            $results.Add($item)
        }
    }

    if ([string]::IsNullOrEmpty($CurrentWord) -or $CurrentWord.StartsWith('/')) {
        if (-not $hasTier) {
            $results.Add((New-FsutilCompletionResult -CompletionText '/tier' -ListItemText '/tier' -ResultType 'ParameterName' -ToolTip 'Filter results to a storage tier.'))
        }

        if (-not $hasVerbose) {
            $results.Add((New-FsutilCompletionResult -CompletionText '/v' -ListItemText '/v' -ResultType 'ParameterName' -ToolTip 'Verbose mode.'))
        }
    }

    @($results.ToArray() | Sort-Object -Property CompletionText -Unique)
}

function Get-FsutilVolumeFindShrinkBlockerCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $seenNoFileName = $false
    $seenShrinkSize = $false
    $seenNewSize = $false
    $pendingSizedOption = $null
    $positionals = New-Object System.Collections.Generic.List[string]

    foreach ($token in @($TokensBeforeCurrent)) {
        $clean = Remove-FsutilOuterQuotes -Value $token
        if ($pendingSizedOption) {
            if ($pendingSizedOption -eq '/shrinksize') { $seenShrinkSize = $true }
            if ($pendingSizedOption -eq '/newsize') { $seenNewSize = $true }
            $pendingSizedOption = $null
            continue
        }

        switch -Regex ($clean) {
            '^/nofilename$' {
                $seenNoFileName = $true
                continue
            }
            '^/shrinksize$' {
                $pendingSizedOption = '/shrinksize'
                continue
            }
            '^/newsize$' {
                $pendingSizedOption = '/newsize'
                continue
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($clean)) {
            $positionals.Add($clean)
        }
    }

    if ($pendingSizedOption) {
        return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @(
                @{ CompletionText = '200MB'; ToolTip = 'Example size with unit' }
                @{ CompletionText = '2GB'; ToolTip = 'Example size with unit' }
                @{ CompletionText = '<SizeWithUnit>'; ToolTip = 'Size in B/KB/MB/GB/TB/PB format' }
            ) -DefaultToolTip 'SizeWithUnit')
    }

    $results = New-Object System.Collections.Generic.List[object]

    if (($positionals.Count -eq 0) -or -not [string]::IsNullOrEmpty($CurrentWord)) {
        foreach ($item in @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})) {
            $results.Add($item)
        }
    }

    if ([string]::IsNullOrEmpty($CurrentWord) -or $CurrentWord.StartsWith('/')) {
        if (-not $seenNoFileName) {
            $results.Add((New-FsutilCompletionResult -CompletionText '/noFileName' -ListItemText '/noFileName' -ResultType 'ParameterName' -ToolTip 'Avoid printing filenames for each immovable or pinned file.'))
        }

        if (-not $seenShrinkSize -and -not $seenNewSize) {
            $results.Add((New-FsutilCompletionResult -CompletionText '/shrinkSize' -ListItemText '/shrinkSize' -ResultType 'ParameterName' -ToolTip 'Amount of space to shrink.'))
            $results.Add((New-FsutilCompletionResult -CompletionText '/newSize' -ListItemText '/newSize' -ResultType 'ParameterName' -ToolTip 'New size of the volume.'))
        }
    }

    @($results.ToArray() | Sort-Object -Property CompletionText -Unique)
}

function Get-FsutilWimEnumFilesCompletions {
    param(
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $positionals = @($TokensBeforeCurrent | ForEach-Object { Remove-FsutilOuterQuotes -Value $_ } | Where-Object { $_ })
    switch ($positionals.Count) {
        0 { return @(Get-FsutilValueKindCompletions -ValueKind 'DriveName' -CurrentValue $CurrentWord -Context @{}) }
        1 { return @(Get-FsutilValueKindCompletions -ValueKind 'DataSource' -CurrentValue $CurrentWord -Context @{}) }
    }

    @()
}

function Get-FsutilArgumentCompletions {
    param(
        [string[]]$CommandPath,
        [string[]]$TokensBeforeCurrent,
        [string]$CurrentWord
    )

    $specKey = Get-FsutilPathKey -PathTokens $CommandPath
    if (-not $script:FsutilCompletionCatalog.SpecsByKey.ContainsKey($specKey)) {
        return @()
    }

    $spec = $script:FsutilCompletionCatalog.SpecsByKey[$specKey]
    if ($spec.ContainsKey('Handler')) {
        switch ([string]$spec.Handler) {
            '8dot3nameSet'          { return @(Get-Fsutil8Dot3nameSetCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'BehaviorQuery'         { return @(Get-FsutilBehaviorQueryCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'BehaviorSet'           { return @(Get-FsutilBehaviorSetCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'FileQueryAllocRanges'  { return @(Get-FsutilFileQueryAllocRangesCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'FileQueryFileNameById' { return @(Get-FsutilFileQueryFileNameByIdCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'ObjectIdSet'           { return @(Get-FsutilObjectIdSetCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'RepairEnumerate'       { return @(Get-FsutilRepairEnumerateCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'RepairSet'             { return @(Get-FsutilRepairSetCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'RepairWait'            { return @(Get-FsutilRepairWaitCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'StorageReserveFindById' { return @(Get-FsutilStorageReserveFindByIdCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'TransactionQuery'      { return @(Get-FsutilTransactionQueryCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'UsnCreateJournal'      { return @(Get-FsutilUsnCreateJournalCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'UsnDeleteJournal'      { return @(Get-FsutilUsnDeleteJournalCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'UsnEnableRangeTracking' { return @(Get-FsutilUsnEnableRangeTrackingCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'VolumeAllocationReport' { return @(Get-FsutilVolumeAllocationReportCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'VolumeFindShrinkBlocker' { return @(Get-FsutilVolumeFindShrinkBlockerCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'VolumeQueryCluster'    { return @(Get-FsutilVolumeQueryClusterCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
            'WimEnumFiles'          { return @(Get-FsutilWimEnumFilesCompletions -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord) }
        }

        return @()
    }

    @(Get-FsutilGenericArgumentCompletions -Spec $spec -TokensBeforeCurrent $TokensBeforeCurrent -CurrentWord $CurrentWord)
}

function Initialize-FsutilCompletionCatalog {
    if ($script:FsutilCompletionCatalog.Initialized) {
        return
    }

    $script:FsutilCompletionCatalog.SpecsByKey = Get-FsutilStaticSpecs
    [void](Get-FsutilNode -PathTokens @() -Create)
    Ensure-FsutilPathLoaded -PathTokens @()

    $rootNode = Get-FsutilNode -PathTokens @()
    foreach ($family in @($rootNode.Children.Values)) {
        Ensure-FsutilPathLoaded -PathTokens @($family.CompletionText)
    }

    $script:FsutilCompletionCatalog.Initialized = $true
}

function Complete-Fsutil {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    if (-not (Test-FsutilCommandAvailable)) {
        return @()
    }

    Initialize-FsutilCompletionCatalog

    $line = $CommandAst.Extent.Text
    $cursorAfterExtent = $CursorPosition -gt $line.Length
    $currentWord = if ($cursorAfterExtent -or [string]::IsNullOrEmpty($WordToComplete)) {
        ''
    } else {
        Get-FsutilCurrentToken -Line $line -CursorPosition $CursorPosition -Fallback $WordToComplete
    }

    $tokens = @($CommandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text })
    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $line.Length)
    $hasTrailingSpace = $cursorAfterExtent -or [string]::IsNullOrEmpty($WordToComplete) -or ($line.Substring(0, $safeCursor) -match '\s$')
    $tokensBeforeCurrent = Get-FsutilTokensBeforeCurrent -Tokens $tokens -CurrentWord $currentWord -HasTrailingSpace:$hasTrailingSpace

    if (@($tokensBeforeCurrent).Count -eq 0) {
        Ensure-FsutilPathLoaded -PathTokens @()
        $rootNode = Get-FsutilNode -PathTokens @()
        return @(Get-FsutilChildSuggestions -Children $rootNode.Children -WordToComplete $currentWord)
    }

    $resolved = Resolve-FsutilCommandPath -Tokens $tokensBeforeCurrent
    $commandPath = @($resolved.PathTokens)
    $argumentTokensBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip $commandPath.Count)

    Ensure-FsutilPathLoaded -PathTokens $commandPath
    $node = Get-FsutilNode -PathTokens $commandPath

    $remainingCount = @($resolved.Remaining).Count

    if ($remainingCount -eq 0 -and $node -and $node.Children.Count -gt 0) {
        return @(Get-FsutilChildSuggestions -Children $node.Children -WordToComplete $currentWord)
    }

    if ($node -and $node.Children.Count -gt 0 -and $remainingCount -eq 1 -and -not $hasTrailingSpace) {
        return @(Get-FsutilChildSuggestions -Children $node.Children -WordToComplete $currentWord)
    }

    @(Get-FsutilArgumentCompletions -CommandPath $commandPath -TokensBeforeCurrent $argumentTokensBeforeCurrent -CurrentWord $currentWord)
}

Register-ArgumentCompleter -Native -CommandName 'fsutil', 'fsutil.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    foreach ($result in @(Complete-Fsutil -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition)) {
        $result
    }
}
