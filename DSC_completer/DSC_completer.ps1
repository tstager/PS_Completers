using namespace System.Management.Automation
using namespace System.Management.Automation.Language

Register-ArgumentCompleter -Native -CommandName 'dsc' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $commandElements = $commandAst.CommandElements
    $command = @(
        'dsc'
        for ($i = 1; $i -lt $commandElements.Count; $i++) {
            $element = $commandElements[$i]
            if ($element.Extent.StartOffset -ge $cursorPosition -or
                $element -isnot [StringConstantExpressionAst] -or
                $element.StringConstantType -ne [StringConstantType]::BareWord -or
                $element.Value.StartsWith('-') -or
                $element.Value -eq $wordToComplete) {
                break
        }
        $element.Value
    }) -join ';'

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
        $valueOption = $previousToken
    }

    if ($valueOption) {
        $outputFormats = @('json', 'pretty-json', 'yaml')
        $outputFormatsWithTable = @('json', 'pretty-json', 'yaml', 'table-no-truncate')
        $valueTable = @{}
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

        $valueKey = "$command $valueOption"
        if ($valueTable.ContainsKey($valueKey)) {
            return @(foreach ($value in $valueTable[$valueKey]) {
                if ($value.StartsWith($valueWord, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [CompletionResult]::new($valuePrefix + $value, $value, [CompletionResultType]::ParameterValue, $value)
                }
            })
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
        'dsc;resource;test' {
            [CompletionResult]::new('-r', '-r', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('--resource', '--resource', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
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
            [CompletionResult]::new('-i', '-i', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('--input', '--input', [CompletionResultType]::ParameterName, 'The input document as JSON or YAML to pass to the configuration or resource')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'The path to a file used as input to the configuration or resource. Use ''-'' for the file to read from STDIN.')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;resource;schema' {
            [CompletionResult]::new('-r', '-r', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('--resource', '--resource', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('--output-format', '--output-format', [CompletionResultType]::ParameterName, 'The output format to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'dsc;resource;export' {
            [CompletionResult]::new('-r', '-r', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
            [CompletionResult]::new('--resource', '--resource', [CompletionResultType]::ParameterName, 'The name of the resource to invoke')
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

    $completions.Where{ $_.CompletionText -like ([System.Management.Automation.WildcardPattern]::Escape($wordToComplete) + '*') } |
        Sort-Object -Property ListItemText
}