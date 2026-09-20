Set-StrictMode -Version 2.0

if ($true) {
function New-FdCompletionResult {
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

function Get-FdCompletionCatalog {
    $existingCatalog = Get-Variable -Name FdCompletionCatalog -Scope Script -ErrorAction Ignore
    if ($null -ne $existingCatalog) {
        return $existingCatalog.Value
    }

    $script:FdCompletionCatalog = @{
        Initialized   = $false
        Seeded        = $false
        CommandName   = $null
        Options       = @()
        OptionByToken = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    }

    $script:FdCompletionCatalog
}

function Resolve-FdCommandName {
    $catalog = Get-FdCompletionCatalog
    if ($catalog.CommandName) {
        return $catalog.CommandName
    }

    $command = Get-Command -Name fd.exe, fd -ErrorAction Ignore | Select-Object -First 1
    if ($command) {
        $catalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $catalog.CommandName
}

function Invoke-FdCapture {
    param([string[]]$Arguments)

    $commandName = Resolve-FdCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>$null | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })
    } catch {
        @()
    }
}

function Get-FdValueKindMap {
    $map = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $entries = @(
        [pscustomobject]@{ Token = '-c'; Kind = 'ColorWhen' }
        [pscustomobject]@{ Token = '--color'; Kind = 'ColorWhen' }
        [pscustomobject]@{ Token = '--hyperlink'; Kind = 'HyperlinkWhen' }
        [pscustomobject]@{ Token = '-t'; Kind = 'FileType' }
        [pscustomobject]@{ Token = '--type'; Kind = 'FileType' }
        [pscustomobject]@{ Token = '-d'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--max-depth'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--min-depth'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--exact-depth'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '-E'; Kind = 'GlobPattern' }
        [pscustomobject]@{ Token = '--exclude'; Kind = 'GlobPattern' }
        [pscustomobject]@{ Token = '-e'; Kind = 'Extension' }
        [pscustomobject]@{ Token = '--extension'; Kind = 'Extension' }
        [pscustomobject]@{ Token = '-S'; Kind = 'Size' }
        [pscustomobject]@{ Token = '--size'; Kind = 'Size' }
        [pscustomobject]@{ Token = '--changed-within'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--change-newer-than'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--newer'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--changed-after'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--changed-before'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--change-older-than'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--older'; Kind = 'DateOrDuration' }
        [pscustomobject]@{ Token = '--format'; Kind = 'Format' }
        [pscustomobject]@{ Token = '-x'; Kind = 'CommandTail' }
        [pscustomobject]@{ Token = '--exec'; Kind = 'CommandTail' }
        [pscustomobject]@{ Token = '-X'; Kind = 'CommandTail' }
        [pscustomobject]@{ Token = '--exec-batch'; Kind = 'CommandTail' }
        [pscustomobject]@{ Token = '--batch-size'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--ignore-file'; Kind = 'Path' }
        [pscustomobject]@{ Token = '--ignore-contain'; Kind = 'Name' }
        [pscustomobject]@{ Token = '-j'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--threads'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '--max-results'; Kind = 'Integer' }
        [pscustomobject]@{ Token = '-C'; Kind = 'Directory' }
        [pscustomobject]@{ Token = '--base-directory'; Kind = 'Directory' }
        [pscustomobject]@{ Token = '--path-separator'; Kind = 'PathSeparator' }
        [pscustomobject]@{ Token = '--search-path'; Kind = 'Directory' }
        [pscustomobject]@{ Token = '--strip-cwd-prefix'; Kind = 'StripMode' }
        [pscustomobject]@{ Token = '--and'; Kind = 'Pattern' }
    )

    foreach ($entry in $entries) {
        $map[$entry.Token] = $entry.Kind
    }

    $map
}

function Get-FdPlaceholderValues {
    # The template placeholders documented under -x/--exec; --format uses the same set (fd
    # prints any other brace token literally).
    @(
        [pscustomobject]@{ Text = '{}'; Tip = 'Path of the search result.' }
        [pscustomobject]@{ Text = '{/}'; Tip = 'Basename of the search result.' }
        [pscustomobject]@{ Text = '{//}'; Tip = 'Parent directory of the search result.' }
        [pscustomobject]@{ Text = '{.}'; Tip = 'Path without the file extension.' }
        [pscustomobject]@{ Text = '{/.}'; Tip = 'Basename without the file extension.' }
        [pscustomobject]@{ Text = '{{'; Tip = 'Literal { (escaping).' }
        [pscustomobject]@{ Text = '}}'; Tip = 'Literal } (escaping).' }
    )
}

function Get-FdStaticOptionSpecs {
    # fd 10.5.0 surface, used as the floor under the help parse and as the only source for the
    # override/alias flags clap does not print (Alias = $true sorts them after canonical names).
    @(
        @{ Tokens = @('-H', '--hidden'); Description = 'Include hidden directories and files in the search results.' }
        @{ Tokens = @('--no-hidden'); Description = 'Override --hidden.'; Alias = $true }
        @{ Tokens = @('-I', '--no-ignore'); Description = 'Show results from files and directories that would otherwise be ignored by .gitignore, .ignore, .fdignore or the global ignore file.' }
        @{ Tokens = @('--ignore'); Description = 'Override --no-ignore.'; Alias = $true }
        @{ Tokens = @('--no-ignore-vcs'); Description = 'Show results that would otherwise be ignored by .gitignore files.' }
        @{ Tokens = @('--ignore-vcs'); Description = 'Override --no-ignore-vcs.'; Alias = $true }
        @{ Tokens = @('--no-require-git'); Description = 'Do not require a git repository to respect gitignores.' }
        @{ Tokens = @('--require-git'); Description = 'Override --no-require-git.'; Alias = $true }
        @{ Tokens = @('--no-ignore-parent'); Description = 'Show results that would otherwise be ignored by ignore files in parent directories.' }
        @{ Tokens = @('--ignore-parent'); Description = 'Override --no-ignore-parent.'; Alias = $true }
        @{ Tokens = @('-u', '--unrestricted'); Description = 'Unrestricted search, including ignored and hidden files (alias for --no-ignore --hidden).' }
        @{ Tokens = @('-s', '--case-sensitive'); Description = 'Case-sensitive search (default: smart case).' }
        @{ Tokens = @('-i', '--ignore-case'); Description = 'Case-insensitive search (default: smart case).' }
        @{ Tokens = @('-g', '--glob'); Description = 'Glob-based search instead of a regular expression search.' }
        @{ Tokens = @('--regex'); Description = 'Regular-expression based search (default); overrides --glob.' }
        @{ Tokens = @('-F', '--fixed-strings'); Description = 'Treat the pattern as a literal string instead of a regular expression.' }
        @{ Tokens = @('--exact'); Description = 'Exact match: like --fixed-strings but the whole filename must match.' }
        @{ Tokens = @('--and'); Description = 'Add additional required search patterns, all of which must be matched.' }
        @{ Tokens = @('-a', '--absolute-path'); Description = 'Show the full path starting from the root.' }
        @{ Tokens = @('--relative-path'); Description = 'Override --absolute-path.'; Alias = $true }
        @{ Tokens = @('-l', '--list-details'); Description = 'Use a detailed listing format like ls -l.' }
        @{ Tokens = @('-L', '--follow'); Description = 'Traverse symbolic links.' }
        @{ Tokens = @('--no-follow'); Description = 'Override --follow.'; Alias = $true }
        @{ Tokens = @('-p', '--full-path'); Description = 'Match the pattern against the full (absolute) path.' }
        @{ Tokens = @('-0', '--print0'); Description = 'Separate search results by the null character.' }
        @{ Tokens = @('-d', '--max-depth'); Description = 'Limit the directory traversal to a given depth.' }
        @{ Tokens = @('--min-depth'); Description = 'Only show search results starting at the given depth.' }
        @{ Tokens = @('--exact-depth'); Description = 'Only show search results at the exact given depth.' }
        @{ Tokens = @('-E', '--exclude'); Description = 'Exclude files/directories that match the given glob pattern.' }
        @{ Tokens = @('--prune'); Description = 'Do not traverse into directories that match the search criteria.' }
        @{ Tokens = @('-t', '--type'); Description = 'Filter the search by type (f/file, d/dir, l/symlink, s/socket, p/pipe, b/block-device, c/char-device, x/executable, e/empty).' }
        @{ Tokens = @('-e', '--extension'); Description = 'Filter results by extension.' }
        @{ Tokens = @('-S', '--size'); Description = 'Limit results based on the size of files (<+-><NUM><UNIT>).' }
        @{ Tokens = @('--changed-within'); Description = 'Filter by modification time: files changed after the given date or within the given duration.' }
        @{ Tokens = @('--change-newer-than'); Description = 'Alias of --changed-within.'; Alias = $true }
        @{ Tokens = @('--newer'); Description = 'Alias of --changed-within.'; Alias = $true }
        @{ Tokens = @('--changed-after'); Description = 'Alias of --changed-within.'; Alias = $true }
        @{ Tokens = @('--changed-before'); Description = 'Filter by modification time: files changed before the given date or duration.' }
        @{ Tokens = @('--change-older-than'); Description = 'Alias of --changed-before.'; Alias = $true }
        @{ Tokens = @('--older'); Description = 'Alias of --changed-before.'; Alias = $true }
        @{ Tokens = @('--format'); Description = 'Print results according to template.' }
        @{ Tokens = @('-x', '--exec'); Description = 'Execute a command for each search result in parallel.' }
        @{ Tokens = @('-X', '--exec-batch'); Description = 'Execute the given command once, with all search results as arguments.' }
        @{ Tokens = @('--batch-size'); Description = 'Maximum number of arguments to pass to the command given with -X.' }
        @{ Tokens = @('--ignore-file'); Description = 'Add a custom ignore-file in .gitignore format.' }
        @{ Tokens = @('-c', '--color'); Description = 'Declare when to use color for the pattern match output (auto, always, never).' }
        @{ Tokens = @('--hyperlink'); Description = 'Add a terminal hyperlink to a file:// url for each path in the output (auto, always, never; no value means always).'; OptionalValue = $true }
        @{ Tokens = @('--ignore-contain'); Description = 'Ignore directories containing the named entry.' }
        @{ Tokens = @('-j', '--threads'); Description = 'Set number of threads to use for searching and executing.' }
        @{ Tokens = @('--max-results'); Description = 'Limit the number of search results and quit immediately.' }
        @{ Tokens = @('-1'); Description = 'Limit the search to a single result and quit immediately.' }
        @{ Tokens = @('-q', '--quiet'); Description = 'Print nothing; exit code 0 if there is at least one match.' }
        @{ Tokens = @('--has-results'); Description = 'Alias of --quiet.'; Alias = $true }
        @{ Tokens = @('--show-errors'); Description = 'Enable the display of filesystem errors.' }
        @{ Tokens = @('-C', '--base-directory'); Description = 'Change the current working directory of fd to the provided path.' }
        @{ Tokens = @('--path-separator'); Description = 'Set the path separator to use when printing file paths.' }
        @{ Tokens = @('--search-path'); Description = 'Provide paths to search as an alternative to the positional <path> argument.' }
        @{ Tokens = @('--strip-cwd-prefix'); Description = 'Control the ./ prefix on relative paths (auto, always, never; no value means always).'; OptionalValue = $true }
        @{ Tokens = @('--one-file-system'); Description = 'Do not descend into a different file system than the one the search started in.' }
        @{ Tokens = @('-h', '--help'); Description = 'Print help.' }
        @{ Tokens = @('-V', '--version'); Description = 'Print version.' }
    )
}

function New-FdOptionSpec {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [bool]$OptionalValue = $false,
        [bool]$Alias = $false
    )

    $valueKindMap = Get-FdValueKindMap
    $valueKind = $null
    foreach ($token in $Tokens) {
        if ($valueKindMap.ContainsKey($token)) {
            $valueKind = $valueKindMap[$token]
            break
        }
    }

    [pscustomobject]@{
        Tokens        = @($Tokens | Select-Object -Unique)
        Description   = $Description
        ValueKind     = $valueKind
        OptionalValue = $OptionalValue
        Alias         = $Alias
    }
}

function Add-FdCatalogSpec {
    param(
        [hashtable]$Catalog,
        [object]$Spec
    )

    # A later spec for the same token (the live help over the static seed) replaces the earlier one.
    $retained = @()
    foreach ($existing in @($Catalog.Options)) {
        $overlaps = $false
        foreach ($token in $Spec.Tokens) {
            if ($token -cin $existing.Tokens) {
                $overlaps = $true
                break
            }
        }

        if ($overlaps) {
            foreach ($token in $existing.Tokens) {
                [void]$Catalog.OptionByToken.Remove($token)
            }
        } else {
            $retained += $existing
        }
    }

    $Catalog.Options = @($retained + $Spec)
    foreach ($token in $Spec.Tokens) {
        $Catalog.OptionByToken[$token] = $Spec
    }
}

function ConvertFrom-FdHelpTokenPart {
    param([string]$TokenPart)

    # '-c, --color <when>' -> -c, --color; '--hyperlink[=<when>]' -> --hyperlink with an optional value.
    $tokens = @()
    $optionalValue = $false
    foreach ($fragment in ($TokenPart -split ',\s*')) {
        $token = $fragment.Trim()
        if ($token -notmatch '^-') {
            continue
        }

        if ($token -match '^(--[A-Za-z0-9-]+)(?:\.\.\.)?(\[=.*\])?(?:[ =<].*)?$') {
            if ($matches[2]) {
                $optionalValue = $true
            }

            $token = $matches[1]
        } elseif ($token -match '^(-[A-Za-z0-9?])(?:[ =<].*)?$') {
            $token = $matches[1]
        } elseif ($token -match '^(-\d)$') {
            $token = $matches[1]
        } else {
            continue
        }

        $tokens += $token
    }

    [pscustomobject]@{ Tokens = $tokens; OptionalValue = $optionalValue }
}

function Add-FdHelpSpec {
    param(
        [hashtable]$Catalog,
        [string]$TokenPart,
        [string[]]$DescriptionLines
    )

    if ([string]::IsNullOrWhiteSpace($TokenPart)) {
        return 0
    }

    $parsed = ConvertFrom-FdHelpTokenPart -TokenPart $TokenPart
    if (@($parsed.Tokens).Count -eq 0) {
        return 0
    }

    $description = (@($DescriptionLines) -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = $TokenPart
    }

    $alias = $false
    foreach ($token in $parsed.Tokens) {
        if ($Catalog.OptionByToken.ContainsKey($token) -and $Catalog.OptionByToken[$token].Alias) {
            $alias = $true
        }
    }

    Add-FdCatalogSpec -Catalog $Catalog -Spec (New-FdOptionSpec -Tokens $parsed.Tokens -Description $description -OptionalValue $parsed.OptionalValue -Alias $alias)
    1
}

function Initialize-FdCompletionCatalog {
    $catalog = Get-FdCompletionCatalog
    if ($catalog.Initialized) {
        return
    }

    if (-not $catalog.Seeded) {
        foreach ($static in Get-FdStaticOptionSpecs) {
            $optionalValue = $static.ContainsKey('OptionalValue') -and $static.OptionalValue
            $alias = $static.ContainsKey('Alias') -and $static.Alias
            Add-FdCatalogSpec -Catalog $catalog -Spec (New-FdOptionSpec -Tokens $static.Tokens -Description $static.Description -OptionalValue $optionalValue -Alias $alias)
        }

        $catalog.Seeded = $true
    }

    $helpLines = Invoke-FdCapture -Arguments @('--help')
    $pendingTokenPart = $null
    $descriptionLines = [System.Collections.Generic.List[string]]::new()
    $inOptions = $false

    foreach ($line in @($helpLines)) {
        if (-not $inOptions) {
            if ($line -eq 'Options:') {
                $inOptions = $true
            }

            continue
        }

        # clap prints option rows at 2 or 6 spaces; the example lines inside descriptions are
        # indented 10 or more, so they never start a spec.
        if ($line -match '^\s{2,7}(?<tokenPart>--?[A-Za-z0-9?].*?)\s*$') {
            $null = Add-FdHelpSpec -Catalog $catalog -TokenPart $pendingTokenPart -DescriptionLines $descriptionLines.ToArray()
            $pendingTokenPart = $matches.tokenPart.Trim()
            $descriptionLines.Clear()
            continue
        }

        if ($null -ne $pendingTokenPart -and $line -match '^\s{10,}(?<description>\S.*)$') {
            $descriptionLines.Add($matches.description.Trim())
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($line) -and $null -ne $pendingTokenPart) {
            $null = Add-FdHelpSpec -Catalog $catalog -TokenPart $pendingTokenPart -DescriptionLines $descriptionLines.ToArray()
            $pendingTokenPart = $null
            $descriptionLines.Clear()
        }
    }

    $null = Add-FdHelpSpec -Catalog $catalog -TokenPart $pendingTokenPart -DescriptionLines $descriptionLines.ToArray()

    $catalog.Initialized = $true
}

function Remove-FdOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-FdQuotedValue {
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

function Test-FdPathLikeInput {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    (Remove-FdOuterQuotes -Value $Value) -match '^(?:\.{1,2}[\\/]|[\\/]|~[\\/]|[A-Za-z]:|\\\\)'
}

function Get-FdCurrentToken {
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

function Get-FdTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-FdArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += Get-FdTokenText -Element $element
        }
    }

    $tokens
}

function Test-FdExecOption {
    param([string]$Token)

    $Token -cin @('-x', '--exec', '-X', '--exec-batch')
}

function Get-FdExecContext {
    param([string[]]$TokensBeforeCurrent)

    # 'Command' when the cursor sits right after -x/-X (the program name), 'Tail' for the
    # command's own arguments up to a '\;' terminator, otherwise $null.
    $context = $null
    foreach ($token in @($TokensBeforeCurrent)) {
        if ($null -eq $context) {
            if (Test-FdExecOption -Token $token) {
                $context = 'Command'
            }

            continue
        }

        if ($token -ceq '\;' -or $token -ceq ';') {
            $context = $null
            continue
        }

        $context = 'Tail'
    }

    $context
}

function Get-FdExpectedValueSpec {
    param([string[]]$TokensBeforeCurrent)

    Initialize-FdCompletionCatalog
    $catalog = Get-FdCompletionCatalog
    if (-not $TokensBeforeCurrent -or $TokensBeforeCurrent.Count -eq 0) {
        return $null
    }

    $lastToken = $TokensBeforeCurrent[-1]
    if ($catalog.OptionByToken.ContainsKey($lastToken)) {
        $spec = $catalog.OptionByToken[$lastToken]
        # An optional value ('--hyperlink[=<when>]') is only accepted attached, so the next token
        # is a positional, not the value.
        if ($spec.ValueKind -and -not $spec.OptionalValue) {
            return $spec
        }
    }

    $null
}

function Get-FdCommandNames {
    $cache = Get-Variable -Name 'FdCommandNameCache' -Scope Script -ErrorAction Ignore
    if ($null -ne $cache -and $null -ne $cache.Value -and $cache.Value.Path -eq $env:PATH) {
        return $cache.Value.Names
    }

    $names = @(
        Get-Command -CommandType Application -ErrorAction Ignore |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
            Where-Object { $_ -and $_ -ne 'fd' } |
            Sort-Object -Unique
    )
    Set-Variable -Name 'FdCommandNameCache' -Value @{ Path = $env:PATH; Names = $names } -Scope Script
    $names
}

function Get-FdPathCompletions {
    param(
        [string]$InputPath,
        [switch]$DirectoriesOnly
    )

    $typedValue = Remove-FdOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

    if ([string]::IsNullOrWhiteSpace($typedValue)) {
        $parent = '.'
        $leaf = ''
    } elseif ($typedValue.EndsWith('\') -or $typedValue.EndsWith('/')) {
        $parent = $typedValue
        $leaf = ''
    } else {
        $candidateParent = Split-Path -Path $typedValue -Parent
        if ([string]::IsNullOrWhiteSpace($candidateParent)) {
            $parent = '.'
            $leaf = $typedValue
        } else {
            $parent = $candidateParent
            $leaf = Split-Path -Path $typedValue -Leaf
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') -and (-not $DirectoriesOnly -or $_.PSIsContainer) } | Sort-Object -Property Name)) {
        $pathText = if ($parent -eq '.') { $item.Name } else { Join-Path -Path $parent -ChildPath $item.Name }
        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        [void]$results.Add((New-FdCompletionResult -CompletionText (ConvertTo-FdQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote) -ToolTip $item.FullName))
    }

    @($results.ToArray())
}

function Get-FdPlaceholderCompletions {
    param([string]$CurrentWord)

    @(
        foreach ($placeholder in Get-FdPlaceholderValues) {
            if ($placeholder.Text -like ([System.Management.Automation.WildcardPattern]::Escape($CurrentWord) + '*')) {
                New-FdCompletionResult -CompletionText $placeholder.Text -ToolTip $placeholder.Tip
            }
        }
    )
}

function Get-FdValueCompletions {
    param(
        [object]$Spec,
        [string]$CurrentWord
    )

    $kind = [string]$Spec.ValueKind
    if ($kind -eq 'Path' -or $kind -eq 'Directory') {
        # -C/--base-directory and --search-path reject a file, --ignore-file takes one.
        $results = @(Get-FdPathCompletions -InputPath $CurrentWord -DirectoriesOnly:($kind -eq 'Directory'))
        if ($results.Count -eq 0) {
            $placeholder = if ($kind -eq 'Directory') { '<dir>' } else { '<path>' }
            return @(New-FdCompletionResult -CompletionText $placeholder -ToolTip 'Filesystem path value.')
        }

        return $results
    }

    if ($kind -eq 'Format' -or $kind -eq 'CommandTail') {
        return Get-FdPlaceholderCompletions -CurrentWord $CurrentWord
    }

    $values = switch ($kind) {
        'ColorWhen' { @{ Values = @('auto', 'always', 'never'); Tip = 'Color output mode.' } }
        'HyperlinkWhen' { @{ Values = @('auto', 'always', 'never'); Tip = 'Hyperlink output mode.' } }
        'StripMode' { @{ Values = @('auto', 'always', 'never'); Tip = 'Strip ./ prefix behavior.' } }
        'PathSeparator' { @{ Values = @('\', '/'); Tip = 'Path separator in printed output.' } }
        'FileType' { @{ Values = @('f', 'file', 'd', 'dir', 'directory', 'l', 'symlink', 's', 'socket', 'p', 'pipe', 'b', 'block-device', 'c', 'char-device', 'x', 'executable', 'e', 'empty'); Tip = 'File type filter.' } }
        'Extension' { @{ Values = @('ps1', 'md', 'json', 'yaml', 'yml', 'txt', 'ts', 'js', 'py', 'rs', 'go', 'zip'); Tip = 'Allowed file extension.' } }
        'Size' { @{ Values = @('+1k', '-10m', '500b', '1mi', '2g'); Tip = 'File size expression.' } }
        'DateOrDuration' { @{ Values = @('1day', '2weeks', '10h', '35min', (Get-Date).ToString('yyyy-MM-dd')); Tip = 'Date or duration filter.' } }
        'Integer' { @{ Values = @('1', '2', '4', '8', '16'); Tip = 'Integer value.' } }
        'GlobPattern' { @{ Values = @('*.log', '*.tmp', 'node_modules', 'bin'); Tip = 'Glob pattern.' } }
        'Pattern' { @{ Values = @('<pattern>'); Tip = 'Additional required search pattern.' } }
        'Name' { @{ Values = @('.git', 'node_modules', '.venv'); Tip = 'Directory marker name.' } }
        default { $null }
    }

    if ($null -eq $values) {
        return @()
    }

    @(
        foreach ($value in $values.Values) {
            if ($value -like ([System.Management.Automation.WildcardPattern]::Escape($CurrentWord) + '*')) {
                New-FdCompletionResult -CompletionText $value -ToolTip $values.Tip
            }
        }
    )
}

function Get-FdOptionCompletions {
    param([string]$CurrentWord)

    Initialize-FdCompletionCatalog
    $catalog = Get-FdCompletionCatalog
    # Each token once, canonical names before the override/alias flags.
    $tokens = @($catalog.OptionByToken.Keys | Sort-Object -Property @{ Expression = { $catalog.OptionByToken[$_].Alias } }, @{ Expression = { $_ } })
    foreach ($token in $tokens) {
        if ($token -like ([System.Management.Automation.WildcardPattern]::Escape($CurrentWord) + '*')) {
            New-FdCompletionResult -CompletionText $token -ResultType 'ParameterName' -ToolTip $catalog.OptionByToken[$token].Description
        }
    }
}

function Get-FdPositionalCount {
    param([string[]]$TokensBeforeCurrent)

    Initialize-FdCompletionCatalog
    $catalog = Get-FdCompletionCatalog
    $count = 0
    $skipNext = $false

    foreach ($token in @($TokensBeforeCurrent)) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }

        # Everything after -x/-X belongs to the command, not to fd's positionals.
        if (Test-FdExecOption -Token $token) {
            break
        }

        if ($catalog.OptionByToken.ContainsKey($token)) {
            $spec = $catalog.OptionByToken[$token]
            if ($spec.ValueKind -and -not $spec.OptionalValue) {
                $skipNext = $true
            }
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($token) -and -not $token.StartsWith('-')) {
            $count++
        }
    }

    $count
}

function Complete-Fd {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    Initialize-FdCompletionCatalog
    $catalog = Get-FdCompletionCatalog

    $currentWord = if ($null -eq $WordToComplete) {
        Get-FdCurrentToken -Line $CommandAst.ToString() -CursorPosition $CursorPosition -Fallback $WordToComplete
    } else {
        $WordToComplete
    }

    $tokensBeforeCurrent = @(Get-FdArgumentTokens -CommandAst $CommandAst -CursorPosition $CursorPosition)

    # -x/-X: the next token is a program name, the rest of the line its arguments.
    $execContext = Get-FdExecContext -TokensBeforeCurrent $tokensBeforeCurrent
    if ($execContext -eq 'Command') {
        return @(
            Get-FdPlaceholderCompletions -CurrentWord $currentWord
            foreach ($name in Get-FdCommandNames) {
                if ($name.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-FdCompletionResult -CompletionText $name -ResultType 'Command' -ToolTip 'Command to execute for each search result.'
                }
            }
        )
    }

    if ($execContext -eq 'Tail') {
        return @(
            Get-FdPlaceholderCompletions -CurrentWord $currentWord
            Get-FdPathCompletions -InputPath $currentWord
        )
    }

    # Attached '--opt=value' / '-o=value': serve the option's values with the prefix kept.
    if ($currentWord -match '^(?<option>--?[A-Za-z0-9?][A-Za-z0-9-]*)=(?<value>.*)$') {
        $optionText = $Matches['option']
        $valueText = $Matches['value']
        if ($catalog.OptionByToken.ContainsKey($optionText) -and $catalog.OptionByToken[$optionText].ValueKind) {
            return @(
                foreach ($result in Get-FdValueCompletions -Spec $catalog.OptionByToken[$optionText] -CurrentWord $valueText) {
                    New-FdCompletionResult -CompletionText ($optionText + '=' + $result.CompletionText) -ListItemText $result.ListItemText -ResultType $result.ResultType -ToolTip $result.ToolTip
                }
            )
        }

        return @(Get-FdOptionCompletions -CurrentWord $optionText)
    }

    $expectedValue = Get-FdExpectedValueSpec -TokensBeforeCurrent $tokensBeforeCurrent
    if ($expectedValue) {
        return @(Get-FdValueCompletions -Spec $expectedValue -CurrentWord $currentWord)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-FdOptionCompletions -CurrentWord $currentWord)
    }

    $positionalCount = Get-FdPositionalCount -TokensBeforeCurrent $tokensBeforeCurrent
    if ($positionalCount -ge 1 -or (Test-FdPathLikeInput -Value $currentWord)) {
        $pathResults = @(Get-FdPathCompletions -InputPath $currentWord)
        if ($pathResults.Count -gt 0) {
            return $pathResults
        }
    }

    if ($positionalCount -eq 0) {
        $results = New-Object System.Collections.Generic.List[object]
        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            [void]$results.Add((New-FdCompletionResult -CompletionText '<pattern>' -ToolTip 'Search pattern (regex by default, glob with --glob).'))
        }

        foreach ($item in @(Get-FdOptionCompletions -CurrentWord $currentWord)) {
            [void]$results.Add($item)
        }

        return @($results.ToArray())
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-FdOptionCompletions -CurrentWord $currentWord)
    }

    @()
}
}

Register-ArgumentCompleter -Native -CommandName @('fd', 'fd.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Fd -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
