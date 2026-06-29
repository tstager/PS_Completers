# factor tab completion for PowerShell
# Static option completion for factor.exe and factor.

Set-StrictMode -Version 2.0

function Get-FactorCompletionOptions {
    @('--help', '--version')
}

function New-FactorCompletionResult {
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

function Get-FactorCurrentToken {
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

function Get-FactorValueCompletions {
    @(
        New-FactorCompletionResult -CompletionText '<number>' -ListItemText '<number>' -ResultType 'ParameterValue' -ToolTip 'Integer or file operand for factor.'
    )
}

function Complete-Factor {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-FactorCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return Get-FactorValueCompletions
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-FactorCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-FactorCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'Option for factor.'
                }
            }
        )
    }

    Get-FactorValueCompletions
}

Register-ArgumentCompleter -Native -CommandName 'factor', 'factor.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Factor -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
