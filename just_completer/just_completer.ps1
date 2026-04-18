Set-StrictMode -Version 2.0

function Resolve-JustCommandName {
    if (Get-Variable -Name JustCompletionCommandName -Scope Script -ErrorAction SilentlyContinue) {
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

function Invoke-JustCompletion {
    param([string]$CommandLine)

    $commandName = Resolve-JustCommandName
    if (-not $commandName) {
        return @()
    }

    $escapedCommandName = $commandName.Replace("'", "''")
    Invoke-Expression "& '$escapedCommandName' -- $CommandLine"
}

Register-ArgumentCompleter -Native -CommandName @("just", "just.exe") -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $prev = $env:JUST_COMPLETE
    $env:JUST_COMPLETE = "powershell"

    $args1 = $commandAst.Extent.Text
    $args1 = $args1.Substring(0, [math]::Min($cursorPosition, $args1.Length))
    if ($wordToComplete -eq "") {
        $args1 += " ''"
    }

    try {
        $results = Invoke-JustCompletion -CommandLine $args1
    } finally {
        if ($null -eq $prev) {
            Remove-Item Env:\JUST_COMPLETE -ErrorAction SilentlyContinue
        } else {
            $env:JUST_COMPLETE = $prev
        }
    }

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
