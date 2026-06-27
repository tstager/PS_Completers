# xargs tab completion for PowerShell
# Registers a native PowerShell argument completer for xargs.exe using the documented
# coreutils option surface and lightweight value-aware completion.

Set-StrictMode -Version 2.0

function New-XargsCompletionResult {
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

function Get-XargsOptionSpecs {
    @(
        [pscustomobject]@{ Token = '-a'; LongToken = '--arg-file'; Description = 'Read arguments from the given file instead of stdin'; ValueKind = 'FilePath' },
        [pscustomobject]@{ Token = '-d'; LongToken = '--delimiter'; Description = 'Use the given delimiter to split the input'; ValueKind = 'Delimiter' },
        [pscustomobject]@{ Token = '-x'; LongToken = '--exit'; Description = 'Exit if the number of arguments allowed by -L or -n do not fit'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = '-n'; LongToken = '--max-args'; Description = 'Set the max number of arguments read from stdin to be passed to each command invocation'; ValueKind = 'Integer' },
        [pscustomobject]@{ Token = '-L'; LongToken = '--max-lines'; Description = 'Set the max number of lines from stdin to be passed to each command invocation'; ValueKind = 'Integer' },
        [pscustomobject]@{ Token = '-l'; LongToken = ''; Description = 'Equivalent to -L, but with a default value of 1 if max-lines is unspecified'; ValueKind = 'OptionalInteger' },
        [pscustomobject]@{ Token = '-P'; LongToken = '--max-procs'; Description = 'Run up to this many commands in parallel'; ValueKind = 'Integer' },
        [pscustomobject]@{ Token = '-r'; LongToken = '--no-run-if-empty'; Description = 'If there are no input arguments, do not run the command at all'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = '-0'; LongToken = '--null'; Description = 'Split the input by null terminators rather than whitespace'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = '-s'; LongToken = '--max-chars'; Description = 'Set the max number of characters to be passed to each invocation'; ValueKind = 'Integer' },
        [pscustomobject]@{ Token = '-t'; LongToken = '--verbose'; Description = 'Be verbose'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = '-i'; LongToken = '--replace'; Description = 'Replace R in initial arguments with names read from standard input'; ValueKind = 'ReplaceText' },
        [pscustomobject]@{ Token = '-I'; LongToken = ''; Description = 'Replace R in initial arguments with names read from standard input'; ValueKind = 'ReplaceText' },
        [pscustomobject]@{ Token = '-E'; LongToken = ''; Description = 'Stop processing the input upon reaching an input item that matches eof-string'; ValueKind = 'EofString' },
        [pscustomobject]@{ Token = '-e'; LongToken = '--eof'; Description = 'Alias for -E'; ValueKind = 'EofString' },
        [pscustomobject]@{ Token = '-h'; LongToken = '--help'; Description = 'Print help'; ValueKind = 'NoValue' },
        [pscustomobject]@{ Token = '-V'; LongToken = '--version'; Description = 'Print version'; ValueKind = 'NoValue' }
    )
}

function Get-XargsOptionSpecByToken {
    param([string]$Token)

    $cleanToken = if ([string]::IsNullOrWhiteSpace($Token)) { '' } else { $Token.Trim() }
    if ([string]::IsNullOrWhiteSpace($cleanToken)) {
        return $null
    }

    foreach ($option in Get-XargsOptionSpecs) {
        if ($option.Token -eq $cleanToken -or $option.LongToken -eq $cleanToken) {
            return $option
        }
    }

    $null
}

function Get-XargsOptionSuggestions {
    param(
        [string]$CurrentToken,
        [string]$Prefix = ''
    )

    $results = New-Object System.Collections.Generic.List[object]
    $typed = if ($null -eq $CurrentToken) { '' } else { $CurrentToken }
    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        $Prefix = ''
    }

    foreach ($option in Get-XargsOptionSpecs) {
        $matchingText = if ($typed.StartsWith('--')) { $option.LongToken } else { $option.Token }
        if ([string]::IsNullOrWhiteSpace($matchingText)) {
            continue
        }

        if ($matchingText -like "$typed*") {
            $completionText = if ($Prefix) { $Prefix + $matchingText } else { $matchingText }
            [void]$results.Add((New-XargsCompletionResult -CompletionText $completionText -ResultType 'ParameterName' -ToolTip $option.Description -ListItemText $matchingText))
        }
    }

    @($results.ToArray())
}

function Get-XargsPathCompletions {
    param(
        [string]$CurrentValue,
        [string]$Prefix = ''
    )

    $results = New-Object System.Collections.Generic.List[object]
    $cleanValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue.Trim([char[]]@([char]34, [char]39)) }
    $alwaysQuote = -not [string]::IsNullOrEmpty($CurrentValue) -and $CurrentValue.StartsWith('"')

    if ([string]::IsNullOrWhiteSpace($cleanValue)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanValue.EndsWith('\') -or $cleanValue.EndsWith('/')) {
        $parent = $cleanValue
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanValue -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }
        $leaf = Split-Path -Path $cleanValue -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    foreach ($item in @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)) {
        $completionText = if ($cleanValue -and -not [System.IO.Path]::IsPathRooted($cleanValue)) {
            if ($parent -eq '.') {
                $item.Name
            } else {
                Join-Path -Path $parent -ChildPath $item.Name
            }
        } else {
            $item.FullName
        }

        if ($item.PSIsContainer -and -not $completionText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionText += [System.IO.Path]::DirectorySeparatorChar
        }

        if ($alwaysQuote -and -not $completionText.StartsWith('"')) {
            $completionText = '"' + $completionText + '"'
        }

        $completionText = $Prefix + $completionText
        [void]$results.Add((New-XargsCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $item.FullName -ListItemText $item.Name))
    }

    @($results.ToArray())
}

function Get-XargsValueSuggestions {
    param(
        [pscustomobject]$OptionSpec,
        [string]$CurrentValue
    )

    if ($null -eq $OptionSpec) {
        return @()
    }

    $typed = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $toolTip = if ([string]::IsNullOrWhiteSpace($OptionSpec.Description)) { $OptionSpec.Token } else { $OptionSpec.Description }

    switch ($OptionSpec.ValueKind) {
        'FilePath' {
            $results = @(Get-XargsPathCompletions -CurrentValue $typed)
            if ($results.Count -gt 0) {
                return $results
            }
            $placeholder = '<arg-file>'
            return @((New-XargsCompletionResult -CompletionText $placeholder -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $placeholder))
        }
        'Delimiter' {
            $placeholder = '<delimiter>'
            return @(
                New-XargsCompletionResult -CompletionText $placeholder -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $placeholder
            )
        }
        'Integer' {
            if ([string]::IsNullOrWhiteSpace($typed)) {
                $placeholder = '<max>'
                return @((New-XargsCompletionResult -CompletionText $placeholder -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $placeholder))
            }
            return @((New-XargsCompletionResult -CompletionText $typed -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $typed))
        }
        'OptionalInteger' {
            if ([string]::IsNullOrWhiteSpace($typed)) {
                $placeholder = '[<max-lines>]'
                return @((New-XargsCompletionResult -CompletionText $placeholder -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $placeholder))
            }
            return @((New-XargsCompletionResult -CompletionText $typed -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $typed))
        }
        'ReplaceText' {
            if ([string]::IsNullOrWhiteSpace($typed)) {
                $placeholder = '<R>'
                return @((New-XargsCompletionResult -CompletionText $placeholder -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $placeholder))
            }
            return @((New-XargsCompletionResult -CompletionText $typed -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $typed))
        }
        'EofString' {
            if ([string]::IsNullOrWhiteSpace($typed)) {
                $placeholder = '<eof-string>'
                return @((New-XargsCompletionResult -CompletionText $placeholder -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $placeholder))
            }
            return @((New-XargsCompletionResult -CompletionText $typed -ResultType 'ParameterValue' -ToolTip $toolTip -ListItemText $typed))
        }
        default {
            @()
        }
    }
}

function Get-XargsCommandSuggestions {
    param([string]$CurrentValue)

    $typed = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $namePattern = if ([string]::IsNullOrWhiteSpace($typed)) { '*' } else { "$typed*" }

    $results = New-Object System.Collections.Generic.List[object]
    $commands = @(Get-Command -Name $namePattern -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -Unique)
    foreach ($name in $commands) {
        if ($name -ne 'xargs' -and $name -ne 'xargs.exe') {
            [void]$results.Add((New-XargsCompletionResult -CompletionText $name -ResultType 'ParameterValue' -ToolTip 'Command to execute' -ListItemText $name))
        }
    }

    @($results.ToArray())
}

function Get-XargsCompletionContext {
    param(
        [string]$CurrentToken,
        [string[]]$TokensBeforeCurrent
    )

    $currentValue = $CurrentToken
    if ($currentValue -match '^(?<option>--[A-Za-z0-9][A-Za-z0-9\-]*)=(?<value>.*)$') {
        $optionSpec = Get-XargsOptionSpecByToken -Token $matches['option']
        if ($optionSpec -and $optionSpec.ValueKind -ne 'NoValue') {
            return [pscustomobject]@{
                OptionSpec = $optionSpec
                ValueText  = $matches['value']
            }
        }
    }

    if ($TokensBeforeCurrent.Count -gt 0) {
        $lastToken = $TokensBeforeCurrent[-1]
        $optionSpec = Get-XargsOptionSpecByToken -Token $lastToken
        if ($optionSpec -and $optionSpec.ValueKind -ne 'NoValue') {
            return [pscustomobject]@{
                OptionSpec = $optionSpec
                ValueText  = $currentValue
            }
        }
    }

    $null
}

Register-ArgumentCompleter -Native -CommandName 'xargs', 'xargs.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $tokensBeforeCurrent = @()
    foreach ($element in $commandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $cursorPosition) {
            $tokensBeforeCurrent += $element.Extent.Text
        }
    }

    $context = Get-XargsCompletionContext -CurrentToken $wordToComplete -TokensBeforeCurrent $tokensBeforeCurrent
    if ($context) {
        return Get-XargsValueSuggestions -OptionSpec $context.OptionSpec -CurrentValue $context.ValueText
    }

    if (-not [string]::IsNullOrWhiteSpace($wordToComplete) -and $wordToComplete.StartsWith('-')) {
        return Get-XargsOptionSuggestions -CurrentToken $wordToComplete
    }

    if ($tokensBeforeCurrent.Count -eq 0 -or ($tokensBeforeCurrent.Count -eq 1 -and $tokensBeforeCurrent[0] -notmatch '^-[A-Za-z0-9]')) {
        return Get-XargsCommandSuggestions -CurrentValue $wordToComplete
    }

    if ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        return Get-XargsCommandSuggestions -CurrentValue ''
    }

    @()
}
