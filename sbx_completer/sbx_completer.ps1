<#
.SYNOPSIS
Registers Docker Sandboxes (`sbx`) tab-completion through the installed `sbx` executable.

.DESCRIPTION
This script registers importer-safe native completers for `sbx` and `sbx.exe`.
Each Tab speaks cobra's completion protocol directly: the typed command line is
projected to literal arguments without evaluating anything, `sbx __complete` is
started as a child process, and its answer becomes the completion list, so
subcommands, flags and sandbox names always match the installed `sbx` version.

Run once per session, or dot-source it from your PowerShell profile.
#>

Set-StrictMode -Version Latest

function Get-SbxCommandPath {
    $cachedPath = Get-Variable -Name SbxCommandPath -Scope Script -ErrorAction Ignore
    if ($null -ne $cachedPath) {
        return $cachedPath.Value
    }

    $sbxCommand = Get-Command -Name 'sbx', 'sbx.exe' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    $script:SbxCommandPath = if ($null -ne $sbxCommand) { $sbxCommand.Source } else { $null }
    $script:SbxCommandPath
}

function ConvertTo-SbxArgument {
    # Renders a value as one PowerShell argument: bare when safe and no quote was typed,
    # otherwise in the typed quote style (single by default). A leading '@' or '#' would
    # start a splat or a comment.
    param(
        [string]$Value,
        [string]$Quote
    )

    if (-not $Quote) {
        if ($Value -notmatch '[\s{}();,|&<>''"`$\u2018-\u201E]' -and $Value -notmatch '^[@#]') {
            return $Value
        }

        $Quote = "'"
    }

    if ($Quote -eq "'") {
        return "'" + ($Value -replace '([''\u2018-\u201B])', '$1$1') + "'"
    }

    '"' + ($Value -replace '([`"$\u201C-\u201E])', '`$1') + '"'
}

function Get-SbxCompletionRequest {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # Project the typed line to literal argv without evaluating anything the user typed:
    # string constants by value, every other element (sub-expressions, variables, splats)
    # by its raw text. Elements at or after the cursor are dropped, as cobra expects.
    $arguments = [System.Collections.Generic.List[string]]::new()
    $current = $null
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.StartOffset -ge $CursorPosition) {
            break
        }

        if ($element.Extent.EndOffset -ge $CursorPosition) {
            $current = $element
            break
        }

        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $arguments.Add($element.Value)
        } else {
            $arguments.Add($element.Extent.Text)
        }
    }

    $quote = ''
    if ($null -eq $current) {
        $word = ''
    } elseif ($current -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $current.Extent.EndOffset -eq $CursorPosition) {
        $word = $current.Value
        $quote = switch ($current.StringConstantType) {
            'BareWord' { '' }
            { $_ -in 'SingleQuoted', 'SingleQuotedHereString' } { "'" }
            default { '"' }
        }
    } else {
        $word = $current.Extent.Text.Substring(0, $CursorPosition - $current.Extent.StartOffset)
    }

    # An attached '--flag=value' completes the value; cobra answers with bare values.
    $prefix = ''
    if ($word -cmatch '^(--[^=]+=)(.*)$') {
        $prefix = $Matches[1]
        $word = $Matches[2]
    }

    if (-not $quote -and $word.Length -gt 0 -and $word[0] -in "'", '"') {
        $quote = [string]$word[0]
        $word = $word.Substring(1)
        if ($word.EndsWith($quote)) {
            $word = $word.Substring(0, $word.Length - 1)
        }
    }

    # A cursor after whitespace still sends the empty word being completed.
    $arguments.Add($prefix + $word)

    [pscustomobject]@{
        Arguments = $arguments.ToArray()
        Prefix    = $prefix
        Quote     = $quote
        Word      = $word
    }
}

function Invoke-SbxCompleteCommand {
    param([string[]]$Arguments)

    # A completion callback must stay silent: diagnostics go to the verbose stream only.
    $sbxCommandPath = Get-SbxCommandPath
    if ([string]::IsNullOrWhiteSpace($sbxCommandPath)) {
        Write-Verbose 'Docker Sandboxes CLI (sbx) was not found in PATH.'
        return $null
    }

    try {
        # ArgumentList hands each argument to sbx verbatim: no shell, no re-parsing.
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($sbxCommandPath)
        $startInfo.ArgumentList.Add('__complete')
        foreach ($argument in $Arguments) {
            $startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $startInfo.Environment['SBX_ACTIVE_HELP'] = '0'

        # A child inherits the process start directory, which Set-Location never updates.
        $location = Get-Location -PSProvider FileSystem -ErrorAction Ignore
        if ($null -ne $location) {
            $startInfo.WorkingDirectory = $location.ProviderPath
        }

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $process.StandardInput.Close()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            [void]$process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) {
                Write-Verbose 'sbx __complete timed out.'
                $process.Kill($true)
                return $null
            }

            $outputTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', ''
        } finally {
            $process.Dispose()
        }
    } catch {
        Write-Verbose ("sbx __complete failed: {0}" -f $_.Exception.Message)
        $null
    }
}

function Get-SbxCobraCompletion {
    param([psobject]$Request)

    $output = Invoke-SbxCompleteCommand -Arguments $Request.Arguments
    if ([string]::IsNullOrWhiteSpace($output)) {
        return
    }

    $lines = @($output -split '\r?\n' | Where-Object { $_ -ne '' })
    $directive = 0
    if ($lines.Count -eq 0 -or $lines[-1] -notmatch '^:(\d+)$' -or -not [int]::TryParse($Matches[1], [ref]$directive)) {
        return
    }

    # Error (1) means no completions; FilterFileExt (8) and FilterDirs (16) ask the shell for
    # paths. Returning nothing leaves those to PowerShell's own path completion, as does an
    # empty answer under the default directive. An empty answer under NoFileComp (4) cannot
    # suppress that fallback: PowerShell rejects an empty completion text.
    if (($directive -band (1 -bor 8 -bor 16)) -ne 0) {
        return
    }

    $candidates = foreach ($line in @($lines | Select-Object -First ($lines.Count - 1))) {
        $value, $description = $line.Split("`t", 2)
        if ($value.Length -gt 0 -and $value.StartsWith($Request.Word, [System.StringComparison]::OrdinalIgnoreCase)) {
            [pscustomobject]@{
                Value       = $value
                Description = if ($description) { $description } else { $value }
            }
        }
    }

    # KeepOrder (32) preserves sbx's ordering; otherwise sort like cobra's own scripts.
    if (($directive -band 32) -eq 0) {
        $candidates = $candidates | Sort-Object -Property Value
    }

    foreach ($candidate in $candidates) {
        $completionText = $Request.Prefix + (ConvertTo-SbxArgument -Value $candidate.Value -Quote $Request.Quote)
        [System.Management.Automation.CompletionResult]::new($completionText, $candidate.Value, 'ParameterValue', $candidate.Description)
    }
}

function Get-SbxFlagValueSlot {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    # Closed value sets that 'sbx <command> --help' documents but cobra does not register.
    # --skills and --pull exist only for local sandboxes, so they are dropped under --cloud.
    $valueSets = @{
        'run --on-timeout'    = 'stop', 'restart', 'delete'
        'run --platform'      = 'linux/amd64', 'linux/arm64'
        'run --skills'        = 'off', 'readonly', 'readwrite'
        'run --pull'          = 'always', 'missing', 'never'
        'create --on-timeout' = 'stop', 'restart', 'delete'
        'create --platform'   = 'linux/amd64', 'linux/arm64'
        'create --skills'     = 'off', 'readonly', 'readwrite'
        'create --pull'       = 'always', 'missing', 'never'
        'move --to'           = 'local', 'cloud'
        'move --on-timeout'   = 'stop', 'delete'
    }
    $localOnlyFlags = '--skills', '--pull'

    $elements = @($CommandAst.CommandElements | Select-Object -Skip 1)
    $preceding = @($elements | Where-Object { $_.Extent.EndOffset -lt $CursorPosition } | ForEach-Object { $_.Extent.Text })
    $current = $elements | Where-Object { $_.Extent.StartOffset -lt $CursorPosition -and $_.Extent.EndOffset -ge $CursorPosition } | Select-Object -First 1
    $typed = if ($null -ne $current) { $current.Extent.Text.Substring(0, $CursorPosition - $current.Extent.StartOffset) } else { '' }

    # Everything after a bare '--' belongs to the agent; root flags take no value, so the first bare word is the command.
    if ($preceding -ccontains '--') {
        return $null
    }
    $command = $preceding | Where-Object { -not $_.StartsWith('-') } | Select-Object -First 1
    if ($null -eq $command) {
        return $null
    }

    $attached = $typed -cmatch '^(--[a-z-]+=)(.*)$'
    if ($attached) {
        $flag = $Matches[1].TrimEnd('=')
        $prefix = $Matches[1]
        $valueText = $Matches[2]
    } elseif ($preceding.Count -gt 0 -and -not $typed.StartsWith('-')) {
        $flag = $preceding[-1]
        $prefix = ''
        $valueText = $typed
    } else {
        return $null
    }

    $values = $valueSets["$command $flag"]
    if ($null -eq $values -or (($preceding -ccontains '--cloud') -and $localOnlyFlags -ccontains $flag)) {
        return $null
    }

    $quote = if ($valueText.Length -gt 0 -and $valueText[0] -in "'", '"') { [string]$valueText[0] } else { '' }
    [pscustomobject]@{
        Attached = $attached
        Prefix   = $prefix
        Quote    = $quote
        Value    = $valueText.Substring($quote.Length)
        Values   = $values
    }
}

function Get-SbxFlagValueCompletion {
    param([psobject]$Slot)

    foreach ($value in $Slot.Values) {
        if ($value.StartsWith($Slot.Value, [System.StringComparison]::OrdinalIgnoreCase)) {
            $completionText = $Slot.Prefix + (ConvertTo-SbxArgument -Value $value -Quote $Slot.Quote)
            [System.Management.Automation.CompletionResult]::new($completionText, $value, 'ParameterValue', $value)
        }
    }
}

function Invoke-SbxCompletion {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete', Justification = 'cobra needs the word cut from the CommandAst element at the cursor; wordToComplete spans past the cursor and drops quotes.')]
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    $flagValueSlot = Get-SbxFlagValueSlot -CommandAst $commandAst -CursorPosition $cursorPosition

    # cobra registers no values for the table's flags, so the attached form skips the round-trip.
    if ($null -ne $flagValueSlot -and $flagValueSlot.Attached) {
        return Get-SbxFlagValueCompletion -Slot $flagValueSlot
    }

    $request = Get-SbxCompletionRequest -CommandAst $commandAst -CursorPosition $cursorPosition
    $results = @(Get-SbxCobraCompletion -Request $request)

    if ($results.Count -eq 0 -and $null -ne $flagValueSlot) {
        return Get-SbxFlagValueCompletion -Slot $flagValueSlot
    }

    $results
}

Register-ArgumentCompleter -Native -CommandName @('sbx', 'sbx.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Invoke-SbxCompletion -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
