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

function ConvertFrom-ContigTypedWord {
    # The value of a typed word. A word opened with a quote (ASCII or typographic) is read by
    # the PowerShell tokenizer, which drops the quotes and undoes that quote style's escapes.
    # Returns $null when the quote closes mid-word ('sp'ace): PowerShell then completes only
    # the text after the quote, so the word has no single value to complete.
    param([string]$Value)

    if ($Value -notmatch '^[''"\u2018-\u201E]') {
        return $Value
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Value, [ref]$tokens, [ref]$parseErrors)
    if ($tokens[0].Extent.EndOffset -lt $Value.Length) {
        return $null
    }

    $tokens[0].Value
}

function ConvertTo-ContigQuotedValue {
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
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]|^[-\u2013-\u2015]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-ContigQuoteClass {
    # 1 = single-quote family (' and U+2018-U+201B), 2 = double-quote family (" and U+201C-U+201E).
    param([char]$Character)

    if ($Character -eq [char]39 -or ($Character -ge [char]0x2018 -and $Character -le [char]0x201B)) {
        return 1
    }

    if ($Character -eq [char]34 -or ($Character -ge [char]0x201C -and $Character -le [char]0x201E)) {
        return 2
    }

    0
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
    $quoteClass = 0
    $escapeNext = $false

    foreach ($character in $prefix.ToCharArray()) {
        if ($escapeNext) {
            $escapeNext = $false
            [void]$builder.Append($character)
            continue
        }

        # A backtick escapes the next character everywhere except inside single quotes.
        if ($character -eq [char]96 -and $quoteClass -ne 1) {
            $escapeNext = $true
            [void]$builder.Append($character)
            continue
        }

        $characterClass = Get-ContigQuoteClass -Character $character
        if ($characterClass -ne 0) {
            if ($quoteClass -eq 0) {
                $quoteClass = $characterClass
            } elseif ($quoteClass -eq $characterClass) {
                $quoteClass = 0
            }

            [void]$builder.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and $quoteClass -eq 0) {
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

    $cleanInput = ConvertFrom-ContigTypedWord -Value $InputPath
    if ($null -eq $cleanInput) {
        return
    }

    $quoteChar = if ($InputPath -match '^[''"\u2018-\u201E]') { $InputPath.Substring(0, 1) } else { '' }

    # Candidates keep the typed directory text exactly (.\, ./, ..\, C:, sub/) and add the item name.
    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    if ($separatorIndex -lt 0 -and $cleanInput -match '^[A-Za-z]:') {
        $separatorIndex = 1
    }

    $directoryText = $cleanInput.Substring(0, $separatorIndex + 1)
    $leaf = $cleanInput.Substring($separatorIndex + 1)
    $parent = if ($directoryText) { $directoryText } else { '.' }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore)
    $items = $items | Where-Object { $_.Name -like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*') }

    foreach ($item in ($items | Sort-Object -Property @{ Expression = 'PSIsContainer'; Descending = $true }, Name)) {
        $pathText = $directoryText + $item.Name

        # A bare word starting with a dash is parsed as a parameter, so a dash-leading name in
        # the current directory gets the .\ prefix PowerShell's own file completion uses.
        if (-not $directoryText -and $pathText -match '^[-\u2013-\u2015]') {
            $pathText = '.' + [System.IO.Path]::DirectorySeparatorChar + $pathText
        }

        if ($item.PSIsContainer -and -not $pathText.EndsWith('\')) {
            $pathText += '\'
        }

        $quotedPath = ConvertTo-ContigQuotedValue -Value $pathText -QuoteChar $quoteChar
        $resultType = if ($item.PSIsContainer) { 'ProviderContainer' } else { 'ParameterValue' }
        New-ContigCompletionResult -CompletionText $quotedPath -ListItemText $pathText -ResultType $resultType -ToolTip $item.FullName
    }
}

function Get-ContigMetadataCompletions {
    param([string]$CurrentWord)

    $cleanCurrent = ConvertFrom-ContigTypedWord -Value $CurrentWord
    if ($null -eq $cleanCurrent) {
        return
    }

    $quoteChar = if ($CurrentWord -match '^[''"\u2018-\u201E]') { $CurrentWord.Substring(0, 1) } else { '' }
    foreach ($metadataName in $script:ContigCompletionCatalog.MetadataFiles) {
        if ($metadataName.StartsWith($cleanCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
            New-ContigCompletionResult -CompletionText (ConvertTo-ContigQuotedValue -Value $metadataName -QuoteChar $quoteChar) -ListItemText $metadataName -ResultType 'ParameterValue' -ToolTip 'NTFS metadata file supported by Contig.'
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
