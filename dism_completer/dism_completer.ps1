# DISM tab completion for PowerShell
# Builds completion data from the DISM built-in help system.
# Usage: . .\dism_completer.ps1

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name DismCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DismCompletionCatalog = @{
        Initialized       = $false
        Commands          = @()
        GlobalSwitches    = @()
        HelpTokensByKey   = @{}
        ValuesByOptionKey = @{}
    }
}

function Invoke-DismHelpText {
    param([string[]]$Arguments)

    try {
        & dism @Arguments '/?' 2>$null
    } catch {
        @()
    }
}

function Get-DismSwitchTokensFromLines {
    param([string[]]$Lines)

    $tokens = foreach ($line in $Lines) {
        foreach ($match in [regex]::Matches($line, '(?<!\w)(/[A-Za-z][A-Za-z0-9\-]*:?)(?=[\s\]\}\|,]|$|<)')) {
            $match.Groups[1].Value
        }
    }

    $tokens | Sort-Object -Unique
}

function Get-DismOptionValueMapFromLines {
    param([string[]]$Lines)

    $result = @{}

    # Pattern like /Option:{A | B}
    foreach ($line in $Lines) {
        foreach ($match in [regex]::Matches($line, '(?<!\w)(/[A-Za-z][A-Za-z0-9\-]*:?)\{([^}]+)\}')) {
            $optionPrefix = $match.Groups[1].Value
            if (-not $optionPrefix.EndsWith(':')) {
                $optionPrefix += ':'
            }

            $values = $match.Groups[2].Value -split '\|' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -match '^[A-Za-z0-9_.\-]+$' }

            if ($values.Count -gt 0) {
                if (-not $result.ContainsKey($optionPrefix)) {
                    $result[$optionPrefix] = @()
                }
                $result[$optionPrefix] += $values
            }
        }
    }

    # Pattern like /Format:<...> with accepted values listed below as "Value = Description"
    $currentOptionPrefix = $null
    foreach ($line in $Lines) {
        if ($line -match '^\s*(/[A-Za-z][A-Za-z0-9\-]*):\s*<[^>]+>') {
            $currentOptionPrefix = "$($matches[1]):"
            if (-not $result.ContainsKey($currentOptionPrefix)) {
                $result[$currentOptionPrefix] = @()
            }
            continue
        }

        if ($line -match '^\s*Examples?:') {
            $currentOptionPrefix = $null
            continue
        }

        if ($line -match '^\s*([A-Za-z0-9_.\-]+)\s*=') {
            if ($currentOptionPrefix) {
                $result[$currentOptionPrefix] += $matches[1]
            }
            continue
        }

    }

    foreach ($key in @($result.Keys)) {
        $result[$key] = $result[$key] | Sort-Object -Unique
    }

    $result
}

function Update-DismCatalogFromHelp {
    param(
        [string]$Key,
        [string[]]$HelpLines
    )

    if (-not $HelpLines -or $HelpLines.Count -eq 0) {
        return
    }

    $normalizedKey = $Key.ToLowerInvariant()

    $tokens = Get-DismSwitchTokensFromLines -Lines $HelpLines
    $script:DismCompletionCatalog.HelpTokensByKey[$normalizedKey] = $tokens

    $valueMap = Get-DismOptionValueMapFromLines -Lines $HelpLines
    foreach ($optionPrefix in $valueMap.Keys) {
        $optionKey = $optionPrefix.ToLowerInvariant()
        if (-not $script:DismCompletionCatalog.ValuesByOptionKey.ContainsKey($optionKey)) {
            $script:DismCompletionCatalog.ValuesByOptionKey[$optionKey] = @()
        }

        $script:DismCompletionCatalog.ValuesByOptionKey[$optionKey] += $valueMap[$optionPrefix]
        $script:DismCompletionCatalog.ValuesByOptionKey[$optionKey] =
            $script:DismCompletionCatalog.ValuesByOptionKey[$optionKey] | Sort-Object -Unique
    }
}

function Initialize-DismCompletionCatalog {
    if ($script:DismCompletionCatalog.Initialized) {
        return
    }

    $topHelp = Invoke-DismHelpText
    if (-not $topHelp -or $topHelp.Count -eq 0) {
        $script:DismCompletionCatalog.Initialized = $true
        return
    }

    Update-DismCatalogFromHelp -Key '__TOP__' -HelpLines $topHelp

    $commands = @()
    $globalRoots = @()
    $section = ''

    foreach ($line in $topHelp) {
        if ($line -match '^\s*([A-Z][A-Z\s]+):\s*$') {
            $section = $matches[1].Trim()
            continue
        }

        if ($line -match '^\s*(/[A-Za-z][A-Za-z0-9\-]+)\s+-') {
            $token = $matches[1]
            if ($section -like '*COMMANDS') {
                $commands += $token
            } elseif ($section -eq 'IMAGE SPECIFICATIONS' -or $section -eq 'DISM OPTIONS') {
                $globalRoots += $token
            }
        }
    }

    # Pull servicing command verbs available in /Online context.
    $onlineHelp = Invoke-DismHelpText -Arguments @('/Online')
    if ($onlineHelp -and $onlineHelp.Count -gt 0) {
        foreach ($line in $onlineHelp) {
            if ($line -match '^\s*(/[A-Za-z][A-Za-z0-9\-]+)\s+-') {
                $commands += $matches[1]
            }
        }
    }

    $script:DismCompletionCatalog.Commands = $commands | Sort-Object -Unique

    $globalSwitches = @($globalRoots)

    # Enrich global switches and value hints from each global option's own help.
    foreach ($root in ($globalRoots | Sort-Object -Unique)) {
        $optionHelp = Invoke-DismHelpText -Arguments @($root)
        if ($optionHelp -and $optionHelp.Count -gt 0) {
            Update-DismCatalogFromHelp -Key $root -HelpLines $optionHelp

            $rootWithColon = "${root}:"
            if ($script:DismCompletionCatalog.ValuesByOptionKey.ContainsKey($rootWithColon.ToLowerInvariant())) {
                $globalSwitches += $rootWithColon
            }
        }
    }

    $globalSwitches += $script:DismCompletionCatalog.HelpTokensByKey['__top__']

    # Remove command verbs from global switch list, keep only true options.
    $commandSet = @{}
    foreach ($command in $script:DismCompletionCatalog.Commands) {
        $commandSet[$command.ToLowerInvariant()] = $true
    }

    $script:DismCompletionCatalog.GlobalSwitches =
        ($globalSwitches |
            Where-Object { -not $commandSet.ContainsKey($_.ToLowerInvariant()) } |
            Sort-Object -Unique)

    $script:DismCompletionCatalog.Initialized = $true
}

function Update-DismCommandCatalog {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return
    }

    $key = $Command.ToLowerInvariant()
    if ($script:DismCompletionCatalog.HelpTokensByKey.ContainsKey($key)) {
        return
    }

    $help = Invoke-DismHelpText -Arguments @($Command)
    if ($help -and $help.Count -gt 0) {
        Update-DismCatalogFromHelp -Key $Command -HelpLines $help
    } else {
        $script:DismCompletionCatalog.HelpTokensByKey[$key] = @()
    }
}

function Get-DismActiveCommand {
    param(
        [string[]]$Tokens,
        [string[]]$KnownCommands
    )

    $knownSet = @{}
    foreach ($command in $KnownCommands) {
        $knownSet[$command.ToLowerInvariant()] = $command
    }

    foreach ($token in $Tokens) {
        $lookup = $token.ToLowerInvariant()
        if ($knownSet.ContainsKey($lookup)) {
            return $knownSet[$lookup]
        }
    }

    $null
}

function Get-DismOptionPrefixFromToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    if ($Token -match '^(/[A-Za-z][A-Za-z0-9\-]*:)') {
        return $matches[1]
    }

    $null
}

function Test-DismPathLikeOption {
    param([string]$OptionPrefix)

    if ([string]::IsNullOrWhiteSpace($OptionPrefix)) {
        return $false
    }

    $option = $OptionPrefix.TrimStart('/').TrimEnd(':')
    $option -match '(?i)(path|dir|file|image)$'
}

function Get-DismAllowedExtensionsForOption {
    param([string]$OptionPrefix)

    switch ($OptionPrefix.ToLowerInvariant()) {
        '/packagepath:' { return @('.cab', '.msu') }
        '/wimfile:' { return @('.wim', '.esd', '.swm') }
        '/imagefile:' { return @('.wim', '.esd', '.swm', '.ffu', '.vhd', '.vhdx') }
        '/sourceimagefile:' { return @('.wim', '.esd', '.swm', '.ffu', '.vhd', '.vhdx') }
        '/vhdfile:' { return @('.vhd', '.vhdx') }
        '/swmfile:' { return @('.swm') }
        default { return @() }
    }
}

function ConvertTo-DismQuotedPath {
    param([string]$Path)

    if ($Path -match '\s' -and -not ($Path.StartsWith('"') -and $Path.EndsWith('"'))) {
        return '"' + $Path + '"'
    }

    $Path
}

function Get-DismPathCompletions {
    param(
        [string]$InputPath,
        [string[]]$AllowedExtensions
    )

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    $parent = Split-Path -Path $cleanInput -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) {
        $parent = '.'
    }

    $leaf = Split-Path -Path $cleanInput -Leaf
    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }

    $items = Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue
    if ($AllowedExtensions -and $AllowedExtensions.Count -gt 0) {
        $items = $items | Where-Object {
            $_.PSIsContainer -or ($AllowedExtensions -contains $_.Extension.ToLowerInvariant())
        }
    }

    $items | ForEach-Object { ConvertTo-DismQuotedPath -Path $_.FullName }
}

Register-ArgumentCompleter -Native -CommandName 'dism' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Initialize-DismCompletionCatalog

    $allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokens = if ($allTokens.Count -gt 1) { @($allTokens[1..($allTokens.Count - 1)]) } else { @() }

    $activeCommand = Get-DismActiveCommand -Tokens $tokens -KnownCommands $script:DismCompletionCatalog.Commands
    if ($activeCommand) {
        Update-DismCommandCatalog -Command $activeCommand
    }

    $currentPrefix = Get-DismOptionPrefixFromToken -Token $wordToComplete
    if ($currentPrefix) {
        $currentPrefixKey = $currentPrefix.ToLowerInvariant()
        $optionValues = @()
        if ($script:DismCompletionCatalog.ValuesByOptionKey.ContainsKey($currentPrefixKey)) {
            $optionValues = $script:DismCompletionCatalog.ValuesByOptionKey[$currentPrefixKey]
        }

        if ($optionValues.Count -gt 0) {
            $typedValue = $wordToComplete.Substring($currentPrefix.Length)
            return $optionValues |
                Where-Object { $_ -like "$typedValue*" } |
                ForEach-Object { "$currentPrefix$_" }
        }

        if (Test-DismPathLikeOption -OptionPrefix $currentPrefix) {
            $typedPath = $wordToComplete.Substring($currentPrefix.Length)
            $allowed = Get-DismAllowedExtensionsForOption -OptionPrefix $currentPrefix
            $paths = Get-DismPathCompletions -InputPath $typedPath -AllowedExtensions $allowed
            return $paths | ForEach-Object { "$currentPrefix$_" }
        }
    }

    if ($wordToComplete.StartsWith('/')) {
        if ($activeCommand) {
            $suggestions = @($script:DismCompletionCatalog.GlobalSwitches)
            $cmdKey = $activeCommand.ToLowerInvariant()
            if ($script:DismCompletionCatalog.HelpTokensByKey.ContainsKey($cmdKey)) {
                $suggestions += $script:DismCompletionCatalog.HelpTokensByKey[$cmdKey]
            }
        } else {
            $suggestions = @($script:DismCompletionCatalog.Commands + $script:DismCompletionCatalog.GlobalSwitches)
        }

        return $suggestions |
            Sort-Object -Unique |
            Where-Object { $_ -like "$wordToComplete*" }
    }

    if ($wordToComplete -like '*\*' -or $wordToComplete -like '[A-Za-z]:*') {
        return Get-DismPathCompletions -InputPath $wordToComplete -AllowedExtensions @()
    }

    if ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        if ($activeCommand) {
            $suggestions = @($script:DismCompletionCatalog.GlobalSwitches)
            $cmdKey = $activeCommand.ToLowerInvariant()
            if ($script:DismCompletionCatalog.HelpTokensByKey.ContainsKey($cmdKey)) {
                $suggestions += $script:DismCompletionCatalog.HelpTokensByKey[$cmdKey]
            }
        } else {
            $suggestions = @($script:DismCompletionCatalog.Commands + $script:DismCompletionCatalog.GlobalSwitches)
        }

        return $suggestions | Sort-Object -Unique
    }

    @()
}
