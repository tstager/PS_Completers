using namespace System.Management.Automation
using namespace System.Management.Automation.Language

if (-not (Get-Variable -Name DscCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:DscCompletionCache = @{ ManifestKey = $null; ManifestTime = 0L; Manifests = $null; FunctionKey = $null; Functions = $null }
}

function Resolve-DscCompletionExecutable {
    # A direct PATH probe: Get-Command's first application lookup costs about a second, and so do
    # 60 cold Join-Path calls; [System.IO.Path] takes milliseconds.
    $fileName = if ($IsWindows) { 'dsc.exe' } else { 'dsc' }
    foreach ($directory in $env:PATH -split [System.IO.Path]::PathSeparator) {
        if ($directory) {
            $candidate = [System.IO.Path]::Combine($directory, $fileName)
            if ([System.IO.File]::Exists($candidate)) {
                return $candidate
            }
        }
    }

    $null
}

function Get-DscCompletionManifest {
    # Resource, adapter and extension names, read passively from the manifests dsc itself discovers:
    # the resource path (DSC_RESOURCE_PATH, else PATH, plus dsc's own folder), the top-level files of
    # every installed Appx package (the Appx discover extension), and the manifest paths cached by the
    # PowerShell discover extension. 'dsc resource list' walks the same files but takes tens of seconds.
    $cache = $script:DscCompletionCache
    $key = "$env:DSC_RESOURCE_PATH|$env:PATH"
    if ($cache.ManifestKey -eq $key -and [Environment]::TickCount64 -lt $cache.ManifestTime + 300000) {
        return $cache.Manifests
    }

    $cache.ManifestKey = $key
    $cache.ManifestTime = [Environment]::TickCount64
    $cache.Manifests = $null
    $exe = Resolve-DscCompletionExecutable
    if (-not $exe) {
        return $null
    }

    $errorCountBefore = $Error.Count
    $result = @{
        Resources  = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Adapters   = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Extensions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    try {
        $directories = [System.Collections.Generic.List[string]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $searchPath = if ($env:DSC_RESOURCE_PATH) { $env:DSC_RESOURCE_PATH } else { $env:PATH }
        foreach ($directory in @($searchPath -split [System.IO.Path]::PathSeparator) + [System.IO.Path]::GetDirectoryName($exe)) {
            if ($directory -and $seen.Add($directory.TrimEnd('\', '/'))) {
                $directories.Add($directory)
            }
        }

        if ($IsWindows) {
            $packages = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages')
            if ($null -ne $packages) {
                try {
                    foreach ($name in $packages.GetSubKeyNames()) {
                        $package = $packages.OpenSubKey($name)
                        if ($null -eq $package) {
                            continue
                        }

                        $root = $package.GetValue('PackageRootFolder')
                        $package.Dispose()
                        if ($root -and $seen.Add(([string]$root).TrimEnd('\'))) {
                            $directories.Add([string]$root)
                        }
                    }
                } finally {
                    $packages.Dispose()
                }
            }
        }

        $files = [System.Collections.Generic.List[string]]::new()
        $options = [System.IO.EnumerationOptions]@{ IgnoreInaccessible = $true; RecurseSubdirectories = $false }
        foreach ($directory in $directories) {
            if (-not [System.IO.Directory]::Exists($directory)) {
                continue
            }

            try {
                foreach ($file in [System.IO.Directory]::EnumerateFiles($directory, '*.dsc.*', $options)) {
                    if ($file -match '\.dsc\.(resource|adaptedresource|extension|manifests)\.(json|ya?ml)$') {
                        $files.Add($file)
                    }
                }
            } catch {
                Write-Debug -Message $_.Exception.Message
            }
        }

        $discoverCache = if ($IsWindows) {
            [System.IO.Path]::Combine([string]$env:LOCALAPPDATA, 'dsc', 'PowerShellDiscoverCache.json')
        } else {
            [System.IO.Path]::Combine($HOME, '.dsc', 'PowerShellDiscoverCache.json')
        }
        if ([System.IO.File]::Exists($discoverCache)) {
            try {
                $discoverText = [System.IO.File]::ReadAllText($discoverCache)
                foreach ($manifest in @(($discoverText | ConvertFrom-Json -AsHashtable)['Manifests'])) {
                    if ($manifest -is [System.Collections.IDictionary] -and $manifest['manifestPath']) {
                        $files.Add([string]$manifest['manifestPath'])
                    }
                }
            } catch {
                Write-Debug -Message $_.Exception.Message
            }
        }

        $addEntry = {
            param($Entry, [string]$Section)
            if ($Entry -isnot [System.Collections.IDictionary] -or -not ($Entry['type'] -is [string]) -or -not $Entry['type']) {
                return
            }

            $type = $Entry['type']
            $description = if ($Entry['description'] -is [string] -and $Entry['description']) { $Entry['description'] } else { $type }
            if ($Section -eq 'extension') {
                $result.Extensions[$type] = $description
                return
            }

            $result.Resources[$type] = $description
            if ($Entry['kind'] -eq 'adapter' -or $Entry['adapter'] -is [System.Collections.IDictionary]) {
                $result.Adapters[$type] = $description
            }
        }

        foreach ($file in $files) {
            try {
                $text = [System.IO.File]::ReadAllText($file)
            } catch {
                Write-Debug -Message $_.Exception.Message
                continue
            }
            if (-not $text) {
                continue
            }

            $section = if ($file -match '\.dsc\.extension\.') { 'extension' } elseif ($file -match '\.dsc\.manifests\.') { 'manifests' } else { 'resource' }
            if ($file -notmatch '\.json$') {
                # YAML manifests: the top-level keys sit at column 0.
                if ($section -ne 'manifests' -and $text -match '(?m)^type:\s*[''"]?(?<type>[^''"\s#]+)') {
                    $entry = @{ type = $Matches.type }
                    if ($text -match '(?m)^kind:\s*[''"]?(?<kind>\w+)') { $entry.kind = $Matches.kind }
                    if ($text -match '(?m)^description:\s*[''"]?(?<description>[^''"\r\n]+)') { $entry.description = $Matches.description.Trim() }
                    & $addEntry $entry $section
                }
                continue
            }

            try {
                $document = $text | ConvertFrom-Json -AsHashtable
            } catch {
                Write-Debug -Message $_.Exception.Message
                continue
            }

            if ($section -eq 'manifests') {
                if ($document -is [System.Collections.IDictionary]) {
                    foreach ($entry in @($document['resources'])) { & $addEntry $entry 'resource' }
                    foreach ($entry in @($document['extensions'])) { & $addEntry $entry 'extension' }
                }
            } else {
                & $addEntry $document $section
            }
        }
    } finally {
        # Unreadable or half-written manifests are expected misses, not faults to leave in $Error.
        while ($Error.Count -gt $errorCountBefore) {
            $Error.RemoveAt(0)
        }
    }

    $cache.Manifests = $result
    $result
}

function Get-DscCompletionFunction {
    # Function names are built into dsc.exe, so ask it once per PATH (which picks the binary):
    # 'dsc function list' reads nothing and changes nothing. Bounded to 5 s; a missing tool or a
    # failed run is remembered until PATH changes.
    $cache = $script:DscCompletionCache
    if ($cache.FunctionKey -eq $env:PATH) {
        return $cache.Functions
    }

    $cache.FunctionKey = $env:PATH
    $cache.Functions = $null
    $exe = Resolve-DscCompletionExecutable
    if (-not $exe) {
        return $null
    }

    $errorCountBefore = $Error.Count
    $functions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $exe
        foreach ($argument in @('function', 'list', '--output-format', 'json')) {
            $startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $process.StandardInput.Close()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            [void]$process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) {
                try { $process.Kill($true) } catch { Write-Debug -Message $_.Exception.Message }
                return $null
            }

            $text = $outputTask.Result -replace '\x1b\[[0-9;?]*[ -/]*[@-~]', ''
            foreach ($line in $text -split '\r?\n') {
                if (-not $line.StartsWith('{')) {
                    continue
                }

                try {
                    $record = $line | ConvertFrom-Json -AsHashtable
                } catch {
                    Write-Debug -Message $_.Exception.Message
                    continue
                }

                if ($record['name'] -is [string] -and $record['name']) {
                    $functions[$record['name']] = if ($record['description'] -is [string] -and $record['description']) { $record['description'] } else { $record['name'] }
                }
            }
        } finally {
            $process.Dispose()
        }
    } catch {
        Write-Debug -Message $_.Exception.Message
    } finally {
        while ($Error.Count -gt $errorCountBefore) {
            $Error.RemoveAt(0)
        }
    }

    $cache.Functions = $functions
    $functions
}

function Get-DscPendingValueOption {
    # The option whose value is the next word: an exact value-taking option, or a bundle of short
    # flags whose last letter takes a value (clap reads '-wr' as -w -r, and '-ldebug' as -l debug).
    param([string]$Node, [string]$Token, $ValueOptions)

    if ($ValueOptions.Contains("$Node $Token")) {
        return $Token
    }

    if ($Token -cmatch '^-[A-Za-z]{2,}$') {
        for ($i = 1; $i -lt $Token.Length; $i++) {
            $short = '-' + $Token[$i]
            if ($ValueOptions.Contains("$Node $short")) {
                if ($i -eq $Token.Length - 1) {
                    return $short
                }

                break
            }
        }
    }

    $null
}

function ConvertTo-DscQuotedValue {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed, otherwise
    # in the quote the user typed (single by default). PowerShell reads ' and U+2018-U+201B as
    # single quotes and " and U+201C-U+201E as double quotes.
    param([string]$Value, [string]$QuoteChar = '')

    if (-not $QuoteChar) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$@#\u2018-\u201E]') {
            return $Value
        }

        $QuoteChar = "'"
    }

    if ($QuoteChar -match '^[''\u2018-\u201B]$') {
        return $QuoteChar + ($Value -replace '([''\u2018-\u201B])', '$1$1') + $QuoteChar
    }

    $QuoteChar + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + $QuoteChar
}

function Get-DscPathCompletion {
    # CompleteFilename quotes for PowerShell and wildcard-escapes for -Path parameters
    # (tick``x.txt). dsc takes literal paths, so each result is unwrapped by the parser and
    # unescaped, then quoted once in the style the user typed.
    param([string]$ValueWord, [string]$ValuePrefix)

    $quoteChar = if ($ValueWord -match '^[''"\u2018-\u201E]') { $ValueWord.Substring(0, 1) } else { '' }
    if ($quoteChar) {
        # The tokenizer reads the typed quote as PowerShell would ('it''s is it's).
        $tokens = $null
        $null = [Parser]::ParseInput($ValueWord, [ref]$tokens, [ref]$null)
        $ValueWord = $tokens[0].Value
    }

    # CompleteFilename writes '\' separators; keep a typed directory such as './' exactly as typed.
    $typedDirectory = if ($ValueWord -match '^(?<dir>.*[\\/])') { $Matches.dir } else { '' }
    foreach ($result in [CompletionCompleters]::CompleteFilename($ValueWord)) {
        $path = $result.CompletionText
        if ($path -match '^[''"\u2018-\u201E]') {
            $ast = [Parser]::ParseInput($path, [ref]$null, [ref]$null)
            $constant = $ast.Find({ param($node) $node -is [StringConstantExpressionAst] }, $true)
            if ($constant) {
                $path = $constant.Value
            }
        }

        $path = [WildcardPattern]::Unescape($path)
        if ($typedDirectory -and $path.Length -ge $typedDirectory.Length -and
            ($path.Substring(0, $typedDirectory.Length) -replace '/', '\') -eq ($typedDirectory -replace '/', '\')) {
            $path = $typedDirectory + $path.Substring($typedDirectory.Length)
        }

        [CompletionResult]::new($ValuePrefix + (ConvertTo-DscQuotedValue -Value $path -QuoteChar $quoteChar), $result.ListItemText, $result.ResultType, $result.ToolTip)
    }
}

Register-ArgumentCompleter -Native -CommandName 'dsc' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $outputFormats = @('json', 'pretty-json', 'yaml')
    $outputFormatsWithTable = @('json', 'pretty-json', 'yaml', 'table-no-truncate')
    $valueTable = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in @(
            @{ Node = 'dsc'; Options = @('-l', '--trace-level'); Values = @('error', 'warn', 'info', 'debug', 'trace') }
            @{ Node = 'dsc'; Options = @('-t', '--trace-format'); Values = @('default', 'plaintext', 'json') }
            @{ Node = 'dsc'; Options = @('-p', '--progress-format'); Values = @('default', 'none', 'json') }
            @{ Node = 'dsc;config;get'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;config;set'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;config;test'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;config;validate'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;config;export'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;config;resolve'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;extension;list'; Options = @('-o', '--output-format'); Values = $outputFormatsWithTable }
            @{ Node = 'dsc;function;list'; Options = @('-o', '--output-format'); Values = $outputFormatsWithTable }
            @{ Node = 'dsc;resource;list'; Options = @('-o', '--output-format'); Values = $outputFormatsWithTable }
            @{ Node = 'dsc;resource;get'; Options = @('-o', '--output-format'); Values = @('json', 'json-array', 'pass-through', 'pretty-json', 'yaml') }
            @{ Node = 'dsc;resource;set'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;resource;test'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;resource;delete'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;resource;schema'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;resource;export'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;schema'; Options = @('-o', '--output-format'); Values = $outputFormats }
            @{ Node = 'dsc;schema'; Options = @('-t', '--type'); Values = @('configuration', 'configuration-get-result', 'configuration-set-result', 'configuration-test-result', 'dsc-resource', 'extension-discover-result', 'extension-manifest', 'function-definition', 'get-result', 'include', 'manifest-list', 'resolve-result', 'resource', 'resource-manifest', 'restart-required', 'set-result', 'test-result') }
        )) {
        foreach ($optionName in $entry.Options) {
            $valueTable["$($entry.Node) $optionName"] = $entry.Values
        }
    }

    # Value slots without an enum: paths (left to PowerShell's filesystem completion), free text, and
    # names read from the installed dsc ('resource', 'adapter').
    $slotTable = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in @(
            @{ Nodes = @('dsc;config'); Options = @('-f', '--parameters-file', '-r', '--system-root'); Kind = 'path' }
            @{ Nodes = @('dsc;config'); Options = @('-p', '--parameters'); Kind = 'text' }
            @{ Nodes = @('get', 'set', 'test', 'validate', 'export', 'resolve').ForEach{ "dsc;config;$_" }; Options = @('-f', '--file'); Kind = 'path' }
            @{ Nodes = @('get', 'set', 'test', 'validate', 'export', 'resolve').ForEach{ "dsc;config;$_" }; Options = @('-i', '--input'); Kind = 'text' }
            @{ Nodes = @('get', 'set', 'test', 'delete', 'export').ForEach{ "dsc;resource;$_" }; Options = @('-f', '--file'); Kind = 'path' }
            @{ Nodes = @('get', 'set', 'test', 'delete', 'export').ForEach{ "dsc;resource;$_" }; Options = @('-i', '--input'); Kind = 'text' }
            @{ Nodes = @('get', 'set', 'test', 'delete', 'schema', 'export').ForEach{ "dsc;resource;$_" }; Options = @('-r', '--resource'); Kind = 'resource' }
            @{ Nodes = @('get', 'set', 'test', 'delete', 'schema', 'export').ForEach{ "dsc;resource;$_" }; Options = @('-v', '--version'); Kind = 'text' }
            @{ Nodes = @('dsc;resource;list'); Options = @('-a', '--adapter'); Kind = 'adapter' }
            @{ Nodes = @('dsc;resource;list'); Options = @('-d', '--description', '-t', '--tags'); Kind = 'text' }
        )) {
        foreach ($node in $entry.Nodes) {
            foreach ($optionName in $entry.Options) {
                $slotTable["$node $optionName"] = $entry.Kind
            }
        }
    }

    $valueOptions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($key in @($valueTable.Keys) + @($slotTable.Keys)) {
        [void]$valueOptions.Add($key)
    }

    # Walk the bare words left of the cursor. Options (and the value of a value-taking option) are
    # skipped rather than ending the walk, so 'dsc -l debug config get' still reaches 'config;get'.
    $commandElements = $commandAst.CommandElements
    $path = [System.Collections.Generic.List[string]]::new()
    $path.Add('dsc')
    $skipValue = $false
    for ($i = 1; $i -lt $commandElements.Count; $i++) {
        $element = $commandElements[$i]
        if ($element.Extent.StartOffset -ge $cursorPosition) {
            break
        }

        if ($skipValue) {
            $skipValue = $false
            continue
        }

        # PowerShell parses '-l' as a CommandParameterAst and '--trace-level' as a bare word.
        if ($element -is [CommandParameterAst]) {
            $text = $element.Extent.Text
        } elseif ($element -is [StringConstantExpressionAst] -and $element.StringConstantType -eq [StringConstantType]::BareWord) {
            $text = $element.Value
        } else {
            break
        }

        # The word under the cursor is being completed, not part of the path.
        if ($element.Extent.EndOffset -ge $cursorPosition) {
            break
        }

        if ($text.StartsWith('-')) {
            $skipValue = $null -ne (Get-DscPendingValueOption -Node ($path -join ';') -Token $text -ValueOptions $valueOptions)
            continue
        }

        $path.Add($text)
    }
    $command = $path -join ';'

    # Value slots: the option token left of the cursor, or the '--option=' prefix of the current word.
    $previousToken = ''
    for ($i = $commandElements.Count - 1; $i -ge 1; $i--) {
        if ($commandElements[$i].Extent.EndOffset -lt $cursorPosition) {
            $previousToken = $commandElements[$i].Extent.Text
            break
        }
    }

    $valueOption = $null
    $valuePrefix = ''
    $valueWord = $wordToComplete
    if ($wordToComplete -match '^(?<option>--?[A-Za-z][A-Za-z0-9-]*)=(?<value>.*)$') {
        $valueOption = $Matches.option
        $valuePrefix = $valueOption + '='
        $valueWord = $Matches.value
    } elseif ($previousToken.StartsWith('-')) {
        $valueOption = Get-DscPendingValueOption -Node $command -Token $previousToken -ValueOptions $valueOptions
    }

    if ($valueOption) {
        $valueKey = "$command $valueOption"
        if ($valueTable.ContainsKey($valueKey)) {
            return @(foreach ($value in $valueTable[$valueKey]) {
                if ($value.StartsWith($valueWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [CompletionResult]::new($valuePrefix + $value, $value, [CompletionResultType]::ParameterValue, $value)
                }
            })
        }

        if ($slotTable.ContainsKey($valueKey)) {
            # Read the value from the parser's element under the cursor: $wordToComplete closes an
            # unterminated quote ('Micro becomes 'Micro') or drops it after '--opt='.
            foreach ($element in $commandElements) {
                if ($element.Extent.StartOffset -lt $cursorPosition -and $element.Extent.EndOffset -ge $cursorPosition) {
                    $valueWord = $element.Extent.Text.Substring(0, $cursorPosition - $element.Extent.StartOffset)
                    if ($valuePrefix -and $valueWord.StartsWith($valuePrefix, [System.StringComparison]::Ordinal)) {
                        $valueWord = $valueWord.Substring($valuePrefix.Length)
                    }
                    break
                }
            }

            switch ($slotTable[$valueKey]) {
                'path' {
                    # A separate word returns nothing so PowerShell completes the path itself; the
                    # attached '--file=' form completes it here and keeps the prefix.
                    if ($valuePrefix) {
                        return @(Get-DscPathCompletion -ValueWord $valueWord -ValuePrefix $valuePrefix)
                    }
                    return
                }
                'text' {
                    return
                }
                default {
                    $manifests = Get-DscCompletionManifest
                    if ($null -eq $manifests) {
                        return
                    }

                    $names = if ($_ -eq 'adapter') { $manifests.Adapters } else { $manifests.Resources }
                    $quote = ''
                    if ($valueWord -match '^[''"]') {
                        $quote = $valueWord.Substring(0, 1)
                        $valueWord = $valueWord.Substring(1)
                    }
                    return @(foreach ($name in $names.Keys | Sort-Object) {
                        if ($name.StartsWith($valueWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                            [CompletionResult]::new($valuePrefix + $quote + $name + $quote, $name, [CompletionResultType]::ParameterValue, $names[$name])
                        }
                    })
                }
            }
        }
    }

    $completions = @(switch ($command) {
        'dsc' {
            [CompletionResult]::new('-l', '-l', [CompletionResultType]::ParameterName, 'Trace level to use')
            [CompletionResult]::new('--trace-level', '--trace-level', [CompletionResultType]::ParameterName, 'Trace level to use')
            [CompletionResult]::new('-t', '-t', [CompletionResultType]::ParameterName, 'Trace format to use')
            [CompletionResult]::new('--trace-format', '--trace-format', [CompletionResultType]::ParameterName, 'Trace format to use')
            [CompletionResult]::new('-p', '-p', [CompletionResultType]::ParameterName, 'Progress format to use')
            [CompletionResult]::new('--progress-format', '--progress-format', [CompletionResultType]::ParameterName, 'Progress format to use')
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'Ignore the settings file when running the command')
            [CompletionResult]::new('--ignore-settings-file', '--ignore-settings-file', [CompletionResultType]::ParameterName, 'Ignore the settings file when running the command')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
            [CompletionResult]::new('-V', '-V ', [CompletionResultType]::ParameterName, 'Print version')
            [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, 'Print version')
            [CompletionResult]::new('completer', 'completer', [CompletionResultType]::ParameterValue, 'Generate a shell completion script')
            [CompletionResult]::new('config', 'config', [CompletionResultType]::ParameterValue, 'Apply a configuration document')
            [CompletionResult]::new('extension', 'extension', [CompletionResultType]::ParameterValue, 'Operations on DSC extensions')
            [CompletionResult]::new('function', 'function', [CompletionResultType]::ParameterValue, 'Operations on DSC functions')
            [CompletionResult]::new('mcp', 'mcp', [CompletionResultType]::ParameterValue, 'Use DSC as a MCP server')
            [CompletionResult]::new('resource', 'resource', [CompletionResultType]::ParameterValue, 'Invoke a specific DSC resource')
            [CompletionResult]::new('schema', 'schema', [CompletionResultType]::ParameterValue, 'Get the JSON schema for a DSC type')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;completer' {
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('bash', 'bash', [CompletionResultType]::ParameterValue, 'Generate a bash completion script')
            [CompletionResult]::new('elvish', 'elvish', [CompletionResultType]::ParameterValue, 'Generate an elvish completion script')
            [CompletionResult]::new('fish', 'fish', [CompletionResultType]::ParameterValue, 'Generate a fish completion script')
            [CompletionResult]::new('powershell', 'powershell', [CompletionResultType]::ParameterValue, 'Generate a PowerShell completion script')
            [CompletionResult]::new('zsh', 'zsh', [CompletionResultType]::ParameterValue, 'Generate a zsh completion script')
            break
        }
        'dsc;config' {
            [CompletionResult]::new('-p', '-p', [CompletionResultType]::ParameterName, 'Parameters to pass to the configuration as JSON or YAML')
            [CompletionResult]::new('--parameters', '--parameters', [CompletionResultType]::ParameterName, 'Parameters to pass to the configuration as JSON or YAML')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'Parameters to pass to the configuration as a JSON or YAML file')
            [CompletionResult]::new('--parameters-file', '--parameters-file', [CompletionResultType]::ParameterName, 'Parameters to pass to the configuration as a JSON or YAML file')
            [CompletionResult]::new('-r', '-r', [CompletionResultType]::ParameterName, 'Specify the operating system root path if not targeting the current running OS')
            [CompletionResult]::new('--system-root', '--system-root', [CompletionResultType]::ParameterName, 'Specify the operating system root path if not targeting the current running OS')
            [CompletionResult]::new('--as-group', '--as-group', [CompletionResultType]::ParameterName, 'as-group')
            [CompletionResult]::new('--as-assert', '--as-assert', [CompletionResultType]::ParameterName, 'as-assert')
            [CompletionResult]::new('--as-include', '--as-include', [CompletionResultType]::ParameterName, 'as-include')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('get', 'get', [CompletionResultType]::ParameterValue, 'Retrieve the current configuration')
            [CompletionResult]::new('set', 'set', [CompletionResultType]::ParameterValue, 'Set the current configuration')
            [CompletionResult]::new('test', 'test', [CompletionResultType]::ParameterValue, 'Test the current configuration')
            [CompletionResult]::new('validate', 'validate', [CompletionResultType]::ParameterValue, 'Validate the current configuration')
            [CompletionResult]::new('export', 'export', [CompletionResultType]::ParameterValue, 'Export the current configuration')
            [CompletionResult]::new('resolve', 'resolve', [CompletionResultType]::ParameterValue, 'Resolve the current configuration')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;config;get' {
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;config;set' {
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-w', '-w', [CompletionResultType]::ParameterName, 'Run as a what-if operation instead of executing the configuration or resource')
            [CompletionResult]::new('--what-if', '--what-if', [CompletionResultType]::ParameterName, 'Run as a what-if operation instead of executing the configuration or resource')
            [CompletionResult]::new('--dry-run', '--dry-run', [CompletionResultType]::ParameterName, 'Alias of --what-if')
            [CompletionResult]::new('--noop', '--noop', [CompletionResultType]::ParameterName, 'Alias of --what-if')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;config;test' {
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--as-get', '--as-get', [CompletionResultType]::ParameterName, 'as-get')
            [CompletionResult]::new('--as-config', '--as-config', [CompletionResultType]::ParameterName, 'as-config')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;config;validate' {
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;config;export' {
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;config;resolve' {
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;config;help' {
            [CompletionResult]::new('get', 'get', [CompletionResultType]::ParameterValue, 'Retrieve the current configuration')
            [CompletionResult]::new('set', 'set', [CompletionResultType]::ParameterValue, 'Set the current configuration')
            [CompletionResult]::new('test', 'test', [CompletionResultType]::ParameterValue, 'Test the current configuration')
            [CompletionResult]::new('validate', 'validate', [CompletionResultType]::ParameterValue, 'Validate the current configuration')
            [CompletionResult]::new('export', 'export', [CompletionResultType]::ParameterValue, 'Export the current configuration')
            [CompletionResult]::new('resolve', 'resolve', [CompletionResultType]::ParameterValue, 'Resolve the current configuration')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;config;help;get' {
            break
        }
        'dsc;config;help;set' {
            break
        }
        'dsc;config;help;test' {
            break
        }
        'dsc;config;help;validate' {
            break
        }
        'dsc;config;help;export' {
            break
        }
        'dsc;config;help;resolve' {
            break
        }
        'dsc;config;help;help' {
            break
        }
        'dsc;extension' {
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, 'List or find extensions')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;extension;list' {
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;extension;help' {
            [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, 'List or find extensions')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;extension;help;list' {
            break
        }
        'dsc;extension;help;help' {
            break
        }
        'dsc;function' {
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, 'List or find functions')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;function;list' {
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;function;help' {
            [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, 'List or find functions')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;mcp' {
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;resource' {
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, 'List or find resources')
            [CompletionResult]::new('get', 'get', [CompletionResultType]::ParameterValue, 'Invoke the get operation to a resource')
            [CompletionResult]::new('set', 'set', [CompletionResultType]::ParameterValue, 'Invoke the set operation to a resource')
            [CompletionResult]::new('test', 'test', [CompletionResultType]::ParameterValue, 'Invoke the test operation to a resource')
            [CompletionResult]::new('delete', 'delete', [CompletionResultType]::ParameterValue, 'Invoke the delete operation to a resource')
            [CompletionResult]::new('schema', 'schema', [CompletionResultType]::ParameterValue, 'Get the JSON schema for a resource')
            [CompletionResult]::new('export', 'export', [CompletionResultType]::ParameterValue, 'Retrieve all resource instances')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;resource;list' {
            [CompletionResult]::new('-a', '-a', [CompletionResultType]::ParameterName, 'Adapter filter to limit the resource search')
            [CompletionResult]::new('--adapter', '--adapter', [CompletionResultType]::ParameterName, 'Adapter filter to limit the resource search')
            [CompletionResult]::new('-d', '-d', [CompletionResultType]::ParameterName, 'Description keyword to search for in the resource description')
            [CompletionResult]::new('--description', '--description', [CompletionResultType]::ParameterName, 'Description keyword to search for in the resource description')
            [CompletionResult]::new('-t', '-t', [CompletionResultType]::ParameterName, 'Tag to search for in the resource tags')
            [CompletionResult]::new('--tags', '--tags', [CompletionResultType]::ParameterName, 'Tag to search for in the resource tags')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;resource;get' {
            [CompletionResult]::new('-r', '-r', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('--resource', '--resource', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('-v', '-v', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-a', '-a', [CompletionResultType]::ParameterName, 'Get all instances of the resource')
            [CompletionResult]::new('--all', '--all', [CompletionResultType]::ParameterName, 'Get all instances of the resource')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;resource;set' {
            [CompletionResult]::new('-r', '-r', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('--resource', '--resource', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('-v', '-v', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-w', '-w', [CompletionResultType]::ParameterName, 'Run as a what-if operation instead of executing the configuration or resource')
            [CompletionResult]::new('--what-if', '--what-if', [CompletionResultType]::ParameterName, 'Run as a what-if operation instead of executing the configuration or resource')
            [CompletionResult]::new('--dry-run', '--dry-run', [CompletionResultType]::ParameterName, 'Alias of --what-if')
            [CompletionResult]::new('--noop', '--noop', [CompletionResultType]::ParameterName, 'Alias of --what-if')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;resource;test' {
            [CompletionResult]::new('-r', '-r', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('--resource', '--resource', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('-v', '-v', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;resource;delete' {
            [CompletionResult]::new('-r', '-r', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('--resource', '--resource', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('-v', '-v', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-w', '-w', [CompletionResultType]::ParameterName, 'Run as a what-if operation instead of executing the configuration or resource')
            [CompletionResult]::new('--what-if', '--what-if', [CompletionResultType]::ParameterName, 'Run as a what-if operation instead of executing the configuration or resource')
            [CompletionResult]::new('--dry-run', '--dry-run', [CompletionResultType]::ParameterName, 'Alias of --what-if')
            [CompletionResult]::new('--noop', '--noop', [CompletionResultType]::ParameterName, 'Alias of --what-if')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;resource;schema' {
            [CompletionResult]::new('-r', '-r', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('--resource', '--resource', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('-v', '-v', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;resource;export' {
            [CompletionResult]::new('-r', '-r', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('--resource', '--resource', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('-v', '-v', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, 'The version of the resource to invoke in semver format')
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;resource;help' {
            [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, 'List or find resources')
            [CompletionResult]::new('get', 'get', [CompletionResultType]::ParameterValue, 'Invoke the get operation to a resource')
            [CompletionResult]::new('set', 'set', [CompletionResultType]::ParameterValue, 'Invoke the set operation to a resource')
            [CompletionResult]::new('test', 'test', [CompletionResultType]::ParameterValue, 'Invoke the test operation to a resource')
            [CompletionResult]::new('delete', 'delete', [CompletionResultType]::ParameterValue, 'Invoke the delete operation to a resource')
            [CompletionResult]::new('schema', 'schema', [CompletionResultType]::ParameterValue, 'Get the JSON schema for a resource')
            [CompletionResult]::new('export', 'export', [CompletionResultType]::ParameterValue, 'Retrieve all resource instances')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;resource;help;list' {
            break
        }
        'dsc;resource;help;get' {
            break
        }
        'dsc;resource;help;set' {
            break
        }
        'dsc;resource;help;test' {
            break
        }
        'dsc;resource;help;delete' {
            break
        }
        'dsc;resource;help;schema' {
            break
        }
        'dsc;resource;help;export' {
            break
        }
        'dsc;resource;help;help' {
            break
        }
        'dsc;schema' {
            [CompletionResult]::new('-t', '-t', [CompletionResultType]::ParameterName, 'The type of DSC schema to get')
            [CompletionResult]::new('--type', '--type', [CompletionResultType]::ParameterName, 'The type of DSC schema to get')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;help' {
            [CompletionResult]::new('completer', 'completer', [CompletionResultType]::ParameterValue, 'Generate a shell completion script')
            [CompletionResult]::new('config', 'config', [CompletionResultType]::ParameterValue, 'Apply a configuration document')
            [CompletionResult]::new('extension', 'extension', [CompletionResultType]::ParameterValue, 'Operations on DSC extensions')
            [CompletionResult]::new('function', 'function', [CompletionResultType]::ParameterValue, 'Operations on DSC functions')
            [CompletionResult]::new('mcp', 'mcp', [CompletionResultType]::ParameterValue, 'Use DSC as a MCP server')
            [CompletionResult]::new('resource', 'resource', [CompletionResultType]::ParameterValue, 'Invoke a specific DSC resource')
            [CompletionResult]::new('schema', 'schema', [CompletionResultType]::ParameterValue, 'Get the JSON schema for a DSC type')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;help;completer' {
            break
        }
        'dsc;help;function' {
            [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, 'List or find functions')
            break
        }
        'dsc;help;config' {
            [CompletionResult]::new('get', 'get', [CompletionResultType]::ParameterValue, 'Retrieve the current configuration')
            [CompletionResult]::new('set', 'set', [CompletionResultType]::ParameterValue, 'Set the current configuration')
            [CompletionResult]::new('test', 'test', [CompletionResultType]::ParameterValue, 'Test the current configuration')
            [CompletionResult]::new('validate', 'validate', [CompletionResultType]::ParameterValue, 'Validate the current configuration')
            [CompletionResult]::new('export', 'export', [CompletionResultType]::ParameterValue, 'Export the current configuration')
            [CompletionResult]::new('resolve', 'resolve', [CompletionResultType]::ParameterValue, 'Resolve the current configuration')
            break
        }
        'dsc;help;config;get' {
            break
        }
        'dsc;help;config;set' {
            break
        }
        'dsc;help;config;test' {
            break
        }
        'dsc;help;config;validate' {
            break
        }
        'dsc;help;config;export' {
            break
        }
        'dsc;help;config;resolve' {
            break
        }
        'dsc;help;extension' {
            [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, 'List or find extensions')
            break
        }
        'dsc;help;extension;list' {
            break
        }
        'dsc;help;resource' {
            [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, 'List or find resources')
            [CompletionResult]::new('get', 'get', [CompletionResultType]::ParameterValue, 'Invoke the get operation to a resource')
            [CompletionResult]::new('set', 'set', [CompletionResultType]::ParameterValue, 'Invoke the set operation to a resource')
            [CompletionResult]::new('test', 'test', [CompletionResultType]::ParameterValue, 'Invoke the test operation to a resource')
            [CompletionResult]::new('delete', 'delete', [CompletionResultType]::ParameterValue, 'Invoke the delete operation to a resource')
            [CompletionResult]::new('schema', 'schema', [CompletionResultType]::ParameterValue, 'Get the JSON schema for a resource')
            [CompletionResult]::new('export', 'export', [CompletionResultType]::ParameterValue, 'Retrieve all resource instances')
            break
        }
        'dsc;help;resource;list' {
            break
        }
        'dsc;help;resource;get' {
            break
        }
        'dsc;help;resource;set' {
            break
        }
        'dsc;help;resource;test' {
            break
        }
        'dsc;help;resource;delete' {
            break
        }
        'dsc;help;resource;schema' {
            break
        }
        'dsc;help;resource;export' {
            break
        }
        'dsc;help;schema' {
            break
        }
        'dsc;help;help' {
            break
        }
    })

    # The optional [RESOURCE_NAME] / [EXTENSION_NAME] / [FUNCTION_NAME] positional of the list commands.
    if (-not $wordToComplete.StartsWith('-') -and $command -in @('dsc;resource;list', 'dsc;extension;list', 'dsc;function;list')) {
        $names = if ($command -eq 'dsc;function;list') {
            Get-DscCompletionFunction
        } else {
            $manifests = Get-DscCompletionManifest
            if ($null -ne $manifests) {
                if ($command -eq 'dsc;resource;list') { $manifests.Resources } else { $manifests.Extensions }
            }
        }
        if ($null -ne $names) {
            $completions += @(foreach ($name in $names.Keys) {
                [CompletionResult]::new($name, $name, [CompletionResultType]::ParameterValue, $names[$name])
            })
        }
    }

    $completions.Where{ $_.CompletionText -like ([System.Management.Automation.WildcardPattern]::Escape($wordToComplete) + '*') } |
        Sort-Object -Property ListItemText
}
