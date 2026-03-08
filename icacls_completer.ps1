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

    if ([string]::IsNullOrWhiteSpace($WordToComplete) -or -not $WordToComplete.Contains(':')) {
        return @()
    }

    $parts = $WordToComplete -split ':', 2
    $identity = $parts[0]
    $permissionPrefix = $parts[1]

    $script:IcaclsCompletionCatalog.SimplePermissions |
        Where-Object { $_ -like "$permissionPrefix*" } |
        ForEach-Object { "${identity}:$_" }
}

Register-ArgumentCompleter -Native -CommandName 'icacls', 'icacls.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Initialize-IcaclsCompletionCatalog

    $allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokens = @($allTokens | Select-Object -Skip 1)
    $line = $commandAst.ToString()
    $currentWord = if ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        Get-IcaclsCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
    } else {
        $wordToComplete
    }
    $hasTrailingSpace = ($line -match '\s$') -or ($cursorPosition -gt $line.Length)

    if ($hasTrailingSpace) {
        $tokensBeforeCurrent = @($tokens)
    } elseif ($tokens.Count -gt 1) {
        $tokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
    } else {
        $tokensBeforeCurrent = @()
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
                return Get-IcaclsPermissionCompletions -WordToComplete $currentWord | ForEach-Object {
                    New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                }
            }
            '/grant:r' {
                return Get-IcaclsPermissionCompletions -WordToComplete $currentWord | ForEach-Object {
                    New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
                }
            }
            '/deny' {
                return Get-IcaclsPermissionCompletions -WordToComplete $currentWord | ForEach-Object {
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