# Completion for comfy-cli, driven by the CLI's machine-readable `--help-json` command tree.
Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name ComfyCliCompletionCache -Scope Script -ErrorAction Ignore)) {
    $script:ComfyCliCompletionCache = @{ Tree = $null; Missing = $false; RetryAt = 0 }
}

function Invoke-ComfyCliHelpJson {
    param([string]$Path)

    $process = [System.Diagnostics.Process]::new()
    try {
        $info = [System.Diagnostics.ProcessStartInfo]::new($Path)
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $info.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $info.Environment['PYTHONIOENCODING'] = 'utf-8'
        $info.Environment['NO_COLOR'] = '1'
        [void]$info.Environment.Remove('FORCE_COLOR')
        [void]$info.ArgumentList.Add('--help-json')
        $process.StartInfo = $info
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        [void]$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(8000)) {
            $process.Kill($true)
            return ''
        }
        return $stdout.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', ''
    } catch {
        return ''
    } finally {
        $process.Dispose()
    }
}

function Get-ComfyCliHelpString {
    param([object]$Text)

    # Help strings carry Rich markup escapes such as '\[all|comfy|cli]'.
    ([string]$Text -replace '\\\[', '[' -replace '\s+', ' ').Trim()
}

function ConvertTo-ComfyCliParamEntry {
    param([System.Collections.IDictionary]$Param)

    # Python-side names carry suffixes such as data_dir_opt and type_; drop them for matching and display.
    $name = [string]$Param['name'] -replace '_opt$|_+$', ''
    $type = [string]$Param['type']
    $help = Get-ComfyCliHelpString $Param['help']
    $takesValue = -not $Param['is_flag']
    $choices = @()
    if ($takesValue) {
        if ($Param.Contains('choices') -and $Param['choices']) {
            $choices = @($Param['choices'])
        } elseif ($type -eq 'boolean') {
            $choices = @('true', 'false')
        } elseif ($name -eq 'where') {
            $choices = @('local', 'cloud' | Where-Object { -not $help -or $help -match "\b$_\b" })
        } elseif ($type -eq 'str') {
            if ($help -match '^\[(?<list>[A-Za-z][\w-]*(?:\|[A-Za-z][\w-]*)+)\]') {
                $choices = @($Matches.list -split '\|')
            } elseif ($help -match '\bone of:?\s*(?<list>[A-Za-z][\w-]*(?:\s*,\s*[A-Za-z][\w-]*)+)') {
                $choices = @($Matches.list -split '\s*,\s*')
            } elseif ($help -match '(?<![\w-])(?<list>[A-Za-z][\w-]*(?:\s*\|\s*[A-Za-z][\w-]*)+)\s*(?:[.)\]]|$)') {
                $choices = @($Matches.list -split '\s*\|\s*')
            } elseif ($help -match "'(?<first>[\w.-]+)'(?:\s*\([^)]*\))?\s+or\s+'(?<second>[\w.-]+)'") {
                $choices = @($Matches.first, $Matches.second)
            } elseif ($help -match "(?:^|:)\s*'(?<first>[\w.-]+)'(?:\s*\([^)]*\))?[^;']*;\s*'(?<second>[\w.-]+)'") {
                # "'full' (default) echoes ...; 'summary' returns ..."
                $choices = @($Matches.first, $Matches.second)
            } elseif ($help -match ':\s*(?<list>[A-Za-z0-9][\w-]*(?:,\s*[A-Za-z0-9][\w-]*)+)\.?$') {
                # A closed comma list that ends the help, e.g. "Output kind: image, video, audio, 3d."
                $choices = @($Matches.list -split ',\s*')
            }
        }
    }

    $flags = if ($Param.Contains('flags')) { @($Param['flags']) } else { @() }
    # Path slots are mostly typed 'str', so the parameter and long-flag names decide; *_id and model-folder names stay free text.
    $longFlag = @($flags | Where-Object { $_ -like '--*' } | Select-Object -First 1)
    $slotNames = @($name) + @($longFlag | ForEach-Object { $_.TrimStart('-') -replace '-', '_' })
    $kind = if ($choices.Count -gt 0) { 'Choice' }
    elseif (-not $takesValue) { 'Flag' }
    elseif ($slotNames -match '^(?:workspace|workspace_path|lib)$|(?:^|_)(?:dir|root)$') { 'Directory' }
    elseif ($type -eq 'path' -or $slotNames -match '(?:^|_)(?:file|files|path|workflow|output|input|out|blueprint|gallery|deps|ops|template|fragment|python|snapshot)$') { 'Path' }
    else { 'Value' }

    $description = if ($help) { $help } else { $name -replace '_', ' ' }
    if ($Param['required']) { $description = 'Required. ' + $description }
    [pscustomobject]@{
        Name        = $name -replace '_', '-'
        Flags       = $flags
        TakesValue  = $takesValue
        Kind        = $kind
        Choices     = $choices
        Open        = $help -match '\bor one of\b'
        Hidden      = [bool]$Param['hidden']
        Description = $description
    }
}

function Add-ComfyCliNode {
    param([System.Collections.IDictionary]$Command, [string]$Path, [System.Collections.IDictionary]$Tree)

    $node = [pscustomobject]@{
        Commands  = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        Options   = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        Arguments = [System.Collections.Generic.List[object]]::new()
    }
    foreach ($param in @($Command['params'])) {
        $entry = ConvertTo-ComfyCliParamEntry $param
        if ($param['param_kind'] -eq 'argument') { $node.Arguments.Add($entry); continue }
        foreach ($flag in $entry.Flags) {
            # Typer's shell-integration installers are not useful completions.
            if ($flag -in @('--install-completion', '--show-completion')) { continue }
            $node.Options[$flag] = $entry
        }
    }
    $node.Options['--help'] = [pscustomobject]@{
        Name = 'help'; Flags = @('--help'); TakesValue = $false; Kind = 'Flag'; Choices = @(); Open = $false
        Hidden = $false; Description = 'Show this message and exit.'
    }
    $Tree[$Path] = $node

    if ($Command.Contains('subcommands') -and $Command['subcommands']) {
        foreach ($name in $Command['subcommands'].Keys) {
            $sub = $Command['subcommands'][$name]
            $summary = Get-ComfyCliHelpString $(if ($sub['short_help']) { $sub['short_help'] } else { $sub['help'] })
            $node.Commands[$name] = [pscustomobject]@{ Description = $summary; Hidden = [bool]$sub['hidden'] }
            Add-ComfyCliNode -Command $sub -Path ($Path + ' ' + $name).Trim() -Tree $Tree
        }
    }
}

function Get-ComfyCliTree {
    $cache = $script:ComfyCliCompletionCache
    if ($null -ne $cache.Tree) { return $cache.Tree }
    if ($cache.Missing -or [Environment]::TickCount64 -lt $cache.RetryAt) { return $null }
    $exe = Get-Command comfy-cli.exe -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if ($null -eq $exe) { $cache.Missing = $true; return $null }
    # A timeout or unreadable output is retried on a later Tab, at most once a minute.
    $cache.RetryAt = [Environment]::TickCount64 + 60000

    $json = Invoke-ComfyCliHelpJson -Path $exe.Source
    # Test-Json first: a caught ConvertFrom-Json failure would still land in the caller's $Error.
    if (-not $json -or -not (Test-Json -Json $json -ErrorAction Ignore)) { return $null }
    try { $envelope = $json | ConvertFrom-Json -AsHashtable -ErrorAction Stop } catch { return $null }
    if (-not ($envelope -is [System.Collections.IDictionary] -and $envelope['ok'] -and $envelope['data'])) { return $null }

    $data = $envelope['data']
    $tree = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    Add-ComfyCliNode -Command @{ params = $data['root']['params']; subcommands = $data['commands'] } -Path '' -Tree $tree

    # `comfy generate` parses its own flags, so --help-json lists only its target; these come from `comfy generate --help`.
    if ($tree.ContainsKey('generate')) {
        $generate = $tree['generate']
        foreach ($spec in @(
                @('--download', 'Path', 'Download the generated output to this path.'),
                @('--async', 'Flag', 'Submit without waiting; resume later with `comfy generate resume <model> <job>`.'),
                @('--yes', 'Flag', 'Skip the credit-spend confirmation (required for --json and non-TTY runs).'),
                @('--api-key', 'Value', 'Comfy API key (otherwise the cloud login session or COMFY_API_KEY).'),
                @('--emit-workflow', 'Path', 'Write a runnable workflow to this path instead of calling the proxy.'),
                @('--emit-ops', 'Flag', 'With --emit-workflow, also return a stamped op batch in the envelope.'),
                @('--actor', 'Value', 'Op author id for --emit-ops.'),
                @('--base-version', 'Value', 'Draft version the emitted ops are stamped against.'))) {
            $generate.Options[$spec[0]] = [pscustomobject]@{
                Name = $spec[0].TrimStart('-'); Flags = @($spec[0]); TakesValue = $spec[1] -ne 'Flag'; Kind = $spec[1]
                Choices = @(); Open = $false; Hidden = $false; Description = $spec[2]
            }
        }
    }

    $cache.Tree = $tree
    return $tree
}

function New-ComfyCliCompletion {
    param([string]$Text, [string]$Description, [string]$Type = 'ParameterValue', [string]$ListText = '')

    if (-not $Text) { return }
    if (-not $ListText) { $ListText = $Text }
    if (-not $Description) { $Description = $ListText }
    $insert = $Text
    $attached = [regex]::Match($Text, '^(?<option>--?[A-Za-z][A-Za-z0-9-]*=)(?<value>.*)$')
    if ($attached.Success -and $attached.Groups['value'].Value -match '[\s''"`$;|&(){}<>#@]') {
        $insert = $attached.Groups['option'].Value + "'" + $attached.Groups['value'].Value.Replace("'", "''") + "'"
    } elseif ($Text -match '[\s''"`$;|&(){}<>#@]') {
        $insert = "'" + $Text.Replace("'", "''") + "'"
    }
    [System.Management.Automation.CompletionResult]::new($insert, $ListText, $Type, $Description)
}

function Get-ComfyCliPathCompletion {
    param([string]$Word, [string]$Prefix = '', [bool]$DirectoryOnly = $false)

    $word = $Word.Trim("'", '"')
    if ($word -match '^(?:\\\\|//)' -or $word -match '^[^:]+::') {
        New-ComfyCliCompletion ($Prefix + $(if ($word) { $word } else { '<path>' })) 'Enter a local path; remote paths are not enumerated'
        return
    }
    $parent = '.'
    $leaf = $word
    if ($word -match '[/\\]$') { $parent = $word; $leaf = '' }
    elseif ($word -match '[/\\]') { $parent = Split-Path -Path $word -Parent; $leaf = Split-Path -Path $word -Leaf }
    $found = $false
    if (Test-Path -LiteralPath $parent -PathType Container) {
        foreach ($item in (Get-ChildItem -LiteralPath $parent -Force -ErrorAction Ignore)) {
            if ($DirectoryOnly -and -not $item.PSIsContainer) { continue }
            if (-not $item.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $candidate = if ($parent -eq '.') { $item.Name } else { Join-Path $parent $item.Name }
            if ($item.PSIsContainer) { $candidate += [System.IO.Path]::DirectorySeparatorChar }
            New-ComfyCliCompletion ($Prefix + $candidate) $item.FullName
            $found = $true
        }
    }
    if (-not $found) {
        New-ComfyCliCompletion ($Prefix + $(if ($word) { $word } else { '<path>' })) 'Enter a local path'
    }
}

function Get-ComfyCliValueCompletion {
    param([string]$Slot, [object]$Entry, [string]$Word, [string]$Prefix = '')

    $value = $Word.Trim("'", '"')
    switch ($Entry.Kind) {
        'Directory' { Get-ComfyCliPathCompletion -Word $value -Prefix $Prefix -DirectoryOnly $true; return }
        'Path' { Get-ComfyCliPathCompletion $value $Prefix; return }
        'Choice' {
            $found = $false
            foreach ($choice in $Entry.Choices) {
                if ($choice.StartsWith($value, [System.StringComparison]::OrdinalIgnoreCase)) {
                    New-ComfyCliCompletion ($Prefix + $choice) $Entry.Description
                    $found = $true
                }
            }
            # An open list (e.g. "a model alias or one of: ...") also accepts free text.
            if (-not $Entry.Open -or ($found -and $value)) { return }
        }
    }
    $hint = '<' + $Entry.Name + '>'
    New-ComfyCliCompletion ($Prefix + $(if ($value) { $value } else { $hint })) "Enter $hint for $Slot. $($Entry.Description)"
}

function Get-ComfyCliOperandCompletion {
    param([object]$Node, [int]$Index, [string]$Word)

    $arguments = $Node.Arguments
    if ($arguments.Count -eq 0) { return }
    $last = $arguments[$arguments.Count - 1]
    # --help-json does not mark variadic arguments; their names are plural (nodes, files, prompt_ids).
    $argument = if ($Index -lt $arguments.Count) { $arguments[$Index] } elseif ($last.Name -match 's$') { $last } else { $null }
    if ($null -eq $argument) { return }
    Get-ComfyCliValueCompletion -Slot $argument.Name -Entry $argument -Word $Word
}

function Complete-ComfyCli {
    param([string]$Word, [System.Management.Automation.Language.CommandAst]$Ast, [int]$Cursor)

    $tree = Get-ComfyCliTree
    if ($null -eq $tree) { return }

    $tokens = @()
    foreach ($element in @($Ast.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.StartOffset -ge $Cursor) { break }
        if ($element.Extent.EndOffset -ge $Cursor -and $Word) { break }
        $text = $element.Extent.Text
        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $text = $element.Value }
        $tokens += $text
    }

    $path = ''
    $node = $tree[$path]
    $operands = @()
    $pending = $null
    $endOptions = $false
    foreach ($token in $tokens) {
        if ($null -ne $pending) { $pending = $null; continue }
        if ($token -ceq '--') { $endOptions = $true; continue }
        if (-not $endOptions -and $token.StartsWith('-')) {
            $optionName = ($token -split '=', 2)[0]
            if ($token -notmatch '=' -and $node.Options.ContainsKey($optionName) -and $node.Options[$optionName].TakesValue) {
                $pending = $optionName
            }
            continue
        }
        if (-not $endOptions -and $operands.Count -eq 0 -and $node.Commands.ContainsKey($token)) {
            $path = ($path + ' ' + $token).Trim()
            $node = $tree[$path]
            continue
        }
        $operands += $token
    }

    if ($null -ne $pending) {
        Get-ComfyCliValueCompletion -Slot $pending -Entry $node.Options[$pending] -Word $Word
        return
    }
    if (-not $endOptions -and $Word -match '^(?<option>--?[A-Za-z][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = $Matches.option
        $value = $Matches.value
        if ($node.Options.ContainsKey($option) -and $node.Options[$option].TakesValue) {
            Get-ComfyCliValueCompletion -Slot $option -Entry $node.Options[$option] -Word $value -Prefix ($option + '=')
            return
        }
    }

    $found = $false
    if (-not $endOptions -and ($Word.StartsWith('-') -or -not $Word)) {
        foreach ($option in @($node.Options.Keys | Sort-Object -CaseSensitive)) {
            $entry = $node.Options[$option]
            if (-not $entry.Hidden -and $option.StartsWith($Word, [System.StringComparison]::Ordinal)) {
                New-ComfyCliCompletion -Text $option -Description $entry.Description -Type 'ParameterName'
                $found = $true
            }
        }
    }
    if (-not $endOptions -and $operands.Count -eq 0 -and -not $Word.StartsWith('-')) {
        foreach ($command in @($node.Commands.Keys | Sort-Object)) {
            $entry = $node.Commands[$command]
            if (-not $entry.Hidden -and $command.StartsWith($Word, [System.StringComparison]::OrdinalIgnoreCase)) {
                New-ComfyCliCompletion $command $entry.Description
                $found = $true
            }
        }
    }
    if ($found -and ($Word.StartsWith('-') -or $node.Commands.Count -gt 0)) { return }
    if ($Word.StartsWith('-') -and -not $endOptions) { return }
    Get-ComfyCliOperandCompletion -Node $node -Index $operands.Count -Word $Word
}

Register-ArgumentCompleter -Native -CommandName @('comfy-cli', 'comfy-cli.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-ComfyCli -Word $wordToComplete -Ast $commandAst -Cursor $cursorPosition
}
