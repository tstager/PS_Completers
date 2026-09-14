# netsh completer

## What it completes / overview
`netsh_completer.ps1` registers a native completer for `netsh` and `netsh.exe`. It builds a hierarchical completion catalog from locally available `netsh /?` help pages and expands that catalog lazily as deeper contexts are explored.

The script covers:
- root commands and contexts
- nested context and multiword command phrases such as `show interfaces`, `set address`, and `add rule`
- leaf-page tags such as `name=`, `source=`, `store=`, and similar `tag=` parameters parsed from `Usage:` and `Parameters:` blocks
- `tag=value` enums parsed from the `Usage:` block and attached to their tag (`dir=in|out`, `action=allow|block|bypass`, `[profile=public|private|domain|any[,...]]`, `[[capture=]yes|no]`), so `netsh advfirewall firewall add rule dir=<TAB>` offers `dir=in` and `dir=out`
- bare literal alternations that are not attached to a tag (true positional operands)
- root global options `-a`, `-c`, `-r`, `-u`, `-p`, and `-f`

## Registration and command names
- Registers with `Register-ArgumentCompleter -Native`
- Command names: `netsh`, `netsh.exe`
- The file enables `Set-StrictMode -Version 2.0`

```powershell
Register-ArgumentCompleter -Native -CommandName 'netsh', 'netsh.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Initialize-NetshCompletionCatalog

    $line = $commandAst.Extent.Text
    $currentWord = if ([string]::IsNullOrEmpty($wordToComplete)) { '' } else { Get-NetshCurrentToken -Line $line -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete }
    $tokensBeforeCurrent = @(Get-NetshTokensBeforeCurrent -CommandAst $commandAst -CursorPosition $cursorPosition)

    $expectedOption = Get-NetshExpectedGlobalOption -TokensBeforeCurrent $tokensBeforeCurrent
    if ($expectedOption) {
        switch ($expectedOption.ValueKind) {
            'Path' {
                foreach ($path in (Get-NetshFilePathCompletions -InputPath $currentWord)) {
                    [System.Management.Automation.CompletionResult]::new($path, $path, 'ProviderItem', $path)
                }
                return
            }
            'Context' {
                foreach ($item in (Get-NetshContextValueCompletions -WordToComplete $currentWord)) {
                    New-NetshCompletionResult -CompletionText $item.CompletionText -ResultType $item.ResultType -ToolTip $item.ToolTip
                }
                return
            }
            'Password' {
                if ([string]::IsNullOrWhiteSpace($currentWord) -or '*' -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*')) {
                    New-NetshCompletionResult -CompletionText '*' -ResultType 'ParameterValue' -ToolTip 'Prompt for the password.'
                }
                return
            }
            'Text' {
                # Free-form remote machine / user name: a placeholder (and the local
                # machine name for -r) instead of the command tree or the filesystem.
                $candidates = @($expectedOption.Placeholder)
                if ($expectedOption.Token -eq '-r' -and -not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
                    $candidates = @($env:COMPUTERNAME) + $candidates
                }

                foreach ($candidate in $candidates) {
                    if ([string]::IsNullOrWhiteSpace($currentWord) -or $candidate -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*')) {
                        New-NetshCompletionResult -CompletionText $candidate -ResultType 'ParameterValue' -ToolTip $expectedOption.ToolTip
                    }
                }
                return
            }
            default {
                return
            }
        }
    }

    $parsedState = Get-NetshParsedState -Tokens $tokensBeforeCurrent
    Ensure-NetshPathLoaded -PathTokens $parsedState.ContextTokens
    $resolved = Resolve-NetshCommandPath -BasePathTokens $parsedState.ContextTokens -Tokens $parsedState.CommandTokens
    Ensure-NetshPathLoaded -PathTokens $resolved.PathTokens
    $activeNode = Get-NetshNode -PathTokens $resolved.PathTokens
    if (-not $activeNode) {
        $activeNode = Get-NetshNode -PathTokens $resolved.PathTokens -Create
    }

    $resultMap = [ordered]@{}
    $candidateItems = New-Object System.Collections.Generic.List[object]

    $isOptionWord = ($currentWord -like '-*') -or ($currentWord -like '/*')
    if ($isOptionWord -or $resolved.PathTokens.Count -eq 0) {
        foreach ($item in (Get-NetshGlobalOptionSuggestions -WordToComplete $currentWord)) {
            $candidateItems.Add($item)
        }
    }

    if (-not $isOptionWord) {
        foreach ($item in (Get-NetshCollectionSuggestions -Collection $activeNode.NextTokens -WordToComplete $currentWord)) {
            $candidateItems.Add($item)
        }

        foreach ($item in (Get-NetshCollectionSuggestions -Collection $activeNode.UsageSuggestions -WordToComplete $currentWord)) {
            $candidateItems.Add($item)
        }

        foreach ($item in (Get-NetshInlineTagValueSuggestions -ValueHintsByTag $activeNode.ValueHintsByTag -WordToComplete $currentWord)) {
            $candidateItems.Add($item)
        }
    }

    foreach ($item in $candidateItems) {
        $key = $item.CompletionText.ToLowerInvariant()
        if (-not $resultMap.Contains($key)) {
            $resultMap[$key] = New-NetshCompletionResult -CompletionText $item.CompletionText -ResultType $item.ResultType -ToolTip $item.ToolTip
        }
    }

    $resultMap.Values
}
```

## How completion works
### Script-scoped catalog
The script keeps a script-scoped hashtable named `$script:NetshCompletionCatalog` with these main buckets:
- `Initialized`
- `NodesByKey`
- `LoadedKeys`
- `ContextPathsByKey`
- `GlobalOptions`
- `GlobalOptionMap`

Each node in `NodesByKey` represents a token path such as:
- root: `__ROOT__`
- `interface`
- `interface ipv4`
- `interface ipv4 show`
- `interface ipv4 set address`

Each node caches:
- `NextTokens`: next command or subcontext tokens available from that path
- `UsageSuggestions`: leaf-page tags and bare literal keywords
- `ValueHintsByTag`: enum-style values parsed from `Parameters:` sections and from `tag=a|b|c` alternations in the `Usage:` block (placeholders such as `<IPv4 address>`, numeric ranges such as `0-65535` and templates such as `icmpv4:type,code` are dropped)

### Lazy help loading
`Initialize-NetshCompletionCatalog` seeds static global-option metadata and loads only the root help page.

`Ensure-NetshPathLoaded` then fetches `netsh <path> /?` the first time a specific token path is reached. This keeps startup cheap while allowing coverage to expand across the local `netsh` surface area as users traverse contexts.

### Help parsing
The implementation parses several `netsh` help page patterns:
- `Commands in this context:`
- `The following sub-contexts are available:`
- `Usage:`
- `Parameters:`

Key helpers:
- `ConvertTo-NetshLogicalLines` normalizes section markers that sometimes appear on the same captured line.
- `Get-NetshHelpSections` extracts command entries, subcontexts, usage lines, and parameter lines.
- `Add-NetshCommandPhrase` stores multiword phrases token by token so completion can offer `show` first, then `interfaces`, instead of flattening the phrase.
- `Test-NetshContextDescription` detects context transitions from descriptions like `Changes to the 'netsh ...' context.`
- `Get-NetshUsageTags`, `Get-NetshUsageLiteralValues`, `Get-NetshUsageTagValueMap` and `Get-NetshParameterValueHints` parse leaf syntax into `tag=` suggestions, bare literal keywords, and enum-like `tag=value` hints. A `Remarks:` or `Examples:` header closes the `Parameters:` section even when its prose shares the line, and commands whose description column is empty (`netsh trace postreset`) are kept.
- `Invoke-NetshHelpText` spawns `netsh.exe <path> /?` through `System.Diagnostics.Process` with stdin closed, asynchronous reads and a 5 s timeout, so a slow or prompting context cannot hang the prompt.

### Command-line context detection
The registered completer:
- reconstructs the current token with `Get-NetshCurrentToken`
- finds prior tokens with `Get-NetshTokensBeforeCurrent`, which keeps only the command elements whose extent ends before the cursor, so mid-token, end-of-token and trailing-space cursors behave the same and a command after another statement on the line still resolves
- offers the global options (`-a`, `-c`, `-r`, `-u`, `-p`, `-f`, `/?`, `-?`) for a `-` or `/` prefixed word or before any context is typed; `-r` and `-u` complete a `<RemoteMachine>` (plus the local machine name) or `<DomainName\UserName>` placeholder rather than the command tree
- separates root global-option state from command tokens with `Get-NetshParsedState`
- resolves the deepest known command path with `Resolve-NetshCommandPath`
- loads the active path on demand before returning suggestions

This lets the completer keep command phrases and argument tags separate from free-form values.

## Global option handling
The completer includes special handling for root options:
- `-a`: file path completion
- `-f`: file path completion
- `-c`: context name and context-path completion
- `-p`: suggests `*` as the password-prompt form
- `-r` and `-u`: recognized as value-taking options so command parsing stays aligned

For `-c`, discovered context paths are cached from parsed help pages. Single-token contexts are suggested directly, while multi-token context paths are suggested in quotes.

## Examples
```powershell
. "$PSScriptRoot\netsh_completer.ps1"

# Root contexts and verbs
# netsh <TAB>

# Multiword command phrase completion
# netsh interface ipv4 show <TAB>
# netsh advfirewall firewall add <TAB>

# Leaf tags and literals
# netsh interface ipv4 set address <TAB>
# netsh advfirewall firewall add rule <TAB>

# Global option values
# netsh -c <TAB>
# netsh -f <TAB>
```

## Dependencies or external command expectations
- Requires `netsh.exe`
- Relies on the local formatting of `netsh /?` and nested `netsh <path> /?` output
- Uses `Get-ChildItem` for file path completion

Because the catalog is derived from built-in help, the exact command surface depends on the Windows version and installed networking features on the local machine.

## Limitations / notes
- The parser is intentionally format-driven, so changes in `netsh` help text could affect discovery.
- The script focuses first on command and subcommand coverage. Value completion is intentionally lightweight and best for literal keywords and enum-like `tag=value` forms.
- Free-form values such as interface names, IP addresses, SDDL strings, and many file or service names are not exhaustively completed.
- Context discovery is lazy. A deep context path is only offered for `-c` after its parent help page has been loaded in the current session.
