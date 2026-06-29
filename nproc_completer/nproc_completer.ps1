# nproc tab completion for PowerShell
# Static option completion for nproc.exe and nproc.

Set-StrictMode -Version 2.0

function Get-NprocCompletionOptions {
    @(
        '-a', '--all', '--ignore', '--help', '--version'
    )
}

function New-NprocCompletionResult {
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

function Remove-NprocOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-NprocQuotedValue {
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

function Get-NprocCurrentToken {
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

function Get-NprocPreviousToken {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    if ($elements.Count -le 1) {
        return $null
    }

    if ([string]::IsNullOrEmpty($CurrentWord)) {
        return $elements[-1]
    }

    if ($elements[-1] -eq $CurrentWord) {
        return $elements[-2]
    }

    return $elements[-1]
}

function Get-NprocValueCompletions {
    param(
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [string]$CurrentWord
    )

    $previousToken = Get-NprocPreviousToken -commandAst $commandAst -CurrentWord $CurrentWord
    if ($null -eq $previousToken) {
        return @()
    }

    if ($previousToken -eq '--ignore') {
        return @(
            New-NprocCompletionResult -CompletionText '<number>' -ListItemText '<number>' -ResultType 'ParameterValue' -ToolTip 'Number of processors to ignore.'
        )
    }

    return @()
}

function Complete-Nproc {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-NprocCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        $valueCompletions = Get-NprocValueCompletions -commandAst $commandAst -CurrentWord $wordToComplete
        if ($valueCompletions.Count -gt 0) {
            return $valueCompletions
        }

        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-NprocCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-NprocCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'Option for nproc.'
                }
            }
        )
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'nproc', 'nproc.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Nproc -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
