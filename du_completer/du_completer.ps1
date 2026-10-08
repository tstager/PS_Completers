# du tab completion for PowerShell
# Help-refreshed native completer for GNU and uutils coreutils du with option value hints and file operand completion.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name DuCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:DuCompletionCatalog = @{
        Initialized  = $false
        CommandName  = $null
        LevelHints   = @('0', '1', '2', '3', '5', '10')
        Switches     = @()
        SwitchByKey  = @{}
    }
}

function Resolve-DuCommandName {
    if ($script:DuCompletionCatalog.CommandName) {
        return $script:DuCompletionCatalog.CommandName
    }

    $command = Get-Command -Name du.exe, du -ErrorAction Ignore | Select-Object -First 1
    if ($command) {
        $script:DuCompletionCatalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $script:DuCompletionCatalog.CommandName
}

function Invoke-DuHelpText {
    $commandName = Resolve-DuCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @($null | & $commandName --help 2>&1 | ForEach-Object { $_ -replace '\e\[[0-9;?]*[ -/]*[@-~]', '' })
    } catch {
        @()
    }
}

function New-DuCompletionResult {
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

function Remove-DuOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertFrom-DuTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    $tokens[0].Value
}

function ConvertTo-DuQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the quote the user typed (single by default). PowerShell reads ' and
    # U+2018-U+201B as single quotes and " and U+201C-U+201E as double quotes.
    param(
        [string]$Value,
        [string]$QuoteChar = ''
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if (-not $QuoteChar) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Initialize-DuCompletionCatalog {
    if ($script:DuCompletionCatalog.Initialized) {
        return
    }

    $catalog = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    $entries = @(
        @('-0', '--null', 'End each output line with NUL, not newline.', $null),
        @('-a', '--all', 'Write counts for all files, not just directories.', $null),
        @('', '--apparent-size', 'Print apparent sizes rather than disk usage.', $null),
        @('-B', '--block-size', 'Scale sizes by SIZE before printing them.', 'Size'),
        @('-b', '--bytes', 'Equivalent to --apparent-size --block-size=1.', $null),
        @('-c', '--total', 'Produce a grand total.', $null),
        @('-D', '--dereference-args', 'Dereference only symlinks listed on the command line.', $null),
        @('-d', '--max-depth', 'Print the total for a directory only if it is N or fewer levels deep.', 'Levels'),
        @('', '--files0-from', 'Summarize disk usage of the NUL-terminated file names in file F.', 'FileOrStdin'),
        @('-H', '', 'Equivalent to --dereference-args.', $null),
        @('-h', '--human-readable', 'Print sizes in human readable format.', $null),
        @('', '--inodes', 'List inode usage information instead of block usage.', $null),
        @('-k', '', 'Like --block-size=1K.', $null),
        @('-L', '--dereference', 'Dereference all symbolic links.', $null),
        @('-l', '--count-links', 'Count sizes many times if hard linked.', $null),
        @('-m', '', 'Like --block-size=1M.', $null),
        @('-P', '--no-dereference', 'Do not follow any symbolic links.', $null),
        @('-S', '--separate-dirs', 'For directories do not include size of subdirectories.', $null),
        @('', '--si', 'Like -h, but use powers of 1000 not 1024.', $null),
        @('-s', '--summarize', 'Display only a total for each argument.', $null),
        @('-t', '--threshold', 'Exclude entries smaller than SIZE if positive, or larger if negative.', 'Size'),
        @('', '--time', 'Show time of the last modification of any file in the directory.', 'TimeWord'),
        @('', '--time-style', 'Show times using STYLE.', 'TimeStyle'),
        @('-X', '--exclude-from', 'Exclude files that match any pattern in FILE.', 'File'),
        @('', '--exclude', 'Exclude files that match PATTERN.', 'Pattern'),
        @('-x', '--one-file-system', 'Skip directories on different file systems.', $null),
        @('', '--help', 'Display help and exit.', $null),
        @('', '--version', 'Output version information and exit.', $null)
    )

    foreach ($entry in $entries) {
        foreach ($token in @($entry[0], $entry[1])) {
            if ([string]::IsNullOrEmpty($token)) {
                continue
            }

            $catalog[$token] = [pscustomobject]@{
                Token       = $token
                Description = $entry[2]
                TakesValue  = ($null -ne $entry[3] -and $entry[1] -ne '--time')
                ValueKind   = $entry[3]
            }
        }
    }

    # The installed du's help refreshes descriptions and adds the options the static table lacks
    # (uutils: -A, -v/--verbose, -V). The placeholder follows the long option as GNU '=SIZE' /
    # '[=WORD]' or uutils ' <SIZE>' / '[=<WORD>...]'; a bracketed one is an optional value.
    $placeholderKinds = @{ SIZE = 'Size'; N = 'Levels'; FILE = 'File'; F = 'File'; PATTERN = 'Pattern'; WORD = 'TimeWord'; STYLE = 'TimeStyle' }
    foreach ($line in Invoke-DuHelpText) {
        if ($line -cnotmatch '^\s+(?:(?<short>-[A-Za-z0-9]),\s+)?(?<long>--[a-z0-9-]+)(?<placeholder>(?:=|\[=|\s<)\S*)?\s{2,}(?<text>.*)$' -and $line -cnotmatch '^\s+(?<short>-[A-Za-z0-9])\s{2,}(?<text>.*)$') {
            continue
        }

        $description = $Matches['text'].Trim()
        $tokens = @($Matches['short'], $Matches['long'] | Where-Object { $_ })
        $placeholder = [string]$Matches['placeholder']
        $known = @($tokens | Where-Object { $catalog.Contains($_) } | ForEach-Object { $catalog[$_] }) | Select-Object -First 1
        foreach ($token in $tokens) {
            if ($catalog.Contains($token)) {
                $catalog[$token].Description = $description
                continue
            }

            $valueKind = if ($known) {
                $known.ValueKind
            } elseif ($placeholder) {
                $placeholderName = ($placeholder -replace '[^A-Za-z]', '').ToUpperInvariant()
                if ($placeholderKinds.ContainsKey($placeholderName)) { $placeholderKinds[$placeholderName] } else { 'Value' }
            } else {
                $null
            }

            $catalog[$token] = [pscustomobject]@{
                Token       = $token
                Description = $description
                TakesValue  = if ($known) { $known.TakesValue } else { $placeholder -and -not $placeholder.StartsWith('[') }
                ValueKind   = $valueKind
            }
        }
    }

    $script:DuCompletionCatalog.Switches = @($catalog.Values)
    $script:DuCompletionCatalog.SwitchByKey = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $script:DuCompletionCatalog.Switches) {
        $script:DuCompletionCatalog.SwitchByKey[$entry.Token] = $entry
    }

    $script:DuCompletionCatalog.Initialized = $true
}

function Get-DuCurrentToken {
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

    $parts = @([regex]::Matches($prefix, '--[a-z0-9-]+=(?:["\u201C-\u201E][^"\u201C-\u201E]*["\u201C-\u201E]?|[''\u2018-\u201B][^''\u2018-\u201B]*[''\u2018-\u201B]?)|["\u201C-\u201E][^"\u201C-\u201E]*["\u201C-\u201E]?|[''\u2018-\u201B][^''\u2018-\u201B]*[''\u2018-\u201B]?|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-DuArgumentTokens {
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

function Get-DuShortFlagCluster {
    param([string]$Token)

    # du parses with getopt, so '-sh' is '-s -h' and '-sd1' is '-s -d 1': every letter is a flag
    # until one that takes a value, which consumes the rest of the word (or the next word).
    if ($Token -cnotmatch '^-[A-Za-z0-9]{2,}$') {
        return @()
    }

    $flags = [System.Collections.Generic.List[object]]::new()
    foreach ($letter in $Token.Substring(1).ToCharArray()) {
        $flag = '-' + $letter
        if (-not $script:DuCompletionCatalog.SwitchByKey.ContainsKey($flag)) {
            return @()
        }

        $flagSpec = $script:DuCompletionCatalog.SwitchByKey[$flag]
        $flags.Add($flagSpec)
        if ($flagSpec.TakesValue) {
            break
        }
    }

    $flags.ToArray()
}

function Get-DuState {
    param([string[]]$TokensBeforeCurrent)

    Initialize-DuCompletionCatalog

    $usedSwitches = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $positionals = New-Object System.Collections.Generic.List[string]
    $pendingValueKind = $null
    $helpRequested = $false

    foreach ($token in $TokensBeforeCurrent) {
        $cleanToken = Remove-DuOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($pendingValueKind) {
            $pendingValueKind = $null
            continue
        }

        $lookup = $cleanToken
        $attachedValue = $cleanToken -match '^(--[a-z0-9-]+)=.*$'
        if ($attachedValue) {
            $lookup = $Matches[1]
        }

        if ($script:DuCompletionCatalog.SwitchByKey.ContainsKey($lookup)) {
            $usedSwitches[$lookup] = $true
            $switchSpec = $script:DuCompletionCatalog.SwitchByKey[$lookup]
            if ($lookup -eq '--help') {
                $helpRequested = $true
            }

            if ($switchSpec.TakesValue -and -not $attachedValue) {
                $pendingValueKind = $switchSpec.ValueKind
            }
            continue
        }

        $clusterFlags = @(Get-DuShortFlagCluster -Token $cleanToken)
        if ($clusterFlags.Count -gt 0) {
            foreach ($flagSpec in $clusterFlags) {
                $usedSwitches[$flagSpec.Token] = $true
            }

            $lastFlag = $clusterFlags[-1]
            if ($lastFlag.TakesValue -and $cleanToken.Length -eq ($clusterFlags.Count + 1)) {
                $pendingValueKind = $lastFlag.ValueKind
            }
            continue
        }

        $positionals.Add($cleanToken)
    }

    [pscustomobject]@{
        UsedSwitches      = $usedSwitches
        Positionals       = @($positionals)
        PendingValueKind  = $pendingValueKind
        HelpRequested     = $helpRequested
    }
}

function Get-DuSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State
    )

    Initialize-DuCompletionCatalog

    $cleanCurrent = Remove-DuOuterQuotes -Value $CurrentWord

    foreach ($switchSpec in $script:DuCompletionCatalog.Switches) {
        if ($State.UsedSwitches.ContainsKey($switchSpec.Token)) {
            continue
        }

        if ($switchSpec.Token.StartsWith($cleanCurrent, [System.StringComparison]::Ordinal)) {
            New-DuCompletionResult -CompletionText $switchSpec.Token -ListItemText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description
        }
    }
}

function Get-DuShortFlagClusterCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State
    )

    # Extend a cluster of value-less short flags with each short flag not yet used; a flag that
    # takes a value may only end the cluster, so it is offered but never extended.
    $clusterFlags = @(Get-DuShortFlagCluster -Token $CurrentWord)
    if ($clusterFlags.Count -eq 0 -or $clusterFlags[-1].TakesValue) {
        return @()
    }

    $usedFlags = @($clusterFlags | ForEach-Object { $_.Token })
    @(
        foreach ($switchSpec in $script:DuCompletionCatalog.Switches) {
            if ($switchSpec.Token -cnotmatch '^-[A-Za-z0-9]$' -or $switchSpec.Token -cin $usedFlags -or $State.UsedSwitches.ContainsKey($switchSpec.Token)) {
                continue
            }

            $clustered = $CurrentWord + $switchSpec.Token.Substring(1)
            New-DuCompletionResult -CompletionText $clustered -ListItemText $clustered -ResultType 'ParameterName' -ToolTip ('{0}: {1}' -f $switchSpec.Token, $switchSpec.Description)
        }
    )
}

function Get-DuPathCompletions {
    param(
        [string]$InputPath,
        [string]$Prefix = ''
    )

    $cleanInput = ConvertFrom-DuTypedWord -Value $InputPath
    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
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

    # Candidates keep the directory part exactly as typed (.\, ./, ..\, sub/), separator included.
    $typedDirectory = if ($cleanInput -match '^(?<directory>.*[\\/])') { $Matches['directory'] } else { '' }
    $separator = if ($typedDirectory) { $typedDirectory[-1] } else { [System.IO.Path]::DirectorySeparatorChar }
    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') }

    # du's operands are FILE...: directories first (they invite the next level), then files.
    foreach ($item in ($items | Sort-Object -Property @{ Expression = { $_ -is [System.IO.FileInfo] } }, Name)) {
        if ($typedDirectory) {
            $pathText = $typedDirectory + $item.Name
        } elseif ($parent -ne '.') {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        } else {
            $pathText = $item.Name
        }

        # A whole word starting with a dash is a parameter to PowerShell and an option to du, so
        # anchor it to the current directory as PowerShell's own file completion does.
        if ($Prefix -eq '' -and $pathText -match '^[-\u2013-\u2015]') {
            $pathText = '.' + $separator + $pathText
        }

        $isDirectory = $item -is [System.IO.DirectoryInfo]
        if ($isDirectory -and $pathText -notmatch '[\\/]$') {
            $pathText += $separator
        }

        $quotedPath = ConvertTo-DuQuotedValue -Value $pathText -QuoteChar $quoteChar
        $resultType = if ($isDirectory) { 'ProviderContainer' } else { 'ProviderItem' }
        New-DuCompletionResult -CompletionText ($Prefix + $quotedPath) -ListItemText $pathText -ResultType $resultType -ToolTip $item.FullName
    }
}

function Get-DuValueCompletions {
    param(
        [string]$ValueKind,
        [string]$CurrentWord,
        [string]$Prefix = ''
    )

    if ($ValueKind -eq 'File' -or $ValueKind -eq 'FileOrStdin') {
        $cleanPath = Remove-DuOuterQuotes -Value $CurrentWord
        return @(
            if ($ValueKind -eq 'FileOrStdin' -and '-'.StartsWith($cleanPath, [System.StringComparison]::Ordinal)) {
                New-DuCompletionResult -CompletionText ($Prefix + '-') -ListItemText '-' -ResultType 'ParameterValue' -ToolTip 'Read the NUL-terminated file names from standard input.'
            }

            Get-DuPathCompletions -InputPath $CurrentWord -Prefix $Prefix
        )
    }

    $values = switch ($ValueKind) {
        'Levels' { @('0', '1', '2', '3', '5', '10') }
        'Size' { @('1', '1K', '1M', '1G', 'K', 'M', 'G') }
        'TimeWord' { @('atime', 'access', 'use', 'ctime', 'status') }
        'TimeStyle' { @('full-iso', 'long-iso', 'iso', '+%Y-%m-%d') }
        'Pattern' { @('<pattern>') }
        default { @() }
    }

    $cleanCurrent = Remove-DuOuterQuotes -Value $CurrentWord
    @(
        foreach ($value in $values) {
            if ($value.StartsWith($cleanCurrent, [System.StringComparison]::Ordinal)) {
                New-DuCompletionResult -CompletionText ($Prefix + $value) -ListItemText $value -ResultType 'ParameterValue' -ToolTip "du $ValueKind value."
            }
        }
    )
}

function Complete-Du {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-DuCompletionCatalog

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-DuCurrentToken -Line $commandAst.ToString() -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }

    $state = Get-DuState -TokensBeforeCurrent (Get-DuArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition)

    if ($state.HelpRequested) {
        return @()
    }

    if ($currentWord -match '^(?<option>--[a-z0-9-]+)=(?<value>.*)$') {
        $option = $Matches['option']
        $value = $Matches['value']
        if ($script:DuCompletionCatalog.SwitchByKey.ContainsKey($option)) {
            return @(Get-DuValueCompletions -ValueKind $script:DuCompletionCatalog.SwitchByKey[$option].ValueKind -CurrentWord $value -Prefix ($option + '='))
        }

        return @()
    }

    if ($state.PendingValueKind) {
        return @(Get-DuValueCompletions -ValueKind $state.PendingValueKind -CurrentWord $currentWord)
    }

    if ($currentWord -cmatch '^-[A-Za-z0-9]{2,}$') {
        return @(Get-DuShortFlagClusterCompletions -CurrentWord $currentWord -State $state)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-DuSwitchCompletions -CurrentWord $currentWord -State $state)
    }

    $results = @(Get-DuPathCompletions -InputPath $currentWord)
    if ([string]::IsNullOrEmpty($currentWord)) {
        $results += @(Get-DuSwitchCompletions -CurrentWord '' -State $state)
    }

    @($results)
}

Register-ArgumentCompleter -Native -CommandName 'du', 'du.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Du -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
