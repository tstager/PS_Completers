# where.exe tab completion for PowerShell
# Static switch catalog seeded from the documented where.exe /? surface, enriched from live help.
# Usage: . .\where_completer.ps1
# Note: PowerShell's built-in "where" alias resolves to Where-Object, so completion needs the where.exe spelling.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name WhereCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:WhereCompletionCatalog = @{
        Initialized     = $false
        Switches        = @()
        PathOptions     = @('/R')
        ExecutablePath  = $null
        Executables     = @()
    }
}

function Get-WhereStaticSwitchTable {
    @(
        [pscustomobject]@{ Token = '/R'; Description = 'Recursively searches and displays the files that match the given pattern starting from the specified directory.' }
        [pscustomobject]@{ Token = '/Q'; Description = 'Returns only the exit code, without displaying the list of matched files. (Quiet mode)' }
        [pscustomobject]@{ Token = '/F'; Description = 'Displays the matched filename in double quotes.' }
        [pscustomobject]@{ Token = '/T'; Description = 'Displays the file size, last modified date and time for all matched files.' }
        [pscustomobject]@{ Token = '/?'; Description = 'Displays this help message.' }
    )
}

function Invoke-WhereHelpText {
    if (-not (Get-Command -Name where.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        return @()
    }

    try {
        @($null | & where.exe '/?' 2>$null)
    } catch {
        @()
    }
}

function Get-WhereSwitchTokensFromLines {
    param([string[]]$Lines)

    $tokens = foreach ($line in @($Lines)) {
        foreach ($match in [regex]::Matches($line, '(?<!\w)(/(?:\?|[A-Za-z][A-Za-z0-9]*):?)(?=[\s\]\}\|,]|$|<)')) {
            $match.Groups[1].Value
        }
    }

    @($tokens | Sort-Object -Unique)
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

    $parts = @([regex]::Matches($prefix, '"[^"]*"?|\S+') | ForEach-Object { $_.Value })
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

function ConvertTo-WhereQuotedText {
    param(
        [string]$Text,
        [bool]$AlwaysQuote
    )

    if (($AlwaysQuote -or $Text -match '\s') -and -not ($Text.StartsWith('"') -and $Text.EndsWith('"'))) {
        return '"' + $Text + '"'
    }

    $Text
}

function Get-WherePathCompletions {
    param([string]$InputPath)

    # /R takes a directory; keep whatever prefix the user typed (relative stays relative, C:\ stays C:\).
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and $InputPath.StartsWith('"')
    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }

    $separatorIndex = $cleanInput.LastIndexOfAny([char[]]@('\', '/'))
    if ($separatorIndex -ge 0) {
        $parentText = $cleanInput.Substring(0, $separatorIndex + 1)
        $leaf = $cleanInput.Substring($separatorIndex + 1)
    } else {
        $parentText = ''
        $leaf = $cleanInput
    }

    $parent = if ([string]::IsNullOrEmpty($parentText)) { '.' } else { $parentText }
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($leaf) + '*'

    $directories = @(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like $pattern } |
        Sort-Object -Property Name)

    if ($directories.Count -eq 0) {
        return @(New-WhereCompletionResult -CompletionText '<directory>' -ResultType 'ParameterValue' -ToolTip 'Directory to start the recursive search from.')
    }

    foreach ($directory in $directories) {
        $completionText = $parentText + $directory.Name + [System.IO.Path]::DirectorySeparatorChar
        New-WhereCompletionResult -CompletionText (ConvertTo-WhereQuotedText -Text $completionText -AlwaysQuote $alwaysQuote) -ResultType 'ParameterValue' -ToolTip $directory.FullName
    }
}

function Get-WherePathExtensionList {
    $extensions = @(([string]$env:PATHEXT).Split(';') |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ -match '^\.[a-z0-9]+$' })

    if ($extensions.Count -eq 0) {
        $extensions = @('.com', '.exe', '.bat', '.cmd')
    }

    $extensions
}

function Get-WhereExecutableNameList {
    # Names where.exe can resolve: files on %PATH% whose extension is in %PATHEXT%, cached per PATH value.
    $pathValue = [string]$env:PATH
    if ($script:WhereCompletionCatalog.ExecutablePath -eq $pathValue -and $script:WhereCompletionCatalog.Executables.Count -gt 0) {
        return $script:WhereCompletionCatalog.Executables
    }

    $extensions = Get-WherePathExtensionList
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($pathValue.Split(';'))) {
        $directory = [System.Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"'))
        if ([string]::IsNullOrWhiteSpace($directory) -or -not [System.IO.Directory]::Exists($directory)) {
            continue
        }

        try {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($directory)) {
                $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
                if ($extensions -contains $extension) {
                    [void]$names.Add([System.IO.Path]::GetFileName($file))
                }
            }
        } catch {
            continue
        }
    }

    $script:WhereCompletionCatalog.Executables = @($names | Sort-Object)
    $script:WhereCompletionCatalog.ExecutablePath = $pathValue
    $script:WhereCompletionCatalog.Executables
}

function Get-WhereOperandCompletion {
    param([string]$CurrentWord)

    $cleanWord = if ([string]::IsNullOrEmpty($CurrentWord)) { '' } else { $CurrentWord.Trim('"') }

    # "$env:pattern", "path:pattern" and explicit paths are left to PowerShell's own completion.
    if ($cleanWord -match '[\\/:$]') {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]

    # PATHEXT patterns plus *.dll, the pattern where.exe's own help uses as its example.
    foreach ($extension in @(Get-WherePathExtensionList) + @('.dll')) {
        $wildcard = '*' + $extension
        if ([string]::IsNullOrEmpty($cleanWord) -or $wildcard.StartsWith($cleanWord, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-WhereCompletionResult -CompletionText $wildcard -ResultType 'ParameterValue' -ToolTip "Every $extension file on the search path."))
        }
    }

    if (-not [string]::IsNullOrEmpty($cleanWord) -and -not $cleanWord.StartsWith('*')) {
        foreach ($name in Get-WhereExecutableNameList) {
            if ($name.StartsWith($cleanWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$results.Add((New-WhereCompletionResult -CompletionText $name -ResultType 'ParameterValue' -ToolTip 'Executable found on %PATH%.'))
            }
        }
    }

    @($results.ToArray())
}

function Initialize-WhereCompletion {
    if ($script:WhereCompletionCatalog.Initialized) {
        return
    }

    # The documented surface is always available; live help can only add to it.
    $switches = New-Object System.Collections.Generic.List[object]
    foreach ($switch in Get-WhereStaticSwitchTable) {
        [void]$switches.Add($switch)
    }

    foreach ($token in Get-WhereSwitchTokensFromLines -Lines (Invoke-WhereHelpText)) {
        $known = $false
        foreach ($switch in $switches) {
            if ($switch.Token.Equals($token, [System.StringComparison]::OrdinalIgnoreCase)) {
                $known = $true
                break
            }
        }

        if (-not $known) {
            [void]$switches.Add([pscustomobject]@{ Token = $token; Description = "where.exe switch $token" })
        }
    }

    $script:WhereCompletionCatalog.Switches = @($switches.ToArray())
    $script:WhereCompletionCatalog.Initialized = $true
}

function Get-WhereSwitchCompletion {
    param([string]$CurrentWord)

    $pattern = if ([string]::IsNullOrEmpty($CurrentWord)) { '*' } else { [System.Management.Automation.WildcardPattern]::Escape($CurrentWord) + '*' }

    foreach ($switch in @($script:WhereCompletionCatalog.Switches)) {
        if ($switch.Token -like $pattern) {
            New-WhereCompletionResult -CompletionText $switch.Token -ResultType 'ParameterName' -ToolTip $switch.Description
        }
    }
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
        Get-WhereCurrentToken -Line $line -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
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
        return @(Get-WherePathCompletions -InputPath $currentWord)
    }

    if (-not [string]::IsNullOrEmpty($currentWord) -and $currentWord.StartsWith('/')) {
        return @(Get-WhereSwitchCompletion -CurrentWord $currentWord)
    }

    if ([string]::IsNullOrWhiteSpace($currentWord)) {
        return @(Get-WhereSwitchCompletion -CurrentWord '') + @(Get-WhereOperandCompletion -CurrentWord '')
    }

    @(Get-WhereOperandCompletion -CurrentWord $currentWord)
}

# Register the completer for both where.exe and bare where.
# The built-in read-only alias named "where" still resolves to Where-Object,
# so the native completer only engages for bare where when that alias is absent.
Register-ArgumentCompleter -Native -CommandName @('where.exe', 'where') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-Where -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
