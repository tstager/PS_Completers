using namespace System.Management.Automation
using namespace System.Management.Automation.Language

Register-ArgumentCompleter -Native -CommandName 'dsc' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $commandElements = $commandAst.CommandElements
    $command = @(
        'dsc'
        for ($i = 1; $i -lt $commandElements.Count; $i++) {
            $element = $commandElements[$i]
            if ($element -isnot [StringConstantExpressionAst] -or
                $element.StringConstantType -ne [StringConstantType]::BareWord -or
                $element.Value.StartsWith('-') -or
                $element.Value -eq $wordToComplete) {
                break
        }
        $element.Value
    }) -join ';'

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
            [CompletionResult]::new('resource', 'resource', [CompletionResultType]::ParameterValue, 'Invoke a specific DSC resource')
            [CompletionResult]::new('schema', 'schema', [CompletionResultType]::ParameterValue, 'Get the JSON schema for a DSC type')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;completer' {
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
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
            [CompletionResult]::new('resource', 'resource', [CompletionResultType]::ParameterValue, 'Invoke a specific DSC resource')
            [CompletionResult]::new('schema', 'schema', [CompletionResultType]::ParameterValue, 'Get the JSON schema for a DSC type')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'dsc;help;completer' {
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

    $completions.Where{ $_.CompletionText -like "$wordToComplete*" } |
        Sort-Object -Property ListItemText
}