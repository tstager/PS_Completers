Set-StrictMode -Version 2.0

function Resolve-JustCommandName {
    if (Get-Variable -Name JustCompletionCommandName -Scope Script -ErrorAction Ignore) {
        return $script:JustCompletionCommandName
    }

    $command = Get-Command -Name just.exe, just -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    $script:JustCompletionCommandName = if ($command) {
        if ($command.Source) { $command.Source } else { $command.Name }
    } else {
        $null
    }

    $script:JustCompletionCommandName
}

function Get-JustCompletionArguments {
    param($CommandAst, [int]$CursorPosition, [string]$WordToComplete)

    # Project the AST to literal argument text without evaluating anything the user typed.
    $relativeCursor = $CursorPosition - $CommandAst.Extent.StartOffset
    $arguments = [System.Collections.Generic.List[string]]::new()

    foreach ($element in $CommandAst.CommandElements) {
        $start = $element.Extent.StartOffset - $CommandAst.Extent.StartOffset
        if ($start -ge $relativeCursor) {
            break
        }

        $end = $element.Extent.EndOffset - $CommandAst.Extent.StartOffset
        if ($end -gt $relativeCursor) {
            $arguments.Add($element.Extent.Text.Substring(0, $relativeCursor - $start))
            break
        }

        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $arguments.Add($element.Value)
        } else {
            $arguments.Add($element.Extent.Text)
        }
    }

    if ($WordToComplete -eq '') {
        $arguments.Add('')
    }

    $arguments.ToArray()
}

function Invoke-JustCompletion {
    param([string[]]$Arguments)

    $commandName = Resolve-JustCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $commandName
        [void]$startInfo.ArgumentList.Add('--')
        foreach ($argument in $Arguments) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $startInfo.Environment['JUST_COMPLETE'] = 'powershell'

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $process.StandardInput.Close()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            [void]$process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) {
                try { $process.Kill($true) } catch { Write-Debug -Message $_.Exception.Message }
                return @()
            }

            $text = ($outputTask.Result -replace '\e\[[0-9;?]*[ -/]*[@-~]', '')
            if ([string]::IsNullOrWhiteSpace($text)) {
                return @()
            }

            @($text -split '\r?\n' | Where-Object { $_ -ne '' })
        } finally {
            $process.Dispose()
        }
    } catch {
        @()
    }
}

Register-ArgumentCompleter -Native -CommandName @("just", "just.exe") -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $arguments = Get-JustCompletionArguments -CommandAst $commandAst -CursorPosition $cursorPosition -WordToComplete $wordToComplete
    $results = Invoke-JustCompletion -Arguments $arguments

    $results | ForEach-Object {
        $split = $_.Split("`t")
        $cmd = $split[0]

        if ($split.Length -eq 2) {
            $help = $split[1]
        }
        else {
            $help = $split[0]
        }

        [System.Management.Automation.CompletionResult]::new($cmd, $cmd, 'ParameterValue', $help)
    }
}
