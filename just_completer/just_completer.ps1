Register-ArgumentCompleter -Native -CommandName just -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $prev = $env:JUST_COMPLETE;
    $env:JUST_COMPLETE = "powershell";

    $args = $commandAst.Extent.Text
    $args = $args.Substring(0, [math]::Min($cursorPosition, $args.Length));
    if ($wordToComplete -eq "") {
        $args += " ''";
    }

    $results = Invoke-Expression @"
& "C:\\Users\\Trent\\AppData\\Local\\Microsoft\\WinGet\\Packages\\Casey.Just_Microsoft.Winget.Source_8wekyb3d8bbwe\\just.exe" -- $args
"@;
    if ($null -eq $prev) {
        Remove-Item Env:\JUST_COMPLETE;
    } else {
        $env:JUST_COMPLETE = $prev;
    }
    $results | ForEach-Object {
        $split = $_.Split("`t");
        $cmd = $split[0];

        if ($split.Length -eq 2) {
            $help = $split[1];
        }
        else {
            $help = $split[0];
        }

        [System.Management.Automation.CompletionResult]::new($cmd, $cmd, 'ParameterValue', $help)
    }
};