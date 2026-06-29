# printenv tab completion for PowerShell
# Static option completion for printenv.exe and printenv.

Set-StrictMode -Version 2.0

function Get-PrintenvCompletionOptions {
    @(
        '-0', '--null', '--help', '--version'
    )
}

function New-PrintenvCompletionResult {
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

function Get-PrintenvCurrentToken {
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

function Get-PrintenvValueCompletions {
    $envVars = @(Get-ChildItem Env: | Sort-Object -Property Name)
    $values = @()
    foreach ($entry in $envVars) {
        $values += New-PrintenvCompletionResult -CompletionText $entry.Name -ListItemText $entry.Name -ResultType 'ParameterValue' -ToolTip $entry.Value
    }

    $values
}

function Complete-Printenv {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $currentWord = if ($cursorPosition -gt $commandAst.Extent.EndOffset) {
        ''
    } else {
        Get-PrintenvCurrentToken -Line $commandAst.ToString() -CursorPosition $cursorPosition -Fallback $wordToComplete
    }

    if ([string]::IsNullOrEmpty($currentWord)) {
        return @()
    }

    if ($currentWord.StartsWith('-')) {
        return @(
            foreach ($option in Get-PrintenvCompletionOptions) {
                if ($option.StartsWith($currentWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-PrintenvCompletionResult -CompletionText $option -ListItemText $option -ResultType 'ParameterName' -ToolTip 'Option for printenv.'
                }
            }
        )
    }

    $prefix = $currentWord
    $matches = @(Get-PrintenvValueCompletions | Where-Object { $_.CompletionText -like "$prefix*" -or $_.ListItemText -like "$prefix*" })
    if ($matches.Count -gt 0) {
        return $matches
    }

    @()
}

Register-ArgumentCompleter -Native -CommandName 'printenv', 'printenv.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Printenv -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
