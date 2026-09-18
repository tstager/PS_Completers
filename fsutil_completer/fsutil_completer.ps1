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
        (Get-FsutilPathKey @('bypassIo', 'State')) = @{
            Positionals = @('Path')
            Options     = @(
                @{ Token = '/v'; Description = 'Verbose mode - display the name of the storage driver.' }
            )
        }
        (Get-FsutilPathKey @('clfs', 'authenticate')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('dax', 'queryFileAlignment')) = @{
            Positionals = @('FilePath')
            Tags        = @(
                @{ Name = 'q'; ValueKind = 'DaxQueryFlag'; Description = 'Query flag: large, huge or both (default both).' }
                @{ Name = 'n'; ValueKind = 'Number';       Description = 'Number of output ranges (default all).' }
                @{ Name = 's'; ValueKind = 'Offset';       Description = 'Starting file offset of the range (default 0).' }
                @{ Name = 'l'; ValueKind = 'Length';       Description = 'Range length in bytes.' }
            )
        }
        (Get-FsutilPathKey @('devdrv', 'clearFiltersAllowed')) = @{
            Positionals = @('VolumePath')
            Options     = @(
                @{ Token = '/f'; Description = 'Force dismount the volume so the change takes effect immediately.' }
            )
        }
        (Get-FsutilPathKey @('devdrv', 'setFiltersAllowed')) = @{
            Positionals = @('FilterList')
            Options     = @(
                @{ Token = '/f';      Description = 'Force dismount the volume so the change takes effect immediately.' }
                @{ Token = '/volume'; Description = 'Set the allowed filter list only for this volume.'; ValueKind = 'VolumePath' }
            )
        }
        (Get-FsutilPathKey @('devdrv', 'trust')) = @{
            Positionals = @('VolumePath')
            Options     = @(
                @{ Token = '/f'; Description = 'Force dismount the volume so the change takes effect immediately.' }
            )
        }
        (Get-FsutilPathKey @('devdrv', 'untrust')) = @{
            Positionals = @('VolumePath')
            Options     = @(
                @{ Token = '/f'; Description = 'Force dismount the volume so the change takes effect immediately.' }
            )
        }
        (Get-FsutilPathKey @('dirty', 'query')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('dirty', 'set')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('file', 'createNew')) = @{
            Positionals = @('FilePath', 'Length')
        }
        (Get-FsutilPathKey @('file', 'findBySID')) = @{
            Positionals = @('UserOrSid', 'DirectoryPath')
        }
        (Get-FsutilPathKey @('file', 'layout')) = @{
            Positionals = @('Path')
            Options     = @(
                @{ Token = '/v'; Description = 'Verbose mode - display the attribute buffer hex dump for $EA and $REPARSE_POINT.' }
            )
        }
        (Get-FsutilPathKey @('file', 'optimizeMetadata')) = @{
            Positionals = @('Path')
            Options     = @(
                @{ Token = '/A'; Description = 'Display metadata usage.' }
            )
        }
        (Get-FsutilPathKey @('file', 'queryAllocRanges')) = @{
            Handler = 'FileQueryAllocRanges'
        }
        (Get-FsutilPathKey @('file', 'queryCaseSensitiveInfo')) = @{
            Positionals = @('DirectoryPath')
        }
        (Get-FsutilPathKey @('file', 'queryEA')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('file', 'queryExtents')) = @{
            Positionals = @('FilePath', 'Vcn', 'Vcn')
            Options     = @(
                @{ Token = '/R'; Description = 'If <filename> is a reparse point, open it rather than its target.' }
            )
            Words       = @(
                @{ Name = 'csv'; Description = 'Display the result in csv format.' }
            )
        }
        (Get-FsutilPathKey @('file', 'queryExtentsAndRefCounts')) = @{
            Positionals = @('FilePath', 'Vcn', 'Vcn')
            Options     = @(
                @{ Token = '/R'; Description = 'If <filename> is a reparse point, open it rather than its target.' }
            )
        }
        (Get-FsutilPathKey @('file', 'queryFileID')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('file', 'queryFileNameById')) = @{
            Handler = 'FileQueryFileNameById'
        }
        (Get-FsutilPathKey @('file', 'queryOptimizeMetadata')) = @{
            Positionals = @('Path')
        }
        (Get-FsutilPathKey @('file', 'queryProcessesUsing')) = @{
            Positionals = @('Path')
            Options     = @(
                @{ Token = '/C'; Description = 'Output in CSV format.' }
            )
        }
        (Get-FsutilPathKey @('file', 'queryValidData')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('file', 'setCaseSensitiveInfo')) = @{
            Positionals = @('DirectoryPath', 'EnableDisable', 'Recursive', 'Depth')
        }
        (Get-FsutilPathKey @('file', 'setEOF')) = @{
            Positionals = @('FilePath', 'Length')
        }
        (Get-FsutilPathKey @('file', 'setShortName')) = @{
            Positionals = @('FilePath', 'ShortName')
        }
        (Get-FsutilPathKey @('file', 'setStrictlySequential')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('file', 'setValidData')) = @{
            Positionals = @('FilePath', 'Length')
        }
        (Get-FsutilPathKey @('file', 'setZeroData')) = @{
            Handler = 'FileQueryAllocRanges'
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
        (Get-FsutilPathKey @('repair', 'initiate')) = @{
            Positionals = @('VolumePath', 'FileRef')
        }
        (Get-FsutilPathKey @('repair', 'query')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('repair', 'set')) = @{
            Handler = 'RepairSet'
        }
        (Get-FsutilPathKey @('repair', 'state')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('repair', 'wait')) = @{
            Handler = 'RepairWait'
        }
        (Get-FsutilPathKey @('resource', 'create')) = @{
            Positionals = @('DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'info')) = @{
            Positionals = @('DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'setAutoReset')) = @{
            Positionals = @('TrueFalse', 'DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'setAvailable')) = @{
            Positionals = @('DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'setConsistent')) = @{
            Positionals = @('DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'setLog', 'growth')) = @{
            Positionals = @('Number', 'GrowthUnit', 'DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'setLog', 'maxExtents')) = @{
            Positionals = @('Number', 'DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'setLog', 'minExtents')) = @{
            Positionals = @('Number', 'DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'setLog', 'mode')) = @{
            Positionals = @('LogMode', 'DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'setLog', 'rename')) = @{
            Positionals = @('DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'setLog', 'shrink')) = @{
            Positionals = @('Number', 'DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'setLog', 'size')) = @{
            Positionals = @('Number', 'DirectoryPath')
        }
        (Get-FsutilPathKey @('resource', 'start')) = @{
            Positionals = @('DirectoryPath', 'Path', 'Path')
        }
        (Get-FsutilPathKey @('resource', 'stop')) = @{
            Positionals = @('DirectoryPath')
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
        (Get-FsutilPathKey @('tiering', 'clearFlags')) = @{
            Positionals = @('VolumePath', 'TieringFlags')
        }
        (Get-FsutilPathKey @('tiering', 'queryFlags')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('tiering', 'regionList')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('tiering', 'setFlags')) = @{
            Positionals = @('VolumePath', 'TieringFlags')
        }
        (Get-FsutilPathKey @('tiering', 'tierList')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('trace', 'decode')) = @{
            Positionals  = @('FilePath')
            TagsAnywhere = $true
            Tags         = @(
                @{ Name = 'output'; ValueKind = 'Path';        Description = 'Output file name (defaults to the input name).' }
                @{ Name = 'format'; ValueKind = 'TraceFormat'; Description = 'Output format: CSV, XML, EVTX, TXT or No.' }
            )
        }
        (Get-FsutilPathKey @('transaction', 'commit')) = @{
            Positionals = @('Guid')
        }
        (Get-FsutilPathKey @('transaction', 'fileinfo')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('transaction', 'query')) = @{
            Handler = 'TransactionQuery'
        }
        (Get-FsutilPathKey @('transaction', 'rollback')) = @{
            Positionals = @('Guid')
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
            Positionals = @('FileRef', 'Usn', 'Usn', 'VolumePath')
        }
        (Get-FsutilPathKey @('usn', 'queryJournal')) = @{
            Positionals = @('VolumePath')
        }
        (Get-FsutilPathKey @('usn', 'readJournal')) = @{
            Positionals = @('VolumePath')
            Words       = @(
                @{ Name = 'csv';  Description = 'Print the USN records in CSV format.' }
                @{ Name = 'wait'; Description = 'Wait for more records to be added to the USN journal.' }
                @{ Name = 'tail'; Description = 'Start reading at the end of the USN journal (overrides startUsn).' }
            )
            Tags        = @(
                @{ Name = 'minVer';   ValueKind = 'UsnVersion'; Description = 'Minimum major version of USN_RECORD to return (default 2).' }
                @{ Name = 'maxVer';   ValueKind = 'UsnVersion'; Description = 'Maximum major version of USN_RECORD to return (default 4).' }
                @{ Name = 'startUsn'; ValueKind = 'Usn';        Description = 'USN to start reading the journal from (default 0).' }
            )
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
        (Get-FsutilPathKey @('volume', 'fileLayout')) = @{
            Positionals = @('Path', 'FileIdOrStar')
            Options     = @(
                @{ Token = '/v'; Description = 'Verbose mode - display the attribute buffer hex dump for $EA and $REPARSE_POINT.' }
            )
        }
        (Get-FsutilPathKey @('volume', 'smrGC')) = @{
            Positionals = @('VolumePath')
            Tags        = @(
                @{ Name = 'Action';        ValueKind = 'SmrAction'; Description = 'Garbage collection action: start, startfullspeed, pause or stop.' }
                @{ Name = 'IoGranularity'; ValueKind = 'Length';    Description = 'I/O granularity for Action=start.' }
            )
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
        (Get-FsutilPathKey @('wim', 'enumWims')) = @{
            Positionals = @('DriveName')
        }
        (Get-FsutilPathKey @('wim', 'queryFile')) = @{
            Positionals = @('FilePath')
        }
        (Get-FsutilPathKey @('wim', 'removeWim')) = @{
            Positionals = @('DriveName', 'DataSource')
        }
    }
}

function Invoke-FsutilHelpText {
    # Runs fsutil with exactly the given arguments (never '/?': several verbs take it as an operand)
    # through a bounded process with stdin closed, so a verb that blocks cannot stall the prompt.
    param([string[]]$Arguments)

    $commandName = Resolve-FsutilCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $commandName
        foreach ($argument in @($Arguments)) {
            $startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $process.StandardInput.Close()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) {
                $process.Kill()
                return @()
            }

            $text = ($outputTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
            if ([string]::IsNullOrWhiteSpace($text)) {
                $text = ($errorTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
            }

            if ([string]::IsNullOrWhiteSpace($text)) {
                return @()
            }

            return @($text -split '\r?\n')
        } finally {
            $process.Dispose()
        }
    } catch {
        Write-Debug "fsutil completer: '$commandName $($Arguments -join ' ')' failed: $($_.Exception.Message)"
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

        # A single space separates name and description when the name fills the column
        # (file queryExtentsAndRefCounts), so any run of whitespace is accepted.
        if ($line -match '^\s{0,4}(?<name>[A-Za-z0-9]+)(?:\s+(?<description>\S.*?))?\s*$') {
            $description = if ($matches.ContainsKey('description')) { $matches.description.Trim() } else { '' }
            $entries.Add([pscustomobject]@{
                    Name        = $matches.name
                    Description = $description
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
        $entries = Get-FsutilHelpEntries -Lines (Invoke-FsutilHelpText -Arguments @())
        if (-not $entries -or $entries.Count -eq 0) {
            $entries = foreach ($entry in (Get-FsutilStaticRootEntries)) {
                [pscustomobject]@{
                    Name        = $entry.Name
                    Description = $entry.Description
                }
            }
        }
    } elseif ($PathTokens.Count -eq 1) {
        $entries = Get-FsutilHelpEntries -Lines (Invoke-FsutilHelpText -Arguments $PathTokens)
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
    } elseif ($key -eq (Get-FsutilPathKey -PathTokens @('resource', 'setLog'))) {
        # The only two-token node with sub-verbs; invoked bare it prints its listing. Every other
        # two-token path is a leaf and is never executed: running 'verb /?' or a bare verb could
        # perform the operation (fsutil tiering queryFlags /? tries to open a volume named '/?').
        $entries = Get-FsutilHelpEntries -Lines (Invoke-FsutilHelpText -Arguments $PathTokens)
    }

    foreach ($entry in @($entries)) {
        Add-FsutilChildNode -PathTokens $PathTokens -Name $entry.Name -Description $entry.Description
    }

    $script:FsutilCompletionCatalog.LoadedKeys[$key] = $true
}

function Get-FsutilLeafHelpLines {
    # Only for 'behavior query' and 'behavior set', which print their usage table when run without
    # arguments (verified on 10.0.26100); no '/?' is appended.
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
    $items = @($items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') })

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
        SeenTags         = @()
        SeenWords        = @()
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

        $tagInfo = Get-FsutilTagInfo -Spec $Spec -Token $cleanToken
        if ($tagInfo) {
            $state.SeenTags += ([string]$tagInfo.Name).ToLowerInvariant()
            continue
        }

        $wordInfo = Get-FsutilWordInfo -Spec $Spec -Token $cleanToken
        if ($wordInfo) {
            $state.SeenWords += ([string]$wordInfo.Name).ToLowerInvariant()
            continue
        }

        $state.Positionals += [pscustomobject]@{
            Kind  = $null
            Value = $cleanToken
        }
    }

    $state
}

function Get-FsutilTagInfo {
    # 'name=value' operands such as startUsn=0xF00 or format=CSV.
    param(
        [hashtable]$Spec,
        [string]$Token
    )

    if (-not $Spec -or -not ($Spec.ContainsKey('Tags'))) {
        return $null
    }

    $match = [regex]::Match((Remove-FsutilOuterQuotes -Value $Token), '^(?<name>[A-Za-z]+)=')
    if (-not $match.Success) {
        return $null
    }

    foreach ($tag in @($Spec.Tags)) {
        if ([string]$tag.Name -ieq $match.Groups['name'].Value) {
            return $tag
        }
    }

    $null
}

function Get-FsutilWordInfo {
    # Bare keyword operands such as csv, wait or tail.
    param(
        [hashtable]$Spec,
        [string]$Token
    )

    if (-not $Spec -or -not ($Spec.ContainsKey('Words'))) {
        return $null
    }

    $lookup = Remove-FsutilOuterQuotes -Value $Token
    foreach ($word in @($Spec.Words)) {
        if ([string]$word.Name -ieq $lookup) {
            return $word
        }
    }

    $null
}

function Get-FsutilTagAndWordCompletionList {
    param(
        [hashtable]$Spec,
        [string]$CurrentValue,
        [hashtable]$State
    )

    $cleanCurrent = Remove-FsutilOuterQuotes -Value $CurrentValue
    if ($Spec.ContainsKey('Tags')) {
        foreach ($tag in @($Spec.Tags)) {
            $name = [string]$tag.Name
            if ($State.SeenTags -contains $name.ToLowerInvariant()) {
                continue
            }

            $completionText = $name + '='
            if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or $completionText.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
                New-FsutilCompletionResult -CompletionText $completionText -ListItemText $completionText -ResultType 'ParameterValue' -ToolTip $tag.Description
            }
        }
    }

    if ($Spec.ContainsKey('Words')) {
        foreach ($word in @($Spec.Words)) {
            $name = [string]$word.Name
            if ($State.SeenWords -contains $name.ToLowerInvariant()) {
                continue
            }

            if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or $name.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
                New-FsutilCompletionResult -CompletionText $name -ListItemText $name -ResultType 'ParameterValue' -ToolTip $word.Description
            }
        }
    }
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
        'FileRef' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '1';                  ToolTip = 'Example file reference number' }
                    @{ CompletionText = '0x001600000000123D'; ToolTip = 'Example file reference number including the segment number' }
                    @{ CompletionText = '<file ref#>';        ToolTip = 'File reference number' }
                ) -DefaultToolTip 'File reference number')
        }
        'Usn' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '0';     ToolTip = 'USN 0' }
                    @{ CompletionText = '1';     ToolTip = 'USN 1' }
                    @{ CompletionText = '0xF00'; ToolTip = 'Example hexadecimal USN' }
                    @{ CompletionText = '<usn>'; ToolTip = 'Update sequence number' }
                ) -DefaultToolTip 'USN')
        }
        'UsnVersion' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '2'; ToolTip = 'USN_RECORD major version 2' }
                    @{ CompletionText = '3'; ToolTip = 'USN_RECORD major version 3' }
                    @{ CompletionText = '4'; ToolTip = 'USN_RECORD major version 4' }
                ) -DefaultToolTip 'USN_RECORD major version')
        }
        'Vcn' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '0';     ToolTip = 'VCN 0' }
                    @{ CompletionText = '10';    ToolTip = 'Example VCN count' }
                    @{ CompletionText = '100';   ToolTip = 'Example VCN count' }
                    @{ CompletionText = '<vcn>'; ToolTip = 'Virtual cluster number' }
                ) -DefaultToolTip 'Virtual cluster number')
        }
        'ShortName' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '""';          ToolTip = 'Remove the existing short name' }
                    @{ CompletionText = '<shortname>'; ToolTip = '8.3 short name to set' }
                ) -DefaultToolTip 'Short name')
        }
        'EnableDisable' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = 'enable';  ToolTip = 'Enable the case sensitive attribute (default)' }
                    @{ CompletionText = 'disable'; ToolTip = 'Disable the case sensitive attribute' }
                ) -DefaultToolTip 'enable or disable')
        }
        'Recursive' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = 'recursive'; ToolTip = 'Also set the attribute on subdirectories' }
                ) -DefaultToolTip 'recursive')
        }
        'Depth' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '0';       ToolTip = 'Depth 0 (same as not recursive)' }
                    @{ CompletionText = '1';       ToolTip = 'One level of subdirectories' }
                    @{ CompletionText = '2';       ToolTip = 'Two levels of subdirectories' }
                    @{ CompletionText = '<depth>'; ToolTip = 'Subdirectory depth to traverse' }
                ) -DefaultToolTip 'Depth')
        }
        'TieringFlags' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '/TrNH'; ToolTip = 'NTFS and ReFS only: disable heat gathering on tiered volumes'; ResultType = 'ParameterName' }
                ) -DefaultToolTip 'Tiering flags')
        }
        'FileIdOrStar' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '*';                  ToolTip = 'All files on the volume' }
                    @{ CompletionText = '0x00040000000001bf'; ToolTip = 'Example 64-bit file ID' }
                    @{ CompletionText = '<file id>';          ToolTip = 'File ID' }
                ) -DefaultToolTip 'File ID or *')
        }
        'TrueFalse' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = 'true';  ToolTip = 'true' }
                    @{ CompletionText = 'false'; ToolTip = 'false' }
                ) -DefaultToolTip 'true or false')
        }
        'Number' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = '5';        ToolTip = 'Example value' }
                    @{ CompletionText = '50';       ToolTip = 'Example value' }
                    @{ CompletionText = '<number>'; ToolTip = 'Number' }
                ) -DefaultToolTip 'Number')
        }
        'GrowthUnit' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = 'containers'; ToolTip = 'Grow by a number of containers' }
                    @{ CompletionText = 'percent';    ToolTip = 'Grow by a percentage' }
                ) -DefaultToolTip 'Growth unit')
        }
        'LogMode' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = 'full'; ToolTip = 'Full logging' }
                    @{ CompletionText = 'undo'; ToolTip = 'Undo only logging' }
                ) -DefaultToolTip 'Log mode')
        }
        'TraceFormat' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = 'CSV';  ToolTip = 'Comma separated values' }
                    @{ CompletionText = 'XML';  ToolTip = 'XML' }
                    @{ CompletionText = 'EVTX'; ToolTip = 'Event log file' }
                    @{ CompletionText = 'TXT';  ToolTip = 'Plain text (default)' }
                    @{ CompletionText = 'No';   ToolTip = 'Do not dump events' }
                ) -DefaultToolTip 'Trace output format')
        }
        'DaxQueryFlag' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = 'large'; ToolTip = 'Query for large page alignment' }
                    @{ CompletionText = 'huge';  ToolTip = 'Query for huge page alignment (64-bit only)' }
                    @{ CompletionText = 'both';  ToolTip = 'Query for both large and huge page alignment (default)' }
                ) -DefaultToolTip 'Query flag')
        }
        'SmrAction' {
            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentValue -Items @(
                    @{ CompletionText = 'start';          ToolTip = 'Start garbage collection (requires IoGranularity=)' }
                    @{ CompletionText = 'startfullspeed'; ToolTip = 'Start garbage collection at full speed' }
                    @{ CompletionText = 'pause';          ToolTip = 'Pause garbage collection' }
                    @{ CompletionText = 'stop';           ToolTip = 'Stop garbage collection' }
                ) -DefaultToolTip 'SMR garbage collection action')
        }
        'FilterList' {
            return @(Get-FsutilPlaceholderCompletions -CurrentValue $CurrentValue -Placeholder '"filter1, filter2"' -ToolTip 'Comma separated list of allowed filter names')
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

    # Attached 'name=value' operand in progress: complete the value and keep the 'name=' prefix.
    $currentTag = Get-FsutilTagInfo -Spec $Spec -Token $CurrentWord
    if ($currentTag) {
        $tagName = [string]$currentTag.Name
        $valuePrefix = (Remove-FsutilOuterQuotes -Value $CurrentWord).Substring($tagName.Length + 1)
        $items = foreach ($item in @(Get-FsutilValueKindCompletions -ValueKind ([string]$currentTag.ValueKind) -CurrentValue $valuePrefix -Context $state)) {
            [pscustomobject]@{
                CompletionText = "$tagName=$($item.CompletionText)"
                ListItemText   = "$tagName=$($item.ListItemText)"
                ToolTip        = $item.ToolTip
            }
        }

        return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @($items) -DefaultToolTip ($tagName + '= value'))
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

    $tagsAnywhere = $Spec.ContainsKey('TagsAnywhere') -and [bool]$Spec.TagsAnywhere
    if (-not $CurrentWord.StartsWith('/') -and ($tagsAnywhere -or $positionalCount -ge $declaredPositionalCount)) {
        foreach ($item in @(Get-FsutilTagAndWordCompletionList -Spec $Spec -CurrentValue $CurrentWord -State $state)) {
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
        { $_ -in @('disabletxf', 'disablewriteautotiering', 'enablereallocatealldatawrites') } {
            # [<Volume Path> <0|1>]
            if ($TypedValues.Count -eq 0) {
                return @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})
            }

            if ($TypedValues.Count -eq 1) {
                return @(Get-FsutilValueKindCompletions -ValueKind 'Boolean01' -CurrentValue $CurrentWord -Context @{})
            }

            return @()
        }
        'symlinkevaluation' {
            # [<L2L>|<L2R>|<R2L>|<R2R>:<0|1>] [...] - any number of kind:value pairs
            $items = foreach ($kind in @('L2L', 'L2R', 'R2L', 'R2R')) {
                if (@($TypedValues | Where-Object { $_ -match ('^' + $kind + ':') }).Count -gt 0) {
                    continue
                }

                foreach ($flag in @('0', '1')) {
                    @{ CompletionText = "${kind}:$flag"; ToolTip = "$kind symbolic link evaluation " + $(if ($flag -eq '1') { 'enabled' } else { 'disabled' }) }
                }
            }

            return @(Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @($items) -DefaultToolTip 'symlinkEvaluation value')
        }
    }

    if ($TypedValues.Count -gt 0) {
        return @()
    }

    $valueShape = [string]$script:FsutilCompletionCatalog.BehaviorSetValueMaps[$lookup].ValueShape
    Get-FsutilValueShapeCompletionList -ValueShape $valueShape -CurrentWord $CurrentWord
}

function Get-FsutilValueShapeCompletionList {
    # Expands every <a-b> range and <a|b|...> alternation found in a help value shape such as
    # '<0-3> | <0|1>' or '<1|2>' into literal values; wide ranges get their bounds plus a placeholder.
    param(
        [string]$ValueShape,
        [string]$CurrentWord
    )

    $items = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($match in [regex]::Matches($ValueShape, '<(?<body>[^<>]+)>')) {
        $body = $match.Groups['body'].Value.Trim()
        if ($body -match '^(?<low>\d[\d,]*)-(?<high>\d[\d,]*)$') {
            $low = [int64]($matches['low'] -replace ',', '')
            $high = [int64]($matches['high'] -replace ',', '')
            if (($high - $low) -le 32) {
                for ($value = $low; $value -le $high; $value++) {
                    if ($seen.Add([string]$value)) {
                        $items.Add(@{ CompletionText = [string]$value; ToolTip = "Value $value ($low-$high)" })
                    }
                }
            } else {
                foreach ($bound in @($low, $high)) {
                    if ($seen.Add([string]$bound)) {
                        $items.Add(@{ CompletionText = [string]$bound; ToolTip = "Value $bound ($low-$high)" })
                    }
                }

                $placeholder = "<$low-$high>"
                if ($seen.Add($placeholder)) {
                    $items.Add(@{ CompletionText = $placeholder; ToolTip = "Any value from $low to $high" })
                }
            }
        } elseif ($body -match '^[\w.]+(?:\|[\w.]+)+$') {
            foreach ($alternative in $body.Split('|')) {
                if ($seen.Add($alternative)) {
                    $items.Add(@{ CompletionText = $alternative; ToolTip = "Value $alternative" })
                }
            }
        }
    }

    if ($ValueShape -match '<Volume Path>') {
        foreach ($item in @(Get-FsutilValueKindCompletions -ValueKind 'VolumePath' -CurrentValue $CurrentWord -Context @{})) {
            $item
        }
    }

    Get-FsutilLiteralCompletions -CurrentValue $CurrentWord -Items @($items.ToArray()) -DefaultToolTip 'behavior set value'
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

    # $CursorPosition is an offset into the whole input line; the extent text is command-relative.
    $line = $CommandAst.Extent.Text
    $relativeCursor = [Math]::Max($CursorPosition - $CommandAst.Extent.StartOffset, 0)
    $cursorAfterExtent = $relativeCursor -gt $line.Length
    $safeCursor = [Math]::Min($relativeCursor, $line.Length)
    $hasTrailingSpace = $cursorAfterExtent -or ($safeCursor -gt 0 -and [char]::IsWhiteSpace($line[$safeCursor - 1]))
    $currentWord = if ($hasTrailingSpace) {
        ''
    } else {
        Get-FsutilCurrentToken -Line $line -CursorPosition $safeCursor -Fallback $WordToComplete
    }

    # Only elements that end before the cursor are completed tokens; the element under the cursor
    # is the current word (truncated at the cursor) and anything after it is ignored.
    $tokensBeforeCurrent = @($CommandAst.CommandElements |
            Select-Object -Skip 1 |
            Where-Object { $_.Extent.EndOffset -lt $CursorPosition } |
            ForEach-Object { $_.Extent.Text })

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
