Register-ArgumentCompleter -Native -CommandName @("just", "just.exe", "j") -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $prev = $env:JUST_COMPLETE;
    $env:JUST_COMPLETE = "powershell";

    $args1 = $commandAst.Extent.Text
    $args1 = $args1.Substring(0, [math]::Min($cursorPosition, $args1.Length));
    if ($wordToComplete -eq "") {
        $args1 += " ''";
    }

    $results = Invoke-Expression @"
& "C:\\Users\\Trent\\AppData\\Local\\Microsoft\\WinGet\\Packages\\Casey.Just_Microsoft.Winget.Source_8wekyb3d8bbwe\\just.exe" -- $args1
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