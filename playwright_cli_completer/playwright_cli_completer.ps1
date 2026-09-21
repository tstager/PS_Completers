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

function Get-PlaywrightCliHelpCatalog {
    # @playwright/cli ships a machine-readable catalog next to the launcher; one cached read, no
    # process spawn. Returns $null when the tool or the file is absent so the static table serves.
    $command = Get-Command -Name playwright-cli.ps1, playwright-cli.cmd, playwright-cli -ErrorAction Ignore | Select-Object -First 1
    if (-not $command -or [string]::IsNullOrWhiteSpace($command.Source)) {
        return $null
    }

    $root = Split-Path -Path $command.Source -Parent
    $candidates = @(
        (Join-Path -Path $root -ChildPath 'node_modules\@playwright\cli\node_modules\playwright-core\lib\tools\cli-client\help.json')
        (Join-Path -Path $root -ChildPath 'node_modules\playwright-core\lib\tools\cli-client\help.json')
    )

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }

        try {
            $catalog = Get-Content -LiteralPath $candidate -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
            if ($catalog -is [System.Collections.IDictionary] -and $catalog.Contains('commands')) {
                return $catalog
            }
        } catch {
            Write-Debug -Message $_.Exception.Message
        }
    }

    $null
}

function Merge-PlaywrightCliHelpCatalog {
    param(
        [object[]]$StaticCommands,
        [System.Collections.IDictionary]$Catalog
    )

    # The catalog decides which commands exist and which flags each one takes; the static table
    # contributes value kinds and wording for the entries it knows. Static-only commands are stale.
    $staticLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($command in @($StaticCommands)) {
        $staticLookup[$command.Name] = $command
    }

    foreach ($name in @($Catalog['commands'].Keys)) {
        $entry = $Catalog['commands'][$name]
        $helpLines = @([string]$entry['help'] -split "`r?`n")
        $description = ''
        foreach ($line in @($helpLines | Select-Object -Skip 1)) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                if ($description) { break }
                continue
            }
            if ($line -match '^(Arguments|Options):') {
                break
            }
            $description = ($description + ' ' + $line.Trim()).Trim()
        }
        if ($description -and -not $description.EndsWith('.')) {
            $description += '.'
        }

        $flagDescriptions = @{}
        foreach ($line in $helpLines) {
            if ($line -match '^\s+--(?<flag>[A-Za-z0-9-]+)\s+(?<text>\S.*)$') {
                $flagDescriptions[$matches.flag] = $matches.text.Trim()
            }
        }

        $static = if ($staticLookup.ContainsKey($name)) { $staticLookup[$name] } else { $null }
        $options = [System.Collections.Generic.List[object]]::new()
        if ($static) {
            foreach ($option in @($static.Options)) {
                [void]$options.Add($option)
            }
        }

        $flags = $entry['flags']
        if ($flags -is [System.Collections.IDictionary]) {
            foreach ($flag in @($flags.Keys)) {
                $token = "--$flag"
                if (Find-PlaywrightCliOptionSpec -Token $token -Options $options.ToArray()) {
                    continue
                }

                $flagDescription = if ($flagDescriptions.ContainsKey($flag)) { $flagDescriptions[$flag] } else { "Option $token." }
                $flagDescription = $flagDescription.Substring(0, 1).ToUpperInvariant() + $flagDescription.Substring(1)
                if ([string]$flags[$flag] -eq 'boolean') {
                    [void]$options.Add((New-PlaywrightCliOptionSpec -Tokens @($token) -Description $flagDescription))
                } else {
                    [void]$options.Add((New-PlaywrightCliOptionSpec -Tokens @($token) -Description $flagDescription -ValueKind 'Value'))
                }
            }
        }

        $positionals = if ($static) {
            @($static.Positionals)
        } else {
            @(@($entry['args']) | ForEach-Object { 'Value' })
        }

        $commandDescription = if ($static -and $static.Description) { $static.Description } elseif ($description) { $description } else { "playwright-cli $name." }
        New-PlaywrightCliCommandSpec -Name $name -Description $commandDescription -Positionals $positionals -Options $options.ToArray()
    }
}

function Get-PlaywrightCliMetadata {
    if (Get-Variable -Name PlaywrightCliMetadata -Scope Script -ErrorAction Ignore) {
        return $script:PlaywrightCliMetadata
    }

    $commands = @(
        New-PlaywrightCliCommandSpec -Name 'open' -Description 'Open the browser.' -Positionals @('Url') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--browser') -Description 'Browser or chrome channel to use.' -ValueKind 'Browser'
            New-PlaywrightCliOptionSpec -Tokens @('--config') -Description 'Path to the configuration file.' -ValueKind 'FilePath'
            New-PlaywrightCliOptionSpec -Tokens @('--device') -Description 'Emulate a specific device, for example "iPhone 15".' -ValueKind 'DeviceName'
            New-PlaywrightCliOptionSpec -Tokens @('--headed') -Description 'Run browser in headed mode.'
            New-PlaywrightCliOptionSpec -Tokens @('--mobile') -Description 'Emulate a generic mobile device.'
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
        New-PlaywrightCliCommandSpec -Name 'detach' -Description 'Detach from an attached browser.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'goto' -Description 'Navigate to a URL.' -Positionals @('Url') -Options @()
        New-PlaywrightCliCommandSpec -Name 'type' -Description 'Type text into the active editable element.' -Positionals @('Text') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--submit') -Description 'Press Enter after typing the text.'
        )
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
        New-PlaywrightCliCommandSpec -Name 'drop' -Description 'Drop files or data onto an element.' -Positionals @('Target') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--path') -Description 'Absolute path to a file to drop onto the element (repeatable).' -ValueKind 'FilePath'
            New-PlaywrightCliOptionSpec -Tokens @('--data') -Description 'Data to drop in "mime/type=value" format (repeatable).' -ValueKind 'DropData'
        )
        New-PlaywrightCliCommandSpec -Name 'hover' -Description 'Hover over an element on the page.' -Positionals @('Target') -Options @()
        New-PlaywrightCliCommandSpec -Name 'select' -Description 'Select an option in a dropdown.' -Positionals @('Target', 'DropdownValue') -Options @()
        New-PlaywrightCliCommandSpec -Name 'upload' -Description 'Upload one or more files.' -Positionals @('FilePath') -Options @()
        New-PlaywrightCliCommandSpec -Name 'check' -Description 'Check a checkbox or radio button.' -Positionals @('Target') -Options @()
        New-PlaywrightCliCommandSpec -Name 'uncheck' -Description 'Uncheck a checkbox or radio button.' -Positionals @('Target') -Options @()
        New-PlaywrightCliCommandSpec -Name 'snapshot' -Description 'Capture page snapshot to obtain element references.' -Positionals @('Target') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'Save snapshot to a markdown file.' -ValueKind 'FilePath'
            New-PlaywrightCliOptionSpec -Tokens @('--depth') -Description 'Limit snapshot depth.' -ValueKind 'Number'
            New-PlaywrightCliOptionSpec -Tokens @('--boxes') -Description 'Include each element''s bounding box in the snapshot.'
        )
        New-PlaywrightCliCommandSpec -Name 'find' -Description 'Search the page snapshot for text or a regexp.' -Positionals @('Text') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--regex') -Description 'Regular expression to search for instead of plain text.' -ValueKind 'RegexFilter'
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
            New-PlaywrightCliOptionSpec -Tokens @('--type') -Description 'Image format; inferred from the filename extension when unset.' -ValueKind 'ImageFormat'
            New-PlaywrightCliOptionSpec -Tokens @('--full-page') -Description 'Capture the full scrollable page.'
            New-PlaywrightCliOptionSpec -Tokens @('--hires') -Description 'Capture a high-resolution screenshot using device pixels.'
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
        New-PlaywrightCliCommandSpec -Name 'set-color-scheme' -Description 'Emulate the light or dark color scheme.' -Positionals @('ColorScheme') -Options @()
        New-PlaywrightCliCommandSpec -Name 'set-reduced-motion' -Description 'Emulate the reduced motion preference.' -Positionals @('ReducedMotion') -Options @()
        New-PlaywrightCliCommandSpec -Name 'set-forced-colors' -Description 'Emulate forced colors mode.' -Positionals @('ForcedColors') -Options @()
        New-PlaywrightCliCommandSpec -Name 'set-contrast' -Description 'Emulate the preferred contrast.' -Positionals @('Contrast') -Options @()
        New-PlaywrightCliCommandSpec -Name 'set-media' -Description 'Emulate the CSS media type.' -Positionals @('MediaType') -Options @()
        New-PlaywrightCliCommandSpec -Name 'clear-color-scheme' -Description 'Clear color scheme emulation.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'clear-reduced-motion' -Description 'Clear reduced motion emulation.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'clear-forced-colors' -Description 'Clear forced colors emulation.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'clear-contrast' -Description 'Clear contrast emulation.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'clear-media' -Description 'Clear CSS media type emulation.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'route' -Description 'Mock network requests matching a URL pattern.' -Positionals @('RoutePattern') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--status') -Description 'HTTP status code.' -ValueKind 'Number'
            New-PlaywrightCliOptionSpec -Tokens @('--body') -Description 'Response body text or JSON string.' -ValueKind 'ResponseBody'
            New-PlaywrightCliOptionSpec -Tokens @('--content-type') -Description 'Content-Type header.' -ValueKind 'ContentType'
            New-PlaywrightCliOptionSpec -Tokens @('--header') -Description 'Header in "name: value" format.' -ValueKind 'Header'
            New-PlaywrightCliOptionSpec -Tokens @('--remove-header') -Description 'Comma-separated header names to remove.' -ValueKind 'HeaderNameList'
        )
        New-PlaywrightCliCommandSpec -Name 'route-list' -Description 'List all active network routes.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'unroute' -Description 'Remove routes matching a pattern.' -Positionals @('RoutePattern') -Options @()
        New-PlaywrightCliCommandSpec -Name 'requests' -Description 'List all network requests since loading the page, numbered for the request command.' -Positionals @() -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--static') -Description 'Include successful static resources such as images, fonts and scripts.'
            New-PlaywrightCliOptionSpec -Tokens @('--filter') -Description 'Only return requests whose URL matches this regexp.' -ValueKind 'RegexFilter'
            New-PlaywrightCliOptionSpec -Tokens @('--clear') -Description 'Clear the network list.'
        )
        New-PlaywrightCliCommandSpec -Name 'request' -Description 'Show full details of a single network request by its number.' -Positionals @('RequestIndex') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'Save the result to a file instead of returning it as text.' -ValueKind 'FilePath'
        )
        New-PlaywrightCliCommandSpec -Name 'request-headers' -Description 'Print only the request headers of a single network request.' -Positionals @('RequestIndex') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'Save the result to a file instead of returning it as text.' -ValueKind 'FilePath'
        )
        New-PlaywrightCliCommandSpec -Name 'request-body' -Description 'Print only the request body of a single network request.' -Positionals @('RequestIndex') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'Save the result to a file instead of returning it as text.' -ValueKind 'FilePath'
        )
        New-PlaywrightCliCommandSpec -Name 'response-headers' -Description 'Print only the response headers of a single network request.' -Positionals @('RequestIndex') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'Save the result to a file instead of returning it as text.' -ValueKind 'FilePath'
        )
        New-PlaywrightCliCommandSpec -Name 'response-body' -Description 'Print the response body of a single network request.' -Positionals @('RequestIndex') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'Save the result to a file instead of returning it as text.' -ValueKind 'FilePath'
        )
        New-PlaywrightCliCommandSpec -Name 'network-state-set' -Description 'Set the browser network state to online or offline.' -Positionals @('NetworkState') -Options @()
        New-PlaywrightCliCommandSpec -Name 'console' -Description 'List console messages.' -Positionals @('ConsoleLevel') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--clear') -Description 'Clear the console list.'
        )
        New-PlaywrightCliCommandSpec -Name 'run-code' -Description 'Run a Playwright code snippet.' -Positionals @('PlaywrightCode') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--filename') -Description 'Load code from the specified file.' -ValueKind 'FilePath'
        )
        New-PlaywrightCliCommandSpec -Name 'recording-start' -Description 'Start recording user actions.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'recording-stop' -Description 'Stop recording user actions and print them as Playwright code.' -Positionals @() -Options @()
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
        New-PlaywrightCliCommandSpec -Name 'video-show-actions' -Description 'Annotate subsequent actions on the page with a callout and target highlight.' -Positionals @() -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--duration') -Description 'How long each action annotation stays on screen, in milliseconds.' -ValueKind 'Number'
            New-PlaywrightCliOptionSpec -Tokens @('--position') -Description 'Where to place the action title.' -ValueKind 'ActionPosition'
            New-PlaywrightCliOptionSpec -Tokens @('--cursor') -Description 'Cursor decoration between action points.' -ValueKind 'CursorStyle'
        )
        New-PlaywrightCliCommandSpec -Name 'video-hide-actions' -Description 'Stop annotating actions performed on the page.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'show' -Description 'Show the Playwright dashboard.' -Positionals @() -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--port') -Description 'Start as a blocking HTTP server on this port (0 picks a random port).' -ValueKind 'Number'
            New-PlaywrightCliOptionSpec -Tokens @('--host') -Description 'Host to bind to when using --port.' -ValueKind 'HostName'
            New-PlaywrightCliOptionSpec -Tokens @('--annotate') -Description 'Switch the dashboard into annotation mode.'
            New-PlaywrightCliOptionSpec -Tokens @('--kill') -Description 'Kill the dashboard daemon.'
        )
        New-PlaywrightCliCommandSpec -Name 'pause-at' -Description 'Run the test to a location and pause there.' -Positionals @('SourceLocation') -Options @()
        New-PlaywrightCliCommandSpec -Name 'resume' -Description 'Resume the test execution.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'step-over' -Description 'Step over the next call in the test.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'generate-locator' -Description 'Generate a Playwright locator for the given element.' -Positionals @('Target') -Options @()
        New-PlaywrightCliCommandSpec -Name 'highlight' -Description 'Show (or with --hide, remove) a highlight overlay for an element.' -Positionals @('Target') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--hide') -Description 'Hide the highlight for this element, or all highlights when no element is given.'
            New-PlaywrightCliOptionSpec -Tokens @('--style') -Description 'Additional inline CSS applied to the highlight overlay.' -ValueKind 'CssStyle'
        )
        New-PlaywrightCliCommandSpec -Name 'config-print' -Description 'Print the effective configuration.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'install' -Description 'Initialize the workspace.' -Positionals @() -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--skills') -Description 'Install skills.' -ValueKind 'SkillSet'
            New-PlaywrightCliOptionSpec -Tokens @('--global') -Description 'Install skills into the home directory instead of the workspace (requires --skills).'
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
        New-PlaywrightCliCommandSpec -Name 'webmcp-list' -Description 'List the WebMCP tools registered by the page.' -Positionals @() -Options @()
        New-PlaywrightCliCommandSpec -Name 'webmcp-call' -Description 'Call a WebMCP tool registered by the page.' -Positionals @('WebMcpToolName') -Options @(
            New-PlaywrightCliOptionSpec -Tokens @('--params') -Description 'Tool input parameters as a JSON object.' -ValueKind 'JsonObject'
            New-PlaywrightCliOptionSpec -Tokens @('--frame') -Description 'Frame that registered the tool, as reported by webmcp-list.' -ValueKind 'FrameName'
        )
        New-PlaywrightCliCommandSpec -Name 'tray' -Description 'Run the Playwright tray application.' -Positionals @() -Options @()
    )

    $catalog = Get-PlaywrightCliHelpCatalog
    if ($catalog) {
        $commands = @(Merge-PlaywrightCliHelpCatalog -StaticCommands $commands -Catalog $catalog)
    }

    $commandLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($command in $commands) {
        $commandLookup[$command.Name] = $command
    }

    $script:PlaywrightCliMetadata = @{
        Commands             = $commands
        CommandLookup        = $commandLookup
        GlobalOptions        = @(
            New-PlaywrightCliOptionSpec -Tokens @('--help') -Description 'Print help for a command.' -ValueKind 'CommandName' -OptionalValue
            New-PlaywrightCliOptionSpec -Tokens @('--json') -Description 'Output the response as JSON.'
            New-PlaywrightCliOptionSpec -Tokens @('--raw') -Description 'Output only the result value, without status and code.'
            New-PlaywrightCliOptionSpec -Tokens @('--version') -Description 'Print version.'
            New-PlaywrightCliOptionSpec -Tokens @('-s') -Description 'Session name for the command invocation.' -ValueKind 'SessionName' -CompletionText '-s='
        )
        BrowserValues        = @('chrome', 'firefox', 'webkit', 'msedge')
        InstallBrowserValues = @(
            'chromium', 'chromium-headless-shell', 'chrome', 'chrome-beta', 'chrome-dev', 'chrome-canary',
            'firefox', 'webkit', 'msedge', 'msedge-beta', 'msedge-dev', 'msedge-canary'
        )
        MouseButtons         = @('left', 'right', 'middle')
        ModifierKeys         = @('Alt', 'Control', 'ControlOrMeta', 'Meta', 'Shift')
        ImageFormats         = @('png', 'jpeg', 'webp')
        ActionPositions      = @('top-left', 'top', 'top-right', 'bottom-left', 'bottom', 'bottom-right')
        CursorStyles         = @('pointer', 'none')
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
        ColorSchemes         = @('light', 'dark', 'no-preference')
        ReducedMotionValues  = @('reduce', 'no-preference')
        ForcedColorsValues   = @('active', 'none')
        ContrastValues       = @('more', 'no-preference')
        MediaTypes           = @('screen', 'print')
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
        [string]$WordToComplete,
        [int]$CursorPosition
    )

    if ($CommandAst.CommandElements.Count -le 1) {
        return @()
    }

    # Only the elements left of the cursor have been "processed"; the element that contains the
    # cursor is the word being completed and anything right of it is ignored. Extent offsets and
    # $CursorPosition are both absolute within the input line.
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($null -eq $element -or $element.Extent.StartOffset -ge $CursorPosition) {
            break
        }

        if ($element.Extent.EndOffset -ge $CursorPosition) {
            break
        }

        [void]$tokens.Add((Get-PlaywrightCliTokenText -Element $element))
    }

    # A word PowerShell hands over that still sits at the end of the list (an empty cursor
    # position, or a token that ends exactly at the cursor) is the current word, not a processed one.
    if ($tokens.Count -gt 0 -and -not [string]::IsNullOrEmpty($WordToComplete) -and $tokens[$tokens.Count - 1] -eq $WordToComplete) {
        $tokens.RemoveAt($tokens.Count - 1)
    }

    @($tokens.ToArray())
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
        # CompleteFilename already quotes a path with spaces, so Test-Path on CompletionText would
        # drop every such directory; its ResultType says whether the entry is a container.
        if ($DirectoriesOnly -and $item.ResultType -ne [System.Management.Automation.CompletionResultType]::ProviderContainer) {
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

        if ($completionText -notlike ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
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
                if ($value -notlike ([System.Management.Automation.WildcardPattern]::Escape($valuePrefix) + '*')) {
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
        'ImageFormat' {
            foreach ($value in $metadata.ImageFormats) {
                & $addResult $value 'Screenshot image format'
            }
        }
        'ActionPosition' {
            foreach ($value in $metadata.ActionPositions) {
                & $addResult $value 'Action title position'
            }
        }
        'CursorStyle' {
            foreach ($value in $metadata.CursorStyles) {
                & $addResult $value 'Cursor decoration'
            }
        }
        'RequestIndex' {
            & $addResult '<index>' '1-based request number as listed by requests'
        }
        'DeviceName' {
            & $addResult '<device>' 'Device to emulate, for example "iPhone 15"'
        }
        'HostName' {
            & $addResult 'localhost' 'Host to bind to'
            & $addResult '<host>' 'Host to bind to'
        }
        'DropData' {
            & $addResult '<mime/type=value>' 'Data to drop, for example text/plain=hello'
        }
        'CssStyle' {
            & $addResult '<css>' 'Inline CSS, for example "outline: 2px dashed red"'
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
        'ColorScheme' {
            foreach ($value in $metadata.ColorSchemes) {
                & $addResult $value 'Color scheme to emulate'
            }
        }
        'ReducedMotion' {
            foreach ($value in $metadata.ReducedMotionValues) {
                & $addResult $value 'Reduced motion preference to emulate'
            }
        }
        'ForcedColors' {
            foreach ($value in $metadata.ForcedColorsValues) {
                & $addResult $value 'Forced colors mode to emulate'
            }
        }
        'Contrast' {
            foreach ($value in $metadata.ContrastValues) {
                & $addResult $value 'Contrast preference to emulate'
            }
        }
        'MediaType' {
            foreach ($value in $metadata.MediaTypes) {
                & $addResult $value 'CSS media type to emulate'
            }
        }
        'WebMcpToolName' {
            & $addResult '<name>' 'Name of the WebMCP tool to call'
        }
        'JsonObject' {
            & $addResult '<json>' "JSON object for $ContextToken"
        }
        'FrameName' {
            & $addResult '<frame>' 'Frame that registered the tool'
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
        if ($completionText -notlike ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
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

    $metadata = Get-PlaywrightCliMetadata
    $tokens = @(Get-PlaywrightCliProcessedTokens -CommandAst $CommandAst -WordToComplete $WordToComplete -CursorPosition $CursorPosition)
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
            if ($command.Name -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*')) {
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
