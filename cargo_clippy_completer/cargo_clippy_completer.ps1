# cargo-clippy native argument completer for PowerShell
# Help-driven completer for cargo-clippy.exe using local cargo/clippy help text.

Set-StrictMode -Version 2.0

if ($true) {
function Get-CargoClippyCompletionCache {
    $cache = Get-Variable -Name CargoClippyCompletionCache -Scope Script -ErrorAction Ignore
    if ($null -ne $cache) {
        return $cache.Value
    }

    $newCache = @{
        Initialized          = $false
        CargoClippyCommand   = $null
        CargoCommand         = $null
        CommandOptions       = @()
        CommandDescriptions  = @{}
        CommandValueMap      = @{}
        PathOptions          = @('-m', '--manifest-path', '--target-dir')
        LintOptions          = @('-W', '--warn', '-A', '--allow', '-D', '--deny', '-F', '--forbid')
        LintDescriptions     = @{}
        LintValueMap         = @{}
        UnstableFlags        = @()
        FixOptions           = @()
        FixOptionsLoaded     = $false
        LintNames            = @()
        LintNamesLoaded      = $false
        TargetTriples        = @()
        TargetTriplesLoaded  = $false
        ManifestFacts        = $null
        ManifestLoadedFor    = $null
        ManifestLoadedAt     = $null
    }

    Set-Variable -Name CargoClippyCompletionCache -Scope Script -Value $newCache
    $newCache
}

function Resolve-CargoClippyCommandName {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.CargoClippyCommand) {
        return $cache.CargoClippyCommand
    }

    $command = Get-Command -Name cargo-clippy.exe, cargo-clippy -ErrorAction Ignore | Select-Object -First 1
    if ($command) {
        $cache.CargoClippyCommand = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $cache.CargoClippyCommand
}

function Resolve-CargoCommandName {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.CargoCommand) {
        return $cache.CargoCommand
    }

    $command = Get-Command -Name cargo.exe, cargo -ErrorAction Ignore | Select-Object -First 1
    if ($command) {
        $cache.CargoCommand = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $cache.CargoCommand
}

function Invoke-CargoClippyText {
    param([string[]]$Arguments)

    $commandName = Resolve-CargoClippyCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>&1 | ForEach-Object { $_.ToString() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })
    } catch {
        @()
    }
}

function Invoke-CargoText {
    param([string[]]$Arguments)

    $commandName = Resolve-CargoCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>&1 | ForEach-Object { $_.ToString() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })
    } catch {
        @()
    }
}

function New-CargoClippyCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ListItemText,
        [string]$ResultType,
        [string]$ToolTip
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

function Remove-CargoClippyOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function Get-CargoClippyTypedQuote {
    # The quote character (ASCII or typographic) the user opened the word with ('' when bare).
    param([string]$Value)

    if ($Value -match '^[''"\u2018-\u201E]') {
        return $Value.Substring(0, 1)
    }

    ''
}

function ConvertFrom-CargoClippyTypedWord {
    # The value of a typed word. A word holding a quote (leading or mid-word, as in it's) is read
    # by the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ($Value -notmatch '[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    if ($tokens[0] -is [System.Management.Automation.Language.StringToken]) {
        return $tokens[0].Value
    }

    $Value
}

function ConvertTo-CargoClippyQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the typed quote style (single by default). Whitespace and argument-mode
    # metacharacters (including the typographic quotes, '@' and '#') end, split or reinterpret
    # a bare word. PowerShell reads ' and U+2018-U+201B as single quotes and " and
    # U+201C-U+201E as double quotes.
    param(
        [string]$Value,
        [string]$Quote
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $Quote) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -match '^[''\u2018-\u201B]$') {
        return $Quote + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $Quote
    }

    $Quote + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $Quote
}

function Get-CargoClippyPathCompletions {
    param([string]$InputPath)

    $quote = Get-CargoClippyTypedQuote -Value $InputPath
    $cleanInput = ConvertFrom-CargoClippyTypedWord -Value $InputPath

    [System.Management.Automation.CompletionCompleters]::CompleteFilename($cleanInput) |
        ForEach-Object {
            # CompleteFilename quotes for PowerShell and wildcard-escapes for -Path parameters
            # (tick``x.txt); cargo takes literal paths, so unwrap with the parser (which undoes
            # every doubled quote, typographic ones included), unescape, and quote exactly once
            # in the style the user typed.
            $path = $_.CompletionText
            if ($path -match '^[''"]') {
                $ast = [System.Management.Automation.Language.Parser]::ParseInput($path, [ref]$null, [ref]$null)
                $constant = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
                if ($constant) {
                    $path = $constant.Value
                }
            }

            $path = [System.Management.Automation.WildcardPattern]::Unescape($path)
            # CompleteFilename turns a typed ./ or ../ into the native separator; keep the one typed.
            if ($cleanInput -match '^\.{1,2}/') {
                $path = $path.Replace([System.IO.Path]::DirectorySeparatorChar, '/')
            }

            $completionText = ConvertTo-CargoClippyQuotedValue -Value $path -Quote $quote
            New-CargoClippyCompletionResult -CompletionText $completionText -ListItemText $_.ListItemText -ResultType $_.ResultType -ToolTip $_.ToolTip
        }
}

function Get-CargoClippyCurrentWord {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition,
        [string]$Fallback
    )

    # The parser keeps an unterminated quoted word as one element running past the cursor, so
    # the element under the cursor is the whole word even when it holds spaces.
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.StartOffset -lt $CursorPosition -and $CursorPosition -le $element.Extent.EndOffset) {
            return $element.Extent.Text.Substring(0, $CursorPosition - $element.Extent.StartOffset)
        }
    }

    # Between words, where PowerShell's own word is empty too.
    $Fallback
}

function Get-CargoClippyArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += $element.Extent.Text
        }
    }

    $tokens
}

function Get-CargoClippyOptionMetadataFromLines {
    param([string[]]$Lines)

    # -F/--forbid and -F/--features are different options, so the table has to be case-exact.
    $result = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)

    foreach ($line in $Lines) {
        $trimmedLine = $line.TrimStart()
        $parts = $trimmedLine -split '\s{2,}', 2
        if ($parts.Count -lt 2) {
            continue
        }

        $spec = $parts[0].Trim()
        $description = $parts[1].Trim()
        if (-not $spec.StartsWith('-')) {
            continue
        }

        # clippy writes its lint-level pairs as '-W / --warn [LINT]', cargo writes '-W, --warn'.
        $tokens = @([regex]::Matches($spec, '(?:^|,\s*|\s*/\s*)(-[A-Za-z]|--[A-Za-z0-9][A-Za-z0-9\-]*)') | ForEach-Object { $_.Groups[1].Value })
        if ($tokens.Count -eq 0) {
            continue
        }

        foreach ($token in $tokens) {
            if (-not $result.ContainsKey($token)) {
                $result[$token] = $description
            }
        }
    }

    $result
}

function Get-CargoClippyCommandValueMap {
    @{
        '--color'          = @('auto', 'always', 'never')
        '--config'         = @('<KEY=VALUE>', '<path>')
        '--explain'        = @('<lint>')
        '--message-format' = @('human', 'short', 'json', 'json-diagnostic-short', 'json-diagnostic-rendered-ansi', 'json-render-diagnostics')
        '--package'        = @('<package-spec>')
        '-p'               = @('<package-spec>')
        '--exclude'        = @('<package-spec>')
        '--bin'            = @('<target-name>')
        '--example'        = @('<target-name>')
        '--test'           = @('<target-name>')
        '--bench'          = @('<target-name>')
        '--features'       = @('<features>')
        '-F'               = @('<features>')
        '--profile'        = @('<profile-name>')
        '--target'         = @('<target-triple>')
        '--manifest-path'  = @('<path>')
        '-m'               = @('<path>')
        '--target-dir'     = @('<path>')
        '--jobs'           = @('<jobs>')
        '-j'               = @('<jobs>')
        '-Z'               = @()
    }
}

function Get-CargoClippyLintValueMap {
    @{
        '-W'      = @('<lint>', 'clippy::<lint>')
        '--warn'  = @('<lint>', 'clippy::<lint>')
        '-A'      = @('<lint>', 'clippy::<lint>')
        '--allow' = @('<lint>', 'clippy::<lint>')
        '-D'      = @('<lint>', 'clippy::<lint>')
        '--deny'  = @('<lint>', 'clippy::<lint>')
        '-F'      = @('<lint>', 'clippy::<lint>')
        '--forbid' = @('<lint>', 'clippy::<lint>')
    }
}

function Get-CargoClippyUnstableFlags {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.UnstableFlags.Count -gt 0) {
        return $cache.UnstableFlags
    }

    $lines = Invoke-CargoText -Arguments @('-Z', 'help')
    $flags = foreach ($line in $lines) {
        if ($line -match '^\s+-Z\s+([a-z0-9][a-z0-9\-]*)\b') {
            $matches[1]
        }
    }

    $cache.UnstableFlags = @($flags | Sort-Object -Unique -CaseSensitive)
    $cache.UnstableFlags
}

function Get-CargoClippyFixOption {
    # With --fix, clippy runs 'cargo fix', which adds its own flags (--allow-dirty, --broken-code,
    # --edition, ...) on top of the check surface; 'cargo check' rejects them without --fix.
    Initialize-CargoClippyCompletionCache
    $cache = Get-CargoClippyCompletionCache
    if ($cache.FixOptionsLoaded) {
        return $cache.FixOptions
    }

    $cache.FixOptionsLoaded = $true
    $fixOnly = foreach ($entry in (Get-CargoClippyOptionMetadataFromLines -Lines (Invoke-CargoText -Arguments @('fix', '--help'))).GetEnumerator()) {
        if (-not $cache.CommandDescriptions.ContainsKey($entry.Key)) {
            $cache.CommandDescriptions[$entry.Key] = $entry.Value
            $entry.Key
        }
    }

    $cache.FixOptions = @($fixOnly | Sort-Object -Unique -CaseSensitive)
    $cache.FixOptions
}

function Get-CargoClippyLintCatalog {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.LintNamesLoaded) {
        return $cache.LintNames
    }

    $cache.LintNamesLoaded = $true

    $driver = Get-Command -Name clippy-driver.exe, clippy-driver -ErrorAction Ignore | Select-Object -First 1
    if (-not $driver) {
        return $cache.LintNames
    }

    $raw = try {
        $null | & $driver.Source '-W' 'help' 2>&1 | ForEach-Object { $_.ToString() -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' }
    } catch {
        @()
    }

    $lines = @($raw)

    $names = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    [void]$seen.Add('warnings')
    [void]$names.Add([pscustomobject]@{ Name = 'warnings'; ToolTip = 'The group of every lint that is set to warn.' })

    $inGroups = $false
    foreach ($line in $lines) {
        if ($line -match '^Lint groups ') {
            $inGroups = $true
            continue
        }

        if ($line -match '^Lint checks ') {
            $inGroups = $false
            continue
        }

        if ($line -notmatch '^\s+((?:clippy::)?[a-z][a-z0-9_-]*)\s{2,}(\S.*)$') {
            continue
        }

        $name = $matches[1]
        $detail = $matches[2].Trim()
        if ($name -eq 'name' -or -not $seen.Add($name)) {
            continue
        }

        $toolTip = if ($inGroups) { "Lint group: $detail" } else { $detail }
        [void]$names.Add([pscustomobject]@{ Name = $name; ToolTip = $toolTip })
    }

    $cache.LintNames = @($names.ToArray())
    $cache.LintNames
}

function Get-CargoClippyTargetTripleList {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.TargetTriplesLoaded) {
        return $cache.TargetTriples
    }

    $cache.TargetTriplesLoaded = $true

    $rustup = Get-Command -Name rustup.exe, rustup -ErrorAction Ignore | Select-Object -First 1
    if ($rustup) {
        $raw = try {
            $null | & $rustup.Source 'target' 'list' '--installed' 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        } catch {
            @()
        }

        $cache.TargetTriples = @($raw)
    }

    if (@($cache.TargetTriples).Count -eq 0) {
        $rustc = Get-Command -Name rustc.exe, rustc -ErrorAction Ignore | Select-Object -First 1
        if ($rustc) {
            $raw = try {
                $null | & $rustc.Source '--print' 'target-list' 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            } catch {
                @()
            }

            $cache.TargetTriples = @($raw)
        }
    }

    $cache.TargetTriples
}

function Add-CargoClippyTomlArrayString {
    param(
        [string]$Text,
        [System.Collections.Generic.List[string]]$Into
    )

    # Collects the quoted strings of a (possibly multi-line) TOML array; returns $true once the
    # closing bracket has been seen. A '#' outside a string ends the line.
    foreach ($match in [regex]::Matches($Text, '"(?<s>[^"]*)"|''(?<s>[^'']*)''|(?<c>#)|(?<e>\])')) {
        if ($match.Groups['c'].Success) {
            return $false
        }

        if ($match.Groups['e'].Success) {
            return $true
        }

        [void]$Into.Add($match.Groups['s'].Value)
    }

    $false
}

function Read-CargoClippyManifestFile {
    param([string]$Path)

    $info = [pscustomobject]@{
        Path             = $Path
        PackageName      = $null
        Edition          = $null
        WorkspacePointer = $null
        HasWorkspace     = $false
        Members          = [System.Collections.Generic.List[string]]::new()
        DefaultMembers   = $null
        Exclude          = [System.Collections.Generic.List[string]]::new()
        Profiles         = [System.Collections.Generic.List[string]]::new()
        Features         = [System.Collections.Generic.List[string]]::new()
        AutoTargets      = @{}
        ExplicitTargets  = @{}
        ExplicitPaths    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    foreach ($kind in @('bin', 'example', 'test', 'bench')) {
        $info.ExplicitTargets[$kind] = [System.Collections.Generic.List[string]]::new()
    }

    $lines = if ([System.IO.File]::Exists($Path)) {
        try {
            [System.IO.File]::ReadAllLines($Path)
        } catch {
            @()
        }
    } else {
        @()
    }

    $section = ''
    $openArray = $null
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($null -ne $openArray) {
            if (Add-CargoClippyTomlArrayString -Text $trimmed -Into $openArray) {
                $openArray = $null
            }
            continue
        }

        if ($trimmed -match '^\[\[?([^\]]+)\]\]?$') {
            $section = $matches[1].Trim()
            if ($section -match '^profile\.([^.]+)') {
                [void]$info.Profiles.Add($matches[1].Trim('"', "'"))
            } elseif ($section -eq 'workspace') {
                $info.HasWorkspace = $true
            }
            continue
        }

        if ($trimmed -match '^([A-Za-z0-9_"''.-]+)\s*=\s*(.*)$') {
            $key = $matches[1].Trim('"', "'")
            $valueText = $matches[2]
            $stringValue = if ($valueText -match '^["'']([^"'']+)["'']') { $matches[1] } else { $null }
            switch -Regex ($section) {
                '^features$' { [void]$info.Features.Add($key) }
                '^package$' {
                    switch -Regex ($key) {
                        '^name$' { $info.PackageName = $stringValue }
                        '^edition$' { $info.Edition = $stringValue }
                        '^workspace$' { $info.WorkspacePointer = $stringValue }
                        '^edition\.workspace$' { $info.Edition = 'workspace' }
                        '^auto(bin|example|test|bench)s$' {
                            $autoKind = $matches[1]
                            $info.AutoTargets[$autoKind] = $valueText -match '^true\b'
                        }
                    }
                }
                '^(bin|example|test|bench)$' {
                    if ($key -eq 'name' -and $stringValue) {
                        [void]$info.ExplicitTargets[$section].Add($stringValue)
                    } elseif ($key -eq 'path' -and $stringValue) {
                        [void]$info.ExplicitPaths.Add(($stringValue -replace '\\', '/' -replace '^\./', ''))
                    }
                }
                '^workspace$' {
                    $list = $null
                    if ($key -eq 'members') {
                        $list = $info.Members
                    } elseif ($key -eq 'exclude') {
                        $list = $info.Exclude
                    } elseif ($key -eq 'default-members') {
                        $info.DefaultMembers = [System.Collections.Generic.List[string]]::new()
                        $list = $info.DefaultMembers
                    }

                    if ($null -ne $list -and $valueText.StartsWith('[') -and -not (Add-CargoClippyTomlArrayString -Text $valueText -Into $list)) {
                        $openArray = $list
                    }
                }
            }
        }
    }

    $info
}

function Get-CargoClippyWorkspaceMemberDirectory {
    param(
        [object]$Workspace,
        [System.Collections.Generic.List[string]]$Patterns
    )

    $rootDirectory = [System.IO.Path]::GetDirectoryName($Workspace.Path)
    $excluded = @($Workspace.Exclude | ForEach-Object { [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootDirectory, $_)).TrimEnd('\', '/') })
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($pattern in $Patterns) {
        # Expand glob members one path segment at a time; Get-ChildItem wildcards are far too slow on Tab.
        $directories = @($rootDirectory)
        foreach ($segment in ($pattern -split '[\\/]' | Where-Object { $_ -and $_ -ne '.' })) {
            $directories = @(foreach ($parent in $directories) {
                    if ([WildcardPattern]::ContainsWildcardCharacters($segment)) {
                        if ([System.IO.Directory]::Exists($parent)) {
                            $wildcard = [WildcardPattern]::new($segment, [System.Management.Automation.WildcardOptions]::IgnoreCase)
                            foreach ($child in [System.IO.Directory]::GetDirectories($parent)) {
                                if ($wildcard.IsMatch([System.IO.Path]::GetFileName($child))) {
                                    $child
                                }
                            }
                        }
                    } else {
                        [System.IO.Path]::Combine($parent, $segment)
                    }
                })
        }

        foreach ($directory in $directories) {
            $directory = [System.IO.Path]::GetFullPath($directory).TrimEnd('\', '/')
            $isExcluded = $false
            foreach ($excludedDirectory in $excluded) {
                if ($directory -eq $excludedDirectory -or $directory.StartsWith($excludedDirectory + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isExcluded = $true
                }
            }

            if (-not $isExcluded -and [System.IO.File]::Exists([System.IO.Path]::Combine($directory, 'Cargo.toml')) -and $seen.Add($directory)) {
                $directory
            }
        }
    }
}

function Find-CargoClippyWorkspaceRoot {
    param([object]$Manifest)

    if ($Manifest.HasWorkspace) {
        return $Manifest
    }

    if (-not $Manifest.PackageName) {
        return $null
    }

    $packageDirectory = [System.IO.Path]::GetDirectoryName($Manifest.Path)
    $root = $null
    if ($Manifest.WorkspacePointer) {
        $candidate = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($packageDirectory, $Manifest.WorkspacePointer, 'Cargo.toml'))
        $root = Read-CargoClippyManifestFile -Path $candidate
    } else {
        $directory = [System.IO.Path]::GetDirectoryName($packageDirectory)
        while (-not [string]::IsNullOrWhiteSpace($directory)) {
            $candidate = [System.IO.Path]::Combine($directory, 'Cargo.toml')
            if ([System.IO.File]::Exists($candidate)) {
                $parsed = Read-CargoClippyManifestFile -Path $candidate
                if ($parsed.HasWorkspace) {
                    $root = $parsed
                    break
                }
            }

            $directory = [System.IO.Path]::GetDirectoryName($directory)
        }
    }

    # A package below a workspace it is not a member of (or is excluded from) builds standalone.
    if ($null -eq $root -or -not $root.HasWorkspace) {
        return $null
    }

    $members = @(Get-CargoClippyWorkspaceMemberDirectory -Workspace $root -Patterns $root.Members)
    if ($members -contains $packageDirectory.TrimEnd('\', '/')) {
        return $root
    }

    $null
}

function Add-CargoClippyPackageTarget {
    param(
        [object]$Manifest,
        [System.Collections.Generic.Dictionary[string, object]]$Targets
    )

    $packageDirectory = [System.IO.Path]::GetDirectoryName($Manifest.Path)
    $layout = @{ bin = 'src/bin'; example = 'examples'; test = 'tests'; bench = 'benches' }

    # Every filesystem call costs about a millisecond on a scanned drive, so list each directory once.
    $present = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in [System.IO.Directory]::GetDirectories($packageDirectory)) {
        [void]$present.Add([System.IO.Path]::GetFileName($entry))
    }

    if ($present.Contains('src')) {
        foreach ($entry in [System.IO.Directory]::GetFileSystemEntries([System.IO.Path]::Combine($packageDirectory, 'src'))) {
            [void]$present.Add('src/' + [System.IO.Path]::GetFileName($entry))
        }
    }

    foreach ($kind in @('bin', 'example', 'test', 'bench')) {
        foreach ($name in $Manifest.ExplicitTargets[$kind]) {
            [void]$Targets[$kind].Add($name)
        }

        # Edition 2015 (also the default when no edition is set) stops inferring a target kind as
        # soon as one target of that kind is declared explicitly.
        $auto = if ($Manifest.AutoTargets.ContainsKey($kind)) {
            $Manifest.AutoTargets[$kind]
        } else {
            -not (($null -eq $Manifest.Edition -or $Manifest.Edition -eq '2015') -and $Manifest.ExplicitTargets[$kind].Count -gt 0)
        }

        if (-not $auto) {
            continue
        }

        if ($kind -eq 'bin' -and $Manifest.PackageName -and -not $Manifest.ExplicitPaths.Contains('src/main.rs') -and $present.Contains('src/main.rs')) {
            [void]$Targets[$kind].Add($Manifest.PackageName)
        }

        $relative = $layout[$kind]
        if (-not $present.Contains($relative)) {
            continue
        }

        foreach ($entry in [System.IO.DirectoryInfo]::new([System.IO.Path]::Combine($packageDirectory, $relative)).GetFileSystemInfos()) {
            if ($entry -is [System.IO.DirectoryInfo]) {
                if (-not $Manifest.ExplicitPaths.Contains("$relative/$($entry.Name)/main.rs") -and
                    [System.IO.File]::Exists([System.IO.Path]::Combine($entry.FullName, 'main.rs'))) {
                    [void]$Targets[$kind].Add($entry.Name)
                }
            } elseif ($entry.Extension -eq '.rs' -and -not $Manifest.ExplicitPaths.Contains("$relative/$($entry.Name)")) {
                [void]$Targets[$kind].Add([System.IO.Path]::GetFileNameWithoutExtension($entry.Name))
            }
        }
    }
}

function Get-CargoClippyManifestInfo {
    param([string]$ExplicitManifestPath)

    $cache = Get-CargoClippyCompletionCache

    $manifestPath = $null
    if (-not [string]::IsNullOrWhiteSpace($ExplicitManifestPath)) {
        # cargo runs in the session's FileSystem location even when the current location is
        # another provider (HKCU:\ has no rooted ProviderPath to resolve against).
        $candidate = [System.IO.Path]::GetFullPath($ExplicitManifestPath, (Get-Location -PSProvider FileSystem).ProviderPath)
        if ([System.IO.File]::Exists($candidate)) {
            $manifestPath = $candidate
        }
    } else {
        $directory = $PWD.ProviderPath
        while (-not [string]::IsNullOrWhiteSpace($directory)) {
            $candidate = Join-Path -Path $directory -ChildPath 'Cargo.toml'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $manifestPath = $candidate
                break
            }

            $directory = Split-Path -Path $directory -Parent
        }
    }

    # Auto-discovered targets come from the directory tree, so a short TTL picks up new files.
    if ($cache.ManifestLoadedFor -eq $manifestPath -and $null -ne $cache.ManifestFacts -and
        $null -ne $cache.ManifestLoadedAt -and ([DateTime]::UtcNow - $cache.ManifestLoadedAt).TotalSeconds -lt 10) {
        return $cache.ManifestFacts
    }

    $profiles = New-Object System.Collections.Generic.List[string]
    foreach ($builtIn in @('dev', 'release', 'test', 'bench')) {
        [void]$profiles.Add($builtIn)
    }

    $packages = New-Object System.Collections.Generic.List[string]
    $targets = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($kind in @('bin', 'example', 'test', 'bench')) {
        $targets[$kind] = New-Object System.Collections.Generic.List[string]
    }

    $manifest = Read-CargoClippyManifestFile -Path $manifestPath
    foreach ($profileName in $manifest.Profiles) {
        [void]$profiles.Add($profileName)
    }

    if ($manifest.PackageName) {
        [void]$packages.Add($manifest.PackageName)
    }

    $workspace = if ($manifestPath) { Find-CargoClippyWorkspaceRoot -Manifest $manifest } else { $null }
    $selected = @()
    if ($null -ne $workspace) {
        if ($workspace.PackageName) {
            [void]$packages.Add($workspace.PackageName)
        }

        $memberManifests = @{}
        foreach ($memberDirectory in Get-CargoClippyWorkspaceMemberDirectory -Workspace $workspace -Patterns $workspace.Members) {
            $member = Read-CargoClippyManifestFile -Path ([System.IO.Path]::Combine($memberDirectory, 'Cargo.toml'))
            $memberManifests[$memberDirectory] = $member
            if ($member.PackageName) {
                [void]$packages.Add($member.PackageName)
            }
        }

        # Target selection follows cargo's default package selection: the package the manifest
        # belongs to, or at the workspace root its default-members (all members when virtual).
        if ($workspace.Path -eq $manifest.Path -and ($null -ne $workspace.DefaultMembers -or -not $workspace.PackageName)) {
            $patterns = if ($null -ne $workspace.DefaultMembers) { $workspace.DefaultMembers } else { $workspace.Members }
            $selected = @(Get-CargoClippyWorkspaceMemberDirectory -Workspace $workspace -Patterns $patterns | ForEach-Object {
                    if ($memberManifests.ContainsKey($_)) { $memberManifests[$_] } else { Read-CargoClippyManifestFile -Path ([System.IO.Path]::Combine($_, 'Cargo.toml')) }
                })
        }
    }

    if ($selected.Count -eq 0 -and $manifest.PackageName) {
        $selected = @($manifest)
    }

    foreach ($package in $selected) {
        Add-CargoClippyPackageTarget -Manifest $package -Targets $targets
    }

    foreach ($kind in @('bin', 'example', 'test', 'bench')) {
        $targets[$kind] = @($targets[$kind] | Sort-Object -Unique -CaseSensitive)
    }

    $facts = [pscustomobject]@{
        Profiles = @($profiles | Sort-Object -Unique -CaseSensitive)
        Features = @($manifest.Features | Sort-Object -Unique -CaseSensitive)
        Packages = @($packages | Sort-Object -Unique -CaseSensitive)
        Targets  = $targets
    }

    $cache.ManifestFacts = $facts
    $cache.ManifestLoadedFor = $manifestPath
    $cache.ManifestLoadedAt = [DateTime]::UtcNow
    $facts
}

function Get-CargoClippyDynamicValueList {
    param(
        [string]$OptionName,
        [bool]$AfterDoubleDash,
        [string]$ManifestPath
    )

    if ($AfterDoubleDash) {
        return @(Get-CargoClippyLintCatalog)
    }

    if ($OptionName -eq '--explain') {
        return @(Get-CargoClippyLintCatalog)
    }

    if ($OptionName -eq '--target') {
        return @(Get-CargoClippyTargetTripleList | ForEach-Object { [pscustomobject]@{ Name = $_; ToolTip = 'Rust target triple.' } })
    }

    $facts = Get-CargoClippyManifestInfo -ExplicitManifestPath $ManifestPath
    $values = switch ($OptionName) {
        '--profile' { @($facts.Profiles); break }
        '--features' { @($facts.Features); break }
        '-F' { @($facts.Features); break }
        '--package' { @($facts.Packages); break }
        '-p' { @($facts.Packages); break }
        '--exclude' { @($facts.Packages); break }
        '--bin' { @($facts.Targets['bin']); break }
        '--example' { @($facts.Targets['example']); break }
        '--test' { @($facts.Targets['test']); break }
        '--bench' { @($facts.Targets['bench']); break }
        default { @() }
    }

    @($values | ForEach-Object { [pscustomobject]@{ Name = $_; ToolTip = "$OptionName value from the local Cargo.toml." } })
}

function Initialize-CargoClippyCompletionCache {
    $cache = Get-CargoClippyCompletionCache
    if ($cache.Initialized) {
        return
    }

    $clippyLines = Invoke-CargoClippyText -Arguments @('--help')
    $checkLines = Invoke-CargoText -Arguments @('check', '--help')

    $descriptions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in (Get-CargoClippyOptionMetadataFromLines -Lines $checkLines).GetEnumerator()) {
        $descriptions[$entry.Key] = $entry.Value
    }
    foreach ($entry in (Get-CargoClippyOptionMetadataFromLines -Lines $clippyLines).GetEnumerator()) {
        # The lint-level flags clippy documents are only accepted after '--'; keeping them out here
        # also stops clippy's '-F / --forbid' text from overwriting cargo's '-F, --features'.
        if ($cache.LintOptions -ccontains $entry.Key) {
            continue
        }

        $descriptions[$entry.Key] = $entry.Value
    }

    $cache.CommandDescriptions = $descriptions
    $cache.CommandOptions = @($descriptions.Keys + '--') | Sort-Object -Unique -CaseSensitive
    $cache.CommandValueMap = Get-CargoClippyCommandValueMap
    $cache.LintDescriptions = @{
        '-W'       = 'Set lint warnings.'
        '--warn'   = 'Set lint warnings.'
        '-A'       = 'Set lint allowed.'
        '--allow'  = 'Set lint allowed.'
        '-D'       = 'Set lint denied.'
        '--deny'   = 'Set lint denied.'
        '-F'       = 'Set lint forbidden.'
        '--forbid' = 'Set lint forbidden.'
    }
    $cache.LintValueMap = Get-CargoClippyLintValueMap
    $cache.Initialized = $true
}

function Get-CargoClippyState {
    param([string[]]$TokensBeforeCurrent)

    Initialize-CargoClippyCompletionCache
    $cache = Get-CargoClippyCompletionCache

    $pendingOption = $null
    $afterDoubleDash = $false
    $manifestPath = $null

    foreach ($token in $TokensBeforeCurrent) {
        $cleanToken = Remove-CargoClippyOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($pendingOption) {
            if ($pendingOption -ceq '-m' -or $pendingOption -eq '--manifest-path') {
                $manifestPath = $cleanToken
            }
            $pendingOption = $null
            continue
        }

        if ($afterDoubleDash) {
            if ($cleanToken -match '^(--[A-Za-z0-9][A-Za-z0-9\-]*)=(.*)$') {
                continue
            }

            if ($cache.LintValueMap.ContainsKey($cleanToken)) {
                $pendingOption = $cleanToken
            }
            continue
        }

        if ($cleanToken -eq '--') {
            $afterDoubleDash = $true
            continue
        }

        if ($cleanToken -match '^(--[A-Za-z0-9][A-Za-z0-9\-]*)=(.*)$') {
            if ($matches[1] -eq '--manifest-path') {
                $manifestPath = Remove-CargoClippyOuterQuotes -Value $matches[2]
            }
            continue
        }

        if ($cache.CommandValueMap.ContainsKey($cleanToken) -or $cache.PathOptions -contains $cleanToken) {
            $pendingOption = $cleanToken
        }
    }

    [pscustomobject]@{
        PendingOption   = $pendingOption
        AfterDoubleDash = $afterDoubleDash
        ManifestPath    = $manifestPath
    }
}

function Get-CargoClippyInlineValueState {
    param(
        [string]$CurrentWord,
        [bool]$AfterDoubleDash
    )

    if ([string]::IsNullOrWhiteSpace($CurrentWord)) {
        return $null
    }

    if ($CurrentWord -match '^(--[A-Za-z0-9][A-Za-z0-9\-]*)=(.*)$') {
        $optionName = $matches[1]
        $currentValue = $matches[2]
        return [pscustomobject]@{
            OptionName   = $optionName
            ValuePrefix  = $currentValue
            PrefixText   = "$optionName="
            AfterDoubleDash = $AfterDoubleDash
        }
    }

    $null
}

function Get-CargoClippyValueCompletions {
    param(
        [string]$OptionName,
        [string]$CurrentWord,
        [bool]$AfterDoubleDash,
        [string]$PrefixText = '',
        [string]$ManifestPath
    )

    Initialize-CargoClippyCompletionCache
    $cache = Get-CargoClippyCompletionCache
    $current = ConvertFrom-CargoClippyTypedWord -Value $CurrentWord

    if ($OptionName -eq '-Z' -and -not $AfterDoubleDash) {
        return @(
            Get-CargoClippyUnstableFlags |
                Where-Object { $_.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase) } |
                ForEach-Object {
                    New-CargoClippyCompletionResult -CompletionText ($PrefixText + $_) -ListItemText $_ -ResultType 'ParameterValue' -ToolTip 'Cargo unstable flag.'
                }
        )
    }

    if (-not $AfterDoubleDash -and $cache.PathOptions -contains $OptionName) {
        return @(
            Get-CargoClippyPathCompletions -InputPath $CurrentWord |
                ForEach-Object {
                    New-CargoClippyCompletionResult -CompletionText ($PrefixText + $_.CompletionText) -ListItemText $_.ListItemText -ResultType $_.ResultType -ToolTip $_.ToolTip
                }
        )
    }

    if ($OptionName -eq '--config' -and -not $AfterDoubleDash) {
        $results = @()
        $results += @(
            Get-CargoClippyPathCompletions -InputPath $CurrentWord |
                ForEach-Object {
                    New-CargoClippyCompletionResult -CompletionText ($PrefixText + $_.CompletionText) -ListItemText $_.ListItemText -ResultType $_.ResultType -ToolTip $_.ToolTip
                }
        )

        foreach ($hint in $cache.CommandValueMap[$OptionName]) {
            if ($hint.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase)) {
                $results += New-CargoClippyCompletionResult -CompletionText ($PrefixText + $hint) -ListItemText $hint -ResultType 'ParameterValue' -ToolTip 'Cargo config override.'
            }
        }

        return @($results)
    }

    $valueMap = if ($AfterDoubleDash) { $cache.LintValueMap } else { $cache.CommandValueMap }
    if (-not $valueMap.ContainsKey($OptionName)) {
        return @()
    }

    $dynamic = @(Get-CargoClippyDynamicValueList -OptionName $OptionName -AfterDoubleDash $AfterDoubleDash -ManifestPath $ManifestPath |
            Where-Object { $_.Name.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($dynamic.Count -gt 0) {
        return @(
            $dynamic | ForEach-Object {
                New-CargoClippyCompletionResult -CompletionText ($PrefixText + $_.Name) -ListItemText $_.Name -ResultType 'ParameterValue' -ToolTip $_.ToolTip
            }
        )
    }

    $literal = @(
        $valueMap[$OptionName] |
            Where-Object { $_.StartsWith($current, [System.StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object {
                $toolTip = if ($AfterDoubleDash) { 'Clippy lint name.' } else { "$OptionName value" }
                New-CargoClippyCompletionResult -CompletionText ($PrefixText + $_) -ListItemText $_ -ResultType 'ParameterValue' -ToolTip $toolTip
            }
    )
    if ($literal.Count -gt 0) {
        return $literal
    }

    # A free-form value slot must keep what the user typed rather than collapse to nothing, which
    # would hand the slot to PowerShell's filename fallback.
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        $toolTip = if ($AfterDoubleDash) { 'Clippy lint name.' } else { "$OptionName value" }
        $echo = ConvertTo-CargoClippyQuotedValue -Value $current -Quote (Get-CargoClippyTypedQuote -Value $CurrentWord)
        return @(New-CargoClippyCompletionResult -CompletionText ($PrefixText + $echo) -ListItemText $current -ResultType 'ParameterValue' -ToolTip $toolTip)
    }

    @()
}

function Get-CargoClippyOptionCompletions {
    param(
        [string[]]$Options,
        [object]$Descriptions,
        [string]$CurrentWord
    )

    $current = Remove-CargoClippyOuterQuotes -Value $CurrentWord

    # -V (--version) and -v (--verbose) are different options, so a single-dash word must be
    # matched ordinally or tab would silently rewrite one into the other.
    $comparison = if ($current -match '^-[^-]') {
        [System.StringComparison]::Ordinal
    } else {
        [System.StringComparison]::OrdinalIgnoreCase
    }

    foreach ($option in $Options | Sort-Object -Unique -CaseSensitive) {
        if ($option.StartsWith($current, $comparison)) {
            $resultType = if ($option -eq '--') { 'ParameterValue' } else { 'ParameterName' }
            $toolTip = if ($Descriptions.ContainsKey($option)) { $Descriptions[$option] } else { 'Pass remaining arguments to Clippy/rustc.' }
            New-CargoClippyCompletionResult -CompletionText $option -ListItemText $option -ResultType $resultType -ToolTip $toolTip
        }
    }
}

function Complete-CargoClippy {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-CargoClippyCompletionCache
    $cache = Get-CargoClippyCompletionCache

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-CargoClippyCurrentWord -CommandAst $commandAst -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $state = Get-CargoClippyState -TokensBeforeCurrent @(Get-CargoClippyArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition)
    $inlineValue = Get-CargoClippyInlineValueState -CurrentWord $currentWord -AfterDoubleDash $state.AfterDoubleDash
    if ($inlineValue) {
        return @(Get-CargoClippyValueCompletions -OptionName $inlineValue.OptionName -CurrentWord $inlineValue.ValuePrefix -AfterDoubleDash $inlineValue.AfterDoubleDash -PrefixText $inlineValue.PrefixText -ManifestPath $state.ManifestPath)
    }

    if ($state.PendingOption) {
        return @(Get-CargoClippyValueCompletions -OptionName $state.PendingOption -CurrentWord $currentWord -AfterDoubleDash $state.AfterDoubleDash -ManifestPath $state.ManifestPath)
    }

    if ($state.AfterDoubleDash) {
        if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('-')) {
            return @(Get-CargoClippyOptionCompletions -Options $cache.LintOptions -Descriptions $cache.LintDescriptions -CurrentWord $currentWord)
        }

        @()
        return
    }

    if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('-')) {
        # clippy switches to 'cargo fix' when --fix appears anywhere before '--'.
        $options = $cache.CommandOptions
        foreach ($element in $commandAst.CommandElements | Select-Object -Skip 1) {
            if ($element.Extent.Text -eq '--') {
                break
            }

            if ($element.Extent.Text -ceq '--fix') {
                $options = @($options) + @(Get-CargoClippyFixOption)
                break
            }
        }

        return @(Get-CargoClippyOptionCompletions -Options $options -Descriptions $cache.CommandDescriptions -CurrentWord $currentWord)
    }

    @()
}

}

Register-ArgumentCompleter -Native -CommandName @('cargo-clippy', 'cargo-clippy.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-CargoClippy -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
