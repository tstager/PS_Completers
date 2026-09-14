<#
.SYNOPSIS
Registers PowerShell tab completion for the local `pnpm` CLI.

.DESCRIPTION
Help-driven completer for pnpm 12, whose CLI is built on clap and prints a
long-form help page for every command and subcommand.

`pnpm --help` supplies the root command list (with aliases) and the universal
rc-options; `pnpm help <command> [<subcommand> ...]` supplies the same shape for
every deeper node. Each parsed page is cached in script scope for the session,
including the negative result, so a missing or failing pnpm costs one probe.

Option values are completed from the help page itself: clap's
`[possible values: ...]` lists and `Possible values:` blocks become enum
completions, `<DIR>` slots become directory completions, and everything else
becomes a `<PLACEHOLDER>` so the engine's filename fallback does not take over a
non-path slot. Both the separate (`--reporter silent`) and the attached
(`--reporter=silent`) forms are handled.

This script registers completion for `pnpm`, `pnpm.cmd`, `pnpm.ps1`, and the
`pn` short alias, matching the names pnpm's own completion script registers.
#>

Set-StrictMode -Version Latest

if (-not (Get-Variable -Name PnpmCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:PnpmCompletionCache = @{
        ExecutableProbed = $false
        ExecutablePath   = $null
        Catalogs         = @{}
    }
}

function Get-PnpmCompletionCache {
    $script:PnpmCompletionCache
}

function Get-PnpmExecutablePath {
    $cache = Get-PnpmCompletionCache
    if ($cache.ExecutableProbed) {
        return $cache.ExecutablePath
    }

    $cache.ExecutableProbed = $true
    $cache.ExecutablePath = $null

    foreach ($candidate in @(
            @{ Name = 'pnpm.cmd'; CommandType = 'Application' }
            @{ Name = 'pnpm'; CommandType = 'Application' }
            @{ Name = 'pnpm.ps1'; CommandType = 'ExternalScript' }
        )) {
        $command = @(Get-Command -Name $candidate.Name -CommandType $candidate.CommandType -ErrorAction SilentlyContinue) |
            Select-Object -First 1

        if ($null -eq $command) {
            continue
        }

        $cache.ExecutablePath = if ($command.Source) { $command.Source } else { $command.Path }
        break
    }

    $cache.ExecutablePath
}

function Get-PnpmHelpText {
    param([string[]]$CommandPath)

    $executablePath = Get-PnpmExecutablePath
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        return ''
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    [void]$arguments.Add('help')
    foreach ($segment in @($CommandPath)) {
        if (-not [string]::IsNullOrWhiteSpace($segment)) {
            [void]$arguments.Add($segment)
        }
    }

    try {
        $helpText = $null | & $executablePath @arguments 2>$null | Out-String
    } catch {
        return ''
    }

    if ([string]::IsNullOrWhiteSpace($helpText)) {
        return ''
    }

    $helpText
}

function New-PnpmCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ListItemText,
        [System.Management.Automation.CompletionResultType]$ResultType,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($CompletionText)) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $ListItemText
    }

    [System.Management.Automation.CompletionResult]::new($CompletionText, $ListItemText, $ResultType, $ToolTip)
}

function Get-PnpmValueKind {
    param([string]$ValueName)

    if ([string]::IsNullOrWhiteSpace($ValueName)) {
        return 'None'
    }

    if ($ValueName -match '(?i)(^|_)dir$') {
        return 'Directory'
    }

    if ($ValueName -match '(?i)(^|_)(file|path)$') {
        return 'File'
    }

    'Text'
}

function ConvertFrom-PnpmHelpText {
    param([string]$HelpText)

    $commands = New-Object System.Collections.Generic.List[object]
    $options = New-Object System.Collections.Generic.List[object]
    $commandSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

    if ([string]::IsNullOrWhiteSpace($HelpText)) {
        return [pscustomobject]@{ Commands = @(); Options = @() }
    }

    $section = ''
    $current = $null
    $inPossibleValuesBlock = $false

    foreach ($line in [regex]::Split($HelpText, '\r?\n')) {
        if ($line -match '^(?<name>[A-Za-z][A-Za-z ]*):\s*$') {
            $section = $Matches.name
            $current = $null
            $inPossibleValuesBlock = $false
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $indent = $line.Length - $line.TrimStart(' ').Length
        $trimmed = $line.Trim()

        if ($section -eq 'Commands') {
            # Command rows are indented two spaces: "  add   Add a package [alias: a]".
            if ($indent -le 6 -and $line -match '^\s{2,}(?<name>[A-Za-z0-9][A-Za-z0-9_.-]*)(?:\s{2,}(?<description>\S.*))?$') {
                $name = $Matches.name
                $description = if ($Matches.ContainsKey('description')) { $Matches.description } else { '' }

                $aliases = New-Object System.Collections.Generic.List[string]
                if ($description -match '\[alias(?:es)?:\s*(?<list>[^\]]+)\]') {
                    foreach ($alias in ($Matches.list -split ',')) {
                        $aliasName = $alias.Trim()
                        if (-not [string]::IsNullOrWhiteSpace($aliasName)) {
                            [void]$aliases.Add($aliasName)
                        }
                    }
                }

                foreach ($spelling in @(@($name) + $aliases.ToArray())) {
                    if ($commandSeen.Add($spelling)) {
                        [void]$commands.Add([pscustomobject]@{
                                Name          = $spelling
                                CanonicalName = $name
                                Description   = $description
                            })
                    }
                }
            }

            continue
        }

        if ($section -ne 'Options') {
            continue
        }

        # Option definition rows are indented at most six spaces and start with a dash;
        # descriptions and clap metadata are indented ten or more.
        if ($indent -le 6 -and $trimmed.StartsWith('-')) {
            $spellings = @(
                [regex]::Matches($trimmed, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)') |
                    ForEach-Object { $_.Value }
            )

            if ($spellings.Count -eq 0) {
                $current = $null
                $inPossibleValuesBlock = $false
                continue
            }

            $valueName = ''
            if ($trimmed -match '<(?<value>[^>]+)>') {
                $valueName = $Matches.value
            }

            $current = [pscustomobject]@{
                Names        = [string[]]$spellings
                ValueName    = $valueName
                ValueKind    = (Get-PnpmValueKind -ValueName $valueName)
                AttachedOnly = ($trimmed -match '\[=<')
                ValueList    = (New-Object System.Collections.Generic.List[object])
                Description  = ''
            }

            [void]$options.Add($current)
            $inPossibleValuesBlock = $false
            continue
        }

        if ($null -eq $current) {
            continue
        }

        if ($inPossibleValuesBlock) {
            if ($trimmed -match '^-\s+(?<name>[^:\s]+):\s*(?<description>.*)$') {
                [void]$current.ValueList.Add([pscustomobject]@{ Name = $Matches.name; Description = $Matches.description.Trim() })
                continue
            }

            $inPossibleValuesBlock = $false
        }

        if ($trimmed -match '^Possible values:$') {
            $inPossibleValuesBlock = $true
            continue
        }

        if ($trimmed -match '^\[possible values:\s*(?<list>[^\]]+)\]$') {
            foreach ($value in ($Matches.list -split ',')) {
                $valueText = $value.Trim()
                if (-not [string]::IsNullOrWhiteSpace($valueText)) {
                    [void]$current.ValueList.Add([pscustomobject]@{ Name = $valueText; Description = '' })
                }
            }

            continue
        }

        if ($trimmed -match '^\[alias(?:es)?:\s*(?<list>[^\]]+)\]$') {
            $extra = New-Object System.Collections.Generic.List[string]
            $extra.AddRange([string[]]$current.Names)
            foreach ($alias in ($Matches.list -split ',')) {
                $aliasName = $alias.Trim()
                if ($aliasName -match '^--?[A-Za-z0-9]') {
                    [void]$extra.Add($aliasName)
                }
            }

            $current.Names = [string[]]$extra.ToArray()
            continue
        }

        if ($trimmed.StartsWith('[')) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($current.Description)) {
            $current.Description = $trimmed
        }
    }

    [pscustomobject]@{
        Commands = @($commands.ToArray())
        Options  = @($options.ToArray())
    }
}

function Get-PnpmCatalog {
    param([string[]]$CommandPath)

    $cache = Get-PnpmCompletionCache
    $segments = @(@($CommandPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $key = if ($segments.Count -gt 0) { $segments -join ' ' } else { '<root>' }

    if ($cache.Catalogs.ContainsKey($key)) {
        return $cache.Catalogs[$key]
    }

    $catalog = ConvertFrom-PnpmHelpText -HelpText (Get-PnpmHelpText -CommandPath $segments)
    $cache.Catalogs[$key] = $catalog
    $catalog
}

function Find-PnpmOption {
    param(
        [object]$Catalog,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    foreach ($option in @($Catalog.Options)) {
        foreach ($spelling in $option.Names) {
            if ([string]::Equals($spelling, $Name, [System.StringComparison]::Ordinal)) {
                return $option
            }
        }
    }

    $null
}

function Test-PnpmOptionTakesValue {
    param([object]$Option)

    $null -ne $Option -and -not [string]::IsNullOrWhiteSpace($Option.ValueName) -and -not $Option.AttachedOnly
}

function Get-PnpmArgumentToken {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = New-Object System.Collections.Generic.List[string]
    if ($null -eq $CommandAst) {
        return @()
    }

    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($null -eq $element -or $null -eq $element.Extent) {
            continue
        }

        # Offsets from the AST and $cursorPosition are both absolute in the input
        # line. A token that ends at or after the cursor is the word being
        # completed, not a settled argument.
        if ($element.Extent.EndOffset -ge $CursorPosition) {
            continue
        }

        $text = $element.Extent.Text
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            [void]$tokens.Add($text.Trim())
        }
    }

    @($tokens.ToArray())
}

function Resolve-PnpmCommandPath {
    param([string[]]$Tokens)

    $path = New-Object System.Collections.Generic.List[string]
    $catalog = Get-PnpmCatalog -CommandPath @()
    $skipNext = $false

    foreach ($token in @($Tokens)) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }

        if ($token.StartsWith('-')) {
            if ($token.Contains('=')) {
                continue
            }

            $option = Find-PnpmOption -Catalog $catalog -Name $token
            if (Test-PnpmOptionTakesValue -Option $option) {
                $skipNext = $true
            }

            continue
        }

        $match = $null
        foreach ($command in @($catalog.Commands)) {
            if ([string]::Equals($command.Name, $token, [System.StringComparison]::Ordinal)) {
                $match = $command
                break
            }
        }

        if ($null -eq $match) {
            break
        }

        [void]$path.Add($match.CanonicalName)
        $catalog = Get-PnpmCatalog -CommandPath @($path.ToArray())
    }

    [pscustomobject]@{
        Path    = @($path.ToArray())
        Catalog = $catalog
    }
}

function Get-PnpmDirectoryCompletion {
    param([string]$WordToComplete)

    @([System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete)) |
        Where-Object { $_.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer }
}

function Get-PnpmOptionValueCompletion {
    param(
        [object]$Option,
        [string]$WordToComplete,
        [string]$Prefix
    )

    $results = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Option) {
        return @()
    }

    # .ToArray() is deliberate: @() over a List[object] throws on PowerShell 7.6.
    $values = @($Option.ValueList.ToArray())
    if ($values.Count -gt 0) {
        foreach ($value in $values) {
            if ($value.Name.StartsWith($WordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                $toolTip = if ([string]::IsNullOrWhiteSpace($value.Description)) { "$($Option.Names[-1]) $($value.Name)" } else { $value.Description }
                [void]$results.Add((New-PnpmCompletionResult -CompletionText ($Prefix + $value.Name) -ListItemText $value.Name -ResultType ParameterValue -ToolTip $toolTip))
            }
        }

        return @($results.ToArray())
    }

    if ($Option.ValueKind -eq 'Directory' -and [string]::IsNullOrEmpty($Prefix)) {
        return @(Get-PnpmDirectoryCompletion -WordToComplete $WordToComplete)
    }

    if ($Option.ValueKind -eq 'File' -and [string]::IsNullOrEmpty($Prefix)) {
        return @([System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete))
    }

    if ([string]::IsNullOrEmpty($WordToComplete)) {
        $placeholder = "<$($Option.ValueName)>"
        [void]$results.Add((New-PnpmCompletionResult -CompletionText ($Prefix + $placeholder) -ListItemText $placeholder -ResultType ParameterValue -ToolTip $Option.Description))
    }

    @($results.ToArray())
}

function Get-PnpmOptionNameCompletion {
    param(
        [object]$Catalog,
        [string]$WordToComplete
    )

    $results = New-Object System.Collections.Generic.List[object]
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*'

    foreach ($option in @($Catalog.Options)) {
        foreach ($spelling in $option.Names) {
            if ($spelling -clike $pattern) {
                $toolTip = if ([string]::IsNullOrWhiteSpace($option.Description)) { $spelling } else { $option.Description }
                if (-not [string]::IsNullOrWhiteSpace($option.ValueName)) {
                    $toolTip = "$toolTip [<$($option.ValueName)>]"
                }

                [void]$results.Add((New-PnpmCompletionResult -CompletionText $spelling -ListItemText $spelling -ResultType ParameterName -ToolTip $toolTip))
            }
        }
    }

    @($results.ToArray())
}

function Get-PnpmCommandCompletion {
    param(
        [object]$Catalog,
        [string[]]$Path,
        [string]$WordToComplete
    )

    $results = New-Object System.Collections.Generic.List[object]
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*'
    $prefix = @(@('pnpm') + @($Path)) -join ' '

    foreach ($command in @($Catalog.Commands)) {
        if ($command.Name -like $pattern) {
            $toolTip = if ([string]::IsNullOrWhiteSpace($command.Description)) { "$prefix $($command.Name)" } else { $command.Description }
            [void]$results.Add((New-PnpmCompletionResult -CompletionText $command.Name -ListItemText $command.Name -ResultType ParameterValue -ToolTip $toolTip))
        }
    }

    @($results.ToArray())
}

function Invoke-PnpmCompletion {
    [CmdletBinding()]
    [OutputType([System.Object[]], [System.Array])]
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $word = if ($null -eq $WordToComplete) { '' } else { $WordToComplete }
    $tokens = @(Get-PnpmArgumentToken -CommandAst $CommandAst -CursorPosition $CursorPosition)
    $resolved = Resolve-PnpmCommandPath -Tokens $tokens
    $catalog = $resolved.Catalog

    # Attached form: --reporter=sil
    if ($word -match '^(?<name>--?[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = Find-PnpmOption -Catalog $catalog -Name $Matches.name
        if ($null -ne $option -and -not [string]::IsNullOrWhiteSpace($option.ValueName)) {
            return @(Get-PnpmOptionValueCompletion -Option $option -WordToComplete $Matches.value -Prefix "$($Matches.name)=")
        }

        return @()
    }

    if ($word.StartsWith('-')) {
        return @(Get-PnpmOptionNameCompletion -Catalog $catalog -WordToComplete $word)
    }

    # Separate form: the settled token before the cursor is a value-bearing option.
    $previous = if ($tokens.Count -gt 0) { $tokens[-1] } else { '' }
    if ($previous.StartsWith('-') -and -not $previous.Contains('=')) {
        $option = Find-PnpmOption -Catalog $catalog -Name $previous
        if (Test-PnpmOptionTakesValue -Option $option) {
            return @(Get-PnpmOptionValueCompletion -Option $option -WordToComplete $word -Prefix '')
        }
    }

    # A pnpm node either dispatches to subcommands or takes operands. When it takes
    # operands, return nothing so the engine's own path completion runs.
    @(Get-PnpmCommandCompletion -Catalog $catalog -Path $resolved.Path -WordToComplete $word)
}

Register-ArgumentCompleter -Native -CommandName @('pnpm', 'pnpm.cmd', 'pnpm.ps1', 'pn') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-PnpmCompletion -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
