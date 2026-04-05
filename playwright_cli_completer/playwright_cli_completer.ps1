<#
.SYNOPSIS
    Registers a native PowerShell argument completer for playwright-cli.

.DESCRIPTION
    Provides static-first completion for `playwright-cli`, `playwright-cli.cmd`,
    and `playwright-cli.ps1` using the locally installed CLI help surface.

    The completer covers:
    - top-level commands
    - command-specific options
    - inline `--option=value` completion
    - path completion for file and directory slots
    - placeholder and enum values for common browser/session/target arguments

    Dot-source this file from your PowerShell profile to enable completion.
#>

Set-StrictMode -Version Latest

function New-PlaywrightCliCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType = 'ParameterValue',
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $ListItemText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function New-PlaywrightCliOptionSpec {
    param(
        [string[]]$Tokens,
        [string]$Description,
        [string]$ValueKind,
        [switch]$OptionalValue,
        [string]$CompletionText
    )

    foreach ($token in @($Tokens)) {
        [pscustomobject]@{
            Token          = $token
            Description    = $Description
            ValueKind      = $ValueKind
            OptionalValue  = [bool]$OptionalValue
            CompletionText = if ([string]::IsNullOrWhiteSpace($CompletionText)) { $token } else { $CompletionText }
        }
    }
}

function New-PlaywrightCliCommandSpec {
    param(
        [string]$Name,
        [string]$Description,
        [string[]]$Positionals,
        [object[]]$Options
    )

    [pscustomobject]@{
        Name        = $Name
        Description = $Description
        Positionals = @($Positionals)
        Options     = @($Options)
    }
}

function Get-PlaywrightCliMetadata {
    if (Get-Variable -Name PlaywrightCliMetadata -Scope Script -ErrorAction SilentlyContinue) {
        return $script:PlaywrightCliMetadata
    }

    $commands = @(
        New-PlaywrightCliCommandSpec -Name 'open' -Description 'Open the browser.' -Positionals @('Url') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--browser') -Description 'Browser or chrome channel to use.' -ValueKind 'Browser'
            New-PlaywrightCliOptionSpec -Tokens @('--config') -Description 'Path to the configuration file.' -ValueKind 'FilePath'
            New-PlaywrightCliOptionSpec -Tokens @('--headed') -Description 'Run browser in headed mode.'
            New-PlaywrightCliOptionSpec -Tokens @('--persistent') -Description 'Use a persistent browser profile.'
            New-PlaywrightCliOptionSpec -Tokens @('--profile') -Description 'Store the persistent profile in the specified directory.' -ValueKind 'DirectoryPath'
        )
        New-PlaywrightCliCommandSpec -Name 'attach' -Description 'Attach to a running Playwright browser.' -Positionals @('SessionTarget') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--cdp') -Description 'Connect to an existing browser via CDP endpoint URL.' -ValueKind 'Url'
            New-PlaywrightCliOptionSpec -Tokens @('--endpoint') -Description 'Playwright browser server endpoint to attach to.' -ValueKind 'Url'
            New-PlaywrightCliOptionSpec -Tokens @('--extension') -Description 'Connect to a browser extension, optionally specifying a browser name.' -ValueKind 'Browser' -OptionalValue
            New-PlaywrightCliOptionSpec -Tokens @('--config') -Description 'Path to the configuration file.' -ValueKind 'FilePath'
            New-PlaywrightCliOptionSpec -Tokens @('--session') -Description 'Session name.' -ValueKind 'SessionName'
        )
        New-PlaywrightCliCommandSpec -Name 'close' -Description 'Close the browser.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'goto' -Description 'Navigate to a URL.' -Positionals @('Url') -Options @()
        New-PlaywrightCliCommandSpec -Name 'type' -Description 'Type text into the active editable element.' -Positionals @('Text') -Options @()
        New-PlaywrightCliCommandSpec -Name 'click' -Description 'Perform click on a web page.' -Positionals @('Target', 'MouseButton') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--modifiers') -Description 'Modifier keys to press.' -ValueKind 'ModifierKeys'
        )
        New-PlaywrightCliCommandSpec -Name 'dblclick' -Description 'Perform double click on a web page.' -Positionals @('Target', 'MouseButton') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--modifiers') -Description 'Modifier keys to press.' -ValueKind 'ModifierKeys'
        )
        New-PlaywrightCliCommandSpec -Name 'fill' -Description 'Fill text into an editable element.' -Positionals @('Target', 'Text') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--submit') -Description 'Press Enter after filling text.'
        )
        New-PlaywrightCliCommandSpec -Name 'drag' -Description 'Perform drag and drop between two elements.' -Positionals @('Target', 'Target') -Options @()
        New-PlaywrightCliCommandSpec -Name 'hover' -Description 'Hover over an element on the page.' -Positionals @('Target') -Options @()
        New-PlaywrightCliCommandSpec -Name 'select' -Description 'Select an option in a dropdown.' -Positionals @('Target', 'DropdownValue') -Options @()
        New-PlaywrightCliCommandSpec -Name 'upload' -Description 'Upload one or more files.' -Positionals @('FilePath') -Options @()
        New-PlaywrightCliCommandSpec -Name 'check' -Description 'Check a checkbox or radio button.' -Positionals @('Target') -Options @()
        New-PlaywrightCliCommandSpec -Name 'uncheck' -Description 'Uncheck a checkbox or radio button.' -Positionals @('Target') -Options @()
        New-PlaywrightCliCommandSpec -Name 'snapshot' -Description 'Capture page snapshot to obtain element references.' -Positionals @('Target') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'Save snapshot to a markdown file.' -ValueKind 'FilePath'
            New-PlaywrightCliOptionSpec -Tokens @('--depth') -Description 'Limit snapshot depth.' -ValueKind 'Number'
        )
        New-PlaywrightCliCommandSpec -Name 'eval' -Description 'Evaluate JavaScript expression on the page or an element.' -Positionals @('JavascriptExpression', 'Target') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'Save evaluation result to a file.' -ValueKind 'FilePath'
        )
        New-PlaywrightCliCommandSpec -Name 'dialog-accept' -Description 'Accept a dialog.' -Positionals @('PromptText') -Options @()
        New-PlaywrightCliCommandSpec -Name 'dialog-dismiss' -Description 'Dismiss a dialog.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'resize' -Description 'Resize the browser window.' -Positionals @('Number', 'Number') -Options @()
        New-PlaywrightCliCommandSpec -Name 'delete-data' -Description 'Delete session data.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'go-back' -Description 'Go back to the previous page.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'go-forward' -Description 'Go forward to the next page.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'reload' -Description 'Reload the current page.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'press' -Description 'Press a keyboard key.' -Positionals @('KeyboardKey') -Options @()
        New-PlaywrightCliCommandSpec -Name 'keydown' -Description 'Press a keyboard key down.' -Positionals @('KeyboardKey') -Options @()
        New-PlaywrightCliCommandSpec -Name 'keyup' -Description 'Release a keyboard key.' -Positionals @('KeyboardKey') -Options @()
        New-PlaywrightCliCommandSpec -Name 'mousemove' -Description 'Move mouse to a given position.' -Positionals @('Number', 'Number') -Options @()
        New-PlaywrightCliCommandSpec -Name 'mousedown' -Description 'Press mouse down.' -Positionals @('MouseButton') -Options @()
        New-PlaywrightCliCommandSpec -Name 'mouseup' -Description 'Press mouse up.' -Positionals @('MouseButton') -Options @()
        New-PlaywrightCliCommandSpec -Name 'mousewheel' -Description 'Scroll mouse wheel.' -Positionals @('Number', 'Number') -Options @()
        New-PlaywrightCliCommandSpec -Name 'screenshot' -Description 'Capture a screenshot of the current page or an element.' -Positionals @('Target') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'File name to save the screenshot to.' -ValueKind 'FilePath'
            New-PlaywrightCliOptionSpec -Tokens @('--full-page') -Description 'Capture the full scrollable page.'
        )
        New-PlaywrightCliCommandSpec -Name 'pdf' -Description 'Save the page as PDF.' -Positionals @() -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'File name to save the PDF to.' -ValueKind 'FilePath'
        )
        New-PlaywrightCliCommandSpec -Name 'tab-list' -Description 'List all tabs.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'tab-new' -Description 'Create a new tab.' -Positionals @('Url') -Options @()
        New-PlaywrightCliCommandSpec -Name 'tab-close' -Description 'Close a browser tab.' -Positionals @('Number') -Options @()
        New-PlaywrightCliCommandSpec -Name 'tab-select' -Description 'Select a browser tab.' -Positionals @('Number') -Options @()
        New-PlaywrightCliCommandSpec -Name 'state-load' -Description 'Load browser storage state from a file.' -Positionals @('FilePath') -Options @()
        New-PlaywrightCliCommandSpec -Name 'state-save' -Description 'Save browser storage state to a file.' -Positionals @('FilePath') -Options @()
        New-PlaywrightCliCommandSpec -Name 'cookie-list' -Description 'List all cookies.' -Positionals @() -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--domain') -Description 'Filter cookies by domain.' -ValueKind 'Domain'
            New-PlaywrightCliOptionSpec -Tokens @('--path') -Description 'Filter cookies by path.' -ValueKind 'CookiePath'
        )
        New-PlaywrightCliCommandSpec -Name 'cookie-get' -Description 'Get a cookie by name.' -Positionals @('CookieName') -Options @()
        New-PlaywrightCliCommandSpec -Name 'cookie-set' -Description 'Set a cookie with optional flags.' -Positionals @('CookieName', 'CookieValue') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--domain') -Description 'Cookie domain.' -ValueKind 'Domain'
            New-PlaywrightCliOptionSpec -Tokens @('--path') -Description 'Cookie path.' -ValueKind 'CookiePath'
            New-PlaywrightCliOptionSpec -Tokens @('--expires') -Description 'Cookie expiration as unix timestamp.' -ValueKind 'UnixTimestamp'
            New-PlaywrightCliOptionSpec -Tokens @('--httpOnly') -Description 'Set the cookie as HTTP-only.'
            New-PlaywrightCliOptionSpec -Tokens @('--secure') -Description 'Set the cookie as secure.'
            New-PlaywrightCliOptionSpec -Tokens @('--sameSite') -Description 'Cookie SameSite attribute.' -ValueKind 'CookieSameSite'
        )
        New-PlaywrightCliCommandSpec -Name 'cookie-delete' -Description 'Delete a specific cookie.' -Positionals @('CookieName') -Options @()
        New-PlaywrightCliCommandSpec -Name 'cookie-clear' -Description 'Clear all cookies.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'localstorage-list' -Description 'List all localStorage key-value pairs.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'localstorage-get' -Description 'Get a localStorage item by key.' -Positionals @('StorageKey') -Options @()
        New-PlaywrightCliCommandSpec -Name 'localstorage-set' -Description 'Set a localStorage item.' -Positionals @('StorageKey', 'StorageValue') -Options @()
        New-PlaywrightCliCommandSpec -Name 'localstorage-delete' -Description 'Delete a localStorage item.' -Positionals @('StorageKey') -Options @()
        New-PlaywrightCliCommandSpec -Name 'localstorage-clear' -Description 'Clear all localStorage.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'sessionstorage-list' -Description 'List all sessionStorage key-value pairs.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'sessionstorage-get' -Description 'Get a sessionStorage item by key.' -Positionals @('StorageKey') -Options @()
        New-PlaywrightCliCommandSpec -Name 'sessionstorage-set' -Description 'Set a sessionStorage item.' -Positionals @('StorageKey', 'StorageValue') -Options @()
        New-PlaywrightCliCommandSpec -Name 'sessionstorage-delete' -Description 'Delete a sessionStorage item.' -Positionals @('StorageKey') -Options @()
        New-PlaywrightCliCommandSpec -Name 'sessionstorage-clear' -Description 'Clear all sessionStorage.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'route' -Description 'Mock network requests matching a URL pattern.' -Positionals @('RoutePattern') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--status') -Description 'HTTP status code.' -ValueKind 'Number'
            New-PlaywrightCliOptionSpec -Tokens @('--body') -Description 'Response body text or JSON string.' -ValueKind 'ResponseBody'
            New-PlaywrightCliOptionSpec -Tokens @('--content-type') -Description 'Content-Type header.' -ValueKind 'ContentType'
            New-PlaywrightCliOptionSpec -Tokens @('--header') -Description 'Header in "name: value" format.' -ValueKind 'Header'
            New-PlaywrightCliOptionSpec -Tokens @('--remove-header') -Description 'Comma-separated header names to remove.' -ValueKind 'HeaderNameList'
        )
        New-PlaywrightCliCommandSpec -Name 'route-list' -Description 'List all active network routes.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'unroute' -Description 'Remove routes matching a pattern.' -Positionals @('RoutePattern') -Options @()
        New-PlaywrightCliCommandSpec -Name 'network-state-set' -Description 'Set the browser network state to online or offline.' -Positionals @('NetworkState') -Options @()
        New-PlaywrightCliCommandSpec -Name 'console' -Description 'List console messages.' -Positionals @('ConsoleLevel') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--clear') -Description 'Clear the console list.'
        )
        New-PlaywrightCliCommandSpec -Name 'run-code' -Description 'Run a Playwright code snippet.' -Positionals @('PlaywrightCode') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'Load code from the specified file.' -ValueKind 'FilePath'
        )
        New-PlaywrightCliCommandSpec -Name 'network' -Description 'List network requests since loading the page.' -Positionals @() -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--static') -Description 'Include successful static resources.'
            New-PlaywrightCliOptionSpec -Tokens @('--request-body') -Description 'Include request bodies.'
            New-PlaywrightCliOptionSpec -Tokens @('--request-headers') -Description 'Include request headers.'
            New-PlaywrightCliOptionSpec -Tokens @('--filter') -Description 'Only return requests whose URL matches this regexp.' -ValueKind 'RegexFilter'
            New-PlaywrightCliOptionSpec -Tokens @('--clear') -Description 'Clear the network list.'
        )
        New-PlaywrightCliCommandSpec -Name 'tracing-start' -Description 'Start trace recording.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'tracing-stop' -Description 'Stop trace recording.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'video-start' -Description 'Start video recording.' -Positionals @('FilePath') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--size') -Description 'Video frame size.' -ValueKind 'VideoSize'
        )
        New-PlaywrightCliCommandSpec -Name 'video-stop' -Description 'Stop video recording.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'video-chapter' -Description 'Add a chapter marker to the video recording.' -Positionals @('ChapterTitle') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--description') -Description 'Chapter description.' -ValueKind 'ChapterDescription'
            New-PlaywrightCliOptionSpec -Tokens @('--duration') -Description 'Duration in milliseconds for the chapter card.' -ValueKind 'Number'
        )
        New-PlaywrightCliCommandSpec -Name 'show' -Description 'Show browser DevTools.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'pause-at' -Description 'Run the test to a location and pause there.' -Positionals @('SourceLocation') -Options @()
        New-PlaywrightCliCommandSpec -Name 'resume' -Description 'Resume the test execution.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'step-over' -Description 'Step over the next call in the test.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'install' -Description 'Initialize the workspace.' -Positionals @() -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--skills') -Description 'Install skills.' -ValueKind 'SkillSet'
        )
        New-PlaywrightCliCommandSpec -Name 'install-browser' -Description 'Install browser binaries.' -Positionals @('InstallBrowser') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--with-deps') -Description 'Install system dependencies for browsers.'
            New-PlaywrightCliOptionSpec -Tokens @('--dry-run') -Description 'Print information without executing installation.'
            New-PlaywrightCliOptionSpec -Tokens @('--list') -Description 'Print list of browsers from all Playwright installations.'
            New-PlaywrightCliOptionSpec -Tokens @('--force') -Description 'Force reinstall of already installed browsers.'
            New-PlaywrightCliOptionSpec -Tokens @('--only-shell') -Description 'Only install the headless shell when installing Chromium.'
            New-PlaywrightCliOptionSpec -Tokens @('--no-shell') -Description 'Do not install Chromium headless shell.'
        )
        New-PlaywrightCliCommandSpec -Name 'list' -Description 'List browser sessions.' -Positionals @() -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--all') -Description 'List browser sessions across all workspaces.'
        )
        New-PlaywrightCliCommandSpec -Name 'close-all' -Description 'Close all browser sessions.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'kill-all' -Description 'Forcefully kill all browser sessions.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'help' -Description 'Display command help.' -Positionals @('CommandName') -Options @()
    )

    $commandLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($command in $commands) {
        $commandLookup[$command.Name] = $command
    }

    $script:PlaywrightCliMetadata = @{
        Commands             = $commands
        CommandLookup        = $commandLookup
        GlobalOptions        = @(
            New-PlaywrightCliOptionSpec -Tokens @('--help') -Description 'Print help for a command.' -ValueKind 'CommandName' -OptionalValue
            New-PlaywrightCliOptionSpec -Tokens @('--raw') -Description 'Output only the result value, without status and code.'
            New-PlaywrightCliOptionSpec -Tokens @('--version') -Description 'Print version.'
            New-PlaywrightCliOptionSpec -Tokens @('-s') -Description 'Session name for the command invocation.' -ValueKind 'SessionName' -CompletionText '-s='
        )
        BrowserValues        = @('chrome', 'firefox', 'webkit', 'msedge')
        InstallBrowserValues = @('chromium', 'chrome', 'firefox', 'webkit', 'msedge')
        MouseButtons         = @('left', 'right', 'middle')
        ModifierKeys         = @('Alt', 'Control', 'Meta', 'Shift')
        KeyboardKeys         = @(
            'Enter', 'Tab', 'Escape', 'Space', 'Backspace', 'Delete', 'Insert',
            'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
            'Home', 'End', 'PageUp', 'PageDown',
            'Control', 'Alt', 'Shift', 'Meta',
            'F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12'
        )
        NetworkStates        = @('online', 'offline')
        CookieSameSiteValues = @('Strict', 'Lax', 'None')
        SkillValues          = @('claude', 'agents')
        VideoSizes           = @('800x600', '1024x768', '1280x720', '1600x900', '1920x1080')
        ConsoleLevels        = @('debug', 'info', 'warning', 'warn', 'error')
        ContentTypes         = @('application/json', 'text/plain', 'text/html')
    }

    $script:PlaywrightCliMetadata
}

function Get-PlaywrightCliTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-PlaywrightCliProcessedTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [string]$WordToComplete
    )

    if ($CommandAst.CommandElements.Count -le 1) {
        return @()
    }

    $tokens = @(
        foreach ($element in @($CommandAst.CommandElements)[1..($CommandAst.CommandElements.Count - 1)]) {
            if ($null -eq $element) {
                continue
            }

            Get-PlaywrightCliTokenText -Element $element
        }
    )

    if ($tokens.Count -gt 0 -and -not [string]::IsNullOrEmpty($WordToComplete) -and $tokens[-1] -eq $WordToComplete) {
        if ($tokens.Count -eq 1) {
            return @()
        }

        return @($tokens[0..($tokens.Count - 2)])
    }

    @($tokens)
}

function Get-PlaywrightCliCommandSpec {
    param([string]$CommandName)

    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        return $null
    }

    $metadata = Get-PlaywrightCliMetadata
    if ($metadata.CommandLookup.ContainsKey($CommandName)) {
        return $metadata.CommandLookup[$CommandName]
    }

    $null
}

function Find-PlaywrightCliOptionSpec {
    param(
        [string]$Token,
        [object[]]$Options
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $normalizedToken = if ($Token.Contains('=')) {
        $Token.Substring(0, $Token.IndexOf('='))
    } else {
        $Token
    }

    foreach ($option in @($Options)) {
        if ($option.Token.TrimEnd('=').Equals($normalizedToken, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $option
        }
    }

    $null
}

function Get-PlaywrightCliPathCompletions {
    param(
        [string]$PathPrefix,
        [switch]$DirectoriesOnly,
        [string]$CompletionPrefix = ''
    )

    $items = [System.Management.Automation.CompletionCompleters]::CompleteFilename($PathPrefix)
    foreach ($item in @($items)) {
        if ($DirectoriesOnly -and -not (Test-Path -LiteralPath $item.CompletionText -PathType Container)) {
            continue
        }

        if ([string]::IsNullOrEmpty($CompletionPrefix)) {
            $item
            continue
        }

        New-PlaywrightCliCompletionResult `
            -CompletionText "$CompletionPrefix$($item.CompletionText)" `
            -ListItemText $item.ListItemText `
            -ResultType $item.ResultType `
            -ToolTip $item.ToolTip
    }
}

function Get-PlaywrightCliValueCompletions {
    param(
        [string]$ValueKind,
        [string]$WordToComplete,
        [string]$ContextToken,
        [string]$InlinePrefix
    )

    $metadata = Get-PlaywrightCliMetadata
    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    $addResult = {
        param(
            [string]$completionText,
            [string]$toolTip,
            [string]$resultType = 'ParameterValue',
            [string]$listItemText = $completionText
        )

        if ([string]::IsNullOrWhiteSpace($completionText)) {
            return
        }

        if ($completionText -notlike "$WordToComplete*") {
            return
        }

        $finalCompletion = if ([string]::IsNullOrEmpty($InlinePrefix)) {
            $completionText
        } else {
            "$InlinePrefix$completionText"
        }

        $finalListItemText = if ([string]::IsNullOrEmpty($InlinePrefix)) {
            $listItemText
        } else {
            $completionText
        }

        [void]$results.Add(
            (New-PlaywrightCliCompletionResult -CompletionText $finalCompletion -ListItemText $finalListItemText -ResultType $resultType -ToolTip $toolTip)
        )
    }

    switch ($ValueKind) {
        'CommandName' {
            foreach ($command in $metadata.Commands) {
                & $addResult $command.Name $command.Description
            }
        }
        'Browser' {
            foreach ($value in $metadata.BrowserValues) {
                & $addResult $value "Browser value for $ContextToken"
            }
        }
        'InstallBrowser' {
            foreach ($value in $metadata.InstallBrowserValues) {
                & $addResult $value 'Browser to install'
            }
        }
        'MouseButton' {
            foreach ($value in $metadata.MouseButtons) {
                & $addResult $value "Mouse button for $ContextToken"
            }
        }
        'ModifierKeys' {
            $prefix = ''
            $valuePrefix = $WordToComplete
            if ($WordToComplete -like '*,*') {
                $lastComma = $WordToComplete.LastIndexOf(',')
                $prefix = $WordToComplete.Substring(0, $lastComma + 1)
                $valuePrefix = $WordToComplete.Substring($lastComma + 1)
            }

            foreach ($value in $metadata.ModifierKeys) {
                if ($value -notlike "$valuePrefix*") {
                    continue
                }

                & $addResult "$prefix$value" 'Modifier key'
            }
        }
        'KeyboardKey' {
            foreach ($value in $metadata.KeyboardKeys) {
                & $addResult $value 'Keyboard key'
            }

            & $addResult '<key>' "Key value for $ContextToken"
        }
        'NetworkState' {
            foreach ($value in $metadata.NetworkStates) {
                & $addResult $value 'Network state'
            }
        }
        'CookieSameSite' {
            foreach ($value in $metadata.CookieSameSiteValues) {
                & $addResult $value 'SameSite value'
            }
        }
        'SkillSet' {
            foreach ($value in $metadata.SkillValues) {
                & $addResult $value 'Skill set to install'
            }
        }
        'VideoSize' {
            foreach ($value in $metadata.VideoSizes) {
                & $addResult $value 'Video frame size'
            }
        }
        'ConsoleLevel' {
            foreach ($value in $metadata.ConsoleLevels) {
                & $addResult $value 'Minimum console level'
            }
        }
        'ContentType' {
            foreach ($value in $metadata.ContentTypes) {
                & $addResult $value 'Content-Type value'
            }
        }
        'FilePath' {
            foreach ($item in @(Get-PlaywrightCliPathCompletions -PathPrefix $WordToComplete -CompletionPrefix $InlinePrefix)) {
                [void]$results.Add($item)
            }
        }
        'DirectoryPath' {
            foreach ($item in @(Get-PlaywrightCliPathCompletions -PathPrefix $WordToComplete -DirectoriesOnly -CompletionPrefix $InlinePrefix)) {
                [void]$results.Add($item)
            }
        }
        'Url' {
            & $addResult 'https://' "URL value for $ContextToken"
            & $addResult 'http://' "URL value for $ContextToken"
        }
        'SessionName' {
            & $addResult '<session>' "Session name for $ContextToken"
        }
        'SessionTarget' {
            & $addResult '<name>' 'Bound browser name to attach to'
        }
        'Target' {
            & $addResult '<target>' 'Exact element reference or selector'
        }
        'Text' {
            & $addResult '<text>' "Text value for $ContextToken"
        }
        'DropdownValue' {
            & $addResult '<value>' 'Dropdown value'
        }
        'PromptText' {
            & $addResult '<prompt>' 'Prompt text for the dialog'
        }
        'CookieName' {
            & $addResult '<name>' 'Cookie name'
        }
        'CookieValue' {
            & $addResult '<value>' 'Cookie value'
        }
        'StorageKey' {
            & $addResult '<key>' 'Storage key'
        }
        'StorageValue' {
            & $addResult '<value>' 'Storage value'
        }
        'RoutePattern' {
            & $addResult '**/api/*' 'URL pattern such as **/api/*'
            & $addResult '<pattern>' 'URL pattern to match'
        }
        'ResponseBody' {
            & $addResult '<body>' 'Response body text or JSON string'
        }
        'Header' {
            & $addResult '<name: value>' 'Header in "name: value" format'
        }
        'HeaderNameList' {
            & $addResult '<name1,name2>' 'Comma-separated header names'
        }
        'Domain' {
            & $addResult '<domain>' 'Domain value'
        }
        'CookiePath' {
            & $addResult '/' 'Cookie path'
            & $addResult '<path>' 'Cookie path value'
        }
        'JavascriptExpression' {
            & $addResult '() => { }' 'JavaScript expression to evaluate'
            & $addResult '(element) => { }' 'JavaScript expression that receives the element'
        }
        'PlaywrightCode' {
            & $addResult 'async page => { }' 'Playwright code snippet'
            & $addResult '<code>' 'Playwright code snippet'
        }
        'Number' {
            & $addResult '<n>' "Numeric value for $ContextToken"
        }
        'UnixTimestamp' {
            & $addResult '<unix-timestamp>' 'Unix timestamp value'
        }
        'RegexFilter' {
            & $addResult '/api/.*' 'Regular expression filter'
            & $addResult '<regex>' 'Regular expression filter'
        }
        'ChapterTitle' {
            & $addResult '<title>' 'Chapter title'
        }
        'ChapterDescription' {
            & $addResult '<description>' 'Chapter description'
        }
        'SourceLocation' {
            & $addResult '<file>:<line>' 'Source location such as example.spec.ts:42'
        }
        default {
            & $addResult '<value>' "Value for $ContextToken"
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($results)) {
        if ($seen.Add($item.CompletionText)) {
            $item
        }
    }
}

function Get-PlaywrightCliOptionCompletions {
    param(
        [object[]]$Options,
        [string]$WordToComplete
    )

    foreach ($option in @($Options)) {
        $completionText = $option.CompletionText
        if ($completionText -notlike "$WordToComplete*") {
            continue
        }

        $toolTip = if ($option.ValueKind) {
            "$($option.Token): $($option.Description)"
        } else {
            $option.Description
        }

        New-PlaywrightCliCompletionResult -CompletionText $completionText -ResultType 'ParameterName' -ToolTip $toolTip
    }
}

function Complete-PlaywrightCli {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $null = $CursorPosition
    $metadata = Get-PlaywrightCliMetadata
    $tokens = @(Get-PlaywrightCliProcessedTokens -CommandAst $CommandAst -WordToComplete $WordToComplete)
    $commandSpec = $null
    $positionalsConsumed = 0
    $expectingValue = $null

    foreach ($token in @($tokens)) {
        if ($expectingValue) {
            $consumeAsValue = $true

            if (-not $commandSpec -and $expectingValue.OptionalValue -and $expectingValue.Token -ne '--help') {
                if (Get-PlaywrightCliCommandSpec -CommandName $token) {
                    $consumeAsValue = $false
                }
            }

            if ($consumeAsValue) {
                $expectingValue = $null
                continue
            }

            $expectingValue = $null
        }

        if (-not $commandSpec) {
            if ($token.StartsWith('-')) {
                $globalOption = Find-PlaywrightCliOptionSpec -Token $token -Options $metadata.GlobalOptions
                if ($globalOption) {
                    if (-not $token.Contains('=') -and $globalOption.ValueKind) {
                        $expectingValue = $globalOption
                    }

                    continue
                }

                continue
            }

            $resolvedCommand = Get-PlaywrightCliCommandSpec -CommandName $token
            if ($resolvedCommand) {
                $commandSpec = $resolvedCommand
            }

            continue
        }

        if ($token.StartsWith('-')) {
            $commandOption = Find-PlaywrightCliOptionSpec -Token $token -Options $commandSpec.Options
            if ($commandOption) {
                if (-not $token.Contains('=') -and $commandOption.ValueKind) {
                    $expectingValue = $commandOption
                }

                continue
            }

            continue
        }

        $positionalsConsumed++
    }

    if ($expectingValue -and $expectingValue.OptionalValue -and $WordToComplete -like '-*') {
        $expectingValue = $null
    }

    if ([string]::IsNullOrEmpty($WordToComplete) -and $tokens.Count -gt 0 -and $tokens[-1].EndsWith('=')) {
        $options = if ($commandSpec) { @($metadata.GlobalOptions + $commandSpec.Options) } else { $metadata.GlobalOptions }
        $inlineEmptyValueOption = Find-PlaywrightCliOptionSpec -Token $tokens[-1] -Options $options
        if ($inlineEmptyValueOption -and $inlineEmptyValueOption.ValueKind) {
            Get-PlaywrightCliValueCompletions -ValueKind $inlineEmptyValueOption.ValueKind -WordToComplete '' -ContextToken $inlineEmptyValueOption.Token -InlinePrefix $tokens[-1]
            return
        }
    }

    if ($WordToComplete -like '*=*') {
        $equalsIndex = $WordToComplete.IndexOf('=')
        $flagPart = $WordToComplete.Substring(0, $equalsIndex)
        $valuePrefix = $WordToComplete.Substring($equalsIndex + 1)
        $options = if ($commandSpec) { @($metadata.GlobalOptions + $commandSpec.Options) } else { $metadata.GlobalOptions }
        $inlineOption = Find-PlaywrightCliOptionSpec -Token $flagPart -Options $options
        if ($inlineOption -and $inlineOption.ValueKind) {
            Get-PlaywrightCliValueCompletions -ValueKind $inlineOption.ValueKind -WordToComplete $valuePrefix -ContextToken $inlineOption.Token -InlinePrefix "$flagPart="
            return
        }
    }

    if ($expectingValue) {
        Get-PlaywrightCliValueCompletions -ValueKind $expectingValue.ValueKind -WordToComplete $WordToComplete -ContextToken $expectingValue.Token
        return
    }

    if ($WordToComplete -like '-*') {
        $options = if ($commandSpec) { @($metadata.GlobalOptions + $commandSpec.Options) } else { $metadata.GlobalOptions }
        Get-PlaywrightCliOptionCompletions -Options $options -WordToComplete $WordToComplete
        return
    }

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    if (-not $commandSpec) {
        foreach ($command in $metadata.Commands) {
            if ($command.Name -like "$WordToComplete*") {
                [void]$results.Add(
                    (New-PlaywrightCliCompletionResult -CompletionText $command.Name -ToolTip $command.Description)
                )
            }
        }

        if ([string]::IsNullOrEmpty($WordToComplete)) {
            foreach ($option in @(Get-PlaywrightCliOptionCompletions -Options $metadata.GlobalOptions -WordToComplete '')) {
                [void]$results.Add($option)
            }
        }
    } else {
        $valueKind = if ($positionalsConsumed -lt $commandSpec.Positionals.Count) {
            $commandSpec.Positionals[$positionalsConsumed]
        } else {
            $null
        }

        if ($valueKind) {
            foreach ($item in @(Get-PlaywrightCliValueCompletions -ValueKind $valueKind -WordToComplete $WordToComplete -ContextToken $commandSpec.Name)) {
                [void]$results.Add($item)
            }
        }

        if ([string]::IsNullOrEmpty($WordToComplete)) {
            foreach ($option in @(Get-PlaywrightCliOptionCompletions -Options $commandSpec.Options -WordToComplete '')) {
                [void]$results.Add($option)
            }
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($results)) {
        if ($seen.Add($item.CompletionText)) {
            $item
        }
    }
}

Register-ArgumentCompleter -Native -CommandName @('playwright-cli', 'playwright-cli.cmd', 'playwright-cli.ps1') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-PlaywrightCli -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
