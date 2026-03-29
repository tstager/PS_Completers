# contig tab completion for PowerShell
# Static-first native completer for Contig with mode-aware path, drive, metadata, and length hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name ContigCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ContigCompletionCatalog = @{
        MetadataFiles = @(
            '$Mft', '$LogFile', '$Volume', '$AttrDef', '$Bitmap',
            '$Boot', '$BadClus', '$Secure', '$UpCase', '$Extend'
        )
        LengthHints   = @('65536', '1048576', '10485760', '1073741824')
        RootSwitches  = @(
            [pscustomobject]@{ Token = '-a'; Description = 'Analyze fragmentation for an existing file.'; Modes = @('existing') }
            [pscustomobject]@{ Token = '-f'; Description = 'Analyze free-space fragmentation on a drive.'; Modes = @('root', 'existing') }
            [pscustomobject]@{ Token = '-l'; Description = 'Set valid data length for quick file creation (with -n).' ; Modes = @('new') }
            [pscustomobject]@{ Token = '-n'; Description = 'Create a new file.'; Modes = @('root', 'existing') }
            [pscustomobject]@{ Token = '-q'; Description = 'Quiet mode.'; Modes = @('existing') }
            [pscustomobject]@{ Token = '-s'; Description = 'Recurse subdirectories.'; Modes = @('existing') }
            [pscustomobject]@{ Token = '-v'; Description = 'Verbose output.'; Modes = @('existing', 'new', 'free') }
            [pscustomobject]@{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.'; Modes = @('existing', 'new', 'free', 'root') }
            [pscustomobject]@{ Token = '/?'; Description = 'Show Contig help.'; Modes = @('existing', 'new', 'free', 'root') }
        )
    }
}

function New-ContigCompletionResult {
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

function Remove-ContigOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-ContigQuotedValue {
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

function Get-ContigCurrentToken {
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

function Get-ContigTokenState {
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
                $tokens.Add($builder.ToString())
                [void]$builder.Clear()
            }

            continue
        }

        [void]$builder.Append($character)
    }

    $hasTrailingSpace = $prefix -match '\s$'
    if ($builder.Length -gt 0) {
        $tokens.Add($builder.ToString())
    }

    if ($hasTrailingSpace) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($tokens)
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

function Get-ContigArgumentTokens {
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

function Get-ContigState {
    param([string[]]$TokensBeforeCurrent)

    $usedSwitches = @{}
    $positionals = New-Object System.Collections.Generic.List[string]
    $helpRequested = $false

    foreach ($token in $TokensBeforeCurrent) {
        $cleanToken = Remove-ContigOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($cleanToken.StartsWith('-') -or $cleanToken.StartsWith('/')) {
            $lookup = $cleanToken.ToLowerInvariant()
            $usedSwitches[$lookup] = $true
            if ($lookup -eq '/?') {
                $helpRequested = $true
            }
            continue
        }

        $positionals.Add($cleanToken)
    }

    $mode = 'existing'
    if ($usedSwitches.ContainsKey('-f')) {
        $mode = 'free'
    } elseif ($usedSwitches.ContainsKey('-n')) {
        $mode = 'new'
    }

    [pscustomobject]@{
        UsedSwitches   = $usedSwitches
        Positionals    = @($positionals)
        HelpRequested  = $helpRequested
        Mode           = $mode
    }
}

function Get-ContigUniqueCompletions {
    param([System.Management.Automation.CompletionResult[]]$Results)

    $seen = @{}
    $unique = @()
    foreach ($result in $Results) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.ContainsKey($result.CompletionText)) {
            continue
        }

        $seen[$result.CompletionText] = $true
        $unique += $result
    }

    $unique
}

function Get-ContigSwitchCompletions {
    param(
        [string]$CurrentWord,
        [pscustomobject]$State
    )

    $cleanCurrent = Remove-ContigOuterQuotes -Value $CurrentWord
    $results = foreach ($switchSpec in $script:ContigCompletionCatalog.RootSwitches) {
        if ($State.HelpRequested -and $switchSpec.Token -ne '/?') {
            continue
        }

        if ($State.Mode -eq 'existing' -and ($State.UsedSwitches.ContainsKey('-f') -or $State.UsedSwitches.ContainsKey('-n'))) {
            continue
        }

        if ($switchSpec.Modes -notcontains $State.Mode -and $switchSpec.Modes -notcontains 'root') {
            continue
        }

        if ($State.UsedSwitches.ContainsKey($switchSpec.Token.ToLowerInvariant())) {
            continue
        }

        if (($State.Mode -eq 'free') -and ($switchSpec.Token -in @('-a', '-l', '-n', '-q', '-s'))) {
            continue
        }

        if (($State.Mode -eq 'new') -and ($switchSpec.Token -in @('-a', '-f', '-q', '-s'))) {
            continue
        }

        if (($State.Mode -eq 'existing') -and ($State.Positionals.Count -gt 0) -and ($switchSpec.Token -in @('-f', '-n'))) {
            continue
        }

        if ($switchSpec.Token.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-ContigCompletionResult -CompletionText $switchSpec.Token -ListItemText $switchSpec.Token -ResultType 'ParameterName' -ToolTip $switchSpec.Description
        }
    }

    @(Get-ContigUniqueCompletions -Results $results)
}

function Get-ContigPathCompletions {
    param([string]$InputPath)

    $cleanInput = Remove-ContigOuterQuotes -Value $InputPath
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
    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
    $items = $items | Where-Object { $_.Name -like "$leaf*" }

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

        $quotedPath = ConvertTo-ContigQuotedValue -Value $pathText -AlwaysQuote $alwaysQuote
        $resultType = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }
        New-ContigCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType $resultType -ToolTip $item.FullName
    }
}

function Get-ContigMetadataCompletions {
    param([string]$CurrentWord)

    $cleanCurrent = Remove-ContigOuterQuotes -Value $CurrentWord
    foreach ($metadataName in $script:ContigCompletionCatalog.MetadataFiles) {
        if ($metadataName.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-ContigCompletionResult -CompletionText $metadataName -ListItemText $metadataName -ResultType 'ParameterValue' -ToolTip 'NTFS metadata file supported by Contig.'
        }
    }
}

function Get-ContigDriveCompletions {
    param([string]$CurrentWord)

    $cleanCurrent = Remove-ContigOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Sort-Object -Property Name)) {
        $candidate = $drive.Name + ':'
        if ($candidate.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            $results.Add((New-ContigCompletionResult -CompletionText $candidate -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip ('Free-space analysis on drive ' + $candidate)))
        }
    }

    if ([string]::IsNullOrWhiteSpace($cleanCurrent) -or '<drive:>'.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
        $results.Add((New-ContigCompletionResult -CompletionText '<drive:>' -ListItemText '<drive:>' -ResultType 'ParameterValue' -ToolTip 'Drive letter target for free-space analysis.'))
    }

    @($results.ToArray())
}

function Get-ContigLengthCompletions {
    param([string]$CurrentWord)

    $cleanCurrent = Remove-ContigOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($hint in $script:ContigCompletionCatalog.LengthHints) {
        if ($hint.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            $results.Add((New-ContigCompletionResult -CompletionText $hint -ListItemText $hint -ResultType 'ParameterValue' -ToolTip 'Sample new-file length in bytes.'))
        }
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-ContigCompletionResult -CompletionText $CurrentWord -ListItemText $CurrentWord -ResultType 'ParameterValue' -ToolTip 'New-file length in bytes.'))
    }

    if ($results.Count -eq 0 -and [string]::IsNullOrWhiteSpace($CurrentWord)) {
        $results.Add((New-ContigCompletionResult -CompletionText ' ' -ListItemText '<new-file-length>' -ResultType 'ParameterValue' -ToolTip 'New-file length in bytes.'))
    }

    @($results.ToArray())
}

function Complete-Contig {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-ContigCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    $state = Get-ContigState -TokensBeforeCurrent (Get-ContigArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition)

    if ($state.HelpRequested) {
        return @(
            New-ContigCompletionResult -CompletionText ' ' -ListItemText '<complete>' -ResultType 'ParameterValue' -ToolTip 'Contig help is terminal for completion.'
        )
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and ($currentWord.StartsWith('-') -or $currentWord.StartsWith('/'))) {
        return @(Get-ContigSwitchCompletions -CurrentWord $currentWord -State $state)
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($switchResult in @(Get-ContigSwitchCompletions -CurrentWord '' -State $state)) {
        $results.Add($switchResult)
    }

    switch ($state.Mode) {
        'free' {
            if ($state.Positionals.Count -eq 0) {
                foreach ($item in @(Get-ContigDriveCompletions -CurrentWord $currentWord)) {
                    $results.Add($item)
                }
                return @(Get-ContigUniqueCompletions -Results $results.ToArray())
            }

            return @()
        }
        'new' {
            if ($state.Positionals.Count -eq 0) {
                foreach ($item in @(Get-ContigPathCompletions -InputPath $currentWord)) {
                    $results.Add($item)
                }
                return @(Get-ContigUniqueCompletions -Results $results.ToArray())
            }

            if ($state.Positionals.Count -eq 1) {
                return @(Get-ContigLengthCompletions -CurrentWord $currentWord)
            }

            return @()
        }
        default {
            if ($state.Positionals.Count -eq 0) {
                foreach ($item in @(Get-ContigPathCompletions -InputPath $currentWord)) {
                    $results.Add($item)
                }

                foreach ($item in @(Get-ContigMetadataCompletions -CurrentWord $currentWord)) {
                    $results.Add($item)
                }

                return @(Get-ContigUniqueCompletions -Results $results.ToArray())
            }

            return @()
        }
    }
}

Register-ArgumentCompleter -Native -CommandName 'contig', 'contig.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Contig -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
