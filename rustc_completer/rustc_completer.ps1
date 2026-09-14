<#
.SYNOPSIS
    Registers a native PowerShell argument completer for rustc.

.DESCRIPTION
    Provides a help-driven native completer for `rustc` and `rustc.exe`.

    The completer keeps its top level compatible with `Import-CompleterScript` by
    limiting top-level content to `Set-StrictMode`, function definitions, and one
    literal `Register-ArgumentCompleter -Native` call.
#>

Set-StrictMode -Version 2.0

function New-RustcCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip = $CompletionText,
        [string]$ListItemText = $CompletionText
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

function Get-RustcTokenState {
    param(
        [string]$Line,
        [int]$CursorPosition
    )

    if ($null -eq $Line) {
        $Line = ''
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    $tokens = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    $quoteChar = [char]0

    foreach ($character in $prefix.ToCharArray()) {
        if (($character -eq [char]34) -or ($character -eq [char]39)) {
            if ($quoteChar -eq [char]0) {
                $quoteChar = $character
            } elseif ($quoteChar -eq $character) {
                $quoteChar = [char]0
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and $quoteChar -eq [char]0) {
            if ($builder.Length -gt 0) {
                [void]$tokens.Add($builder.ToString())
                [void]$builder.Clear()
            }

            continue
        }

        [void]$builder.Append($character)
    }

    $hasTrailingSpace = $prefix -match '\s$'
    if ($builder.Length -gt 0) {
        [void]$tokens.Add($builder.ToString())
    }

    if ($hasTrailingSpace) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens.ToArray())
            CurrentToken        = ''
        }
    }

    if ($tokens.Count -gt 0) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
            CurrentToken        = $tokens[$tokens.Count - 1]
        }
    }

    [pscustomobject]@{
        TokensBeforeCurrent = @()
        CurrentToken        = ''
    }
}

function Remove-RustcOuterQuotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    if ($Value.Length -ge 2) {
        if ($Value.StartsWith('"') -and $Value.EndsWith('"')) {
            return $Value.Substring(1, $Value.Length - 2).Replace('`"', '"')
        }

        if ($Value.StartsWith("'") -and $Value.EndsWith("'")) {
            return $Value.Substring(1, $Value.Length - 2).Replace("''", "'")
        }
    }

    $Value.TrimStart('"', "'")
}

function ConvertTo-RustcQuotedValue {
    param(
        [string]$Value,
        [string]$OriginalToken = ''
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    $needsQuote = $Value -match '\s'
    $preferSingle = $OriginalToken.StartsWith("'")

    if (-not $needsQuote -and -not $OriginalToken.StartsWith('"') -and -not $preferSingle) {
        return $Value
    }

    if ($preferSingle -and -not $Value.Contains("'")) {
        return "'" + $Value + "'"
    }

    '"' + $Value.Replace('`', '``').Replace('"', '`"') + '"'
}

function Split-RustcPathToken {
    param([string]$Value)

    # Split on the last separator instead of Split-Path: Split-Path throws on an
    # empty string, and on a trailing separator it returns the directory itself
    # as the leaf, so a path slot could never descend.
    if ([string]::IsNullOrEmpty($Value)) {
        return [pscustomobject]@{ Prefix = ''; Parent = '.'; Leaf = '' }
    }

    if ($Value -match '^[A-Za-z]:$') {
        return [pscustomobject]@{ Prefix = $Value; Parent = ($Value + [IO.Path]::DirectorySeparatorChar); Leaf = '' }
    }

    $index = $Value.LastIndexOfAny([char[]]@('\', '/'))
    if ($index -lt 0) {
        return [pscustomobject]@{ Prefix = ''; Parent = '.'; Leaf = $Value }
    }

    $prefix = $Value.Substring(0, $index + 1)
    [pscustomobject]@{ Prefix = $prefix; Parent = $prefix; Leaf = $Value.Substring($index + 1) }
}

function Get-RustcPathCompletions {
    param(
        [string]$CurrentToken,
        [bool]$DirectoriesOnly = $false,
        [bool]$FilesOnly = $false,
        [bool]$RustSourceOnly = $false
    )

    $raw = if ($null -eq $CurrentToken) { '' } else { $CurrentToken }
    $clean = Remove-RustcOuterQuotes -Value $raw
    $split = Split-RustcPathToken -Value $clean
    $leaf = $split.Leaf

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    try {
        $items = Get-ChildItem -LiteralPath $split.Parent -Force -ErrorAction Stop
    } catch {
        return @()
    }

    foreach ($item in $items) {
        if ($DirectoriesOnly -and -not $item.PSIsContainer) {
            continue
        }

        if ($FilesOnly -and $item.PSIsContainer) {
            continue
        }

        if ($RustSourceOnly -and -not $item.PSIsContainer -and $item.Extension -ne '.rs') {
            continue
        }

        if ($leaf -and -not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $completionPath = $split.Prefix + $item.Name
        if ($item.PSIsContainer) {
            $completionPath += [IO.Path]::DirectorySeparatorChar
        }

        $quoted = ConvertTo-RustcQuotedValue -Value $completionPath -OriginalToken $raw
        [void]$results.Add((New-RustcCompletionResult -CompletionText $quoted -ResultType 'ParameterValue' -ToolTip $item.FullName -ListItemText $item.Name))
    }

    @($results.ToArray() | Sort-Object ListItemText)
}

function Get-RustcCommandPath {
    if (Test-Path -LiteralPath variable:script:RustcCommandPath) {
        return $script:RustcCommandPath
    }

    $command = Get-Command -Name rustc.exe, rustc -ErrorAction SilentlyContinue | Select-Object -First 1
    $script:RustcCommandPath = if ($command) {
        if ($command.Source) { $command.Source } else { $command.Name }
    } else {
        $null
    }

    $script:RustcCommandPath
}

function Invoke-RustcText {
    param([string[]]$Arguments)

    $commandPath = Get-RustcCommandPath
    if (-not $commandPath) {
        return @()
    }

    try {
        @(& $commandPath @Arguments 2>$null)
    } catch {
        @()
    }
}

function Get-RustcCatalog {
    if (Test-Path -LiteralPath variable:script:RustcCompletionCatalog) {
        return $script:RustcCompletionCatalog
    }

    $switches = @(
        [pscustomobject]@{ Token = '-h'; Aliases = @('-h', '--help'); Description = 'Display this message'; ValueKind = $null }
        [pscustomobject]@{ Token = '--cfg'; Aliases = @('--cfg'); Description = 'Configure the compilation environment.'; ValueKind = 'CfgSpec' }
        [pscustomobject]@{ Token = '--check-cfg'; Aliases = @('--check-cfg'); Description = 'Provide list of expected cfgs for checking.'; ValueKind = 'CheckCfgSpec' }
        [pscustomobject]@{ Token = '-L'; Aliases = @('-L'); Description = 'Add a directory to the library search path.'; ValueKind = 'LibrarySearchPath' }
        [pscustomobject]@{ Token = '-l'; Aliases = @('-l'); Description = 'Link generated crates to the specified native library.'; ValueKind = 'LinkLibrary' }
        [pscustomobject]@{ Token = '--crate-type'; Aliases = @('--crate-type'); Description = 'Specify emitted crate types.'; ValueKind = 'CrateType' }
        [pscustomobject]@{ Token = '--crate-name'; Aliases = @('--crate-name'); Description = 'Specify the crate name.'; ValueKind = 'CrateName' }
        [pscustomobject]@{ Token = '--edition'; Aliases = @('--edition'); Description = 'Specify the Rust edition.'; ValueKind = 'Edition' }
        [pscustomobject]@{ Token = '--emit'; Aliases = @('--emit'); Description = 'Specify emitted output types.'; ValueKind = 'EmitType' }
        [pscustomobject]@{ Token = '--print'; Aliases = @('--print'); Description = 'Print compiler information.'; ValueKind = 'PrintInfo' }
        [pscustomobject]@{ Token = '-g'; Aliases = @('-g'); Description = 'Equivalent to -C debuginfo=2.'; ValueKind = $null }
        [pscustomobject]@{ Token = '-O'; Aliases = @('-O'); Description = 'Equivalent to -C opt-level=3.'; ValueKind = $null }
        [pscustomobject]@{ Token = '-o'; Aliases = @('-o'); Description = 'Write output to file.'; ValueKind = 'OutputFile' }
        [pscustomobject]@{ Token = '--out-dir'; Aliases = @('--out-dir'); Description = 'Write output to directory.'; ValueKind = 'OutputDir' }
        [pscustomobject]@{ Token = '--explain'; Aliases = @('--explain'); Description = 'Explain an error code.'; ValueKind = 'ExplainCode' }
        [pscustomobject]@{ Token = '--test'; Aliases = @('--test'); Description = 'Build a test harness.'; ValueKind = $null }
        [pscustomobject]@{ Token = '--target'; Aliases = @('--target'); Description = 'Compile for a target tuple.'; ValueKind = 'TargetTriple' }
        [pscustomobject]@{ Token = '-A'; Aliases = @('-A', '--allow'); Description = 'Set lint allowed.'; ValueKind = 'LintName' }
        [pscustomobject]@{ Token = '-W'; Aliases = @('-W', '--warn'); Description = 'Set lint warnings.'; ValueKind = 'LintName' }
        [pscustomobject]@{ Token = '--force-warn'; Aliases = @('--force-warn'); Description = 'Set lint force-warn.'; ValueKind = 'LintName' }
        [pscustomobject]@{ Token = '-D'; Aliases = @('-D', '--deny'); Description = 'Set lint denied.'; ValueKind = 'LintName' }
        [pscustomobject]@{ Token = '-F'; Aliases = @('-F', '--forbid'); Description = 'Set lint forbidden.'; ValueKind = 'LintName' }
        [pscustomobject]@{ Token = '--cap-lints'; Aliases = @('--cap-lints'); Description = 'Cap lint level.'; ValueKind = 'LintLevel' }
        [pscustomobject]@{ Token = '-C'; Aliases = @('-C', '--codegen'); Description = 'Set a codegen option.'; ValueKind = 'CodegenOption' }
        [pscustomobject]@{ Token = '-V'; Aliases = @('-V', '--version'); Description = 'Print version info and exit.'; ValueKind = $null }
        [pscustomobject]@{ Token = '-v'; Aliases = @('-v', '--verbose'); Description = 'Use verbose output.'; ValueKind = $null }
        # Documented by `rustc --help -v` only, but accepted on every invocation.
        [pscustomobject]@{ Token = '--extern'; Aliases = @('--extern'); Description = 'Specify where an external rust library is located.'; ValueKind = 'ExternSpec' }
        [pscustomobject]@{ Token = '--sysroot'; Aliases = @('--sysroot'); Description = 'Override the system root.'; ValueKind = 'OutputDir' }
        [pscustomobject]@{ Token = '--error-format'; Aliases = @('--error-format'); Description = 'How errors and other messages are produced.'; ValueKind = 'ErrorFormat' }
        [pscustomobject]@{ Token = '--json'; Aliases = @('--json'); Description = 'Configure the JSON output of the compiler.'; ValueKind = 'JsonConfig' }
        [pscustomobject]@{ Token = '--color'; Aliases = @('--color'); Description = 'Configure coloring of output.'; ValueKind = 'ColorMode' }
        [pscustomobject]@{ Token = '--diagnostic-width'; Aliases = @('--diagnostic-width'); Description = 'Inform rustc of the width of the output.'; ValueKind = 'DiagnosticWidth' }
        [pscustomobject]@{ Token = '--remap-path-prefix'; Aliases = @('--remap-path-prefix'); Description = 'Remap source names in all output.'; ValueKind = 'RemapPathPrefix' }
        [pscustomobject]@{ Token = '--remap-path-scope'; Aliases = @('--remap-path-scope'); Description = 'Which scopes of paths --remap-path-prefix remaps.'; ValueKind = 'RemapPathScope' }
    )

    $aliasLookup = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::Ordinal)
    foreach ($switch in $switches) {
        foreach ($alias in $switch.Aliases) {
            $aliasLookup[$alias] = $switch
        }
    }

    $topHelp = Invoke-RustcText -Arguments @('--help', '-v')
    foreach ($line in $topHelp) {
        if ($line -match '^\s+(-\w(?:,\s+--[A-Za-z0-9\-]+)?|--[A-Za-z0-9\-]+)\b') {
            $tokenGroup = $matches[1]
            foreach ($token in ($tokenGroup -split ',\s*')) {
                $key = $token
                if ($aliasLookup.ContainsKey($key)) {
                    $spec = $aliasLookup[$key]
                    if ($line -match '\s{2,}(.*)$') {
                        $spec.Description = $matches[1].Trim()
                    }
                }
            }
        }
    }

    # `rustc -W help` prints two tables: "Lint checks provided by rustc:" with a
    # default level per lint, and "Lint groups provided by rustc:" with the
    # group's sub-lints. Both are valid -A/-W/-D/-F/--force-warn values.
    $lintNames = New-Object System.Collections.Generic.List[string]
    $lintGroups = New-Object System.Collections.Generic.List[object]
    $inGroups = $false
    foreach ($line in (Invoke-RustcText -Arguments @('-W', 'help'))) {
        if ($line -match '^Lint groups provided by') {
            $inGroups = $true
            continue
        }

        if ($line -match '^[A-Za-z].*:\s*$') {
            $inGroups = $false
            continue
        }

        if ($line -match '^\s{2,}([a-z0-9][a-z0-9\-]*)\s{2,}(allow|warn|deny|forbid)\s{2,}') {
            [void]$lintNames.Add($matches[1])
            continue
        }

        if ($inGroups -and $line -match '^\s{2,}(?<name>[a-z0-9][a-z0-9\-]*)\s{2,}(?<sub>\S.*)$' -and $matches.name -ne 'name') {
            [void]$lintGroups.Add([pscustomobject]@{ Name = $matches.name; SubLints = $matches.sub.Trim() })
        }
    }

    $codegenOptions = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Invoke-RustcText -Arguments @('-C', 'help'))) {
        if ($line -match '^\s+-C\s+([A-Za-z0-9\-]+)=val\b') {
            [void]$codegenOptions.Add($matches[1])
        }
    }

    $targetTriples = Invoke-RustcText -Arguments @('--print', 'target-list')
    $targetCpus = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Invoke-RustcText -Arguments @('--print', 'target-cpus'))) {
        if ($line -match '^\s{4}([A-Za-z0-9_\-+.]+)\b') {
            [void]$targetCpus.Add($matches[1])
        }
    }

    $script:RustcCompletionCatalog = [pscustomobject]@{
        Switches       = $switches
        AliasLookup    = $aliasLookup
        Editions       = @('2015', '2018', '2021', '2024', 'future')
        CrateTypes     = @('bin', 'lib', 'rlib', 'dylib', 'cdylib', 'staticlib', 'proc-macro')
        EmitTypes      = @('asm', 'llvm-bc', 'dep-info', 'link', 'llvm-ir', 'metadata', 'mir', 'obj', 'thin-link-bitcode')
        PrintInfos     = @('all-target-specs-json', 'backend-has-zstd', 'calling-conventions', 'cfg', 'check-cfg', 'code-models', 'crate-name', 'crate-root-lint-levels', 'deployment-target', 'file-names', 'host-tuple', 'link-args', 'native-static-libs', 'relocation-models', 'split-debuginfo', 'stack-protector-strategies', 'supported-crate-types', 'sysroot', 'target-cpus', 'target-features', 'target-libdir', 'target-list', 'target-spec-json', 'target-spec-json-schema', 'tls-models')
        LintLevels     = @('allow', 'warn', 'deny', 'forbid')
        LintNames      = @($lintNames.ToArray() | Sort-Object -Unique)
        LintGroups     = @($lintGroups.ToArray() | Sort-Object -Property Name -Unique)
        CodegenOptions = @($codegenOptions.ToArray() | Sort-Object -Unique)
        TargetTriples  = @($targetTriples | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        TargetCpus     = @($targetCpus.ToArray() | Sort-Object -Unique)
        TargetFeatures = @('help')
        CodeModels     = @('tiny', 'small', 'kernel', 'medium', 'large')
        LtoModes       = @('off', 'thin', 'fat', 'yes', 'no')
        PanicModes     = @('abort', 'unwind')
        StripModes     = @('none', 'debuginfo', 'symbols')
        SplitDebuginfo = @('off', 'packed', 'unpacked')
        SymbolMangling = @('legacy', 'v0', 'hashed')
        OptLevels      = @('0', '1', '2', '3', 's', 'z')
        BoolValues     = @('yes', 'no', 'on', 'off', 'true', 'false')
    }

    $script:RustcCompletionCatalog
}

function Get-RustcValueKindSuggestions {
    param(
        [string]$ValueKind,
        [string]$CurrentToken
    )

    $catalog = Get-RustcCatalog
    $raw = if ($null -eq $CurrentToken) { '' } else { $CurrentToken }
    $clean = Remove-RustcOuterQuotes -Value $raw
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    switch ($ValueKind) {
        'Edition' {
            foreach ($value in $catalog.Editions) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'Rust edition'))
                }
            }
        }
        'CrateType' {
            foreach ($value in $catalog.CrateTypes) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'rustc crate type'))
                }
            }
        }
        'EmitType' {
            foreach ($value in $catalog.EmitTypes) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'rustc emit type'))
                }
            }
            if ($clean -and ($results.Count -eq 0)) {
                [void]$results.Add((New-RustcCompletionResult -CompletionText $clean -ResultType 'ParameterValue' -ToolTip 'Custom --emit value'))
            }
        }
        'PrintInfo' {
            foreach ($value in $catalog.PrintInfos) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'rustc --print topic'))
                }
            }
        }
        'TargetTriple' {
            foreach ($value in $catalog.TargetTriples) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'Rust target triple'))
                }
            }
        }
        'LintName' {
            foreach ($group in $catalog.LintGroups) {
                if ($group.Name.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $group.Name -ResultType 'ParameterValue' -ToolTip "lint group: $($group.SubLints)"))
                }
            }
            foreach ($value in $catalog.LintNames) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'rustc lint name'))
                }
            }
        }
        'ErrorFormat' {
            foreach ($value in @('human', 'json', 'short')) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'rustc --error-format'))
                }
            }
        }
        'ColorMode' {
            foreach ($value in @('auto', 'always', 'never')) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'rustc --color'))
                }
            }
        }
        'RemapPathScope' {
            foreach ($value in @('macro', 'diagnostics', 'debuginfo', 'coverage', 'object', 'all')) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'rustc --remap-path-scope'))
                }
            }
        }
        'JsonConfig' {
            foreach ($value in @('artifacts', 'diagnostic-short', 'diagnostic-rendered-ansi', 'diagnostic-unicode', 'future-incompat')) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'rustc --json config'))
                }
            }
        }
        'DiagnosticWidth' {
            if ([string]::IsNullOrEmpty($clean)) {
                [void]$results.Add((New-RustcCompletionResult -CompletionText '<width>' -ResultType 'ParameterValue' -ToolTip 'Output width in columns'))
            }
        }
        'RemapPathPrefix' {
            if ([string]::IsNullOrEmpty($clean)) {
                [void]$results.Add((New-RustcCompletionResult -CompletionText '<from>=<to>' -ResultType 'ParameterValue' -ToolTip 'rustc --remap-path-prefix'))
            }
        }
        'ExternSpec' {
            if ([string]::IsNullOrEmpty($clean)) {
                [void]$results.Add((New-RustcCompletionResult -CompletionText '<name>=<path>' -ResultType 'ParameterValue' -ToolTip 'rustc --extern NAME[=PATH]'))
            }
        }
        'LintLevel' {
            foreach ($value in $catalog.LintLevels) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'Lint level'))
                }
            }
        }
        'CodegenOption' {
            if ($clean -match '^([^=]+)=(.*)$') {
                $optionName = $matches[1]
                $optionValuePrefix = $matches[2]
                foreach ($value in (Get-RustcCodegenValueSuggestions -OptionName $optionName -ValuePrefix $optionValuePrefix)) {
                    [void]$results.Add($value)
                }
            } else {
                foreach ($value in $catalog.CodegenOptions) {
                    if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                        [void]$results.Add((New-RustcCompletionResult -CompletionText ($value + '=') -ResultType 'ParameterValue' -ToolTip 'rustc -C option'))
                    }
                }
            }
        }
        'LibrarySearchPath' { return Get-RustcPathCompletions -CurrentToken $raw -DirectoriesOnly $true }
        'OutputDir' { return Get-RustcPathCompletions -CurrentToken $raw -DirectoriesOnly $true }
        'OutputFile' { return Get-RustcPathCompletions -CurrentToken $raw }
        'InputFile' { return Get-RustcPathCompletions -CurrentToken $raw -RustSourceOnly $true }
        'ExplainCode' {
            foreach ($value in @('E0001', 'E0308', 'E0425', 'E0599', '<error-code>')) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'rustc --explain code'))
                }
            }
        }
        'CfgSpec' {
            foreach ($value in @('feature="<name>"', 'test', 'debug_assertions', '<name>[="<value>"]')) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'cfg specification'))
                }
            }
        }
        'CheckCfgSpec' {
            foreach ($value in @('cfg(<name>)', 'cfg(<name>, values("<value>"))', '<spec>')) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'check-cfg specification'))
                }
            }
        }
        'LinkLibrary' {
            foreach ($value in @('<name>', 'static=<name>', 'dylib=<name>', 'framework=<name>', 'static:+bundle=<name>')) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'Native library specification'))
                }
            }
        }
        'CrateName' {
            foreach ($value in @('<name>', 'my_crate')) {
                if ($value.StartsWith($clean, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$results.Add((New-RustcCompletionResult -CompletionText $value -ResultType 'ParameterValue' -ToolTip 'Crate name'))
                }
            }
        }
    }

    @($results.ToArray())
}

function Get-RustcCodegenValueSuggestions {
    param(
        [string]$OptionName,
        [string]$ValuePrefix
    )

    $catalog = Get-RustcCatalog
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]
    $name = $OptionName.ToLowerInvariant()

    $values = switch ($name) {
        'opt-level' { $catalog.OptLevels }
        'debug-assertions' { $catalog.BoolValues }
        'embed-bitcode' { $catalog.BoolValues }
        'force-frame-pointers' { $catalog.BoolValues }
        'force-unwind-tables' { $catalog.BoolValues }
        'link-dead-code' { $catalog.BoolValues }
        'prefer-dynamic' { $catalog.BoolValues }
        'rpath' { $catalog.BoolValues }
        'save-temps' { $catalog.BoolValues }
        'target-cpu' { $catalog.TargetCpus }
        'target-feature' { $catalog.TargetFeatures }
        'code-model' { $catalog.CodeModels }
        'lto' { $catalog.LtoModes }
        'panic' { $catalog.PanicModes }
        'strip' { $catalog.StripModes }
        'split-debuginfo' { $catalog.SplitDebuginfo }
        'symbol-mangling-version' { $catalog.SymbolMangling }
        default { @() }
    }

    foreach ($value in $values) {
        if ($value.StartsWith($ValuePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-RustcCompletionResult -CompletionText ($OptionName + '=' + $value) -ResultType 'ParameterValue' -ToolTip "rustc -C $OptionName value"))
        }
    }

    if (($results.Count -eq 0) -and -not [string]::IsNullOrWhiteSpace($OptionName)) {
        [void]$results.Add((New-RustcCompletionResult -CompletionText ($OptionName + '=<value>') -ResultType 'ParameterValue' -ToolTip 'Codegen option value placeholder'))
    }

    @($results.ToArray())
}

function Get-RustcState {
    param([string[]]$TokensBeforeCurrent)

    $catalog = Get-RustcCatalog
    $pendingValueKind = $null
    $operandCount = 0

    foreach ($token in $TokensBeforeCurrent) {
        $clean = Remove-RustcOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($clean)) {
            continue
        }

        if ($pendingValueKind) {
            $pendingValueKind = $null
            continue
        }

        if ($clean -match '^(--[A-Za-z0-9\-]+)=(.*)$') {
            continue
        }

        $lookup = $clean
        if ($catalog.AliasLookup.ContainsKey($lookup)) {
            $spec = $catalog.AliasLookup[$lookup]
            if ($spec.ValueKind) {
                $pendingValueKind = $spec.ValueKind
            }
            continue
        }

        if ($clean.StartsWith('-')) {
            continue
        }

        $operandCount++
    }

    [pscustomobject]@{
        PendingValueKind = $pendingValueKind
        OperandCount     = $operandCount
    }
}

function Get-RustcSwitchSuggestions {
    param([string]$CurrentToken)

    $catalog = Get-RustcCatalog
    $clean = Remove-RustcOuterQuotes -Value $CurrentToken
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    # Ordinal throughout: rustc's short flags are case-distinct in three pairs
    # (-L/-l, -O/-o, -V/-v). A case-insensitive match plus a case-insensitive
    # Sort-Object -Unique keeps only one spelling of each pair.
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($switch in $catalog.Switches) {
        foreach ($alias in $switch.Aliases) {
            if ($alias.StartsWith($clean, [System.StringComparison]::Ordinal) -and $seen.Add($alias)) {
                [void]$results.Add((New-RustcCompletionResult -CompletionText $alias -ResultType 'ParameterName' -ToolTip $switch.Description -ListItemText $alias))
            }
        }
    }

    @($results.ToArray() | Sort-Object -Property CompletionText -CaseSensitive)
}

Register-ArgumentCompleter -Native -CommandName @('rustc', 'rustc.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    # $cursorPosition is an offset into the whole input line, while
    # $commandAst.Extent.Text is command-relative.
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    $tokenState = Get-RustcTokenState -Line $commandAst.Extent.Text -CursorPosition $relativeCursor
    $currentToken = if ($null -eq $tokenState.CurrentToken) { $wordToComplete } else { $tokenState.CurrentToken }
    $tokensBeforeCurrent = @($tokenState.TokensBeforeCurrent)
    if ([string]::IsNullOrEmpty($wordToComplete) -and -not [string]::IsNullOrEmpty($currentToken)) {
        $tokensBeforeCurrent = @($tokensBeforeCurrent + $currentToken)
        $currentToken = ''
    }
    $tokensBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip 1)
    $state = Get-RustcState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.PendingValueKind) {
        return Get-RustcValueKindSuggestions -ValueKind $state.PendingValueKind -CurrentToken $currentToken
    }

    $cleanCurrent = Remove-RustcOuterQuotes -Value $currentToken
    if ($cleanCurrent -match '^(--[A-Za-z0-9\-]+)=(.*)$') {
        $catalog = Get-RustcCatalog
        $optionName = $matches[1]
        $attachedValue = $matches[2]
        if ($catalog.AliasLookup.ContainsKey($optionName)) {
            $spec = $catalog.AliasLookup[$optionName]
            if ($spec.ValueKind) {
                # Keep the "--opt=" prefix on every suggestion so accepting one
                # does not delete the option name.
                return @(
                    Get-RustcValueKindSuggestions -ValueKind $spec.ValueKind -CurrentToken $attachedValue |
                        ForEach-Object {
                            New-RustcCompletionResult -CompletionText ($optionName + '=' + $_.CompletionText) -ResultType $_.ResultType -ToolTip $_.ToolTip -ListItemText $_.ListItemText
                        }
                )
            }
        }

        return @()
    }

    if ($cleanCurrent.StartsWith('-')) {
        return Get-RustcSwitchSuggestions -CurrentToken $currentToken
    }

    if ([string]::IsNullOrEmpty($cleanCurrent)) {
        # The INPUT operand is reachable from a bare TAB: offer the switches and
        # the .rs sources rustc actually compiles.
        return @(
            @(Get-RustcSwitchSuggestions -CurrentToken $currentToken) +
            @(Get-RustcPathCompletions -CurrentToken $currentToken -RustSourceOnly $true)
        )
    }

    Get-RustcPathCompletions -CurrentToken $currentToken -RustSourceOnly $true
}
