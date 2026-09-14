# icacls tab completion for PowerShell
# Builds completion data from icacls built-in help.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name IcaclsCompletionCatalog -Scope Script -ErrorAction Ignore)) {
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
        PreCommandOptions   = @()
        Identities          = @()
        IdentitiesBuilt     = $false
        AclIdentityCache    = @{}
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

    # Keep a trailing '[...]' group so '/grant[:r]' and '/remove[:g|:d]' reach Expand-IcaclsHelpToken intact.
    $tokens = foreach ($match in [regex]::Matches($Text, '(?<!\w)(/[A-Za-z][A-Za-z0-9]*(?:\[[^\]]*\])?(?::[^\s\]]+)?)')) {
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
        # Syntax blocks start at column 0 in upper case; the indented lower-case
        # 'icacls ...' example lines must not overwrite them.
        if ($line -match '^Examples:') {
            break
        }

        if ($line -cmatch '^ICACLS\s') {
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

        # Syntax continuation lines start with '[' or '/'; the description lines that
        # follow start with a word and may mention other switches ("for later use with /restore").
        if ($line -match '^\s+[\[/]') {
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
    $preCommandOptions = @()
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

            # Options documented before the command ('[/substitute SidOld SidNew] /restore')
            # are typed before it, so they must be offered while no command is active.
            $mainIndex = $blockText.IndexOf($mainCommand, [System.StringComparison]::OrdinalIgnoreCase)
            if ($mainIndex -gt 0) {
                $preCommandOptions += @(Get-IcaclsTokensFromText -Text $blockText.Substring(0, $mainIndex))
            }
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
    $script:IcaclsCompletionCatalog.PreCommandOptions = @($preCommandOptions | Sort-Object -Unique)
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

    # A trailing separator means "list this directory"; Split-Path -Leaf would return the directory itself.
    $parent = '.'
    $leaf = ''
    if (-not [string]::IsNullOrWhiteSpace($cleanInput)) {
        if ($cleanInput.EndsWith('\') -or $cleanInput.EndsWith('/')) {
            $parent = $cleanInput
        } else {
            $candidateParent = Split-Path -Path $cleanInput -Parent
            if (-not [string]::IsNullOrWhiteSpace($candidateParent)) {
                $parent = $candidateParent
            }

            $leaf = Split-Path -Path $cleanInput -Leaf
        }
    }

    $items = @(Get-ChildItem -LiteralPath $parent -ErrorAction Ignore | Where-Object {
        [string]::IsNullOrWhiteSpace($leaf) -or $_.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)
    })
    $items | ForEach-Object { ConvertTo-IcaclsQuotedPath -Path $_.FullName }
}

function Get-IcaclsIdentityList {
    param([string]$OperandPath)

    # Principals a Sid operand can name: well-known accounts, the current user, local
    # users and groups (built once per session), plus whatever the operand's ACL already
    # references (cached per path for 30 s). All read-only local state.
    if (-not $script:IcaclsCompletionCatalog.IdentitiesBuilt) {
        $names = New-Object System.Collections.Generic.List[string]
        foreach ($name in @('Everyone', 'SYSTEM', 'Administrators', 'Users', 'Authenticated Users', 'CREATOR OWNER',
                'NT AUTHORITY\SYSTEM', 'NT AUTHORITY\LOCAL SERVICE', 'NT AUTHORITY\NETWORK SERVICE',
                'NT SERVICE\TrustedInstaller', 'BUILTIN\Administrators', 'BUILTIN\Users')) {
            $names.Add($name)
        }

        if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
            $names.Add($env:USERNAME)
            if (-not [string]::IsNullOrWhiteSpace($env:USERDOMAIN)) {
                $names.Add($env:USERDOMAIN + '\' + $env:USERNAME)
            }
        }

        try {
            foreach ($account in @(Get-LocalUser -ErrorAction Ignore) + @(Get-LocalGroup -ErrorAction Ignore)) {
                if ($account -and -not [string]::IsNullOrWhiteSpace($account.Name)) {
                    $names.Add($account.Name)
                }
            }
        } catch {
            Write-Debug "icacls local account enumeration failed: $($_.Exception.Message)"
        }

        $script:IcaclsCompletionCatalog.Identities = @($names | Sort-Object -Unique)
        $script:IcaclsCompletionCatalog.IdentitiesBuilt = $true
    }

    $aclNames = @()
    if (-not [string]::IsNullOrWhiteSpace($OperandPath)) {
        $cleanPath = $OperandPath.Trim('"')
        $cache = $script:IcaclsCompletionCatalog.AclIdentityCache
        $entry = if ($cache.ContainsKey($cleanPath)) { $cache[$cleanPath] } else { $null }
        if ($entry -and ((Get-Date) - $entry.UpdatedAt).TotalSeconds -lt 30) {
            $aclNames = @($entry.Names)
        } else {
            try {
                $acl = Get-Acl -LiteralPath $cleanPath -ErrorAction Ignore
                if ($acl) {
                    $aclNames = @($acl.Access | ForEach-Object { $_.IdentityReference.Value } | Where-Object { $_ } | Sort-Object -Unique)
                }
            } catch {
                Write-Debug "icacls ACL read failed for '$cleanPath': $($_.Exception.Message)"
            }

            $cache[$cleanPath] = [pscustomobject]@{ UpdatedAt = Get-Date; Names = @($aclNames) }
        }
    }

    @(@($aclNames) + @($script:IcaclsCompletionCatalog.Identities) | Sort-Object -Unique)
}

function Get-IcaclsIdentityCompletions {
    param(
        [string]$WordToComplete,
        [string]$OperandPath,
        [switch]$PermissionStage
    )

    # Sid operands (/setowner, /findsid, /remove, /substitute) complete as the bare
    # principal; the Sid:perm slots (/grant, /deny) complete as 'Identity:' so the
    # permission engine takes over after the colon.
    $word = if ($null -eq $WordToComplete) { '' } else { $WordToComplete }
    $isQuoted = $word.StartsWith('"')
    $prefix = $word.Trim('"')

    foreach ($identity in @(Get-IcaclsIdentityList -OperandPath $OperandPath)) {
        $leafName = if ($identity.Contains('\')) { $identity.Substring($identity.LastIndexOf('\') + 1) } else { $identity }
        if (-not [string]::IsNullOrEmpty($prefix) -and
            -not $identity.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not $leafName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $needsQuote = $isQuoted -or ($identity -match '\s')
        if ($PermissionStage) {
            # Leave the quote open so the permission part can still be typed inside it.
            if ($needsQuote) { '"' + $identity + ':' } else { $identity + ':' }
        } else {
            if ($needsQuote) { '"' + $identity + '"' } else { $identity }
        }
    }
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

function Get-IcaclsCursorContext {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # Locate the element under the cursor by extent (offsets are absolute), then pull in
    # any elements glued to it without whitespace (the parser splits 'Users:(D' into
    # 'Users:' and '(D'). Everything before that group is already typed.
    $elements = @($CommandAst.CommandElements | Select-Object -Skip 1)
    $currentIndex = -1
    for ($index = 0; $index -lt $elements.Count; $index++) {
        $extent = $elements[$index].Extent
        if ($extent.StartOffset -lt $CursorPosition -and $extent.EndOffset -ge $CursorPosition) {
            $currentIndex = $index
            break
        }
    }

    if ($currentIndex -lt 0) {
        return [pscustomobject]@{
            TokensBeforeCurrent = @($elements | Where-Object { $_.Extent.EndOffset -le $CursorPosition } | ForEach-Object { $_.Extent.Text })
            CurrentGroup        = @()
        }
    }

    $startIndex = $currentIndex
    while ($startIndex -gt 0 -and $elements[$startIndex - 1].Extent.EndOffset -eq $elements[$startIndex].Extent.StartOffset) {
        $startIndex--
    }

    [pscustomobject]@{
        TokensBeforeCurrent = @($elements | Select-Object -First $startIndex | ForEach-Object { $_.Extent.Text })
        CurrentGroup        = @($elements[$startIndex..$currentIndex] | ForEach-Object { $_.Extent.Text })
    }
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

    # /substitute takes two Sid operands (SidOld SidNew).
    if ($TokensBeforeCurrent.Count -ge 2 -and $TokensBeforeCurrent[-2] -eq '/substitute' -and -not $TokensBeforeCurrent[-1].StartsWith('/')) {
        return '/substitute'
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
            Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($valuePrefix) + '*') } |
            ForEach-Object { "/inheritance:$_" }
    }

    if ($WordToComplete -match '^(?i)/remove:([^\s]*)$') {
        $valuePrefix = $matches[1]
        return @('g', 'd') |
            Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($valuePrefix) + '*') } |
            ForEach-Object { "/remove:$_" }
    }

    if ($WordToComplete -match '^(?i)/grant:([^\s]*)$') {
        $valuePrefix = $matches[1]
        return @('r') |
            Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($valuePrefix) + '*') } |
            ForEach-Object { "/grant:$_" }
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
        Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*') }
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
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($permissionPrefix) + '*') } |
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
            if ($specificPrefix -eq '(' -or $permission -like ([System.Management.Automation.WildcardPattern]::Escape($partial) + '*')) {
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

            if ($permission -like ([System.Management.Automation.WildcardPattern]::Escape($currentSegment) + '*')) {
                $suggestions.Add("${Identity}:${inheritancePrefix}${prefixText}$permission)")
            }
        }

        return @($suggestions | Sort-Object -Unique)
    }

    $script:IcaclsCompletionCatalog.SimplePermissions |
        Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($remaining) + '*') } |
        ForEach-Object { "${Identity}:${inheritancePrefix}$_" }
}

Register-ArgumentCompleter -Native -CommandName 'icacls', 'icacls.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Initialize-IcaclsCompletionCatalog

    $line = $commandAst.ToString()
    $rawCurrentWord = $wordToComplete
    $lineCurrentWord = Get-IcaclsCurrentToken -Line $line -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    $currentWord = if (
        (-not [string]::IsNullOrEmpty($lineCurrentWord)) -and
        (-not [string]::IsNullOrWhiteSpace($wordToComplete)) -and
        ($lineCurrentWord.Length -gt $wordToComplete.Length)
    ) {
        $lineCurrentWord
    } else {
        $wordToComplete
    }

    $cursorContext = Get-IcaclsCursorContext -CommandAst $commandAst -CursorPosition $cursorPosition
    $tokensBeforeCurrent = @($cursorContext.TokensBeforeCurrent)
    $currentGroup = @($cursorContext.CurrentGroup)
    $permissionIdentityPrefix = $null
    if (
        (-not [string]::IsNullOrWhiteSpace($rawCurrentWord)) -and
        (-not $rawCurrentWord.Contains(':')) -and
        ($currentWord.Contains(':')) -and
        ($currentGroup.Count -ge 2) -and
        $currentGroup[0].EndsWith(':')
    ) {
        $permissionIdentityPrefix = $currentGroup[0]
    }

    $activeCommand = Get-IcaclsActiveCommand -Tokens $tokensBeforeCurrent -KnownCommands $script:IcaclsCompletionCatalog.Commands
    $hasModifyOperation = Test-IcaclsHasModifyOperation -Tokens $tokensBeforeCurrent
    $expectedValueOption = Get-IcaclsExpectedValueOption -TokensBeforeCurrent $tokensBeforeCurrent
    $hasTargetPath = ($tokensBeforeCurrent.Count -gt 0) -and (-not $tokensBeforeCurrent[0].StartsWith('/'))
    $operandPath = if ($hasTargetPath) { $tokensBeforeCurrent[0] } else { '' }

    $inlineOptionCompletions = @(Get-IcaclsInlineOptionCompletions -WordToComplete $currentWord)
    if ($inlineOptionCompletions.Count -gt 0) {
        return $inlineOptionCompletions | ForEach-Object {
            New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
        }
    }

    if ($expectedValueOption) {
        # Sid:perm slots complete the principal first, then hand over to the permission engine.
        if ($expectedValueOption -in @('/grant', '/grant:r', '/deny') -and -not $currentWord.Trim('"').Contains(':')) {
            return @(Get-IcaclsIdentityCompletions -WordToComplete $currentWord -OperandPath $operandPath -PermissionStage) | ForEach-Object {
                New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
            }
        }

        if ($expectedValueOption -in @('/setowner', '/findsid', '/remove', '/remove:g', '/remove:d', '/substitute')) {
            return @(Get-IcaclsIdentityCompletions -WordToComplete $currentWord -OperandPath $operandPath) | ForEach-Object {
                New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterValue' -ToolTip $_
            }
        }

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
            Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*') } |
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
            $script:IcaclsCompletionCatalog.PreCommandOptions +
            $script:IcaclsCompletionCatalog.ModifyOptions +
            $script:IcaclsCompletionCatalog.CommonOptions +
            '/?'
        )
    }

    $suggestions |
        Sort-Object -Unique |
        Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*') } |
        ForEach-Object {
            New-IcaclsCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
        }
}
