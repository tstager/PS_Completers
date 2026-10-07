# curl completer

## What it completes / overview

`curl_completer.ps1` registers a standalone native PowerShell completer for `curl` and `curl.exe`.

It is a help-driven completer that:

- parses the local `curl.exe --help all` surface once per session
- suggests both short and long option forms, keyed ordinally so case-distinct short options such as `-s`/`-S`, `-o`/`-O`, and `-x`/`-X` are all offered and never rewritten into each other
- completes `--help` subjects from `curl.exe --help category`
- provides targeted enum hints for high-value option values like protocol lists, certificate types, FTP modes, and TLS versions
- offers filesystem completion for file, directory, certificate, and `@file`-style value slots
- suppresses irrelevant filesystem fallback for free-form URL and text arguments with placeholder-style suggestions

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'curl', 'curl.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    if ($wordToComplete -isnot [string]) {
        $wordToComplete = [string]$wordToComplete
    }

    Initialize-CurlCompletionCatalog

    $currentToken = Get-CurlCurrentToken -Line $commandAst.Extent.Text -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    $tokensBeforeCurrent = Get-CurlArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition

    if ($currentToken -match '^(--[^=]+)=(.*)$') {
        $optionName = $matches[1]
        $valuePrefix = $matches[2]
        $optionSpec = Get-CurlOptionSpecByToken -Token $optionName
        if ($optionSpec -and $optionSpec.ValueKind) {
            return @(Get-CurlValueCompletions -OptionSpec $optionSpec -CurrentValue $valuePrefix -Prefix ($optionName + '='))
        }
    }

    $atWord = Get-CurlAtFileWord -CommandAst $commandAst -CursorPosition $cursorPosition
    if ($atWord) {
        # A split-off '@' is part of the value being typed, not a value of its own.
        $atTokens = if ($atWord.SplitAt) { @($tokensBeforeCurrent | Select-Object -First (@($tokensBeforeCurrent).Count - 1)) } else { $tokensBeforeCurrent }
        $atOption = Get-CurlPendingOption -TokensBeforeCurrent $atTokens
        if ($atOption -and $atOption.ValueKind -in 'DataValue', 'HeaderOrFile') {
            return @(Get-CurlValueCompletions -OptionSpec $atOption -CurrentValue $atWord.Value -Quote $atWord.Quote -SplitAt:$atWord.SplitAt)
        }
    }

    $pendingOption = Get-CurlPendingOption -TokensBeforeCurrent $tokensBeforeCurrent
    if ($pendingOption) {
        return @(Get-CurlValueCompletions -OptionSpec $pendingOption -CurrentValue $wordToComplete)
    }

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    if ([string]::IsNullOrWhiteSpace($currentToken) -or $currentToken.StartsWith('-')) {
        foreach ($result in @(Get-CurlOptionCompletions -CurrentWord $wordToComplete)) {
            [void]$results.Add($result)
        }
    }

    if (-not $currentToken.StartsWith('-')) {
        foreach ($result in @(Get-CurlPositionalCompletions -CurrentWord $wordToComplete)) {
            [void]$results.Add($result)
        }
    }

    @($results.ToArray())
}
```

Load it with:

```powershell
. .\curl_completer\curl_completer.ps1
```

The script also enables:

```powershell
Set-StrictMode -Version 2.0
```

## How completion works

### Help-driven option catalog

Initialization captures:

- `curl.exe --help all` for the option surface
- `curl.exe --help category` for help-topic values
- `curl.exe --version` for the locally available protocol list

The parsed catalog is cached in script scope and built lazily on first completion use, which keeps the top level import-safe for `Import-CompleterScript`.

### Value-aware handling

The completer uses the placeholder text from curl help plus a small static overlay to decide when to:

- offer enum values such as `DER`, `PEM`, `P12`, `multicwd`, `singlecwd`, `active`, `passive`, TLS version hints, and the `--krb` levels `clear`, `safe`, `confidential`, `private`
- complete `--upload-flags` as a comma list of `answered`, `deleted`, `draft`, `flagged`, `seen`, each optionally negated with a leading `-` (curl's own spelling; the names are case-sensitive)
- complete protocol-bearing values like `http://`, `https://`, or protocol lists for `--proto`
- complete file paths for options like `--config`, `--output`, `--trace`, `--key`, `--cacert`, and `--output-dir`
- treat `-d`, `--data`, `-H`, `--header`, `--proxy-header`, and `--variable` specially when the value uses `@file`-style syntax
- read a separate `@file` value for `-d`/`-H` and their long forms from the parsed command elements: a leading `@` would start a PowerShell splat, so `'@.\` and `"@.\` complete to whole quoted values in the typed quote style (`'@.\data.json'`), and a bare `@` completes to single-quoted values
- emit the documented `<placeholder>` for any other value-taking option, so a value slot never falls back to the option list

### Inline long-option values

Long options written as `--option=value` are completed in-place for the option sets that have recognized value kinds.

## Usage examples

```powershell
curl -
curl --help 
curl --proto=
curl --config .\
curl -d @
curl -d '@.\
curl --upload-flags seen,-
curl https
```

## Dependencies or external command expectations

- Expects `curl.exe` or `curl` to be resolvable if help data should be harvested
- Falls back to built-in help-topic defaults and placeholder completion when runtime discovery is unavailable
- File and directory completion depend on local filesystem access

## Limitations / notes

- The completer does not attempt to model every curl option as repeatable vs singleton; it favors broad option discovery over strict deduplication.
- Free-form values such as headers, request methods, credentials, and URL templates intentionally use placeholder-oriented completion instead of speculative parsing.
- Short options with attached values are not specially parsed; value-aware completion is focused on space-separated forms and `--long=value`.
- An unquoted `@.\` is not valid PowerShell: the parser splits it into an `@` token and `.\`, and completion can only replace the `.\` part, so that spelling completes the path after the `@` but the line still needs the `@` value quoted to run. Type `'@.\` instead.
