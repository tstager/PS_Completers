# netsh completer

## What it completes / overview
`netsh_completer.ps1` registers a native completer for `netsh` and `netsh.exe`. It builds a hierarchical completion catalog from locally available `netsh /?` help pages and expands that catalog lazily as deeper contexts are explored.

The script covers:
- root commands and contexts
- nested context and multiword command phrases such as `show interfaces`, `set address`, and `add rule`
- leaf-page tags such as `name=`, `source=`, `store=`, and similar `tag=` parameters parsed from `Usage:` and `Parameters:` blocks
- `tag=value` enums parsed from the `Usage:` block and attached to their tag (`dir=in|out`, `action=allow|block|bypass`, `[profile=public|private|domain|any[,...]]`, `[[capture=]yes|no]`), so `netsh advfirewall firewall add rule dir=<TAB>` offers `dir=in` and `dir=out`
- machine-state and path values for attached tags (see [Live tag values](#live-tag-values)): interface names, WLAN profile names, trace scenarios, service names, and file paths for `program=` and `traceFile=`
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
                $cursorWord = Get-NetshCursorWord -CommandAst $commandAst -CursorPosition $cursorPosition
                if ($null -ne $cursorWord.Segment) {
                    # Past an unquoted comma no path fits PowerShell's span as one argument.
                    # The typed segment is echoed so the filename fallback adds none either;
                    # an empty segment cannot be (PowerShell rejects an empty completion text).
                    if ($cursorWord.Segment) {
                        [System.Management.Automation.CompletionResult]::new($cursorWord.Segment, $cursorWord.Segment, 'ParameterValue', "An unquoted comma splits the path into an array; quote it: 'C:\a,b.txt'")
                    }
                    return
                }

                $word = ConvertFrom-NetshTypedWord -Text $cursorWord.Text
                foreach ($item in (Get-NetshFilePathCompletions -Value $word.Value)) {
                    $completionText = ConvertTo-NetshArgumentText -Value $item.Path -Quote $word.Quote
                    [System.Management.Automation.CompletionResult]::new($completionText, $item.ListItemText, $item.ResultType, $item.ToolTip)
                }
                return
            }
            'Context' {
                $word = ConvertFrom-NetshTypedWord -Text (Get-NetshCursorWord -CommandAst $commandAst -CursorPosition $cursorPosition).Text
                foreach ($item in (Get-NetshContextValueCompletions -Word $word)) {
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

    # Machine-state and path values for tags such as name=, scenario=, program=.
    $tagValueSource = $null
    $tagValue = Get-NetshCursorTagValue -CommandAst $commandAst -CursorPosition $cursorPosition
    if ($tagValue) {
        $commandWords = @($resolved.PathTokens) + @($resolved.Remaining | Where-Object { $_ -notmatch '=' })
        $tagValueSource = Get-NetshTagValueSource -CommandWords $commandWords -Tag $tagValue.Tag
    }

    # After an unquoted comma PowerShell replaces only the segment past it, so tag values
    # stand alone there; with nothing to offer the command's tags follow, as without a source.
    if ($tagValueSource -and $tagValue.SegmentOnly) {
        $segmentItems = @(Get-NetshTagValueSuggestion -Source $tagValueSource -TagValue $tagValue)
        if ($segmentItems.Count -gt 0) {
            foreach ($item in $segmentItems) {
                New-NetshCompletionResult -CompletionText $item.CompletionText -ResultType $item.ResultType -ToolTip $item.ToolTip
            }
            return
        }

        $tagValueSource = $null
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

        if ($tagValueSource) {
            foreach ($item in (Get-NetshTagValueSuggestion -Source $tagValueSource -TagValue $tagValue)) {
                $candidateItems.Add($item)
            }
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
- `Usage:` (also the colon-less `Usage set interface ...` header that `netsh interface set interface /?` prints)
- `Parameters:`

Key helpers:
- `ConvertTo-NetshLogicalLines` normalizes section markers that sometimes appear on the same captured line.
- `Get-NetshHelpSections` extracts command entries, subcontexts, usage lines, and parameter lines.
- `ConvertTo-NetshUsageLine` folds spaced optional tags (`[admin = ] ENABLED|DISABLED`, used by `interface set interface`, `ipsec`, `wfp`, `wcn` and some `ras` pages) into the `[admin=] ENABLED|DISABLED` spelling, so `admin=` offers `admin=ENABLED` and `admin=DISABLED` while the enum stays a bare positional operand (`netsh ras ipv6 set routeradvertise E` still offers `ENABLE`). Grouped enums such as `[soft=](yes|no)` keep every member.
- `Add-NetshCommandPhrase` stores multiword phrases token by token so completion can offer `show` first, then `interfaces`, instead of flattening the phrase.
- `Test-NetshContextDescription` detects context transitions from descriptions like `Changes to the 'netsh ...' context.`
- `Get-NetshUsageTags`, `Get-NetshUsageLiteralValues`, `Get-NetshUsageTagValueMap` and `Get-NetshParameterValueHints` parse leaf syntax into `tag=` suggestions, bare literal keywords, and enum-like `tag=value` hints. A `Remarks:` or `Examples:` header closes the `Parameters:` section even when its prose shares the line, and commands whose description column is empty (`netsh trace postreset`) are kept.
- `Invoke-NetshHelpText` spawns `netsh.exe <path> /?` through `System.Diagnostics.Process` with stdin closed, asynchronous reads and a 5 s timeout, so a slow or prompting context cannot hang the prompt.

### Command-line context detection
The registered completer:
- reconstructs the current token with `Get-NetshCurrentToken`; option values (`-a`, `-f`, `-c`) and attached tag values instead take the parser's word under the cursor (`Get-NetshCursorWord`) and decode it with `ConvertFrom-NetshTypedWord`, which keeps the opening quote (ASCII or typographic) and resolves doubled quotes and backtick escapes through the tokenizer
- finds prior tokens with `Get-NetshTokensBeforeCurrent`, which keeps only the command elements whose extent ends before the cursor, so mid-token, end-of-token and trailing-space cursors behave the same and a command after another statement on the line still resolves
- offers the global options (`-a`, `-c`, `-r`, `-u`, `-p`, `-f`, `/?`, `-?`) for a `-` or `/` prefixed word or before any context is typed; `-r` and `-u` complete a `<RemoteMachine>` (plus the local machine name) or `<DomainName\UserName>` placeholder rather than the command tree
- separates root global-option state from command tokens with `Get-NetshParsedState`
- resolves the deepest known command path with `Resolve-NetshCommandPath`
- loads the active path on demand before returning suggestions

This lets the completer keep command phrases and argument tags separate from free-form values.

## Live tag values
When the word under the cursor is an attached `tag=value`, `Get-NetshTagValueSource` maps the command path and tag to a local source. The word is read from the parser (`Get-NetshCursorTagValue`), so an open quote such as `name="Ethernet 2` stays one word.

| Command path | Tag | Source |
| --- | --- | --- |
| `interface ...` (not `set relay`, `set router`, `add v6v4tunnel`) | `name=`, `interface=` | `netsh interface show interface` |
| `dnsclient ...` | `name=` | `netsh interface show interface` |
| `wlan ...` | `name=` | `netsh wlan show profiles` (names only) |
| `trace ...` | `scenario=`, and `name=` under `show scenario` | registry `HKLM\SYSTEM\CurrentControlSet\Control\NetTrace\Scenarios` (the keys `netsh trace show scenarios` lists) |
| `advfirewall firewall ...` | `service=` | `ServiceController.GetServices()` service names, alongside the help's `any` |
| `advfirewall firewall ...` | `program=` | file paths via `Get-NetshFilePathCompletions` |
| `trace ...` | `traceFile=` | file paths via `Get-NetshFilePathCompletions` |

- The two `netsh` listings run through the same bounded spawn as the help pages (`Invoke-NetshProcess`: stdin closed, asynchronous reads, 5 s timeout, ANSI strip). The listings are cached for 60 s, including an empty answer when `netsh` or the WLAN service is missing.
- Values keep the typed tag casing and the typed quote character (a typographic quote counts as its ASCII kind). With no quote typed, a value with whitespace, any of `{ } ( ) ; , | & < > ' " $ @ #`, a backtick, or a typographic quote is single-quoted: `name='Ethernet 2'`, `name='vEthernet (Default Switch)'`, `program='C:\Tools\it''s.exe'`. Inside single quotes every single-quote character (ASCII and U+2018-U+201B) is doubled; inside double quotes `` ` ``, `"`, `$` and U+201C-U+201E are backtick-escaped. PowerShell removes the quotes, so `program='C:\a b\x.exe'` reaches netsh as the one argument `program=C:\a b\x.exe`.
- `scenario=` takes a comma list. In an unquoted list (`scenario=InternetClient,Net`) PowerShell replaces only the segment after the last comma. In a quoted list the earlier segments are kept as a prefix. Scenarios already in the list are not offered again.
- Any other unquoted tag value keeps a comma as part of the value (`name=Ethernet,`). PowerShell still replaces only the text after the comma, so a live name matching the full value is offered as its remainder, an unmatched remainder is echoed back, and an empty remainder offers the command's tags. None of these cases fall through to the filesystem.
- `program=` and `traceFile=` complete paths once part of the path is typed. An empty value (or a lone quote) returns the bare tag, so the current directory is not listed.
- Firewall rule names (`show|set|delete rule name=`) are not completed: `Get-NetFirewallRule` takes seconds on a typical machine.

## Global option handling
The completer includes special handling for root options:
- `-a`: file path completion
- `-f`: file path completion
- `-c`: context name and context-path completion
- `-p`: suggests `*` as the password-prompt form
- `-r` and `-u`: recognized as value-taking options so command parsing stays aligned

For `-a` and `-f`, `Get-NetshFilePathCompletions` lists paths with `CompletionCompleters.CompleteFilename`. Its results are quoted and wildcard-escaped for PowerShell `-Path` parameters (``'br`[1`].txt'``, ```'tick``x.txt'```), so each one is unwrapped by the parser and `WildcardPattern.Unescape` to the literal path, then quoted once by `ConvertTo-NetshArgumentText` in the style the user typed, with the same rules as tag values: `netsh -f C:\Scripts\amp<TAB>` gives `'C:\Scripts\amp&sand.txt'`, never a bare `&` that would end the statement or a bare `$x` that would expand.

An unquoted comma makes the typed word an array, and PowerShell then replaces only the text after the last comma, so no path can be inserted there as one argument. The completer offers no path: `netsh -f comma,x<TAB>` echoes `x` back (with a tooltip to quote the path) so PowerShell's own filename completion does not add a second array item. After a trailing comma (`netsh -f comma,<TAB>`) nothing can be echoed (PowerShell rejects an empty completion text), so PowerShell's own filename completion runs. Quote the path instead: `netsh -f 'comma,<TAB>` gives `'.\comma,x.pdf'`.

For `-c`, discovered context paths are cached from parsed help pages. Single-token contexts are suggested directly, while multi-token context paths are suggested in double quotes, or in the quote the user opened (`-c 'interface ip<TAB>` gives `'interface ipv4'`). A quoted `-c` value is read back with the same decoding, so `netsh -c 'interface ipv4' show <TAB>` resolves the context.

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

# Live tag values
# netsh interface ipv4 set address name=<TAB>
# netsh wlan show profiles name=<TAB>
# netsh trace start scenario=InternetClient,<TAB>
# netsh advfirewall firewall add rule program=C:\Prog<TAB>

# Global option values
# netsh -c <TAB>
# netsh -f <TAB>
```

## Dependencies or external command expectations
- Requires `netsh.exe`
- Relies on the local formatting of `netsh /?` and nested `netsh <path> /?` output
- Uses `CompletionCompleters.CompleteFilename` for file path completion

Because the catalog is derived from built-in help, the exact command surface depends on the Windows version and installed networking features on the local machine.

## Limitations / notes
- The parser is intentionally format-driven, so changes in `netsh` help text could affect discovery.
- The script focuses first on command and subcommand coverage. Value completion is intentionally lightweight and best for literal keywords and enum-like `tag=value` forms.
- Free-form values such as IP addresses, SDDL strings and firewall rule names are not completed. Values in the positional form (`[name=]<string>` written without the tag) are not completed either.
- Context discovery is lazy. For `-c`, the context levels already typed in a quoted value are loaded first (`-c "interface ip<TAB>` loads `interface`), but a deeper path is not offered until its parent help page has been loaded in the current session.
