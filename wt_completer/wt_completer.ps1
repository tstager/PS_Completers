# PowerShell Argument Completer for wt.exe
# Provides tab completion for top-level wt options, subcommands, and selected subcommand arguments.

Set-StrictMode -Version Latest

function Get-WtSettingsNames {
    param([string]$Kind)

    $cache = Get-Variable -Name 'WtSettingsNames' -Scope Script -ErrorAction Ignore
    if ($null -eq $cache -or $null -eq $cache.Value) {
        $names = @{ profiles = @(); schemes = @() }
        foreach ($package in 'Microsoft.WindowsTerminal_8wekyb3d8bbwe', 'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe') {
            $settingsPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Packages\$package\LocalState\settings.json"
            if (-not (Test-Path -LiteralPath $settingsPath)) {
                continue
            }

            try {
                $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
            } catch {
                continue
            }

            if ($settings.PSObject.Properties['profiles'] -and $settings.profiles.PSObject.Properties['list']) {
                $names.profiles += @($settings.profiles.list | ForEach-Object { $_.name } | Where-Object { $_ })
            }

            if ($settings.PSObject.Properties['schemes']) {
                $names.schemes += @($settings.schemes | ForEach-Object { $_.name } | Where-Object { $_ })
            }
        }

        $names.profiles = @($names.profiles | Sort-Object -Unique)
        $names.schemes = @($names.schemes | Sort-Object -Unique)
        Set-Variable -Name 'WtSettingsNames' -Value $names -Scope Script
        $cache = Get-Variable -Name 'WtSettingsNames' -Scope Script
    }

    @($cache.Value[$Kind])
}

function Get-WtValueCompletionData {
    param([string]$Option)

    $kind = if ($Option -in '-p', '--profile') { 'profiles' } elseif ($Option -eq '--colorScheme') { 'schemes' } else { $null }
    if (-not $kind) {
        return @()
    }

    @(
        foreach ($name in Get-WtSettingsNames -Kind $kind) {
            $text = if ($name -match '\s') { '"' + $name + '"' } else { $name }
            @{ Text = $text; Display = $name; Type = 'ParameterValue'; Tooltip = "Windows Terminal $kind entry" }
        }
    )
}

function Complete-WtNative {
    param($wordToComplete, $commandAst, $cursorPosition)

    if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue) -and
        -not (Get-Command wt -ErrorAction SilentlyContinue)) {
        return
    }

    $topLevelOptionData = @(
        @{ Text = '-h'; Display = '-h'; Type = 'ParameterName'; Tooltip = 'Print this help message and exit' }
        @{ Text = '--help'; Display = '--help'; Type = 'ParameterName'; Tooltip = 'Print this help message and exit' }
        @{ Text = '-v'; Display = '-v'; Type = 'ParameterName'; Tooltip = 'Display the application version' }
        @{ Text = '--version'; Display = '--version'; Type = 'ParameterName'; Tooltip = 'Display the application version' }
        @{ Text = '-M'; Display = '-M'; Type = 'ParameterName'; Tooltip = 'Launch the window maximized' }
        @{ Text = '--maximized'; Display = '--maximized'; Type = 'ParameterName'; Tooltip = 'Launch the window maximized' }
        @{ Text = '-F'; Display = '-F'; Type = 'ParameterName'; Tooltip = 'Launch the window in fullscreen mode' }
        @{ Text = '--fullscreen'; Display = '--fullscreen'; Type = 'ParameterName'; Tooltip = 'Launch the window in fullscreen mode' }
        @{ Text = '-f'; Display = '-f'; Type = 'ParameterName'; Tooltip = 'Launch the window in focus mode' }
        @{ Text = '--focus'; Display = '--focus'; Type = 'ParameterName'; Tooltip = 'Launch the window in focus mode' }
        @{ Text = '--pos'; Display = '--pos'; Type = 'ParameterName'; Tooltip = 'Specify the position for the terminal, in ''x,y'' format' }
        @{ Text = '--size'; Display = '--size'; Type = 'ParameterName'; Tooltip = 'Specify the number of columns and rows for the terminal, in ''c,r'' format' }
        @{ Text = '-w'; Display = '-w'; Type = 'ParameterName'; Tooltip = 'Specify a terminal window to run the given commandline in' }
        @{ Text = '--window'; Display = '--window'; Type = 'ParameterName'; Tooltip = 'Specify a terminal window to run the given commandline in' }
        @{ Text = '-s'; Display = '-s'; Type = 'ParameterName'; Tooltip = 'Internal parameter for saved command lines' }
        @{ Text = '--saved'; Display = '--saved'; Type = 'ParameterName'; Tooltip = 'Internal parameter for saved command lines' }
    )

    $newTerminalOptionData = @(
        @{ Text = '-p'; Display = '-p'; Type = 'ParameterName'; Tooltip = 'Use the specified profile' }
        @{ Text = '--profile'; Display = '--profile'; Type = 'ParameterName'; Tooltip = 'Use the specified profile' }
        @{ Text = '--sessionId'; Display = '--sessionId'; Type = 'ParameterName'; Tooltip = 'Reuse or assign the specified session ID' }
        @{ Text = '-d'; Display = '-d'; Type = 'ParameterName'; Tooltip = 'Set the starting directory' }
        @{ Text = '--startingDirectory'; Display = '--startingDirectory'; Type = 'ParameterName'; Tooltip = 'Set the starting directory' }
        @{ Text = '--title'; Display = '--title'; Type = 'ParameterName'; Tooltip = 'Set the starting tab title' }
        @{ Text = '--tabColor'; Display = '--tabColor'; Type = 'ParameterName'; Tooltip = 'Set the starting tab color' }
        @{ Text = '--suppressApplicationTitle'; Display = '--suppressApplicationTitle'; Type = 'ParameterName'; Tooltip = 'Prevent the terminal application from changing the tab title' }
        @{ Text = '--useApplicationTitle'; Display = '--useApplicationTitle'; Type = 'ParameterName'; Tooltip = 'Allow the terminal application to change the tab title' }
        @{ Text = '--colorScheme'; Display = '--colorScheme'; Type = 'ParameterName'; Tooltip = 'Set the color scheme' }
        @{ Text = '--appendCommandLine'; Display = '--appendCommandLine'; Type = 'ParameterName'; Tooltip = 'Append the provided command line to the profile command line' }
        @{ Text = '--inheritEnvironment'; Display = '--inheritEnvironment'; Type = 'ParameterName'; Tooltip = 'Inherit environment variables into the new terminal' }
        @{ Text = '--reloadEnvironment'; Display = '--reloadEnvironment'; Type = 'ParameterName'; Tooltip = 'Reload the environment instead of inheriting it' }
    )

    $splitPaneOptionData = @(
        @{ Text = '-H'; Display = '-H'; Type = 'ParameterName'; Tooltip = 'Split horizontally' }
        @{ Text = '--horizontal'; Display = '--horizontal'; Type = 'ParameterName'; Tooltip = 'Split horizontally' }
        @{ Text = '-V'; Display = '-V'; Type = 'ParameterName'; Tooltip = 'Split vertically' }
        @{ Text = '--vertical'; Display = '--vertical'; Type = 'ParameterName'; Tooltip = 'Split vertically' }
        @{ Text = '-s'; Display = '-s'; Type = 'ParameterName'; Tooltip = 'Set the pane size ratio between 0.01 and 0.99' }
        @{ Text = '--size'; Display = '--size'; Type = 'ParameterName'; Tooltip = 'Set the pane size ratio between 0.01 and 0.99' }
        @{ Text = '-D'; Display = '-D'; Type = 'ParameterName'; Tooltip = 'Duplicate the focused pane instead of launching a new terminal' }
        @{ Text = '--duplicate'; Display = '--duplicate'; Type = 'ParameterName'; Tooltip = 'Duplicate the focused pane instead of launching a new terminal' }
    )

    $focusTabOptionData = @(
        @{ Text = '-t'; Display = '-t'; Type = 'ParameterName'; Tooltip = 'Target the specified tab index' }
        @{ Text = '--target'; Display = '--target'; Type = 'ParameterName'; Tooltip = 'Target the specified tab index' }
        @{ Text = '-n'; Display = '-n'; Type = 'ParameterName'; Tooltip = 'Move focus to the next tab' }
        @{ Text = '--next'; Display = '--next'; Type = 'ParameterName'; Tooltip = 'Move focus to the next tab' }
        @{ Text = '-p'; Display = '-p'; Type = 'ParameterName'; Tooltip = 'Move focus to the previous tab' }
        @{ Text = '--previous'; Display = '--previous'; Type = 'ParameterName'; Tooltip = 'Move focus to the previous tab' }
    )

    $movePaneOptionData = @(
        @{ Text = '-t'; Display = '-t'; Type = 'ParameterName'; Tooltip = 'Move the focused pane to the specified tab index' }
        @{ Text = '--tab'; Display = '--tab'; Type = 'ParameterName'; Tooltip = 'Move the focused pane to the specified tab index' }
    )

    $focusPaneOptionData = @(
        @{ Text = '-t'; Display = '-t'; Type = 'ParameterName'; Tooltip = 'Focus the specified pane index' }
        @{ Text = '--target'; Display = '--target'; Type = 'ParameterName'; Tooltip = 'Focus the specified pane index' }
    )

    $directionValueData = @(
        @{ Text = 'left'; Display = 'left'; Type = 'ParameterValue'; Tooltip = 'Direction: left' }
        @{ Text = 'right'; Display = 'right'; Type = 'ParameterValue'; Tooltip = 'Direction: right' }
        @{ Text = 'up'; Display = 'up'; Type = 'ParameterValue'; Tooltip = 'Direction: up' }
        @{ Text = 'down'; Display = 'down'; Type = 'ParameterValue'; Tooltip = 'Direction: down' }
        @{ Text = 'previous'; Display = 'previous'; Type = 'ParameterValue'; Tooltip = 'Direction: previous focused pane' }
        @{ Text = 'nextInOrder'; Display = 'nextInOrder'; Type = 'ParameterValue'; Tooltip = 'Direction: next pane in order' }
        @{ Text = 'previousInOrder'; Display = 'previousInOrder'; Type = 'ParameterValue'; Tooltip = 'Direction: previous pane in order' }
        @{ Text = 'first'; Display = 'first'; Type = 'ParameterValue'; Tooltip = 'Direction: first pane' }
    )

    $subcommandData = @(
        @{ Text = 'new-tab'; Display = 'new-tab'; Type = 'ParameterValue'; Tooltip = 'Create a new tab' }
        @{ Text = 'nt'; Display = 'nt'; Type = 'ParameterValue'; Tooltip = 'Alias for new-tab' }
        @{ Text = 'split-pane'; Display = 'split-pane'; Type = 'ParameterValue'; Tooltip = 'Create a new split pane' }
        @{ Text = 'sp'; Display = 'sp'; Type = 'ParameterValue'; Tooltip = 'Alias for split-pane' }
        @{ Text = 'focus-tab'; Display = 'focus-tab'; Type = 'ParameterValue'; Tooltip = 'Move focus to another tab' }
        @{ Text = 'ft'; Display = 'ft'; Type = 'ParameterValue'; Tooltip = 'Alias for focus-tab' }
        @{ Text = 'move-focus'; Display = 'move-focus'; Type = 'ParameterValue'; Tooltip = 'Move focus to the adjacent pane in the specified direction' }
        @{ Text = 'mf'; Display = 'mf'; Type = 'ParameterValue'; Tooltip = 'Alias for move-focus' }
        @{ Text = 'move-pane'; Display = 'move-pane'; Type = 'ParameterValue'; Tooltip = 'Move focused pane to another tab' }
        @{ Text = 'mp'; Display = 'mp'; Type = 'ParameterValue'; Tooltip = 'Alias for move-pane' }
        @{ Text = 'swap-pane'; Display = 'swap-pane'; Type = 'ParameterValue'; Tooltip = 'Swap the focused pane with the adjacent pane in the specified direction' }
        @{ Text = 'focus-pane'; Display = 'focus-pane'; Type = 'ParameterValue'; Tooltip = 'Move focus to another pane' }
        @{ Text = 'fp'; Display = 'fp'; Type = 'ParameterValue'; Tooltip = 'Alias for focus-pane' }
        @{ Text = 'x-save'; Display = 'x-save'; Type = 'ParameterValue'; Tooltip = 'Save command line as input action' }
    )

    $subcommandMap = @{
        'new-tab' = 'new-tab'
        'nt' = 'new-tab'
        'split-pane' = 'split-pane'
        'sp' = 'split-pane'
        'focus-tab' = 'focus-tab'
        'ft' = 'focus-tab'
        'move-focus' = 'move-focus'
        'mf' = 'move-focus'
        'move-pane' = 'move-pane'
        'mp' = 'move-pane'
        'swap-pane' = 'swap-pane'
        'focus-pane' = 'focus-pane'
        'fp' = 'focus-pane'
        'x-save' = 'x-save'
    }

    $topLevelValueOptions = @('--pos', '--size', '-w', '--window', '-s', '--saved')
    $newTerminalValueOptions = @('-p', '--profile', '--sessionId', '-d', '--startingDirectory', '--title', '--tabColor', '--colorScheme')
    $splitPaneValueOptions = $newTerminalValueOptions + @('-s', '--size')
    $focusTabValueOptions = @('-t', '--target')
    $movePaneValueOptions = @('-t', '--tab')
    $focusPaneValueOptions = @('-t', '--target')

    $subcommandOptionData = @{
        'new-tab' = $newTerminalOptionData
        'split-pane' = $newTerminalOptionData + $splitPaneOptionData
        'focus-tab' = $focusTabOptionData
        'move-focus' = @()
        'move-pane' = $movePaneOptionData
        'swap-pane' = @()
        'focus-pane' = $focusPaneOptionData
        'x-save' = @()
    }

    $subcommandValueOptions = @{
        'new-tab' = $newTerminalValueOptions
        'split-pane' = $splitPaneValueOptions
        'focus-tab' = $focusTabValueOptions
        'move-focus' = @()
        'move-pane' = $movePaneValueOptions
        'swap-pane' = @()
        'focus-pane' = $focusPaneValueOptions
        'x-save' = @()
    }

    $line = $commandAst.ToString()
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    $prefixLength = [Math]::Max(0, [Math]::Min($relativeCursor, $line.Length))
    $linePrefix = $line.Substring(0, $prefixLength)
    $tokens = @([regex]::Matches($linePrefix, '\S+') | ForEach-Object { $_.Value })
    $hasTrailingSpace = ($linePrefix -match '\s$') -or ($relativeCursor -gt $line.Length)
    $matchPrefix = if ((-not $hasTrailingSpace) -and $tokens.Count -gt 0 -and $tokens[-1] -like '-*') {
        $tokens[-1]
    }
    elseif ($wordToComplete) {
        $wordToComplete
    }
    else {
        if ($hasTrailingSpace -or $tokens.Count -eq 0) { '' } else { $tokens[-1] }
    }
    $previousToken = if ($hasTrailingSpace) {
        if ($tokens.Count -gt 0) { $tokens[-1] } else { '' }
    }
    elseif ($tokens.Count -gt 1) {
        $tokens[-2]
    }
    else {
        ''
    }

    [object[]]$argumentTokens = if ($tokens.Count -gt 1) {
        @($tokens[1..($tokens.Count - 1)])
    }
    else {
        @()
    }

    [object[]]$completedTokens = if ($hasTrailingSpace) {
        @($argumentTokens)
    }
    elseif ($argumentTokens.Count -gt 0) {
        @($argumentTokens | Select-Object -First ($argumentTokens.Count - 1))
    }
    else {
        @()
    }

    $expandedTokens = New-Object System.Collections.Generic.List[string]
    foreach ($token in $completedTokens) {
        if ($token -eq ';' -or $token -eq '`;') {
            $expandedTokens.Add(';')
            continue
        }

        if ($token -match '^(.+?)`?;$') {
            $expandedTokens.Add($Matches[1])
            $expandedTokens.Add(';')
            continue
        }

        $expandedTokens.Add($token)
    }
    $completedTokens = @($expandedTokens.ToArray())

    $selectedSubcommand = $null
    $expectingValueOption = $null
    foreach ($token in $completedTokens) {
        if ($token -eq ';') {
            $selectedSubcommand = $null
            $expectingValueOption = $null
            continue
        }

        if ($expectingValueOption) {
            $expectingValueOption = $null
            continue
        }

        if (-not $selectedSubcommand) {
            if (($topLevelValueOptions + $newTerminalValueOptions) -contains $token) {
                $expectingValueOption = $token
                continue
            }

            if ($subcommandMap.ContainsKey($token)) {
                $selectedSubcommand = $subcommandMap[$token]
                continue
            }

            continue
        }

        if ($subcommandValueOptions[$selectedSubcommand] -contains $token) {
            $expectingValueOption = $token
        }
    }

    [object[]]$completionData = @()
    if (-not $selectedSubcommand) {
        if (($topLevelValueOptions + $newTerminalValueOptions) -contains $previousToken) {
            $completionData = Get-WtValueCompletionData -Option $previousToken
        }
        elseif ($matchPrefix -like '-*') {
            $completionData = $topLevelOptionData + $newTerminalOptionData
        }
        else {
            $completionData = $topLevelOptionData + $newTerminalOptionData + $subcommandData
        }
    }
    else {
        switch ($selectedSubcommand) {
            'move-focus' {
                if ($matchPrefix -like '-*') {
                    $completionData = @()
                }
                else {
                    $completionData = $directionValueData
                }
            }
            'swap-pane' {
                if ($matchPrefix -like '-*') {
                    $completionData = @()
                }
                else {
                    $completionData = $directionValueData
                }
            }
            default {
                if ($subcommandValueOptions[$selectedSubcommand] -contains $previousToken) {
                    $completionData = Get-WtValueCompletionData -Option $previousToken
                }
                elseif ($matchPrefix -like '-*') {
                    $completionData = $subcommandOptionData[$selectedSubcommand]
                }
                else {
                    $completionData = @()
                }
            }
        }
    }

    foreach ($item in $completionData) {
        if ($item.Text -notlike "$matchPrefix*" -and $item.Display -notlike "$matchPrefix*") {
            continue
        }

        [System.Management.Automation.CompletionResult]::new(
            $item.Text,
            $item.Display,
            [System.Management.Automation.CompletionResultType]::$($item.Type),
            $item.Tooltip
        )
    }
}

Register-ArgumentCompleter -Native -CommandName @('wt', 'wt.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-WtNative -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
