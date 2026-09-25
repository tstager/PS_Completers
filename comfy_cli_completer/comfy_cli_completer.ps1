# Help-driven completion for the installed comfy-cli executable.
Set-StrictMode -Version 2.0

function Get-ComfyCliHelpText {
    param([string[]]$Segments)

    $exe = Get-Command comfy-cli.exe -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if ($null -eq $exe) { return '' }

    $process = [System.Diagnostics.Process]::new()
    try {
        $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($exe.Source)
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $process.StartInfo.Environment['PYTHONIOENCODING'] = 'utf-8'
        $process.StartInfo.Environment['NO_COLOR'] = '1'
        foreach ($segment in @($Segments)) { [void]$process.StartInfo.ArgumentList.Add($segment) }
        [void]$process.StartInfo.ArgumentList.Add('--help')
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(5000)) {
            $process.Kill($true)
            return ''
        }
        return ($stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()) -replace '\e\[[0-9;?]*[ -/]*[@-~]', ''
    } catch {
        return ''
    } finally {
        $process.Dispose()
    }
}

function ConvertFrom-ComfyCliHelp {
    param([string]$HelpText)

    $commands = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $options = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    $usage = ''
    $section = ''
    $current = $null
    foreach ($line in ($HelpText -split '\r?\n')) {
        if ($line -match '^\s*Usage:\s*comfy-cli(?:\.exe)?\s*(.*)$') { $usage = $Matches[1].Trim(); continue }
        if ($line -match '^\s*┌─\s*(Options|Commands)\b') { $section = $Matches[1]; $current = $null; continue }
        if ($line -match '^\s*└') { $section = ''; $current = $null; continue }
        if ($section -eq '' -or $line -notmatch '^\s*│(?<content>.*?)│\s*$') { continue }
        $raw = $Matches.content
        $content = $raw.Trim()
        if (-not $content) { continue }

        if ($section -eq 'Commands') {
            if ($content -match '^(?<name>[A-Za-z0-9][A-Za-z0-9-]*)\s{2,}(?<description>\S.*)$') {
                $commands[$Matches.name] = $Matches.description.Trim()
                $current = $Matches.name
            } elseif ($null -ne $current) {
                $commands[$current] = ($commands[$current] + ' ' + $content).Trim()
            }
            continue
        }

        $match = if ($raw -match '^\s{0,3}--?') {
            [regex]::Match($content, '^(?:(?<name>--?[A-Za-z][A-Za-z0-9-]*)(?:\s+|,\s*)?)+')
        } else { [System.Text.RegularExpressions.Match]::Empty }
        if ($match.Success) {
            $names = @($match.Groups['name'].Captures | ForEach-Object { $_.Value })
            $remainder = $content.Substring($match.Length).Trim()
            $meta = ''
            if ($remainder -match '^<(?<meta>[^>]+)>\s*(?<description>.*)$') {
                $meta = $Matches.meta
                $remainder = $Matches.description.Trim()
            } elseif ($remainder -match '^(?<meta>[A-Z][A-Z0-9_]*(?:=[A-Z][A-Z0-9_]*)?)\s{2,}(?<description>.+)$') {
                $meta = $Matches.meta
                $remainder = $Matches.description.Trim()
            }
            $entry = [pscustomobject]@{ Names = $names; Meta = $meta; Description = $remainder }
            foreach ($name in $names) {
                if ($name -in @('--install-completion', '--show-completion')) { continue }
                $options[$name] = $entry
            }
            $current = $entry
        } elseif ($null -ne $current) {
            $current.Description = ($current.Description + ' ' + $content).Trim()
        }
    }

    [pscustomobject]@{ Commands = $commands; Options = $options; Usage = $usage }
}

function Get-ComfyCliCatalog {
    param([string[]]$Segments)

    if (-not (Get-Variable -Name ComfyCliCatalogs -Scope Script -ErrorAction Ignore)) {
        $script:ComfyCliCatalogs = @{}
    }
    $key = @($Segments) -join ' '
    if ($script:ComfyCliCatalogs.ContainsKey($key)) { return $script:ComfyCliCatalogs[$key] }

    $catalog = ConvertFrom-ComfyCliHelp (Get-ComfyCliHelpText $Segments)
    if ($catalog.Options.Count -gt 0 -or $catalog.Commands.Count -gt 0) {
        $script:ComfyCliCatalogs[$key] = $catalog
    }
    return $catalog
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
    param([string]$Option, [object]$Entry, [string]$Word, [string]$Prefix = '')

    $value = $Word.Trim("'", '"')
    $name = $Option.TrimStart('-')
    if ($name -match '(?i)(file|folder|directory|path|workspace|workflow|output|input|config|image)$' -or $Entry.Meta -match '(?i)^(file|path|dir|directory)$') {
        Get-ComfyCliPathCompletion $value $Prefix ($name -match '(?i)(folder|directory|workspace)$')
        return
    }

    $description = $Entry.Description
    if ($Option -ceq '--where') {
        $root = Get-ComfyCliCatalog -Segments @()
        if ($root.Options.ContainsKey('--where')) { $description = $root.Options['--where'].Description }
    }
    $choices = @()
    if ($description -match '(?i)\b(?:choices?|one of):?\s*\[?([A-Za-z][A-Za-z0-9_-]*(?:\s*[,|]\s*[A-Za-z][A-Za-z0-9_-]*)+)') {
        $choices = @($Matches[1] -split '\s*[,|]\s*')
    } elseif ($description -match "'([A-Za-z][A-Za-z0-9_-]*)'\s+or\s+'([A-Za-z][A-Za-z0-9_-]*)'") {
        $choices = @($Matches[1], $Matches[2])
    }
    if ($choices.Count -gt 0) {
        foreach ($choice in $choices) {
            if ($choice.StartsWith($value, [System.StringComparison]::OrdinalIgnoreCase)) {
                New-ComfyCliCompletion ($Prefix + $choice) $Entry.Description
            }
        }
        return
    }
    $hint = if ($Entry.Meta) { '<' + $Entry.Meta + '>' } else { '<value>' }
    New-ComfyCliCompletion ($Prefix + $(if ($value) { $value } else { $hint })) "Enter $hint for $Option"
}

function Get-ComfyCliOperandCompletion {
    param([object]$Catalog, [int]$Index, [string]$Word)

    $usage = $Catalog.Usage -replace '^\s*(?:\S+\s+)*?\[OPTIONS\]\s*', ''
    $parts = @($usage -split '\s+' | Where-Object { $_ -and $_ -notin @('COMMAND', '[ARGS]...', '[OPTIONS]') })
    if ($parts.Count -eq 0) { return }
    $operand = if ($Index -lt $parts.Count) { $parts[$Index] } elseif ($parts.Count -gt 0 -and $parts[-1] -match '\.\.\.$') { $parts[-1] } else { '<argument>' }
    $operand = $operand.Trim('[', ']', '{', '}', '.', '<', '>')
    if (-not $operand) { $operand = 'argument' }
    if ($operand -match '(?i)(file|files|path|workflow|image|folder|directory|filenames)') {
        Get-ComfyCliPathCompletion $Word
    } else {
        New-ComfyCliCompletion $(if ($Word) { $Word } else { '<' + $operand + '>' }) "Enter $operand"
    }
}

function Complete-ComfyCli {
    param([string]$Word, [System.Management.Automation.Language.CommandAst]$Ast, [int]$Cursor)

    $tokens = @()
    foreach ($element in @($Ast.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.StartOffset -ge $Cursor) { break }
        if ($element.Extent.EndOffset -ge $Cursor -and $Word) { break }
        $text = $element.Extent.Text
        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $text = $element.Value }
        $tokens += $text
    }

    $segments = @()
    $catalog = Get-ComfyCliCatalog $segments
    $operands = @()
    $pending = $null
    $endOptions = $false
    foreach ($token in $tokens) {
        if ($null -ne $pending) { $pending = $null; continue }
        if ($token -ceq '--') { $endOptions = $true; continue }
        if (-not $endOptions -and $token.StartsWith('-')) {
            $optionName = ($token -split '=', 2)[0]
            if ($token -notmatch '=' -and $catalog.Options.ContainsKey($optionName) -and $catalog.Options[$optionName].Meta) {
                $pending = $optionName
            }
            continue
        }
        if (-not $endOptions -and $operands.Count -eq 0 -and $catalog.Commands.ContainsKey($token)) {
            $segments += $token
            $catalog = Get-ComfyCliCatalog $segments
            continue
        }
        $operands += $token
    }

    if ($null -ne $pending) {
        Get-ComfyCliValueCompletion $pending $catalog.Options[$pending] $Word
        return
    }
    if (-not $endOptions -and $Word -match '^(?<option>--?[A-Za-z][A-Za-z0-9-]*)=(?<value>.*)$') {
        $option = $Matches.option
        $value = $Matches.value
        if ($catalog.Options.ContainsKey($option) -and $catalog.Options[$option].Meta) {
            Get-ComfyCliValueCompletion $option $catalog.Options[$option] $value ($option + '=')
            return
        }
    }

    $found = $false
    if (-not $endOptions -and ($Word.StartsWith('-') -or -not $Word)) {
        foreach ($option in @($catalog.Options.Keys | Sort-Object -CaseSensitive)) {
            if ($option.StartsWith($Word, [System.StringComparison]::Ordinal)) {
                New-ComfyCliCompletion $option $catalog.Options[$option].Description 'ParameterName'
                $found = $true
            }
        }
    }
    if (-not $endOptions -and $operands.Count -eq 0 -and -not $Word.StartsWith('-')) {
        foreach ($command in @($catalog.Commands.Keys | Sort-Object)) {
            if ($command.StartsWith($Word, [System.StringComparison]::OrdinalIgnoreCase)) {
                New-ComfyCliCompletion $command $catalog.Commands[$command]
                $found = $true
            }
        }
    }
    if ($found -and ($Word.StartsWith('-') -or $catalog.Commands.Count -gt 0)) { return }
    if ($Word.StartsWith('-') -and -not $endOptions) { return }
    Get-ComfyCliOperandCompletion $catalog $operands.Count $Word
}

Register-ArgumentCompleter -Native -CommandName @('comfy-cli', 'comfy-cli.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-ComfyCli -Word $wordToComplete -Ast $commandAst -Cursor $cursorPosition
}
