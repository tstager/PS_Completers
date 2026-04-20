Set-StrictMode -Version Latest

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-ContainsCompletion {
    param(
        [string[]]$CompletionTexts,
        [string]$Expected,
        [string]$Context
    )

    if ($Expected -notin $CompletionTexts) {
        $joined = if ($CompletionTexts.Count -gt 0) {
            $CompletionTexts -join ', '
        } else {
            '<none>'
        }

        throw "Expected completion '$Expected' for $Context. Actual: $joined"
    }
}

function Get-CompletionTexts {
    param([string]$InputText)

    @(
        (TabExpansion2 $InputText $InputText.Length).CompletionMatches |
            Select-Object -ExpandProperty CompletionText
    )
}

$scriptPath = Join-Path $PSScriptRoot 'markitdown_completer.ps1'
Assert-True -Condition (Test-Path -LiteralPath $scriptPath) -Message "Completer script not found: $scriptPath"

$null = $tokens = $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
Assert-True -Condition ($errors.Count -eq 0) -Message ("Parse errors: " + (($errors | ForEach-Object { $_.Message }) -join ' | '))

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Get-ChildItem -Path (Join-Path $repoRoot '..\Modules\CompleterActions\*\CompleterActions.psd1') -ErrorAction Stop |
    Sort-Object { [version]$_.Directory.Name } -Descending |
    Select-Object -First 1 -ExpandProperty FullName

Import-Module $modulePath -Force
$imported = @(Import-CompleterScript -LiteralPath $scriptPath)
Assert-True -Condition ($imported.Count -eq 2) -Message "Expected 2 imported completer definitions, found $($imported.Count)."
Assert-ContainsCompletion -CompletionTexts @($imported.CommandName) -Expected 'markitdown' -Context 'Import-CompleterScript command registrations'
Assert-ContainsCompletion -CompletionTexts @($imported.CommandName) -Expected 'markitdown.exe' -Context 'Import-CompleterScript command registrations'

. $scriptPath

$optionCompletions = Get-CompletionTexts -InputText 'markitdown -'
Assert-ContainsCompletion -CompletionTexts $optionCompletions -Expected '-o' -Context 'markitdown -'
Assert-ContainsCompletion -CompletionTexts $optionCompletions -Expected '--list-plugins' -Context 'markitdown -'

$charsetCompletions = Get-CompletionTexts -InputText 'markitdown --charset '
Assert-ContainsCompletion -CompletionTexts $charsetCompletions -Expected 'utf-8' -Context 'markitdown --charset '

$mimeCompletions = Get-CompletionTexts -InputText 'markitdown --mime-type '
Assert-ContainsCompletion -CompletionTexts $mimeCompletions -Expected 'application/pdf' -Context 'markitdown --mime-type '

$inputPathCompletions = Get-CompletionTexts -InputText 'markitdown .\markitdown_completer\'
Assert-ContainsCompletion -CompletionTexts $inputPathCompletions -Expected '.\markitdown_completer\validate_markitdown_completer.ps1' -Context 'markitdown input path completion'

$outputPathCompletions = Get-CompletionTexts -InputText 'markitdown -o .\markitdown_completer\'
Assert-ContainsCompletion -CompletionTexts $outputPathCompletions -Expected '.\markitdown_completer\validate_markitdown_completer.ps1' -Context 'markitdown -o path completion'

$exeCompletions = Get-CompletionTexts -InputText 'markitdown.exe --charset '
Assert-ContainsCompletion -CompletionTexts $exeCompletions -Expected 'utf-8' -Context 'markitdown.exe --charset '

'VALIDATION=PASS'
