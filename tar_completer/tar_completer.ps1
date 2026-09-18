# tar tab completion for PowerShell
# Provides mode-aware completion for whichever tar resolves first: the static bsdtar catalog for
# Windows' libarchive build, or a catalog parsed live from 'tar --help' for GNU tar.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name TarCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:TarCompletionCatalog = @{
        Initialized       = $false
        CommandName       = $null
        CommandPath       = $null
        Flavor            = $null
        AllModes          = @('c', 'r', 't', 'u', 'x')
        ModeEntries       = @()
        ModeByAlias       = @{}
        OptionEntries     = @()
        OptionByAlias     = @{}
        ShortOptionByChar = @{}
        ShortValueByChar  = @{}
        FormatValues      = @('ustar', 'pax', 'paxr', 'cpio', 'odc', 'newc', 'shar', 'shardump', 'gnutar', 'v7tar', 'bsdtar', 'mtree', 'zip', '7zip', 'iso9660', 'xar', 'raw', 'warc')
        BlockSizeHints    = @('1', '10', '20', '64', '128')
        StripCountHints   = @('1', '2', '3')
        CompressProgramHints = @('gzip', 'bzip2', 'xz', 'zstd', 'lz4', 'lzop')
        DefaultPatterns   = @('*', '*/*', '*.txt', '*.log')
        StandaloneEntries = @()
        TokenPattern      = '"[^"]*"|''[^'']*''|"[^"]*$|''[^'']*$|\S+'
    }
}

function Resolve-TarCommandName {
    if ($script:TarCompletionCatalog.CommandName) {
        return $script:TarCompletionCatalog.CommandName
    }

    $command = Get-Command -Name tar.exe, tar -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $script:TarCompletionCatalog.CommandName = $command.Name
        $script:TarCompletionCatalog.CommandPath = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $script:TarCompletionCatalog.CommandName
}

function Get-TarFlavor {
    # 'gnu' or 'bsdtar', decided once per session from the resolved binary's --version banner.
    if ($script:TarCompletionCatalog.Flavor) {
        return $script:TarCompletionCatalog.Flavor
    }

    if (-not (Resolve-TarCommandName)) {
        return $null
    }

    $banner = ''
    try {
        $banner = [string](@($null | & $script:TarCompletionCatalog.CommandPath --version 2>$null) | Select-Object -First 1)
    } catch {
        Write-Debug "tar --version probe failed: $($_.Exception.Message)"
    }

    $script:TarCompletionCatalog.Flavor = if ($banner -match 'GNU tar') { 'gnu' } else { 'bsdtar' }
    $script:TarCompletionCatalog.Flavor
}

function Get-TarGnuValueKind {
    param(
        [string]$Placeholder,
        [string]$Canonical
    )

    switch -Regex ($Placeholder) {
        '^(ARCHIVE|FILE|MEMBER-NAME)$' { return 'ArchivePath' }
        '^DIR$' { return 'DirectoryPath' }
        '^(DATE|DATE-OR-FILE)$' { return 'DateTime' }
        '^(PATTERN|MASK)$' { return 'Pattern' }
        '^PROG$' { return 'CompressProgram' }
        '^FORMAT$' { return 'Format' }
        '^BLOCKS$' { return 'BlockSize' }
        '^NUMBER$' { return 'StripCount' }
        '^NAME$' { return 'Name' }
        '^(ORDER|METHOD|STYLE|CONTROL|TYPE)$' { return 'Enum:' + $Canonical }
        '^$' { return $null }
        default { return 'Text:' + $Placeholder }
    }
}

function Get-TarGnuEnumValueList {
    param(
        [string]$Placeholder,
        [string[]]$QuotingStyles
    )

    switch ($Placeholder) {
        'ORDER' { return @('none', 'name', 'inode') }
        'METHOD' { return @('replace', 'system') }
        'STYLE' { if ($QuotingStyles.Count -gt 0) { return @($QuotingStyles) } else { return @('literal', 'shell', 'shell-always', 'shell-escape', 'shell-escape-always', 'c', 'c-maybe', 'escape', 'locale', 'clocale') } }
        'CONTROL' { return @('none', 'off', 't', 'numbered', 'nil', 'existing', 'never', 'simple') }
        'TYPE' { return @('raw', 'seek') }
    }

    @()
}

function ConvertFrom-TarGnuHelp {
    # Parses GNU tar's --help into the same mode/option spec shape the static bsdtar catalog uses.
    param([string[]]$Lines)

    $modeSpecs = New-Object System.Collections.Generic.List[hashtable]
    $optionSpecs = New-Object System.Collections.Generic.List[hashtable]
    $formatValues = New-Object System.Collections.Generic.List[string]
    $quotingStyles = New-Object System.Collections.Generic.List[string]
    $section = ''
    $lastSpec = $null
    $inQuotingList = $false

    foreach ($line in @($Lines)) {
        if ($line -match '^ (?<section>[A-Z][A-Za-z ]+):\s*$') {
            $section = $Matches['section']
            $lastSpec = $null
            continue
        }

        if ($line -match '^Valid arguments for the --quoting-style option') {
            $inQuotingList = $true
            $lastSpec = $null
            continue
        }

        if ($inQuotingList) {
            if ($line -match '^\s{2}(?<style>[a-z][a-z-]*)\s*$') {
                $quotingStyles.Add($Matches['style'])
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $inQuotingList = $false
            }
        }

        if ($section -eq 'Archive format selection' -and $line -match '^\s{4}(?<name>[a-z0-9]+)\s{2,}\S') {
            $formatValues.Add($Matches['name'])
            $lastSpec = $null
            continue
        }

        if ($line -match '^\s{2,6}(?<spec>-\S.*?)(?:\s{2,}(?<desc>\S.*))?\s*$') {
            $spec = $Matches['spec']
            $description = if ($Matches['desc']) { $Matches['desc'].Trim() } else { '' }
            $aliases = New-Object System.Collections.Generic.List[string]
            $shortName = $null
            $placeholder = ''
            $optionalValue = $false

            foreach ($part in ($spec -split ',\s+')) {
                if ($part -notmatch '^(?<token>--?[A-Za-z?][A-Za-z0-9-]*)(?<value>\[=[^\]]+\]|=\S+)?$') {
                    continue
                }

                $token = $Matches['token']
                $aliases.Add($token)
                if ($Matches['value']) {
                    $valueText = $Matches['value']
                    if ($valueText.StartsWith('[')) {
                        $optionalValue = $true
                        $valueText = $valueText.Substring(1).TrimEnd(']')
                    }
                    if (-not $placeholder) {
                        $placeholder = $valueText.TrimStart('=')
                    }
                }

                if ($token -match '^-([A-Za-z])$' -and -not $shortName) {
                    $shortName = $Matches[1]
                }
            }

            if ($aliases.Count -eq 0) {
                $lastSpec = $null
                continue
            }

            $canonical = if ($shortName) { '-' + $shortName } else { $aliases[0] }
            if ($section -eq 'Main operation mode') {
                $modeCanonical = if ($shortName) { $shortName } else { $aliases[0].TrimStart('-') }
                $lastSpec = @{ Canonical = $modeCanonical; Aliases = @($aliases.ToArray()); Description = $description }
                $modeSpecs.Add($lastSpec)
                continue
            }

            $lastSpec = @{
                Canonical   = $canonical
                Aliases     = @($aliases.ToArray())
                Modes       = @()
                Description = $description
                Placeholder = $placeholder
            }
            if ($shortName) {
                $lastSpec['ShortName'] = $shortName
            }

            $valueKind = Get-TarGnuValueKind -Placeholder $placeholder -Canonical $canonical
            if ($valueKind) {
                $lastSpec['ValueKind'] = $valueKind
                if ($optionalValue) {
                    $lastSpec['OptionalValue'] = $true
                }
            }

            if ($canonical -in @('--help', '--usage', '--version', '--show-defaults') -or $aliases -contains '--help') {
                $lastSpec['Standalone'] = $true
            }

            $optionSpecs.Add($lastSpec)
            continue
        }

        if ($null -ne $lastSpec -and $line -match '^\s{20,}(?<text>\S.*?)\s*$') {
            $lastSpec.Description = if ($lastSpec.Description) { $lastSpec.Description + ' ' + $Matches['text'] } else { $Matches['text'] }
            continue
        }

        $lastSpec = $null
    }

    foreach ($spec in $optionSpecs) {
        if ($spec.ContainsKey('ValueKind') -and $spec.ValueKind.StartsWith('Enum:')) {
            $spec['Values'] = @(Get-TarGnuEnumValueList -Placeholder $spec.Placeholder -QuotingStyles @($quotingStyles.ToArray()))
        }
    }

    [pscustomobject]@{
        ModeSpecs    = @($modeSpecs.ToArray())
        OptionSpecs  = @($optionSpecs.ToArray())
        FormatValues = @($formatValues.ToArray())
    }
}

function New-TarCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Remove-TarOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return $Value
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-TarQuotedValue {
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

function Test-TarStartsWith {
    param(
        [string]$Value,
        [string]$Prefix
    )

    if ([string]::IsNullOrEmpty($Prefix)) {
        return $true
    }

    $Value.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-TarValueKind {
    param([object]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties['ValueKind']
    if ($property) {
        return [string]$property.Value
    }

    $null
}

function Initialize-TarCompletionCatalog {
    if ($script:TarCompletionCatalog.Initialized) {
        return
    }

    $modeSpecs = @(
        @{ Canonical = 'c'; Aliases = @('-c', '--create'); Description = 'Create a new archive.' }
        @{ Canonical = 'r'; Aliases = @('-r', '--append'); Description = 'Append files to an existing archive.' }
        @{ Canonical = 't'; Aliases = @('-t', '--list'); Description = 'List archive contents.' }
        @{ Canonical = 'u'; Aliases = @('-u', '--update'); Description = 'Update archive entries that are newer on disk.' }
        @{ Canonical = 'x'; Aliases = @('-x', '--extract'); Description = 'Extract files from an archive.' }
    )

    $optionSpecs = @(
        @{
            Canonical   = '-b'
            Aliases     = @('-b', '--block-size')
            ShortName   = 'b'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Use the specified number of 512-byte records per I/O block.'
            ValueKind   = 'BlockSize'
        }
        @{
            Canonical   = '-f'
            Aliases     = @('-f', '--file')
            ShortName   = 'f'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Read the archive from or write the archive to the specified file.'
            ValueKind   = 'ArchivePath'
        }
        @{
            Canonical   = '-v'
            Aliases     = @('-v')
            ShortName   = 'v'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Operate verbosely.'
        }
        @{
            Canonical   = '-w'
            Aliases     = @('-w')
            ShortName   = 'w'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Interactively confirm each action.'
        }
        @{
            Canonical   = '-C'
            Aliases     = @('-C', '--cd', '--directory')
            ShortName   = 'C'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Change to a directory before processing later files or before extracting.'
            ValueKind   = 'DirectoryPath'
        }
        @{
            Canonical   = '-a'
            Aliases     = @('-a', '--auto-compress')
            ShortName   = 'a'
            Modes       = @('c', 'x')
            Description = 'Choose compression from the archive file suffix.'
        }
        @{
            Canonical   = '-z'
            Aliases     = @('-z', '--gzip', '--gunzip')
            ShortName   = 'z'
            Modes       = @('c', 't', 'x')
            Description = 'Compress the archive with gzip (or read a gzip archive).'
        }
        @{
            Canonical   = '-j'
            Aliases     = @('-j', '-y', '--bzip', '--bzip2', '--bunzip2')
            ShortName   = 'j'
            Modes       = @('c', 't', 'x')
            Description = 'Compress the archive with bzip2 (or read a bzip2 archive).'
        }
        @{
            Canonical   = '-J'
            Aliases     = @('-J', '--xz')
            ShortName   = 'J'
            Modes       = @('c', 't', 'x')
            Description = 'Compress the archive with xz (or read an xz archive).'
        }
        @{
            Canonical   = '--lzma'
            Aliases     = @('--lzma')
            Modes       = @('c', 't', 'x')
            Description = 'Compress the archive with lzma (or read an lzma archive).'
        }
        @{
            Canonical   = '--zstd'
            Aliases     = @('--zstd')
            Modes       = @('c', 't', 'x')
            Description = 'Compress the archive with zstd (or read a zstd archive).'
        }
        @{
            Canonical   = '--lz4'
            Aliases     = @('--lz4')
            Modes       = @('c', 't', 'x')
            Description = 'Compress the archive with lz4 (or read an lz4 archive).'
        }
        @{
            Canonical   = '--lzop'
            Aliases     = @('--lzop')
            Modes       = @('c', 't', 'x')
            Description = 'Compress the archive with lzop (or read an lzop archive).'
        }
        @{
            Canonical   = '--lrzip'
            Aliases     = @('--lrzip')
            Modes       = @('c', 't', 'x')
            Description = 'Compress the archive with lrzip (or read an lrzip archive).'
        }
        @{
            Canonical   = '-Z'
            Aliases     = @('-Z', '--compress', '--uncompress')
            ShortName   = 'Z'
            Modes       = @('c', 't', 'x')
            Description = 'Compress the archive with compress (or read a .Z archive).'
        }
        @{
            Canonical   = '--uuencode'
            Aliases     = @('--uuencode')
            Modes       = @('c', 't', 'x')
            Description = 'Filter the archive through uuencode.'
        }
        @{
            Canonical   = '--b64encode'
            Aliases     = @('--b64encode')
            Modes       = @('c', 't', 'x')
            Description = 'Filter the archive through base64 encoding.'
        }
        @{
            Canonical   = '-I'
            Aliases     = @('-I', '--use-compress-program')
            ShortName   = 'I'
            Modes       = @('c', 't', 'x')
            Description = 'Pipe the archive through an external compression program.'
            ValueKind   = 'CompressProgram'
        }
        @{
            Canonical   = '--format'
            Aliases     = @('--format')
            Modes       = @('c', 'r', 'u')
            Description = 'Select the archive format.'
            ValueKind   = 'Format'
        }
        @{
            Canonical   = '--posix'
            Aliases     = @('--posix')
            Modes       = @('c', 'r', 'u')
            Description = 'Synonym for --format pax.'
        }
        @{
            Canonical   = '--exclude'
            Aliases     = @('--exclude')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Skip files or archive entries that match a pattern.'
            ValueKind   = 'Pattern'
        }
        @{
            Canonical   = '--include'
            Aliases     = @('--include')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Process only files or archive entries that match a pattern.'
            ValueKind   = 'Pattern'
        }
        @{
            Canonical   = '-T'
            Aliases     = @('-T', '--files-from')
            ShortName   = 'T'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Read names to process from a file, one per line.'
            ValueKind   = 'ArchivePath'
        }
        @{
            Canonical   = '-X'
            Aliases     = @('-X', '--exclude-from')
            ShortName   = 'X'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Read exclusion patterns from a file, one per line.'
            ValueKind   = 'ArchivePath'
        }
        @{
            Canonical   = '--exclude-vcs'
            Aliases     = @('--exclude-vcs')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Skip version control system files and directories.'
        }
        @{
            Canonical   = '--null'
            Aliases     = @('--null')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Names read with -T are NUL-terminated instead of newline-terminated.'
        }
        @{
            Canonical   = '--mtime'
            Aliases     = @('--mtime')
            Modes       = @('c', 'r', 'u')
            Description = 'Set modification times for added files.'
            ValueKind   = 'DateTime'
        }
        @{
            Canonical   = '--clamp-mtime'
            Aliases     = @('--clamp-mtime')
            Modes       = @('c', 'r', 'u')
            Description = 'Only apply --mtime when a file is newer than the requested time.'
        }
        @{
            Canonical   = '--newer'
            Aliases     = @('--newer', '--newer-ctime')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Only include entries newer than the given date (ctime).'
            ValueKind   = 'DateTime'
        }
        @{
            Canonical   = '--newer-mtime'
            Aliases     = @('--newer-mtime')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Only include entries whose modification time is newer than the given date.'
            ValueKind   = 'DateTime'
        }
        @{
            Canonical   = '--newer-than'
            Aliases     = @('--newer-than', '--newer-ctime-than')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Only include entries newer than the given file.'
            ValueKind   = 'ArchivePath'
        }
        @{
            Canonical   = '--newer-mtime-than'
            Aliases     = @('--newer-mtime-than')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Only include entries modified more recently than the given file.'
            ValueKind   = 'ArchivePath'
        }
        @{
            Canonical   = '--older'
            Aliases     = @('--older', '--older-ctime')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Only include entries older than the given date (ctime).'
            ValueKind   = 'DateTime'
        }
        @{
            Canonical   = '--older-mtime'
            Aliases     = @('--older-mtime')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Only include entries whose modification time is older than the given date.'
            ValueKind   = 'DateTime'
        }
        @{
            Canonical   = '--older-than'
            Aliases     = @('--older-than', '--older-ctime-than')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Only include entries older than the given file.'
            ValueKind   = 'ArchivePath'
        }
        @{
            Canonical   = '--older-mtime-than'
            Aliases     = @('--older-mtime-than')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Only include entries modified less recently than the given file.'
            ValueKind   = 'ArchivePath'
        }
        @{
            Canonical   = '--strip-components'
            Aliases     = @('--strip-components')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Remove the given number of leading path elements from entry names.'
            ValueKind   = 'StripCount'
        }
        @{
            Canonical   = '-P'
            Aliases     = @('-P', '--absolute-paths', '--insecure')
            ShortName   = 'P'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Preserve absolute path names and .. components.'
        }
        @{
            Canonical   = '-n'
            Aliases     = @('-n', '--norecurse', '--no-recursion')
            ShortName   = 'n'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Do not recurse into directories.'
        }
        @{
            Canonical   = '-q'
            Aliases     = @('-q', '--fast-read')
            ShortName   = 'q'
            Modes       = @('t', 'x')
            Description = 'Stop after the first archive entry that matches each pattern.'
        }
        @{
            Canonical   = '-L'
            Aliases     = @('-L', '--dereference')
            ShortName   = 'L'
            Modes       = @('c', 'r', 'u')
            Description = 'Archive the target of symbolic links instead of the link itself.'
        }
        @{
            Canonical   = '-U'
            Aliases     = @('-U', '--unlink', '--unlink-first')
            ShortName   = 'U'
            Modes       = @('x')
            Description = 'Unlink files before creating them when extracting.'
        }
        @{
            Canonical   = '-B'
            Aliases     = @('-B', '--read-full-blocks')
            ShortName   = 'B'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Ignored for compatibility with other tar implementations.'
        }
        @{
            Canonical   = '-S'
            Aliases     = @('-S')
            ShortName   = 'S'
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Extract files as sparse files.'
        }
        @{
            Canonical   = '--one-file-system'
            Aliases     = @('--one-file-system')
            Modes       = @('c', 'r', 'u')
            Description = 'Do not cross mount points.'
        }
        @{
            Canonical   = '--ignore-zeros'
            Aliases     = @('--ignore-zeros')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Continue reading past zero blocks (concatenated archives).'
        }
        @{
            Canonical   = '--numeric-owner'
            Aliases     = @('--numeric-owner')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Use numeric user and group IDs instead of names.'
        }
        @{
            Canonical   = '--no-same-owner'
            Aliases     = @('--no-same-owner')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Do not restore file ownership when extracting.'
        }
        @{
            Canonical   = '--same-owner'
            Aliases     = @('--same-owner')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Restore file ownership when extracting.'
        }
        @{
            Canonical   = '--no-same-permissions'
            Aliases     = @('--no-same-permissions')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Do not restore full permissions when extracting.'
        }
        @{
            Canonical   = '--keep-newer-files'
            Aliases     = @('--keep-newer-files')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Do not overwrite existing files that are newer than the archive entry.'
        }
        @{
            Canonical   = '--safe-writes'
            Aliases     = @('--safe-writes')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Extract to a temporary file and rename it into place atomically.'
        }
        @{
            Canonical   = '--no-safe-writes'
            Aliases     = @('--no-safe-writes')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Do not use atomic writes when extracting.'
        }
        @{
            Canonical   = '--acls'
            Aliases     = @('--acls')
            Modes       = @('c', 'r', 'u', 'x')
            Description = 'Archive or extract POSIX.1e or NFSv4 ACLs.'
        }
        @{
            Canonical   = '--no-acls'
            Aliases     = @('--no-acls')
            Modes       = @('c', 'r', 'u', 'x')
            Description = 'Do not archive or extract ACLs.'
        }
        @{
            Canonical   = '--xattrs'
            Aliases     = @('--xattrs')
            Modes       = @('c', 'r', 'u', 'x')
            Description = 'Archive or extract extended file attributes.'
        }
        @{
            Canonical   = '--no-xattrs'
            Aliases     = @('--no-xattrs')
            Modes       = @('c', 'r', 'u', 'x')
            Description = 'Do not archive or extract extended file attributes.'
        }
        @{
            Canonical   = '--fflags'
            Aliases     = @('--fflags')
            Modes       = @('c', 'r', 'u', 'x')
            Description = 'Archive or extract platform-specific file flags.'
        }
        @{
            Canonical   = '--no-fflags'
            Aliases     = @('--no-fflags')
            Modes       = @('c', 'r', 'u', 'x')
            Description = 'Do not archive or extract platform-specific file flags.'
        }
        @{
            Canonical   = '--totals'
            Aliases     = @('--totals')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Print the total bytes written after the archive is created.'
        }
        @{
            Canonical   = '--uid'
            Aliases     = @('--uid')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Use the given user ID for archived or extracted entries.'
            ValueKind   = 'Id'
        }
        @{
            Canonical   = '--gid'
            Aliases     = @('--gid')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Use the given group ID for archived or extracted entries.'
            ValueKind   = 'Id'
        }
        @{
            Canonical   = '--uname'
            Aliases     = @('--uname')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Use the given user name for archived or extracted entries.'
            ValueKind   = 'Name'
        }
        @{
            Canonical   = '--gname'
            Aliases     = @('--gname')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Use the given group name for archived or extracted entries.'
            ValueKind   = 'Name'
        }
        @{
            Canonical   = '--owner'
            Aliases     = @('--owner')
            Modes       = @('c', 'r', 'u')
            Description = 'Override the owner (name or name:id) of added entries.'
            ValueKind   = 'Name'
        }
        @{
            Canonical   = '--group'
            Aliases     = @('--group')
            Modes       = @('c', 'r', 'u')
            Description = 'Override the group (name or name:id) of added entries.'
            ValueKind   = 'Name'
        }
        @{
            Canonical   = '--options'
            Aliases     = @('--options')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Pass module-specific options (module:key=value, comma separated).'
            ValueKind   = 'Options'
        }
        @{
            Canonical   = '--passphrase'
            Aliases     = @('--passphrase')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Passphrase for encrypted zip archives.'
            ValueKind   = 'Passphrase'
        }
        @{
            Canonical   = '--read-sparse'
            Aliases     = @('--read-sparse')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Read sparse file holes efficiently when archiving.'
        }
        @{
            Canonical   = '--no-read-sparse'
            Aliases     = @('--no-read-sparse')
            Modes       = $script:TarCompletionCatalog.AllModes
            Description = 'Read sparse files as regular files when archiving.'
        }
        @{
            Canonical   = '-k'
            Aliases     = @('-k', '--keep-old-files')
            ShortName   = 'k'
            Modes       = @('x')
            Description = 'Do not overwrite existing files when extracting.'
        }
        @{
            Canonical   = '-m'
            Aliases     = @('-m', '--modification-time')
            ShortName   = 'm'
            Modes       = @('x')
            Description = 'Do not restore modification times when extracting.'
        }
        @{
            Canonical   = '-O'
            Aliases     = @('-O', '--to-stdout')
            ShortName   = 'O'
            Modes       = @('t', 'x')
            Description = 'Write extracted entries to stdout instead of restoring them to disk.'
        }
        @{
            Canonical   = '-p'
            Aliases     = @('-p', '--preserve-permissions', '--same-permissions')
            ShortName   = 'p'
            Modes       = @('x')
            Description = 'Restore permissions, owner data, ACLs, and file flags when extracting.'
        }
        @{
            Canonical   = '-o'
            Aliases     = @('-o')
            ShortName   = 'o'
            Modes       = @('c', 'r', 'u', 'x')
            Description = 'Create: use the ustar format; extract: do not restore owner (--no-same-owner).'
        }
        @{
            Canonical   = '--help'
            Aliases     = @('--help')
            Modes       = $script:TarCompletionCatalog.AllModes
            Standalone  = $true
            Description = 'Show the bsdtar usage summary and exit.'
        }
        @{
            Canonical   = '--version'
            Aliases     = @('--version')
            Modes       = $script:TarCompletionCatalog.AllModes
            Standalone  = $true
            Description = 'Show the bsdtar and libarchive version and exit.'
        }
    )

    # GNU tar rejects roughly a third of the bsdtar catalog and adds four modes of its own, so its
    # catalog is parsed from the live --help instead; the static table stays the bsdtar model.
    if ((Get-TarFlavor) -eq 'gnu') {
        $helpLines = @()
        try {
            $helpLines = @($null | & $script:TarCompletionCatalog.CommandPath --help 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })
        } catch {
            Write-Debug "tar --help probe failed: $($_.Exception.Message)"
        }

        $parsed = ConvertFrom-TarGnuHelp -Lines $helpLines
        if ($parsed.OptionSpecs.Count -gt 0 -and $parsed.ModeSpecs.Count -gt 0) {
            $modeSpecs = $parsed.ModeSpecs
            $script:TarCompletionCatalog.AllModes = @($modeSpecs | ForEach-Object { $_.Canonical })
            $optionSpecs = @(
                foreach ($spec in $parsed.OptionSpecs) {
                    $spec.Modes = $script:TarCompletionCatalog.AllModes
                    $spec
                }
            )
            $script:TarCompletionCatalog.FormatValues = if ($parsed.FormatValues.Count -gt 0) { $parsed.FormatValues } else { @('gnu', 'oldgnu', 'pax', 'posix', 'ustar', 'v7') }
        }
    }

    $modeEntries = @()
    $modeByAlias = @{}
    foreach ($modeSpec in $modeSpecs) {
        foreach ($alias in $modeSpec.Aliases) {
            $modeEntries += [pscustomobject]@{
                Canonical      = $modeSpec.Canonical
                CompletionText = $alias
                Description    = $modeSpec.Description
            }
            $modeByAlias[$alias.ToLowerInvariant()] = $modeSpec.Canonical
        }
    }

    $optionEntries = @()
    $standaloneEntries = @()
    $optionByAlias = @{}
    $shortOptionByChar = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::Ordinal)
    $shortValueByChar = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::Ordinal)
    foreach ($optionSpec in $optionSpecs) {
        $specObject = [pscustomobject]$optionSpec
        foreach ($alias in $specObject.Aliases) {
            $valueKind = Get-TarValueKind -InputObject $specObject
            $entry = [pscustomobject]@{
                Canonical      = $specObject.Canonical
                CompletionText = $alias
                Description    = $specObject.Description
                Modes          = @($specObject.Modes)
                ValueKind      = $valueKind
                OptionalValue  = [bool]($optionSpec.ContainsKey('OptionalValue') -and $optionSpec.OptionalValue)
                Values         = @(if ($optionSpec.ContainsKey('Values')) { $optionSpec.Values })
            }
            $optionEntries += $entry
            $optionByAlias[$alias.ToLowerInvariant()] = $entry
            if ($optionSpec.ContainsKey('Standalone')) {
                $standaloneEntries += $entry
            }
        }

        if ($specObject.PSObject.Properties.Name -contains 'ShortName') {
            $shortName = [string]$specObject.ShortName
            if (-not [string]::IsNullOrWhiteSpace($shortName)) {
                $shortOptionByChar[$shortName] = $specObject
                if ($specObject.PSObject.Properties.Name -contains 'ValueKind') {
                    $shortValueByChar[$shortName] = $specObject
                }
            }
        }
    }

    $script:TarCompletionCatalog.ModeEntries = @($modeEntries)
    $script:TarCompletionCatalog.ModeByAlias = $modeByAlias
    $script:TarCompletionCatalog.OptionEntries = @($optionEntries)
    $script:TarCompletionCatalog.StandaloneEntries = @($standaloneEntries)
    $script:TarCompletionCatalog.OptionByAlias = $optionByAlias
    $script:TarCompletionCatalog.ShortOptionByChar = $shortOptionByChar
    $script:TarCompletionCatalog.ShortValueByChar = $shortValueByChar
    $script:TarCompletionCatalog.Initialized = $true
}

function Get-TarDateHintList {
    # Computed per completion so "today" stays today; only forms bsdtar's date parser accepts
    # (ISO 'T'-separated and round-trip timestamps are rejected with "bad date string").
    $now = Get-Date
    @(
        $now.ToString('yyyy-MM-dd')
        $now.ToString('yyyy-MM-dd HH:mm:ss')
        $now.AddDays(-1).ToString('yyyy-MM-dd')
        $now.AddDays(-7).ToString('yyyy-MM-dd')
        '2024-01-01'
        '2024-01-01 00:00:00'
        '@' + [System.DateTimeOffset]::new($now).ToUnixTimeSeconds()
    )
}

function Get-TarCurrentToken {
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

    $parts = @([regex]::Matches($prefix, $script:TarCompletionCatalog.TokenPattern) | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Test-TarBareBundle {
    param(
        [string]$Token,
        [string]$KnownMode
    )

    if ([string]::IsNullOrWhiteSpace($Token) -or $Token.StartsWith('-', [System.StringComparison]::Ordinal)) {
        return $false
    }

    $mode = $KnownMode
    for ($index = 0; $index -lt $Token.Length; $index++) {
        $character = [string]$Token[$index]
        if ((-not $mode) -and $index -eq 0 -and $script:TarCompletionCatalog.AllModes -ccontains $character) {
            $mode = $character
            continue
        }

        if ($script:TarCompletionCatalog.ShortValueByChar.ContainsKey($character) -or $script:TarCompletionCatalog.ShortOptionByChar.ContainsKey($character)) {
            continue
        }

        return $false
    }

    $true
}

function Get-TarParsedTokenInfo {
    param(
        [string]$Token,
        [string]$KnownMode
    )

    $result = [ordered]@{
        Mode         = $KnownMode
        PendingValue = $null
        IsPositional = $true
    }

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return [pscustomobject]$result
    }

    if ($Token.StartsWith('--', [System.StringComparison]::Ordinal)) {
        $match = [regex]::Match($Token, '^(--[^=]+)(?:=(.*))?$')
        if (-not $match.Success) {
            return [pscustomobject]$result
        }

        $name = $match.Groups[1].Value
        $lookup = $name.ToLowerInvariant()
        if ((-not $KnownMode) -and $script:TarCompletionCatalog.ModeByAlias.ContainsKey($lookup)) {
            $result.Mode = $script:TarCompletionCatalog.ModeByAlias[$lookup]
            $result.IsPositional = $false
            return [pscustomobject]$result
        }

        if ($script:TarCompletionCatalog.OptionByAlias.ContainsKey($lookup)) {
            $result.IsPositional = $false
            $option = $script:TarCompletionCatalog.OptionByAlias[$lookup]
            $valueKind = Get-TarValueKind -InputObject $option
            # An optional value (--occurrence[=NUMBER]) only ever arrives attached, never as the next token.
            if (-not [string]::IsNullOrWhiteSpace($valueKind) -and -not $match.Groups[2].Success -and -not $option.OptionalValue) {
                $result.PendingValue = $valueKind
            }

            return [pscustomobject]$result
        }

        return [pscustomobject]$result
    }

    if ($Token.StartsWith('-', [System.StringComparison]::Ordinal) -and -not $Token.StartsWith('--', [System.StringComparison]::Ordinal) -and $Token.Length -gt 1) {
        $result.IsPositional = $false
        $bundle = $Token.Substring(1)
        $mode = $KnownMode

        for ($index = 0; $index -lt $bundle.Length; $index++) {
            $character = [string]$bundle[$index]
            if ((-not $mode) -and $index -eq 0 -and $script:TarCompletionCatalog.AllModes -ccontains $character) {
                $mode = $character
                $result.Mode = $mode
                continue
            }

            if ($script:TarCompletionCatalog.ShortValueByChar.ContainsKey($character)) {
                if ($index -eq ($bundle.Length - 1)) {
                    $result.PendingValue = $script:TarCompletionCatalog.ShortValueByChar[$character].ValueKind
                }

                return [pscustomobject]$result
            }

            if ($script:TarCompletionCatalog.ShortOptionByChar.ContainsKey($character)) {
                continue
            }

            return [pscustomobject]$result
        }

        return [pscustomobject]$result
    }

    if (Test-TarBareBundle -Token $Token -KnownMode $KnownMode) {
        $result.IsPositional = $false
        $bundle = $Token
        $mode = $KnownMode

        for ($index = 0; $index -lt $bundle.Length; $index++) {
            $character = [string]$bundle[$index]
            if ((-not $mode) -and $index -eq 0 -and $script:TarCompletionCatalog.AllModes -ccontains $character) {
                $mode = $character
                $result.Mode = $mode
                continue
            }

            if ($script:TarCompletionCatalog.ShortValueByChar.ContainsKey($character)) {
                if ($index -eq ($bundle.Length - 1)) {
                    $result.PendingValue = $script:TarCompletionCatalog.ShortValueByChar[$character].ValueKind
                }

                return [pscustomobject]$result
            }

            if ($script:TarCompletionCatalog.ShortOptionByChar.ContainsKey($character)) {
                continue
            }

            return [pscustomobject]$result
        }

        return [pscustomobject]$result
    }

    [pscustomobject]$result
}

function Get-TarCompletionState {
    param([string[]]$Tokens)

    $state = [ordered]@{
        Mode             = $null
        PendingValue     = $null
        OptionTerminated = $false
        Positionals      = @()
    }

    $positionals = New-Object System.Collections.Generic.List[string]
    foreach ($token in $Tokens) {
        if ($state.PendingValue) {
            $state.PendingValue = $null
            continue
        }

        if ($state.OptionTerminated) {
            $positionals.Add($token)
            continue
        }

        if ($token -eq '--') {
            $state.OptionTerminated = $true
            continue
        }

        $parsed = Get-TarParsedTokenInfo -Token $token -KnownMode $state.Mode
        if ($parsed.Mode) {
            $state.Mode = $parsed.Mode
        }

        if ($parsed.PendingValue) {
            $state.PendingValue = $parsed.PendingValue
            continue
        }

        if ($parsed.IsPositional) {
            $positionals.Add($token)
        }
    }

    $state.Positionals = @($positionals)
    [pscustomobject]$state
}

function Get-TarCurrentValueContext {
    param(
        [string]$Token,
        [string]$KnownMode
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    if ($Token.StartsWith('--', [System.StringComparison]::Ordinal)) {
        $match = [regex]::Match($Token, '^(--[^=]+)=(.*)$')
        if (-not $match.Success) {
            return $null
        }

        $lookup = $match.Groups[1].Value.ToLowerInvariant()
        if (-not $script:TarCompletionCatalog.OptionByAlias.ContainsKey($lookup)) {
            return $null
        }

        $option = $script:TarCompletionCatalog.OptionByAlias[$lookup]
        $valueKind = Get-TarValueKind -InputObject $option
        if ([string]::IsNullOrWhiteSpace($valueKind)) {
            return $null
        }

        return [pscustomobject]@{
            ValueKind    = $valueKind
            Prefix       = $match.Groups[1].Value + '='
            CurrentValue = $match.Groups[2].Value
            Mode         = $KnownMode
        }
    }

    if ($Token.StartsWith('-', [System.StringComparison]::Ordinal) -and -not $Token.StartsWith('--', [System.StringComparison]::Ordinal) -and $Token.Length -gt 1) {
        $bundle = $Token.Substring(1)
        $mode = $KnownMode

        for ($index = 0; $index -lt $bundle.Length; $index++) {
            $character = [string]$bundle[$index]
            if ((-not $mode) -and $index -eq 0 -and $script:TarCompletionCatalog.AllModes -ccontains $character) {
                $mode = $character
                continue
            }

            if (-not $script:TarCompletionCatalog.ShortValueByChar.ContainsKey($character)) {
                if ($script:TarCompletionCatalog.ShortOptionByChar.ContainsKey($character)) {
                    continue
                }

                return $null
            }

            $currentValue = ''
            if ($index -lt ($bundle.Length - 1)) {
                $currentValue = $bundle.Substring($index + 1)
            }

            return [pscustomobject]@{
                ValueKind    = $script:TarCompletionCatalog.ShortValueByChar[$character].ValueKind
                Prefix       = '-' + $bundle.Substring(0, $index + 1)
                CurrentValue = $currentValue
                Mode         = $mode
            }
        }
    }

    if (Test-TarBareBundle -Token $Token -KnownMode $KnownMode) {
        $bundle = $Token
        $mode = $KnownMode

        for ($index = 0; $index -lt $bundle.Length; $index++) {
            $character = [string]$bundle[$index]
            if ((-not $mode) -and $index -eq 0 -and $script:TarCompletionCatalog.AllModes -ccontains $character) {
                $mode = $character
                continue
            }

            if (-not $script:TarCompletionCatalog.ShortValueByChar.ContainsKey($character)) {
                if ($script:TarCompletionCatalog.ShortOptionByChar.ContainsKey($character)) {
                    continue
                }

                return $null
            }

            $currentValue = ''
            if ($index -lt ($bundle.Length - 1)) {
                $currentValue = $bundle.Substring($index + 1)
            }

            return [pscustomobject]@{
                ValueKind    = $script:TarCompletionCatalog.ShortValueByChar[$character].ValueKind
                Prefix       = $bundle.Substring(0, $index + 1)
                CurrentValue = $currentValue
                Mode         = $mode
            }
        }
    }

    $null
}

function Get-TarModeCompletionResults {
    param([string]$CurrentValue)

    foreach ($entry in $script:TarCompletionCatalog.ModeEntries) {
        if (Test-TarStartsWith -Value $entry.CompletionText -Prefix $CurrentValue) {
            New-TarCompletionResult -CompletionText $entry.CompletionText -ResultType 'ParameterName' -ToolTip $entry.Description
        }
    }
}

function Get-TarOptionCompletionResults {
    param(
        [string]$Mode,
        [string]$CurrentValue
    )

    foreach ($entry in $script:TarCompletionCatalog.OptionEntries) {
        if (($entry.Modes -contains $Mode) -and (Test-TarStartsWith -Value $entry.CompletionText -Prefix $CurrentValue)) {
            New-TarCompletionResult -CompletionText $entry.CompletionText -ResultType 'ParameterName' -ToolTip $entry.Description
        }
    }
}

function Get-TarSimpleValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$ToolTipPrefix,
        [string]$Prefix
    )

    $alwaysQuote = $CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'")
    $cleanCurrent = Remove-TarOuterQuotes -Value $CurrentValue
    foreach ($value in ($Values | Sort-Object -Unique)) {
        if (Test-TarStartsWith -Value $value -Prefix $cleanCurrent) {
            $completionText = ConvertTo-TarQuotedValue -Value $value -AlwaysQuote:$alwaysQuote
            if ($Prefix) {
                $completionText = $Prefix + $completionText
            }

            $toolTip = if ([string]::IsNullOrWhiteSpace($ToolTipPrefix)) { $value } else { $ToolTipPrefix + ': ' + $value }
            New-TarCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $toolTip
        }
    }
}

function Get-TarPathCompletionResults {
    param(
        [string]$CurrentValue,
        [string]$Prefix,
        [switch]$DirectoryOnly,
        [string]$ToolTipPrefix = 'Path'
    )

    $startedQuoted = $CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'")
    $pathText = Remove-TarOuterQuotes -Value $CurrentValue
    $isRootDrive = $pathText -match '^[A-Za-z]:$'

    if ([string]::IsNullOrEmpty($pathText)) {
        $searchBase = '.'
        $leaf = ''
        $useParentInCompletion = $false
    }
    elseif ($isRootDrive) {
        $searchBase = $pathText + '\'
        $leaf = ''
        $useParentInCompletion = $true
    }
    elseif ($pathText.EndsWith('\') -or $pathText.EndsWith('/')) {
        $searchBase = $pathText
        $leaf = ''
        $useParentInCompletion = $true
    }
    else {
        $parentPath = Split-Path -Path $pathText -Parent
        $leaf = Split-Path -Path $pathText -Leaf
        if ([string]::IsNullOrEmpty($parentPath)) {
            $searchBase = '.'
            $useParentInCompletion = $false
        }
        else {
            $searchBase = $parentPath
            $useParentInCompletion = $true
        }
    }

    $items = @(Get-ChildItem -LiteralPath $searchBase -ErrorAction SilentlyContinue |
            Sort-Object -Property @{ Expression = 'PSIsContainer'; Descending = $true }, Name)

    foreach ($item in $items) {
        if ($DirectoryOnly -and -not $item.PSIsContainer) {
            continue
        }

        if (-not (Test-TarStartsWith -Value $item.Name -Prefix $leaf)) {
            continue
        }

        $candidate = if ($useParentInCompletion) {
            Join-Path -Path $searchBase -ChildPath $item.Name
        }
        else {
            $item.Name
        }

        if ($item.PSIsContainer) {
            $candidate += [System.IO.Path]::DirectorySeparatorChar
        }

        $completionText = ConvertTo-TarQuotedValue -Value $candidate -AlwaysQuote:$startedQuoted
        if ($Prefix) {
            $completionText = $Prefix + $completionText
        }

        $toolTip = $ToolTipPrefix
        if ($item.PSIsContainer) {
            $toolTip += ' directory'
        }
        else {
            $toolTip += ' file'
        }

        New-TarCompletionResult -CompletionText $completionText -ResultType 'ProviderItem' -ToolTip $toolTip
    }
}

function Get-TarPatternCompletionResults {
    param(
        [string]$CurrentValue,
        [string]$Prefix,
        [string]$ToolTipPrefix = 'Pattern'
    )

    $alwaysQuote = $CurrentValue.StartsWith('"') -or $CurrentValue.StartsWith("'")
    $cleanCurrent = Remove-TarOuterQuotes -Value $CurrentValue
    $suggestions = New-Object System.Collections.Generic.List[string]

    foreach ($defaultPattern in $script:TarCompletionCatalog.DefaultPatterns) {
        $suggestions.Add($defaultPattern)
    }

    if (-not [string]::IsNullOrWhiteSpace($cleanCurrent)) {
        $suggestions.Add($cleanCurrent)

        if ($cleanCurrent -notmatch '[\*\?\[]') {
            $suggestions.Add($cleanCurrent + '*')
            $suggestions.Add('*' + $cleanCurrent + '*')
            if ($cleanCurrent -notmatch '[/\\]$') {
                $suggestions.Add($cleanCurrent + '/*')
            }
        }
    }

    foreach ($value in ($suggestions | Sort-Object -Unique)) {
        if (Test-TarStartsWith -Value $value -Prefix $cleanCurrent) {
            $completionText = ConvertTo-TarQuotedValue -Value $value -AlwaysQuote:$alwaysQuote
            if ($Prefix) {
                $completionText = $Prefix + $completionText
            }

            New-TarCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip ($ToolTipPrefix + ': ' + $value)
        }
    }
}

function Invoke-TarValueCompletion {
    param(
        [string]$ValueKind,
        [string]$CurrentValue,
        [string]$Prefix
    )

    switch ($ValueKind) {
        'ArchivePath' {
            Get-TarPathCompletionResults -CurrentValue $CurrentValue -Prefix $Prefix -ToolTipPrefix 'Archive path'
            break
        }
        'DirectoryPath' {
            Get-TarPathCompletionResults -CurrentValue $CurrentValue -Prefix $Prefix -DirectoryOnly -ToolTipPrefix 'Directory path'
            break
        }
        'Format' {
            Get-TarSimpleValueResults -Values $script:TarCompletionCatalog.FormatValues -CurrentValue $CurrentValue -ToolTipPrefix 'Archive format' -Prefix $Prefix
            break
        }
        'DateTime' {
            Get-TarSimpleValueResults -Values (Get-TarDateHintList) -CurrentValue $CurrentValue -ToolTipPrefix 'Date' -Prefix $Prefix
            break
        }
        'BlockSize' {
            Get-TarSimpleValueResults -Values $script:TarCompletionCatalog.BlockSizeHints -CurrentValue $CurrentValue -ToolTipPrefix '512-byte record count' -Prefix $Prefix
            break
        }
        'StripCount' {
            Get-TarSimpleValueResults -Values $script:TarCompletionCatalog.StripCountHints -CurrentValue $CurrentValue -ToolTipPrefix 'Leading path elements to strip' -Prefix $Prefix
            break
        }
        'CompressProgram' {
            Get-TarSimpleValueResults -Values $script:TarCompletionCatalog.CompressProgramHints -CurrentValue $CurrentValue -ToolTipPrefix 'Compression program' -Prefix $Prefix
            break
        }
        'Id' {
            Get-TarSimpleValueResults -Values @('0', '1000', '<id>') -CurrentValue $CurrentValue -ToolTipPrefix 'Numeric ID' -Prefix $Prefix
            break
        }
        'Name' {
            Get-TarSimpleValueResults -Values @('<name>') -CurrentValue $CurrentValue -ToolTipPrefix 'Name' -Prefix $Prefix
            break
        }
        'Options' {
            Get-TarSimpleValueResults -Values @('<module:key=value>') -CurrentValue $CurrentValue -ToolTipPrefix 'Module option' -Prefix $Prefix
            break
        }
        'Passphrase' {
            Get-TarSimpleValueResults -Values @('<passphrase>') -CurrentValue $CurrentValue -ToolTipPrefix 'Passphrase' -Prefix $Prefix
            break
        }
        'Pattern' {
            Get-TarPatternCompletionResults -CurrentValue $CurrentValue -Prefix $Prefix -ToolTipPrefix 'Pattern'
            break
        }
        default {
            if ($ValueKind -like 'Enum:*') {
                $lookup = $ValueKind.Substring(5).ToLowerInvariant()
                $values = @()
                if ($script:TarCompletionCatalog.OptionByAlias.ContainsKey($lookup)) {
                    $values = @($script:TarCompletionCatalog.OptionByAlias[$lookup].Values)
                }
                Get-TarSimpleValueResults -Values $values -CurrentValue $CurrentValue -ToolTipPrefix 'Value' -Prefix $Prefix
            } elseif ($ValueKind -like 'Text:*') {
                $placeholder = '<' + $ValueKind.Substring(5).ToLowerInvariant() + '>'
                Get-TarSimpleValueResults -Values @($placeholder) -CurrentValue $CurrentValue -ToolTipPrefix 'Value' -Prefix $Prefix
            }
            break
        }
    }
}

function Invoke-TarPositionalCompletion {
    param(
        [string]$Mode,
        [string]$CurrentValue,
        [bool]$IncludeOptions
    )

    $results = @()
    $seen = @{}

    if ($IncludeOptions) {
        foreach ($option in (Get-TarOptionCompletionResults -Mode $Mode -CurrentValue '')) {
            if (-not $seen.ContainsKey($option.CompletionText)) {
                $seen[$option.CompletionText] = $true
                $results += $option
            }
        }
    }

    if ($Mode -in @('c', 'r', 'u', 'A')) {
        if ($CurrentValue.StartsWith('@')) {
            foreach ($item in (Get-TarPathCompletionResults -CurrentValue $CurrentValue.Substring(1) -Prefix '@' -ToolTipPrefix 'Source archive')) {
                if (-not $seen.ContainsKey($item.CompletionText)) {
                    $seen[$item.CompletionText] = $true
                    $results += $item
                }
            }
        }
        else {
            foreach ($item in (Get-TarPathCompletionResults -CurrentValue $CurrentValue -ToolTipPrefix 'Archive input')) {
                if (-not $seen.ContainsKey($item.CompletionText)) {
                    $seen[$item.CompletionText] = $true
                    $results += $item
                }
            }
        }
    }
    elseif ($Mode -in @('t', 'x', 'd', 'delete')) {
        foreach ($item in (Get-TarPatternCompletionResults -CurrentValue $CurrentValue -ToolTipPrefix 'Archive entry pattern')) {
            if (-not $seen.ContainsKey($item.CompletionText)) {
                $seen[$item.CompletionText] = $true
                $results += $item
            }
        }
    }

    @($results)
}

function Complete-Tar {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    if (-not (Resolve-TarCommandName)) {
        return
    }

    Initialize-TarCompletionCatalog

    $line = $commandAst.ToString()
    $prefixLength = [Math]::Min([Math]::Max($cursorPosition - $commandAst.Extent.StartOffset, 0), $line.Length)
    $linePrefix = $line.Substring(0, $prefixLength)
    $tokens = @([regex]::Matches($linePrefix, $script:TarCompletionCatalog.TokenPattern) | ForEach-Object { $_.Value })
    $hasTrailingSpace = ($linePrefix -match '\s$') -or (($cursorPosition - $commandAst.Extent.StartOffset) -gt $line.Length)
    $currentToken = if ($hasTrailingSpace) { '' } else { Get-TarCurrentToken -Line $line -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete }

    [object[]]$argumentTokens = if ($tokens.Count -gt 1) {
        @($tokens[1..($tokens.Count - 1)])
    }
    else {
        @()
    }

    [object[]]$completedTokens = if ($hasTrailingSpace) {
        @($argumentTokens)
    }
    elseif ($argumentTokens.Count -gt 1) {
        @($argumentTokens[0..($argumentTokens.Count - 2)])
    }
    else {
        @()
    }

    $state = Get-TarCompletionState -Tokens $completedTokens

    if (-not $hasTrailingSpace) {
        $currentValueContext = Get-TarCurrentValueContext -Token $currentToken -KnownMode $state.Mode
        if ($currentValueContext) {
            Invoke-TarValueCompletion -ValueKind $currentValueContext.ValueKind -CurrentValue $currentValueContext.CurrentValue -Prefix $currentValueContext.Prefix
            return
        }
    }

    if ($state.PendingValue) {
        Invoke-TarValueCompletion -ValueKind $state.PendingValue -CurrentValue $currentToken -Prefix ''
        return
    }

    if (-not $state.Mode) {
        Get-TarModeCompletionResults -CurrentValue $currentToken
        if ($currentToken.StartsWith('-')) {
            foreach ($entry in $script:TarCompletionCatalog.StandaloneEntries) {
                if (Test-TarStartsWith -Value $entry.CompletionText -Prefix $currentToken) {
                    New-TarCompletionResult -CompletionText $entry.CompletionText -ResultType 'ParameterName' -ToolTip $entry.Description
                }
            }
        }
        return
    }

    if ((-not $state.OptionTerminated) -and $currentToken.StartsWith('-')) {
        Get-TarOptionCompletionResults -Mode $state.Mode -CurrentValue $currentToken
        return
    }

    Invoke-TarPositionalCompletion -Mode $state.Mode -CurrentValue $currentToken -IncludeOptions:((-not $state.OptionTerminated) -and [string]::IsNullOrEmpty($currentToken))
}

Register-ArgumentCompleter -Native -CommandName 'tar', 'tar.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Tar -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
