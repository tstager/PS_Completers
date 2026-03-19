# icacls tab completion for PowerShell
# Builds completion data from icacls built-in help.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name IcaclsCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:IcaclsCompletionCatalog = @{
        Initialized         = $false
        Commands            = @()
        CommandOptionsByKey = @{}
        CommonOptions       = @()
        ModifyOptions       = @()
        IntegrityLevels     = @()
        SimplePermissions   = @()
        SpecificPermissions = @()
        InheritanceFlags    = @()
    }
}

function Invoke-IcaclsHelpText {
    if (-not (Get-Command -Name icacls.exe -ErrorAction SilentlyContinue)) {
        return @()
    }

    @(& icacls.exe '/?' 2>$null)
}

function Expand-IcaclsHelpToken {
    param([string]$Token)

    $normalized = $Token.TrimEnd(']', ')', ',')
    $lookup = $normalized.ToLowerInvariant()

    if ($lookup.StartsWith('/grant[')) {
        return @('/grant', '/grant:r')
    }

    if ($lookup.StartsWith('/remove[')) {
        return @('/remove', '/remove:g', '/remove:d')
    }

    if ($lookup -eq '/inheritance:e|d|r') {
        return @('/inheritance:e', '/inheritance:d', '/inheritance:r')
    }

    return @($normalized)
}

function Get-IcaclsTokensFromText {
    param([string]$Text)

    $tokens = foreach ($match in [regex]::Matches($Text, '(?<!\w)(/[A-Za-z][A-Za-z0-9]*(?::[^\s\]]+)?)')) {
        Expand-IcaclsHelpToken -Token $match.Groups[1].Value
    }

    $tokens | Sort-Object -Unique
}

function Get-IcaclsSyntaxBlocks {
    param([string[]]$Lines)

    $blocks = New-Object System.Collections.Generic.List[object]
    $current = New-Object System.Collections.Generic.List[string]
    $capturing = $false

    foreach ($line in $Lines) {
        if ($line -match '^\s*ICACLS\s+') {
            if ($current.Count -gt 0) {
                $blocks.Add(@($current))
                $current.Clear()
            }

            $capturing = $true
            $current.Add($line.TrimEnd())
            continue
        }

        if (-not $capturing) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($current.Count -gt 0) {
                $blocks.Add(@($current))
                $current.Clear()
            }

            $capturing = $false
            continue
        }

        if ($line -match '^\s+') {
            $current.Add($line.Trim())
            continue
        }

        if ($current.Count -gt 0) {
            $blocks.Add(@($current))
            $current.Clear()
        }

        $capturing = $false
    }

    if ($current.Count -gt 0) {
        $blocks.Add(@($current))
    }

    $blocks
}

function Get-IcaclsMainCommandFromTokens {
    param([string[]]$Tokens)

    foreach ($candidate in @('/save', '/restore', '/setowner', '/findsid', '/verify', '/reset')) {
        if ($Tokens -contains $candidate) {
            return $candidate
        }
    }

    $null
}

function Get-IcaclsCommonOptionsFromLines {
    param([string[]]$Lines)

    $options = foreach ($line in $Lines) {
        if ($line -match '^\s*(/[A-Za-z][A-Za-z0-9]*)\s+indicates') {
            $matches[1]
        }
    }

    $options | Sort-Object -Unique
}

function Get-IcaclsIntegrityLevelsFromLines {
    param([string[]]$Lines)

    $levels = foreach ($line in $Lines) {
        if ($line -match '^\s*([LMH])\[([a-z]+)\]') {
            $shortLevel = $matches[1].ToUpperInvariant()
            $fullLevel = ($matches[1] + $matches[2]).ToLowerInvariant()
            $fullLevel = $fullLevel.Substring(0, 1).ToUpperInvariant() + $fullLevel.Substring(1)

            $shortLevel
            $fullLevel
        }
    }

    $levels | Sort-Object -Unique
}

function Get-IcaclsSimplePermissionsFromLines {
    param([string[]]$Lines)

    $permissions = New-Object System.Collections.Generic.List[string]
    $inSimpleRights = $false

    foreach ($line in $Lines) {
        if ($line -match '^\s*a sequence of simple rights:') {
            $inSimpleRights = $true
            continue
        }

        if (-not $inSimpleRights) {
            continue
        }

        if ($line -match '^\s*a comma-separated list') {
            break
        }

        if ($line -match '^\s*([A-Z]+)\s+-') {
            $permissions.Add($matches[1])
        }
    }

    @($permissions | Sort-Object -Unique)
}

function Get-IcaclsSpecificPermissionsFromLines {
    param([string[]]$Lines)

    $permissions = New-Object System.Collections.Generic.List[string]
    $inSpecificRights = $false

    foreach ($line in $Lines) {
        if ($line -match '^\s*a comma-separated list in parentheses of specific rights:') {
            $inSpecificRights = $true
            continue
        }

        if (-not $inSpecificRights) {
            continue
        }

        if ($line -match '^\s*inheritance rights may precede either form') {
            break
        }

        if ($line -match '^\s*([A-Z]+)\s+-') {
            $permissions.Add($matches[1])
        }
    }

    @($permissions | Sort-Object -Unique)
}

function Get-IcaclsInheritanceFlagsFromLines {
    param([string[]]$Lines)

    $flags = New-Object System.Collections.Generic.List[string]
    $inInheritanceFlags = $false

    foreach ($line in $Lines) {
        if ($line -match '^\s*inheritance rights may precede either form') {
            $inInheritanceFlags = $true
            continue
        }

        if (-not $inInheritanceFlags) {
            continue
        }

        if ($line -match '^\s*Examples:') {
            break
        }

        if ($line -match '^\s*(\([A-Z]+\))\s+-') {
            $flags.Add($matches[1])
        }
    }

    @($flags | Sort-Object -Unique)
}

function Initialize-IcaclsCompletionCatalog {
    if ($script:IcaclsCompletionCatalog.Initialized) {
        return
    }

    $helpLines = Invoke-IcaclsHelpText
    if (-not $helpLines -or $helpLines.Count -eq 0) {
        $script:IcaclsCompletionCatalog.Initialized = $true
        return
    }

    $commands = @()
    $modifyOptions = @()
    $commandOptionsByKey = @{}
    $syntaxBlocks = Get-IcaclsSyntaxBlocks -Lines $helpLines

    foreach ($block in $syntaxBlocks) {
        $blockText = ($block -join ' ')
        $tokens = @(Get-IcaclsTokensFromText -Text $blockText)
        if ($tokens.Count -eq 0) {
            continue
        }

        $mainCommand = Get-IcaclsMainCommandFromTokens -Tokens $tokens
        if ($mainCommand) {
            $commands += $mainCommand
            $commandOptionsByKey[$mainCommand.ToLowerInvariant()] = @(
                $tokens |
                    Where-Object { $_ -ne $mainCommand } |
                    Sort-Object -Unique
            )
            continue
        }

        $modifyOptions += $tokens
    }

    $commonOptions = @(Get-IcaclsCommonOptionsFromLines -Lines $helpLines)
    $detailTokens = @(Get-IcaclsTokensFromText -Text ($helpLines -join ' '))
    foreach ($token in $detailTokens) {
        if ($token -like '/inheritance:*') {
            $modifyOptions += $token
        }
    }

    $script:IcaclsCompletionCatalog.Commands = @($commands | Sort-Object -Unique)
    $script:IcaclsCompletionCatalog.CommandOptionsByKey = $commandOptionsByKey
    $script:IcaclsCompletionCatalog.CommonOptions = $commonOptions
    $script:IcaclsCompletionCatalog.ModifyOptions = @(
        $modifyOptions |
            Where-Object {
                ($script:IcaclsCompletionCatalog.Commands -notcontains $_) -and
                ($commonOptions -notcontains $_)
            } |
            Sort-Object -Unique
    )
    $script:IcaclsCompletionCatalog.IntegrityLevels = @(Get-IcaclsIntegrityLevelsFromLines -Lines $helpLines)
    $script:IcaclsCompletionCatalog.SimplePermissions = @(Get-IcaclsSimplePermissionsFromLines -Lines $helpLines)
    $script:IcaclsCompletionCatalog.SpecificPermissions = @(Get-IcaclsSpecificPermissionsFromLines -Lines $helpLines)
    $script:IcaclsCompletionCatalog.InheritanceFlags = @(Get-IcaclsInheritanceFlagsFromLines -Lines $helpLines)
    $script:IcaclsCompletionCatalog.Initialized = $true
}

function ConvertTo-IcaclsQuotedPath {
    param([string]$Path)

    if ($Path -match '\s' -and -not ($Path.StartsWith('"') -and $Path.EndsWith('"'))) {
        return '"' + $Path + '"'
    }

    $Path
}

function Get-IcaclsPathCompletions {
    param([string]$InputPath)

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    $parent = Split-Path -Path $cleanInput -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) {
        $parent = '.'
    }

    $leaf = Split-Path -Path $cleanInput -Leaf
    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }

    $items = Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue
    $items | ForEach-Object { ConvertTo-IcaclsQuotedPath -Path $_.FullName }
}

function New-IcaclsCompletionResult {
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

function Get-IcaclsCurrentToken {
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

function Get-IcaclsTokensBeforeCurrent {
    param(
        [string[]]$Tokens,
        [string]$CurrentWord,
        [bool]$HasTrailingSpace
    )

    if ($HasTrailingSpace) {
        return @($Tokens)
    }

    if (-not $Tokens -or $Tokens.Count -eq 0) {
        return @()
    }

    if (-not [string]::IsNullOrEmpty($CurrentWord)) {
        for ($suffixLength = 1; $suffixLength -le $Tokens.Count; $suffixLength++) {
            $suffix = (@($Tokens | Select-Object -Last $suffixLength) -join '')
            if ($suffix -eq $CurrentWord) {
                $prefixLength = $Tokens.Count - $suffixLength
                if ($prefixLength -le 0) {
                    return @()
                }

                return @($Tokens | Select-Object -First $prefixLength)
            }
        }
    }

    if ($Tokens.Count -gt 1) {
        return @($Tokens | Select-Object -First ($Tokens.Count - 1))
    }

    @()
}

function Get-IcaclsActiveCommand {
    param(
        [string[]]$Tokens,
        [string[]]$KnownCommands
    )

    $known = @{}
    foreach ($command in $KnownCommands) {
        $known[$command.ToLowerInvariant()] = $command
    }

    foreach ($token in $Tokens) {
        $lookup = $token.ToLowerInvariant()
        if ($known.ContainsKey($lookup)) {
            return $known[$lookup]
        }
    }

    $null
}

function Test-IcaclsHasModifyOperation {
    param([string[]]$Tokens)

    foreach ($token in $Tokens) {
        if ($script:IcaclsCompletionCatalog.ModifyOptions -contains $token) {
            return $true
        }
    }

    $false
}

function Get-IcaclsExpectedValueOption {
    param([string[]]$TokensBeforeCurrent)

    if (-not $TokensBeforeCurrent -or $TokensBeforeCurrent.Count -eq 0) {
        return $null
    }

    $lastToken = $TokensBeforeCurrent[-1].ToLowerInvariant()
    switch ($lastToken) {
        '/save' { return '/save' }
        '/restore' { return '/restore' }
        '/setowner' { return '/setowner' }
        '/findsid' { return '/findsid' }
        '/grant' { return '/grant' }
        '/grant:r' { return '/grant:r' }
        '/deny' { return '/deny' }
        '/remove' { return '/remove' }
        '/remove:g' { return '/remove:g' }
        '/remove:d' { return '/remove:d' }
        '/setintegritylevel' { return '/setintegritylevel' }
        '/substitute' { return '/substitute' }
        default { return $null }
    }
}

function Get-IcaclsInlineOptionCompletions {
    param([string]$WordToComplete)

    if ($WordToComplete -match '^(?i)/inheritance:([^\s]*)$') {
        $valuePrefix = $matches[1]
        return @('e', 'd', 'r') |
            Where-Object { $_ -like "$valuePrefix*" } |
            ForEach-Object { "/inheritance:$_" }
    }

    if ($WordToComplete -match '^(?i)/remove:([^\s]*)$') {
        $valuePrefix = $matches[1]
        return @('g', 'd') |
            Where-Object { $_ -like "$valuePrefix*" } |
            ForEach-Object { "/remove:$_" }
    }

    if ($WordToComplete -match '^(?i)/grant:([^\s]*)$') {
        $valuePrefix = $matches[1]
        return @('r') |
            Where-Object { $_ -like "$valuePrefix*" } |
            ForEach-Object { "/grant:$_" }
    }

    @()
}

function Get-IcaclsExpandedOptionValueCompletions {
    param([string]$WordToComplete)

    if ($WordToComplete.Equals('/setintegritylevel', [System.StringComparison]::OrdinalIgnoreCase)) {
        return Get-IcaclsIntegrityLevelCompletions -WordToComplete '' |
            ForEach-Object { "/setintegritylevel $_" }
    }

    @()
}

function Get-IcaclsIntegrityLevelCompletions {
    param([string]$WordToComplete)

    $prefixes = @('', '(OI)', '(CI)', '(OI)(CI)', '(CI)(OI)')
    $values = foreach ($prefix in $prefixes) {
        foreach ($level in $script:IcaclsCompletionCatalog.IntegrityLevels) {
            "$prefix$level"
        }
    }

    $values |
        Sort-Object -Unique |
        Where-Object { $_ -like "$WordToComplete*" }
}

function Get-IcaclsPermissionCompletions {
    param([string]$WordToComplete)

    if ([string]::IsNullOrWhiteSpace($WordToComplete)) {
        return @()
    }

    $isQuoted = $WordToComplete.StartsWith('"')
    $normalizedWord = $WordToComplete.Trim('"')
    if (-not $normalizedWord.Contains(':')) {
        return @()
    }

    $parts = $normalizedWord -split ':', 2
    $identity = $parts[0]
    $permissionPrefix = $parts[1]

    if ([string]::IsNullOrEmpty($identity)) {
        return @()
    }

    $completions = if ($permissionPrefix.StartsWith('(')) {
        @(Get-IcaclsParenthesizedPermissionCompletions -Identity $identity -PermissionPrefix $permissionPrefix)
    } else {
        @(
            $script:IcaclsCompletionCatalog.SimplePermissions |
                Where-Object { $_ -like "$permissionPrefix*" } |
                ForEach-Object { "${identity}:$_" }
        )
    }

    if ($isQuoted) {
        return $completions | ForEach-Object { '"' + $_ + '"' }
    }

    $completions
}

function Get-IcaclsParenthesizedPermissionCompletions {
    param(
        [string]$Identity,
        [string]$PermissionPrefix
    )

    $remaining = $PermissionPrefix
    $inheritancePrefix = ''
    $usedFlags = @{}

    while ($remaining -match '^\(([A-Z]+)\)') {
        $candidateFlag = "($($matches[1]))"
        if ($script:IcaclsCompletionCatalog.InheritanceFlags -notcontains $candidateFlag) {
            break
        }

        $inheritancePrefix += $candidateFlag
        $usedFlags[$candidateFlag.ToUpperInvariant()] = $true
        $remaining = $remaining.Substring($matches[0].Length)
    }

    $suggestions = New-Object System.Collections.Generic.List[string]

    if ($remaining.Length -eq 0) {
        foreach ($flag in $script:IcaclsCompletionCatalog.InheritanceFlags) {
            if (-not $usedFlags.ContainsKey($flag.ToUpperInvariant())) {
                $suggestions.Add("${Identity}:${inheritancePrefix}$flag")
            }
        }

        foreach ($permission in $script:IcaclsCompletionCatalog.SimplePermissions) {
            $suggestions.Add("${Identity}:${inheritancePrefix}$permission")
        }

        foreach ($permission in $script:IcaclsCompletionCatalog.SpecificPermissions) {
            $suggestions.Add("${Identity}:${inheritancePrefix}($permission)")
        }

        return @($suggestions | Sort-Object -Unique)
    }

    if ($remaining -match '^\(([A-Z]*)$') {
        $partial = $matches[1]

        foreach ($flag in $script:IcaclsCompletionCatalog.InheritanceFlags) {
            if ($usedFlags.ContainsKey($flag.ToUpperInvariant())) {
                continue
            }

            if ($flag -like "($partial*)") {
                $suggestions.Add("${Identity}:${inheritancePrefix}$flag")
            }
        }

        $specificPrefix = "($partial"
        foreach ($permission in $script:IcaclsCompletionCatalog.SpecificPermissions) {
            if ($specificPrefix -eq '(' -or $permission -like "$partial*") {
                $suggestions.Add("${Identity}:${inheritancePrefix}($permission)")
            }
        }

        return @($suggestions | Sort-Object -Unique)
    }

    if ($remaining -match '^\(([A-Z,]*)$') {
        $content = $matches[1]
        $segments = @($content.Split(',', [System.StringSplitOptions]::None))
        $completedSegments = @()
        if ($segments.Count -gt 1) {
            $completedSegments = @($segments | Select-Object -First ($segments.Count - 1))
        }

        $currentSegment = $segments[-1]
        $usedPermissions = @{}
        foreach ($segment in $completedSegments) {
            if (-not [string]::IsNullOrWhiteSpace($segment)) {
                $usedPermissions[$segment.ToUpperInvariant()] = $true
            }
        }

        $prefixText = if ($completedSegments.Count -gt 0) {
            '(' + (($completedSegments -join ',') + ',')
        } else {
            '('
        }

        foreach ($permission in $script:IcaclsCompletionCatalog.SpecificPermissions) {
            if ($usedPermissions.ContainsKey($permission.ToUpperInvariant())) {
                continue
            }

            if ($permission -like "$currentSegment*") {
                $suggestions.Add("${Identity}:${inheritancePrefix}${prefixText}$permission)")
            }
        }

        return @($suggestions | Sort-Object -Unique)
    }

    $script:IcaclsCompletionCatalog.SimplePermissions |
        Where-Object { $_ -like "$remaining*" } |
        ForEach-Object { "${Identity}:${inheritancePrefix}$_" }
}

Register-ArgumentCompleter -Native -CommandName 'icacls', 'icacls.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Initialize-IcaclsCompletionCatalog

    $allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokens = @($allTokens | Select-Object -Skip 1)
    $line = $commandAst.ToString()
    $rawCurrentWord = $wordToComplete
    $lineCurrentWord = Get-IcaclsCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
    $currentWord = if (
        (-not [string]::IsNullOrEmpty($lineCurrentWord)) -and
        (
            [string]::IsNullOrWhiteSpace($wordToComplete) -or
            ($lineCurrentWord.Length -gt $wordToComplete.Length)
        )
    ) {
        $lineCurrentWord
    } else {
        $wordToComplete
    }
    $hasTrailingSpace = ($line -match '\s$') -or ($cursorPosition -gt $line.Length)
    $tokensBeforeCurrent = @(Get-IcaclsTokensBeforeCurrent -Tokens $tokens -CurrentWord $currentWord -HasTrailingSpace $hasTrailingSpace)
    $permissionIdentityPrefix = $null
    if (
        (-not [string]::IsNullOrWhiteSpace($rawCurrentWord)) -and
        (-not $rawCurrentWord.Contains(':')) -and
        ($currentWord.Contains(':')) -and
        ($tokens.Count -ge 2) -and
        $tokens[-2].EndsWith(':') -and
        (($tokens[-2] + $tokens[-1]) -eq $currentWord)
    ) {
        $permissionIdentityPrefix = $tokens[-2]
    }

    $activeCommand = Get-IcaclsActiveCommand -Tokens $tokensBeforeCurrent -KnownCommands $script:IcaclsCompletionCatalog.Commands
    $hasModifyOperation = Test-IcaclsHasModifyOperation -Tokens $tokensBeforeCurrent
    $expectedValueOption = Get-IcaclsExpectedValueOption -TokensBeforeCurrent $tokensBeforeCurrent
    $hasTargetPath = ($tokensBeforeCurrent.Count -gt 0) -and (-not $tokensBeforeCurrent[0].StartsWith('/'))

    $inlineOptionCompletions = @(Get-IcaclsInlineOptionCompletions -WordToComplete $currentWord)
    if ($inlineOptionCompletions.Count -gt 0) {
        return $inlineOptionCompletions | ForEach-Object {
            New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
        }
    }

    $expandedOptionValueCompletions = @(Get-IcaclsExpandedOptionValueCompletions -WordToComplete $currentWord)
    if ($expandedOptionValueCompletions.Count -gt 0) {
        return $expandedOptionValueCompletions | ForEach-Object {
            New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
        }
    }

    if ($expectedValueOption) {
        switch ($expectedValueOption) {
            '/save' {
                return Get-IcaclsPathCompletions -InputPath $currentWord | ForEach-Object {
                    New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                }
            }
            '/restore' {
                return Get-IcaclsPathCompletions -InputPath $currentWord | ForEach-Object {
                    New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                }
            }
            '/grant' {
                $completionText = @(Get-IcaclsPermissionCompletions -WordToComplete $currentWord)
                if ($permissionIdentityPrefix) {
                    $completionText = @(
                        $completionText | ForEach-Object {
                            if ($_.StartsWith($permissionIdentityPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $_.Substring($permissionIdentityPrefix.Length)
                            } else {
                                $_
                            }
                        }
                    )
                }

                return $completionText | ForEach-Object {
                    New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                }
            }
            '/grant:r' {
                $completionText = @(Get-IcaclsPermissionCompletions -WordToComplete $currentWord)
                if ($permissionIdentityPrefix) {
                    $completionText = @(
                        $completionText | ForEach-Object {
                            if ($_.StartsWith($permissionIdentityPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $_.Substring($permissionIdentityPrefix.Length)
                            } else {
                                $_
                            }
                        }
                    )
                }

                return $completionText | ForEach-Object {
                    New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                }
            }
            '/deny' {
                $completionText = @(Get-IcaclsPermissionCompletions -WordToComplete $currentWord)
                if ($permissionIdentityPrefix) {
                    $completionText = @(
                        $completionText | ForEach-Object {
                            if ($_.StartsWith($permissionIdentityPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $_.Substring($permissionIdentityPrefix.Length)
                            } else {
                                $_
                            }
                        }
                    )
                }

                return $completionText | ForEach-Object {
                    New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                }
            }
            '/setintegritylevel' {
                return Get-IcaclsIntegrityLevelCompletions -WordToComplete $currentWord | ForEach-Object {
                    New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                }
            }
            default {
                return @()
            }
        }
    }

    if (-not $hasTargetPath) {
        if ([string]::IsNullOrWhiteSpace($currentWord) -or -not $currentWord.StartsWith('/')) {
            return Get-IcaclsPathCompletions -InputPath $currentWord | ForEach-Object {
                New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
            }
        }

        return @('/?') |
            Where-Object { $_ -like "$currentWord*" } |
            ForEach-Object {
                New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
            }
    }

    if (-not [string]::IsNullOrWhiteSpace($currentWord) -and -not $currentWord.StartsWith('/')) {
        return Get-IcaclsPathCompletions -InputPath $currentWord | ForEach-Object {
            New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
        }
    }

    if ($activeCommand) {
        $optionKey = $activeCommand.ToLowerInvariant()
        $suggestions = @($script:IcaclsCompletionCatalog.CommonOptions)
        if ($script:IcaclsCompletionCatalog.CommandOptionsByKey.ContainsKey($optionKey)) {
            $suggestions += $script:IcaclsCompletionCatalog.CommandOptionsByKey[$optionKey]
        }
    } elseif ($hasModifyOperation) {
        $suggestions = @($script:IcaclsCompletionCatalog.ModifyOptions + $script:IcaclsCompletionCatalog.CommonOptions)
    } else {
        $suggestions = @(
            $script:IcaclsCompletionCatalog.Commands +
            $script:IcaclsCompletionCatalog.ModifyOptions +
            $script:IcaclsCompletionCatalog.CommonOptions +
            '/?'
        )
    }

    $suggestions |
        Sort-Object -Unique |
        Where-Object { $_ -like "$currentWord*" } |
        ForEach-Object {
            New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
        }
}
