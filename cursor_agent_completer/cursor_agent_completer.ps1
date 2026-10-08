<#
.SYNOPSIS
Registers a native PowerShell argument completer for the Cursor Agent CLI.

.DESCRIPTION
Provides standalone completion for `cursor-agent`, `cursor-agent.cmd`, and
`cursor-agent.ps1` using live help output from the installed CLI.
#>

Set-StrictMode -Version 2.0

function New-CursorAgentCompletionResult {
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

function Get-CursorAgentCommandPath {
    foreach ($candidate in @('cursor-agent.cmd', 'cursor-agent.ps1', 'cursor-agent')) {
        $command = Get-Command -Name $candidate -CommandType Application, ExternalScript -ErrorAction Ignore |
            Select-Object -First 1

        if ($null -ne $command) {
            if ($command.Source) {
                return $command.Source
            }

            return $command.Name
        }
    }

    return $null
}

function Get-CursorAgentRootHelpOutput {
    $commandPath = Get-CursorAgentCommandPath
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return ''
    }

    try {
        return ($null | & $commandPath --help 2>&1 | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String)
    } catch {
        return ''
    }
}

function Get-CursorAgentSubcommandHelpOutput {
    param([string[]]$CommandPath)

    $launcherPath = Get-CursorAgentCommandPath
    if ([string]::IsNullOrWhiteSpace($launcherPath) -or @($CommandPath).Count -eq 0) {
        return ''
    }

    try {
        return ($null | & $launcherPath @CommandPath --help 2>&1 | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' } | Out-String)
    } catch {
        return ''
    }
}

function ConvertFrom-CursorAgentHelpText {
    param([string]$HelpText)

    $lines = @([regex]::Split($HelpText, '\r?\n'))
    $options = New-Object System.Collections.Generic.List[object]
    $subcommands = New-Object System.Collections.Generic.List[string]
    $inOptions = $false
    $inCommands = $false

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $trimmed = $line.Trim()

        if ($trimmed -eq 'Options:') {
            $inOptions = $true
            $inCommands = $false
            continue
        }

        if ($trimmed -eq 'Commands:') {
            $inOptions = $false
            $inCommands = $true
            continue
        }

        if ($trimmed -eq 'Arguments:') {
            $inOptions = $false
            $inCommands = $false
            continue
        }

        if ($inOptions) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                $inOptions = $false
                continue
            }

            $contentLine = $line.TrimStart()
            $parts = [regex]::Split($contentLine, '\s{2,}', 2)
            if ($parts.Count -lt 2) {
                continue
            }

            $namesPart = $parts[0].Trim()
            $description = $parts[1].Trim()
            $optionNames = @([regex]::Matches($namesPart, '(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|$))') |
                ForEach-Object { $_.Value.Trim() })

            if ($optionNames.Count -eq 0) {
                continue
            }

            $takesValue = ($namesPart -match '<[^>]+>') -or ($namesPart -match '\[[^]]*\]')
            [void]$options.Add([pscustomobject]@{
                    Names        = @($optionNames)
                    TakesValue   = [bool]$takesValue
                    Description  = $description
                })

            continue
        }

        if ($inCommands) {
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                $inCommands = $false
                continue
            }

            $contentLine = $line.TrimStart()
            $parts = [regex]::Split($contentLine, '\s{2,}', 2)
            if ($parts.Count -lt 2) {
                continue
            }

            $commandToken = $parts[0].Trim()
            if ([string]::IsNullOrWhiteSpace($commandToken)) {
                continue
            }

            $commandToken = ($commandToken -split '\s', 2)[0]
            $commandToken = ($commandToken -split '<', 2)[0]
            $commandNames = @($commandToken.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            foreach ($commandName in $commandNames) {
                if ($commandName -match '^[A-Za-z0-9][A-Za-z0-9-]*$') {
                    [void]$subcommands.Add($commandName)
                }
            }
        }
    }

    [pscustomobject]@{
        Options     = @($options.ToArray())
        Subcommands = @($subcommands.ToArray() | Sort-Object -Unique)
    }
}

function Get-CursorAgentCompletionCatalog {
    $existing = Get-Variable -Name 'CursorAgentCompletionCatalog' -Scope Script -ErrorAction Ignore
    if ($null -ne $existing -and $null -ne $existing.Value) {
        return $existing.Value
    }

    $catalog = [ordered]@{
        Initialized       = $false
        CommandPath       = $null
        RootHelpText      = ''
        RootOptions       = @()
        RootSubcommands   = @()
        SubcommandCatalogs = @{}
    }

    Set-Variable -Name 'CursorAgentCompletionCatalog' -Value $catalog -Scope Script
    return (Get-Variable -Name 'CursorAgentCompletionCatalog' -Scope Script).Value
}

function Initialize-CursorAgentCompletionCatalog {
    $catalog = Get-CursorAgentCompletionCatalog
    if ($catalog.Initialized) {
        return $catalog
    }

    $catalog.CommandPath = Get-CursorAgentCommandPath
    $catalog.RootHelpText = Get-CursorAgentRootHelpOutput
    $rootHelp = ConvertFrom-CursorAgentHelpText -HelpText $catalog.RootHelpText
    $catalog.RootOptions = @($rootHelp.Options)
    $catalog.RootSubcommands = @($rootHelp.Subcommands)

    $catalog.Initialized = $true
    Set-Variable -Name 'CursorAgentCompletionCatalog' -Value $catalog -Scope Script
    return (Get-Variable -Name 'CursorAgentCompletionCatalog' -Scope Script).Value
}

function Get-CursorAgentNodeCatalog {
    <#
    .SYNOPSIS
    Returns the parsed help (Options + Subcommands) for a validated subcommand
    path, fetching '<path> --help' once per session and caching misses too.
    #>
    param([string[]]$CommandPath)

    $catalog = Initialize-CursorAgentCompletionCatalog
    if (@($CommandPath).Count -eq 0) {
        return [pscustomobject]@{
            Options     = @($catalog.RootOptions)
            Subcommands = @($catalog.RootSubcommands)
        }
    }

    $key = $CommandPath -join ' '
    if (-not $catalog.SubcommandCatalogs.ContainsKey($key)) {
        $helpText = Get-CursorAgentSubcommandHelpOutput -CommandPath $CommandPath
        $catalog.SubcommandCatalogs[$key] = if ([string]::IsNullOrWhiteSpace($helpText)) {
            $null
        } else {
            ConvertFrom-CursorAgentHelpText -HelpText $helpText
        }
    }

    $catalog.SubcommandCatalogs[$key]
}

function Find-CursorAgentOption {
    param(
        $Node,
        [string]$Token
    )

    if ($null -eq $Node) {
        return $null
    }

    foreach ($option in @($Node.Options)) {
        foreach ($name in @($option.Names)) {
            if ([string]::Equals($name, $Token, [System.StringComparison]::Ordinal)) {
                return $option
            }
        }
    }

    $null
}

function Get-CursorAgentCanonicalOptionName {
    param($Option)

    foreach ($name in @($Option.Names)) {
        if ($name.StartsWith('--')) {
            return $name
        }
    }

    @($Option.Names)[0]
}

function Get-CursorAgentValueHints {
    @{
        '--mode' = @('plan', 'ask')
        '--output-format' = @('text', 'json', 'stream-json')
        '--sandbox' = @('enabled', 'disabled')
        '--format' = @('text', 'json')
    }
}

function Get-CursorAgentPathOptions {
    @('--workspace', '--add-dir', '--plugin-dir')
}

function Get-CursorAgentPlaceholderValue {
    param([string]$OptionName)

    switch ($OptionName) {
        '--api-key' { return '<key>' }
        '--endpoint' { return '<url>' }
        '--header' { return '<header>' }
        '--model' { return '<model>' }
        '--resume' { return '<chatId>' }
        '--worktree' { return '<name>' }
        '--worktree-base' { return '<branch>' }
        default { return '<value>' }
    }
}

function ConvertFrom-CursorAgentTypedWord {
    # Splits the text typed so far into its value and the opening quote the
    # user typed ('' when bare), undoing that quote style's escapes.
    param([string]$Text)

    $quote = ''
    if ($Text.StartsWith("'") -or $Text.StartsWith('"')) {
        $quote = $Text.Substring(0, 1)
        $Text = $Text.Substring(1)
        if ($Text.EndsWith($quote)) {
            $Text = $Text.Substring(0, $Text.Length - 1)
        }

        $Text = if ($quote -eq "'") { $Text.Replace("''", "'") } else { $Text -replace '`(.)', '$1' }
    }

    [pscustomobject]@{ Value = $Text; Quote = $quote }
}

function Test-CursorAgentArgumentNeedsQuote {
    # Whitespace and argument-mode metacharacters (including the typographic
    # quotes PowerShell treats as quotes) end or split a bare word; a leading
    # '@' or '#' would start a splat or a comment.
    param([string]$Value)

    return ($Value -match '[\s{}();,|&<>''"`$\u2018-\u201E]' -or $Value -match '^[@#]')
}

function ConvertTo-CursorAgentArgument {
    # Renders a value as one PowerShell argument: bare when safe and no quote
    # was typed, otherwise in the typed quote style (single by default).
    param(
        [string]$Value,
        [string]$Quote
    )

    if (-not $Quote) {
        if (-not (Test-CursorAgentArgumentNeedsQuote -Value $Value)) {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -eq "'") {
        return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
    }

    return '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
}

function Get-CursorAgentPathCompletions {
    param(
        [string]$WordToComplete,
        [string]$CompletionPrefix = '',
        [string]$Quote = ''
    )

    if ([string]::IsNullOrWhiteSpace($WordToComplete) -or $WordToComplete -eq '.') {
        $WordToComplete = ''
    }

    $prefix = $WordToComplete
    if ($prefix.StartsWith('~')) {
        $prefix = $prefix -replace '^~', $HOME
    }

    $basePath = ''
    $leafName = ''
    if ($prefix -match '[\\/]$') {
        $basePath = $prefix
    } elseif ($prefix) {
        $basePath = Split-Path -Path $prefix -Parent
        $leafName = Split-Path -Path $prefix -Leaf
    }

    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = (Get-Location).Path
    }

    if (-not (Test-Path -LiteralPath $basePath)) {
        return @()
    }

    # A typed directory part ('.\', '../', 'C:\dir/') is kept verbatim, with
    # the separator the user typed; '~' is expanded as before.
    $typedDirectory = ''
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $separatorIndex = $WordToComplete.LastIndexOfAny([char[]]'\/')
    if ($separatorIndex -ge 0 -and -not $WordToComplete.StartsWith('~')) {
        $typedDirectory = $WordToComplete.Substring(0, $separatorIndex + 1)
        $separator = $WordToComplete[$separatorIndex]
    }

    $items = @(Get-ChildItem -LiteralPath $basePath -Force -ErrorAction Ignore)
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($item in $items) {
        if (-not [string]::IsNullOrWhiteSpace($leafName) -and $item.Name -notlike "$leafName*") {
            continue
        }

        $displayText = $item.Name
        if ($item.PSIsContainer) {
            $displayText = $displayText + $separator
        }

        $displayPath = $displayText
        if ($typedDirectory) {
            $displayPath = $typedDirectory + $displayText
        } elseif ($WordToComplete.StartsWith('~')) {
            $displayPath = Join-Path -Path $basePath -ChildPath $item.Name
            if ($item.PSIsContainer) {
                $displayPath = $displayPath + [System.IO.Path]::DirectorySeparatorChar
            }
        } elseif (-not $CompletionPrefix -and $displayPath -match '^[-\u2013-\u2015]') {
            # PowerShell reads a bare word starting with a dash as a parameter
            # name; as PowerShell's own path completion does, lead with '.\'.
            $displayPath = '.' + $separator + $displayPath
        }

        # A quoted directory drops its trailing separator, as PowerShell's own
        # path completion does: '...\' would end in an escaped quote once the
        # cmd launcher re-quotes it for the CLI.
        $completionText = $CompletionPrefix + $displayPath
        if ($Quote -or (Test-CursorAgentArgumentNeedsQuote -Value $completionText)) {
            $completionText = ConvertTo-CursorAgentArgument -Value ($CompletionPrefix + $displayPath.TrimEnd('\', '/')) -Quote $Quote
        }

        [void]$results.Add((New-CursorAgentCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $item.FullName -ListItemText $displayText))
    }

    return @($results.ToArray())
}

function Get-CursorAgentOptionValueCompletion {
    param(
        $Option,
        [string]$WordToComplete,
        [string]$CompletionPrefix = '',
        [string]$Quote = ''
    )

    $results = New-Object System.Collections.Generic.List[object]
    $canonicalName = Get-CursorAgentCanonicalOptionName -Option $Option
    $valueHints = Get-CursorAgentValueHints

    if ($valueHints.ContainsKey($canonicalName)) {
        foreach ($hint in @($valueHints[$canonicalName])) {
            if ([string]::IsNullOrWhiteSpace($WordToComplete) -or $hint -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
                [void]$results.Add((New-CursorAgentCompletionResult -CompletionText (ConvertTo-CursorAgentArgument -Value ($CompletionPrefix + $hint) -Quote $Quote) -ResultType 'ParameterValue' -ToolTip $Option.Description -ListItemText $hint))
            }
        }

        return @($results.ToArray())
    }

    if ($canonicalName -in (Get-CursorAgentPathOptions)) {
        return @(Get-CursorAgentPathCompletions -WordToComplete $WordToComplete -CompletionPrefix $CompletionPrefix -Quote $Quote)
    }

    $placeholder = Get-CursorAgentPlaceholderValue -OptionName $canonicalName
    if ([string]::IsNullOrWhiteSpace($WordToComplete) -or $placeholder -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
        [void]$results.Add((New-CursorAgentCompletionResult -CompletionText ($CompletionPrefix + $placeholder) -ResultType 'ParameterValue' -ToolTip $Option.Description -ListItemText $placeholder))
    }

    return @($results.ToArray())
}

function Complete-CursorAgent {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $null = Initialize-CursorAgentCompletionCatalog
    $results = New-Object System.Collections.Generic.List[object]

    # Committed tokens are the elements that end before the cursor; the word
    # under the cursor is read from its extent so a typed opening quote is
    # kept ($wordToComplete drops it for '--opt="value').
    $tokens = @()
    $typedText = ''
    if ($null -ne $commandAst) {
        foreach ($element in @($commandAst.CommandElements | Select-Object -Skip 1)) {
            $extent = $element.Extent
            if ($extent.EndOffset -lt $cursorPosition) {
                $tokens = @($tokens + $extent.Text)
            } elseif ($extent.StartOffset -lt $cursorPosition) {
                $typedText = $extent.Text.Substring(0, $cursorPosition - $extent.StartOffset)
            }
        }
    }

    $typedWord = ConvertFrom-CursorAgentTypedWord -Text $typedText
    $prefix = $typedWord.Value

    # Walk the committed tokens to the deepest validated subcommand node. Each
    # node's options and subcommands come from its own '--help' (commander does
    # not inherit root options into subcommands).
    $commandPath = @()
    $node = Get-CursorAgentNodeCatalog -CommandPath @()
    $index = 0
    while ($index -lt $tokens.Count) {
        $token = $tokens[$index]
        $index++

        # Commander treats everything after '--' as positional arguments.
        if ($token -eq '--') {
            return @()
        }

        if ($token.StartsWith('-')) {
            $option = Find-CursorAgentOption -Node $node -Token $token
            if ($option -and $option.TakesValue -and -not $token.Contains('=') -and
                $index -lt $tokens.Count -and -not $tokens[$index].StartsWith('-')) {
                $index++
            }

            continue
        }

        if ($null -ne $node -and (@($node.Subcommands) -ccontains $token)) {
            $commandPath = @($commandPath + $token)
            $node = Get-CursorAgentNodeCatalog -CommandPath $commandPath
        }
    }

    if ($null -eq $node) {
        $node = [pscustomobject]@{ Options = @(); Subcommands = @() }
    }

    # Attached long form '--opt=value' (commander accepts it; root help cites
    # '--mode=plan'): complete the value and keep '--opt=' in CompletionText.
    # A quote typed before the option or before the value quotes the whole
    # token, so PowerShell still passes it as one argument.
    if ($prefix -match '^(--[^=]+)=(.*)$') {
        $attachedName = $Matches[1]
        $attachedValue = [pscustomobject]@{ Value = $Matches[2]; Quote = $typedWord.Quote }
        if (-not $attachedValue.Quote) {
            $attachedValue = ConvertFrom-CursorAgentTypedWord -Text $attachedValue.Value
        }

        $option = Find-CursorAgentOption -Node $node -Token $attachedName
        if ($option -and $option.TakesValue) {
            return @(Get-CursorAgentOptionValueCompletion -Option $option -WordToComplete $attachedValue.Value -CompletionPrefix "$attachedName=" -Quote $attachedValue.Quote)
        }

        return @()
    }

    $previousToken = if ($tokens.Count -gt 0) { $tokens[-1] } else { $null }

    if ($previousToken -and $previousToken.StartsWith('-') -and -not $previousToken.Contains('=')) {
        $option = Find-CursorAgentOption -Node $node -Token $previousToken
        if ($option -and $option.TakesValue) {
            return @(Get-CursorAgentOptionValueCompletion -Option $option -WordToComplete $prefix -Quote $typedWord.Quote)
        }
    }

    foreach ($option in @($node.Options)) {
        foreach ($optionName in @($option.Names)) {
            if ([string]::IsNullOrWhiteSpace($prefix) -or $optionName -like ([System.Management.Automation.WildcardPattern]::Escape($prefix) + '*')) {
                [void]$results.Add((New-CursorAgentCompletionResult -CompletionText $optionName -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $optionName))
            }
        }
    }

    foreach ($subcommand in @($node.Subcommands)) {
        if ([string]::IsNullOrWhiteSpace($prefix) -or $subcommand -like ([System.Management.Automation.WildcardPattern]::Escape($prefix) + '*')) {
            [void]$results.Add((New-CursorAgentCompletionResult -CompletionText $subcommand -ResultType 'ParameterValue' -ToolTip $subcommand -ListItemText $subcommand))
        }
    }

    return @($results.ToArray())
}

Register-ArgumentCompleter -Native -CommandName @('cursor-agent', 'cursor-agent.cmd', 'cursor-agent.ps1') -ScriptBlock {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Complete-CursorAgent -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
