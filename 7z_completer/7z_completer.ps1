# 7z tab completion for PowerShell
# Builds completion data from 7z built-in help.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name SevenZipCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:SevenZipCompletionCatalog = @{
        Initialized         = $false
        HelpCommand         = $null
        Commands            = @()
        SwitchTokens        = @()
        ValueHintsBySwitch  = @{}
        PathLikeSwitches    = @('-o', '-w')
        ArchiveTypeSwitches = @('-t', '-stx')
        ArchiveTypes        = @()
        ArchiveTypesLoaded  = $false
    }
}

function Resolve-SevenZipHelpCommand {
    if ($script:SevenZipCompletionCatalog.HelpCommand) {
        return $script:SevenZipCompletionCatalog.HelpCommand
    }

    $command = Get-Command -Name 7z.exe, 7z -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $script:SevenZipCompletionCatalog.HelpCommand = $command.Name
    }

    $script:SevenZipCompletionCatalog.HelpCommand
}

function Invoke-SevenZipHelpText {
    $commandName = Resolve-SevenZipHelpCommand
    if (-not $commandName) {
        return @()
    }

    try {
        @($null | & $commandName --help 2>$null)
    } catch {
        @()
    }
}

function Get-SevenZipNormalizedHelpText {
    param([string[]]$Lines)

    if (-not $Lines -or $Lines.Count -eq 0) {
        return ''
    }

    $text = $Lines -join "`n"
    foreach ($marker in @('Usage:', '<Commands>', '<Switches>')) {
        $text = $text -replace [regex]::Escape($marker), ("`n" + $marker)
    }

    $text.Trim()
}

function Get-SevenZipHelpSectionLines {
    param(
        [string[]]$Lines,
        [string]$StartHeader,
        [string]$EndHeader
    )

    $text = Get-SevenZipNormalizedHelpText -Lines $Lines
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }

    $startPattern = [regex]::Escape($StartHeader)
    if ([string]::IsNullOrWhiteSpace($EndHeader)) {
        $pattern = "(?s)$startPattern\s*(.*)$"
    } else {
        $endPattern = [regex]::Escape($EndHeader)
        $pattern = "(?s)$startPattern\s*(.*?)(?=$endPattern)"
    }

    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) {
        return @()
    }

    @($match.Groups[1].Value -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-SevenZipCommandsFromLines {
    param([string[]]$Lines)

    $commandLines = Get-SevenZipHelpSectionLines -Lines $Lines -StartHeader '<Commands>' -EndHeader '<Switches>'
    $commands = foreach ($line in $commandLines) {
        if ($line -match '^\s*([a-z][a-z0-9]*)\s*:') {
            $matches[1]
        }
    }

    $commands | Sort-Object -Unique
}

function Get-SevenZipSwitchTokensFromLines {
    param([string[]]$Lines)

    $switchLines = Get-SevenZipHelpSectionLines -Lines $Lines -StartHeader '<Switches>'
    $tokens = foreach ($line in $switchLines) {
        if ($line -match '^\s*(--|-[A-Za-z][A-Za-z0-9]*)(?=[\[\{\s:]|$)') {
            $matches[1]
        }
    }

    $tokens | Sort-Object -Unique
}

function ConvertFrom-SevenZipRangeExpression {
    param([string]$Text)

    if ($Text -match '^(\d+)-(\d+)$') {
        $start = [int]$matches[1]
        $end = [int]$matches[2]
        if ($start -le $end) {
            return @($start..$end | ForEach-Object { $_.ToString() })
        }
    }

    @()
}

function Get-SevenZipSimpleValues {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $rangeValues = ConvertFrom-SevenZipRangeExpression -Text $Text.Trim()
    if (@($rangeValues).Count -gt 0) {
        return $rangeValues
    }

    $parts = @($Text -split '\|')

    # A lone '{Directory}', '{Type}' or '[N]' is a metavariable, not a value 7-Zip accepts; only a
    # list of alternatives, or a short lower-case token, is a real enum member.
    if ($parts.Count -eq 1) {
        $only = $parts[0].Trim()
        if ($only -eq 'N' -or ($only.Length -gt 3 -and $only -cmatch '^[A-Z]')) {
            return @()
        }
    }

    $values = foreach ($part in $parts) {
        $value = $part.Trim()
        if ($value -match '^\{.+\}$') {
            continue
        }

        if ($value -match '^[A-Za-z0-9*][A-Za-z0-9*._:-]*$') {
            $value
        }
    }

    $values | Sort-Object -Unique
}

function Get-SevenZipValueHintsFromLines {
    param([string[]]$Lines)

    $result = @{}
    $switchLines = Get-SevenZipHelpSectionLines -Lines $Lines -StartHeader '<Switches>'

    foreach ($line in $switchLines) {
        if ($line -match '^\s*(--|-[A-Za-z][A-Za-z0-9]*)(\{([^}]+)\}|\[([^\]]+)\])\s*:') {
            $switchToken = $matches[1]
            $rawValues = if ($matches[3]) { $matches[3] } else { $matches[4] }
            $values = @(Get-SevenZipSimpleValues -Text $rawValues)

            if ($values.Count -gt 0) {
                $result[$switchToken.ToLowerInvariant()] = $values
            }
        }
    }

    $result
}

function Get-SevenZipArchiveTypeList {
    if ($script:SevenZipCompletionCatalog.ArchiveTypesLoaded) {
        return $script:SevenZipCompletionCatalog.ArchiveTypes
    }

    $script:SevenZipCompletionCatalog.ArchiveTypesLoaded = $true

    $commandName = Resolve-SevenZipHelpCommand
    if (-not $commandName) {
        return $script:SevenZipCompletionCatalog.ArchiveTypes
    }

    $raw = try {
        $null | & $commandName i 2>$null
    } catch {
        @()
    }

    # The 'Formats:' table lists one archive format per line as
    # '<index> <flags>  <Name>  <extensions>  <signature>'. The flag column can contain spaces, so
    # the name is the first single-word field that is neither the index nor the dotted flag string.
    $inFormats = $false
    $names = foreach ($line in @($raw)) {
        if ($line -match '^Formats:') {
            $inFormats = $true
            continue
        }

        if ($inFormats -and $line -match '^\S') {
            $inFormats = $false
        }

        if (-not $inFormats) {
            continue
        }

        foreach ($field in @($line -split '\s{2,}')) {
            $words = @($field.Trim() -split '\s+' | Where-Object { $_ })
            if ($words.Count -eq 0) {
                continue
            }

            $first = $words[0]
            if ($first -match '^\d+$' -or $first -match '^[.]+$') {
                continue
            }

            if ($first -match '^[A-Za-z0-9][A-Za-z0-9]*$') {
                $first.ToLowerInvariant()
                break
            }
        }
    }

    $script:SevenZipCompletionCatalog.ArchiveTypes = @(@($names) | Sort-Object -Unique)
    $script:SevenZipCompletionCatalog.ArchiveTypes
}

function Initialize-SevenZipCompletionCatalog {
    if ($script:SevenZipCompletionCatalog.Initialized) {
        return
    }

    $helpLines = Invoke-SevenZipHelpText
    if ($helpLines -and $helpLines.Count -gt 0) {
        $script:SevenZipCompletionCatalog.Commands = @(Get-SevenZipCommandsFromLines -Lines $helpLines)
        $script:SevenZipCompletionCatalog.SwitchTokens = @(Get-SevenZipSwitchTokensFromLines -Lines $helpLines)
        $script:SevenZipCompletionCatalog.ValueHintsBySwitch = Get-SevenZipValueHintsFromLines -Lines $helpLines
    }

    $script:SevenZipCompletionCatalog.Initialized = $true
}

function New-SevenZipCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip
    )

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $CompletionText,
        $ResultType,
        $ToolTip
    )
}

function Get-SevenZipCurrentToken {
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Test-SevenZipHasOptionTerminator {
    param([string[]]$TokensBeforeCurrent)

    foreach ($token in $TokensBeforeCurrent) {
        if ($token -eq '--') {
            return $true
        }
    }

    $false
}

function Get-SevenZipActiveCommand {
    param(
        [string[]]$Tokens,
        [string[]]$KnownCommands
    )

    $known = @{}
    foreach ($command in $KnownCommands) {
        $known[$command.ToLowerInvariant()] = $command
    }

    foreach ($token in $Tokens) {
        if ($token -eq '--') {
            break
        }

        $lookup = $token.ToLowerInvariant()
        if ($known.ContainsKey($lookup)) {
            return $known[$lookup]
        }
    }

    $null
}

function Get-SevenZipInlineValueSwitch {
    param(
        [string]$Token,
        [string[]]$KnownValueSwitches
    )

    if ([string]::IsNullOrWhiteSpace($Token) -or -not $Token.StartsWith('-') -or $Token -eq '--') {
        return $null
    }

    foreach ($switchToken in ($KnownValueSwitches | Sort-Object Length -Descending)) {
        if ($Token.Length -ge $switchToken.Length -and
            $Token.Substring(0, $switchToken.Length).Equals($switchToken, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $switchToken
        }
    }

    $null
}

function Get-SevenZipDirectoryCompletions {
    param(
        [string]$InputPath,
        [string]$SwitchPrefix = ''
    )

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and $InputPath.StartsWith('"')

    Get-ChildItem -Path $parent -Filter $filter -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $completionText = if ($cleanInput -and -not [System.IO.Path]::IsPathRooted($cleanInput)) {
                if ($parent -eq '.') {
                    $_.Name
                } else {
                    Join-Path -Path $parent -ChildPath $_.Name
                }
            } else {
                $_.FullName
            }

            if (-not $completionText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
                $completionText += [System.IO.Path]::DirectorySeparatorChar
            }

            if (($alwaysQuote -or $completionText -match '\s') -and
                -not ($completionText.StartsWith('"') -and $completionText.EndsWith('"'))) {
                $completionText = '"' + $completionText + '"'
            }

            if ($SwitchPrefix) {
                $completionText = $SwitchPrefix + $completionText
            }

            New-SevenZipCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $_.FullName
        }
}

function Get-SevenZipFileCompletionList {
    param([string]$InputPath)

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    [System.Management.Automation.CompletionCompleters]::CompleteFilename($cleanInput)
}

function Complete-SevenZip {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-SevenZipCompletionCatalog

    $allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokens = @($allTokens | Select-Object -Skip 1)
    $line = $commandAst.ToString()
    $hasTrailingSpace = ([string]::IsNullOrEmpty($wordToComplete) -and $cursorPosition -ge $line.Length) -or ($line -match '\s$')
    $currentWord = if ($hasTrailingSpace) {
        ''
    } elseif ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        Get-SevenZipCurrentToken -Line $line -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    } else {
        $wordToComplete
    }

    if ($hasTrailingSpace) {
        $tokensBeforeCurrent = @($tokens)
    } elseif ($tokens.Count -gt 1) {
        $tokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
    } else {
        $tokensBeforeCurrent = @()
    }

    $hasOptionTerminator = Test-SevenZipHasOptionTerminator -TokensBeforeCurrent $tokensBeforeCurrent
    $activeCommand = Get-SevenZipActiveCommand -Tokens $tokensBeforeCurrent -KnownCommands $script:SevenZipCompletionCatalog.Commands
    # 7-Zip only accepts switch values attached to the switch ('-tzip', '-oC:\out'); there is no
    # space-separated and no '--switch=value' form, so only the inline shape is completed.
    $valueSwitches = @(
        $script:SevenZipCompletionCatalog.ValueHintsBySwitch.Keys
        $script:SevenZipCompletionCatalog.PathLikeSwitches
        $script:SevenZipCompletionCatalog.ArchiveTypeSwitches
    ) | Sort-Object -Unique

    if (-not $hasOptionTerminator) {
        $inlineValueSwitch = Get-SevenZipInlineValueSwitch -Token $currentWord -KnownValueSwitches $valueSwitches
        if ($inlineValueSwitch) {
            $typedValue = $currentWord.Substring($inlineValueSwitch.Length)
            $switchKey = $inlineValueSwitch.ToLowerInvariant()

            if ($script:SevenZipCompletionCatalog.PathLikeSwitches -contains $switchKey) {
                return Get-SevenZipDirectoryCompletions -InputPath $typedValue -SwitchPrefix $inlineValueSwitch
            }

            if ($script:SevenZipCompletionCatalog.ArchiveTypeSwitches -contains $switchKey) {
                return Get-SevenZipArchiveTypeList |
                    Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                    ForEach-Object {
                        New-SevenZipCompletionResult -CompletionText ($inlineValueSwitch + $_) -ResultType 'ParameterValue' -ToolTip "Archive type $_"
                    }
            }

            if ($script:SevenZipCompletionCatalog.ValueHintsBySwitch.ContainsKey($switchKey)) {
                return $script:SevenZipCompletionCatalog.ValueHintsBySwitch[$switchKey] |
                    Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($typedValue) + '*') } |
                    ForEach-Object {
                        New-SevenZipCompletionResult -CompletionText ($inlineValueSwitch + $_) -ResultType 'ParameterValue' -ToolTip ($inlineValueSwitch + $_)
                    }
            }
        }
    }

    if (-not $activeCommand) {
        if ([string]::IsNullOrWhiteSpace($currentWord)) {
            $commandResults = $script:SevenZipCompletionCatalog.Commands |
                ForEach-Object {
                    New-SevenZipCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                }
            $switchResults = if ($hasOptionTerminator) {
                @()
            } else {
                $script:SevenZipCompletionCatalog.SwitchTokens |
                    ForEach-Object {
                        New-SevenZipCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
                    }
            }

            return @($commandResults + $switchResults)
        }

        if (-not $hasOptionTerminator -and $currentWord.StartsWith('-')) {
            return $script:SevenZipCompletionCatalog.SwitchTokens |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*') } |
                ForEach-Object {
                    New-SevenZipCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
                }
        }

        return $script:SevenZipCompletionCatalog.Commands |
            Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*') } |
            ForEach-Object {
                New-SevenZipCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
            }
    }

    if (-not $hasOptionTerminator -and $currentWord.StartsWith('-')) {
        return $script:SevenZipCompletionCatalog.SwitchTokens |
            Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*') } |
            ForEach-Object {
                New-SevenZipCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
            }
    }

    # Everything after the command is <archive_name> then <file_names>, so this is a path slot.
    $fileResults = @(Get-SevenZipFileCompletionList -InputPath $currentWord)
    if (-not $hasOptionTerminator -and [string]::IsNullOrWhiteSpace($currentWord)) {
        $switchResults = @(
            $script:SevenZipCompletionCatalog.SwitchTokens |
                ForEach-Object {
                    New-SevenZipCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
                }
        )

        return @($switchResults + $fileResults)
    }

    $fileResults
}

Register-ArgumentCompleter -Native -CommandName '7z', '7z.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-SevenZip -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
