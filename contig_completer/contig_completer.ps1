# contig tab completion for PowerShell
# Static-first native completer for Contig with mode-aware path, drive, metadata, and length hints.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name ContigCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:ContigCompletionCatalog = @{
        MetadataFiles = @(
            '$Mft', '$LogFile', '$Volume', '$AttrDef', '$Bitmap',
            '$Boot', '$BadClus', '$Secure', '$UpCase', '$Extend'
        )
        LengthHints   = @('65536', '1048576', '10485760', '1073741824')
        DriveCache    = $null
        # Forms are Contig's three documented usage lines:
        #   1  contig [-a] [-s] [-q] [-v] <existing file>
        #   2  contig -f [-v] [drive:]
        #   3  contig [-v] [-l] -n <new file> <new file length>
        RootSwitches  = @(
            @{ Token = '-a'; Description = 'Analyze fragmentation.'; Forms = @(1) }
            @{ Token = '-f'; Description = 'Analyze free space fragmentation.'; Forms = @(2) }
            @{ Token = '-l'; Description = 'Set valid data length for quick file creation (requires administrator rights).'; Forms = @(3) }
            @{ Token = '-n'; Description = 'Create a new file.'; Forms = @(3) }
            @{ Token = '-q'; Description = 'Quiet mode.'; Forms = @(1) }
            @{ Token = '-s'; Description = 'Recurse subdirectories.'; Forms = @(1) }
            @{ Token = '-v'; Description = 'Verbose.'; Forms = @(1, 2, 3) }
            @{ Token = '-nobanner'; Description = 'Do not display the startup banner and copyright message.'; Forms = @(1, 2, 3) }
            @{ Token = '-accepteula'; Description = 'Accept the Sysinternals EULA silently.'; Forms = @(1, 2, 3) }
            @{ Token = '-?'; Description = 'Show Contig help.'; Forms = @(1, 2, 3) }
            @{ Token = '/?'; Description = 'Show Contig help.'; Forms = @(1, 2, 3) }
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
            if ($lookup -in @('-?', '/?')) {
                $helpRequested = $true
            }
            continue
        }

        $positionals.Add($cleanToken)
    }

    $viableForms = @(1, 2, 3)
    foreach ($switchSpec in $script:ContigCompletionCatalog.RootSwitches) {
        if ($usedSwitches.ContainsKey($switchSpec.Token.ToLowerInvariant())) {
            $viableForms = @($viableForms | Where-Object { $_ -in $switchSpec.Forms })
        }
    }

    # A bare operand with no form-selecting switch can only be usage form 1.
    if ($positionals.Count -gt 0 -and $viableForms -contains 1) {
        $viableForms = @(1)
    }

    $mode = 'existing'
    if ($usedSwitches.ContainsKey('-f')) {
        $mode = 'free'
    } elseif ($usedSwitches.ContainsKey('-n') -or $usedSwitches.ContainsKey('-l')) {
        $mode = 'new'
    }

    [pscustomobject]@{
        UsedSwitches   = $usedSwitches
        Positionals    = @($positionals)
        HelpRequested  = $helpRequested
        ViableForms    = @($viableForms)
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
        if ($State.HelpRequested -and $switchSpec.Token -notin @('-?', '/?')) {
            continue
        }

        if ($State.UsedSwitches.ContainsKey($switchSpec.Token.ToLowerInvariant())) {
            continue
        }

        if (-not @($switchSpec.Forms | Where-Object { $_ -in $State.ViableForms })) {
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
    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') }

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
            New-ContigCompletionResult -CompletionText ("'" + $metadataName + "'") -ListItemText $metadataName -ResultType 'ParameterValue' -ToolTip 'NTFS metadata file supported by Contig.'
        }
    }
}

function Get-ContigDriveLetterCache {
    if ($null -eq $script:ContigCompletionCatalog.DriveCache) {
        $entries = New-Object System.Collections.Generic.List[object]
        foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
            try {
                if (-not $drive.IsReady -or $drive.DriveFormat -ne 'NTFS') {
                    continue
                }

                $entries.Add([pscustomobject]@{ Token = $drive.Name.Substring(0, 2); Label = $drive.VolumeLabel })
            } catch {
                continue
            }
        }

        $script:ContigCompletionCatalog.DriveCache = @($entries.ToArray())
    }

    @($script:ContigCompletionCatalog.DriveCache)
}

function Get-ContigDriveCompletions {
    param([string]$CurrentWord)

    $cleanCurrent = Remove-ContigOuterQuotes -Value $CurrentWord
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($drive in (Get-ContigDriveLetterCache)) {
        $candidate = $drive.Token
        if ($candidate.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            $tooltip = if ([string]::IsNullOrWhiteSpace($drive.Label)) {
                'NTFS free-space analysis on drive ' + $candidate
            } else {
                'NTFS free-space analysis on drive ' + $candidate + ' (' + $drive.Label + ')'
            }

            $results.Add((New-ContigCompletionResult -CompletionText $candidate -ListItemText $candidate -ResultType 'ParameterValue' -ToolTip $tooltip))
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

    $line = $commandAst.ToString()
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    if ($relativeCursor -gt $line.Length) {
        $line = $line.PadRight($relativeCursor)
    }

    $tokenState = Get-ContigTokenState -Line $line -CursorPosition $relativeCursor
    $currentWord = $tokenState.CurrentToken
    $state = Get-ContigState -TokensBeforeCurrent @($tokenState.TokensBeforeCurrent | Select-Object -Skip 1)

    if ($state.HelpRequested) {
        return @(
            New-ContigCompletionResult -CompletionText ' ' -ListItemText '<complete>' -ResultType 'ParameterValue' -ToolTip 'Contig help is terminal for completion.'
        )
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and ($currentWord.StartsWith('-') -or $currentWord.StartsWith('/'))) {
        return @(Get-ContigSwitchCompletions -CurrentWord $currentWord -State $state)
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($switchResult in @(Get-ContigSwitchCompletions -CurrentWord $currentWord -State $state)) {
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
