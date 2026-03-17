# where.exe tab completion for PowerShell
# Builds completion data from where.exe built-in help.
# Usage: . .\where_completer.ps1

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name WhereCompletionCatalog -Scope Script -ErrorAction SilentlyContinue)) {
    $script:WhereCompletionCatalog = @{
        Initialized       = $false
        GlobalSwitches    = @()
        PathOptions       = @()
    }
}

function Invoke-WhereHelpText {
    param([string[]]$Arguments)

    if (-not (Get-Command -Name where.exe -ErrorAction SilentlyContinue)) {
        return @()
    }

    & where.exe @Arguments '/?' 2>$null
}

function Get-WhereSwitchTokensFromLines {
    param([string[]]$Lines)

    $tokens = foreach ($line in $Lines) {
        foreach ($match in [regex]::Matches($line, '(?<!\w)(/[A-Za-z][A-Za-z0-9]*:?)(?=[\s\]\}\|,]|$|<)')) {
            $match.Groups[1].Value
        }
    }

    $tokens | Sort-Object -Unique
}

function New-WhereCompletionResult {
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

function Get-WhereCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    if ($CursorPosition -gt $Line.Length) {
        return ''
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

function Get-WhereExpectedValueOption {
    param([string[]]$TokensBeforeCurrent)

    if (-not $TokensBeforeCurrent -or $TokensBeforeCurrent.Count -eq 0) {
        return $null
    }

    $lastToken = $TokensBeforeCurrent[$TokensBeforeCurrent.Count - 1]
    if ($lastToken.Equals('/R', [System.StringComparison]::OrdinalIgnoreCase)) {
        return '/R'
    }

    $null
}

function Get-WherePathCompletions {
    param([string]$InputPath)

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

    Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue |
        ForEach-Object {
            $completionText = if ($cleanInput -and -not [System.IO.Path]::IsPathRooted($cleanInput) -and $parent -ne '.') {
                Join-Path -Path $parent -ChildPath $_.Name
            } else {
                $_.FullName
            }

            if ($_.PSIsContainer -and -not $completionText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
                $completionText += [System.IO.Path]::DirectorySeparatorChar
            }

            if (($alwaysQuote -or $completionText -match '\s') -and -not ($completionText.StartsWith('"') -and $completionText.EndsWith('"'))) {
                $completionText = '"' + $completionText + '"'
            }

            New-WhereCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $_.FullName
        }
}

function Initialize-WhereCompletion {
    if ($script:WhereCompletionCatalog.Initialized) {
        return
    }

    try {
        $helpLines = Invoke-WhereHelpText
        if ($helpLines) {
            $script:WhereCompletionCatalog.GlobalSwitches = Get-WhereSwitchTokensFromLines $helpLines
            $script:WhereCompletionCatalog.PathOptions = @('/R')
        }
    } catch {
        # If we can't get help, use known values from documentation
        $script:WhereCompletionCatalog.GlobalSwitches = @('/R', '/Q', '/F', '/T', '/?')
        $script:WhereCompletionCatalog.PathOptions = @('/R')
    }

    $script:WhereCompletionCatalog.Initialized = $true
}

function Complete-Where {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    Initialize-WhereCompletion

    $allTokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $tokens = @($allTokens | Select-Object -Skip 1)
    $line = $commandAst.ToString()
    $currentWord = if ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        Get-WhereCurrentToken -Line $line -CursorPosition $cursorPosition -Fallback $wordToComplete
    } else {
        $wordToComplete
    }
    $hasTrailingSpace = [string]::IsNullOrEmpty($wordToComplete)

    if ($hasTrailingSpace) {
        $tokensBeforeCurrent = @($tokens)
    } elseif ($tokens.Count -gt 1) {
        $tokensBeforeCurrent = @($tokens | Select-Object -First ($tokens.Count - 1))
    } else {
        $tokensBeforeCurrent = @()
    }

    $expectedValueOption = Get-WhereExpectedValueOption -TokensBeforeCurrent $tokensBeforeCurrent
    if ($expectedValueOption -and ($script:WhereCompletionCatalog.PathOptions -contains $expectedValueOption)) {
        $pathCompletions = @(Get-WherePathCompletions -InputPath $currentWord)
        return $pathCompletions
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('/')) {
        return $script:WhereCompletionCatalog.GlobalSwitches |
            Where-Object { $_ -like "$currentWord*" } |
            ForEach-Object {
                New-WhereCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
            }
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return $script:WhereCompletionCatalog.GlobalSwitches |
            ForEach-Object {
                New-WhereCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
            }
    }

    return @()
}

# Register the completer
Register-ArgumentCompleter -Native -CommandName where.exe -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-Where -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}