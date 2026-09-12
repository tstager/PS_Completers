# du tab completion for PowerShell
# Help-refreshed native completer for GNU coreutils du with option value hints and directory operand completion.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name DuCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
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

    $command = Get-Command -Name du.exe, du -ErrorAction SilentlyContinue | Select-Object -First 1
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
        @($null | & $commandName --help 2>&1)
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

function ConvertTo-DuQuotedValue {
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
        @('', '--files0-from', 'Summarize disk usage of the NUL-terminated file names in file F.', 'File'),
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

    foreach ($line in Invoke-DuHelpText) {
        if ($line -match '^\s+(?:(-[A-Za-z0-9]),\s+)?(--[a-z0-9-]+)(?:[=\[]\S*)?\s{2,}(.*)$' -or $line -match '^\s+(-[A-Za-z0-9])()\s{2,}(.*)$') {
            $description = $Matches[3].Trim()
            foreach ($token in @($Matches[1], $Matches[2])) {
                if ($token -and $catalog.Contains($token)) {
                    $catalog[$token].Description = $description
                }
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"?|''[^'']*''?|\S+') | ForEach-Object { $_.Value })
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

function Get-DuState {
    param([string[]]$TokensBeforeCurrent)

    Initialize-DuCompletionCatalog

    $usedSwitches = @{}
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

function Get-DuDirectoryCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-DuOuterQuotes -Value $InputPath
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and ($InputPath.StartsWith('"') -or $InputPath.StartsWith("'"))

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

    $inputIsRooted = -not [string]::IsNullOrWhiteSpace($cleanInput) -and [System.IO.Path]::IsPathRooted($cleanInput)
    $items = @(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') }

    foreach ($item in ($items | Sort-Object -Property Name)) {
        if ($inputIsRooted) {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        } elseif ($parent -eq '.' -or [string]::IsNullOrWhiteSpace($cleanInput)) {
            $pathText = $item.Name
        } else {
            $pathText = Join-Path -Path $parent -ChildPath $item.Name
        }

        if (-not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $quotedPath = ConvertTo-DuQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        New-DuCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType 'ProviderContainer' -ToolTip $item.FullName
    }
}

function Get-DuValueCompletions {
    param(
        [string]$ValueKind,
        [string]$CurrentWord,
        [string]$Prefix = ''
    )

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

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('-')) {
        return @(Get-DuSwitchCompletions -CurrentWord $currentWord -State $state)
    }

    $results = @(Get-DuDirectoryCompletions -InputPath $currentWord)
    if ([string]::IsNullOrEmpty($currentWord)) {
        $results += @(Get-DuSwitchCompletions -CurrentWord '' -State $state)
    }

    @($results)
}

Register-ArgumentCompleter -Native -CommandName 'du', 'du.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Du -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
